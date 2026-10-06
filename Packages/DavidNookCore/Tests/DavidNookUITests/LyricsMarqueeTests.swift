import XCTest
@testable import DavidNookUI

/// 跑馬燈時間軸：起點停頓 → 勻速 → 句尾停頓；放得下不捲；要在下一句開始前跑完（有速度上下限）。
final class LyricsMarqueeTests: XCTestCase {
    private typealias C = LyricsMarquee.Constants

    // MARK: 放得下

    func testTextThatFitsNeverScrolls() {
        let m = LyricsMarquee(containerWidth: 300, textWidth: 240, lineDuration: 4)
        XCTAssertFalse(m.needsScrolling)
        XCTAssertEqual(m.overflow, 0)
        for t in [0.0, 0.4, 1, 3, 100] {
            XCTAssertEqual(m.scrollOffset(at: t), 0)
            XCTAssertFalse(m.isScrolling(at: t))
        }
    }

    func testHalfPointOverflowCountsAsFitting() {
        XCTAssertFalse(LyricsMarquee(containerWidth: 300, textWidth: 300.4, lineDuration: 4).needsScrolling)
        XCTAssertTrue(LyricsMarquee(containerWidth: 300, textWidth: 301, lineDuration: 4).needsScrolling)
    }

    func testDegenerateInputsAreSafe() {
        for (c, t) in [(CGFloat.nan, 300), (300, .nan), (0, 300), (-5, 300), (300, -1), (.infinity, 300)] as [(CGFloat, CGFloat)] {
            let m = LyricsMarquee(containerWidth: c, textWidth: t, lineDuration: 4)
            XCTAssertFalse(m.needsScrolling, "\(c) \(t)")
            XCTAssertEqual(m.scrollOffset(at: 1), 0)
        }
        let m = LyricsMarquee(containerWidth: 300, textWidth: 500, lineDuration: .nan, speedMultiplier: .nan)
        XCTAssertTrue(m.speed.isFinite && m.speed > 0)
        XCTAssertEqual(m.scrollOffset(at: -3), 0)
        XCTAssertEqual(m.scrollOffset(at: .nan), 0)
    }

    // MARK: 時間軸形狀

    private let long = LyricsMarquee(containerWidth: 300, textWidth: 500, lineDuration: 5)

    func testHoldsAtStartForTheStartPause() {
        XCTAssertEqual(C.startPause, 0.4)
        XCTAssertEqual(long.scrollOffset(at: 0), 0)
        XCTAssertEqual(long.scrollOffset(at: 0.39), 0)
        XCTAssertEqual(long.scrollOffset(at: C.startPause), 0)
        XCTAssertGreaterThan(long.scrollOffset(at: C.startPause + 0.1), 0)
    }

    func testMovesAtConstantSpeedThenHoldsAtTheEnd() {
        let t1 = C.startPause + 0.5, t2 = C.startPause + 1.5
        XCTAssertEqual(long.scrollOffset(at: t2) - long.scrollOffset(at: t1), long.speed * 1.0, accuracy: 1e-6)
        XCTAssertEqual(long.scrollOffset(at: long.finishTime), long.overflow, accuracy: 1e-6)
        XCTAssertEqual(long.scrollOffset(at: long.finishTime + 5), long.overflow)
        XCTAssertEqual(long.scrollOffset(at: 10_000), long.overflow)
        // 單調不減、不超過 overflow。
        var last = 0.0 as CGFloat
        for step in 0...600 {
            let v = long.scrollOffset(at: Double(step) / 100)
            XCTAssertGreaterThanOrEqual(v, last)
            XCTAssertLessThanOrEqual(v, long.overflow)
            last = v
        }
    }

    func testFramesAreOnlyNeededUntilTheScrollFinishes() {
        XCTAssertTrue(long.isScrolling(at: 0))
        XCTAssertTrue(long.isScrolling(at: long.finishTime - 0.01))
        XCTAssertFalse(long.isScrolling(at: long.finishTime))
        XCTAssertFalse(long.isScrolling(at: long.finishTime + 3))
    }

    // MARK: 在下一句開始前跑完

    func testFinishesBeforeTheNextLineWithTheEndPauseToSpare() {
        for duration in [3.0, 4, 5, 8, 12] {
            let m = LyricsMarquee(containerWidth: 300, textWidth: 520, lineDuration: duration)
            XCTAssertLessThanOrEqual(m.finishTime, duration - C.endPause + 1e-9, "duration \(duration)")
        }
    }

    func testSlowMultiplierStillFinishesInTime() {
        let m = LyricsMarquee(containerWidth: 300, textWidth: 500, lineDuration: 5, speedMultiplier: 0.5)
        XCTAssertLessThanOrEqual(m.finishTime, 5 - C.endPause + 1e-9)
    }

    func testFasterMultiplierScrollsFaster() {
        let normal = LyricsMarquee(containerWidth: 300, textWidth: 500, lineDuration: 5, speedMultiplier: 1)
        let fast = LyricsMarquee(containerWidth: 300, textWidth: 500, lineDuration: 5, speedMultiplier: 2)
        XCTAssertEqual(fast.speed, normal.speed * 2, accuracy: 1e-6)
        XCTAssertLessThan(fast.finishTime, normal.finishTime)
    }

    func testMultiplierIsClampedToTheSupportedRange() {
        let a = LyricsMarquee(containerWidth: 300, textWidth: 500, lineDuration: 5, speedMultiplier: 50)
        let b = LyricsMarquee(containerWidth: 300, textWidth: 500, lineDuration: 5, speedMultiplier: 2)
        XCTAssertEqual(a.speed, b.speed)
    }

    // MARK: 速度上下限

    func testTightLineSpeedsUpToTheCapButNoFurther() {
        let m = LyricsMarquee(containerWidth: 300, textWidth: 520, lineDuration: 1.5)
        XCTAssertEqual(m.speed, C.maxSpeed)
        XCTAssertEqual(m.scrollDuration, m.overflow / C.maxSpeed, accuracy: 1e-9)
    }

    func testVeryLongLineNeverCrawlsBelowTheMinimum() {
        let m = LyricsMarquee(containerWidth: 300, textWidth: 340, lineDuration: 60)
        XCTAssertEqual(m.speed, C.minSpeed)
    }

    func testUnknownDurationUsesTheFallback() {
        let unknown = LyricsMarquee(containerWidth: 300, textWidth: 500, lineDuration: nil)
        let explicit = LyricsMarquee(containerWidth: 300, textWidth: 500, lineDuration: C.fallbackLineDuration)
        XCTAssertEqual(unknown, explicit)
    }
}
