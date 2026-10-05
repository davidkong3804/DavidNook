import XCTest
@testable import DavidNookCore

final class LRCParserTests: XCTestCase {

    // MARK: - 時間標籤格式

    func testParsesCentisecondTag() {
        let doc = LRCParser.parse("[00:12.34]你好")
        XCTAssertEqual(doc.lines, [L(12_340, "你好")])
    }

    func testParsesMillisecondTag() {
        XCTAssertEqual(LRCParser.parse("[01:02.345]hi").lines, [L(62_345, "hi")])
    }

    func testParsesTagWithoutFraction() {
        XCTAssertEqual(LRCParser.parse("[01:02]hi").lines, [L(62_000, "hi")])
    }

    func testSingleDigitFractionIsTenths() {
        XCTAssertEqual(LRCParser.parse("[00:01.5]x").lines, [L(1_500, "x")])
    }

    func testCentisecondWithLeadingZero() {
        XCTAssertEqual(LRCParser.parse("[00:01.05]x").lines, [L(1_050, "x")])
    }

    func testFractionBeyondMillisecondsIsTruncated() {
        XCTAssertEqual(LRCParser.parse("[00:01.1239]x").lines, [L(1_123, "x")])
    }

    func testMinutesMayExceed59() {
        XCTAssertEqual(LRCParser.parse("[100:00.00]x").lines, [L(6_000_000, "x")])
    }

    func testSingleDigitMinuteAndSecond() {
        XCTAssertEqual(LRCParser.parse("[0:5.00]x").lines, [L(5_000, "x")])
    }

    func testWhitespaceInsideBracketsIsTolerated() {
        XCTAssertEqual(LRCParser.parse("[ 00:12.00 ]x").lines, [L(12_000, "x")])
    }

    func testTextIsTrimmed() {
        XCTAssertEqual(LRCParser.parse("[00:01.00]   spaced out  \u{3000}").lines, [L(1_000, "spaced out")])
    }

    // MARK: - 多時間標籤與排序

    func testMultipleTagsExpandToMultipleLines() {
        let doc = LRCParser.parse("[00:12.00][00:45.10]副歌")
        XCTAssertEqual(doc.lines, [L(12_000, "副歌"), L(45_100, "副歌")])
    }

    func testInterleavedMultiTagsAreSortedAcrossLines() {
        let doc = LRCParser.parse("[00:30.00][00:10.00]B\n[00:20.00]A")
        XCTAssertEqual(doc.lines, [L(10_000, "B"), L(20_000, "A"), L(30_000, "B")])
    }

    func testUnsortedInputIsSortedByTime() {
        let doc = LRCParser.parse("[00:30.00]c\n[00:10.00]a\n[00:20.00]b")
        XCTAssertEqual(doc.lines.map(\.text), ["a", "b", "c"])
    }

    func testSortIsStableForEqualTimestamps() {
        let doc = LRCParser.parse("[00:10.00]first\n[00:10.00]second\n[00:10.00]third")
        XCTAssertEqual(doc.lines.map(\.text), ["first", "second", "third"])
    }

    func testStableOrderAlsoHoldsForMixedTimestamps() {
        let doc = LRCParser.parse("[00:20.00]x1\n[00:10.00]y1\n[00:20.00]x2\n[00:10.00]y2")
        XCTAssertEqual(doc.lines.map(\.text), ["y1", "y2", "x1", "x2"])
    }

    // MARK: - [offset:] 標籤（正值＝歌詞提早顯示；解析階段不改寫行時間）

    func testPositiveOffsetIsRecordedNotApplied() {
        let doc = LRCParser.parse("[offset:+500]\n[00:10.00]x")
        XCTAssertEqual(doc.offsetMs, 500)
        XCTAssertEqual(doc.lines, [L(10_000, "x")], "解析階段不得改寫行時間")
    }

    func testNegativeOffset() {
        XCTAssertEqual(LRCParser.parse("[offset:-250]\n[00:10.00]x").offsetMs, -250)
    }

    func testOffsetWithoutSign() {
        XCTAssertEqual(LRCParser.parse("[offset:300]\n[00:10.00]x").offsetMs, 300)
    }

    func testOffsetWithSurroundingSpaces() {
        XCTAssertEqual(LRCParser.parse("[offset: +120 ]\n[00:10.00]x").offsetMs, 120)
    }

    func testInvalidOffsetIsIgnored() {
        let doc = LRCParser.parse("[offset:abc]\n[00:10.00]x")
        XCTAssertEqual(doc.offsetMs, 0)
        XCTAssertEqual(doc.lines.count, 1)
    }

    func testOffsetDefaultsToZero() {
        XCTAssertEqual(LRCParser.parse("[00:10.00]x").offsetMs, 0)
    }

