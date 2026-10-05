import XCTest
@testable import DavidNookCore

final class LyricsOverridesTests: XCTestCase {
    /// 把「沒被覆寫的片段」標成 [..]，方便斷言覆寫表如何切段。
    private func marked(_ overrides: LyricsOverrides, _ text: String) -> String {
        overrides.apply(to: text) { "[" + $0 + "]" }
    }

    // MARK: - 解析

    func testParsesSimpleEntries() {
        let overrides = LyricsOverrides(parsing: "发如雪=髮如雪\n发端=髮端\n")
        XCTAssertEqual(overrides.entries.map(\.key), ["发如雪", "发端"])
        XCTAssertEqual(overrides.entries.map(\.value), ["髮如雪", "髮端"])
        XCTAssertTrue(overrides.duplicateKeys.isEmpty)
        XCTAssertTrue(overrides.malformedLineNumbers.isEmpty)
    }

    func testIgnoresCommentsAndBlankLinesAndTrimsWhitespace() {
        let text = """
        # 這是註解
        \u{20}
        发丝 = 髮絲\u{20}
          # 前面有空白的註解
        白发=白髮
        """
        let overrides = LyricsOverrides(parsing: text)
        XCTAssertEqual(overrides.entries.map(\.key), ["发丝", "白发"])
        XCTAssertEqual(overrides.entries.map(\.value), ["髮絲", "白髮"])
        XCTAssertTrue(overrides.malformedLineNumbers.isEmpty)
    }

    func testHandlesCRLF() {
        let overrides = LyricsOverrides(parsing: "发如雪=髮如雪\r\n发端=髮端\r\n")
        XCTAssertEqual(overrides.entries.map(\.value), ["髮如雪", "髮端"])
    }

    func testReportsMalformedLinesWithLineNumbers() {
        let overrides = LyricsOverrides(parsing: "没有等號\n=沒有鍵\n沒有值=\n发端=髮端\n")
        XCTAssertEqual(overrides.malformedLineNumbers, [1, 2, 3])
        XCTAssertEqual(overrides.entries.map(\.key), ["发端"])
    }

    func testReportsDuplicateKeysAndLastOneWins() {
        let overrides = LyricsOverrides(parsing: "发端=髮端\n发端=發端\n")
        XCTAssertEqual(overrides.duplicateKeys, ["发端"])
        XCTAssertEqual(overrides.apply(to: "发端") { $0 }, "發端")
    }

    // MARK: - 套用（最長匹配優先，未匹配片段交還給轉換器）

    func testNoMatchPassesWholeTextToConverterOnce() {
        let overrides = LyricsOverrides(parsing: "发如雪=髮如雪")
        XCTAssertEqual(marked(overrides, "你好世界"), "[你好世界]")
        XCTAssertEqual(marked(overrides, ""), "")
    }

    func testReplacesMatchAndSplitsRest() {
        let overrides = LyricsOverrides(parsing: "发如雪=髮如雪")
        XCTAssertEqual(marked(overrides, "我发如雪的夜"), "[我]髮如雪[的夜]")
        XCTAssertEqual(marked(overrides, "发如雪"), "髮如雪")
    }

    func testAdjacentAndRepeatedMatches() {
        let overrides = LyricsOverrides(parsing: "发如雪=髮如雪\n发端=髮端")
        XCTAssertEqual(marked(overrides, "发如雪发端"), "髮如雪髮端")
        XCTAssertEqual(marked(overrides, "发端,发端"), "髮端[,]髮端")
    }

    func testLongestMatchWinsRegardlessOfFileOrder() {
        let shortFirst = LyricsOverrides(parsing: "发=發\n发如雪=髮如雪")
        let longFirst = LyricsOverrides(parsing: "发如雪=髮如雪\n发=發")
        for overrides in [shortFirst, longFirst] {
            XCTAssertEqual(marked(overrides, "发如雪"), "髮如雪")
            XCTAssertEqual(marked(overrides, "发现"), "發[现]")
        }
    }

    func testLeftmostMatchWinsBeforeLongerOverlappingLaterMatch() {
        // 「头发」先於「发现」：從左到右掃描，不會把「发」讓給後面的詞。
        let overrides = LyricsOverrides(parsing: "头发=頭髮\n发现=發現")
        XCTAssertEqual(marked(overrides, "头发现在"), "頭髮[现在]")
    }

    func testIdentityEntriesProtectTextFromOpenCC() {
        // 值等於鍵也合法：用來避免 OpenCC 把這段字改壞（片段不會交給轉換器）。
        let overrides = LyricsOverrides(parsing: "手托=手托")
        XCTAssertEqual(marked(overrides, "那只手托着"), "[那只]手托[着]")
    }

    func testSupplementaryScalarsAreHandled() {
        let overrides = LyricsOverrides(parsing: "发端=髮端")
        XCTAssertEqual(marked(overrides, "😀发端😀"), "[😀]髮端[😀]")
    }

    // MARK: - 內建覆寫表（Resources/lyrics_overrides.txt）

    func testBundledTableLoadsAndIsWellFormed() {
        let overrides = LyricsOverrides.bundled
        XCTAssertGreaterThanOrEqual(overrides.entries.count, 40)
        XCTAssertTrue(overrides.malformedLineNumbers.isEmpty, "格式錯誤的行：\(overrides.malformedLineNumbers)")
        XCTAssertTrue(overrides.duplicateKeys.isEmpty, "重複的鍵：\(overrides.duplicateKeys)")
    }

