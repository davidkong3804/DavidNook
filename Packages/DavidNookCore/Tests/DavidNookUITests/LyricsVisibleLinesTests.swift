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

    func testFourLineVariantShowsFewerLinesThanFive() throws {
        func litBands(_ n: Int) throws -> Int {
            let image = try renderImage(
                LyricsPanelView(lines: lines, currentIndex: 3, status: .loaded, visibleLineCount: n)
                    .frame(width: 240).background(Color.black)
            )
            let px = Pixels(image)
            // 掃每一列像素的最大亮度，數出「文字帶」（連續亮列為一帶）。
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
        XCTAssertLessThan(four, five, "4 行版本可見的歌詞行數應少於 5 行版本（\(four) vs \(five)）")
        XCTAssertLessThanOrEqual(four, 4)
        XCTAssertGreaterThanOrEqual(four, 3)
    }

    func testCurrentLineStaysCenteredAndWhiteWithFourLines() throws {
        let image = try renderImage(
            LyricsPanelView(lines: lines, currentIndex: 3, status: .loaded, visibleLineCount: 4)
                .frame(width: 240).background(Color.black)
        )
        let px = Pixels(image)
        let mid = px.height / 2
        let band = (mid - px.height / 10)...(mid + px.height / 10)
        XCTAssertGreaterThan(px.maxLuminance(rows: band), 0.95, "目前行（白色）應在垂直中央")
        XCTAssertLessThan(px.maxLuminance(rows: 0...(px.height / 14)), 0.3, "上緣應淡出")
        XCTAssertLessThan(px.maxLuminance(rows: (px.height - px.height / 14)...(px.height - 1)), 0.3, "下緣應淡出")
    }
}
