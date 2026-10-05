import XCTest
@testable import DavidNookCore

/// 黃金樣本：斷言 SwiftyOpenCC（OpenCC 1.1.2 字典）＋覆寫表的「實際輸出」。
/// 樣本皆為單詞、人名或自編短句，不含受版權保護的真實歌詞。
final class LyricsChineseConverterTests: XCTestCase {
    private func assertConverts(
        _ mode: LyricsConversionMode,
        _ pairs: [(String, String)],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let converter = try LyricsChineseConverter.cached(mode)
        for (input, expected) in pairs {
            XCTAssertEqual(converter.convert(input), expected, "[\(mode)] \(input)", file: file, line: line)
        }
    }

    // MARK: - .conservative（歌詞預設：簡→繁字形＋台灣字形，不做慣用詞）

    func testConservativeGoldenSamples() throws {
        try assertConverts(.conservative, [
            ("周杰伦", "周杰倫"),
            ("词：周杰伦", "詞：周杰倫"),
            ("编曲", "編曲"),
            ("后来", "後來"),
            ("头发", "頭髮"),
            ("发现", "發現"),
            ("里面", "裡面"),
            ("干杯", "乾杯"),
            ("萝卜", "蘿蔔"),
        ])
    }

    func testConservativeDoesNotApplyTaiwanIdioms() throws {
        // 記錄「不做慣用詞」的行為：支持/打开/溢出/信息/网络/软件/鼠标 都只換字形。
        try assertConverts(.conservative, [
            ("软件", "軟件"),
            ("鼠标", "鼠標"),
            ("信息", "信息"),
            ("网络", "網絡"),
            ("支持", "支持"),
            ("打开", "打開"),
            ("溢出", "溢出"),
        ])
    }

    func testConservativeAppliesTaiwanCharacterForms() throws {
        // twStandard：着→著、裏→裡 等台灣字形（由簡體來源轉出時）。
        try assertConverts(.conservative, [
            ("跟着我", "跟著我"),
            ("为什么", "為什麼"),
            ("怎么了", "怎麼了"),
        ])
    }

    // MARK: - .taiwanIdioms（等同 s2twp，設定可開）

    func testTaiwanIdiomsGoldenSamples() throws {
        try assertConverts(.taiwanIdioms, [
            ("软件", "軟體"),
            ("鼠标", "滑鼠"),
            ("信息", "資訊"),
            ("网络", "網路"),
            // 慣用詞層同時保留 conservative 的字形結果
            ("周杰伦", "周杰倫"),
            ("头发", "頭髮"),
            ("里面", "裡面"),
        ])
    }

    func testTaiwanIdiomsRisksDocumented() throws {
        // 這就是歌詞預設不開慣用詞層的原因：把一般詞彙當成電腦術語改掉。
        try assertConverts(.taiwanIdioms, [
            ("支持", "支援"),
            ("打开", "開啟"),
            ("溢出", "溢位"),
        ])
    }

    // MARK: - .variantsOnly（原生繁體歌詞：只做台灣字形正規化）

    func testVariantsOnlyKeepsNativeTraditionalUnchanged() throws {
        // 這些是 s2tw / s2twp 會誤改的原生繁體寫法（鄰里→鄰裡、台→臺 等）。
        try assertConverts(.variantsOnly, [
            ("我願意為你被放逐天際", "我願意為你被放逐天際"),
            ("裡面有軟體", "裡面有軟體"),
            ("鄰里之間", "鄰里之間"),
            ("台灣的夜晚", "台灣的夜晚"),
            ("乾杯", "乾杯"),
            ("皇后", "皇后"),
            ("公里", "公里"),
            ("周杰倫", "周杰倫"),
            ("網絡", "網絡"),
            ("溢出", "溢出"),
        ])
    }

    func testVariantsOnlyNeverTurnsTaiToTai() throws {
        let converter = try LyricsChineseConverter.cached(.variantsOnly)
        XCTAssertEqual(converter.convert("台灣"), "台灣")
        XCTAssertEqual(converter.convert("台北"), "台北")
        XCTAssertEqual(converter.convert("舞台"), "舞台")
        XCTAssertEqual(converter.convert("臺灣"), "臺灣", "原本寫臺的也不動")
    }

