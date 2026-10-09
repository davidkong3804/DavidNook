import XCTest
@testable import DavidNookCore

final class ReleaseNotesFormatterTests: XCTestCase {
    func testPlainTextPassesThrough() {
        XCTAssertEqual(ReleaseNotesFormatter.plainSummary("修正歌詞偏移。", maxLength: 100), "修正歌詞偏移。")
    }

    func testMarkdownLinkKeepsOnlyLabel() {
        let out = ReleaseNotesFormatter.plainSummary("請看 [Beta 說明](https://example.com/x) 了解。", maxLength: 100)
        XCTAssertEqual(out, "請看 Beta 說明 了解。")
        XCTAssertFalse(out.contains("http"))
    }

    func testImagesAreDropped() {
        let out = ReleaseNotesFormatter.plainSummary("前 ![alt](https://example.com/a.png) 後", maxLength: 100)
        XCTAssertFalse(out.contains("example.com"))
        XCTAssertFalse(out.contains("!["))
    }

    func testHtmlTagsAndScriptContentAreRemoved() {
        let out = ReleaseNotesFormatter.plainSummary("A<script>alert(1)</script>B<img src=x onerror=y>C<b>D</b>", maxLength: 100)
        XCTAssertFalse(out.contains("<"))
        XCTAssertFalse(out.contains("alert"))
        XCTAssertFalse(out.contains("onerror"))
        XCTAssertTrue(out.contains("A"))
        XCTAssertTrue(out.contains("D"))
    }

    func testHeadingAndEmphasisMarkersAreStripped() {
        let out = ReleaseNotesFormatter.plainSummary("### 重點\n- **粗體** 與 `code` 與 _斜體_", maxLength: 200)
        XCTAssertFalse(out.contains("###"))
        XCTAssertFalse(out.contains("**"))
        XCTAssertFalse(out.contains("`"))
        XCTAssertTrue(out.contains("重點"))
        XCTAssertTrue(out.contains("粗體"))
    }

    func testBareUrlsAreKeptAsTextButNeverAsLinksTargetsOfMarkdown() {
        // 純文字顯示；網址只是文字，不會被點開。
        let out = ReleaseNotesFormatter.plainSummary("見 https://example.com/a", maxLength: 100)
        XCTAssertTrue(out.contains("https://example.com/a"))
    }

    func testControlCharactersAndBidiOverridesAreRemoved() {
        let out = ReleaseNotesFormatter.plainSummary("a\u{0007}b\u{202E}c\u{200B}d\u{0000}e", maxLength: 100)
        XCTAssertEqual(out, "abcde")
    }

    func testNewlinesCollapseAndTabsBecomeSpaces() {
        let out = ReleaseNotesFormatter.plainSummary("一\r\n\r\n\r\n\r\n二\t三", maxLength: 100)
        XCTAssertEqual(out, "一\n\n二 三")
    }

    func testTruncatesAtMaxLengthWithEllipsis() {
        let out = ReleaseNotesFormatter.plainSummary(String(repeating: "字", count: 500), maxLength: 50)
        XCTAssertEqual(out.count, 50)
        XCTAssertTrue(out.hasSuffix("…"))
    }

    func testDoesNotCutInsideEmojiGraphemeCluster() {
        let out = ReleaseNotesFormatter.plainSummary(String(repeating: "👨‍👩‍👧", count: 40), maxLength: 10)
        XCTAssertLessThanOrEqual(out.count, 10)
        XCTAssertTrue(out.hasSuffix("…"))
    }

    func testChecksumLineIsRemovedFromSummary() {
        let notes = "新增更新功能。\n- SHA-256：`4f5f876063681b334bbc1b3c201addb957717ddbee11b6a2606b3e9e0727dcc7`"
        let out = ReleaseNotesFormatter.plainSummary(notes, maxLength: 300)
        XCTAssertFalse(out.contains("4f5f8760"))
        XCTAssertTrue(out.contains("新增更新功能"))
    }

    func testEmptyInputGivesEmptyString() {
        XCTAssertEqual(ReleaseNotesFormatter.plainSummary("", maxLength: 10), "")
        XCTAssertEqual(ReleaseNotesFormatter.plainSummary("   \n  ", maxLength: 10), "")
    }
}