    func testOffsetTagIsAlsoListedInMetadataAndNeverALyricLine() {
        let doc = LRCParser.parse("[offset:+500]\n[00:10.00]x")
        XCTAssertEqual(doc.metadata["offset"], "+500")
        XCTAssertFalse(doc.lines.contains { $0.text.contains("offset") })
    }

    // MARK: - ID tag → metadata

    func testIDTagsGoToMetadataNotToLines() {
        let lrc = """
        [ar:自編歌手]
        [ti:自編歌名]
        [al:自編專輯]
        [by:某人]
        [length:03:45]
        [00:01.00]x
        """
        let doc = LRCParser.parse(lrc)
        XCTAssertEqual(doc.metadata, ["ar": "自編歌手", "ti": "自編歌名", "al": "自編專輯", "by": "某人", "length": "03:45"])
        XCTAssertEqual(doc.lines, [L(1_000, "x")])
    }

    func testIDTagKeysAreLowercased() {
        XCTAssertEqual(LRCParser.parse("[AR:Someone]\n[00:01.00]x").metadata["ar"], "Someone")
    }

    func testEmptyIDTagValueIsKeptAsEmptyString() {
        let doc = LRCParser.parse("[ti:]\n[00:01.00]x")
        XCTAssertEqual(doc.metadata["ti"], "")
        XCTAssertEqual(doc.lines.count, 1)
    }

    func testIDTagValueMayContainColons() {
        XCTAssertEqual(LRCParser.parse("[ti:A:B]\n[00:01.00]x").metadata["ti"], "A:B")
    }

    func testIDTagValueIsTrimmed() {
        XCTAssertEqual(LRCParser.parse("[ar:  某人  ]\n[00:01.00]x").metadata["ar"], "某人")
    }

    // MARK: - CRLF / BOM

    func testCRLFLineEndings() {
        let doc = LRCParser.parse("[00:01.00]a\r\n[00:02.00]b\r\n")
        XCTAssertEqual(doc.lines, [L(1_000, "a"), L(2_000, "b")])
    }

    func testLoneCarriageReturnLineEndings() {
        let doc = LRCParser.parse("[00:01.00]a\r[00:02.00]b")
        XCTAssertEqual(doc.lines, [L(1_000, "a"), L(2_000, "b")])
    }

    func testLeadingByteOrderMarkIsIgnored() {
        let doc = LRCParser.parse("\u{FEFF}[ti:x]\n[00:01.00]a")
        XCTAssertEqual(doc.metadata["ti"], "x")
        XCTAssertEqual(doc.lines, [L(1_000, "a")])
    }

    func testBOMBeforeFirstTimeTag() {
        XCTAssertEqual(LRCParser.parse("\u{FEFF}[00:01.00]a").lines, [L(1_000, "a")])
    }

    // MARK: - Enhanced LRC <mm:ss.xxx>

    func testEnhancedWordTagsAreStripped() {
        let doc = LRCParser.parse("[00:10.00]<00:10.00>你<00:10.50>好<00:11.00>嗎")
        XCTAssertEqual(doc.lines, [L(10_000, "你好嗎")])
    }

    func testEnhancedTagsKeepSpacesBetweenWords() {
        let doc = LRCParser.parse("[00:10.00]<00:10.00>Hello <00:10.50>world")
        XCTAssertEqual(doc.lines, [L(10_000, "Hello world")])
    }

    func testEnhancedTagOnlyLineBecomesBlankMarker() {
        let doc = LRCParser.parse("[00:05.00]a\n[00:10.00]<00:10.00>")
        XCTAssertEqual(doc.lines, [L(5_000, "a"), L(10_000, "")])
    }

    func testNonTimeAngleBracketsArePreserved() {
        let doc = LRCParser.parse("[00:10.00]a <b> c")
        XCTAssertEqual(doc.lines, [L(10_000, "a <b> c")])
    }

    // MARK: - 空白行 / 間奏標記策略

    func testTrailingBlankTimestampIsKeptAsEndMarker() {
        let doc = LRCParser.parse("[00:10.00]a\n[03:25.72]")
        XCTAssertEqual(doc.lines, [L(10_000, "a"), L(205_720, "")])
    }

    func testTrailingBlankWithOnlySpaces() {
        let doc = LRCParser.parse("[00:10.00]a\n[03:25.72]   ")
        XCTAssertEqual(doc.lines.last, L(205_720, ""))
    }

    func testConsecutiveBlankLinesCollapseToTheEarliest() {
        let doc = LRCParser.parse("[00:10.00]a\n[00:20.00]\n[00:21.00]\n[00:22.00]\n[00:30.00]b")
        XCTAssertEqual(doc.lines, [L(10_000, "a"), L(20_000, ""), L(30_000, "b")])
    }

