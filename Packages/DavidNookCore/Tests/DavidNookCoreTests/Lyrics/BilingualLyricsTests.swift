import XCTest
@testable import DavidNookCore

// 日文／韓文歌詞的中文對照（雙語歌詞）。樣本皆為自編的虛構句子；不使用任何真實歌詞。

private let japaneseLines = [
    "夜の駅で猫が眠っている", "窓の外に小さな雨が降る", "", "明日はきっと晴れるだろう", "ひとりで歩く帰り道",
]
private let koreanLines = [
    "밤하늘에 작은 별이 떠 있어", "창문 너머로 비가 내려", "", "내일은 분명 맑을 거야", "혼자 걷는 집으로 가는 길",
]

// MARK: - 來源語言判斷

final class LyricsSourceLanguageTests: XCTestCase {

    func testJapaneseLyricsAreDetected() {
        XCTAssertEqual(LyricsTranslation.sourceLanguage(of: japaneseLines), .japanese)
    }

    func testKoreanLyricsAreDetected() {
        XCTAssertEqual(LyricsTranslation.sourceLanguage(of: koreanLines), .korean)
    }

    func testChineseLyricsAreNotForeign() {
        XCTAssertNil(LyricsTranslation.sourceLanguage(of: ["夜行的燈亮起來", "我在這裡等你", "", "明天會更好"]))
    }

    func testEnglishLyricsAreNotForeign() {
        XCTAssertNil(LyricsTranslation.sourceLanguage(of: ["a made-up line", "another made-up line"]))
    }

    func testChineseSongWithOneJapaneseLineIsNotForeign() {
        var lines = (0..<10).map { "這是第\($0)句虛構的歌詞" }
        lines.insert("夜の駅で猫が眠っている", at: 4)
        XCTAssertNil(LyricsTranslation.sourceLanguage(of: lines))
    }

    func testJapaneseSongWithOneEnglishLineIsStillJapanese() {
        XCTAssertEqual(LyricsTranslation.sourceLanguage(of: japaneseLines + ["oh yeah"]), .japanese)
    }

    func testMixedLyricsPickTheMajorityLanguage() {
        let lines = koreanLines + Array(japaneseLines.prefix(2))
        XCTAssertEqual(LyricsTranslation.sourceLanguage(of: lines), .korean)
    }

    func testEmptyAndBlankLyricsHaveNoLanguage() {
        XCTAssertNil(LyricsTranslation.sourceLanguage(of: []))
        XCTAssertNil(LyricsTranslation.sourceLanguage(of: ["", "  "]))
    }
}

// MARK: - 中文翻譯判斷、請求與對齊

final class LyricsTranslationHelpersTests: XCTestCase {

    func testChineseTextIsAChineseTranslation() {
        XCTAssertTrue(LyricsTranslation.isChineseTranslation("夜晚的車站裡貓正在睡覺"))
        XCTAssertTrue(LyricsTranslation.isChineseTranslation("夜晚的车站里猫正在睡觉"))
    }

    func testJapaneseKoreanAndLatinTextAreNotChineseTranslations() {
        XCTAssertFalse(LyricsTranslation.isChineseTranslation("夜の駅で猫が眠っている"))
        XCTAssertFalse(LyricsTranslation.isChineseTranslation("밤하늘에 작은 별이 떠 있어"))
        XCTAssertFalse(LyricsTranslation.isChineseTranslation("The cat sleeps at the night station"))
        XCTAssertFalse(LyricsTranslation.isChineseTranslation(""))
    }

    func testRequestsSkipBlankLinesAndKeepOriginalIndexes() {
        let requests = LyricsTranslation.requests(for: ["甲", "", "  ", "乙"])
        XCTAssertEqual(requests.map(\.index), [0, 3])
        XCTAssertEqual(requests.map(\.text), ["甲", "乙"])
    }

    func testAlignPutsTranslationsBackAtTheirLinesAndLeavesBlanksEmpty() {
        let lines = ["a", "", "b", "c"]
        let requests = LyricsTranslation.requests(for: lines)
        XCTAssertEqual(
            LyricsTranslation.align(count: lines.count, requests: requests, translated: ["一", "二", "三"]),
            ["一", "", "二", "三"]
        )
    }

    func testAlignRejectsAResultOfTheWrongSize() {
        let requests = LyricsTranslation.requests(for: ["a", "b"])
        XCTAssertNil(LyricsTranslation.align(count: 2, requests: requests, translated: ["一"]))
        XCTAssertNil(LyricsTranslation.align(count: 2, requests: requests, translated: ["一", "二", "三"]))
    }
}

// MARK: - LRCLIB 版本本身附中文翻譯

final class EmbeddedTranslationTests: XCTestCase {

    private func synced(_ rows: [(Int, String)]) -> String {
        rows.map { row in
            let seconds = row.0 / 1000
            return String(format: "[%02d:%02d.00]", seconds / 60, seconds % 60) + row.1
        }.joined(separator: "\n")
    }

