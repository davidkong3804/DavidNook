import SwiftUI
import XCTest
@testable import DavidNookUI

/// 展開尺寸模型：每分頁尺寸、使用者寬／高係數、夾限、視窗涵蓋尺寸。
final class NotchSizingTests: XCTestCase {
    private let sizing = NotchSizing()

    // MARK: - 預設值

    func testDefaultsAre720WideAndFullHeight() {
        XCTAssertEqual(NotchSizing.defaultWidth, 720)
        XCTAssertEqual(NotchSizing.defaultHeightScale, 1.0)
        XCTAssertEqual(sizing.width, 720)
        XCTAssertEqual(sizing.heightScale, 1.0)
        XCTAssertTrue(sizing.isDefault)
    }

    func testDefaultPanelSizes() {
        XCTAssertEqual(sizing.openSize(for: .home), CGSize(width: 720, height: 176))
        XCTAssertEqual(sizing.openSize(for: .clipboard), CGSize(width: 720, height: 232))
    }

    func testBothDefaultPanelsAreWiderAndShorterThanTheOld640x190ExceptClipboard() {
        let old = CGSize(width: 640, height: 190)
        XCTAssertGreaterThan(sizing.openSize(for: .home).width, old.width)
        XCTAssertLessThan(sizing.openSize(for: .home).height, old.height, "Home 要比舊版矮（不要垂得太長）")
        XCTAssertGreaterThan(sizing.openSize(for: .clipboard).height, sizing.openSize(for: .home).height)
    }

    // MARK: - 夾限

    func testWidthRangeAndStep() {
        XCTAssertEqual(NotchSizing.widthRange, 560...900)
        XCTAssertEqual(NotchSizing.widthStep, 10)
        XCTAssertEqual(NotchSizing.heightScaleRange, 0.85...1.30)
    }

    func testWidthIsClamped() {
        XCTAssertEqual(NotchSizing(width: 100).width, 560)
        XCTAssertEqual(NotchSizing(width: 5000).width, 900)
        XCTAssertEqual(NotchSizing(width: 640).width, 640)
        XCTAssertEqual(NotchSizing(width: 560).openSize(for: .home).width, 560)
        XCTAssertEqual(NotchSizing(width: 900).openSize(for: .clipboard).width, 900)
    }

    func testHeightScaleIsClamped() {
        XCTAssertEqual(NotchSizing(heightScale: 0.1).heightScale, 0.85, accuracy: 1e-9)
        XCTAssertEqual(NotchSizing(heightScale: 9).heightScale, 1.30, accuracy: 1e-9)
        XCTAssertEqual(NotchSizing(heightScale: 1.15).heightScale, 1.15, accuracy: 1e-9)
    }

    func testNonFiniteInputFallsBackToDefaults() {
        XCTAssertEqual(NotchSizing(width: .nan, heightScale: .nan), NotchSizing())
        XCTAssertEqual(NotchSizing(width: .infinity, heightScale: -.infinity).width, 900)
    }

    func testHeightScalesWholePointsOnly() {
        let small = NotchSizing(heightScale: 0.85)
        let large = NotchSizing(heightScale: 1.30)
        XCTAssertEqual(small.openSize(for: .home).height, 150)
        XCTAssertEqual(large.openSize(for: .home).height, 229)
        XCTAssertEqual(small.openSize(for: .clipboard).height, 197)
        XCTAssertEqual(large.openSize(for: .clipboard).height, 302)
        for panel in NotchSizing.Panel.allCases {
            for step in stride(from: 0.85, through: 1.30, by: 0.05) {
                let h = NotchSizing(heightScale: step).openSize(for: panel).height
                XCTAssertEqual(h, h.rounded(), "\(panel) @\(step)")
            }
        }
    }

    func testSliderSnapping() {
        XCTAssertEqual(NotchSizing.snappedWidth(724), 720)
        XCTAssertEqual(NotchSizing.snappedWidth(725), 730)
        XCTAssertEqual(NotchSizing.snappedWidth(100), 560)
        XCTAssertEqual(NotchSizing.snappedWidth(2000), 900)
    }

    // MARK: - 內容區高度與下限

    func testBodyHeightIsTotalMinusHeaderAndBottomInset() {
        XCTAssertEqual(sizing.bodyHeight(for: .home, headerHeight: 38), 176 - 38 - 12)
        XCTAssertEqual(sizing.bodyHeight(for: .clipboard, headerHeight: 38), 232 - 38 - 12)
    }