    func testBundledTableContainsRequiredEntries() {
        let table = Dictionary(
            LyricsOverrides.bundled.entries.map { ($0.key, $0.value) },
            uniquingKeysWith: { _, last in last }
        )
        XCTAssertEqual(table["发如雪"], "髮如雪")
        XCTAssertEqual(table["发端"], "髮端")
        XCTAssertEqual(table["发丝"], "髮絲")
        XCTAssertEqual(table["白发"], "白髮")
        XCTAssertEqual(table["头发"], "頭髮")
        XCTAssertEqual(table["青丝白发"], "青絲白髮")
        // 審稿補充
        let reviewed: [String: String] = [
            "凄美": "淒美", "谷堆": "穀堆", "泪干": "淚乾", "泪已干": "淚已乾", "泪都干": "淚都乾",
            "里美丽": "裡美麗", "千里美": "千里美",
            "书本里": "書本裡", "课本里": "課本裡", "剧本里": "劇本裡", "日记本里": "日記本裡", "笔记本里": "筆記本裡",
            "舞台": "舞台", "站台": "站台", "月台": "月台", "阳台": "陽台", "后台": "後台", "讲台": "講台",
            "电台": "電台", "台词": "台詞", "台上": "台上", "台下": "台下", "台前": "台前",
            "台风": "颱風", "柜台": "櫃檯", "了解": "了解",
        ]
        for (key, value) in reviewed {
            XCTAssertEqual(table[key], value, "覆寫表缺少或錯誤：\(key)")
        }
    }

    func testBundledTableContainsFuEntries() {
        // 「复」：重复／反复／复杂／复制／复习（一般歌詞語境都成立）；原生繁體路徑殘留的「复」靠它們修。
        let table = Dictionary(
            LyricsOverrides.bundled.entries.map { ($0.key, $0.value) },
            uniquingKeysWith: { _, last in last }
        )
        let expected: [String: String] = [
            "重复": "重複", "反复": "反覆", "复杂": "複雜", "复制": "複製", "复习": "複習",
        ]
        for (key, value) in expected {
            XCTAssertEqual(table[key], value, "覆寫表缺少或錯誤：\(key)")
        }
    }

    func testBundledTableDoesNotContainAmbiguousFuWords() {
        // 「回复」（回覆／回復）與「恢复」（恢復）歧義大，刻意不放。
        let keys = Set(LyricsOverrides.bundled.entries.map(\.key))
        for key in ["回复", "恢复", "复", "复原", "答复"] {
            XCTAssertFalse(keys.contains(key), "不該有歧義條目：\(key)")
        }
    }

    // MARK: - 原生繁體路徑用的子集合

    func testRestrictedSubsetKeepsOnlyEntriesWhoseKeyContainsASimplifiedForm() {
        let overrides = LyricsOverrides(parsing: "重复=重複\n海里=海裡\n托=托\n台上=台上\n泪干=淚乾\n谷堆=穀堆\n复习=複習")
        let subset = overrides.restrictedToSimplifiedKeys { "复泪".unicodeScalars.contains($0) }
        XCTAssertEqual(Set(subset.entries.map(\.key)), ["重复", "泪干", "复习"])
        XCTAssertEqual(subset.apply(to: "重复海里谷堆泪干") { $0 }, "重複海里谷堆淚乾")
    }

    func testRestrictedSubsetDropsIdentityEntriesEvenWhenTheKeyHasASimplifiedForm() {
        // 保護條目（值＝鍵）在原生繁體路徑沒有意義（t2tw 本來就不會動它們）。
        let overrides = LyricsOverrides(parsing: "复=复\n重复=重複")
        let subset = overrides.restrictedToSimplifiedKeys { $0 == "复" }
        XCTAssertEqual(subset.entries.map(\.key), ["重复"])
    }

    func testBundledValuesAreTraditional() {
        // 覆寫輸出必須是繁體：不含任何簡體專有字。
        let detector = ChineseScriptDetector()
        for entry in LyricsOverrides.bundled.entries {
            XCTAssertEqual(
                detector.evidence(in: entry.value).simplified, 0,
                "\(entry.key)=\(entry.value) 的值含簡體專有字"
            )
        }
    }

    func testBundledKeysAreNotEmptyAndValuesAreNotEmpty() {
        for entry in LyricsOverrides.bundled.entries {
            XCTAssertFalse(entry.key.isEmpty)
            XCTAssertFalse(entry.value.isEmpty)
        }
    }

    /// 每一個內建條目都要被「實際轉換結果」覆蓋到：用條目的鍵單獨轉換，結果必須等於值。
    func testEveryBundledEntryProducesItsValue() throws {
        let converter = try LyricsChineseConverter(mode: .conservative, overrides: .bundled)
        for entry in LyricsOverrides.bundled.entries {
            XCTAssertEqual(converter.convert(entry.key), entry.value, "\(entry.key)")
        }
    }

    /// 同一條目在句子中（左右夾雜其他中文字）也要保持結果，且不影響鄰近字的轉換。
    func testBundledEntriesInsideSentences() throws {
        let converter = try LyricsChineseConverter(mode: .conservative, overrides: .bundled)
        for entry in LyricsOverrides.bundled.entries {
            let output = converter.convert("我" + entry.key + "们")
            XCTAssertEqual(output, "我" + entry.value + "們", "\(entry.key)")
        }
    }

    /// 內建表所有條目的值，經 .variantsOnly（原生繁體路徑）後不得被改動：確保輸出是穩定的繁體。
    func testBundledValuesAreStableUnderVariantsNormalization() throws {
        let converter = try LyricsChineseConverter(mode: .variantsOnly, overrides: .bundled)
        for entry in LyricsOverrides.bundled.entries {
            XCTAssertEqual(converter.convert(entry.value), entry.value, "\(entry.key)=\(entry.value)")
        }
    }
}
