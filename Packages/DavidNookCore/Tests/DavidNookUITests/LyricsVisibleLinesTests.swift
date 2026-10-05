import SwiftUI
import XCTest
@testable import DavidNookUI

/// 歌詞面板的「可見行數」：預設 5 行（124 pt，與舊版固定高度相同），高度不足時降為 4 行。
@MainActor
final class LyricsVisibleLinesTests: XCTestCase {
    private let lines = LyricsPanelLine.make(from: [
        "測試句一，夜行的燈還亮著",
        "測試句二，我們沿著河岸走",
        "測試句三，風把名字吹遠了",
        "測試句四，後來沒有人再問",
        "測試句五，窗口亮起一盞燈",
        "測試句六，雲在遠處慢慢散",
        "測試句七，回家只剩一句話",
        "測試句八，故事停在這一行",
    ])

    // MARK: - 純邏輯

    func testHeightForVisibleLines() {
        XCTAssertEqual(LyricsPanelMetrics.defaultVisibleLines, 5)
        XCTAssertEqual(LyricsPanelMetrics.height(forVisibleLines: 5), 124, "與舊版固定高度 124 相同")
        XCTAssertEqual(LyricsPanelMetrics.height(forVisibleLines: 4), 100)
        XCTAssertEqual(LyricsPanelMetrics.height(forVisibleLines: 3), 76)
        XCTAssertEqual(LyricsPanelMetrics.height(forVisibleLines: 7), 172)
        let heights = (3...7).map { LyricsPanelMetrics.height(forVisibleLines: $0) }
        XCTAssertEqual(heights, heights.sorted())
    }

    func testVisibleLineCountIsClamped() {
        XCTAssertEqual(LyricsPanelMetrics.clampedVisibleLines(1), 3)
        XCTAssertEqual(LyricsPanelMetrics.clampedVisibleLines(99), 7)
        XCTAssertEqual(LyricsPanelMetrics.clampedVisibleLines(5), 5)
        XCTAssertEqual(LyricsPanelMetrics.height(forVisibleLines: 0), LyricsPanelMetrics.height(forVisibleLines: 3))
    }

    func testVisibleLinesForAvailableHeight() {
        XCTAssertEqual(LyricsPanelMetrics.visibleLines(forAvailableHeight: 126), 5)
        XCTAssertEqual(LyricsPanelMetrics.visibleLines(forAvailableHeight: 124), 5)
        XCTAssertEqual(LyricsPanelMetrics.visibleLines(forAvailableHeight: 123), 4, "高度不足 5 行 → 降為 4 行")
        XCTAssertEqual(LyricsPanelMetrics.visibleLines(forAvailableHeight: 100), 4)
        XCTAssertEqual(LyricsPanelMetrics.visibleLines(forAvailableHeight: 99), 3)
        XCTAssertEqual(LyricsPanelMetrics.visibleLines(forAvailableHeight: 20), 3)
        XCTAssertEqual(LyricsPanelMetrics.visibleLines(forAvailableHeight: 400), 7)
        // 取到的行數所需高度一定放得進可用高度（至少 3 行除外）。
        for h in stride(from: 76.0, through: 200.0, by: 1) {
            let n = LyricsPanelMetrics.visibleLines(forAvailableHeight: CGFloat(h))
            XCTAssertLessThanOrEqual(LyricsPanelMetrics.height(forVisibleLines: n), CGFloat(h) + 0.001, "h=\(h)")
        }
    }

    // MARK: - 視圖

    /// 以固定寬度渲染、不給高度：視圖自己的高度就是 `visibleLineCount` 對應的高度。
    private func renderedHeight(visibleLineCount: Int?) throws -> CGFloat {
        let view: some View = {
            if let visibleLineCount {
                return AnyView(LyricsPanelView(lines: lines, currentIndex: 3, status: .loaded, visibleLineCount: visibleLineCount))
            }
            return AnyView(LyricsPanelView(lines: lines, currentIndex: 3, status: .loaded))
        }()
        let image = try renderImage(view.frame(width: 240).background(Color.black))
        return CGFloat(image.height) / 2
    }

    func testViewHeightFollowsVisibleLineCount() throws {
        XCTAssertEqual(try renderedHeight(visibleLineCount: nil), 124, accuracy: 0.5, "預設為 5 行")
        XCTAssertEqual(try renderedHeight(visibleLineCount: 5), 124, accuracy: 0.5)
        XCTAssertEqual(try renderedHeight(visibleLineCount: 4), 100, accuracy: 0.5)
        XCTAssertEqual(try renderedHeight(visibleLineCount: 7), 172, accuracy: 0.5)
    }

