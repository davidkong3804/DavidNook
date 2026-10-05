import XCTest
@testable import DavidNookCore

// 樣本皆為自編的虛構句子；不使用任何真實歌詞。

final class FileLyricsCacheStoreTests: XCTestCase {

    private let key = TrackKey(title: "夜行的燈", artist: "阿虛", duration: 223.4)
    private let otherKey = TrackKey(title: "Night Lamp", artist: "Someone", duration: 180)

    private func makeLyrics(id: Int = 1) -> PickedLyrics {
        PickedLyrics(
            candidateID: id,
            trackName: "夜行的燈",
            artistName: "阿虛",
            script: .traditional,
            lines: [L(0, ""), L(10_000, "測試句一"), L(20_500, "測試句二"), L(30_000, "")],
            offsetMs: -250,
            metadata: ["ti": "夜行的燈", "length": "03:43"]
        )
    }

    private func makeStore() throws -> (store: FileLyricsCacheStore, directory: URL) {
        let root = try makeTempDirectory(for: self)
        let directory = root.appendingPathComponent("Application Support/DavidNook/Lyrics", isDirectory: true)
        return (try FileLyricsCacheStore(directory: directory), directory)
    }

    private func cacheFiles(_ directory: URL) -> [String] {
        directoryEntries(directory)
    }

    // MARK: - 權限與目錄

    func testInitCreatesNestedDirectoryWithMode0700() throws {
        let (_, directory) = try makeStore()
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
        XCTAssertEqual(try posixPermissions(of: directory), 0o700)
    }

    func testInitTightensAnExistingLooseDirectoryTo0700() throws {
        let root = try makeTempDirectory(for: self)
        let directory = root.appendingPathComponent("Lyrics")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        _ = try FileLyricsCacheStore(directory: directory)
        XCTAssertEqual(try posixPermissions(of: directory), 0o700)
    }

    func testCacheFilesAreMode0600AndLeaveNoTempFiles() throws {
        let (store, directory) = try makeStore()
        store.store(LyricsCacheEntry(lyrics: makeLyrics(), storedAt: ManualClock.reference), for: key)
        let files = cacheFiles(directory)
        XCTAssertEqual(files.count, 1)
        XCTAssertFalse(files.contains { $0.contains(".tmp-") })
        let first = try XCTUnwrap(files.first)
        XCTAssertEqual(try posixPermissions(of: directory.appendingPathComponent(first)), 0o600)
    }

