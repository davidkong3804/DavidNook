import XCTest
@testable import DavidNookCore

// 樣本皆為自編的虛構句子；所有 HTTP 一律走 StubTransport，不連外網。
// 這些測試走「App 實際使用的管線」（LyricsPipeline）：LRCLIB 用戶端 → 挑選 → 剝檔頭 → 簡繁本地化。

final class LyricsPipelineTests: XCTestCase {

    private let simplifiedLRC = """
    [00:00.00]夜行的灯 - 阿虚
    [00:01.00]词：阿虚
    [00:02.00]曲：阿虚
    [00:12.00]测试句一，我们在夜里行走
    [00:20.00]测试句二，为什么灯还亮着
    [00:28.00]
    [00:40.00]测试句三，后来我发现了光
    """

    private let traditionalLRC = """
    [00:00.00]夜行的燈 - 阿虛
    [00:01.00]詞：阿虛
    [00:12.00]測試句一，我們在夜裡行走
    [00:20.00]測試句二，為什麼燈還亮著
    [00:40.00]測試句三，後來我發現了光
    """

    private func record(id: Int, track: String, artist: String, lrc: String, duration: Double = 223) -> String {
        jsonString(recordObject(id: id, track: track, artist: artist, duration: duration, synced: lrc))
    }

    private func makeRepo(_ transport: StubTransport) -> LyricsRepository {
        LyricsPipeline.makeRepository(
            transport: transport, store: MemoryLyricsCacheStore(),
            appVersion: "9.9.9", sleeper: { _ in }, requestSpacing: 0
        )
    }

    // MARK: - 查詢變體

    func testSimplifiedQueryGetsATraditionalVariant() {
        let variants = LyricsPipeline.queryVariants(for: LyricsQuery(title: "夜行的灯", artist: "阿虚", album: "某专辑", duration: 223))
        XCTAssertEqual(variants.map(\.title), ["夜行的燈"])
        XCTAssertEqual(variants.map(\.artist), ["阿虛"])
        XCTAssertNil(variants.first?.album, "專輯名不帶入變體")
        XCTAssertEqual(variants.first?.duration, 223)
    }

    func testTraditionalQueryGetsASimplifiedVariant() {
        let variants = LyricsPipeline.queryVariants(for: LyricsQuery(title: "夜行的燈", artist: "阿虛", duration: 223))
        XCTAssertEqual(variants.map(\.title), ["夜行的灯"])
        XCTAssertEqual(variants.map(\.artist), ["阿虚"])
    }

    func testMixedQueryGetsBothVariantsTraditionalFirst() {
        // 歌名簡體、歌手繁體 → 混合。
        let variants = LyricsPipeline.queryVariants(for: LyricsQuery(title: "夜行的灯", artist: "阿虛", duration: 223))
        XCTAssertEqual(variants.count, 2)
        XCTAssertEqual(variants[0].title, "夜行的燈")
        XCTAssertEqual(variants[1].title, "夜行的灯")
    }

    func testEnglishQueryGetsNoVariants() {
        XCTAssertEqual(LyricsPipeline.queryVariants(for: LyricsQuery(title: "Night Lamp", artist: "Someone", duration: 180)), [])
    }

    func testJapaneseQueryGetsNoVariants() {
        // 日文歌名含新字體（国・恋）與假名：不是華語，不該送出簡繁變體請求（浪費 LRCLIB 請求）。
        XCTAssertEqual(LyricsPipeline.queryVariants(for: LyricsQuery(title: "恋する国の夜", artist: "テストバンド", duration: 200)), [])
    }

    func testJapaneseCandidateIsClassifiedNeutralByThePicker() throws {
        // 日文同步歌詞（假名＋新字體）：挑選結果的字體屬性是 neutral，不會被當成簡體而排在後面。
        let lrc = "[00:05.00]恋する国の声が聞こえる\n[00:12.00]残酷な夜に会えたなら\n[00:20.00]ありがとう"
        let candidate = LrclibCandidate(
            id: 1, trackName: "恋する国の夜", artistName: "テストバンド", albumName: nil, duration: 200,
            instrumental: false, plainLyrics: nil, syncedLyrics: lrc
        )
        let picked = try XCTUnwrap(LyricsPipeline.makePicker().pick(
            from: [candidate], for: LyricsQuery(title: "恋する国の夜", artist: "テストバンド", duration: 200)
        ))
        XCTAssertEqual(picked.script, .neutral)
    }

    // MARK: - 端到端（用戶端＋挑選＋剝檔頭＋本地化）