    /// 「n 行」是版面預算（n × 24 + 4 pt，含上下兩行半透明的淡出邊緣），不是精確的文字帶數：
    /// 4 行版本比 5 行版本矮 24 pt，且最外側那兩行幾乎被淡出遮罩吃掉。這裡只驗證不會比 5 行版本更多。
    func testFourLineVariantNeverShowsMoreTextBandsThanFiveLine() throws {
        func litBands(_ n: Int) throws -> Int {
            let image = try renderImage(
                LyricsPanelView(lines: lines, currentIndex: 3, status: .loaded, visibleLineCount: n)
                    .frame(width: 240).background(Color.black)
            )
            let px = Pixels(image)
            var bands = 0
            var inBand = false
            for y in 0..<px.height {
                let lit = px.maxLuminance(rows: y...y) > 0.12
                if lit && !inBand { bands += 1 }
                inBand = lit
            }
            return bands
        }
        let four = try litBands(4)
        let five = try litBands(5)
        let seven = try litBands(7)
        XCTAssertLessThanOrEqual(four, five)
        XCTAssertLessThanOrEqual(five, seven)
        XCTAssertLessThanOrEqual(four, 5)
        XCTAssertGreaterThanOrEqual(four, 3)
        XCTAssertGreaterThan(seven, five - 1)
    }

    // MARK: - 焦點位置（偶數行不得把最外側的行切半）

    func testFocusFractionIsCenteredForOddCountsAndRaisedForEvenCounts() {
        for n in [3, 5, 7] {
            XCTAssertEqual(LyricsPanelMetrics.focusFraction(forVisibleLines: n), 0.5, accuracy: 1e-9, "n=\(n)")
        }
        XCTAssertEqual(LyricsPanelMetrics.focusFraction(forVisibleLines: 4), 38.0 / 100, accuracy: 1e-9)
        XCTAssertEqual(LyricsPanelMetrics.focusFraction(forVisibleLines: 6), 62.0 / 148, accuracy: 1e-9)
    }

    func testEveryVisibleLineSlotFitsInsideThePanel() {
        // 以一行高 17、節距 24 估算：目前行前後各取 n 個格子中心，整行（±8.5）都在 0…高度 之內。
        let pitch = LyricsPanelMetrics.linePitch()
        for n in LyricsPanelMetrics.visibleLinesRange {
            let height = LyricsPanelMetrics.height(forVisibleLines: n)
            let focusY = LyricsPanelMetrics.focusFraction(forVisibleLines: n) * height
            let before = Int((focusY - 2 - 8.5) / pitch + 1e-9)          // 目前行之前放得下的整行數
            let after = Int((height - focusY - 8.5 - 2 + 8.5) / pitch + 1e-9)
            XCTAssertEqual(before + 1 + after, n, "n=\(n)：整行可見數應等於 n（before \(before)、after \(after)）")
            let top = focusY - CGFloat(before) * pitch - 8.5
            let bottom = focusY + CGFloat(after) * pitch + 8.5
            XCTAssertGreaterThanOrEqual(top, 0, "n=\(n) 最上一行被切")
            XCTAssertLessThanOrEqual(bottom, height, "n=\(n) 最下一行被切")
        }
    }

    func testCurrentLineIsWhiteAtTheFocusPositionWithFourLines() throws {
        let image = try renderImage(
            LyricsPanelView(lines: lines, currentIndex: 3, status: .loaded, visibleLineCount: 4)
                .frame(width: 240).background(Color.black)
        )
        let px = Pixels(image)
        let focus = Int(LyricsPanelMetrics.focusFraction(forVisibleLines: 4) * CGFloat(px.height))
        let band = (focus - px.height / 12)...(focus + px.height / 12)
        XCTAssertGreaterThan(px.maxLuminance(rows: band), 0.95, "目前行（白色）應在焦點位置（約 38% 高度）")
        // 面板正中央（50%）不是目前行：整個目前行都在焦點帶內，中央帶下方的下一行是暗色。
        let below = (focus + px.height / 6)...(focus + px.height / 3)
        XCTAssertLessThan(px.maxLuminance(rows: below), 0.75)
        XCTAssertLessThan(px.maxLuminance(rows: 0...(px.height / 14)), 0.3, "上緣應淡出")
        XCTAssertLessThan(px.maxLuminance(rows: (px.height - px.height / 14)...(px.height - 1)), 0.3, "下緣應淡出")
    }

    func testCurrentLineStaysCenteredAndWhiteWithFiveLines() throws {
        let image = try renderImage(
            LyricsPanelView(lines: lines, currentIndex: 3, status: .loaded, visibleLineCount: 5)
                .frame(width: 240).background(Color.black)
        )
        let px = Pixels(image)
        let mid = px.height / 2
        XCTAssertGreaterThan(px.maxLuminance(rows: (mid - px.height / 10)...(mid + px.height / 10)), 0.95)
    }
}
