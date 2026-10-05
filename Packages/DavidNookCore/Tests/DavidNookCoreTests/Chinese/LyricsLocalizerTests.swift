import XCTest
@testable import DavidNookCore

/// 整合管線：偵測 → 選模式 → 轉換。樣本皆為自編句子或極短詞組。
final class LyricsLocalizerTests: XCTestCase {
    private let localizer = LyricsLocalizer()

    private func localize(
        _ lines: [String],
        idioms: Bool = false,
        skipping: Set<Int> = []
    ) throws -> LocalizedLyrics {
        try localizer.localize(
            lines: lines,
            options: LyricsLocalizationOptions(useTaiwanIdioms: idioms),
            skippingDetectionOfLineIndices: skipping
        )
    }

    // MARK: - 簡體 → 全轉

    func testSimplifiedDocumentIsConvertedWithConservativeMode() throws {
        let result = try localize([
            "词：周杰伦",
            "我愿意为你被放逐天际",
            "后来我们没有回头",
            "头发散落在肩上",
            "发如雪",
            "里面有软件",
            "干杯，朋友",
        ])
        XCTAssertEqual(result.script, .simplified)
        XCTAssertEqual(result.appliedMode, .conservative)
        XCTAssertNil(result.lineScripts)
        XCTAssertEqual(result.lines, [
            "詞：周杰倫",
            "我願意為你被放逐天際",
            "後來我們沒有回頭",
            "頭髮散落在肩上",
            "髮如雪",
            "裡面有軟件",
            "乾杯，朋友",
        ])
    }

    func testSimplifiedDocumentWithTaiwanIdiomsOption() throws {
        let result = try localize(["这个软件没有网络", "请打开鼠标的信息"], idioms: true)
        XCTAssertEqual(result.script, .simplified)
        XCTAssertEqual(result.appliedMode, .taiwanIdioms)
        XCTAssertEqual(result.lines, ["這個軟體沒有網路", "請開啟滑鼠的資訊"])
    }

    func testSimplifiedDocumentDefaultsToNoIdioms() throws {
        let result = try localize(["这个软件没有网络"])
        XCTAssertEqual(result.lines, ["這個軟件沒有網絡"])
    }

    func testAmbiguousOnlyLinesInsideSimplifiedDocumentAreStillConverted() throws {
        // 「后面」「里面」這兩行本身沒有專有字，但整篇是簡體 → 全文轉換，這兩行也要轉。
        let result = try localize(["我们都没有说话", "后面", "里面"])
        XCTAssertEqual(result.script, .simplified)
        XCTAssertEqual(result.lines, ["我們都沒有說話", "後面", "裡面"])
    }

    // MARK: - 繁體 → 不轉（僅 t2tw 變體正規化）

    func testNativeTraditionalSentencesStayCharacterForCharacter() throws {
        let lines = [
            "我願意為你被放逐天際",
            "裡面有軟體",
            "鄰里之間",
            "台灣的夜晚",
            "乾杯，朋友",
            "皇后大道上的燈",
            "公里與千里之外",
        ]
        let result = try localize(lines)
        XCTAssertEqual(result.script, .traditional)
        XCTAssertEqual(result.appliedMode, .variantsOnly)
        XCTAssertEqual(result.lines, lines)
    }

    func testNativeTraditionalIgnoresIdiomsOption() throws {
        let lines = ["裡面有軟體", "我們支持你", "鄰里之間"]
        let result = try localize(lines, idioms: true)
        XCTAssertEqual(result.script, .traditional)
        XCTAssertEqual(result.appliedMode, .variantsOnly)
        XCTAssertEqual(result.lines, lines, "idioms 不得把原生繁體的 支持 改成 支援")
    }

    func testNativeTraditionalGetsOnlyVariantNormalization() throws {
        let result = try localize(["我願意跟着你", "裏面很安靜"])
        XCTAssertEqual(result.script, .traditional)
        XCTAssertEqual(result.lines, ["我願意跟著你", "裡面很安靜"])
    }

