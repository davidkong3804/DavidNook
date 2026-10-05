import XCTest
@testable import DavidNookCore

/// 元件 4：ClipboardStore（去重、上限、保留期、釘選、搜尋、清除）。
final class ClipboardStoreTests: XCTestCase {
    // MARK: 輔助

    private func makeStore(
        maxItems: Int = 100,
        retention: TimeInterval? = nil,
        logger: ClipboardLogging = NoOpClipboardLogger()
    ) -> (store: ClipboardStore, persistence: InMemoryClipboardPersistence) {
        let persistence = InMemoryClipboardPersistence()
        return (ClipboardStore(persistence: persistence, maxItems: maxItems, retention: retention, logger: logger), persistence)
    }

    private func cap(_ text: String, source: String? = nil) -> ClipboardCapture {
        ClipboardCapture(text: text, sourceAppBundleID: source)
    }

    private func imageCap(_ seed: String, ext: String = "png", source: String? = nil) -> ClipboardCapture {
        ClipboardCapture(imageData: utf8(seed), fileExtension: ext, sourceAppBundleID: source)
    }

    private func texts(_ store: ClipboardStore) async -> [String] {
        await store.items.compactMap(\.text)
    }

    private func insertedItem(_ result: ClipboardAddResult, file: StaticString = #filePath, line: UInt = #line) -> ClipboardItem? {
        guard case .inserted(let item) = result else {
            XCTFail("預期 .inserted，實得 \(result)", file: file, line: line)
            return nil
        }
        return item
    }

    private func bumpedItem(_ result: ClipboardAddResult, file: StaticString = #filePath, line: UInt = #line) -> ClipboardItem? {
        guard case .bumped(let item) = result else {
            XCTFail("預期 .bumped，實得 \(result)", file: file, line: line)
            return nil
        }
        return item
    }

    private struct UnexpectedAddResult: Error {}

    /// 新增並要求結果為 .inserted（await 不能放進 XCTUnwrap 的 autoclosure，所以獨立成輔助函式）。
    private func addInserted(_ store: ClipboardStore, _ capture: ClipboardCapture, _ now: Date,
                             file: StaticString = #filePath, line: UInt = #line) async throws -> ClipboardItem {
        let result = await store.add(capture, now: now)
        guard let item = insertedItem(result, file: file, line: line) else { throw UnexpectedAddResult() }
        return item
    }

    /// 新增並要求結果為 .bumped。
    private func addBumped(_ store: ClipboardStore, _ capture: ClipboardCapture, _ now: Date,
                           file: StaticString = #filePath, line: UInt = #line) async throws -> ClipboardItem {
        let result = await store.add(capture, now: now)
        guard let item = bumpedItem(result, file: file, line: line) else { throw UnexpectedAddResult() }
        return item
    }

    // MARK: 新增與去重

    func testAddInsertsNewestFirstAndReportsInserted() async {
        let (store, _) = makeStore()
        let r1 = await store.add(cap("a"), now: t(1))
        _ = await store.add(cap("b"), now: t(2))
        XCTAssertEqual(insertedItem(r1)?.createdAt, t(1))
        let order = await texts(store)
        XCTAssertEqual(order, ["b", "a"])
    }

