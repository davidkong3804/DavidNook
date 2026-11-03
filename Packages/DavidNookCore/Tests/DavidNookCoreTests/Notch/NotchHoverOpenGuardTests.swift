import CoreGraphics
import XCTest
@testable import DavidNookCore

final class NotchHoverOpenGuardTests: XCTestCase {
    // AppKit 座標（y 向上）：螢幕 1512×982，選單列 33 高，實體瀏海 190 寬、置中（x 661…851）。
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let menuBar: CGFloat = 33
    private let notch: CGFloat = 190

    private func allows(_ x: CGFloat, _ y: CGFloat, screen: CGRect? = nil, menuBar: CGFloat? = nil, notch: CGFloat? = nil) -> Bool {
        NotchHoverOpenGuard.allowsHoverOpen(
            pointer: CGPoint(x: x, y: y),
            screenFrame: screen ?? self.screen,
            menuBarHeight: menuBar ?? self.menuBar,
            notchWidth: notch ?? self.notch
        )
    }

    func testPointerOnPhysicalNotchOpens() {
        XCTAssertTrue(allows(756, 970))
    }

    func testPointerBesideNotchInMenuBarBandDoesNotOpen() {
        // 音樂活動膠囊兩側延伸（約 40pt）蓋住的區域：選單列高度、但不在實體瀏海正上方。
        XCTAssertFalse(allows(661 - 30, 970))
        XCTAssertFalse(allows(851 + 30, 970))
        // 更遠處（展開面板的耳朵、旁邊的選單列圖示）也一樣。
        XCTAssertFalse(allows(100, 975))
        XCTAssertFalse(allows(1400, 975))
    }

    func testToleranceAtNotchEdges() {
        let edge = NotchHoverOpenGuard.sideTolerance
        XCTAssertTrue(allows(661 - edge, 970))
        XCTAssertTrue(allows(851 + edge, 970))
        XCTAssertFalse(allows(661 - edge - 1, 970))
        XCTAssertFalse(allows(851 + edge + 1, 970))
    }

    func testBelowMenuBarBandAlwaysOpens() {
        // 歌詞膠囊、閉合瀏海底下的提示都畫在選單列下方：不在選單列高度，不受限制。
        XCTAssertTrue(allows(400, 982 - menuBar - 1))
        XCTAssertTrue(allows(1100, 900))
    }

    func testMenuBarBandBoundary() {
        XCTAssertFalse(allows(400, 982 - menuBar))       // 剛好在選單列最下緣：算在帶內
        XCTAssertTrue(allows(400, 982 - menuBar - 0.5))
    }

    func testPointerAboveScreenTopCountsAsInBand() {
        // 游標頂到最上緣時 y 可能略大於 maxY。
        XCTAssertFalse(allows(400, 982 + 2))
        XCTAssertTrue(allows(756, 982 + 2))
    }

    func testScreenWithNonZeroOrigin() {
        // 外接螢幕在主螢幕上方（AppKit 座標 y 從 982 起）。
        let external = CGRect(x: 291, y: 982, width: 1920, height: 1080)
        XCTAssertTrue(allows(1251, 2050, screen: external, menuBar: 24, notch: 200))
        XCTAssertFalse(allows(1251 + 140, 2050, screen: external, menuBar: 24, notch: 200))
        XCTAssertTrue(allows(1251 + 140, 2000, screen: external, menuBar: 24, notch: 200))
    }

    func testUnknownMetricsFallBackToOldBehavior() {
        XCTAssertTrue(allows(100, 975, menuBar: 0))
        XCTAssertTrue(allows(100, 975, menuBar: -5))
        XCTAssertTrue(allows(100, 975, menuBar: .nan))
        XCTAssertTrue(allows(100, 975, notch: 0))
        XCTAssertTrue(allows(100, 975, notch: .nan))
    }
}
