import XCTest
@testable import DavidNookUI

/// 膠囊可見性狀態機：收合＋播放中＋歌詞已載入＋當前句非空＋功能開啟才顯示；暫停延遲 1.5 秒才收起。
final class LyricsPillVisibilityTests: XCTestCase {
    private typealias Input = LyricsPillVisibility.Input

    private let ok = Input(isEnabled: true, isNotchClosed: true, isPlaying: true, hasLyrics: true, hasCurrentText: true)

    func testStartsHidden() {
        XCTAssertFalse(LyricsPillVisibility().isVisible)
    }

    func testShowsWhenEverythingHolds() {
        var v = LyricsPillVisibility()
        v.update(ok, at: 0)
        XCTAssertTrue(v.isVisible)
        XCTAssertNil(v.hideDeadline)
    }

    func testEachMissingConditionHidesImmediately() {
        let breakers: [(String, (inout Input) -> Void)] = [
            ("disabled", { $0.isEnabled = false }),
            ("open", { $0.isNotchClosed = false }),
            ("no lyrics", { $0.hasLyrics = false }),
            ("interlude", { $0.hasCurrentText = false }),
        ]
        for (name, breaker) in breakers {
            var v = LyricsPillVisibility()
            v.update(ok, at: 0)
            var input = ok
            breaker(&input)
            v.update(input, at: 1)
            XCTAssertFalse(v.isVisible, name)
            XCTAssertNil(v.hideDeadline, name)
        }
    }

    func testNeverShowsWhileNotPlaying() {
        var v = LyricsPillVisibility()
        var input = ok
        input.isPlaying = false
        v.update(input, at: 0)
        XCTAssertFalse(v.isVisible)
        XCTAssertNil(v.hideDeadline)
    }

    func testPauseKeepsThePillForTheGracePeriodThenHides() {
        XCTAssertEqual(LyricsPillVisibility.pauseGrace, 1.5)
        var v = LyricsPillVisibility()
        v.update(ok, at: 0)
        var paused = ok
        paused.isPlaying = false
        v.update(paused, at: 10)
        XCTAssertTrue(v.isVisible)
        XCTAssertEqual(v.hideDeadline, 11.5)
        // 重複的暫停更新不會把期限往後推。
        v.update(paused, at: 11)
        XCTAssertEqual(v.hideDeadline, 11.5)
        v.tick(at: 11.4)
        XCTAssertTrue(v.isVisible)
        v.tick(at: 11.5)
        XCTAssertFalse(v.isVisible)
        XCTAssertNil(v.hideDeadline)
    }

    func testResumingWithinTheGraceCancelsTheHide() {
        var v = LyricsPillVisibility()
        v.update(ok, at: 0)
        var paused = ok
        paused.isPlaying = false
        v.update(paused, at: 10)
        v.update(ok, at: 10.5)
        XCTAssertNil(v.hideDeadline)
        v.tick(at: 20)
        XCTAssertTrue(v.isVisible)
    }

    func testOpeningTheNotchDuringPauseGraceHidesAtOnce() {
        var v = LyricsPillVisibility()
        v.update(ok, at: 0)
        var paused = ok
        paused.isPlaying = false
        v.update(paused, at: 10)
        paused.isNotchClosed = false
        v.update(paused, at: 10.2)
        XCTAssertFalse(v.isVisible)
        XCTAssertNil(v.hideDeadline)
    }

    func testTickWithoutDeadlineChangesNothing() {
        var v = LyricsPillVisibility()
        v.update(ok, at: 0)
        v.tick(at: 999)
        XCTAssertTrue(v.isVisible)
    }
}
