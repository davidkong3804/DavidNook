import XCTest
@testable import DavidNookCore

/// 幀狀態分類：靜止（idle）不是「串流停了」；第一幀（started）要顯示。
final class VideoFrameStatusTests: XCTestCase {
    func testRawValuesMatchTheSDKHeader() {
        XCTAssertEqual(VideoFrameStatus.allCases.map(\.rawValue), [0, 1, 2, 3, 4, 5])
    }

    func testPictureCarriers() {
        XCTAssertEqual(VideoFrameStatus.allCases.filter(\.carriesNewPicture), [.complete, .started])
    }

    func testIdleBlankSuspendedAreHeartbeatsButNotPictures() {
        for s in [VideoFrameStatus.idle, .blank, .suspended] {
            XCTAssertTrue(s.isHeartbeat, "\(s)")
            XCTAssertFalse(s.carriesNewPicture, "\(s)")
        }
        XCTAssertFalse(VideoFrameStatus.stopped.isHeartbeat)
        XCTAssertTrue(VideoFrameStatus.isHeartbeat(rawStatus: nil))
        XCTAssertTrue(VideoFrameStatus.isHeartbeat(rawStatus: 99))
    }

    /// 靜止來源：只有 idle 回呼，監看器不得判定卡住。
    func testStaticSourceWithIdleHeartbeatsNeverRestarts() {
        var w = VideoStallWatchdog()
        w.start(at: 0)
        for t in stride(from: 0.5, through: 120.0, by: 0.5) {
            if VideoFrameStatus.idle.isHeartbeat { w.heartbeat(at: t) }
            XCTAssertEqual(w.tick(at: t), .none)
        }
        XCTAssertEqual(w.health, .healthy)
    }
}