    func testTraditionalPlayerTitleFindsSimplifiedLRCLIBEntryViaVariantAndLocalizesToTraditional() async throws {
        let t = StubTransport(steps: [
            .notFound,                                                                    // 原樣（繁體）
            .ok(record(id: 7, track: "夜行的灯", artist: "阿虚", lrc: simplifiedLRC)),     // 簡體變體命中
        ])
        let picked = try await makeRepo(t).lyrics(for: LyricsQuery(title: "夜行的燈", artist: "阿虛", duration: 223.4))

        let result = try XCTUnwrap(picked)
        XCTAssertEqual(result.candidateID, 7)
        XCTAssertEqual(result.script, .simplified)
        XCTAssertEqual(queryDict(t.requests[0])["track_name"], "夜行的燈", "原樣固定最先，且用播放器原值")
        XCTAssertEqual(queryDict(t.requests[1])["track_name"], "夜行的灯")
        XCTAssertEqual(queryDict(t.requests[1])["artist_name"], "阿虚")

        // 檔頭（歌名 - 歌手、詞、曲）被剝掉，第一句是真正的歌詞。
        XCTAssertEqual(result.lines.first?.text, "测试句一，我们在夜里行走")

        // 本地化：簡→繁，行數與順序不變，間奏的空白行保留。
        let localized = try LyricsLocalizer.shared.localize(lines: result.lines.map(\.text))
        XCTAssertEqual(localized.lines, [
            "測試句一，我們在夜裡行走", "測試句二，為什麼燈還亮著", "", "測試句三，後來我發現了光",
        ])
        XCTAssertEqual(localized.script, .simplified)
    }

    func testSimplifiedPlayerTitleFindsTraditionalEntryViaVariantAndLeavesItUntouched() async throws {
        let t = StubTransport(steps: [
            .notFound,
            .ok(record(id: 8, track: "夜行的燈", artist: "阿虛", lrc: traditionalLRC)),
        ])
        let picked = try await makeRepo(t).lyrics(for: LyricsQuery(title: "夜行的灯", artist: "阿虚", duration: 223))

        let result = try XCTUnwrap(picked)
        XCTAssertEqual(result.script, .traditional)
        XCTAssertEqual(queryDict(t.requests[1])["track_name"], "夜行的燈")
        XCTAssertEqual(result.lines.first?.text, "測試句一，我們在夜裡行走", "繁體檔頭（歌名 - 歌手、詞）也要被簡繁不敏感地剝掉")

        // 原生繁體：不被轉壞（只做台灣字形正規化，這裡本來就是台灣字形，輸出應與輸入相同）。
        let localized = try LyricsLocalizer.shared.localize(lines: result.lines.map(\.text))
        XCTAssertEqual(localized.lines, result.lines.map(\.text))
        XCTAssertEqual(localized.script, .traditional)
    }

    func testHeaderStrippingIsScriptInsensitive() async throws {
        // 播放器歌名是繁體，歌詞檔的檔頭行是簡體：仍要剝掉。
        let t = StubTransport(steps: [
            .ok(record(id: 9, track: "夜行的燈", artist: "阿虛", lrc: simplifiedLRC)),
        ])
        let picked = try await makeRepo(t).lyrics(for: LyricsQuery(title: "夜行的燈", artist: "阿虛", duration: 223))
        XCTAssertEqual(try XCTUnwrap(picked).lines.first?.text, "测试句一，我们在夜里行走")
        XCTAssertEqual(t.requests.count, 1, "原樣就命中，不需要變體請求")
    }

    func testEnglishTrackUsesOnlyTheOriginalQueryAndKeepsEnglishLyrics() async throws {
        let lrc = "[00:05.00]first made-up line\n[00:12.00]second made-up line"
        let t = StubTransport(steps: [.ok(record(id: 3, track: "Night Lamp", artist: "Someone", lrc: lrc, duration: 180))])
        let picked = try await makeRepo(t).lyrics(for: LyricsQuery(title: "Night Lamp", artist: "Someone", duration: 180))

        let result = try XCTUnwrap(picked)
        XCTAssertEqual(t.requests.count, 1)
        XCTAssertEqual(result.script, .neutral)
        let localized = try LyricsLocalizer.shared.localize(lines: result.lines.map(\.text))
        XCTAssertEqual(localized.lines, ["first made-up line", "second made-up line"])
    }

    func testRequestsCarryTheAppVersionInUserAgentAndOnlyHitLrclib() async throws {
        let t = StubTransport(steps: [.notFound, .notFound, .ok("[]"), .ok("[]")])
        _ = try await makeRepo(t).lyrics(for: LyricsQuery(title: "夜行的燈", artist: "阿虛", duration: 223))
        XCTAssertFalse(t.requests.isEmpty)
        for request in t.requests {
            XCTAssertEqual(request.url?.host, "lrclib.net")
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), LrclibClient.userAgent(appVersion: "9.9.9"))
        }
    }

    func testPlayerValuesAreSentVerbatimInTheFirstRequest() async throws {
        // 歌名／歌手名保持播放器原值：不轉換、不去音標、不改大小寫。
        let t = StubTransport(steps: [.ok(record(id: 4, track: "Café Noir", artist: "Zoë", lrc: "[00:05.00]a\n[00:09.00]b"))])
        _ = try await makeRepo(t).lyrics(for: LyricsQuery(title: "Café Noir", artist: "Zoë", duration: 223))
        XCTAssertEqual(queryDict(t.requests[0])["track_name"], "Café Noir")
        XCTAssertEqual(queryDict(t.requests[0])["artist_name"], "Zoë")
    }
}
