import CoreGraphics
import XCTest
@testable import DavidNookCore

/// 游標移到歌詞膠囊上 → 膠囊暫時「透過去」（變淡、滑鼠事件穿透給底下的視窗，例如瀏覽器分頁）。
final class LyricsPillPassThroughTests: XCTestCase {
    private let rect = CGRect(x: 500, y: 900, width: 300, height: 22)
    private let inside = CGPoint(x: 650, y: 910)
    private let far = CGPoint(x: 100, y: 100)

    private func engaged(_ machine: inout LyricsPillPassThrough, at start: TimeInterval = 0) -> TimeInterval {
        _ = machine.update(now: start, pointer: inside, pillRect: rect, mouseButtonDown: false)
        let later = start + LyricsPillPassThrough.engageDelay + 0.01
        XCTAssertTrue(machine.update(now: later, pointer: inside, pillRect: rect, mouseButtonDown: false))
        return later
    }

    func testPillRectIsCenteredOnTheWindowAndHangsFromTheTop() {
        let window = CGRect(x: 400, y: 800, width: 640, height: 210)
        let r = LyricsPillPassThrough.pillRect(windowFrame: window, topOffset: 38, size: CGSize(width: 300, height: 22))
        XCTAssertEqual(r.width, 300)
        XCTAssertEqual(r.height, 22)
        XCTAssertEqual(r.midX, window.midX, accuracy: 0.001)
        XCTAssertEqual(r.maxY, window.maxY - 38, accuracy: 0.001, "AppKit 座標 y 向上：上緣＝視窗上緣往下 topOffset")
    }

    func testDoesNotEngageUntilThePointerHasStayedForTheDelay() {
        var machine = LyricsPillPassThrough()
        XCTAssertFalse(machine.update(now: 0, pointer: inside, pillRect: rect, mouseButtonDown: false))
        XCTAssertFalse(machine.update(now: LyricsPillPassThrough.engageDelay - 0.02, pointer: inside, pillRect: rect, mouseButtonDown: false))
        XCTAssertTrue(machine.update(now: LyricsPillPassThrough.engageDelay + 0.01, pointer: inside, pillRect: rect, mouseButtonDown: false))
    }

    func testQuickFlybyDoesNotEngageAndResetsTheTimer() {
        var machine = LyricsPillPassThrough()
        _ = machine.update(now: 0, pointer: inside, pillRect: rect, mouseButtonDown: false)
        _ = machine.update(now: 0.05, pointer: far, pillRect: rect, mouseButtonDown: false)
        // 再進來要重新計時，不能沿用第一次的 0。
        XCTAssertFalse(machine.update(now: 0.12, pointer: inside, pillRect: rect, mouseButtonDown: false))
        XCTAssertFalse(machine.update(now: 0.12 + LyricsPillPassThrough.engageDelay - 0.02, pointer: inside, pillRect: rect, mouseButtonDown: false))
    }

    func testReleasesAsSoonAsThePointerLeavesBeyondTheMargin() {
        var machine = LyricsPillPassThrough()
        let t = engaged(&machine)
        let justOutside = CGPoint(x: rect.minX - 2, y: 910)
        XCTAssertTrue(machine.update(now: t + 0.05, pointer: justOutside, pillRect: rect, mouseButtonDown: false),
                      "貼著邊緣的小抖動不能閃爍")
        let away = CGPoint(x: rect.minX - LyricsPillPassThrough.releaseMargin - 5, y: 910)
        XCTAssertFalse(machine.update(now: t + 0.1, pointer: away, pillRect: rect, mouseButtonDown: false))
    }

    func testAfterReleaseItNeedsTheDelayAgain() {
        var machine = LyricsPillPassThrough()
        let t = engaged(&machine)
        XCTAssertFalse(machine.update(now: t + 0.1, pointer: far, pillRect: rect, mouseButtonDown: false))
        XCTAssertFalse(machine.update(now: t + 0.2, pointer: inside, pillRect: rect, mouseButtonDown: false))
    }

    func testNoPillRectMeansNeverPassThroughAndResets() {
        var machine = LyricsPillPassThrough()
        let t = engaged(&machine)
        XCTAssertFalse(machine.update(now: t + 0.1, pointer: inside, pillRect: nil, mouseButtonDown: false))
        XCTAssertFalse(machine.update(now: t + 0.11, pointer: inside, pillRect: rect, mouseButtonDown: false), "重新計時")
    }

    func testMouseButtonDownBlocksEngagingButDoesNotReleaseWhileEngaged() {
        var machine = LyricsPillPassThrough()
        _ = machine.update(now: 0, pointer: inside, pillRect: rect, mouseButtonDown: true)
        XCTAssertFalse(machine.update(now: 1, pointer: inside, pillRect: rect, mouseButtonDown: true), "按著滑鼠進來（拖曳中）不啟動")

        var other = LyricsPillPassThrough()
        let t = engaged(&other)
        XCTAssertTrue(other.update(now: t + 0.5, pointer: inside, pillRect: rect, mouseButtonDown: true), "已透過去時按下滑鼠（在點分頁）要維持")
    }

    func testNonFiniteInputsAreIgnored() {
        var machine = LyricsPillPassThrough()
        XCTAssertFalse(machine.update(now: 0, pointer: CGPoint(x: CGFloat.nan, y: 5), pillRect: rect, mouseButtonDown: false))
        XCTAssertFalse(machine.update(now: 1, pointer: CGPoint(x: CGFloat.nan, y: 5), pillRect: rect, mouseButtonDown: false))
        XCTAssertFalse(machine.update(now: 2, pointer: inside, pillRect: CGRect(x: CGFloat.nan, y: 0, width: 10, height: 10), mouseButtonDown: false))
    }
}
