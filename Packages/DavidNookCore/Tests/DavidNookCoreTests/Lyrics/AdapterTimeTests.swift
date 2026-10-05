import XCTest
@testable import DavidNookCore

/// mediaremote-adapter（v0.7.7）輸出欄位的時間換算。
///
/// 依據上游 README 與原始碼（src/adapter/now_playing.m、src/utility/helpers.m）：
/// - 預設輸出：`elapsedTime`/`duration` 為秒（Double），`timestamp` 是 **UTC、秒級解析度** 的字串
///   `yyyy-MM-dd'T'HH:mm:ss'Z'`（小數秒被截掉，位置推算最多差 1 秒）。
/// - `--micros`：改成 `elapsedTimeMicros`/`durationMicros`（微秒）與 `timestampEpochMicros`（epoch 微秒，整數）。
/// 這些測試以文件／原始碼推定的格式構造資料；**未用真實播放驗證**。
final class AdapterTimeTests: XCTestCase {

    // MARK: - 秒數：微秒優先

    func testMicrosAreConvertedToSeconds() {
        XCTAssertEqual(AdapterTime.seconds(micros: 12_345_678, seconds: nil)!, 12.345678, accuracy: 1e-9)
    }

    func testMicrosTakePrecedenceOverSeconds() {
        XCTAssertEqual(AdapterTime.seconds(micros: 2_000_000, seconds: 99)!, 2.0, accuracy: 1e-9)
    }

    func testFallsBackToSecondsWhenMicrosMissing() {
        XCTAssertEqual(AdapterTime.seconds(micros: nil, seconds: 7.5)!, 7.5, accuracy: 1e-9)
    }

    func testBothMissingYieldsNil() {
        XCTAssertNil(AdapterTime.seconds(micros: nil, seconds: nil))
    }

    func testNonFiniteInputsAreRejected() {
        XCTAssertNil(AdapterTime.seconds(micros: .nan, seconds: nil))
        XCTAssertNil(AdapterTime.seconds(micros: .infinity, seconds: nil))
        XCTAssertEqual(AdapterTime.seconds(micros: .nan, seconds: 3)!, 3, accuracy: 1e-9)
    }

    // MARK: - 時間戳：epoch 微秒優先

    func testEpochMicrosKeepSubSecondPrecision() {
        // 2026-10-05T01:44:12.345678Z
        let date = AdapterTime.date(epochMicros: 1_791_164_652_345_678, iso8601: nil)!
        XCTAssertEqual(date.timeIntervalSince1970, 1_791_164_652.345678, accuracy: 1e-5)
    }

    func testEpochMicrosTakePrecedenceOverISOString() {
        let date = AdapterTime.date(epochMicros: 1_791_164_652_500_000, iso8601: "2020-01-01T00:00:00Z")!
        XCTAssertEqual(date.timeIntervalSince1970, 1_791_164_652.5, accuracy: 1e-6)
    }

    func testISOStringIsParsedAsUTCWithSecondResolution() {
        // 上游預設格式：UTC、無小數秒。
        let date = AdapterTime.date(epochMicros: nil, iso8601: "2026-10-05T01:44:12Z")!
        XCTAssertEqual(date.timeIntervalSince1970, 1_791_164_652, accuracy: 1e-9)
    }

    func testISOStringWithFractionIsAlsoAccepted() {
        let date = AdapterTime.date(epochMicros: nil, iso8601: "2026-10-05T01:44:12.250Z")!
        XCTAssertEqual(date.timeIntervalSince1970, 1_791_164_652.25, accuracy: 1e-3)
    }

    func testGarbageTimestampYieldsNil() {
        XCTAssertNil(AdapterTime.date(epochMicros: nil, iso8601: "not a date"))
        XCTAssertNil(AdapterTime.date(epochMicros: nil, iso8601: ""))
        XCTAssertNil(AdapterTime.date(epochMicros: nil, iso8601: nil))
        XCTAssertNil(AdapterTime.date(epochMicros: .nan, iso8601: nil))
        XCTAssertNil(AdapterTime.date(epochMicros: -1, iso8601: nil))
    }

