import XCTest
@testable import DavidNookCore

/// 「里→裡」詞級規則：里前一字（漢字）不在「前綴排除集」、後一字不在「後綴排除集」、也不屬於整詞保護清單 → 「裡」。
/// 真實資料稽核：原生繁體歌詞殘留的「里」後面都接字（心里卻…、家里沒有…、場景里出現…），子句尾啟發式一行都改不到。
/// 樣本全為自編句子。
final class LiWordRuleTests: XCTestCase {

    private func assertRule(_ cases: [(String, String)], file: StaticString = #filePath, line: UInt = #line) {
        for (input, expected) in cases {
            XCTAssertEqual(LiWordRule.apply(to: input), expected, "輸入：\(input)", file: file, line: line)
        }
    }

    private func assertKept(_ inputs: [String], file: StaticString = #filePath, line: UInt = #line) {
        assertRule(inputs.map { ($0, $0) }, file: file, line: line)
    }

    // MARK: - 正例：里＋後接字也要轉（詞級）

    func testLiFollowedByACharacterBecomesLi() {
        assertRule([
            ("我的心里卻一直下著雨", "我的心裡卻一直下著雨"),
            ("家里沒有人等我", "家裡沒有人等我"),
            ("場景里出現了你", "場景裡出現了你"),
            ("秋涼里帶著微風", "秋涼裡帶著微風"),
            ("心里想著你", "心裡想著你"),
            ("手里的傘", "手裡的傘"),
            ("夜里看雪", "夜裡看雪"),
            ("夢里面有你", "夢裡面有你"),
            ("书本里夹着枫叶", "书本裡夹着枫叶"),
            ("在海里游泳", "在海裡游泳"),
        ])
    }

    func testLiAtClauseEndBecomesLi() {
        assertRule([
            ("在我心里", "在我心裡"),
            ("在我心里，", "在我心裡，"),
            ("你在哪里？", "你在哪裡？"),
            ("家里。", "家裡。"),
            ("（在家里）", "（在家裡）"),
            ("「在心里」", "「在心裡」"),
            ("在心里…", "在心裡…"),
            ("在家里 你在哪", "在家裡 你在哪"),
            ("在家里\u{3000}你在哪", "在家裡\u{3000}你在哪"),
            ("村里", "村裡"),
        ])
    }

    func testEveryLiInALineIsHandledIndependently() {
        assertRule([
            ("這里那里哪里", "這裡那裡哪裡"),
            ("家里，千里，心里", "家裡，千里，心裡"),
            ("在家里想著萬里之外，在心里", "在家裡想著萬里之外，在心裡"),
            ("心里想著千里外的你，手里握著十里桃花", "心裡想著千里外的你，手裡握著十里桃花"),
        ])
    }

    // MARK: - 反例：數詞與量詞、單位、整詞保護（任務指定的全部反例）

    func testNumeralsAndMeasureWordsKeepLi() {
        assertKept([
            "千里", "萬里", "万里", "百里", "十里", "三里", "半里", "幾里", "几里", "兩里", "億里", "5里", "５里",
            "相隔千里的我們", "萬里無雲", "十里桃花開了", "要幾里路才到", "走了百里山路",
        ])
    }

    func testUnitsKeepLi() {
        assertKept(["公里", "英里", "跑了五公里", "時速六十英里", "公里外的海", "英里外的家"])
    }

    func testNeighborhoodAndHometownWordsKeepLi() {
        assertKept(["鄰里", "邻里", "鄉里", "乡里", "故里", "他住在鄰里之間", "回到故里去", "鄰里相望", "鄉里鄉親"])
    }

    func testLiAsFirstPartOfAWordKeepsLi() {
        // 這些詞的「里」前面都有字，靠後綴排除集／整詞保護才保得住。
        assertKept([
            "走過里程碑", "跑完里程", "找里長伯伯", "參加里民大會", "去里約看球", "去里约热内卢", "去里昂旅行", "去里斯本",
        ])
    }

