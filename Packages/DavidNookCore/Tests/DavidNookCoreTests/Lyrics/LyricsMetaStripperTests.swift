import XCTest
@testable import DavidNookCore

final class LyricsMetaStripperTests: XCTestCase {

    private let stripper = LyricsMetaStripper()
    private let title = "夜行燈"
    private let artist = "阿虛"

    /// 把 `texts` 依序排在 1s、2s、3s… 後接一段正文，回傳剝除結果。
    private func strip(_ headers: [String], then body: [LRCLine] = [L(30_000, "他們都在等天亮"), L(34_000, "我獨自走過街角")],
                       title: String? = nil, artist: String? = nil,
                       using s: LyricsMetaStripper? = nil) -> LyricsMetaStripper.Result {
        var lines: [LRCLine] = []
        for (i, t) in headers.enumerated() { lines.append(L((i + 1) * 1_000, t)) }
        lines.append(contentsOf: body)
        return (s ?? stripper).strip(lines, title: title ?? self.title, artist: artist ?? self.artist)
    }

    // MARK: - 標籤：值 格式

    func testStripsCommonCreditLabelsWithFullWidthColon() {
        let r = strip(["詞：甲", "曲：乙", "編曲：丙", "监制：丁", "製作人：戊"])
        XCTAssertEqual(r.lines.map(\.text), ["他們都在等天亮", "我獨自走過街角"])
        XCTAssertEqual(r.dropped.count, 5)
    }

    func testStripsLabelsWithHalfWidthColon() {
        let r = strip(["作词: 甲", "作曲: 乙", "OP: 某公司", "SP: 某公司"])
        XCTAssertEqual(r.lines.first?.text, "他們都在等天亮")
        XCTAssertEqual(r.dropped.count, 4)
    }

    func testStripsEnglishCreditLabelsCaseInsensitively() {
        let r = strip(["Lyrics by: someone", "MUSIC BY : someone else", "composer：x"])
        XCTAssertEqual(r.lines.first?.text, "他們都在等天亮")
        XCTAssertEqual(r.dropped.count, 3)
    }

    func testLabelMayHaveSpacesAroundColon() {
        let r = strip(["詞 ： 甲", "曲 : 乙"])
        XCTAssertEqual(r.lines.first?.text, "他們都在等天亮")
    }

    func testLabelWithEmptyValueIsStillCredit() {
        let r = strip(["作曲：", "作詞："])
        XCTAssertEqual(r.dropped.count, 2)
    }

    func testBothScriptsOfLabelAreRecognised() {
        let r = strip(["詞：a", "词：b", "曲：c", "编曲：d", "編曲：e", "作詞：f", "作词：g", "监制：h", "監製：i"])
        XCTAssertEqual(r.lines.first?.text, "他們都在等天亮")
        XCTAssertEqual(r.dropped.count, 9)
    }

    // MARK: - X - Y、歌名／歌手名

    func testStripsTitleDashArtistLine() {
        let r = strip(["夜行燈 - 阿虛"])
        XCTAssertEqual(r.dropped.map(\.text), ["夜行燈 - 阿虛"])
    }

    func testStripsArtistDashTitleLine() {
        let r = strip(["阿虛 - 夜行燈"])
        XCTAssertEqual(r.dropped.count, 1)
    }

    func testStripsDashLineThatOnlyContainsTheArtist() {
        let r = strip(["阿虛 - 某某電影主題曲"])
        XCTAssertEqual(r.dropped.count, 1)
    }

    func testAcceptsEnAndEmDashSeparators() {
        let r = strip(["夜行燈 – 阿虛", "夜行燈 — 阿虛"])
        XCTAssertEqual(r.dropped.count, 2)
    }

    func testStripsBareTitleLine() {
        let r = strip(["夜行燈"])
        XCTAssertEqual(r.dropped.map(\.text), ["夜行燈"])
    }

    func testStripsBareArtistLine() {
        let r = strip(["阿虛"])
        XCTAssertEqual(r.dropped.map(\.text), ["阿虛"])
    }