    // MARK: - 中性 → 原樣

    func testEnglishLyricsUnchanged() throws {
        let lines = ["The night is quiet and I wait for you", "", "la la la", "♪"]
        let result = try localize(lines)
        XCTAssertEqual(result.script, .neutral)
        XCTAssertNil(result.appliedMode)
        XCTAssertEqual(result.lines, lines)
    }

    func testNeutralChineseWithoutEvidenceIsLeftAlone() throws {
        let lines = ["后面", "里面", "你我他"]
        let result = try localize(lines)
        XCTAssertEqual(result.script, .neutral)
        XCTAssertEqual(result.lines, lines)
    }

    func testEmptyInput() throws {
        let result = try localize([])
        XCTAssertEqual(result.script, .neutral)
        XCTAssertEqual(result.lines, [])
    }

    // MARK: - 混合 → 逐行判斷

    func testMixedDocumentIsDecidedLineByLine() throws {
        let lines = [
            "我愿意为你被放逐天际",   // 簡體 → 轉
            "我願意為你被放逐天際",   // 繁體 → 不轉
            "Hello world",             // 中性 → 原樣
            "",                        // 空行 → 原樣
            "里面有软件",              // 簡體 → 轉
            "裡面有軟體",              // 繁體 → 不轉
            "鄰里之間",                // 繁體 → 不轉（不可變成鄰裡）
            "后面",                    // 中性行（只有 后 面 等通用字）→ 原樣
            "头发散落",                // 簡體 → 轉
        ]
        let result = try localize(lines)
        XCTAssertEqual(result.script, .mixed)
        XCTAssertNil(result.appliedMode)
        XCTAssertEqual(result.lineScripts, [
            .simplified, .traditional, .neutral, .neutral, .simplified,
            .traditional, .traditional, .neutral, .simplified,
        ])
        XCTAssertEqual(result.lines, [
            "我願意為你被放逐天際",
            "我願意為你被放逐天際",
            "Hello world",
            "",
            "裡面有軟件",
            "裡面有軟體",
            "鄰里之間",
            "后面",
            "頭髮散落",
        ])
    }

    func testMixedDocumentHonorsIdiomsOptionOnlyForSimplifiedLines() throws {
        let lines = ["这个软件", "我們支持你", "裡面有軟體"]
        let result = try localize(lines, idioms: true)
        XCTAssertEqual(result.script, .mixed)
        XCTAssertEqual(result.lines, ["這個軟體", "我們支持你", "裡面有軟體"])
    }

    func testMixedLineWithBothScriptsStillGetsSimplifiedCharactersConverted() throws {
        let lines = ["我爱你們", "我愛你們", "这个世界"]
        let result = try localize(lines)
        XCTAssertEqual(result.script, .mixed)
        XCTAssertEqual(result.lineScripts?[0], .mixed)
        XCTAssertEqual(result.lines[0], "我愛你們")
    }

    // MARK: - 略過中繼行索引（只影響偵測）

    func testSkippedMetaLinesDoNotInfluenceDetection() throws {
        var lines = ["作詞：周杰倫　編曲：黃國隆"]
        lines += Array(repeating: "我们爱你", count: 10)
        let withoutSkip = try localize(lines)
        XCTAssertEqual(withoutSkip.script, .mixed)
        let withSkip = try localize(lines, skipping: [0])
        XCTAssertEqual(withSkip.script, .simplified)
        XCTAssertEqual(withSkip.lines[1], "我們愛你")
        XCTAssertEqual(withSkip.lines[0], "作詞：周杰倫　編曲：黃國隆")
    }

    func testSkippedLinesAreStillConvertedByTheDocumentDecision() throws {
        // 「略過」只作用於偵測；中繼行本身仍依整篇判斷轉換（簡體文件裡的簡體中繼行要轉）。
        var lines = ["词：周杰伦"]
        lines += Array(repeating: "我们爱你", count: 10)
        let result = try localize(lines, skipping: [0])
        XCTAssertEqual(result.script, .simplified)
        XCTAssertEqual(result.lines[0], "詞：周杰倫")
    }

