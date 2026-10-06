import XCTest
@testable import DavidNookCore

/// 釘選樣式（pinStyle：none／capsule／floating）的狀態機轉移、串流結束全部關閉、黑畫面策略與 pause 規則。
final class FloatingVideoPinStyleTests: XCTestCase {
    private func streaming() -> VideoCapsuleStateMachine {
        var m = VideoCapsuleStateMachine()
        m.handle(.source(.started(aspectRatio: 16.0 / 9.0)), at: 0)
        return m
    }

    func testInitialStyleIsNone() {
        let m = VideoCapsuleStateMachine()
        XCTAssertEqual(m.pinStyle, .none)
        XCTAssertFalse(m.isPinned)
        XCTAssertFalse(m.isFloating)
    }

    func testIsPinnedMeansCapsuleOnly() {
        var m = streaming()
        m.handle(.togglePin, at: 1)
        XCTAssertEqual(m.pinStyle, .capsule)
        XCTAssertTrue(m.isPinned)
        m.handle(.openFloating, at: 2)
        XCTAssertEqual(m.pinStyle, .floating)
        XCTAssertFalse(m.isPinned, "浮動視窗時收合膠囊必須隱藏")
        XCTAssertTrue(m.isFloating)
    }

    func testOpenFloatingOnlyWhileStreaming() {
        var idle = VideoCapsuleStateMachine()
        idle.handle(.openFloating, at: 0)
        XCTAssertEqual(idle.pinStyle, .none)

        var choosing = VideoCapsuleStateMachine()
        choosing.handle(.requestPicker, at: 0)
        choosing.handle(.openFloating, at: 0)
        XCTAssertEqual(choosing.pinStyle, .none)

        var closed = streaming()
        closed.handle(.source(.sourceClosed), at: 1)
        closed.handle(.openFloating, at: 2)
        XCTAssertEqual(closed.pinStyle, .none)
    }

    func testTransitionsBetweenStyles() {
        var m = streaming()
        m.handle(.openFloating, at: 1)
        XCTAssertEqual(m.pinStyle, .floating)
        m.handle(.pinToCapsule, at: 2)
        XCTAssertEqual(m.pinStyle, .capsule, "浮動視窗的「釘選到瀏海」")
        m.handle(.openFloating, at: 3)
        XCTAssertEqual(m.pinStyle, .floating, "從膠囊改開浮動視窗")
        m.handle(.closeFloating, at: 4)
        XCTAssertEqual(m.pinStyle, .none)
        m.handle(.pinToCapsule, at: 5)
        XCTAssertEqual(m.pinStyle, .capsule)
        m.handle(.closeFloating, at: 6)
        XCTAssertEqual(m.pinStyle, .capsule, "沒開浮動視窗時 closeFloating 不影響膠囊")
        m.handle(.togglePin, at: 7)
        XCTAssertEqual(m.pinStyle, .none)
    }

    func testTogglePinFromFloatingSwitchesToCapsule() {
        var m = streaming()
        m.handle(.openFloating, at: 1)
        m.handle(.togglePin, at: 2)
        XCTAssertEqual(m.pinStyle, .capsule, "點封面槽的影片＝釘成膠囊（同一時間只有一種樣式）")
    }

    func testPinToCapsuleNeedsStreaming() {
        var m = VideoCapsuleStateMachine()
        m.handle(.pinToCapsule, at: 0)
        XCTAssertEqual(m.pinStyle, .none)
    }

    func testEveryStreamEndClosesEverything() {
        let endings: [VideoCapsuleInput] = [
            .userStopped, .source(.sourceClosed), .source(.failed(.unknown)), .source(.failed(.streamStopped(code: -3817))),
        ]
        for ending in endings {
            var m = streaming()
            m.handle(.openFloating, at: 1)
            m.handle(ending, at: 2)
            XCTAssertEqual(m.pinStyle, .none, "\(ending) 後浮動視窗必須關閉")
            XCTAssertFalse(m.isFloating)
            // 結束後不能自己回來
            m.handle(.source(.started(aspectRatio: 1.5)), at: 3)
            XCTAssertEqual(m.pinStyle, .none)
        }
    }