    /// 每個原文行後面接一行翻譯，兩行共用時間戳（雙語檔慣例）。
    private func bilingual(original: [String], translation: [String]) -> String {
        synced(zip(original, translation).enumerated().flatMap { index, pair -> [(Int, String)] in
            let t = 10_000 + index * 6_000
            return [(t, pair.0), (t, pair.1)]
        })
    }

    private func pick(_ syncedLyrics: String) -> PickedLyrics? {
        let candidate = LrclibCandidate(
            id: 1, trackName: "T", artistName: "A", albumName: nil, duration: 200,
            instrumental: false, plainLyrics: nil, syncedLyrics: syncedLyrics
        )
        return LyricsPipeline.makePicker().pick(from: [candidate], for: LyricsQuery(title: "T", artist: "A", duration: 200))
    }

    private let originals = (0..<6).map { "夜の駅で猫が眠っている\($0)" }
    private let chinese = (0..<6).map { "夜晚的車站裡貓正在睡覺\($0)" }

    func testJapaneseFileWithChineseTranslationKeepsOriginalAndExposesTranslation() throws {
        let picked = try XCTUnwrap(pick(bilingual(original: originals, translation: chinese)))
        XCTAssertEqual(picked.lines.map(\.text), originals)
        XCTAssertEqual(picked.embeddedTranslations, chinese)
    }

    func testEmbeddedTranslationsStayAlignedWithLinesAcrossBlankMarkers() throws {
        var rows: [(Int, String)] = []
        for (index, pair) in zip(originals, chinese).enumerated() {
            rows.append((10_000 + index * 6_000, pair.0))
            rows.append((10_000 + index * 6_000, pair.1))
        }
        rows.append((60_000, ""))                       // 結尾的空白標記
        let picked = try XCTUnwrap(pick(synced(rows)))
        XCTAssertEqual(picked.embeddedTranslations?.count, picked.lines.count)
        XCTAssertEqual(picked.embeddedTranslations?.last, "")
    }

    func testJapaneseFileWithEnglishTranslationHasNoEmbeddedTranslation() throws {
        let english = (0..<6).map { "The cat sleeps at the night station \($0)" }
        let picked = try XCTUnwrap(pick(bilingual(original: originals, translation: english)))
        XCTAssertEqual(picked.lines.map(\.text), originals)
        XCTAssertNil(picked.embeddedTranslations)
    }

    func testEnglishFileWithChineseTranslationHasNoEmbeddedTranslation() throws {
        // 英文歌不在支援範圍：原文英文、翻譯中文的雙語檔照舊只留原文。
        let english = (0..<6).map { "made-up original \($0)" }
        let picked = try XCTUnwrap(pick(bilingual(original: english, translation: chinese)))
        XCTAssertNil(picked.embeddedTranslations)
    }

    func testPlainJapaneseFileHasNoEmbeddedTranslation() throws {
        let picked = try XCTUnwrap(pick(synced(originals.enumerated().map { (10_000 + $0.offset * 6_000, $0.element) })))
        XCTAssertNil(picked.embeddedTranslations)
    }

    func testPickedLyricsWithoutTheNewFieldStillDecodes() throws {
        // 舊版 App 寫進磁碟快取的歌詞沒有 embeddedTranslations 欄位：必須照常解碼。
        let picked = PickedLyrics(candidateID: 1, trackName: "T", artistName: "A", script: .neutral, lines: [L(1000, "x")])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(picked)) as? [String: Any])
        object.removeValue(forKey: "embeddedTranslations")
        let data = try JSONSerialization.data(withJSONObject: object)
        XCTAssertEqual(try JSONDecoder().decode(PickedLyrics.self, from: data), picked)
    }

    func testPickedLyricsRoundTripsEmbeddedTranslations() throws {
        var picked = PickedLyrics(candidateID: 1, trackName: "T", artistName: "A", script: .neutral, lines: [L(1000, "x")])
        picked.embeddedTranslations = ["甲"]
        let data = try JSONEncoder().encode(picked)
        XCTAssertEqual(try JSONDecoder().decode(PickedLyrics.self, from: data).embeddedTranslations, ["甲"])
    }
}

// MARK: - 翻譯快取

final class TranslationCacheStoreTests: XCTestCase {

    private let key = TrackKey(title: "夜行的燈", artist: "阿虛", duration: 223.4)
    private let otherKey = TrackKey(title: "Night Lamp", artist: "Someone", duration: 180)
    private let entry = TranslationCacheEntry(source: .japanese, lines: ["甲", "", "乙"])

    private func makeStore() throws -> (store: FileLyricsCacheStore, directory: URL) {
        let root = try makeTempDirectory(for: self)
        let directory = root.appendingPathComponent("Lyrics", isDirectory: true)
        return (try FileLyricsCacheStore(directory: directory), directory)
    }

    func testRoundTrip() throws {
        let (store, _) = try makeStore()
        store.storeTranslation(entry, for: key)
        XCTAssertEqual(store.translation(for: key), entry)
    }

