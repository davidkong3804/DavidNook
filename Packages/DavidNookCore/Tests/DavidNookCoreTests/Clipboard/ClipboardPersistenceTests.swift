import XCTest
@testable import DavidNookCore

/// 元件 5：持久化（記憶體版與檔案版）。
final class FileClipboardPersistenceTests: XCTestCase {
    private func makePersistence(
        logger: ClipboardLogging = NoOpClipboardLogger()
    ) throws -> (persistence: FileClipboardPersistence, directory: URL) {
        let root = try makeTempDirectory(for: self)
        let directory = root.appendingPathComponent("Application Support/DavidNook/Clipboard", isDirectory: true)
        return (try FileClipboardPersistence(directory: directory, logger: logger), directory)
    }

    private func indexURL(_ directory: URL) -> URL {
        directory.appendingPathComponent(FileClipboardPersistence.indexFileName)
    }

    // MARK: 權限與目錄

    func testInitCreatesNestedDirectoryWithMode0700() throws {
        let (_, directory) = try makePersistence()
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
        XCTAssertEqual(try posixPermissions(of: directory), 0o700)
    }

    func testInitTightensAnExistingLooseDirectoryTo0700() throws {
        let root = try makeTempDirectory(for: self)
        let directory = root.appendingPathComponent("Clipboard")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        _ = try FileClipboardPersistence(directory: directory)
        XCTAssertEqual(try posixPermissions(of: directory), 0o700)
    }

    // MARK: 排除備份（F1）

    func testNewDirectoryIsExcludedFromBackup() throws {
        let (_, directory) = try makePersistence()
        XCTAssertTrue(try isExcludedFromBackup(directory), "明文剪貼簿歷史不得進 Time Machine 備份")
    }

    func testExistingDirectoryThatWasNotExcludedGetsBackfilledOnInit() throws {
        let root = try makeTempDirectory(for: self)
        let directory = root.appendingPathComponent("Clipboard")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        XCTAssertFalse(try isExcludedFromBackup(directory), "前置條件：舊版建立的目錄尚未排除備份")
        _ = try FileClipboardPersistence(directory: directory)
        XCTAssertTrue(try isExcludedFromBackup(directory), "載入時發現目錄已存在，也要補設排除備份")
    }

    func testExclusionSurvivesSavesAndClearAll() throws {
        let (persistence, directory) = try makePersistence()
        try persistence.saveItems([ClipboardItem(text: "x")])
        try persistence.deleteAll()
        XCTAssertTrue(try isExcludedFromBackup(directory))
    }

    func testIndexAndImageFilesAreMode0600() throws {
        let (persistence, directory) = try makePersistence()
        let image = ClipboardItem(imageData: tinyPNG)
        try persistence.saveImage(tinyPNG, fileName: try XCTUnwrap(image.imageFileName))
        try persistence.saveItems([image])
        XCTAssertEqual(try posixPermissions(of: indexURL(directory)), 0o600)
        XCTAssertEqual(try posixPermissions(of: directory.appendingPathComponent(try XCTUnwrap(image.imageFileName))), 0o600)
    }

    // MARK: 往返

    func testRoundTripsItemsAndImageData() throws {
        let (persistence, _) = try makePersistence()
        let text = ClipboardItem(text: "你好", now: t(1), isPinned: true, sourceAppBundleID: "com.apple.Notes")
        let files = ClipboardItem(filePaths: ["/Users/a/b.txt"], now: t(2))
        let image = ClipboardItem(imageData: tinyPNG, now: t(3))
        let name = try XCTUnwrap(image.imageFileName)
        try persistence.saveImage(tinyPNG, fileName: name)
        try persistence.saveItems([image, files, text])

        XCTAssertEqual(persistence.loadItems(), [image, files, text])
        XCTAssertEqual(persistence.loadImage(fileName: name), tinyPNG)
        XCTAssertTrue(persistence.imageExists(fileName: name))
        XCTAssertEqual(persistence.imageFileNames(), [name])
    }

    func testMissingIndexLoadsEmptyWithoutCreatingCorruptBackup() throws {
        let (persistence, directory) = try makePersistence()
        XCTAssertEqual(persistence.loadItems(), [])
        XCTAssertEqual(directoryEntries(directory), [])
    }