    // MARK: - 結構保證

    func testOutputPreservesLineCountAndOrder() throws {
        let lines = (0..<50).map { $0 % 3 == 0 ? "我们爱你 \($0)" : ($0 % 3 == 1 ? "" : "Hello \($0)") }
        let result = try localize(lines)
        XCTAssertEqual(result.lines.count, lines.count)
        for (index, line) in lines.enumerated() where line.isEmpty || line.hasPrefix("Hello") {
            XCTAssertEqual(result.lines[index], line)
        }
    }

    // MARK: - 冪等性（對輸出再跑一次結果不變）

    func testLocalizingTwiceEqualsLocalizingOnce() throws {
        let documents: [[String]] = [
            ["词：周杰伦", "我愿意为你被放逐天际", "邻里之间", "里面有软件", "发如雪", "不断发展"],
            ["我願意為你被放逐天際", "裡面有軟體", "鄰里之間", "台灣的夜晚", "跟着我"],
            ["我愿意为你", "我願意為你", "Hello", "", "鄰里", "邻里", "后来"],
            ["Hello world", "la la la"],
            ["这个软件没有网络", "请打开鼠标的信息", "海里有鱼，在海里游"],
        ]
        for idioms in [false, true] {
            for document in documents {
                let once = try localize(document, idioms: idioms)
                let twice = try localize(once.lines, idioms: idioms)
                XCTAssertEqual(twice.lines, once.lines, "idioms=\(idioms) \(document)")
            }
        }
    }

    // MARK: - 自編整首簡體歌詞（端到端；內容為本專案自編，非真實歌詞）

    func testWholeSimplifiedSongEndToEnd() throws {
        let input = [
            "我愿意为你被放逐天际",
            "头发被风吹乱了",
            "你的发梢带着雨的气息",
            "后来的后来我们都没有回头",
            "海里的鱼不知道天空有多高",
            "我在干净的月光下干杯",
            "面条和面包都凉了",
            "托着下巴想象你的样子",
            "回应我的每一个梦",
            "不断发现新的自己",
            "不断发展的城市里没有风",
            "这里那里哪里都是你",
            "爱像发如雪一样落下",
            "我发端的指尖微凉",
            "白发苍苍的老人",
            "成长发展的故事",
            "苍白发抖的手",
            "象征与特征",
            "周杰伦和林俊杰",
            "钟意你的人",
            "周而复始的夜晚",
            "托付给你的信",
            "寄托着我的希望",
            "拜托你别走",
            "征途漫漫",
            "后街的灯火",
            "皇后与国王",
            "曲终人散",
            "干涉与干部",
            "树干和骨干",
            "千里之外万里无云",
            "公里和英里",
            "一只鸟两只猫",
            "只要你只想你",
            "The night is quiet",
            "",
        ]
        let expected = [
            "我願意為你被放逐天際",
            "頭髮被風吹亂了",
            "你的髮梢帶著雨的氣息",
            "後來的後來我們都沒有回頭",
            "海裡的魚不知道天空有多高",
            "我在乾淨的月光下乾杯",
            "麵條和麵包都涼了",
            "托著下巴想像你的樣子",
            "回應我的每一個夢",
            "不斷發現新的自己",
            "不斷發展的城市裡沒有風",
            "這裡那裡哪裡都是你",
            "愛像髮如雪一樣落下",
            "我髮端的指尖微涼",
            "白髮蒼蒼的老人",
            "成長發展的故事",
            "蒼白發抖的手",
            "象徵與特徵",
            "周杰倫和林俊傑",
            "鍾意你的人",
            "周而復始的夜晚",
            "託付給你的信",
            "寄託著我的希望",
            "拜託你別走",
            "征途漫漫",
            "後街的燈火",
            "皇后與國王",
            "曲終人散",
            "干涉與幹部",
            "樹幹和骨幹",
            "千里之外萬里無雲",
            "公里和英里",
            "一隻鳥兩隻貓",
            "只要你只想你",
            "The night is quiet",
            "",
        ]
        let result = try localize(input)
        XCTAssertEqual(result.script, .simplified)
        XCTAssertEqual(result.lines.count, expected.count)
        for (index, (actual, want)) in zip(result.lines, expected).enumerated() {
            XCTAssertEqual(actual, want, "第 \(index + 1) 行：\(input[index])")
        }
    }

