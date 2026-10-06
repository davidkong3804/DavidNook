import XCTest
@testable import DavidNookCore

/// M-C 純邏輯：影片膠囊可見性（收合＋釘選＋串流中＋非黑畫面＋功能開）與串流 pause 規則（釘選則不 pause）。
final class VideoCapsulePolicyTests: XCTestCase {
    private let streaming = VideoCapsuleState.streaming(aspectRatio: 16.0 / 9.0)

    // MARK: 可見性

    func testVisibleOnlyWhenEverythingHolds() {
        XCTAssertTrue(VideoCapsuleVisibility.isVisible(isEnabled: true, isNotchClosed: true, isPinned: true, state: streaming))
    }

    func testEachMissingConditionHides() {
        XCTAssertFalse(VideoCapsuleVisibility.isVisible(isEnabled: false, isNotchClosed: true, isPinned: true, state: streaming), "功能關閉")
        XCTAssertFalse(VideoCapsuleVisibility.isVisible(isEnabled: true, isNotchClosed: false, isPinned: true, state: streaming), "展開時影片在封面槽，外面不重複顯示")
        XCTAssertFalse(VideoCapsuleVisibility.isVisible(isEnabled: true, isNotchClosed: true, isPinned: false, state: streaming), "未釘選")
    }

    func testOnlyStreamingStateShows() {
        let others: [VideoCapsuleState] = [
            .idle, .choosing, .sourceClosed, .blackContent(aspectRatio: 2), .error(.unknown), .error(.permissionDenied),
        ]
        for state in others {
            XCTAssertFalse(
                VideoCapsuleVisibility.isVisible(isEnabled: true, isNotchClosed: true, isPinned: true, state: state),
                "\(state) 不顯示（尤其黑畫面不能顯示黑塊）"
            )
        }
    }

    /// 與狀態機串起來：釘選→顯示；黑畫面→自動取消釘選、不顯示；回到非黑也不會自己再出現；來源關閉→不顯示。
    func testVisibilityFollowsTheStateMachine() {
        var m = VideoCapsuleStateMachine()
        func visible(closed: Bool = true) -> Bool {
            VideoCapsuleVisibility.isVisible(isEnabled: true, isNotchClosed: closed, isPinned: m.isPinned, state: m.state)
        }
        m.handle(.source(.started(aspectRatio: 1.5)), at: 0)
        XCTAssertFalse(visible(), "沒釘選")
        m.handle(.togglePin, at: 0)
        XCTAssertTrue(visible())
        XCTAssertFalse(visible(closed: false), "展開時不重複")
        for t in 1...4 { m.handle(.source(.brightness(0)), at: Double(t)) }
        XCTAssertFalse(visible(), "黑畫面不顯示黑塊")
        XCTAssertFalse(m.isPinned, "黑畫面（疑似受保護）自動取消釘選")
        m.handle(.source(.brightness(90)), at: 6)
        XCTAssertFalse(visible(), "取消後要使用者再點一次才會釘")
        m.handle(.togglePin, at: 7)
        XCTAssertTrue(visible())
        m.handle(.source(.sourceClosed), at: 8)
        XCTAssertFalse(visible())
    }

    /// 使用者在 Music 暫停歌曲與影片無關：可見性不吃任何播放狀態輸入。
    func testVisibilityDoesNotDependOnMusicPlayback() {
        // 簽名上就沒有播放狀態；這裡只確認同一組輸入結果穩定。
        for _ in 0..<3 {
            XCTAssertTrue(VideoCapsuleVisibility.isVisible(isEnabled: true, isNotchClosed: true, isPinned: true, state: streaming))
        }
    }

    // MARK: pause 規則

    func testPauseRuleTruthTable() {
        XCTAssertFalse(VideoStreamPolicy.shouldPause(isSlotVisible: true, isPinned: false), "封面槽在畫面上要串流")
        XCTAssertFalse(VideoStreamPolicy.shouldPause(isSlotVisible: true, isPinned: true))
        XCTAssertFalse(VideoStreamPolicy.shouldPause(isSlotVisible: false, isPinned: true), "已釘選：槽離開畫面不 pause，持續串流給膠囊")
        XCTAssertTrue(VideoStreamPolicy.shouldPause(isSlotVisible: false, isPinned: false), "未釘選且槽不可見：pause")
    }
}
