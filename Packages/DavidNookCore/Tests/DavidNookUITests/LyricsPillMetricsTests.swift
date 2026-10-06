import XCTest
@testable import DavidNookUI

/// 膠囊的設定夾限、尺寸與「不超出視窗涵蓋範圍」的保證。
final class LyricsPillMetricsTests: XCTestCase {
    private typealias M = LyricsPillMetrics

    func testDefaultsAndRanges() {
        XCTAssertEqual(M.defaultDropDistance, 6)
        XCTAssertEqual(M.dropDistanceRange, -8...40)
        XCTAssertEqual(M.defaultMaxWidth, 360)
        XCTAssertEqual(M.maxWidthRange, 240...520)
        XCTAssertEqual(M.defaultFontSize, 12)
        XCTAssertEqual(M.fontSizeRange, 11...16)
        XCTAssertEqual(M.defaultSpeed, 1)
        XCTAssertEqual(M.speedRange, 0.5...2)
        XCTAssertEqual(M.height, 22)
    }

    func testClamping() {
        XCTAssertEqual(M.clampedDropDistance(-100), -8)
        XCTAssertEqual(M.clampedDropDistance(100), 40)
        XCTAssertEqual(M.clampedDropDistance(12), 12)
        XCTAssertEqual(M.clampedDropDistance(.nan), 6)
        XCTAssertEqual(M.clampedMaxWidth(10), 240)
        XCTAssertEqual(M.clampedMaxWidth(9999), 520)
        XCTAssertEqual(M.clampedMaxWidth(.nan), 360)
        XCTAssertEqual(M.clampedFontSize(5), 11)
        XCTAssertEqual(M.clampedFontSize(40), 16)
        XCTAssertEqual(M.clampedFontSize(.nan), 12)
        XCTAssertEqual(M.clampedSpeed(0), 0.5)
        XCTAssertEqual(M.clampedSpeed(9), 2)
        XCTAssertEqual(M.clampedSpeed(.nan), 1)
    }

    func testPillWidthHugsTextButStaysWithinBounds() {
        XCTAssertEqual(M.pillWidth(textWidth: 100, maxWidth: 360), 100 + 2 * M.horizontalPadding)
        XCTAssertEqual(M.pillWidth(textWidth: 900, maxWidth: 360), 360)
        XCTAssertEqual(M.pillWidth(textWidth: 0, maxWidth: 360), M.minimumWidth)
        XCTAssertEqual(M.pillWidth(textWidth: .nan, maxWidth: 360), M.minimumWidth)
        XCTAssertEqual(M.pillWidth(textWidth: 900, maxWidth: 10), 240, "最大寬度先夾到 240")
        XCTAssertEqual(M.textContainerWidth(pillWidth: 360), 360 - 2 * M.horizontalPadding)
    }

    func testTopOffsetIsRelativeToTheNotchBottomAndNeverAboveTheScreen() {
        XCTAssertEqual(M.topOffset(notchBottom: 32, dropDistance: 6), 38)
        XCTAssertEqual(M.topOffset(notchBottom: 32, dropDistance: -8), 24)
        XCTAssertEqual(M.topOffset(notchBottom: 32, dropDistance: 500), 72, "下拉距離先夾到 40")
        XCTAssertEqual(M.topOffset(notchBottom: 4, dropDistance: -8), 0)
    }

    func testWorstCaseStaysInsideTheClosedAndCoveringWindows() {
        let bottom = M.topOffset(notchBottom: M.maximumAssumedNotchBottom, dropDistance: 999) + M.height
        XCTAssertEqual(bottom, M.maximumBottomExtent)
        let closed = NotchSizing.legacyClosedWindowSize
        let covering = NotchSizing.coveringWindowSize
        XCTAssertLessThanOrEqual(M.maximumBottomExtent, closed.height - M.windowBottomPadding)
        XCTAssertLessThanOrEqual(M.maximumBottomExtent, covering.height)
        XCTAssertLessThanOrEqual(M.maxWidthRange.upperBound, closed.width)
        XCTAssertLessThanOrEqual(M.maxWidthRange.upperBound, covering.width)
    }

    func testLineChangeMotion() {
        let normal = M.lineChangeMotion(NotchMotion(speed: 1))
        XCTAssertEqual(normal.duration, NotchMotion.Constants.contentRevealResponse, accuracy: 1e-9)
        XCTAssertEqual(normal.offsetY, 3)
        let fast = M.lineChangeMotion(NotchMotion(speed: 2))
        XCTAssertEqual(fast.duration, normal.duration / 2, accuracy: 1e-9)
        let reduced = M.lineChangeMotion(NotchMotion(speed: 1, reduceMotion: true))
        XCTAssertEqual(reduced.duration, NotchMotion.Constants.reducedDuration, accuracy: 1e-9)
        XCTAssertEqual(reduced.offsetY, 0)
        let off = M.lineChangeMotion(NotchMotion(isEnabled: false))
        XCTAssertEqual(off.duration, 0)
        XCTAssertEqual(off.offsetY, 0)
    }
}