    func testFileNamesDoNotRevealSongTitleOrArtist() throws {
        let (store, directory) = try makeStore()
        store.store(LyricsCacheEntry(lyrics: makeLyrics(), storedAt: ManualClock.reference), for: key)
        store.store(LyricsCacheEntry(lyrics: nil, storedAt: ManualClock.reference), for: otherKey)
        let pattern = try NSRegularExpression(pattern: "^[0-9a-f]{64}\\.json$")
        for name in cacheFiles(directory) {
            XCTAssertNotNil(pattern.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)), "檔名不符：\(name)")
        }
        XCTAssertEqual(cacheFiles(directory).count, 2)
    }

    // MARK: - 往返

    func testRoundTripsFoundLyrics() throws {
        let (store, _) = try makeStore()
        let entry = LyricsCacheEntry(lyrics: makeLyrics(), storedAt: ManualClock.reference)
        store.store(entry, for: key)
        XCTAssertEqual(store.entry(for: key), entry)
    }

    func testRoundTripsNegativeEntryWithStoredAt() throws {
        let (store, _) = try makeStore()
        let when = Date(timeIntervalSinceReferenceDate: 812_345_678.25)
        store.store(LyricsCacheEntry(lyrics: nil, storedAt: when), for: key)
        let loaded = try XCTUnwrap(store.entry(for: key))
        XCTAssertNil(loaded.lyrics)
        XCTAssertEqual(loaded.storedAt.timeIntervalSinceReferenceDate, when.timeIntervalSinceReferenceDate, accuracy: 0.001)
    }

    func testMissingKeyYieldsNilAndCreatesNoFiles() throws {
        let (store, directory) = try makeStore()
        XCTAssertNil(store.entry(for: key))
        XCTAssertEqual(cacheFiles(directory), [])
    }

    func testKeysAreIndependent() throws {
        let (store, _) = try makeStore()
        store.store(LyricsCacheEntry(lyrics: makeLyrics(id: 1), storedAt: ManualClock.reference), for: key)
        store.store(LyricsCacheEntry(lyrics: makeLyrics(id: 2), storedAt: ManualClock.reference), for: otherKey)
        XCTAssertEqual(store.entry(for: key)?.lyrics?.candidateID, 1)
        XCTAssertEqual(store.entry(for: otherKey)?.lyrics?.candidateID, 2)
    }

    func testEquivalentTrackKeysShareAnEntry() throws {
        // TrackKey 正規化：大小寫、前後空白、秒數取整都視為同一首。
        let (store, directory) = try makeStore()
        store.store(LyricsCacheEntry(lyrics: makeLyrics(), storedAt: ManualClock.reference),
                    for: TrackKey(title: "Song", artist: "Artist", duration: 223.4))
        let hit = store.entry(for: TrackKey(title: "  song ", artist: "ARTIST", duration: 222.6))
        XCTAssertNotNil(hit)
        XCTAssertEqual(cacheFiles(directory).count, 1)
    }

    func testOverwriteReplacesTheEntry() throws {
        let (store, directory) = try makeStore()
        store.store(LyricsCacheEntry(lyrics: nil, storedAt: ManualClock.reference), for: key)
        store.store(LyricsCacheEntry(lyrics: makeLyrics(id: 9), storedAt: ManualClock.reference), for: key)
        XCTAssertEqual(store.entry(for: key)?.lyrics?.candidateID, 9)
        XCTAssertEqual(cacheFiles(directory).count, 1)
    }

    func testEntriesSurviveANewInstanceOnTheSameDirectory() throws {
        let (store, directory) = try makeStore()
        let entry = LyricsCacheEntry(lyrics: makeLyrics(), storedAt: ManualClock.reference)
        store.store(entry, for: key)
        let reopened = try FileLyricsCacheStore(directory: directory)
        XCTAssertEqual(reopened.entry(for: key), entry)
    }

    // MARK: - 損毀容忍

    private func onlyCacheFile(_ directory: URL) throws -> URL {
        let files = cacheFiles(directory)
        XCTAssertEqual(files.count, 1)
        return directory.appendingPathComponent(try XCTUnwrap(files.first))
    }

    func testGarbageFileIsTreatedAsMissAndCanBeRewritten() throws {
        let (store, directory) = try makeStore()
        store.store(LyricsCacheEntry(lyrics: makeLyrics(), storedAt: ManualClock.reference), for: key)
        let file = try onlyCacheFile(directory)
        try Data([0x00, 0xFF, 0x10, 0x80, 0x42]).write(to: file)

        XCTAssertNil(store.entry(for: key))                       // 不崩潰、視為沒有
        store.store(LyricsCacheEntry(lyrics: makeLyrics(id: 5), storedAt: ManualClock.reference), for: key)
        XCTAssertEqual(store.entry(for: key)?.lyrics?.candidateID, 5)
        XCTAssertEqual(cacheFiles(directory).count, 1)
    }

    func testTruncatedJSONIsTreatedAsMiss() throws {
        let (store, directory) = try makeStore()
        store.store(LyricsCacheEntry(lyrics: makeLyrics(), storedAt: ManualClock.reference), for: key)
        let file = try onlyCacheFile(directory)
        let data = try Data(contentsOf: file)
        try data.prefix(data.count / 2).write(to: file)
        XCTAssertNil(store.entry(for: key))
    }

    func testWellFormedJSONWithWrongShapeIsTreatedAsMiss() throws {
        let (store, directory) = try makeStore()
        // 讀到壞檔時會把它刪掉，所以每次都直接寫到該 key 的檔名。
        let file = directory.appendingPathComponent(FileLyricsCacheStore.fileName(for: key))
        for garbage in ["{\"version\":1,\"hello\":\"world\"}", "[1,2,3]", "", "null"] {
            try utf8(garbage).write(to: file)
            XCTAssertNil(store.entry(for: key), "應視為未命中：\(garbage)")
        }
    }

    func testFileWhoseEmbeddedKeyDoesNotMatchIsRejected() throws {
        // 例如檔案被複製或改名成別首歌的檔名：內嵌的 key 不符就不能被當成那首歌的歌詞。
        let (store, directory) = try makeStore()
        store.store(LyricsCacheEntry(lyrics: makeLyrics(id: 1), storedAt: ManualClock.reference), for: key)
        let source = try onlyCacheFile(directory)
        let target = directory.appendingPathComponent(FileLyricsCacheStore.fileName(for: otherKey))
        try FileManager.default.copyItem(at: source, to: target)
        XCTAssertNil(store.entry(for: otherKey))
        XCTAssertNotNil(store.entry(for: key))
    }

    func testUnknownFormatVersionIsTreatedAsMiss() throws {
        let (store, directory) = try makeStore()
        store.store(LyricsCacheEntry(lyrics: makeLyrics(), storedAt: ManualClock.reference), for: key)
        let file = try onlyCacheFile(directory)
        var text = try String(contentsOf: file, encoding: .utf8)
        text = text.replacingOccurrences(of: "\"version\":\(FileLyricsCacheStore.formatVersion)", with: "\"version\":999")
        try utf8(text).write(to: file)
        XCTAssertNil(store.entry(for: key))
    }

    func testUnwritableDirectoryDoesNotCrashAndLosesNothingElse() throws {
        let (store, directory) = try makeStore()
        store.store(LyricsCacheEntry(lyrics: makeLyrics(id: 1), storedAt: ManualClock.reference), for: key)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        // 寫入失敗要靜默吞掉（快取是 best effort），既有檔案不受影響。
        store.store(LyricsCacheEntry(lyrics: makeLyrics(id: 2), storedAt: ManualClock.reference), for: otherKey)
        XCTAssertEqual(store.entry(for: key)?.lyrics?.candidateID, 1)
        XCTAssertNil(store.entry(for: otherKey))
    }

    // MARK: - 清除

    func testRemoveAllDeletesOnlyCacheFiles() throws {
        let (store, directory) = try makeStore()
        store.store(LyricsCacheEntry(lyrics: makeLyrics(id: 1), storedAt: ManualClock.reference), for: key)
        store.store(LyricsCacheEntry(lyrics: nil, storedAt: ManualClock.reference), for: otherKey)
        let stranger = directory.appendingPathComponent("notes.txt")
        try utf8("not ours").write(to: stranger)

        let removed = try store.removeAll()

        XCTAssertEqual(removed, 2)
        XCTAssertNil(store.entry(for: key))
        XCTAssertNil(store.entry(for: otherKey))
        XCTAssertEqual(cacheFiles(directory), ["notes.txt"], "不是本 app 產生的檔案不能被碰")
    }

    func testRemoveAllOnEmptyDirectoryReturnsZero() throws {
        let (store, _) = try makeStore()
        XCTAssertEqual(try store.removeAll(), 0)
    }

    func testStoreAfterRemoveAllWorks() throws {
        let (store, _) = try makeStore()
        store.store(LyricsCacheEntry(lyrics: makeLyrics(id: 1), storedAt: ManualClock.reference), for: key)
        try store.removeAll()
        store.store(LyricsCacheEntry(lyrics: makeLyrics(id: 2), storedAt: ManualClock.reference), for: key)
        XCTAssertEqual(store.entry(for: key)?.lyrics?.candidateID, 2)
    }

    // MARK: - 與 LyricsRepository 整合

    private final class CountingFetcher: LyricsFetching, @unchecked Sendable {
        let calls = Locked<Int>(0)
        let result: PickedLyrics?
        init(_ result: PickedLyrics?) { self.result = result }
        func lyrics(for query: LyricsQuery) async throws -> PickedLyrics? {
            calls.withLock { $0 += 1 }
            return result
        }
    }

    func testRepositoryServesFoundLyricsFromDiskAfterRestartWithoutFetching() async throws {
        let (store, directory) = try makeStore()
        let query = LyricsQuery(title: "夜行的燈", artist: "阿虛", duration: 223.4)
        let first = CountingFetcher(makeLyrics())
        let repo1 = LyricsRepository(fetcher: first, store: store)
        _ = try await repo1.lyrics(for: query)
        XCTAssertEqual(first.calls.snapshot, 1)

        let second = CountingFetcher(nil)
        let repo2 = LyricsRepository(fetcher: second, store: try FileLyricsCacheStore(directory: directory))
        let loaded = try await repo2.lyrics(for: query)
        XCTAssertEqual(loaded, makeLyrics())
        XCTAssertEqual(second.calls.snapshot, 0)
    }

    func testRepositoryHonoursNegativeTTLAcrossRestarts() async throws {
        let (store, directory) = try makeStore()
        let clock = ManualClock()
        let query = LyricsQuery(title: "夜行的燈", artist: "阿虛", duration: 223.4)
        let first = CountingFetcher(nil)
        _ = try await LyricsRepository(fetcher: first, store: store, negativeTTL: 1_800, now: clock.provider).lyrics(for: query)
        XCTAssertEqual(first.calls.snapshot, 1)

        // 重啟後、TTL 內：仍視為找不到，不重打網路。
        clock.advance(600)
        let second = CountingFetcher(makeLyrics())
        let repo2 = LyricsRepository(fetcher: second, store: try FileLyricsCacheStore(directory: directory),
                                     negativeTTL: 1_800, now: clock.provider)
        let within = try await repo2.lyrics(for: query)
        XCTAssertNil(within)
        XCTAssertEqual(second.calls.snapshot, 0)

        // TTL 過後：重新查詢，並以結果取代負快取。
        clock.advance(1_300)
        let after = try await repo2.lyrics(for: query)
        XCTAssertEqual(after, makeLyrics())
        XCTAssertEqual(second.calls.snapshot, 1)
    }

    // MARK: - 並行

    func testConcurrentStoresAndReadsAreSafe() async throws {
        let (store, _) = try makeStore()
        let keys = (0..<8).map { TrackKey(title: "曲目\($0)", artist: "阿虛", duration: Double(100 + $0)) }
        await withTaskGroup(of: Void.self) { group in
            for round in 0..<40 {
                group.addTask {
                    let k = keys[round % keys.count]
                    store.store(LyricsCacheEntry(lyrics: self.makeLyrics(id: round), storedAt: ManualClock.reference), for: k)
                    _ = store.entry(for: k)
                }
            }
        }
        for k in keys { XCTAssertNotNil(store.entry(for: k)?.lyrics) }
    }

    // MARK: - 隱私：不輸出任何內容到 log

    /// 靜態把關：FileLyricsCacheStore 原始碼不得出現 print / NSLog / os_log / Logger 等直接輸出。
    func testSourceContainsNoPrintOrSystemLoggingCalls() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Lyrics
            .deletingLastPathComponent()   // DavidNookCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // package root
        let file = packageRoot.appendingPathComponent("Sources/DavidNookCore/Lyrics/FileLyricsCacheStore.swift")
        let text = try String(contentsOf: file, encoding: .utf8)
        let call = try NSRegularExpression(pattern: "(?<![A-Za-z0-9_])(print|debugPrint|NSLog|os_log|Logger|dump|fputs)\\(")
        let imp = try NSRegularExpression(pattern: "^\\s*import\\s+(os|OSLog)\\b")
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let content = String(line)
            if content.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
            let range = NSRange(content.startIndex..., in: content)
            if call.firstMatch(in: content, range: range) != nil || imp.firstMatch(in: content, range: range) != nil {
                XCTFail("FileLyricsCacheStore.swift:\(index + 1) 含有直接輸出／系統 log 呼叫：\(content)")
            }
        }
    }
}
