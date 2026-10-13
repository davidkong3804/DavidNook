import CoreGraphics
import XCTest
@testable import DavidNookCore

final class NotchCloseWatchdogTests: XCTestCase {
    // AppKit 座標（y 向上）：螢幕 1512×982，展開瀏海 720×176 貼齊上緣置中。
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private var rect: CGRect { NotchCloseWatchdog.openRect(screenFrame: screen, size: CGSize(width: 720, height: 176)) }
    private var inside: CGPoint { CGPoint(x: 756, y: 900) }
    private var outside: CGPoint { CGPoint(x: 100, y: 300) }

    private func decide(_ w: inout NotchCloseWatchdog, at t: TimeInterval, pointer: CGPoint, open: Bool = true, hold: Bool = false, down: Bool = false) -> NotchCloseWatchdog.Decision {
        w.evaluate(now: t, isOpen: open, pointer: pointer, notchRect: rect, holdOpen: hold, mouseButtonDown: down)
    }

    func testOpenRectIsTopCentered() {
        XCTAssertEqual(rect, CGRect(x: 396, y: 982 - 176, width: 720, height: 176))
    }

    func testPointerInsideKeepsOpen() {
        var w = NotchCloseWatchdog()
        for t in stride(from: 0.0, through: 5.0, by: 0.25) { XCTAssertEqual(decide(&w, at: t, pointer: inside), .keepOpen) }
    }

    func testPointerOutsideClosesOnlyAfterGrace() {
        var w = NotchCloseWatchdog()
        XCTAssertEqual(decide(&w, at: 0, pointer: outside), .keepOpen)
        XCTAssertEqual(decide(&w, at: NotchCloseWatchdog.graceInterval - 0.05, pointer: outside), .keepOpen)
        XCTAssertEqual(decide(&w, at: NotchCloseWatchdog.graceInterval, pointer: outside), .close)
    }

    func testReenteringResetsTheTimer() {
        var w = NotchCloseWatchdog()
        _ = decide(&w, at: 0, pointer: outside)
        _ = decide(&w, at: 0.3, pointer: inside)
        XCTAssertEqual(decide(&w, at: 0.6, pointer: outside), .keepOpen)
        XCTAssertEqual(decide(&w, at: 0.6 + NotchCloseWatchdog.graceInterval - 0.05, pointer: outside), .keepOpen)
        XCTAssertEqual(decide(&w, at: 0.6 + NotchCloseWatchdog.graceInterval, pointer: outside), .close)
    }

    func testHoldOpenAndMouseButtonResetTheTimer() {
        var w = NotchCloseWatchdog()
        _ = decide(&w, at: 0, pointer: outside)
        XCTAssertEqual(decide(&w, at: 10, pointer: outside, hold: true), .keepOpen)
        // hold 解除後重新計時，不會立刻關。
        XCTAssertEqual(decide(&w, at: 10.1, pointer: outside), .keepOpen)
        XCTAssertEqual(decide(&w, at: 20, pointer: outside, down: true), .keepOpen)
        XCTAssertEqual(decide(&w, at: 20.1, pointer: outside), .keepOpen)
        XCTAssertEqual(decide(&w, at: 20.1 + NotchCloseWatchdog.graceInterval, pointer: outside), .close)
    }

    func testClosedNotchNeverAsksToClose() {
        var w = NotchCloseWatchdog()
        XCTAssertEqual(decide(&w, at: 0, pointer: outside, open: false), .keepOpen)
        XCTAssertEqual(decide(&w, at: 100, pointer: outside, open: false), .keepOpen)
        // 之後展開：從展開那一刻才開始計時。
        XCTAssertEqual(decide(&w, at: 101, pointer: outside), .keepOpen)
    }

    func testMarginAroundTheNotchCountsAsInside() {
        var w = NotchCloseWatchdog()
        let nearBottom = CGPoint(x: 756, y: rect.minY - NotchCloseWatchdog.margin + 1)
        let nearSide = CGPoint(x: rect.maxX + NotchCloseWatchdog.margin - 1, y: 900)
        let farBottom = CGPoint(x: 756, y: rect.minY - NotchCloseWatchdog.margin - 20)
        XCTAssertEqual(decide(&w, at: 0, pointer: nearBottom), .keepOpen)
        XCTAssertEqual(decide(&w, at: 5, pointer: nearBottom), .keepOpen)
        XCTAssertEqual(decide(&w, at: 6, pointer: nearSide), .keepOpen)
        XCTAssertEqual(decide(&w, at: 11, pointer: nearSide), .keepOpen)
        _ = decide(&w, at: 12, pointer: farBottom)
        XCTAssertEqual(decide(&w, at: 12 + NotchCloseWatchdog.graceInterval, pointer: farBottom), .close)
    }

    func testPointerAboveTheScreenTopStillCountsAsInsideWhenHorizontallyOver() {
        var w = NotchCloseWatchdog()
        let atTopEdge = CGPoint(x: 756, y: screen.maxY + 3)
        XCTAssertEqual(decide(&w, at: 0, pointer: atTopEdge), .keepOpen)
        XCTAssertEqual(decide(&w, at: 5, pointer: atTopEdge), .keepOpen)
    }

    func testAfterCloseTheWatchdogStartsFresh() {
        var w = NotchCloseWatchdog()
        _ = decide(&w, at: 0, pointer: outside)
        XCTAssertEqual(decide(&w, at: 1, pointer: outside), .close)
        // 再次展開後又移出：要重新等寬限時間。
        XCTAssertEqual(decide(&w, at: 2, pointer: outside), .keepOpen)
        XCTAssertEqual(decide(&w, at: 2 + NotchCloseWatchdog.graceInterval, pointer: outside), .close)
    }
}
