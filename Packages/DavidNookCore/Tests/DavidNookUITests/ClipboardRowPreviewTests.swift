import DavidNookCore
import XCTest
@testable import DavidNookUI

/// 列表預覽字串（全部自編文字）。
final class ClipboardRowPreviewTests: XCTestCase {
    func testShortTextIsUnchanged() {
        XCTAssertEqual(ClipboardRowPreview.text("Hello 世界"), "Hello 世界")
    }

    func testLeadingWhitespaceAndBlankLinesAreSkipped() {
        XCTAssertEqual(ClipboardRowPreview.text("\n\n   第一行\n第二行"), "第一行\n第二行")
    }

    func testMultiLineTextKeepsNewlines() {
        XCTAssertEqual(ClipboardRowPreview.text("line one\nline two\nline three"), "line one\nline two\nline three")
    }

    func testLongTextIsCutAtMaxCharactersWithEllipsis() {
        let text = String(repeating: "字", count: 500)
        let preview = ClipboardRowPreview.text(text)
        XCTAssertEqual(preview, String(repeating: "字", count: ClipboardRowPreview.maxCharacters) + "…")
    }

    func testTextExactlyAtLimitHasNoEllipsis() {
        let text = String(repeating: "a", count: ClipboardRowPreview.maxCharacters)
        XCTAssertEqual(ClipboardRowPreview.text(text), text)
    }

    func testTrailingWhitespaceBeforeCutIsDropped() {
        let text = String(repeating: "a", count: ClipboardRowPreview.maxCharacters - 1) + " " + "tail"
        XCTAssertEqual(ClipboardRowPreview.text(text), String(repeating: "a", count: ClipboardRowPreview.maxCharacters - 1) + "…")
    }

    func testWhitespaceOnlyTextGivesEmptyPreview() {
        XCTAssertEqual(ClipboardRowPreview.text("  \n\t "), "")
    }

    func testHugeTextPreviewIsCheap() {
        // 1MB 文字（Core 的文字上限）：預覽只處理前 200 字，不應該花時間。
        let text = String(repeating: "abcdefghij", count: 100_000)
        let start = Date()
        let preview = ClipboardRowPreview.text(text)
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.05)
        XCTAssertEqual(preview.count, ClipboardRowPreview.maxCharacters + 1)
    }

    func testFileTitleUsesFirstFileName() {
        XCTAssertEqual(ClipboardRowPreview.fileTitle(["/Users/test/Documents/report-final.pdf", "/tmp/b.txt"]), "report-final.pdf")
        XCTAssertEqual(ClipboardRowPreview.fileTitle(["/"]), "/")
        XCTAssertEqual(ClipboardRowPreview.fileTitle([]), "")
    }

    func testTooltips() {
        let files = ClipboardItem(filePaths: ["/a/one.txt", "/b/two.txt"])
        XCTAssertEqual(ClipboardRowPreview.tooltip(for: files), "/a/one.txt\n/b/two.txt")
        let text = ClipboardItem(text: String(repeating: "x", count: 1000))
        XCTAssertEqual(ClipboardRowPreview.tooltip(for: text)?.count, ClipboardRowPreview.maxTooltipCharacters + 1)
        let image = ClipboardItem(imageData: Data("seed".utf8))
        XCTAssertNil(ClipboardRowPreview.tooltip(for: image))
    }
}
