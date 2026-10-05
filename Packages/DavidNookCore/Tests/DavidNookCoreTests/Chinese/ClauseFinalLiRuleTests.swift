import XCTest
@testable import DavidNookCore

/// 「里」子句尾啟發式：「里」後面是標點／空白／行尾，且前一字是漢字、不在排除集合時 → 「裡」。
/// 真實資料稽核：OpenCC 不轉「書本里」「電影里」，原生繁體歌詞也常殘留「場景里」「秋涼里」。樣本全為自編句子。
final class ClauseFinalLiRuleTests: XCTestCase {

    private func assertRule(_ cases: [(String, String)], file: StaticString = #filePath, line: UInt = #line) {
        for (input, expected) in cases {
            XCTAssertEqual(ClauseFinalLiRule.apply(to: input), expected, "輸入：\(input)", file: file, line: line)
        }
    }

    // MARK: - 正例：子句尾的「里」→「裡」

    func testClauseFinalLiBecomesLi() {
        assertRule([
            ("在我心里", "在我心裡"),
            ("場景里", "場景裡"),
            ("秋涼里", "秋涼裡"),
            ("书本里", "书本裡"),
            ("家里", "家裡"),
            ("在海里", "在海裡"),
            ("村里", "村裡"),
        ])
    }

    func testPunctuationWhitespaceAndLineEndAreClauseBoundaries() {
        assertRule([
            ("在我心里，", "在我心裡，"),
            ("家里。", "家裡。"),
            ("你在哪里？", "你在哪裡？"),
            ("心里！", "心裡！"),
            ("心里、手里；眼里：", "心裡、手裡；眼裡："),
            ("「在心里」", "「在心裡」"),
            ("（在家里）", "（在家裡）"),
            ("在心里…", "在心裡…"),
            ("在心里～", "在心裡～"),
            ("在心里, 在手里. ", "在心裡, 在手裡. "),
            ("在家里 你在哪", "在家裡 你在哪"),
            ("在家里\u{3000}你在哪", "在家裡\u{3000}你在哪"),
            ("\"在心里\"", "\"在心裡\""),
        ])
    }

    func testEveryClauseInALineIsHandledIndependently() {
        assertRule([
            ("家里，千里，心里", "家裡，千里，心裡"),
            ("在家里，想著萬里之外，在心里", "在家裡，想著萬里之外，在心裡"),
            ("在家里想著萬里之外，在心里", "在家里想著萬里之外，在心裡"),   // 「家里想」不是子句尾
        ])
    }

    // MARK: - 反例：保留「里」

    func testNumeralsAndMeasureWordsKeepLi() {
        assertRule([
            ("千里", "千里"), ("萬里", "萬里"), ("万里", "万里"), ("公里", "公里"), ("英里", "英里"),
            ("三里", "三里"), ("半里", "半里"), ("幾里", "幾里"), ("几里", "几里"), ("兩里", "兩里"),
            ("十里", "十里"), ("百里", "百里"), ("億里", "億里"), ("5里", "5里"), ("５里", "５里"),
            ("相隔千里，", "相隔千里，"), ("跑了十公里。", "跑了十公里。"),
        ])
    }

    func testNeighborhoodAndHometownWordsKeepLi() {
        assertRule([
            ("鄰里", "鄰里"), ("邻里", "邻里"), ("鄉里", "鄉里"), ("乡里", "乡里"), ("故里", "故里"),
            ("回到故里，", "回到故里，"), ("鄰里。", "鄰里。"),
        ])
    }

    func testLiFollowedByACharacterIsNotClauseFinal() {
        assertRule([
            ("十里桃花", "十里桃花"), ("里程", "里程"), ("里約", "里約"), ("里斯本", "里斯本"), ("里昂", "里昂"),
            ("心里想着你", "心里想着你"), ("家里的灯", "家里的灯"), ("家里ok", "家里ok"), ("家里2號", "家里2號"),
        ])
    }

    func testLiWithoutAHanCharacterBeforeItIsLeftAlone() {
        assertRule([
            ("里", "里"), ("，里", "，里"), (" 里", " 里"), ("A里", "A里"), ("里，", "里，"), ("", ""),
        ])
    }

    func testTextWithoutLiIsReturnedUnchanged() {
        assertRule([("我們一起走過這條安靜的街", "我們一起走過這條安靜的街"), ("Hello world", "Hello world")])
    }

    func testRuleIsIdempotent() {
        for text in ["在我心里", "家里，千里，心里", "鄰里", "书本里。"] {
            let once = ClauseFinalLiRule.apply(to: text)
            XCTAssertEqual(ClauseFinalLiRule.apply(to: once), once)
        }
    }
}