    func testSourceClosedWhilePickingClosesFloating() {
        var m = streaming()
        m.handle(.openFloating, at: 1)
        m.handle(.requestPicker, at: 2)
        XCTAssertEqual(m.pinStyle, .floating, "換視窗期間維持")
        m.handle(.source(.sourceClosed), at: 3)
        XCTAssertEqual(m.pinStyle, .none)
    }

    func testPickerCancelAndCropKeepFloating() {
        var m = streaming()
        m.handle(.openFloating, at: 1)
        m.handle(.requestPicker, at: 2)
        m.handle(.source(.selectionCancelled), at: 3)
        XCTAssertEqual(m.pinStyle, .floating)
        m.handle(.source(.cropChanged(aspectRatio: 1)), at: 4)
        XCTAssertEqual(m.pinStyle, .floating)
        m.handle(.source(.frameSize(width: 100, height: 200)), at: 5)
        XCTAssertEqual(m.pinStyle, .floating)
    }

    /// 黑畫面（疑似 DRM）：膠囊自動取消（既有決議）；浮動視窗維持（視窗內顯示說明＋可關閉），恢復後回到畫面。
    func testBlackContentKeepsFloatingButDropsCapsule() {
        var floating = streaming()
        floating.handle(.openFloating, at: 0)
        for t in stride(from: 1.0, through: 5.0, by: 1.0) { floating.handle(.source(.brightness(0)), at: t) }
        guard case .blackContent = floating.state else { return XCTFail("應為黑畫面") }
        XCTAssertEqual(floating.pinStyle, .floating)
        floating.handle(.openFloating, at: 6)
        XCTAssertEqual(floating.pinStyle, .floating)
        floating.handle(.source(.brightness(120)), at: 7)
        guard case .streaming = floating.state else { return XCTFail("應恢復串流") }
        XCTAssertEqual(floating.pinStyle, .floating)

        var capsule = streaming()
        capsule.handle(.togglePin, at: 0)
        for t in stride(from: 1.0, through: 5.0, by: 1.0) { capsule.handle(.source(.brightness(0)), at: t) }
        XCTAssertEqual(capsule.pinStyle, .none)
    }

    func testCannotOpenFloatingWhileBlack() {
        var m = streaming()
        for t in stride(from: 1.0, through: 5.0, by: 1.0) { m.handle(.source(.brightness(0)), at: t) }
        m.handle(.openFloating, at: 6)
        XCTAssertEqual(m.pinStyle, .none)
    }

    // MARK: pause 規則

    func testFloatingNeverPauses() {
        for slotVisible in [true, false] {
            for pinned in [true, false] {
                XCTAssertFalse(VideoStreamPolicy.shouldPause(isSlotVisible: slotVisible, isPinned: pinned, isFloating: true),
                               "浮動視窗開著＝不 pause")
            }
        }
    }

    func testPauseRuleUnchangedWithoutFloating() {
        XCTAssertTrue(VideoStreamPolicy.shouldPause(isSlotVisible: false, isPinned: false, isFloating: false))
        XCTAssertFalse(VideoStreamPolicy.shouldPause(isSlotVisible: true, isPinned: false, isFloating: false))
        XCTAssertFalse(VideoStreamPolicy.shouldPause(isSlotVisible: false, isPinned: true, isFloating: false))
        XCTAssertTrue(VideoStreamPolicy.shouldPause(isSlotVisible: false, isPinned: false), "舊的雙參數形式仍可用")
    }

    // MARK: 浮動視窗內容策略

    func testFloatingContentPolicy() {
        XCTAssertEqual(FloatingVideoPolicy.content(style: .floating, state: .streaming(aspectRatio: 2)), .live)
        XCTAssertEqual(FloatingVideoPolicy.content(style: .floating, state: .blackContent(aspectRatio: 2)), .protectedNotice)
        XCTAssertEqual(FloatingVideoPolicy.content(style: .capsule, state: .streaming(aspectRatio: 2)), .hidden)
        XCTAssertEqual(FloatingVideoPolicy.content(style: .none, state: .streaming(aspectRatio: 2)), .hidden)
        for state in [VideoCapsuleState.idle, .choosing, .sourceClosed, .error(.unknown)] {
            XCTAssertEqual(FloatingVideoPolicy.content(style: .floating, state: state), .hidden, "\(state)")
        }
    }
}
