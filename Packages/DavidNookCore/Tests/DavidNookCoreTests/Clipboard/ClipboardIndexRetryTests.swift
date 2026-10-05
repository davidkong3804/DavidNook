import XCTest
@testable import DavidNookCore

/// F3(b)：索引寫入失敗（磁碟滿、唯讀）時，記憶體已刪的文字條目不能在重啟後復活。
/// store 在失敗時標記 dirty，下一次異動或 prune tick 重試；連續失敗時報告一次，恢復後再報告一次。
final class ClipboardIndexRetryTests: XCTestCase {
    private func makeStore(
        _ persistence: FlakyIndexPersistence,
        logger: ClipboardLogging = NoOpClipboardLogger()
    ) -> ClipboardStore {
        ClipboardStore(persistence: persistence, maxItems: 50, retention: nil, logger: logger)
    }

    private func persistedTexts(_ persistence: FlakyIndexPersistence) -> Set<String> {
        Set(persistence.persistedItems.compactMap(\.text))
    }

    // MARK: dirty 與重試

    func testSuccessfulWritesLeaveNothingDirty() async {
        let persistence = FlakyIndexPersistence()
        let store = makeStore(persistence)
        _ = await store.add(ClipboardCapture(text: "a"), now: t(1))
        let dirty = await store.hasUnsavedChanges
        XCTAssertFalse(dirty)
    }

    func testRemoveWhoseIndexWriteFailsIsMarkedDirtyAndRetriedByTheNextPruneTick() async throws {
        let persistence = FlakyIndexPersistence()
        let store = makeStore(persistence)
        _ = await store.add(ClipboardCapture(text: "keep"), now: t(1))
        let doomed = await store.add(ClipboardCapture(text: "delete me"), now: t(2))
        guard case .inserted(let item) = doomed else { return XCTFail("預期 inserted") }

        persistence.failSaveItems = true
        let removed = await store.remove(id: item.id)
        XCTAssertTrue(removed)
        var dirty = await store.hasUnsavedChanges
        XCTAssertTrue(dirty, "索引寫入失敗必須標記 dirty")
        XCTAssertEqual(persistedTexts(persistence), ["keep", "delete me"], "磁碟上還是舊的——此刻重啟條目會復活")

        persistence.failSaveItems = false
        _ = await store.prune(now: t(3))      // prune tick 重試
        dirty = await store.hasUnsavedChanges
        XCTAssertFalse(dirty)
        XCTAssertEqual(persistedTexts(persistence), ["keep"], "重試成功後，被刪的條目不會再復活")
    }

    func testClearUnpinnedWhoseIndexWriteFailsIsRetriedByTheNextPruneTick() async {
        let persistence = FlakyIndexPersistence()
        let store = makeStore(persistence)
        _ = await store.add(ClipboardCapture(text: "one"), now: t(1))
        _ = await store.add(ClipboardCapture(text: "two"), now: t(2))

        persistence.failSaveItems = true
        await store.clearUnpinned()
        var dirty = await store.hasUnsavedChanges
        XCTAssertTrue(dirty)
        XCTAssertEqual(persistedTexts(persistence), ["one", "two"])

        persistence.failSaveItems = false
        _ = await store.prune(now: t(3))
        dirty = await store.hasUnsavedChanges
        XCTAssertFalse(dirty)
        XCTAssertEqual(persistedTexts(persistence), [])
    }

    func testAnyLaterMutationAlsoRetriesTheFailedWrite() async {
        let persistence = FlakyIndexPersistence()
        let store = makeStore(persistence)
        _ = await store.add(ClipboardCapture(text: "old"), now: t(1))
        let first = await store.items.first
        persistence.failSaveItems = true
        _ = await store.remove(id: first?.id ?? UUID())
        persistence.failSaveItems = false

        _ = await store.add(ClipboardCapture(text: "fresh"), now: t(2))
        let dirty = await store.hasUnsavedChanges
        XCTAssertFalse(dirty)
        XCTAssertEqual(persistedTexts(persistence), ["fresh"], "下一次異動寫入的是完整的最新狀態，被刪的 old 不會復活")
    }

    func testFlushIfNeededRetriesADirtyWriteAndIsANoOpWhenClean() async {
        let persistence = FlakyIndexPersistence()
        let store = makeStore(persistence)
        _ = await store.add(ClipboardCapture(text: "gone soon"), now: t(1))
        let attemptsAfterAdd = persistence.saveAttempts
        await store.flushIfNeeded()
        XCTAssertEqual(persistence.saveAttempts, attemptsAfterAdd, "沒有待寫的變動就不寫")

        persistence.failSaveItems = true
        await store.clearUnpinned()
        persistence.failSaveItems = false
        await store.flushIfNeeded()
        let dirty = await store.hasUnsavedChanges
        XCTAssertFalse(dirty)
        XCTAssertEqual(persistedTexts(persistence), [])
    }