    func testBlankBetweenLyricsIsKeptAsInterlude() {
        let doc = LRCParser.parse("[00:10.00]a\n[00:20.00]\n[00:40.00]b")
        XCTAssertEqual(doc.lines, [L(10_000, "a"), L(20_000, ""), L(40_000, "b")])
    }

    func testLeadingBlankLinesAreDropped() {
        let doc = LRCParser.parse("[00:00.00]\n[00:10.00]a")
        XCTAssertEqual(doc.lines, [L(10_000, "a")])
    }

    func testBlankSharingTimestampWithTextIsDropped() {
        let doc = LRCParser.parse("[00:10.00]a\n[00:20.00]\n[00:20.00]b")
        XCTAssertEqual(doc.lines, [L(10_000, "a"), L(20_000, "b")])
    }

    func testBlankSharingTimestampIsDroppedRegardlessOfFileOrder() {
        let doc = LRCParser.parse("[00:10.00]a\n[00:20.00]b\n[00:20.00]")
        XCTAssertEqual(doc.lines, [L(10_000, "a"), L(20_000, "b")])
    }

    func testOnlyBlankLinesYieldNoLines() {
        XCTAssertEqual(LRCParser.parse("[00:01.00]\n[00:02.00]").lines, [])
    }

    func testMultiTagBlankLineCollapses() {
        let doc = LRCParser.parse("[00:10.00]a\n[00:20.00][00:30.00]")
        XCTAssertEqual(doc.lines, [L(10_000, "a"), L(20_000, "")])
    }

    func testBlankFileLinesWithoutTagsAreIgnored() {
        let doc = LRCParser.parse("\n\n[00:10.00]a\n\n\n[00:20.00]b\n")
        XCTAssertEqual(doc.lines, [L(10_000, "a"), L(20_000, "b")])
    }

    // MARK: - 錯誤輸入

    func testEmptyStringYieldsEmptyDocument() {
        let doc = LRCParser.parse("")
        XCTAssertEqual(doc.lines, [])
        XCTAssertEqual(doc.metadata, [:])
        XCTAssertEqual(doc.offsetMs, 0)
    }

    func testWhitespaceOnlyInput() {
        let doc = LRCParser.parse("  \n\r\n \t \n")
        XCTAssertEqual(doc.lines, [])
        XCTAssertEqual(doc.metadata, [:])
    }

    func testMalformedTimeTagsAreSkippedWithoutCrashing() {
        let lrc = [
            "[00:xx.00]a",      // 非數字
            "[00:61.00]c",      // 秒數 >= 60
            "[00:]d",           // 缺秒
            "[:12.00]e",        // 缺分
            "[]f",              // 空標籤
            "[00:12.]g",        // 小數點後無數字
            "[00:01.00 h",      // 沒閉合
            "00:02.00]i",       // 沒開頭括號
            "[-1:00.00]j",      // 負分鐘
            "純文字沒有時間標籤",
            "[00:03.00]ok",
        ].joined(separator: "\n")
        let doc = LRCParser.parse(lrc)
        XCTAssertEqual(doc.lines, [L(3_000, "ok")])
    }

    func testLineWithoutTagsIsNotALyricLine() {
        XCTAssertEqual(LRCParser.parse("just plain words\nmore words").lines, [])
    }

    func testBracketedNonTimeTextAfterTimeTagStaysInText() {
        let doc = LRCParser.parse("[00:05.00][Chorus]唱")
        XCTAssertEqual(doc.lines, [L(5_000, "[Chorus]唱")])
    }

    func testBracketsInsideTextArePreserved() {
        XCTAssertEqual(LRCParser.parse("[00:01.00]hello [x] world").lines, [L(1_000, "hello [x] world")])
    }

    func testTimeTagInTheMiddleOfTextIsNotExpanded() {
        let doc = LRCParser.parse("[00:01.00]hello [00:02.00] world")
        XCTAssertEqual(doc.lines.count, 1)
    }

    func testUnknownIDLikeTagGoesToMetadata() {
        let doc = LRCParser.parse("[xx:yy]\n[00:01.00]a")
        XCTAssertEqual(doc.metadata["xx"], "yy")
        XCTAssertEqual(doc.lines, [L(1_000, "a")])
    }

    func testVeryLongInputParses() {
        var lrc = ""
        for i in 0..<5_000 {
            let secs = i
            lrc += String(format: "[%02d:%02d.00]line%d\n", secs / 60, secs % 60, i)
        }
        let doc = LRCParser.parse(lrc)
        XCTAssertEqual(doc.lines.count, 5_000)
        XCTAssertEqual(doc.lines.last?.timeMs, 4_999_000)
    }

    func testLRCLineTimeConvenienceIsSeconds() {
        XCTAssertEqual(L(12_340, "x").time, 12.34, accuracy: 1e-9)
    }
}
