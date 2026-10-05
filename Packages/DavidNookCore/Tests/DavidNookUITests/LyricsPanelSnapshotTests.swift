import SwiftUI
import XCTest
@testable import DavidNookUI

/// 歌詞面板離屏渲染（ImageRenderer，scale 2）：輸出 PNG 供人工檢視，並以像素統計做基本斷言。
/// 輸出目錄：環境變數 DAVIDNOOK_SNAPSHOT_DIR（未設定則為暫存目錄）。
@MainActor
final class LyricsPanelSnapshotTests: XCTestCase {

    // MARK: - 自編歌詞

    private let english = LyricsPanelLine.make(from: [
        "Lanterns on the quiet street",
        "We walk where the shadows meet",
        "Nobody calls us by name",
        "The night keeps time for us",
        "Somewhere a window is warm",
        "We follow the humming wires",
        "Home is a small bright word",
    ])

    private let traditional = LyricsPanelLine.make(from: [
        "測試句一，夜行的燈還亮著",
        "測試句二，我們沿著河岸走",
        "測試句三，風把名字吹遠了",
        "測試句四，後來沒有人再問",
        "測試句五，窗口亮起一盞燈",
        "測試句六，雲在遠處慢慢散",
        "測試句七，回家只剩一句話",
    ])

    private let withInterlude = LyricsPanelLine.make(from: [
        "測試句一，夜行的燈還亮著",
        "測試句二，我們沿著河岸走",
        "",
        "測試句三，風把名字吹遠了",
        "測試句四，後來沒有人再問",
        "",
    ])

    private let longLines = LyricsPanelLine.make(from: [
        "測試句一，短短的一行",
        "這是一行特別特別長的測試句子，用來檢查中文折行之後每一行是否仍然左對齊、行距是否合理",
        "A deliberately long made-up English line to check that wrapping keeps the system font and stays aligned",
        "測試句四，又是一行短的",
        "測試句五，最後一行",
    ])

    private let panelSize = CGSize(width: 240, height: 124)
    private let canvas = CGSize(width: 300, height: 170)

    // MARK: - 渲染

    private func panel(
        _ lines: [LyricsPanelLine], current: Int?, offsetMs: Int = 0, status: LyricsPanelStatus = .loaded
    ) -> some View {
        LyricsPanelView(lines: lines, currentIndex: current, offsetMs: offsetMs, status: status)
            .frame(width: panelSize.width, height: panelSize.height)
    }

    /// 視覺快照：黑色圓角瀏海風格底＋面板（可選：偏移控制）。
    private func snapshot<V: View>(_ name: String, _ content: V) throws -> CGImage {
        let image = try renderImage(NotchBackdrop(size: canvas) { content })
        let url = try writeSnapshot(image, named: name)
        XCTAssertGreaterThan((try? Data(contentsOf: url).count) ?? 0, 1_000, "PNG 太小：\(name)")
        XCTAssertEqual(image.width, Int(canvas.width * 2))
        XCTAssertEqual(image.height, Int(canvas.height * 2))
        return image
    }

    /// 斷言用：純黑底的面板，像素座標以面板為準（scale 2）。
    private func plain(_ lines: [LyricsPanelLine], current: Int?, status: LyricsPanelStatus = .loaded) throws -> Pixels {
        let image = try renderImage(
            panel(lines, current: current, status: status).background(Color.black)
        )
        return Pixels(image)
    }

    private var bands: (top: ClosedRange<Int>, middle: ClosedRange<Int>, bottom: ClosedRange<Int>) {
        let h = Int(panelSize.height * 2)
        return (0...(h / 14), (h * 3 / 10)...(h * 7 / 10), (h - h / 14)...(h - 1))
    }

    // MARK: - 8 張要求的快照＋補充

