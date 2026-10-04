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
        // 「后来」這行本身沒有專有字，但整篇是簡體 → 全文轉換，這行也要轉。
        let result = try localize(["我们都没有说话", "后来", "里面"])
        XCTAssertEqual(result.script, .simplified)
        XCTAssertEqual(result.lines, ["我們都沒有說話", "後來", "裡面"])
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
        let lines = ["后来", "里面", "你我他"]
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
            "后来",                    // 中性行（只有通用字）→ 原樣
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
            "后来",
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
        let lines = ["我愿意為你", "我願意為你", "这个世界"]
        let result = try localize(lines)
        XCTAssertEqual(result.script, .mixed)
        XCTAssertEqual(result.lineScripts?[0], .mixed)
        XCTAssertEqual(result.lines[0], "我願意為你")
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

    // MARK: - shared 實例

    func testSharedInstanceWorks() throws {
        let result = try LyricsLocalizer.shared.localize(lines: ["周杰伦", "我们"])
        XCTAssertEqual(result.lines, ["周杰倫", "我們"])
    }
}