    func testDeleteImageIsIdempotentAndSaveImageOverwrites() throws {
        let (persistence, _) = try makePersistence()
        let name = try XCTUnwrap(ClipboardItem(imageData: tinyPNG).imageFileName)
        XCTAssertNoThrow(try persistence.deleteImage(fileName: name), "刪除不存在的圖片檔不是錯誤")
        try persistence.saveImage(tinyPNG, fileName: name)
        try persistence.saveImage(tinyPNG, fileName: name)
        XCTAssertEqual(persistence.imageFileNames(), [name])
        try persistence.deleteImage(fileName: name)
        XCTAssertNil(persistence.loadImage(fileName: name))
    }

    // MARK: 原子寫入

    func testSaveLeavesNoTemporaryFilesBehind() throws {
        let (persistence, directory) = try makePersistence()
        let image = ClipboardItem(imageData: tinyPNG)
        let name = try XCTUnwrap(image.imageFileName)
        for round in 0..<5 {
            try persistence.saveImage(tinyPNG, fileName: name)
            try persistence.saveItems([image, ClipboardItem(text: "round \(round)")])
        }
        XCTAssertEqual(directoryEntries(directory), [name, FileClipboardPersistence.indexFileName].sorted())
    }

    func testFailedWriteKeepsThePreviousIndexIntact() throws {
        try XCTSkipIf(getuid() == 0, "root 不受目錄唯讀限制")
        let (persistence, directory) = try makePersistence()
        let original = ClipboardItem(text: "original", now: t(1))
        try persistence.saveItems([original])

        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        XCTAssertThrowsError(try persistence.saveItems([original, ClipboardItem(text: "never written")]))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        XCTAssertEqual(persistence.loadItems(), [original], "寫入失敗不得破壞既有索引")
        XCTAssertEqual(directoryEntries(directory), [FileClipboardPersistence.indexFileName], "失敗後也不留暫存檔")
    }

    // MARK: 損毀容忍

    func testCorruptIndexLoadsEmptyKeepsBackupAsCorruptAndStaysUsable() throws {
        let spy = SpyClipboardLogger()
        let (persistence, directory) = try makePersistence(logger: spy)
        let garbage = utf8("{ this is not json ]]")
        try garbage.write(to: indexURL(directory))

        XCTAssertEqual(persistence.loadItems(), [])

        let corrupt = directory.appendingPathComponent("index.json.corrupt")
        XCTAssertEqual(try Data(contentsOf: corrupt), garbage, "壞檔原樣保留以便人工檢查")
        XCTAssertEqual(try posixPermissions(of: corrupt), 0o600)
        XCTAssertFalse(FileManager.default.fileExists(atPath: indexURL(directory).path), "壞索引已被改名移走")
        XCTAssertTrue(spy.events.contains(.indexCorrupted))

        let fresh = ClipboardItem(text: "fresh start")
        try persistence.saveItems([fresh])
        XCTAssertEqual(persistence.loadItems(), [fresh])
    }