    func testVariantsOnlyRecordedNormalizations() throws {
        // 如實記錄 t2tw 的變體正規化行為（屬字形統一，不是簡轉繁）。
        try assertConverts(.variantsOnly, [
            ("着", "著"),
            ("跟着我", "跟著我"),
            ("着急", "著急"),
            ("裏面", "裡面"),
            ("爲了你", "為了你"),
            ("啓程", "啟程"),
            ("羣星", "群星"),
            ("衆人", "眾人"),
            ("麪包", "麵包"),
            ("喫飯", "吃飯"),
            ("纔剛", "才剛"),
            ("僞裝", "偽裝"),
            ("污染", "汙染"),
        ])
    }

    func testVariantsOnlyDoesNotNormalizeMa() throws {
        // 記錄：麽 不在 TWVariants 內，所以「為什麽」維持原樣（偵測器也因此不把 麽 當簡體證據）。
        try assertConverts(.variantsOnly, [("為什麽", "為什麽"), ("怎麽", "怎麽")])
    }

    func testVariantsOnlyDoesNotSimplifiedToTraditional() throws {
        // variantsOnly 不處理簡體：簡體文字要走 .conservative / .taiwanIdioms。
        let converter = try LyricsChineseConverter.cached(.variantsOnly)
        XCTAssertEqual(converter.convert("周杰伦"), "周杰伦")
    }

    func testVariantsOnlyIsIdempotent() throws {
        let converter = try LyricsChineseConverter.cached(.variantsOnly)
        for sample in ["跟着我", "裏面", "爲了你", "鄰里之間", "台灣", "麪包", "污染", "為什麽", "Hello 世界"] {
            let once = converter.convert(sample)
            XCTAssertEqual(converter.convert(once), once, sample)
        }
    }

    func testConservativeOnNativeTraditionalWouldDamageIt() throws {
        // 記錄「為什麼一定要先偵測」：對原生繁體誤用 conservative 會把 鄰里→鄰裡、台灣→臺灣。
        let converter = try LyricsChineseConverter.cached(.conservative)
        XCTAssertEqual(converter.convert("鄰里之間"), "鄰裡之間")
        XCTAssertEqual(converter.convert("台灣的夜晚"), "臺灣的夜晚")
    }

    // MARK: - 語意歧義（髮/發、乾/幹/干、里/裡/裏、后/後/后、曲/麴、面/麵、征/徵…）

    func testAmbiguityHairVersusSend() throws {
        try assertConverts(.conservative, [
            ("头发", "頭髮"),
            ("发现", "發現"),
            ("发如雪", "髮如雪"),
            ("我发端的指尖", "我髮端的指尖"),
            ("发丝", "髮絲"),
            ("白发", "白髮"),
            ("青丝白发", "青絲白髮"),
            ("发线", "髮線"),
            ("长发及腰", "長髮及腰"),
            ("理发", "理髮"),
            ("出发", "出發"),
            ("不断发展", "不斷發展"),
            ("不断发现", "不斷發現"),
            ("生长发育", "生長發育"),
        ])
    }

    func testAmbiguityDryDoStem() throws {
        try assertConverts(.conservative, [
            ("干杯", "乾杯"),
            ("干净", "乾淨"),
            ("没干净", "沒乾淨"),
            ("才干净", "才乾淨"),
            ("干部", "幹部"),
            ("树干", "樹幹"),
            ("干涉", "干涉"),
            ("若干", "若干"),
        ])
    }

    func testAmbiguityInside() throws {
        try assertConverts(.conservative, [
            ("里面", "裡面"),
            ("这里", "這裡"),
            ("心里话", "心裡話"),
            ("海里", "海裡"),
            ("在海里游", "在海裡遊"),
            ("公里", "公里"),
            ("千里之外", "千里之外"),
            ("万里", "萬里"),
            ("邻里之间", "鄰里之間"),
            ("糊里糊涂", "糊裡糊塗"),
            ("傻里傻气", "傻裡傻氣"),
        ])
    }

