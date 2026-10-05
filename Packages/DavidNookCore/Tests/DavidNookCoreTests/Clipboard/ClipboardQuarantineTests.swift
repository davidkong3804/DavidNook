import XCTest
@testable import DavidNookCore

/// F3(a)：損毀索引的隔離檔 `index.json.corrupt` 保留完整明文，不能無限期留著，
/// 也不能躲過「清除未釘選」「清除全部」。
final class ClipboardQuarantineTests: XCTestCase {
    private let hours: TimeInterval = 3600

    private func makeDirectory() throws -> URL {
        let root = try makeTempDirectory(for: self)
        return root.appendingPathComponent("Clipboard", isDirectory: true)
    }

    private func corruptURL(_ directory: URL) -> URL {
        directory.appendingPathComponent("index.json.corrupt")
    }

    /// 在目錄中放一個隔離檔，並把它的修改時間設成 `age` 秒以前。
    private func plantQuarantine(in directory: URL, age: TimeInterval, content: String = "{ broken TOPSECRET-F3") throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = corruptURL(directory)
        try Data(content.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: url.path)
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    // MARK: 常數

    func testQuarantineMaxAgeIs24Hours() {
        XCTAssertEqual(FileClipboardPersistence.quarantineMaxAge, 24 * 3600)
    }

    // MARK: 逾期刪除

    func testStartupDeletesAQuarantineFileOlderThan24Hours() throws {
        let directory = try makeDirectory()
        try plantQuarantine(in: directory, age: 25 * hours)
        _ = try FileClipboardPersistence(directory: directory)
        XCTAssertFalse(exists(corruptURL(directory)), "啟動時要刪掉逾期的隔離檔")
    }

    func testStartupKeepsARecentQuarantineFile() throws {
        let directory = try makeDirectory()
        try plantQuarantine(in: directory, age: 1 * hours)
        _ = try FileClipboardPersistence(directory: directory)
        XCTAssertTrue(exists(corruptURL(directory)))
    }

    func testPruneQuarantineDeletesOnlyFilesOlderThanMaxAge() throws {
        let directory = try makeDirectory()
        let persistence = try FileClipboardPersistence(directory: directory)
        try plantQuarantine(in: directory, age: 23 * hours)
        persistence.pruneQuarantine(now: Date(), maxAge: FileClipboardPersistence.quarantineMaxAge)
        XCTAssertTrue(exists(corruptURL(directory)), "23 小時：保留")
        try plantQuarantine(in: directory, age: 25 * hours)
        persistence.pruneQuarantine(now: Date(), maxAge: FileClipboardPersistence.quarantineMaxAge)
        XCTAssertFalse(exists(corruptURL(directory)), "25 小時：刪除")
    }

    func testPruneQuarantineNeverTouchesTheIndexOrImages() throws {
        let directory = try makeDirectory()
        let persistence = try FileClipboardPersistence(directory: directory)
        let image = ClipboardItem(imageData: tinyPNG)
        try persistence.saveImage(tinyPNG, fileName: try XCTUnwrap(image.imageFileName))
        try persistence.saveItems([image])
        try plantQuarantine(in: directory, age: 48 * hours)
        persistence.pruneQuarantine(now: Date(), maxAge: 1)
        XCTAssertEqual(persistence.loadItems(), [image])
        XCTAssertTrue(persistence.imageExists(fileName: try XCTUnwrap(image.imageFileName)))
    }

    func testQuarantiningStampsTheMoveTimeSoAnOldIndexIsNotExpiredImmediately() throws {
        let directory = try makeDirectory()
        let persistence = try FileClipboardPersistence(directory: directory)
        let index = directory.appendingPathComponent("index.json")
        try Data("{ not json".utf8).write(to: index)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-72 * hours)], ofItemAtPath: index.path)

        XCTAssertEqual(persistence.loadItems(), [])
        XCTAssertTrue(exists(corruptURL(directory)))
        persistence.pruneQuarantine(now: Date(), maxAge: FileClipboardPersistence.quarantineMaxAge)
        XCTAssertTrue(exists(corruptURL(directory)), "隔離檔的年齡從「被隔離的那一刻」算起，不是原索引的最後寫入時間")
    }

    func testStorePruneDeletesAnExpiredQuarantineEvenWhenRetentionIsForever() async throws {
        let directory = try makeDirectory()
        let persistence = try FileClipboardPersistence(directory: directory)
        let store = ClipboardStore(persistence: persistence, retention: nil)
        try plantQuarantine(in: directory, age: 30 * hours)
        _ = await store.prune(now: Date())
        XCTAssertFalse(exists(corruptURL(directory)), "保留期設為永久，也不能讓隔離檔永久留著")
    }

    // MARK: 清除

    func testDeleteQuarantineRemovesOnlyTheQuarantineFile() throws {
        let directory = try makeDirectory()
        let persistence = try FileClipboardPersistence(directory: directory)
        try persistence.saveItems([ClipboardItem(text: "live")])
        try plantQuarantine(in: directory, age: 0)
        try persistence.deleteQuarantine()
        XCTAssertFalse(exists(corruptURL(directory)))
        XCTAssertEqual(persistence.loadItems().compactMap(\.text), ["live"])
        XCTAssertNoThrow(try persistence.deleteQuarantine(), "沒有隔離檔也不是錯誤")
    }

    func testClearUnpinnedDeletesTheQuarantineFile() async throws {
        let directory = try makeDirectory()
        let persistence = try FileClipboardPersistence(directory: directory)
        let store = ClipboardStore(persistence: persistence)
        _ = await store.add(ClipboardCapture(text: "unpinned"), now: t(1))
        try plantQuarantine(in: directory, age: 0)
        await store.clearUnpinned()
        XCTAssertFalse(exists(corruptURL(directory)), "「清除未釘選」必須連隔離檔一起刪")
    }

    func testClearAllDeletesTheQuarantineFile() async throws {
        let directory = try makeDirectory()
        let persistence = try FileClipboardPersistence(directory: directory)
        let store = ClipboardStore(persistence: persistence)
        _ = await store.add(ClipboardCapture(text: "x"), now: t(1))
        try plantQuarantine(in: directory, age: 0)
        try await store.clearAll()
        XCTAssertFalse(exists(corruptURL(directory)), "「清除全部」必須連隔離檔一起刪")
        XCTAssertEqual(directoryEntries(directory), [])
    }
}
