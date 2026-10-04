import XCTest
import OpenCC
@testable import DavidNookCore

/// 字集由 Tools/gen_charsets.py 產生；這裡驗證產物的健全性，並用實際會被使用的
/// SwiftyOpenCC（OpenCC 1.1.2 字典）交叉檢查腳本（PyPI OpenCC）當時的假設。
final class GeneratedCharsetsTests: XCTestCase {
    private var simplified: Set<Unicode.Scalar> { Set(GeneratedCharsets.simplifiedOnly.unicodeScalars) }
    private var traditional: Set<Unicode.Scalar> { Set(GeneratedCharsets.traditionalOnly.unicodeScalars) }

    func testSizesAreInExpectedRange() {
        // 參考值約 2,187 與 3,120；容許 OpenCC 版本差異。
        XCTAssertTrue((1800...2600).contains(simplified.count), "simplified-only = \(simplified.count)")
        XCTAssertTrue((2600...3700).contains(traditional.count), "traditional-only = \(traditional.count)")
    }

    func testHeaderCountsMatchActualContent() {
        XCTAssertEqual(GeneratedCharsets.simplifiedOnly.unicodeScalars.count, GeneratedCharsets.simplifiedOnlyCount)
        XCTAssertEqual(GeneratedCharsets.traditionalOnly.unicodeScalars.count, GeneratedCharsets.traditionalOnlyCount)
        XCTAssertEqual(simplified.count, GeneratedCharsets.simplifiedOnlyCount, "字集內不應有重複字元")
        XCTAssertEqual(traditional.count, GeneratedCharsets.traditionalOnlyCount, "字集內不應有重複字元")
    }

    func testSetsAreDisjointAndContainNoWhitespace() {
        XCTAssertTrue(simplified.isDisjoint(with: traditional))
        for scalar in simplified.union(traditional) {
            XCTAssertFalse(scalar.properties.isWhitespace, "U+\(String(scalar.value, radix: 16)) 是空白")
        }
    }

    func testKnownSimplifiedOnlyAndTraditionalOnly() {
        for ch in "爱们这说国东车门书软为际伦".unicodeScalars {
            XCTAssertTrue(simplified.contains(ch), "\(ch) 應為簡體專有字")
        }
        for ch in "愛們這說國東車門書網軟為際願倫".unicodeScalars {
            XCTAssertTrue(traditional.contains(ch), "\(ch) 應為繁體專有字")
        }
    }

    func testAmbiguousCharactersAreExcluded() {
        for ch in "麽着里后干发面台群於".unicodeScalars {
            XCTAssertFalse(simplified.contains(ch), "\(ch) 不應在簡體專有字")
            XCTAssertFalse(traditional.contains(ch), "\(ch) 不應在繁體專有字")
        }
    }

    func testEveryCharacterIsABMPCJKIdeograph() {
        for scalar in simplified.union(traditional) {
            XCTAssertTrue((0x4E00...0x9FFF).contains(scalar.value), "U+\(String(scalar.value, radix: 16))")
        }
    }

    /// 交叉檢查：簡體專有字在 SwiftyOpenCC 的 s2t 下應會被改；繁體專有字在 t2s 下應會被改。
    /// 腳本用的是 PyPI OpenCC 1.4.2，SwiftyOpenCC 內建的是 1.1.2 字典：極罕用字可能有差異，
    /// 容許少數例外（≤ 5%）並把它們列在失敗訊息裡。
    func testCrossCheckAgainstSwiftyOpenCC() throws {
        let toTraditional = try ChineseConverter(options: [.traditionalize])
        let toSimplified = try ChineseConverter(options: [.simplify])
        let simplifiedMisses = simplified.map { String($0) }.filter { toTraditional.convert($0) == $0 }
        let traditionalMisses = traditional.map { String($0) }.filter { toSimplified.convert($0) == $0 }
        XCTAssertLessThanOrEqual(
            simplifiedMisses.count, simplified.count / 20,
            "s2t 不會改的簡體專有字：\(simplifiedMisses.sorted().joined())"
        )
        XCTAssertLessThanOrEqual(
            traditionalMisses.count, traditional.count / 20,
            "t2s 不會改的繁體專有字：\(traditionalMisses.sorted().joined())"
        )
    }
}