    func testAmbiguityQueenVersusAfter() throws {
        try assertConverts(.conservative, [
            ("后来", "後來"),
            ("以后", "以後"),
            ("皇后", "皇后"),
            ("太后", "太后"),
            ("后羿", "后羿"),
        ])
    }

    func testAmbiguityKojiVersusSong() throws {
        try assertConverts(.conservative, [
            ("酒曲", "酒麴"),
            ("歌曲", "歌曲"),
            ("曲终人散", "曲終人散"),
            ("弯曲", "彎曲"),
        ])
    }

    func testAmbiguityNoodleVersusFace() throws {
        try assertConverts(.conservative, [
            ("面条", "麵條"),
            ("面包", "麵包"),
            ("见面", "見面"),
            ("面对", "面對"),
            ("面向", "面向"),
        ])
    }

    func testAmbiguityLevyVersusMarch() throws {
        try assertConverts(.conservative, [
            ("特征", "特徵"),
            ("象征", "象徵"),
            ("征求", "徵求"),
            ("征途", "征途"),
            ("征服", "征服"),
            ("远征", "遠征"),
        ])
    }

    func testOtherLyricRiskWords() throws {
        try assertConverts(.conservative, [
            ("回应", "回應"),
            ("想象", "想像"),
            ("想象力", "想像力"),
            ("林俊杰", "林俊傑"),
            ("托着", "托著"),
            ("托起", "托起"),
            ("手托", "手托"),
            ("托付", "託付"),
            ("拜托", "拜託"),
            ("钟意", "鍾意"),
            ("周而复始", "周而復始"),
            ("诋毁", "詆毀"),
        ])
    }

    // MARK: - 覆寫表與轉換器的互動

    func testOverrideBeatsOpenCCPhrases() throws {
        // 發如雪：OpenCC 單獨轉出「發如雪」，覆寫表要把它改成「髮如雪」。
        let withOverrides = try LyricsChineseConverter(mode: .conservative, overrides: .bundled)
        let withoutOverrides = try LyricsChineseConverter(mode: .conservative, overrides: LyricsOverrides(parsing: ""))
        XCTAssertEqual(withOverrides.convert("发如雪"), "髮如雪")
        XCTAssertEqual(withoutOverrides.convert("发如雪"), "發如雪")
    }

    func testOverridesAreAppliedInTaiwanIdiomsModeToo() throws {
        try assertConverts(.taiwanIdioms, [("发如雪", "髮如雪"), ("我发端的指尖", "我髮端的指尖")])
    }

    func testOverridesAreNotAppliedInVariantsOnlyMode() throws {
        // 繁體文字不走簡體覆寫表。
        let converter = try LyricsChineseConverter.cached(.variantsOnly)
        XCTAssertEqual(converter.convert("发如雪"), "发如雪")
    }

    // MARK: - 快取與一般行為

    func testConvertersAreCachedPerMode() throws {
        let a = try LyricsChineseConverter.cached(.conservative)
        let b = try LyricsChineseConverter.cached(.conservative)
        XCTAssertTrue(a === b)
        XCTAssertFalse(a === (try LyricsChineseConverter.cached(.taiwanIdioms)))
        XCTAssertEqual(a.mode, .conservative)
    }

    func testEmptyAndNonChineseTextPassThrough() throws {
        for mode in LyricsConversionMode.allCases {
            let converter = try LyricsChineseConverter.cached(mode)
            XCTAssertEqual(converter.convert(""), "")
            XCTAssertEqual(converter.convert("Hello, world! 123 ~ ♪"), "Hello, world! 123 ~ ♪")
        }
    }

    func testPunctuationAndTimestampsAreNotDamaged() throws {
        let converter = try LyricsChineseConverter.cached(.conservative)
        XCTAssertEqual(converter.convert("词：周杰伦 - Jay (2001)"), "詞：周杰倫 - Jay (2001)")
    }
}
