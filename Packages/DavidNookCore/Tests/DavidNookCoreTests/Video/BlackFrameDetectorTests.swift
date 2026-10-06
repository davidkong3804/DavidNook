import XCTest
@testable import DavidNookCore

/// 連續全黑（受保護內容）偵測：短暫黑場（轉場）不得誤判。
final class BlackFrameDetectorTests: XCTestCase {
    func testDefaults() {
        XCTAssertEqual(BlackFrameDetector.blackThreshold, 2.0)
        XCTAssertEqual(BlackFrameDetector.requiredDuration, 3.0)
    }

    func testBrightFramesNeverTrigger() {
        var d = BlackFrameDetector()
        for t in 0..<30 { XCTAssertFalse(d.ingest(brightness: 80, at: Double(t))) }
    }

    func testSustainedBlackTriggersAfterRequiredDuration() {
        var d = BlackFrameDetector()
        XCTAssertFalse(d.ingest(brightness: 0, at: 10))
        XCTAssertFalse(d.ingest(brightness: 0, at: 11))
        XCTAssertFalse(d.ingest(brightness: 0, at: 12))
        XCTAssertFalse(d.ingest(brightness: 1.9, at: 12.9))
        XCTAssertTrue(d.ingest(brightness: 0, at: 13))
        XCTAssertTrue(d.ingest(brightness: 0, at: 14))
    }

    func testShortBlackSceneTransitionDoesNotTrigger() {
        var d = BlackFrameDetector()
        XCTAssertFalse(d.ingest(brightness: 90, at: 0))
        XCTAssertFalse(d.ingest(brightness: 0, at: 1))
        XCTAssertFalse(d.ingest(brightness: 0, at: 2))
        XCTAssertFalse(d.ingest(brightness: 70, at: 3), "轉場 2 秒後恢復，不算受保護")
        XCTAssertFalse(d.ingest(brightness: 0, at: 4))
        XCTAssertFalse(d.ingest(brightness: 0, at: 5))
        XCTAssertFalse(d.ingest(brightness: 0, at: 6.5), "第二段黑場從 4 秒起算，只有 2.5 秒")
    }

    func testThresholdIsExclusiveAtTwo() {
        var d = BlackFrameDetector()
        XCTAssertFalse(d.ingest(brightness: 2.0, at: 0))
        XCTAssertFalse(d.ingest(brightness: 2.0, at: 10), "亮度 = 2 不算黑（門檻是 < 2）")
    }

    func testRecoversAsSoonAsAFrameIsNotBlack() {
        var d = BlackFrameDetector()
        _ = d.ingest(brightness: 0, at: 0)
        XCTAssertTrue(d.ingest(brightness: 0, at: 5))
        XCTAssertFalse(d.ingest(brightness: 40, at: 6))
        XCTAssertFalse(d.ingest(brightness: 0, at: 7), "恢復後重新計時")
    }

    func testLargeGapBetweenSamplesRestartsTheClock() {
        var d = BlackFrameDetector()
        XCTAssertFalse(d.ingest(brightness: 0, at: 0))
        // 中間 10 秒沒有任何樣本（例如來源最小化暫停）：不能把空窗當成「持續全黑」。
        XCTAssertFalse(d.ingest(brightness: 0, at: 10))
        XCTAssertFalse(d.ingest(brightness: 0, at: 11))
        XCTAssertFalse(d.ingest(brightness: 0, at: 12))
        XCTAssertTrue(d.ingest(brightness: 0, at: 13))
    }

    func testInvalidBrightnessIsIgnored() {
        var d = BlackFrameDetector()
        _ = d.ingest(brightness: 0, at: 0)
        XCTAssertFalse(d.ingest(brightness: .nan, at: 1))
        XCTAssertFalse(d.ingest(brightness: -1, at: 2))
        XCTAssertFalse(d.ingest(brightness: .infinity, at: 2.5), "無窮大不是合法亮度，忽略")
        XCTAssertTrue(d.ingest(brightness: 0, at: 3), "無效樣本不打斷、也不推進黑場計時")
    }

    func testTimeGoingBackwardsDoesNotCrashOrTrigger() {
        var d = BlackFrameDetector()
        _ = d.ingest(brightness: 0, at: 100)
        XCTAssertFalse(d.ingest(brightness: 0, at: 50))
    }

    func testResetClearsState() {
        var d = BlackFrameDetector()
        _ = d.ingest(brightness: 0, at: 0)
        XCTAssertTrue(d.ingest(brightness: 0, at: 4))
        d.reset()
        XCTAssertFalse(d.isBlack)
        XCTAssertFalse(d.ingest(brightness: 0, at: 5))
    }

    func testAverageBrightnessOfBGRAGridSampling() {
        // 8x8 全黑／全白／半黑半白 BGRA（B,G,R,A）。
        let w = 8, h = 8
        var black = [UInt8](repeating: 0, count: w * h * 4)
        for i in stride(from: 3, to: black.count, by: 4) { black[i] = 255 }
        XCTAssertEqual(BlackFrameDetector.averageBrightness(bgra: black, width: w, height: h, bytesPerRow: w * 4, grid: 4), 0, accuracy: 1e-9)
        let white = [UInt8](repeating: 255, count: w * h * 4)
        XCTAssertEqual(BlackFrameDetector.averageBrightness(bgra: white, width: w, height: h, bytesPerRow: w * 4, grid: 4), 255, accuracy: 0.01)
        XCTAssertNil(BlackFrameDetector.averageBrightness(bgra: [], width: 0, height: 0, bytesPerRow: 0, grid: 4))
    }
}
