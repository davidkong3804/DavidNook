import XCTest
@testable import DavidNookCore

// 以 stub transport 驗證「影片標題 → 歌名／歌手 → LRCLIB 查詢 → 歌詞」整條管線。
// 樣本皆為自編的虛構歌詞；所有 HTTP 一律走 StubTransport，不連外網。

final class VideoAwareLyricsFetcherTests: XCTestCase {

    private let lrc = "[00:05.00]測試句一，第一行是虛構的\n[00:12.00]測試句二，第二行也是\n[00:30.00]測試句三"

    private struct Song {
        var id: Int
        var track: String
        var artist: String
        var duration: Double = 215
    }

    /// 假 LRCLIB：`catalog` 內的曲目，get 以（歌名,歌手）精確比對（不看 duration，與 LRCLIB 缺省行為近似），
    /// search 以歌名包含比對；其餘 404／空陣列。
    private func fakeLrclib(_ catalog: [Song]) -> StubTransport {
        StubTransport(handler: { [lrc] request, _ in
            let q = queryDict(request)
            func record(_ s: Song) -> [String: Any] {
                recordObject(id: s.id, track: s.track, artist: s.artist, duration: s.duration, synced: lrc)
            }
            switch request.url?.path {
            case "/api/get":
                if let s = catalog.first(where: { $0.track == q["track_name"] && $0.artist == q["artist_name"] }) {
                    return .ok(jsonString(record(s)))
                }
                return .notFound
            case "/api/search":
                let hits = catalog.filter { s in
                    guard let name = q["track_name"] else { return false }
                    return s.track.lowercased().contains(name.lowercased())
                        && (q["artist_name"].map { s.artist.lowercased().contains($0.lowercased()) } ?? true)
                }
                return .ok(jsonString(hits.map(record)))
            default:
                return .status(500)
            }
        })
    }

    private func repo(_ transport: StubTransport, store: MemoryLyricsCacheStore = MemoryLyricsCacheStore()) -> LyricsRepository {
        LyricsPipeline.makeRepository(
            transport: transport, store: store, appVersion: "9.9.9", sleeper: { _ in }, requestSpacing: 0
        )
    }

    private func youtube(
        _ title: String, channel: String = "", duration: TimeInterval = 270, bundle: String? = "com.google.Chrome"
    ) -> LyricsQuery {
        LyricsQuery(title: title, artist: channel, album: nil, duration: duration, sourceBundleID: bundle)
    }

    // MARK: - 影片標題 → 正確查詢 → 歌詞

    func testYouTubeStyleTitleIsResolvedToTheRealSongAndArtist() async throws {
        let t = fakeLrclib([Song(id: 11, track: "告白氣球", artist: "周杰倫")])
        let picked = try await repo(t).lyrics(for: youtube(
            "周杰倫 Jay Chou【告白氣球 Balloon】Official MV", channel: "杰威爾音樂 JVR Music", duration: 270
        ))

        let result = try XCTUnwrap(picked, "影片比歌長 55 秒仍應找到")
        XCTAssertEqual(result.candidateID, 11)
        XCTAssertEqual(result.trackName, "告白氣球")
        XCTAssertEqual(result.lines.first?.text, "測試句一，第一行是虛構的")

        let get = try XCTUnwrap(t.requests.first)
        XCTAssertEqual(get.url?.path, "/api/get", "先 /api/get")
        XCTAssertEqual(queryDict(get)["track_name"], "告白氣球")
        XCTAssertEqual(queryDict(get)["artist_name"], "周杰倫")
        XCTAssertNil(queryDict(get)["duration"], "影片長度≠歌長：影片來源的 get 不帶 duration")
        XCTAssertEqual(t.requests.last?.url?.path, "/api/search", "再 /api/search")
        XCTAssertEqual(t.requests.last.map(queryDict)?["track_name"], "告白氣球")
        XCTAssertEqual(t.requests.count, 2)
    }

    func testNoRequestEverCarriesVideoTitleJunk() async throws {
        let t = fakeLrclib([Song(id: 11, track: "告白氣球", artist: "周杰倫")])
        _ = try await repo(t).lyrics(for: youtube("周杰倫 Jay Chou【告白氣球 Balloon】Official MV", channel: "JVR Music"))
        for request in t.requests {
            let url = request.url?.absoluteString ?? ""
            XCTAssertFalse(url.contains("Official"), url)
            XCTAssertFalse(url.contains("MV"), url)
            XCTAssertEqual(request.url?.host, "lrclib.net", "唯一的對外主機")
            XCTAssertTrue(Set(queryDict(request).keys).isSubset(of: ["track_name", "artist_name", "duration"]), "只送歌名、歌手、長度")
        }
    }