    func testDuplicateContentDoesNotCreateSecondItemAndBumpsToFront() async throws {
        let (store, _) = makeStore()
        let original = try await addInserted(store, cap("a"), t(1))
        _ = await store.add(cap("b"), now: t(2))
        let bumped = try await addBumped(store, cap("a"), t(3))
        XCTAssertEqual(bumped.id, original.id, "沿用同一筆條目")
        XCTAssertEqual(bumped.lastUsedAt, t(3))
        XCTAssertEqual(bumped.createdAt, t(1), "createdAt 不變")
        let items = await store.items
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.first?.id, original.id)
        XCTAssertEqual(items.compactMap(\.text), ["a", "b"])
    }

    func testDuplicatePreservesPinnedState() async throws {
        let (store, _) = makeStore()
        let item = try await addInserted(store, cap("keep"), t(1))
        _ = await store.togglePin(id: item.id)
        let bumped = try await addBumped(store, cap("keep"), t(2))
        XCTAssertTrue(bumped.isPinned)
        let pinnedAfter = await store.item(id: item.id)?.isPinned
        XCTAssertEqual(pinnedAfter, true)
    }

    func testRapidRepeatedCopiesOfTheSameContentCollapseToOneItem() async {
        let (store, _) = makeStore()
        for i in 0..<50 {
            _ = await store.add(cap("same"), now: t(Double(i) * 0.01))
        }
        let items = await store.items
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.lastUsedAt, t(0.49))
    }

    func testSameContentOfDifferentKindsAreDistinctItems() async {
        let (store, _) = makeStore()
        _ = await store.add(ClipboardCapture(text: "/Users/me/a.txt"), now: t(1))
        _ = await store.add(ClipboardCapture(filePaths: ["/Users/me/a.txt"]), now: t(2))
        _ = await store.add(ClipboardCapture(imageData: utf8("/Users/me/a.txt")), now: t(3))
        let kinds = await store.items.map(\.kind)
        XCTAssertEqual(kinds, [.image, .files, .text])
    }

    func testDuplicateUpdatesSourceAppOnlyWhenNewOneIsKnown() async throws {
        let (store, _) = makeStore()
        let item = try await addInserted(store, cap("x", source: "com.a"), t(1))
        _ = await store.add(cap("x", source: nil), now: t(2))
        var current = await store.item(id: item.id)
        XCTAssertEqual(current?.sourceAppBundleID, "com.a")
        _ = await store.add(cap("x", source: "com.b"), now: t(3))
        current = await store.item(id: item.id)
        XCTAssertEqual(current?.sourceAppBundleID, "com.b")
    }

    // MARK: 上限與釘選

    func testMaxItemsEvictsOldestUnpinned() async {
        let (store, _) = makeStore(maxItems: 3)
        for (i, s) in ["1", "2", "3", "4", "5"].enumerated() {
            _ = await store.add(cap(s), now: t(Double(i)))
        }
        let order = await texts(store)
        XCTAssertEqual(order, ["5", "4", "3"])
    }

    func testPinnedItemIsNeverEvictedByMaxItems() async throws {
        let (store, _) = makeStore(maxItems: 2)
        let oldest = try await addInserted(store, cap("A"), t(1))
        _ = await store.togglePin(id: oldest.id)
        for (i, s) in ["B", "C", "D"].enumerated() {
            _ = await store.add(cap(s), now: t(Double(10 + i)))
        }
        let order = await texts(store)
        XCTAssertEqual(order, ["A", "D", "C"], "釘選的 A 留下且排最前；未釘選只留最新 2 筆")
    }

    func testNewItemSurvivesEvenWhenEveryOtherItemIsPinned() async throws {
        let (store, _) = makeStore(maxItems: 1)
        let a = try await addInserted(store, cap("A"), t(1))
        _ = await store.togglePin(id: a.id)
        _ = await store.add(cap("B"), now: t(2))
        var order = await texts(store)
        XCTAssertEqual(order, ["A", "B"], "釘選項目不佔用上限額度，新項目不會一進來就被淘汰")
        _ = await store.add(cap("C"), now: t(3))
        order = await texts(store)
        XCTAssertEqual(order, ["A", "C"])
    }

    func testUnpinningAnOldItemBeyondTheLimitEvictsItSoTheLimitAlwaysHolds() async throws {
        let (store, _) = makeStore(maxItems: 1)
        let old = try await addInserted(store, cap("old"), t(1))
        _ = await store.togglePin(id: old.id)
        _ = await store.add(cap("new"), now: t(2))
        let unpinned = await store.togglePin(id: old.id)
        XCTAssertEqual(unpinned, false)
        let order = await texts(store)
        XCTAssertEqual(order, ["new"], "取消釘選後未釘選筆數超出上限，最舊的未釘選項目被淘汰")
    }

    func testEvictionDeletesTheEvictedImageFile() async {
        let (store, persistence) = makeStore(maxItems: 1)
        _ = await store.add(imageCap("img-1"), now: t(1))
        let firstFile = persistence.imageFileNames()
        XCTAssertEqual(firstFile.count, 1)
        _ = await store.add(imageCap("img-2"), now: t(2))
        let files = persistence.imageFileNames()
        XCTAssertEqual(files.count, 1)
        XCTAssertNotEqual(files, firstFile, "被淘汰那筆的圖片檔必須一併刪除")
    }

    func testSetMaxItemsShrinksImmediatelyAndClampsToAtLeastOne() async {
        let (store, _) = makeStore(maxItems: 10)
        for (i, s) in ["1", "2", "3", "4", "5"].enumerated() {
            _ = await store.add(cap(s), now: t(Double(i)))
        }
        await store.setMaxItems(2)
        let order = await texts(store)
        XCTAssertEqual(order, ["5", "4"])
        await store.setMaxItems(0)
        let clamped = await store.maxItems
        XCTAssertEqual(clamped, 1)
        let (zero, _) = makeStore(maxItems: -5)
        let zeroMax = await zero.maxItems
        XCTAssertEqual(zeroMax, 1)
    }

    // MARK: 保留期

    func testPruneRemovesExpiredUnpinnedItemsOnlyAndReturnsCount() async {
        let (store, _) = makeStore(retention: 100)
        _ = await store.add(cap("old"), now: t(0))
        _ = await store.add(cap("mid"), now: t(60))
        _ = await store.add(cap("new"), now: t(150))
        let removed = await store.prune(now: t(170))
        XCTAssertEqual(removed, 2, "old 年齡 170、mid 年齡 110，皆 > 100")
        let order = await texts(store)
        XCTAssertEqual(order, ["new"])
    }

    func testPruneKeepsPinnedItemsEvenWhenExpired() async throws {
        let (store, _) = makeStore(retention: 10)
        let pinned = try await addInserted(store, cap("pinned"), t(0))
        _ = await store.add(cap("plain"), now: t(1))
        _ = await store.togglePin(id: pinned.id)
        _ = await store.prune(now: t(10_000))
        let order = await texts(store)
        XCTAssertEqual(order, ["pinned"])
    }

    func testPruneWithNilRetentionKeepsEverything() async {
        let (store, _) = makeStore(retention: nil)
        _ = await store.add(cap("ancient"), now: t(0))
        let removed = await store.prune(now: t(10_000_000))
        XCTAssertEqual(removed, 0)
        let count = await store.items.count
        XCTAssertEqual(count, 1)
    }

    func testPruneBoundaryAgeEqualToRetentionIsKept() async {
        let (store, _) = makeStore(retention: 100)
        _ = await store.add(cap("edge"), now: t(0))
        var removed = await store.prune(now: t(100))
        XCTAssertEqual(removed, 0, "年齡剛好等於保留期 → 保留")
        removed = await store.prune(now: t(100.5))
        XCTAssertEqual(removed, 1)
    }

    func testRecopyingRefreshesRetentionClock() async {
        let (store, _) = makeStore(retention: 100)
        _ = await store.add(cap("again"), now: t(0))
        _ = await store.add(cap("again"), now: t(90))
        let removed = await store.prune(now: t(150))
        XCTAssertEqual(removed, 0, "以 lastUsedAt 計算；重新複製等於重新計時")
    }

    func testPruneDeletesImageFilesOfExpiredItems() async {
        let (store, persistence) = makeStore(retention: 10)
        _ = await store.add(imageCap("img"), now: t(0))
        _ = await store.prune(now: t(100))
        XCTAssertEqual(persistence.imageFileNames(), [])
    }

    func testSetRetentionAppliesOnNextPrune() async {
        let (store, _) = makeStore(retention: nil)
        _ = await store.add(cap("x"), now: t(0))
        await store.setRetention(50)
        let retention = await store.retention
        XCTAssertEqual(retention, 50)
        let removed = await store.prune(now: t(100))
        XCTAssertEqual(removed, 1)
    }

    // MARK: 暫停

    func testPauseIgnoresNewItemsAndResumeRestoresRecording() async {
        let (store, _) = makeStore()
        await store.pause()
        let paused = await store.isPaused
        XCTAssertTrue(paused)
        let ignored = await store.add(cap("while paused"), now: t(1))
        XCTAssertEqual(ignored, .ignored)
        var count = await store.items.count
        XCTAssertEqual(count, 0)
        await store.resume()
        let resumedFlag = await store.isPaused
        XCTAssertFalse(resumedFlag)
        _ = await store.add(cap("after resume"), now: t(2))
        count = await store.items.count
        XCTAssertEqual(count, 1)
    }

    func testPauseDoesNotAffectExistingItemsOrOtherOperations() async throws {
        let (store, _) = makeStore()
        let item = try await addInserted(store, cap("existing"), t(1))
        await store.pause()
        let pinState = await store.togglePin(id: item.id)
        XCTAssertEqual(pinState, true)
        let found = await store.search(query: "exist")
        XCTAssertEqual(found.count, 1)
    }

    // MARK: 搜尋

    func testSearchEmptyOrWhitespaceQueryReturnsAllPinnedFirstThenNewestFirst() async throws {
        let (store, _) = makeStore()
        let a = try await addInserted(store, cap("a"), t(1))
        _ = await store.add(cap("b"), now: t(2))
        _ = await store.add(cap("c"), now: t(3))
        _ = await store.togglePin(id: a.id)
        for query in ["", "   ", "\n"] {
            let result = await store.search(query: query).compactMap(\.text)
            XCTAssertEqual(result, ["a", "c", "b"], "query = 「\(query)」")
        }
    }

    func testSearchTextIsCaseInsensitiveAndSupportsChinese() async {
        let (store, _) = makeStore()
        _ = await store.add(cap("Hello World"), now: t(1))
        _ = await store.add(cap("繁體中文測試"), now: t(2))
        _ = await store.add(cap("unrelated"), now: t(3))
        let hello = await store.search(query: "hELLo").compactMap(\.text)
        XCTAssertEqual(hello, ["Hello World"])
        let chinese = await store.search(query: "體中").compactMap(\.text)
        XCTAssertEqual(chinese, ["繁體中文測試"])
        let none = await store.search(query: "zzz")
        XCTAssertTrue(none.isEmpty)
    }

    func testSearchMatchesFilePathFragments() async {
        let (store, _) = makeStore()
        _ = await store.add(ClipboardCapture(filePaths: ["/Users/me/Reports/Q3.xlsx", "/Users/me/notes.txt"]), now: t(1))
        _ = await store.add(cap("not a file"), now: t(2))
        let byFolder = await store.search(query: "reports")
        XCTAssertEqual(byFolder.map(\.kind), [.files])
        let byFileName = await store.search(query: "NOTES.TXT")
        XCTAssertEqual(byFileName.map(\.kind), [.files])
        let miss = await store.search(query: "nonexistent-dir")
        XCTAssertTrue(miss.isEmpty)
    }

    func testSearchImagesMatchOnlyBySourceAppAndNeverWithoutOne() async {
        let (store, _) = makeStore()
        _ = await store.add(imageCap("with-source", source: "com.apple.Preview"), now: t(1))
        _ = await store.add(imageCap("no-source"), now: t(2))
        _ = await store.add(cap("hello", source: "com.apple.Safari"), now: t(3))
        let preview = await store.search(query: "preview")
        XCTAssertEqual(preview.map(\.kind), [.image])
        XCTAssertEqual(preview.first?.sourceAppBundleID, "com.apple.Preview")
        let safariOnText = await store.search(query: "safari")
        XCTAssertTrue(safariOnText.isEmpty, "文字條目不以來源 App 命中")
        let imageNoSource = await store.search(query: "png")
        XCTAssertTrue(imageNoSource.isEmpty, "沒有來源 App 的圖片不會被任何查詢命中")
    }

    func testSearchResultsKeepPinnedFirstThenLastUsedDescending() async throws {
        let (store, _) = makeStore()
        let a = try await addInserted(store, cap("note a"), t(1))
        _ = await store.add(cap("note b"), now: t(2))
        let c = try await addInserted(store, cap("note c"), t(3))
        _ = await store.add(cap("note d"), now: t(4))
        _ = await store.togglePin(id: a.id)
        _ = await store.togglePin(id: c.id)
        let result = await store.search(query: "note").compactMap(\.text)
        XCTAssertEqual(result, ["note c", "note a", "note d", "note b"])
    }

    // MARK: 釘選 / 移除 / bump

    func testTogglePinFlipsStateReturnsNewValueAndLeavesLastUsedAlone() async throws {
        let (store, _) = makeStore()
        let item = try await addInserted(store, cap("x"), t(1))
        let on = await store.togglePin(id: item.id)
        XCTAssertEqual(on, true)
        let off = await store.togglePin(id: item.id)
        XCTAssertEqual(off, false)
        let unknown = await store.togglePin(id: UUID())
        XCTAssertNil(unknown)
        let current = await store.item(id: item.id)
        XCTAssertEqual(current?.lastUsedAt, t(1))
    }

    func testRemoveByIDRemovesItemAndItsImageFile() async throws {
        let (store, persistence) = makeStore()
        let text = try await addInserted(store, cap("t"), t(1))
        let image = try await addInserted(store, imageCap("img"), t(2))
        XCTAssertEqual(persistence.imageFileNames().count, 1)
        let removedImage = await store.remove(id: image.id)
        XCTAssertTrue(removedImage)
        XCTAssertEqual(persistence.imageFileNames(), [])
        let removedUnknown = await store.remove(id: UUID())
        XCTAssertFalse(removedUnknown)
        let removedText = await store.remove(id: text.id)
        XCTAssertTrue(removedText)
        let count = await store.items.count
        XCTAssertEqual(count, 0)
    }

    func testBumpMovesItemToFrontAndUpdatesLastUsed() async throws {
        let (store, _) = makeStore()
        let a = try await addInserted(store, cap("a"), t(1))
        _ = await store.add(cap("b"), now: t(2))
        let ok = await store.bump(id: a.id, now: t(5))
        XCTAssertTrue(ok)
        let order = await texts(store)
        XCTAssertEqual(order, ["a", "b"])
        let used = await store.item(id: a.id)?.lastUsedAt
        XCTAssertEqual(used, t(5))
        let unknown = await store.bump(id: UUID(), now: t(6))
        XCTAssertFalse(unknown)
    }

    // MARK: 圖片檔

    func testDuplicateImageReusesTheSingleFileAndRewritesItIfMissing() async throws {
        let (store, persistence) = makeStore()
        let first = try await addInserted(store, imageCap("same-image"), t(1))
        let second = await store.add(imageCap("same-image"), now: t(2))
        XCTAssertEqual(bumpedItem(second)?.id, first.id)
        XCTAssertEqual(persistence.imageFileNames().count, 1)

        let fileName = try XCTUnwrap(first.imageFileName)
        try persistence.deleteImage(fileName: fileName)
        _ = await store.add(imageCap("same-image"), now: t(3))
        XCTAssertTrue(persistence.imageExists(fileName: fileName), "檔案遺失時，重複複製會把圖片檔補回")
    }

    func testImageDataIsReadableThroughStore() async throws {
        let (store, _) = makeStore()
        let item = try await addInserted(store, ClipboardCapture(imageData: tinyPNG), t(1))
        let data = await store.imageData(for: item)
        XCTAssertEqual(data, tinyPNG)
        let textItem = try await addInserted(store, cap("t"), t(2))
        let none = await store.imageData(for: textItem)
        XCTAssertNil(none)
    }

    func testImageSaveFailureIsIgnoredNotInsertedAndLoggedByOperationOnly() async {
        let persistence = FailingImagePersistence()
        let spy = SpyClipboardLogger()
        let store = ClipboardStore(persistence: persistence, logger: spy)
        let result = await store.add(imageCap("img"), now: t(1))
        XCTAssertEqual(result, .ignored)
        let count = await store.items.count
        XCTAssertEqual(count, 0)
        XCTAssertTrue(spy.events.contains(.persistenceFailed(operation: .saveImage)))
    }

    // MARK: 清除

    func testClearAllRemovesEverythingIncludingPinnedAndAllImageFiles() async throws {
        let (store, persistence) = makeStore()
        _ = await store.add(cap("text"), now: t(1))
        _ = await store.add(imageCap("img-1"), now: t(2))
        let pinnedImage = try await addInserted(store, imageCap("img-2"), t(3))
        _ = await store.togglePin(id: pinnedImage.id)
        XCTAssertEqual(persistence.imageFileNames().count, 2)

        try await store.clearAll()

        let items = await store.items
        XCTAssertTrue(items.isEmpty, "「清除全部」就是全部，釘選也要刪")
        XCTAssertEqual(persistence.imageFileNames(), [], "磁碟上不得殘留任何圖片檔")
        XCTAssertTrue(persistence.loadItems().isEmpty)
    }

    func testClearUnpinnedKeepsPinnedItemsAndTheirImageFilesOnly() async throws {
        let (store, persistence) = makeStore()
        _ = await store.add(cap("plain"), now: t(1))
        _ = await store.add(imageCap("unpinned-img"), now: t(2))
        let pinnedImage = try await addInserted(store, imageCap("pinned-img"), t(3))
        _ = await store.togglePin(id: pinnedImage.id)

        await store.clearUnpinned()

        let items = await store.items
        XCTAssertEqual(items.map(\.id), [pinnedImage.id])
        XCTAssertEqual(persistence.imageFileNames(), [try XCTUnwrap(pinnedImage.imageFileName)])
        XCTAssertEqual(persistence.loadItems().map(\.id), [pinnedImage.id])
    }

    func testStoreIsUsableAfterClearAll() async throws {
        let (store, _) = makeStore()
        _ = await store.add(cap("a"), now: t(1))
        try await store.clearAll()
        _ = await store.add(cap("b"), now: t(2))
        let order = await texts(store)
        XCTAssertEqual(order, ["b"])
    }

    // MARK: 持久化整合

    func testEveryMutationIsPersistedImmediately() async throws {
        let (store, persistence) = makeStore()
        func assertPersistedMatchesMemory(_ label: String, file: StaticString = #filePath, line: UInt = #line) async {
            let memory = Dictionary(uniqueKeysWithValues: await store.items.map { ($0.id, $0) })
            let disk = Dictionary(uniqueKeysWithValues: persistence.loadItems().map { ($0.id, $0) })
            XCTAssertEqual(memory, disk, label, file: file, line: line)
        }
        let a = try await addInserted(store, cap("a"), t(1))
        await assertPersistedMatchesMemory("add")
        _ = await store.add(cap("a"), now: t(2))
        await assertPersistedMatchesMemory("dedup bump")
        _ = await store.togglePin(id: a.id)
        await assertPersistedMatchesMemory("pin")
        _ = await store.add(cap("b"), now: t(3))
        _ = await store.remove(id: a.id)
        await assertPersistedMatchesMemory("remove")
        _ = await store.prune(now: t(9))
        await assertPersistedMatchesMemory("prune")
    }

    func testNewStoreOnSamePersistenceRestoresItemsInTheSameOrder() async throws {
        let persistence = InMemoryClipboardPersistence()
        let first = ClipboardStore(persistence: persistence)
        let a = try await addInserted(first, ClipboardCapture(text: "a"), t(1))
        _ = await first.add(ClipboardCapture(text: "b"), now: t(2))
        _ = await first.add(ClipboardCapture(imageData: tinyPNG), now: t(3))
        _ = await first.togglePin(id: a.id)

        let second = ClipboardStore(persistence: persistence)
        let before = await first.items
        let after = await second.items
        XCTAssertEqual(after, before)
    }

    func testStartupRemovesOrphanImageFilesAndMergesDuplicateIndexEntries() async throws {
        let persistence = InMemoryClipboardPersistence()
        try persistence.saveImage(utf8("leftover"), fileName: "orphan.png")
        let older = ClipboardItem(text: "dup", now: t(1))
        let newer = ClipboardItem(text: "dup", now: t(2))
        try persistence.saveItems([older, newer])

        let store = ClipboardStore(persistence: persistence)

        XCTAssertEqual(persistence.imageFileNames(), [], "沒有任何條目參照的圖片檔屬於殘留，啟動時清掉")
        let items = await store.items
        XCTAssertEqual(items.map(\.id), [newer.id], "索引內重複內容只留最近使用的一筆")
    }
}