    func testEnglishCurrentLineInTheMiddle() throws {
        _ = try snapshot("01-english-current-middle", panel(english, current: 3))
        let px = try plain(english, current: 3)
        let b = bands
        XCTAssertGreaterThan(px.maxLuminance(rows: b.middle), 0.95, "目前行應為白色")
        XCTAssertLessThan(px.maxLuminance(rows: b.top), 0.3, "上緣應淡出")
        XCTAssertLessThan(px.maxLuminance(rows: b.bottom), 0.3, "下緣應淡出")
    }

    func testTraditionalChineseCurrentLine() throws {
        _ = try snapshot("02-traditional-chinese-current", panel(traditional, current: 3))
        let px = try plain(traditional, current: 3)
        let b = bands
        XCTAssertGreaterThan(px.maxLuminance(rows: b.middle), 0.95)
        XCTAssertLessThan(px.maxLuminance(rows: b.top), 0.3)
        // 其餘行是暗色（不是白色）：中央帶以外的最大亮度明顯低於目前行。
        let h = Int(panelSize.height * 2)
        XCTAssertLessThan(px.maxLuminance(rows: (h / 14)...(h * 3 / 10 - 8)), 0.7)
    }

    func testBeforeTheFirstLine() throws {
        _ = try snapshot("03-before-first-line", panel(traditional, current: nil))
        let px = try plain(traditional, current: nil)
        // 還沒開始：沒有任何一行是純白高亮。
        XCTAssertLessThan(px.maxLuminance(rows: 0...(Int(panelSize.height * 2) - 1)), 0.75)
        // 第一句仍可見（有可見像素）。
        XCTAssertGreaterThan(px.count(rows: 0...(Int(panelSize.height * 2) - 1), above: 0.2), 50)
    }

    func testAfterTheLastLineWithBlankEndMarker() throws {
        // LRC 常以空白時間戳收尾；Timeline 過了最後一行仍回傳最後一行（空白）→ 全部暗色。
        let lines = LyricsPanelLine.make(from: traditional.prefix(5).map(\.text) + [""])
        _ = try snapshot("04-after-last-line", panel(lines, current: lines.count - 1))
        let px = try plain(lines, current: lines.count - 1)
        XCTAssertLessThan(px.maxLuminance(rows: 0...(Int(panelSize.height * 2) - 1)), 0.75, "歌詞已結束，不應有白色高亮")
    }

    func testLastRealLineIsHighlightedAndCentered() throws {
        let lines = Array(traditional.prefix(5))
        _ = try snapshot("04b-last-real-line", panel(lines, current: 4))
        let px = try plain(lines, current: 4)
        XCTAssertGreaterThan(px.maxLuminance(rows: bands.middle), 0.95)
    }

    func testLongLinesWrapAndStayInsideThePanel() throws {
        _ = try snapshot("05-long-line-wrap", panel(longLines, current: 1))
        let px = try plain(longLines, current: 1)
        XCTAssertGreaterThan(px.maxLuminance(rows: bands.middle), 0.95)
        // 折行後不得超出面板右緣：最右側 6 像素欄不應有亮點。
        var rightEdgeLit = 0
        for y in 0..<px.height { for x in (px.width - 6)..<px.width where px.luminance(x: x, y: y) > 0.3 { rightEdgeLit += 1 } }
        XCTAssertEqual(rightEdgeLit, 0)
        _ = try snapshot("05b-long-english-wrap-current", panel(longLines, current: 2))
    }

    func testLoadingState() throws {
        _ = try snapshot("06-loading", panel([], current: nil, status: .loading))
        let px = try plain([], current: nil, status: .loading)
        XCTAssertGreaterThan(px.count(rows: 0...(Int(panelSize.height * 2) - 1), above: 0.2), 50, "應顯示『載入歌詞中…』")
    }

    func testNoLyricsState() throws {
        _ = try snapshot("07-no-lyrics", panel([], current: nil, status: .noLyrics))
        let px = try plain([], current: nil, status: .noLyrics)
        XCTAssertGreaterThan(px.count(rows: 0...(Int(panelSize.height * 2) - 1), above: 0.2), 50)
    }