    func testSecondCandidateWinsWhenTheFirstOrientationFindsNothing() async throws {
        // 「歌名 - 歌手」且頻道沒有線索：先試（Ed Sheeran, Shape of You），沒結果再換方向。
        let t = fakeLrclib([Song(id: 21, track: "Shape of You", artist: "Ed Sheeran", duration: 233)])
        let picked = try await repo(t).lyrics(for: youtube(
            "Shape of You - Ed Sheeran (Lyrics)", channel: "Lyric Archive Channel", duration: 245
        ))

        XCTAssertEqual(picked?.candidateID, 21)
        let gets = t.requests.filter { $0.url?.path == "/api/get" }.map { queryDict($0)["track_name"] ?? "" }
        XCTAssertEqual(gets.last, "Shape of You", "最後命中的是正確方向")
    }

    func testChannelHintPicksTheRightOrientationFirstWithMinimalRequests() async throws {
        let t = fakeLrclib([Song(id: 21, track: "Shape of You", artist: "Ed Sheeran", duration: 233)])
        let picked = try await repo(t).lyrics(for: youtube("Shape of You - Ed Sheeran (Lyrics)", channel: "Ed Sheeran - Topic", duration: 233))
        XCTAssertEqual(picked?.candidateID, 21)
        XCTAssertEqual(t.requests.count, 2, "頻道線索正確時，第一個候選就命中（get＋search）")
    }

    func testEnglishAliasCandidateCanWin() async throws {
        // LRCLIB 只收錄英文歌名。
        let t = fakeLrclib([Song(id: 31, track: "Balloon", artist: "周杰倫")])
        let picked = try await repo(t).lyrics(for: youtube("周杰倫 Jay Chou【告白氣球 Balloon】Official MV", channel: "JVR Music"))
        XCTAssertEqual(picked?.candidateID, 31)
    }

    func testCleanTitleFromYouTubeMusicStillWorks() async throws {
        let t = fakeLrclib([Song(id: 41, track: "稻香", artist: "周杰倫", duration: 223)])
        let picked = try await repo(t).lyrics(for: youtube("稻香", channel: "周杰倫", duration: 223))
        XCTAssertEqual(picked?.candidateID, 41)
    }

    // MARK: - 寧缺勿錯

    func testVideoMuchLongerThanTheSongFindsNothing() async throws {
        let t = fakeLrclib([Song(id: 11, track: "告白氣球", artist: "周杰倫", duration: 215)])
        let picked = try await repo(t).lyrics(for: youtube("周杰倫 - 告白氣球 (Official MV)", duration: 600))
        XCTAssertNil(picked, "10 分鐘的影片（合輯／直播）不能配 3 分 35 秒的歌")
    }

    func testSameTitleByAnotherArtistIsNotAccepted() async throws {
        let t = fakeLrclib([Song(id: 51, track: "Shape of You", artist: "Some Cover Band", duration: 233)])
        let picked = try await repo(t).lyrics(for: youtube("Ed Sheeran - Shape of You (Official Music Video)", channel: "Ed Sheeran", duration: 245))
        XCTAssertNil(picked, "同名但歌手不同＝放錯歌，寧可顯示找不到")
    }

    func testNothingFoundReturnsNilWithoutCrashing() async throws {
        let t = fakeLrclib([])
        let picked = try await repo(t).lyrics(for: youtube("Unknown Artist - Unknown Song (Official Video)", channel: "Unknown Artist"))
        XCTAssertNil(picked)
        XCTAssertLessThanOrEqual(t.requests.count, TrackTitleExtractor.maxCandidates * 6, "請求數有上限")
    }

    func testOnlyDecorationTitleMakesNoRequests() async throws {
        let t = fakeLrclib([])
        let picked = try await repo(t).lyrics(for: youtube("【Official MV】", channel: "JVR Music"))
        XCTAssertNil(picked)
        XCTAssertEqual(t.requests.count, 0)
    }

    func testNetworkErrorsPropagateInsteadOfBeingReportedAsNotFound() async {
        let t = StubTransport(handler: { _, _ in .failure(URLError(.notConnectedToInternet)) })
        do {
            _ = try await repo(t).lyrics(for: youtube("Ed Sheeran - Perfect (Official Video)", channel: "Ed Sheeran"))
            XCTFail("應該拋出網路錯誤")
        } catch let error as LrclibError {
            guard case .network = error else { return XCTFail("\(error)") }
        } catch {
            XCTFail("\(error)")
        }
    }