    // MARK: - 餵進 PlaybackClock：位置＝elapsed + (now − timestamp) × rate

    func testMicrosSnapshotYieldsMillisecondAccuratePosition() {
        // 在 timestamp 之後 0.4 秒查詢；若只有秒級時間戳，這裡會有最多 1 秒誤差。
        let timestamp = AdapterTime.date(epochMicros: 1_791_164_652_900_000, iso8601: nil)!
        let clock = PlaybackClock(now: { timestamp.addingTimeInterval(0.4) })
        clock.update(PlaybackSnapshot(
            elapsedTime: AdapterTime.seconds(micros: 61_250_000, seconds: nil)!,
            timestamp: timestamp,
            playbackRate: 1,
            isPlaying: true,
            duration: AdapterTime.seconds(micros: 200_000_000, seconds: nil)
        ))
        XCTAssertEqual(clock.position()!, 61.65, accuracy: 1e-6)
    }

    // MARK: - PlaybackSnapshot.rebased(at:)：沒有新錨點的狀態變化

    private func snapshot(
        elapsed: TimeInterval, at timestamp: Date, rate: Double = 1, playing: Bool = true, duration: TimeInterval? = 200
    ) -> PlaybackSnapshot {
        PlaybackSnapshot(elapsedTime: elapsed, timestamp: timestamp, playbackRate: rate, isPlaying: playing, duration: duration)
    }

    func testRebasedPlayingMovesAnchorToNowAndKeepsPosition() {
        let t0 = ManualClock.reference
        let s = snapshot(elapsed: 10, at: t0)
        let r = s.rebased(at: t0.addingTimeInterval(3))
        XCTAssertEqual(r.elapsedTime, 13, accuracy: 1e-9)
        XCTAssertEqual(r.timestamp, t0.addingTimeInterval(3))
        XCTAssertTrue(r.isPlaying)
        XCTAssertEqual(r.position(at: t0.addingTimeInterval(5)), 15, accuracy: 1e-9)
    }

    func testRebasedPausedKeepsElapsed() {
        let t0 = ManualClock.reference
        let s = snapshot(elapsed: 10, at: t0, rate: 0, playing: false)
        let r = s.rebased(at: t0.addingTimeInterval(30))
        XCTAssertEqual(r.elapsedTime, 10, accuracy: 1e-9)
        XCTAssertEqual(r.position(at: t0.addingTimeInterval(60)), 10, accuracy: 1e-9)
    }

    /// 暫停後恢復播放（沒有新錨點）：必須先把暫停位置固定下來再改成播放，否則會一口氣多算暫停時間。
    func testResumeAfterPauseDoesNotOvershootByThePauseDuration() {
        let t0 = ManualClock.reference
        let paused = snapshot(elapsed: 10, at: t0, rate: 0, playing: false)
        // 30 秒後收到「恢復播放」但沒有新的 elapsed/timestamp：以 rebased 取新錨點，再改為播放中。
        let resumeAt = t0.addingTimeInterval(30)
        var resumed = paused.rebased(at: resumeAt)
        resumed.isPlaying = true
        resumed.playbackRate = 1
        XCTAssertEqual(resumed.position(at: resumeAt.addingTimeInterval(2)), 12, accuracy: 1e-9)
    }

    func testRebasedClampsToDuration() {
        let t0 = ManualClock.reference
        let s = snapshot(elapsed: 195, at: t0, duration: 200)
        let r = s.rebased(at: t0.addingTimeInterval(60))
        XCTAssertEqual(r.elapsedTime, 200, accuracy: 1e-9)
    }

    func testPositionOfSnapshotMatchesClock() {
        let t0 = ManualClock.reference
        let s = snapshot(elapsed: 10, at: t0, rate: 1.5)
        let clock = PlaybackClock(now: { t0.addingTimeInterval(4) })
        clock.update(s)
        XCTAssertEqual(s.position(at: t0.addingTimeInterval(4)), clock.position()!, accuracy: 1e-12)
        XCTAssertEqual(s.position(at: t0.addingTimeInterval(4)), 16, accuracy: 1e-9)
    }
}
