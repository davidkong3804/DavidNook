import XCTest
@testable import DavidNookCore

final class PlaybackClockTests: XCTestCase {

    private var clock: ManualClock!
    private var playback: PlaybackClock!

    override func setUp() {
        super.setUp()
        clock = ManualClock()
        playback = PlaybackClock(now: clock.provider)
    }

    /// 在「現在」往前 `ago` 秒取得的快照。
    private func snapshot(
        elapsed: TimeInterval,
        ago: TimeInterval = 0,
        rate: Double = 1.0,
        playing: Bool = true,
        duration: TimeInterval? = 300
    ) -> PlaybackSnapshot {
        PlaybackSnapshot(
            elapsedTime: elapsed,
            timestamp: clock.now().addingTimeInterval(-ago),
            playbackRate: rate,
            isPlaying: playing,
            duration: duration
        )
    }

    func testNoSnapshotYieldsNilPosition() {
        XCTAssertNil(playback.position())
    }

    func testPlayingInterpolatesFromTimestamp() {
        playback.update(snapshot(elapsed: 10.0, ago: 2.5))
        XCTAssertEqual(playback.position()!, 12.5, accuracy: 1e-9)
    }

    func testPositionAtTheSnapshotInstantEqualsElapsed() {
        playback.update(snapshot(elapsed: 42.0))
        XCTAssertEqual(playback.position()!, 42.0, accuracy: 1e-9)
    }

    func testPositionAdvancesWithTheInjectedClock() {
        playback.update(snapshot(elapsed: 10.0))
        clock.advance(1.0)
        XCTAssertEqual(playback.position()!, 11.0, accuracy: 1e-9)
        clock.advance(0.25)
        XCTAssertEqual(playback.position()!, 11.25, accuracy: 1e-9)
    }

    func testPositionAtExplicitDate() {
        playback.update(snapshot(elapsed: 10.0))
        let later = clock.now().addingTimeInterval(4)
        XCTAssertEqual(playback.position(at: later)!, 14.0, accuracy: 1e-9)
    }

    func testPausedPositionIsFixedNoMatterHowMuchTimePasses() {
        playback.update(snapshot(elapsed: 10.0, ago: 2.5, rate: 0, playing: false))
        XCTAssertEqual(playback.position()!, 10.0, accuracy: 1e-9)
        clock.advance(100)
        XCTAssertEqual(playback.position()!, 10.0, accuracy: 1e-9)
    }

    func testNotPlayingWithNonZeroRateIsStillFixed() {
        playback.update(snapshot(elapsed: 10.0, ago: 5, rate: 1.0, playing: false))
        XCTAssertEqual(playback.position()!, 10.0, accuracy: 1e-9)
    }

    func testPlayingFlagTrueButRateZeroIsFixed() {
        playback.update(snapshot(elapsed: 10.0, ago: 5, rate: 0, playing: true))
        XCTAssertEqual(playback.position()!, 10.0, accuracy: 1e-9)
    }

    func testHalfRate() {
        playback.update(snapshot(elapsed: 10.0, ago: 5, rate: 0.5))
        XCTAssertEqual(playback.position()!, 12.5, accuracy: 1e-9)
    }

    func testDoubleRate() {
        playback.update(snapshot(elapsed: 10.0, ago: 5, rate: 2.0))
        XCTAssertEqual(playback.position()!, 20.0, accuracy: 1e-9)
    }

    func testClampsToDurationUpperBound() {
        playback.update(snapshot(elapsed: 200, ago: 30, duration: 210))
        XCTAssertEqual(playback.position()!, 210, accuracy: 1e-9)
    }

    func testClampsToZeroLowerBound() {
        playback.update(snapshot(elapsed: -5, duration: 100))
        XCTAssertEqual(playback.position()!, 0, accuracy: 1e-9)
    }

    func testNegativeRateNeverGoesBelowZero() {
        playback.update(snapshot(elapsed: 3, ago: 10, rate: -1))
        XCTAssertEqual(playback.position()!, 0, accuracy: 1e-9)
    }

    func testZeroDurationMeansUnknownAndIsNotAnUpperBound() {
        playback.update(snapshot(elapsed: 500, duration: 0))
        XCTAssertEqual(playback.position()!, 500, accuracy: 1e-9)
    }

    func testMissingDurationMeansUnknown() {
        playback.update(snapshot(elapsed: 500, ago: 1, duration: nil))
        XCTAssertEqual(playback.position()!, 501, accuracy: 1e-9)
    }

    func testNegativeDurationMeansUnknown() {
        playback.update(snapshot(elapsed: 50, duration: -1))
        XCTAssertEqual(playback.position()!, 50, accuracy: 1e-9)
    }

    func testUpdateReplacesTheAnchorOnSeek() {
        playback.update(snapshot(elapsed: 10.0))
        clock.advance(5)
        XCTAssertEqual(playback.position()!, 15.0, accuracy: 1e-9)
        playback.update(snapshot(elapsed: 100.0))            // 使用者拖曳到 100 秒
        XCTAssertEqual(playback.position()!, 100.0, accuracy: 1e-9)
        clock.advance(1)
        XCTAssertEqual(playback.position()!, 101.0, accuracy: 1e-9)
    }

    func testResetClearsThePositionOnTrackChange() {
        playback.update(snapshot(elapsed: 10.0))
        playback.reset()
        XCTAssertNil(playback.position())
        playback.update(snapshot(elapsed: 0.0))              // 新曲目
        XCTAssertEqual(playback.position()!, 0.0, accuracy: 1e-9)
    }

    func testPauseThenResumeContinuesFromTheResumeSnapshot() {
        playback.update(snapshot(elapsed: 10.0, rate: 0, playing: false))
        clock.advance(60)
        XCTAssertEqual(playback.position()!, 10.0, accuracy: 1e-9)
        playback.update(snapshot(elapsed: 10.0))             // 恢復播放
        clock.advance(2)
        XCTAssertEqual(playback.position()!, 12.0, accuracy: 1e-9)
    }

    func testTimestampInTheFutureDoesNotRewind() {
        playback.update(snapshot(elapsed: 10.0, ago: -5))    // timestamp 比 now 晚 5 秒（時鐘偏差）
        XCTAssertEqual(playback.position()!, 10.0, accuracy: 1e-9)
    }

    func testNonFiniteElapsedIsTreatedAsZero() {
        playback.update(snapshot(elapsed: .nan))
        XCTAssertEqual(playback.position()!, 0.0, accuracy: 1e-9)
    }

    func testNonFiniteRateIsTreatedAsPaused() {
        playback.update(snapshot(elapsed: 10.0, ago: 5, rate: .nan))
        XCTAssertEqual(playback.position()!, 10.0, accuracy: 1e-9)
    }

    func testDefaultClockUsesSystemTime() {
        let real = PlaybackClock()
        real.update(PlaybackSnapshot(elapsedTime: 5, timestamp: Date(), playbackRate: 1, isPlaying: true, duration: 300))
        let p = real.position()!
        XCTAssertGreaterThanOrEqual(p, 5)
        XCTAssertLessThan(p, 10)
    }
}