    func testInstrumentalState() throws {
        _ = try snapshot("08-instrumental", panel([], current: nil, status: .instrumental))
        let px = try plain([], current: nil, status: .instrumental)
        XCTAssertGreaterThan(px.count(rows: 0...(Int(panelSize.height * 2) - 1), above: 0.2), 20)
    }

    func testErrorState() throws {
        _ = try snapshot("09-error", panel([], current: nil, status: .error))
    }

    func testInterludeBlankLinesRenderAsWhitespace() throws {
        _ = try snapshot("10-interlude-blank-lines", panel(withInterlude, current: 1))
        _ = try snapshot("10b-interlude-current-is-blank", panel(withInterlude, current: 2))
        let px = try plain(withInterlude, current: 2)
        XCTAssertLessThan(px.maxLuminance(rows: 0...(Int(panelSize.height * 2) - 1)), 0.75, "目前行是間奏時不應有白色高亮")
    }

    func testOffsetBadgeAndControls() throws {
        let content = VStack(spacing: 6) {
            panel(traditional, current: 3, offsetMs: 1500).frame(height: 100)
            OffsetControlView(offsetMs: 1500, onAdjust: { _ in }, onReset: {})
        }
        _ = try snapshot("11-offset-badge-and-controls", content)
        let reset = try snapshot("11b-offset-zero-controls", VStack(spacing: 6) {
            panel(traditional, current: 3).frame(height: 100)
            OffsetControlView(offsetMs: 0, onAdjust: { _ in }, onReset: {})
        })
        XCTAssertGreaterThan(reset.width, 0)
    }

    // MARK: - 純邏輯

    func testOffsetLabelFormatting() {
        XCTAssertEqual(LyricsOffsetFormat.label(offsetMs: 0), "0.0s")
        XCTAssertEqual(LyricsOffsetFormat.label(offsetMs: 500), "+0.5s")
        XCTAssertEqual(LyricsOffsetFormat.label(offsetMs: -1500), "\u{2212}1.5s")
        XCTAssertEqual(LyricsOffsetFormat.label(offsetMs: 12_000), "+12.0s")
    }

    func testDimOpacityDecreasesWithDistanceAndHasAFloor() {
        let values = (1...8).map { LyricsPanelView.dimOpacity(distance: $0) }
        XCTAssertEqual(values, values.sorted(by: >))
        XCTAssertGreaterThanOrEqual(values.last!, 0.18)
        XCTAssertLessThan(values[0], 1)
    }

    func testDefaultStringsAreTraditionalChinese() {
        XCTAssertEqual(LyricsPanelStrings.zhHant.loading, "載入歌詞中…")
        XCTAssertEqual(LyricsPanelStrings.zhHant.noLyrics, "這首歌沒有歌詞")
        XCTAssertEqual(LyricsPanelStrings.zhHant.instrumental, "純音樂")
        XCTAssertEqual(LyricsPanelStrings.zhHant.error, "無法取得歌詞")
    }

    func testBlankDetection() {
        XCTAssertTrue(LyricsPanelLine(id: 0, text: "").isBlank)
        XCTAssertTrue(LyricsPanelLine(id: 0, text: "  \t").isBlank)
        XCTAssertFalse(LyricsPanelLine(id: 0, text: "測試句一").isBlank)
    }

    func testChineseFontCascadesToPingFangTC() {
        let font = LyricsFont.nsFont(size: 14, weight: .regular)
        let cascade = font.fontDescriptor.object(forKey: .cascadeList) as? [NSFontDescriptor]
        XCTAssertEqual(cascade?.first?.object(forKey: .family) as? String, "PingFang TC")
        // 拉丁字母仍由系統字型負責：基底字型不是 PingFang。
        XCTAssertFalse(font.familyName?.contains("PingFang") ?? false)
    }
}
