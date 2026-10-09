import CoreGraphics
import XCTest
@testable import DavidNookCore

/// 擷取輸出尺寸跟著顯示大小走（純邏輯）：浮動視窗＝視窗寬 pt × scale 夾在 480…1920 px、高 ≤ 1080；封面槽維持小尺寸（≤ 480）以省 GPU。
final class VideoCaptureSizingTests: XCTestCase {
    func testFloatingWidthFollowsDisplayWidthTimesScale() {
        let p = VideoCaptureSizing.plan(mode: .floating, displayWidthPoints: 640, scale: 2, aspectRatio: 16.0 / 9.0)
        XCTAssertEqual(p.width, 1280)
        XCTAssertEqual(p.height, 720)
        XCTAssertEqual(p.framesPerSecond, 30)
    }

    func testFloatingClampsToMinimum480AndMaximum1920() {
        XCTAssertEqual(VideoCaptureSizing.plan(mode: .floating, displayWidthPoints: 160, scale: 2, aspectRatio: 16.0 / 9.0).width, 480)
        XCTAssertEqual(VideoCaptureSizing.plan(mode: .floating, displayWidthPoints: 3000, scale: 2, aspectRatio: 16.0 / 9.0).width, 1920)
    }

    func testFloatingHeightNeverExceeds1080() {
        // 4:3：1920 寬會是 1440 高 → 改以高度 1080 為準。
        let p = VideoCaptureSizing.plan(mode: .floating, displayWidthPoints: 2000, scale: 2, aspectRatio: 4.0 / 3.0)
        XCTAssertLessThanOrEqual(p.height, 1080)
        XCTAssertEqual(p.width, 1440)
        XCTAssertEqual(p.height, 1080)
        // 很高的來源（直式）：寬度可低於 480，高度仍 ≤ 1080。
        let tall = VideoCaptureSizing.plan(mode: .floating, displayWidthPoints: 600, scale: 2, aspectRatio: 0.5)
        XCTAssertLessThanOrEqual(tall.height, 1080)
        XCTAssertGreaterThan(tall.width, 0)
    }

    func testWidthIsQuantizedToMultiplesOf8AndHeightIsEven() {
        for pt in stride(from: 250.0, through: 900.0, by: 7.3) {
            let p = VideoCaptureSizing.plan(mode: .floating, displayWidthPoints: pt, scale: 2, aspectRatio: 16.0 / 9.0)
            XCTAssertEqual(p.width % 8, 0, "width \(p.width) for \(pt)pt")
            XCTAssertEqual(p.height % 2, 0, "height \(p.height) for \(pt)pt")
        }
    }

    func testSlotStaysSmallAndTwentyFps() {
        let p = VideoCaptureSizing.plan(mode: .slot, displayWidthPoints: 400, scale: 2, aspectRatio: 16.0 / 9.0)
        XCTAssertEqual(p.width, 480, "槽寬 × scale 超過 480 → 480")
        XCTAssertEqual(p.framesPerSecond, 20)
        let small = VideoCaptureSizing.plan(mode: .slot, displayWidthPoints: 120, scale: 2, aspectRatio: 16.0 / 9.0)
        XCTAssertEqual(small.width, 240)
        let tiny = VideoCaptureSizing.plan(mode: .slot, displayWidthPoints: 40, scale: 2, aspectRatio: 16.0 / 9.0)
        XCTAssertEqual(tiny.width, 160, "最小 160")
    }

    func testInvalidInputsFallBackToSafeValues() {
        for bad in [Double.nan, 0, -5, .infinity] {
            let p = VideoCaptureSizing.plan(mode: .floating, displayWidthPoints: bad, scale: 2, aspectRatio: 16.0 / 9.0)
            XCTAssertGreaterThanOrEqual(p.width, 160)
            XCTAssertLessThanOrEqual(p.width, 1920)
        }
        let p = VideoCaptureSizing.plan(mode: .floating, displayWidthPoints: 400, scale: 0, aspectRatio: .nan)
        XCTAssertGreaterThan(p.width, 0)
        XCTAssertGreaterThan(p.height, 0)
    }

    func testReconfigureOnlyWhenWidthChangesByTenPercentOrMore() {
        let current = VideoCapturePlan(width: 960, height: 540, framesPerSecond: 30)
        XCTAssertTrue(VideoCaptureSizing.shouldReconfigure(current: nil, target: current))
        XCTAssertFalse(VideoCaptureSizing.shouldReconfigure(current: current, target: VideoCapturePlan(width: 1000, height: 562, framesPerSecond: 30)), "+4%")
        XCTAssertFalse(VideoCaptureSizing.shouldReconfigure(current: current, target: VideoCapturePlan(width: 880, height: 496, framesPerSecond: 30)), "-8%")
        XCTAssertTrue(VideoCaptureSizing.shouldReconfigure(current: current, target: VideoCapturePlan(width: 1080, height: 608, framesPerSecond: 30)), "+12.5%")
        XCTAssertTrue(VideoCaptureSizing.shouldReconfigure(current: current, target: VideoCapturePlan(width: 800, height: 450, framesPerSecond: 30)), "-16%")
    }

    func testReconfigureWhenFrameRateOrHeightRatioChanges() {
        let current = VideoCapturePlan(width: 960, height: 540, framesPerSecond: 30)
        XCTAssertTrue(VideoCaptureSizing.shouldReconfigure(current: current, target: VideoCapturePlan(width: 960, height: 540, framesPerSecond: 20)), "換模式（fps 不同）一定重設")
        XCTAssertTrue(VideoCaptureSizing.shouldReconfigure(current: current, target: VideoCapturePlan(width: 960, height: 720, framesPerSecond: 30)), "長寬比變了（裁切）")
    }
}