    func testBareTitleMatchIgnoresCaseAndSpaces() {
        let r = LyricsMetaStripper().strip([L(1_000, " HELLO  world "), L(20_000, "x")], title: "Hello World", artist: "Someone")
        XCTAssertEqual(r.dropped.count, 1)
        XCTAssertEqual(r.lines.map(\.text), ["x"])
    }

    func testTitleAndCreditsAndBlankLinesInSequence() {
        let r = strip(["夜行燈 - 阿虛", "詞：甲", "", "曲：乙", ""])
        XCTAssertEqual(r.lines.map(\.text), ["他們都在等天亮", "我獨自走過街角"])
        XCTAssertEqual(r.dropped.count, 5)
    }

    func testTagLikeTextLinesAreDropped() {
        let r = strip(["[ti:夜行燈]", "[ar:阿虛]", "[by:某人]"])
        XCTAssertEqual(r.lines.first?.text, "他們都在等天亮")
        XCTAssertEqual(r.dropped.count, 3)
    }

    func testNormalizerBridgesScriptDifferencesBetweenTitleAndLine() {
        // 假的「簡轉繁」：只處理本測試用到的兩個字。
        let fold: @Sendable (String) -> String = { $0.replacingOccurrences(of: "燈", with: "灯").replacingOccurrences(of: "虛", with: "虚") }
        let s = LyricsMetaStripper(normalize: fold)
        let r = strip(["夜行灯 - 阿虚"], using: s)
        XCTAssertEqual(r.dropped.count, 1)
        let withoutNormalizer = strip(["夜行灯 - 阿虚"])
        XCTAssertEqual(withoutNormalizer.dropped.count, 0, "沒有注入 normalizer 時，簡繁不同寫法不會被當成同一個名字")
    }

    func testExtraCreditLabelsCanBeInjected() {
        let s = LyricsMetaStripper(extraCreditLabels: ["海報設計"])
        XCTAssertEqual(strip(["海報設計：某人"], using: s).dropped.count, 1)
        XCTAssertEqual(strip(["海報設計：某人"]).dropped.count, 0)
    }

    // MARK: - 範圍限制：前 10 行、<25 秒

    func testOnlyTheFirstTenLinesAreInspected() {
        var lines: [LRCLine] = (1...12).map { L($0 * 1_000, "詞：甲\($0)") }
        lines.append(L(40_000, "正文"))
        let r = stripper.strip(lines, title: title, artist: artist)
        XCTAssertEqual(r.dropped.count, 10)
        XCTAssertEqual(r.lines.map(\.text), ["詞：甲11", "詞：甲12", "正文"])
    }

    func testLinesAtOrAfter25SecondsAreNeverStripped() {
        let r = stripper.strip([L(25_000, "詞：甲"), L(30_000, "正文")], title: title, artist: artist)
        XCTAssertEqual(r.lines.count, 2)
        XCTAssertEqual(r.dropped.count, 0)
    }

    func testLineJustBefore25SecondsIsStripped() {
        let r = stripper.strip([L(24_999, "詞：甲"), L(30_000, "正文")], title: title, artist: artist)
        XCTAssertEqual(r.lines.map(\.text), ["正文"])
    }

    func testCustomWindowParameters() {
        let s = LyricsMetaStripper(maxHeaderLines: 2, maxHeaderTimeMs: 5_000)
        let lines = [L(1_000, "詞：a"), L(2_000, "曲：b"), L(3_000, "編曲：c"), L(10_000, "正文")]
        let r = s.strip(lines, title: title, artist: artist)
        XCTAssertEqual(r.dropped.count, 2)
        XCTAssertEqual(r.lines.map(\.text), ["編曲：c", "正文"])
    }

    func testStopsAtTheFirstRealLyricEvenIfLaterLinesLookLikeCredits() {
        let lines = [L(1_000, "詞：甲"), L(5_000, "真正的第一句"), L(8_000, "曲：乙"), L(12_000, "第三句")]
        let r = stripper.strip(lines, title: title, artist: artist)
        XCTAssertEqual(r.lines.map(\.text), ["真正的第一句", "曲：乙", "第三句"])
        XCTAssertEqual(r.dropped.map(\.text), ["詞：甲"])
    }