    // MARK: - 多執行緒

    func testConcurrentLocalizationGivesIdenticalResults() throws {
        let lines = ["头发被风吹乱了", "海里的鱼", "发如雪", "这个软件没有网络", "Hello"]
        let baseline = try localize(lines).lines
        let failures = LockedCounter()
        DispatchQueue.concurrentPerform(iterations: 200) { _ in
            do {
                let result = try localizer.localize(lines: lines)
                if result.lines != baseline { failures.increment() }
            } catch {
                failures.increment()
            }
        }
        XCTAssertEqual(failures.value, 0)
    }

    // MARK: - 日文／韓文不轉換（真實資料稽核：日文新字體被轉成「國・戀・聲・會」）
    // 樣本全為自編句子。

    func testJapaneseLyricsAreNeverConverted() throws {
        let lines = ["恋する国の声が聞こえる", "", "残酷な夜に会えたなら", "ありがとう", "ただそれだけ"]
        let result = try localize(lines)
        XCTAssertEqual(result.script, .neutral)
        XCTAssertNil(result.appliedMode)
        XCTAssertEqual(result.lines, lines, "日文歌詞不得被簡轉繁（国→國、恋→戀、声→聲、会→會）")
    }

    func testJapaneseLyricsAreNeverConvertedEvenWithTaiwanIdioms() throws {
        let lines = ["恋する国の声が聞こえる", "残酷な夜に会えたなら"]
        XCTAssertEqual(try localize(lines, idioms: true).lines, lines)
    }

    func testKoreanLyricsWithHanjaAreNeverConverted() throws {
        let lines = ["그대는 나의 戀人", "사랑해 영원히"]
        let result = try localize(lines)
        XCTAssertEqual(result.script, .neutral)
        XCTAssertEqual(result.lines, lines)
    }

    func testJapaneseLineInsideSimplifiedChineseDocumentIsKept() throws {
        // 簡體華語歌夾一句日文：華語行照常轉換，日文行原樣保留。
        var lines = Array(repeating: "我们为什么还没有开始", count: 6)
        lines.append("恋する国の声が聞こえる")
        let result = try localize(lines)
        XCTAssertEqual(result.script, .simplified)
        XCTAssertEqual(Array(result.lines.prefix(6)), Array(repeating: "我們為什麼還沒有開始", count: 6))
        XCTAssertEqual(result.lines[6], "恋する国の声が聞こえる")
    }

    func testJapaneseLineInsideTraditionalChineseDocumentIsKept() throws {
        // 繁體華語歌夾一句日文：日文行不做 t2tw（「裏」「着」之類的變體正規化只對華語行）。
        var lines = Array(repeating: "我們為什麼還沒有開始", count: 6)
        lines.append("裏切りの声が聞こえる")
        let result = try localize(lines)
        XCTAssertEqual(result.script, .traditional)
        XCTAssertEqual(result.lines[6], "裏切りの声が聞こえる", "日文行裡的「裏」不可被改成「裡」")
    }

    // MARK: - shared 實例

    func testSharedInstanceWorks() throws {
        let result = try LyricsLocalizer.shared.localize(lines: ["周杰伦", "我们"])
        XCTAssertEqual(result.lines, ["周杰倫", "我們"])
    }
}

/// 多執行緒測試用的計數器。
private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