    func testPruneRetriesEvenWhenRetentionIsForever() async {
        let persistence = FlakyIndexPersistence()
        let store = makeStore(persistence)
        _ = await store.add(ClipboardCapture(text: "x"), now: t(1))
        persistence.failSaveItems = true
        await store.clearUnpinned()
        persistence.failSaveItems = false
        let pruned = await store.prune(now: t(2))   // retention == nil
        XCTAssertEqual(pruned, 0)
        XCTAssertEqual(persistedTexts(persistence), [])
    }

    func testFailedClearAllLeavesTheStoreDirtySoTheNextTickRewritesAnEmptyIndex() async {
        let persistence = FlakyIndexPersistence()
        let store = makeStore(persistence)
        _ = await store.add(ClipboardCapture(text: "secret-ish"), now: t(1))
        persistence.failDeleteAll = true
        do {
            try await store.clearAll()
            XCTFail("deleteAll 失敗時 clearAll 應該拋錯")
        } catch {}
        var dirty = await store.hasUnsavedChanges
        XCTAssertTrue(dirty)
        persistence.failDeleteAll = false
        _ = await store.prune(now: t(2))
        dirty = await store.hasUnsavedChanges
        XCTAssertFalse(dirty)
        XCTAssertEqual(persistedTexts(persistence), [], "磁碟刪除失敗後，下一次 tick 至少把索引重寫成空的")
    }

    // MARK: 連續失敗的報告

    func testSingleFailureIsNotReportedButTwoConsecutiveFailuresAreReportedExactlyOnce() async {
        let persistence = FlakyIndexPersistence()
        let spy = SpyClipboardLogger()
        let store = makeStore(persistence, logger: spy)
        persistence.failSaveItems = true

        _ = await store.add(ClipboardCapture(text: "a"), now: t(1))
        XCTAssertFalse(spy.events.contains(.indexWriteFailing), "單次失敗可能只是暫時的，不打擾使用者")

        _ = await store.add(ClipboardCapture(text: "b"), now: t(2))
        XCTAssertEqual(spy.events.filter { $0 == .indexWriteFailing }.count, 1, "連續失敗：報告一次")

        _ = await store.add(ClipboardCapture(text: "c"), now: t(3))
        _ = await store.prune(now: t(4))
        XCTAssertEqual(spy.events.filter { $0 == .indexWriteFailing }.count, 1, "同一段失敗期間不重複報告")
        XCTAssertFalse(spy.events.contains(.indexWriteRecovered))
    }

    func testRecoveryIsReportedOnceAndANewFailureEpisodeIsReportedAgain() async {
        let persistence = FlakyIndexPersistence()
        let spy = SpyClipboardLogger()
        let store = makeStore(persistence, logger: spy)
        persistence.failSaveItems = true
        _ = await store.add(ClipboardCapture(text: "a"), now: t(1))
        _ = await store.add(ClipboardCapture(text: "b"), now: t(2))

        persistence.failSaveItems = false
        _ = await store.prune(now: t(3))
        XCTAssertEqual(spy.events.filter { $0 == .indexWriteRecovered }.count, 1)

        persistence.failSaveItems = true
        _ = await store.add(ClipboardCapture(text: "c"), now: t(4))
        _ = await store.add(ClipboardCapture(text: "d"), now: t(5))
        XCTAssertEqual(spy.events.filter { $0 == .indexWriteFailing }.count, 2, "新的失敗期間要再報告一次")
    }

    func testFailureReportsNeverCarryContent() async {
        let persistence = FlakyIndexPersistence()
        let spy = SpyClipboardLogger()
        let store = makeStore(persistence, logger: spy)
        persistence.failSaveItems = true
        _ = await store.add(ClipboardCapture(text: "TOPSECRET-F3"), now: t(1))
        _ = await store.add(ClipboardCapture(filePaths: ["/Users/secret-user/F3.txt"]), now: t(2))
        _ = await store.prune(now: t(3))
        XCTAssertTrue(spy.events.contains(.indexWriteFailing))
        spy.assertNoneContain(["TOPSECRET-F3", "secret-user", "F3.txt", "Failure"])
    }
}