    // MARK: - 快取鍵＝原始曲目鍵

    func testFoundLyricsAreCachedUnderTheOriginalTrackKey() async throws {
        let t = fakeLrclib([Song(id: 11, track: "告白氣球", artist: "周杰倫")])
        let store = MemoryLyricsCacheStore()
        let r = repo(t, store: store)
        let query = youtube("周杰倫 Jay Chou【告白氣球 Balloon】Official MV", channel: "JVR Music")

        _ = try await r.lyrics(for: query)
        let afterFirst = t.requests.count
        let second = try await r.lyrics(for: query)

        XCTAssertNotNil(second)
        XCTAssertEqual(t.requests.count, afterFirst, "同一支影片第二次不再連網")
        let key = TrackKey(title: query.title, artist: query.artist, duration: query.duration)
        XCTAssertNotNil(store.entry(for: key)?.lyrics, "快取鍵是原始 title／artist／duration")
        XCTAssertNil(store.entry(for: TrackKey(title: "告白氣球", artist: "周杰倫", duration: 270)))
    }

    func testNotFoundIsNegativelyCachedUnderTheOriginalKey() async throws {
        let t = fakeLrclib([])
        let r = repo(t)
        let query = youtube("Nobody - Nothing (Official Video)", channel: "Nobody")
        _ = try await r.lyrics(for: query)
        let afterFirst = t.requests.count
        XCTAssertGreaterThan(afterFirst, 0)
        _ = try await r.lyrics(for: query)
        XCTAssertEqual(t.requests.count, afterFirst, "負快取：30 分鐘內同一支影片不重查")
    }

    // MARK: - 乾淨來源完全不變

    func testAppleMusicQueryProducesExactlyTheSameRequestsAsTheBareClient() async throws {
        let catalog = [Song(id: 61, track: "告白氣球", artist: "周杰倫", duration: 215)]
        let query = LyricsQuery(title: "告白氣球", artist: "周杰倫", album: nil, duration: 215, sourceBundleID: "com.apple.Music")

        let wrapped = fakeLrclib(catalog)
        let viaPipeline = try await repo(wrapped).lyrics(for: query)

        let bare = fakeLrclib(catalog)
        let client = LyricsPipeline.makeClient(transport: bare, appVersion: "9.9.9", sleeper: { _ in }, requestSpacing: 0)
        let viaClient = try await LyricsRepository(fetcher: client, store: MemoryLyricsCacheStore()).lyrics(for: query)

        XCTAssertEqual(viaPipeline, viaClient)
        XCTAssertEqual(wrapped.requests.map { $0.url }, bare.requests.map { $0.url }, "請求網址與順序完全相同")
        XCTAssertEqual(queryDict(wrapped.requests[0])["duration"], "215", "乾淨來源的 get 仍帶 duration")
    }

    func testVideoLikeTitleFromAppleMusicIsNotParsed() async throws {
        let t = fakeLrclib([Song(id: 71, track: "Song (Official Video)", artist: "Someone", duration: 200)])
        let query = LyricsQuery(title: "Song (Official Video)", artist: "Someone", album: nil, duration: 200, sourceBundleID: "com.apple.Music")
        let picked = try await repo(t).lyrics(for: query)
        XCTAssertEqual(picked?.candidateID, 71)
        XCTAssertEqual(queryDict(t.requests[0])["track_name"], "Song (Official Video)", "乾淨來源的歌名原樣查詢，不剝裝飾")
    }

    func testAppleMusicDurationMismatchStillRejected() async throws {
        let t = fakeLrclib([Song(id: 61, track: "告白氣球", artist: "周杰倫", duration: 215)])
        let query = LyricsQuery(title: "告白氣球", artist: "周杰倫", album: nil, duration: 255, sourceBundleID: "com.apple.Music")
        let picked = try await repo(t).lyrics(for: query)
        XCTAssertNil(picked, "非影片來源：長度差 40 秒仍然拒絕（嚴格 2 秒規則不變）")
    }

    func testQueryWithoutBundleIDAndCleanTitleIsUnchanged() async throws {
        let catalog = [Song(id: 81, track: "夜行燈", artist: "阿虛", duration: 223)]
        let query = LyricsQuery(title: "夜行燈", artist: "阿虛", duration: 223)
        let a = fakeLrclib(catalog)
        let viaPipeline = try await repo(a).lyrics(for: query)
        XCTAssertEqual(viaPipeline?.candidateID, 81)
        XCTAssertEqual(a.requests.count, 2)
    }
}