    func testEmptyFileAndWrongShapedJSONAreTreatedAsCorrupt() throws {
        for (label, bytes) in [("empty file", Data()), ("array root", utf8("[1,2,3]")), ("no items key", utf8("{\"version\":1}"))] {
            let (persistence, directory) = try makePersistence()
            try bytes.write(to: indexURL(directory))
            XCTAssertEqual(persistence.loadItems(), [], label)
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("index.json.corrupt").path), label)
        }
    }

    func testSecondCorruptionReplacesThePreviousCorruptBackupInsteadOfFailing() throws {
        let (persistence, directory) = try makePersistence()
        try utf8("bad-1").write(to: indexURL(directory))
        XCTAssertEqual(persistence.loadItems(), [])
        try utf8("bad-2").write(to: indexURL(directory))
        XCTAssertEqual(persistence.loadItems(), [])
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("index.json.corrupt")), utf8("bad-2"))
    }

    func testItemsWhoseImageFileIsMissingAreDroppedAndOthersKept() throws {
        let spy = SpyClipboardLogger()
        let (persistence, _) = try makePersistence(logger: spy)
        let text = ClipboardItem(text: "survivor", now: t(1))
        let image = ClipboardItem(imageData: tinyPNG, now: t(2))   // 圖片檔從未寫入
        try persistence.saveItems([image, text])
        XCTAssertEqual(persistence.loadItems(), [text])
        XCTAssertTrue(spy.events.contains(.itemsDropped(count: 1)))
    }

    func testIndividuallyInvalidItemsAreDroppedWithoutLosingTheRest() throws {
        let spy = SpyClipboardLogger()
        let (persistence, directory) = try makePersistence(logger: spy)
        let good = ClipboardItem(text: "good")
        try persistence.saveItems([good])

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: indexURL(directory))) as? [String: Any])
        var array = try XCTUnwrap(object["items"] as? [Any])
        array.append(["kind": "text"])      // 缺欄位
        array.append(42)                    // 型別錯誤
        object["items"] = array
        try JSONSerialization.data(withJSONObject: object).write(to: indexURL(directory))

        XCTAssertEqual(persistence.loadItems(), [good])
        XCTAssertTrue(spy.events.contains(.itemsDropped(count: 2)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("index.json.corrupt").path), "只是個別條目壞，不算整份索引損毀")
    }

    // MARK: 路徑穿越

    func testImageFileNamesThatEscapeTheDirectoryAreRejected() throws {
        let (persistence, directory) = try makePersistence()
        let outside = directory.deletingLastPathComponent().appendingPathComponent("escape.png")
        for bad in ["../escape.png", "/etc/passwd", "a/b.png", "..", "", "not-a-hash.png", String(repeating: "a", count: 64) + ".p/g"] {
            XCTAssertThrowsError(try persistence.saveImage(tinyPNG, fileName: bad), bad)
            XCTAssertNil(persistence.loadImage(fileName: bad), bad)
            XCTAssertFalse(persistence.imageExists(fileName: bad), bad)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.path))
    }

    func testIndexEntryPointingOutsideTheDirectoryIsDroppedNotRead() throws {
        let (persistence, directory) = try makePersistence()
        let secret = directory.deletingLastPathComponent().appendingPathComponent("outside.png")
        try tinyPNG.write(to: secret)
        let good = ClipboardItem(text: "good")
        try persistence.saveItems([good, ClipboardItem(imageData: tinyPNG)])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: indexURL(directory))) as? [String: Any])
        var array = try XCTUnwrap(object["items"] as? [[String: Any]])
        array[1]["imageFileName"] = "../outside.png"
        object["items"] = array
        try JSONSerialization.data(withJSONObject: object).write(to: indexURL(directory))

        XCTAssertEqual(persistence.loadItems(), [good])
    }

    // MARK: 清除

    func testDeleteAllRemovesIndexImagesBackupsAndTempFilesButNotForeignFiles() throws {
        let (persistence, directory) = try makePersistence()
        let image = ClipboardItem(imageData: tinyPNG)
        let tiff = ClipboardItem(imageData: utf8("tiff-bytes"), fileExtension: "tiff")
        try persistence.saveImage(tinyPNG, fileName: try XCTUnwrap(image.imageFileName))
        try persistence.saveImage(utf8("tiff-bytes"), fileName: try XCTUnwrap(tiff.imageFileName))
        try persistence.saveItems([image, tiff])
        try utf8("old corrupt").write(to: directory.appendingPathComponent("index.json.corrupt"))
        try utf8("tmp").write(to: directory.appendingPathComponent("index.json.tmp-123"))
        let foreign = directory.appendingPathComponent("user-notes.txt")
        try utf8("not ours").write(to: foreign)

        try persistence.deleteAll()

        XCTAssertEqual(directoryEntries(directory), ["user-notes.txt"], "只刪自己產生的檔案；圖片檔、索引、損毀備份、暫存檔全部消失")
        XCTAssertEqual(persistence.imageFileNames(), [])
        XCTAssertEqual(persistence.loadItems(), [])
    }

    // MARK: 與 Store 整合（真實磁碟）

    func testStoreClearAllLeavesNoImageFilesOnDisk() async throws {
        let (persistence, directory) = try makePersistence()
        let store = ClipboardStore(persistence: persistence)
        _ = await store.add(ClipboardCapture(imageData: tinyPNG, fileExtension: "png"), now: t(1))
        _ = await store.add(ClipboardCapture(imageData: utf8("tiff-1"), fileExtension: "tiff"), now: t(2))
        let pinned = await store.add(ClipboardCapture(imageData: utf8("png-2"), fileExtension: "png"), now: t(3))
        if case .inserted(let item) = pinned { _ = await store.togglePin(id: item.id) } else { XCTFail("預期 inserted") }
        _ = await store.add(ClipboardCapture(text: "secret text"), now: t(4))
        let imagesBefore = directoryEntries(directory).filter { $0.hasSuffix(".png") || $0.hasSuffix(".tiff") }
        XCTAssertEqual(imagesBefore.count, 3)

        try await store.clearAll()

        let remaining = directoryEntries(directory)
        XCTAssertTrue(remaining.filter { $0.hasSuffix(".png") || $0.hasSuffix(".tiff") }.isEmpty, "殘留：\(remaining)")
        let reloaded = ClipboardStore(persistence: persistence)
        let count = await reloaded.items.count
        XCTAssertEqual(count, 0)
        if let data = try? Data(contentsOf: indexURL(directory)) {
            XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("secret text"), "索引檔不得殘留文字內容")
        }
    }

    func testStoreOnRealDiskSurvivesRestartAndEvictionDeletesImageFile() async throws {
        let (persistence, directory) = try makePersistence()
        let first = ClipboardStore(persistence: persistence, maxItems: 1)
        _ = await first.add(ClipboardCapture(imageData: utf8("img-1")), now: t(1))
        _ = await first.add(ClipboardCapture(imageData: utf8("img-2")), now: t(2))
        XCTAssertEqual(directoryEntries(directory).filter { $0.hasSuffix(".png") }.count, 1, "被淘汰那筆的檔案已刪除")

        let second = ClipboardStore(persistence: persistence, maxItems: 1)
        let restored = await second.items
        XCTAssertEqual(restored.count, 1)
        let data = await second.imageData(for: try XCTUnwrap(restored.first))
        XCTAssertEqual(data, utf8("img-2"))
    }
}

