import XCTest
@testable import DavidNookCore

/// 雙語（逐行附翻譯）LRC：原文行與翻譯行共用同一個時間戳。真實資料稽核發現這類版本會被 `/api/get` 直接選中，
/// 兩行同時間，時間軸「目前行」會跳到翻譯行（原文一閃而過）。樣本全為自編的虛構句子。
final class LyricsTranslationCollapserTests: XCTestCase {

    /// 前 N 行是「原文 / 翻譯」成對、同時間戳。
    private func bilingual(pairs: Int) -> [LRCLine] {
        var lines: [LRCLine] = []
        for i in 0..<pairs {
            let t = 10_000 + i * 6_000
            lines.append(L(t, "made-up original \(i)"))
            lines.append(L(t, "虚构的翻译 \(i)"))
        }
        return lines
    }

    // MARK: - 單元

    func testKeepsOnlyTheFirstLineOfEachSameTimestampGroupInABilingualFile() {
        let result = LyricsTranslationCollapser.collapse(bilingual(pairs: 6))
        XCTAssertEqual(result.lines.map(\.text), (0..<6).map { "made-up original \($0)" })
        XCTAssertEqual(result.dropped.count, 6)
        XCTAssertTrue(result.dropped.allSatisfy { $0.text.hasPrefix("虚构的翻译") })
    }

    func testKeepsTimestampsOfTheKeptLines() {
        let result = LyricsTranslationCollapser.collapse(bilingual(pairs: 4))
        XCTAssertEqual(result.lines.map(\.timeMs), [10_000, 16_000, 22_000, 28_000])
    }

    func testFewSameTimestampLinesAreLeftAlone() {
        // 一份普通歌詞偶爾有兩行同時間（重疊的合唱）：低於門檻不處理，不能誤刪真歌詞。
        var lines = (0..<12).map { L(10_000 + $0 * 5_000, "line \($0)") }
        lines.insert(L(15_000, "overlapping line"), at: 2)       // 與 "line 1" 同時間
        let result = LyricsTranslationCollapser.collapse(lines)
        XCTAssertEqual(result.lines, lines)
        XCTAssertTrue(result.dropped.isEmpty)
    }

    func testThreeOrMorePairsIsRequired() {
        // 只有 2 組（占 100%）仍不處理：樣本太少，無法判定是雙語檔。
        let lines = bilingual(pairs: 2)
        XCTAssertEqual(LyricsTranslationCollapser.collapse(lines).lines, lines)
    }

    func testBlankMarkersAreKeptAndDoNotBreakGrouping() {
        var lines = bilingual(pairs: 4)
        lines.append(L(40_000, ""))
        let result = LyricsTranslationCollapser.collapse(lines)
        XCTAssertEqual(result.lines.count, 5)
        XCTAssertTrue(result.lines.last?.isBlank ?? false)
    }

    func testEmptyInput() {
        XCTAssertTrue(LyricsTranslationCollapser.collapse([]).lines.isEmpty)
    }

    // MARK: - 與 Picker 整合

    func testPickerCollapsesBilingualLyricsBeforeClassifyingScript() {
        // 英文原文 + 簡體中文翻譯：不收合會被判成簡體並把翻譯行轉成繁體；收合後只剩英文原文（neutral）。
        let synced = bilingual(pairs: 6).map { line -> String in
            let m = line.timeMs / 1000
            return String(format: "[%02d:%02d.00]", m / 60, m % 60) + line.text
        }.joined(separator: "\n")
        let candidate = LrclibCandidate(
            id: 1, trackName: "T", artistName: "A", albumName: nil, duration: 200,
            instrumental: false, plainLyrics: nil, syncedLyrics: synced
        )
        let picked = LyricsPipeline.makePicker().pick(
            from: [candidate], for: LyricsQuery(title: "T", artist: "A", duration: 200)
        )
        XCTAssertEqual(picked?.lines.count, 6)
        XCTAssertEqual(picked?.script, .neutral)
        XCTAssertTrue(picked?.lines.allSatisfy { $0.text.hasPrefix("made-up original") } ?? false)
    }
}
