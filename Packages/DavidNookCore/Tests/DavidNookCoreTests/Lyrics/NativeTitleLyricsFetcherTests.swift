import XCTest
@testable import DavidNookCore

final class NativeTitleLyricsFetcherTests: XCTestCase {
    private let romanized = LyricsQuery(title: "Shinunoga E-Wa", artist: "藤井風", album: nil, duration: 185.573)

    private func itunes(_ results: [(String, Double)]) -> String {
        let items = results.map { "{\"trackName\":\"\($0.0)\",\"trackTimeMillis\":\(Int($0.1))}" }
        return "{\"resultCount\":\(results.count),\"results\":[\(items.joined(separator: ","))]}"
    }

    private func resolver(_ t: StubTransport, enabled: Bool = true) -> ITunesNativeTitleResolver {
        ITunesNativeTitleResolver(transport: t, isEnabled: { enabled })
    }

    // MARK: - 判斷

    func testOnlyRomanizedTitleWithNativeArtistQualifies() {
        XCTAssertTrue(romanized.looksRomanizedAgainstNativeArtist)
        XCTAssertFalse(LyricsQuery(title: "Shinunoga E-Wa", artist: "Fujii Kaze", duration: 185).looksRomanizedAgainstNativeArtist)
        XCTAssertFalse(LyricsQuery(title: "死ぬのがいいわ", artist: "藤井風", duration: 185).looksRomanizedAgainstNativeArtist)
        XCTAssertFalse(LyricsQuery(title: "Song", artist: "", duration: 185).looksRomanizedAgainstNativeArtist)
        XCTAssertFalse(LyricsQuery(title: " ", artist: "藤井風", duration: 185).looksRomanizedAgainstNativeArtist)
    }

    // MARK: - iTunes 解析

    func testResolvesTheNativeTitleByArtistAndExactLength() async {
        let t = StubTransport(steps: [.ok(itunes([
            ("I Need U Back", 186_351), ("死ぬのがいいわ", 185_573), ("死ぬのがいいわ (Live)", 199_599), ("Be Alright", 184_787),
        ]))])
        let title = await resolver(t).nativeTitle(for: romanized)
        XCTAssertEqual(title, "死ぬのがいいわ")
        XCTAssertEqual(t.requests.count, 1)
        let url = t.requests[0].url!
        XCTAssertEqual(url.host, "itunes.apple.com")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.first { $0.name == "term" }?.value, "藤井風", "只送出歌手名，不帶歌名或長度")
        XCTAssertEqual(items.first { $0.name == "country" }?.value, "JP")
        XCTAssertNil(items.first { $0.name == "duration" })
    }

    func testAmbiguousOrMissingMatchesGiveNil() async {
        let two = StubTransport(steps: [.ok(itunes([("死ぬのがいいわ", 185_500), ("別の曲", 185_600)]))])
        let ambiguous = await resolver(two).nativeTitle(for: romanized)
        XCTAssertNil(ambiguous)
        let none = StubTransport(steps: [.ok(itunes([("死ぬのがいいわ", 190_000)]))])
        let missing = await resolver(none).nativeTitle(for: romanized)
        XCTAssertNil(missing)
        let ascii = StubTransport(steps: [.ok(itunes([("Shinunoga E-wa", 185_573)]))])
        let asciiOnly = await resolver(ascii).nativeTitle(for: romanized)
        XCTAssertNil(asciiOnly, "結果歌名也是 ASCII 就沒有換的意義")
    }

    func testFailuresNeverThrowAndDisabledOrNonQualifyingSendsNothing() async {
        let bad = StubTransport(steps: [.ok("not json")])
        let r1 = await resolver(bad).nativeTitle(for: romanized)
        XCTAssertNil(r1)
        let status = StubTransport(steps: [.status(503)])
        let r2 = await resolver(status).nativeTitle(for: romanized)
        XCTAssertNil(r2)
        let off = StubTransport(steps: [])
        let r3 = await resolver(off, enabled: false).nativeTitle(for: romanized)
        XCTAssertNil(r3)
        let r4 = await resolver(off).nativeTitle(for: LyricsQuery(title: "死ぬのがいいわ", artist: "藤井風", duration: 185))
        XCTAssertNil(r4)
        let r5 = await resolver(off).nativeTitle(for: LyricsQuery(title: "Shinunoga E-Wa", artist: "藤井風", duration: 0))
        XCTAssertNil(r5)
        XCTAssertTrue(off.requests.isEmpty)
    }

    // MARK: - 抓取器

    private struct FixedResolver: NativeTitleResolving {
        var title: String?
        func nativeTitle(for query: LyricsQuery) async -> String? { title }
    }

    private final class RecordingFetcher: LyricsFetching, @unchecked Sendable {
        var titles: [String] = []
        let answer: @Sendable (String) -> PickedLyrics?
        init(answer: @escaping @Sendable (String) -> PickedLyrics?) { self.answer = answer }
        func lyrics(for query: LyricsQuery) async throws -> PickedLyrics? {
            titles.append(query.title)
            return answer(query.title)
        }
    }

    private func picked(_ id: Int) -> PickedLyrics {
        PickedLyrics(candidateID: id, trackName: "t", artistName: "a", script: .neutral, lines: [LRCLine(timeMs: 0, text: "x")])
    }

    func testUsesTheNativeTitleFirstAndFallsBackToTheOriginal() async throws {
        let native = RecordingFetcher { $0 == "死ぬのがいいわ" ? self.picked(1) : self.picked(2) }
        let a = try await NativeTitleLyricsFetcher(base: native, resolver: FixedResolver(title: "死ぬのがいいわ")).lyrics(for: romanized)
        XCTAssertEqual(a?.candidateID, 1)
        XCTAssertEqual(native.titles, ["死ぬのがいいわ"])

        let miss = RecordingFetcher { $0 == "Shinunoga E-Wa" ? self.picked(2) : nil }
        let b = try await NativeTitleLyricsFetcher(base: miss, resolver: FixedResolver(title: "死ぬのがいいわ")).lyrics(for: romanized)
        XCTAssertEqual(b?.candidateID, 2)
        XCTAssertEqual(miss.titles, ["死ぬのがいいわ", "Shinunoga E-Wa"])
    }

    func testPassesThroughWhenNothingToResolve() async throws {
        let base = RecordingFetcher { _ in self.picked(3) }
        let fetcher = NativeTitleLyricsFetcher(base: base, resolver: FixedResolver(title: "不該被用到"))
        _ = try await fetcher.lyrics(for: LyricsQuery(title: "Hello", artist: "Adele", duration: 200))
        _ = try await NativeTitleLyricsFetcher(base: base, resolver: FixedResolver(title: nil)).lyrics(for: romanized)
        XCTAssertEqual(base.titles, ["Hello", "Shinunoga E-Wa"])
    }
}
