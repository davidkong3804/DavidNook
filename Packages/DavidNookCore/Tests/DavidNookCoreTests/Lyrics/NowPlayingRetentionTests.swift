import XCTest
@testable import DavidNookCore

/// 「播放結束＝暫停」的狀態轉移：來源回報無曲目時，保留最後一首（只在記憶體），不清空。
final class NowPlayingRetentionTests: XCTestCase {
    private var r = NowPlayingRetention()

    func testColdStartWithNoTrackAppliesAndStaysNone() {
        XCTAssertEqual(r.phase, .none)
        XCTAssertEqual(r.observe(hasTrack: false, isPlaying: false), .applyIncoming)
        XCTAssertEqual(r.phase, .none)
        XCTAssertFalse(r.isEnded)
    }

    func testPlayingThenPausedAppliesBoth() {
        XCTAssertEqual(r.observe(hasTrack: true, isPlaying: true), .applyIncoming)
        XCTAssertEqual(r.phase, .playing)
        XCTAssertEqual(r.observe(hasTrack: true, isPlaying: false), .applyIncoming)
        XCTAssertEqual(r.phase, .paused)
        XCTAssertFalse(r.isEnded)
    }

    func testPlayingThenNoTrackRetainsAndMarksEnded() {
        _ = r.observe(hasTrack: true, isPlaying: true)
        XCTAssertEqual(r.observe(hasTrack: false, isPlaying: false), .retainLast)
        XCTAssertEqual(r.phase, .ended)
        XCTAssertTrue(r.isEnded)
    }

    func testPausedThenNoTrackAlsoRetains() {
        _ = r.observe(hasTrack: true, isPlaying: false)
        XCTAssertEqual(r.observe(hasTrack: false, isPlaying: false), .retainLast)
        XCTAssertTrue(r.isEnded)
    }

    func testEndedStaysEndedOnRepeatedNoTrack() {
        _ = r.observe(hasTrack: true, isPlaying: true)
        _ = r.observe(hasTrack: false, isPlaying: false)
        XCTAssertEqual(r.observe(hasTrack: false, isPlaying: false), .retainLast)
        XCTAssertEqual(r.phase, .ended)
    }

    func testNoTrackReportedAsPlayingStillRetainsAndIsNotPlaying() {
        // 沒有曲目卻說「播放中」是來源的不一致回報；仍保留最後一首，並視為結束。
        _ = r.observe(hasTrack: true, isPlaying: true)
        XCTAssertEqual(r.observe(hasTrack: false, isPlaying: true), .retainLast)
        XCTAssertTrue(r.isEnded)
    }

    func testEndedThenNewTrackPlayingApplies() {
        _ = r.observe(hasTrack: true, isPlaying: true)
        _ = r.observe(hasTrack: false, isPlaying: false)
        XCTAssertEqual(r.observe(hasTrack: true, isPlaying: true), .applyIncoming)
        XCTAssertEqual(r.phase, .playing)
        XCTAssertFalse(r.isEnded)
    }

    func testEndedThenTrackPausedApplies() {
        _ = r.observe(hasTrack: true, isPlaying: true)
        _ = r.observe(hasTrack: false, isPlaying: false)
        XCTAssertEqual(r.observe(hasTrack: true, isPlaying: false), .applyIncoming)
        XCTAssertEqual(r.phase, .paused)
    }

    func testResetForgetsEverythingSoNoTrackAppliesAgain() {
        // 換來源（controller 切換）時整份狀態清掉，無曲目就是真的無曲目。
        _ = r.observe(hasTrack: true, isPlaying: true)
        _ = r.observe(hasTrack: false, isPlaying: false)
        r.reset()
        XCTAssertEqual(r.phase, .none)
        XCTAssertEqual(r.observe(hasTrack: false, isPlaying: false), .applyIncoming)
    }

    func testHasTrackRule() {
        XCTAssertFalse(NowPlayingRetention.hasTrack(title: "", artist: ""))
        XCTAssertTrue(NowPlayingRetention.hasTrack(title: "Song", artist: ""))
        XCTAssertTrue(NowPlayingRetention.hasTrack(title: "", artist: "Artist"))
    }
}
