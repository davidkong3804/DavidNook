import XCTest
@testable import DavidNookCore

/// 偵測器：全部樣本為自編句子或極短詞組，不含受版權保護的真實歌詞。
final class ChineseScriptDetectorTests: XCTestCase {
    private let detector = ChineseScriptDetector()

    // MARK: - neutral（沒有任何專有字）

    func testNeutralEmptyAndWhitespace() {
        XCTAssertEqual(detector.detect(""), .neutral)
        XCTAssertEqual(detector.detect("   \n\t "), .neutral)
    }

    func testNeutralEnglishAndSymbols() {
        XCTAssertEqual(detector.detect("Hello, world! la la la ~ 123"), .neutral)
        XCTAssertEqual(detector.detect("♪ ♪ ♪"), .neutral)
    }

    func testNeutralOnlyAmbiguousCharacters() {
        // 這些字兩邊通用（或刻意排除）：里后干发面台群於 麽 着。單獨出現時沒有證據。
        XCTAssertEqual(detector.detect("里后干发面台群於"), .neutral)
        XCTAssertEqual(detector.detect("麽着"), .neutral)
        XCTAssertEqual(detector.detect("天地人和你我他"), .neutral)
    }

    // MARK: - traditional

    func testTraditionalSentences() {
        XCTAssertEqual(detector.detect("我願意為你被放逐天際"), .traditional)
        XCTAssertEqual(detector.detect("裡面有軟體"), .traditional)
        XCTAssertEqual(detector.detect("鄰里之間"), .traditional)
        XCTAssertEqual(detector.detect("台灣的夜晚"), .traditional)
    }

    func testTraditionalWithMainlandVariantsStillTraditional() {
        // 麽、着 不算簡體證據（原生繁體歌詞常混入）。
        XCTAssertEqual(detector.detect("為什麽要這麽的脆弱，跟着我"), .traditional)
    }

    // MARK: - simplified

    func testSimplifiedSentences() {
        XCTAssertEqual(detector.detect("我愿意为你被放逐天际"), .simplified)
        XCTAssertEqual(detector.detect("周杰伦"), .simplified)
        XCTAssertEqual(detector.detect("这个软件没有网络"), .simplified)
    }

    func testSimplifiedSingleCharacter() {
        XCTAssertEqual(detector.detect("爱"), .simplified)
        XCTAssertEqual(detector.detect("愛"), .traditional)
    }

    // MARK: - mixed

    func testMixedHalfAndHalf() {
        XCTAssertEqual(detector.detect("爱愛"), .mixed)
        XCTAssertEqual(detector.detect("我愿意为你\n我願意為你"), .mixed)
    }

    func testMixedDocumentOfTwoStyles() {
        let text = ["这个软件没有网络", "我願意為你被放逐天際", "裡面有軟體"].joined(separator: "\n")
        XCTAssertEqual(detector.detect(text), .mixed)
    }

    // MARK: - 3% 邊界（以整數比較，剛好 3% 算少數派）

    private func doc(trad: Int, simp: Int) -> String {
        String(repeating: "愛", count: trad) + String(repeating: "爱", count: simp)
    }

    func testBoundaryExactlyThreePercentSimplifiedMinorityIsTraditional() {
        XCTAssertEqual(detector.evidence(in: doc(trad: 97, simp: 3)), ScriptEvidence(simplified: 3, traditional: 97))
        XCTAssertEqual(detector.detect(doc(trad: 97, simp: 3)), .traditional)
    }

    func testBoundaryJustOverThreePercentSimplifiedMinorityIsMixed() {
        XCTAssertEqual(detector.detect(doc(trad: 96, simp: 4)), .mixed)
        XCTAssertEqual(detector.detect(doc(trad: 32, simp: 1)), .mixed)  // 1/33 ≈ 3.03%
    }

    func testBoundaryExactlyThreePercentTraditionalMinorityIsSimplified() {
        XCTAssertEqual(detector.detect(doc(trad: 3, simp: 97)), .simplified)
        XCTAssertEqual(detector.detect(doc(trad: 1, simp: 33)), .simplified)  // 1/34 ≈ 2.94%
    }

    func testBoundaryJustOverThreePercentTraditionalMinorityIsMixed() {
        XCTAssertEqual(detector.detect(doc(trad: 4, simp: 96)), .mixed)
        XCTAssertEqual(detector.detect(doc(trad: 1, simp: 32)), .mixed)  // 1/33 ≈ 3.03%
    }

    func testClassifyIsPureArithmetic() {
        XCTAssertEqual(ChineseScriptDetector.classify(ScriptEvidence(simplified: 0, traditional: 0)), .neutral)
        XCTAssertEqual(ChineseScriptDetector.classify(ScriptEvidence(simplified: 5, traditional: 0)), .simplified)
        XCTAssertEqual(ChineseScriptDetector.classify(ScriptEvidence(simplified: 0, traditional: 5)), .traditional)
        XCTAssertEqual(ChineseScriptDetector.classify(ScriptEvidence(simplified: 3, traditional: 97)), .traditional)
        XCTAssertEqual(ChineseScriptDetector.classify(ScriptEvidence(simplified: 4, traditional: 96)), .mixed)
        XCTAssertEqual(ChineseScriptDetector.classify(ScriptEvidence(simplified: 50, traditional: 50)), .mixed)
    }

    // MARK: - 多行 / 跳過

    func testDetectLinesIgnoresBlankLines() {
        XCTAssertEqual(detector.detect(lines: ["", "  ", "我愿意为你", ""]), .simplified)
        XCTAssertEqual(detector.detect(lines: ["", "  "]), .neutral)
    }

    func testDetectLinesSkippingMetaLines() {
        // 第 0 行是繁體的中繼行；本文是簡體。不跳過會被判成 mixed，跳過後是 simplified。
        var lines = ["作詞：周杰倫　編曲：黃國隆"]
        lines += Array(repeating: "我们爱你", count: 10)
        XCTAssertEqual(detector.detect(lines: lines), .mixed)
        XCTAssertEqual(detector.detect(lines: lines, skippingLineIndices: [0]), .simplified)
    }

    func testSkippingOutOfRangeIndicesIsHarmless() {
        XCTAssertEqual(detector.detect(lines: ["我们爱你"], skippingLineIndices: [5, -1]), .simplified)
    }

    // MARK: - 逐行（mixed 文件使用）

    func testDetectEachLine() {
        let lines = ["我愿意为你被放逐天际", "我願意為你被放逐天際", "Hello", "", "后面", "爱愛"]
        XCTAssertEqual(
            detector.detectEachLine(lines),
            [.simplified, .traditional, .neutral, .neutral, .neutral, .mixed]
        )
    }

    // MARK: - 證據計數

    func testEvidenceCountsOccurrencesNotUniqueCharacters() {
        XCTAssertEqual(detector.evidence(in: "爱爱爱愛"), ScriptEvidence(simplified: 3, traditional: 1))
        XCTAssertEqual(detector.evidence(in: "abc 123"), ScriptEvidence(simplified: 0, traditional: 0))
    }
}