    func testTransliteratedAndProperNamesKeepLi() {
        assertKept([
            "阿里山", "阿里山的日出", "阿里巴巴", "阿里巴巴與四十大盜", "斯里蘭卡", "斯里兰卡", "斯里蘭卡的海",
            "卡路里", "歇斯底里地喊", "香格里拉", "西西里島", "克里姆林宮", "烏蘇里江", "佛羅里達", "艾里克",
        ])
    }

    func testPrefixExclusionSetKeepsLi() {
        // 轉寫與專名常見前綴（阿 斯 加 卡 艾 哈 安 莫 馬 俄 哥 約 波 德 塞 達 賽 沙 福 奧）：後面接什麼字都保留。
        for prefix in "阿斯加卡艾哈安莫馬俄哥約波德塞達賽沙福奧" {
            let text = "\(prefix)里某地"
            XCTAssertEqual(LiWordRule.apply(to: text), text, "前綴 \(prefix)")
        }
    }

    func testSuffixExclusionSetKeepsLi() {
        // 後綴排除集（程 長 弄 巷 約 昂 斯 爾 尼 加 奧 德 根 正 甲 坊 民 鄰 鄉）：里 後面是這些字時保留。
        for suffix in "程長弄巷約昂斯爾尼加奧德根正甲坊民鄰鄉" {
            let text = "某地里\(suffix)"
            XCTAssertEqual(LiWordRule.apply(to: text), text, "後綴 \(suffix)")
        }
    }

    func testSimplifiedFormsOfExcludedCharactersAreAlsoKept() {
        // 簡體來源的殘留或尚未轉換的行：排除集同時含簡體字形。
        for suffix in "长约尔奥邻乡" {
            let text = "某地里\(suffix)"
            XCTAssertEqual(LiWordRule.apply(to: text), text, "後綴 \(suffix)")
        }
        for prefix in "万亿两几马约达赛奥邻乡" {
            let text = "\(prefix)里某地"
            XCTAssertEqual(LiWordRule.apply(to: text), text, "前綴 \(prefix)")
        }
        assertKept(["万里长城", "邻里之间", "乡里乡亲", "斯里兰卡的海"])
    }

    func testDictionaryDerivedTransliterationPrefixesKeepLi() {
        // 辭典掃描（OpenCC STPhrases 保留「里」的詞）找到的誤傷模式：克里米亞、烏蘇里江、佛羅里達、薩里郡、弗里曼…
        for prefix in "克蘇苏羅罗薩萨弗佛伊尤亞亚烏乌費费歐欧瓦庫库凱凯餘余托貝贝" {
            let text = "\(prefix)里某地"
            XCTAssertEqual(LiWordRule.apply(to: text), text, "前綴 \(prefix)")
        }
        assertKept(["克里米亞半島", "烏蘇里江", "佛羅里達州", "格里高利曆", "劈里啪啦", "稀里嘩啦", "炸里脊"])
    }

    func testPlausibleLyricContextsStillBecomeLi() {
        // 排除集不能過寬：這些前綴字在歌詞裡常是「X裡」。
        assertRule([
            ("性格里藏著秘密", "性格裡藏著秘密"),
            ("東西里有你的味道", "東西裡有你的味道"),
            ("嘴巴里含著糖", "嘴巴裡含著糖"),
            ("雨里有你的聲音", "雨裡有你的聲音"),
            ("稀里糊塗地過", "稀裡糊塗地過"),
        ])
    }

    // MARK: - 邊界：前面沒有漢字、沒有「里」

    func testLiWithoutAHanCharacterBeforeItIsLeftAlone() {
        assertKept(["里", "，里", " 里", "A里", "里，", "里面", "5里", ""])
    }

    func testTextWithoutLiIsReturnedUnchanged() {
        assertKept(["我們一起走過這條安靜的街", "Hello world", "裡面", "裏面"])
    }

    func testRuleIsIdempotent() {
        for text in ["在我心里", "家里，千里，心里", "鄰里", "书本里。", "我的心里卻一直下著雨", "阿里山的日出，手里的傘"] {
            let once = LiWordRule.apply(to: text)
            XCTAssertEqual(LiWordRule.apply(to: once), once)
        }
    }
}