final class InMemoryClipboardPersistenceTests: XCTestCase {
    func testRoundTripOfItemsAndImages() throws {
        let persistence = InMemoryClipboardPersistence()
        let image = ClipboardItem(imageData: tinyPNG)
        let name = try XCTUnwrap(image.imageFileName)
        try persistence.saveImage(tinyPNG, fileName: name)
        try persistence.saveItems([image, ClipboardItem(text: "t")])
        XCTAssertEqual(persistence.loadItems().count, 2)
        XCTAssertEqual(persistence.loadImage(fileName: name), tinyPNG)
        XCTAssertEqual(persistence.imageFileNames(), [name])
    }

    func testDeleteImageAndDeleteAll() throws {
        let persistence = InMemoryClipboardPersistence()
        try persistence.saveImage(utf8("a"), fileName: "a.png")
        try persistence.saveImage(utf8("b"), fileName: "b.png")
        try persistence.deleteImage(fileName: "a.png")
        try persistence.deleteImage(fileName: "missing.png")
        XCTAssertEqual(persistence.imageFileNames(), ["b.png"])
        try persistence.saveItems([ClipboardItem(text: "x")])
        try persistence.deleteAll()
        XCTAssertEqual(persistence.imageFileNames(), [])
        XCTAssertEqual(persistence.loadItems(), [])
    }

    func testEmptyPersistenceLoadsEmpty() {
        let persistence = InMemoryClipboardPersistence()
        XCTAssertEqual(persistence.loadItems(), [])
        XCTAssertNil(persistence.loadImage(fileName: "nope.png"))
        XCTAssertFalse(persistence.imageExists(fileName: "nope.png"))
    }

    func testConcurrentAccessIsSafe() {
        let persistence = InMemoryClipboardPersistence()
        DispatchQueue.concurrentPerform(iterations: 200) { i in
            try? persistence.saveImage(utf8("\(i)"), fileName: "f\(i % 10).png")
            try? persistence.saveItems([ClipboardItem(text: "\(i)")])
            _ = persistence.loadItems()
            _ = persistence.imageFileNames()
        }
        XCTAssertEqual(persistence.imageFileNames().count, 10)
    }
}