    func testUnknownKeyIsAMiss() throws {
        let (store, _) = try makeStore()
        store.storeTranslation(entry, for: key)
        XCTAssertNil(store.translation(for: otherKey))
    }

    func testLyricsAndTranslationOfTheSameTrackDoNotCollide() throws {
        let (store, _) = try makeStore()
        let lyrics = PickedLyrics(candidateID: 5, trackName: "夜行的燈", artistName: "阿虛", script: .neutral, lines: [L(1000, "x")])
        store.store(LyricsCacheEntry(lyrics: lyrics, storedAt: Date(timeIntervalSinceReferenceDate: 1)), for: key)
        store.storeTranslation(entry, for: key)
        XCTAssertEqual(store.entry(for: key)?.lyrics, lyrics)
        XCTAssertEqual(store.translation(for: key), entry)
    }

    func testFileIsPrivateAndClearedByRemoveAll() throws {
        let (store, directory) = try makeStore()
        store.storeTranslation(entry, for: key)
        let names = directoryEntries(directory)
        XCTAssertEqual(names.count, 1)
        XCTAssertEqual(try posixPermissions(of: directory.appendingPathComponent(names[0])), 0o600)
        XCTAssertEqual(try store.removeAll(), 1)
        XCTAssertNil(store.translation(for: key))
    }

    func testCorruptTranslationFileIsAMissAndIsRemoved() throws {
        let (store, directory) = try makeStore()
        store.storeTranslation(entry, for: key)
        let file = directory.appendingPathComponent(directoryEntries(directory)[0])
        try Data("not json".utf8).write(to: file)
        XCTAssertNil(store.translation(for: key))
        XCTAssertTrue(directoryEntries(directory).isEmpty)
    }

    func testMemoryStoreRoundTrip() {
        let store = MemoryTranslationCacheStore()
        XCTAssertNil(store.translation(for: key))
        store.storeTranslation(entry, for: key)
        XCTAssertEqual(store.translation(for: key), entry)
        XCTAssertNil(store.translation(for: otherKey))
    }
}

// MARK: - 翻譯計畫（要用內嵌、用快取、還是現翻）

final class TranslationPlanTests: XCTestCase {

    private let lines = japaneseLines
    private let embedded = ["甲", "乙", "", "丙", "丁"]

    func testNonForeignLyricsNeedNothing() {
        let plan = LyricsTranslation.plan(
            lines: ["夜行的燈亮起來", "我在這裡等你"], embedded: nil, cached: nil, allowTranslating: true
        )
        XCTAssertEqual(plan, .none)
    }

    func testEmbeddedTranslationWinsOverEverything() {
        let cached = TranslationCacheEntry(source: .japanese, lines: ["x", "x", "", "x", "x"])
        let plan = LyricsTranslation.plan(lines: lines, embedded: embedded, cached: cached, allowTranslating: false)
        XCTAssertEqual(plan, .useEmbedded(embedded))
    }

    func testEmbeddedTranslationOfTheWrongSizeIsIgnored() {
        let plan = LyricsTranslation.plan(lines: lines, embedded: ["甲"], cached: nil, allowTranslating: true)
        guard case .translate(.japanese, let requests) = plan else { return XCTFail("expected translate, got \(plan)") }
        XCTAssertEqual(requests.map(\.index), [0, 1, 3, 4])
    }

    func testCachedTranslationIsUsedWithoutTranslatingAgain() {
        let cached = TranslationCacheEntry(source: .japanese, lines: embedded)
        let plan = LyricsTranslation.plan(lines: lines, embedded: nil, cached: cached, allowTranslating: true)
        XCTAssertEqual(plan, .useCached(embedded))
    }

    func testCachedTranslationForADifferentLanguageOrSizeIsIgnored() {
        let wrongLanguage = TranslationCacheEntry(source: .korean, lines: embedded)
        let wrongSize = TranslationCacheEntry(source: .japanese, lines: ["甲"])
        for cached in [wrongLanguage, wrongSize] {
            let plan = LyricsTranslation.plan(lines: lines, embedded: nil, cached: cached, allowTranslating: true)
            guard case .translate = plan else { return XCTFail("expected translate, got \(plan)") }
        }
    }

    func testNothingIsTranslatedWhileTranslatingIsNotAllowed() {
        // 「只顯示原文」開著時不翻譯（省電、省時間）；關掉後才會翻。
        XCTAssertEqual(LyricsTranslation.plan(lines: lines, embedded: nil, cached: nil, allowTranslating: false), .none)
    }

    func testKoreanLyricsTranslateFromKorean() {
        let plan = LyricsTranslation.plan(lines: koreanLines, embedded: nil, cached: nil, allowTranslating: true)
        guard case .translate(.korean, let requests) = plan else { return XCTFail("expected translate, got \(plan)") }
        XCTAssertEqual(requests.count, 4)
    }
}