    // MARK: - 不誤殺

    func testFirstLyricWithColonButNotACreditIsKept() {
        let lines = [L(10_000, "他說：我們走吧"), L(14_000, "夜很深")]
        let r = stripper.strip(lines, title: title, artist: artist)
        XCTAssertEqual(r.lines, lines)
        XCTAssertTrue(r.dropped.isEmpty)
    }

    func testEnglishColonLineThatIsNotACreditIsKept() {
        let lines = [L(10_000, "Note: this is just a sentence"), L(14_000, "next")]
        XCTAssertEqual(stripper.strip(lines, title: title, artist: artist).lines, lines)
    }

    func testLabelLookalikePrefixIsKept() {
        // 「STOP」含有 OP 兩個字母，「曲終人散」以曲開頭；都不是標籤。
        let lines = [L(10_000, "STOP: hammer time"), L(14_000, "曲終人散：我獨自離開"), L(18_000, "x")]
        XCTAssertEqual(stripper.strip(lines, title: title, artist: artist).lines, lines)
    }

    func testFirstLyricThatContainsTheTitleAsPartOfALongerSentenceIsKept() {
        let lines = [L(10_000, "夜行燈在巷口亮著"), L(14_000, "我跟著光走")]
        let r = stripper.strip(lines, title: title, artist: artist)
        XCTAssertEqual(r.lines, lines)
    }

    func testFirstLyricThatStartsWithTheArtistNameInASentenceIsKept() {
        let lines = [L(10_000, "阿虛說今天要早睡"), L(14_000, "但窗外還亮著")]
        XCTAssertEqual(stripper.strip(lines, title: title, artist: artist).lines, lines)
    }

    func testDashLineThatMentionsNeitherTitleNorArtistIsKept() {
        let lines = [L(10_000, "愛是 - 一種等待"), L(14_000, "x")]
        XCTAssertEqual(stripper.strip(lines, title: title, artist: artist).lines, lines)
    }

    func testOneCharacterTitleDoesNotKillDashLyricsThatMerelyContainIt() {
        let lines = [L(10_000, "我愛你 - 你愛我"), L(14_000, "x")]
        let r = stripper.strip(lines, title: "愛", artist: "某人")
        XCTAssertEqual(r.lines, lines)
    }

    func testEmptyTitleAndArtistNeverMatchAnything() {
        let lines = [L(1_000, "A - B"), L(2_000, "隨便一句"), L(3_000, "")]
        let r = stripper.strip(lines, title: "", artist: "   ")
        XCTAssertEqual(r.lines, lines)
        XCTAssertTrue(r.dropped.isEmpty)
    }

    func testNeverStripsEverything() {
        let lines = [L(1_000, "詞：甲"), L(2_000, "曲：乙")]
        let r = stripper.strip(lines, title: title, artist: artist)
        XCTAssertEqual(r.lines, lines, "剝完會一行歌詞都不剩時，視為誤判並原樣回傳")
        XCTAssertTrue(r.dropped.isEmpty)
    }

    func testEmptyInput() {
        let r = stripper.strip([], title: title, artist: artist)
        XCTAssertEqual(r.lines, [])
        XCTAssertEqual(r.dropped, [])
    }

    func testInputWithoutHeaderIsReturnedUntouched() {
        let lines = [L(12_000, "第一句"), L(16_000, "第二句")]
        let r = stripper.strip(lines, title: title, artist: artist)
        XCTAssertEqual(r.lines, lines)
        XCTAssertTrue(r.dropped.isEmpty)
    }

    func testBlankMarkerAfterRealLyricIsNotTouched() {
        let lines = [L(12_000, "第一句"), L(16_000, ""), L(20_000, "第二句")]
        XCTAssertEqual(stripper.strip(lines, title: title, artist: artist).lines, lines)
    }
}