    func testTallHeaderGrowsThePanelInsteadOfSqueezingTheBody() {
        let tiny = NotchSizing(heightScale: 0.85)
        for header in stride(from: 38.0, through: 60.0, by: 1) {
            XCTAssertGreaterThanOrEqual(tiny.bodyHeight(for: .home, headerHeight: CGFloat(header)), NotchSizing.minimumBodyHeight)
            let total = tiny.openSize(for: .home, headerHeight: CGFloat(header)).height
            XCTAssertEqual(total, tiny.bodyHeight(for: .home, headerHeight: CGFloat(header)) + CGFloat(header) + NotchSizing.bottomInset)
        }
        XCTAssertEqual(NotchSizing.minimumBodyHeight, 100)
    }

    func testContentWidthSubtractsEarsAndSideInsets() {
        // 耳朵（上緣圓角）19 ＋ 內縮 12，兩側各一次。
        XCTAssertEqual(sizing.contentWidth(earInset: 19), 720 - 2 * (19 + 12))
        XCTAssertEqual(NotchSizing(width: 560).contentWidth(earInset: 19), 498)
    }

    // MARK: - 視窗

    func testClosedWindowIsExactlyTheLegacyFootprint() {
        // 關閉狀態的視窗與舊版（640×210）完全相同：不因展開尺寸變大而增加任何可能擋住點擊的區域。
        XCTAssertEqual(NotchSizing.windowSize(isOpen: false), CGSize(width: 640, height: 210))
        XCTAssertEqual(NotchSizing.legacyClosedWindowSize, CGSize(width: 640, height: 210))
    }

    func testOpenWindowCoversEveryPanelAtEveryAdjustableLimit() {
        let window = NotchSizing.windowSize(isOpen: true)
        for panel in NotchSizing.Panel.allCases {
            for width in stride(from: 560.0, through: 900.0, by: 10) {
                for scale in stride(from: 0.85, through: 1.30, by: 0.05) {
                    for header in [38.0, 45.0, 60.0] {
                        let size = NotchSizing(width: width, heightScale: scale).openSize(for: panel, headerHeight: CGFloat(header))
                        XCTAssertLessThanOrEqual(size.width, window.width, "\(panel) w\(width) s\(scale)")
                        XCTAssertLessThanOrEqual(size.height + NotchSizing.shadowPadding, window.height, "\(panel) w\(width) s\(scale)")
                    }
                }
            }
        }
        XCTAssertEqual(NotchSizing.maximumOpenSize, CGSize(width: 900, height: 302))
    }

    func testOpenWindowAlsoCoversTheSpringOvershootAndShadow() {
        // 展開彈簧過衝時，形體會暫時比目標再大一點；視窗必須留得下，否則會被視窗邊緣切掉。
        let overshoot = peakOvershoot(of: NotchMotion().curve(.open))
        let window = NotchSizing.windowSize(isOpen: true)
        let closedMinWidth: CGFloat = 150
        let closedHeight: CGFloat = 24
        let growthX = NotchSizing.maximumOpenSize.width - closedMinWidth
        let growthY = NotchSizing.maximumOpenSize.height - closedHeight
        // 寬度往左右對稱長，每側多出 growth/2 × 過衝。
        XCTAssertGreaterThanOrEqual((window.width - NotchSizing.maximumOpenSize.width) / 2, growthX / 2 * overshoot)
        XCTAssertGreaterThanOrEqual(window.height - NotchSizing.maximumOpenSize.height - NotchSizing.shadowPadding, growthY * overshoot)
    }

    func testOpenWindowContainsTheClosedWindow() {
        let open = NotchSizing.windowSize(isOpen: true)
        let closed = NotchSizing.windowSize(isOpen: false)
        XCTAssertGreaterThanOrEqual(open.width, closed.width)
        XCTAssertGreaterThanOrEqual(open.height, closed.height)
    }

    func testResizingKeepsTheTopCentreFixed() {
        let old = CGRect(x: 640, y: 870, width: 640, height: 210) // 1920×1080 螢幕頂端置中
        let new = NotchSizing.anchoredFrame(from: old, to: CGSize(width: 948, height: 346))
        XCTAssertEqual(new.midX, old.midX, accuracy: 1e-9)
        XCTAssertEqual(new.maxY, old.maxY, accuracy: 1e-9)
        XCTAssertEqual(new.size, CGSize(width: 948, height: 346))
    }

    // MARK: - 工具

    private func peakOvershoot(of curve: NotchMotionCurve) -> Double {
        var peak = 0.0
        var t = 0.0
        while t <= 3 { peak = max(peak, curve.progress(at: t)); t += 0.001 }
        return peak - 1
    }
}
