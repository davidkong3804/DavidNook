import XCTest
@testable import DavidNookCore

/// 釘選（pinStyle：none／pinned＝桌面浮動視窗）的狀態機轉移、串流結束關閉、黑畫面策略、pause 規則、視窗內容策略、卡住監看。
final class FloatingVideoPinStyleTests: XCTestCase {
    private func streaming() -> VideoCapsuleStateMachine {
        var m = VideoCapsuleStateMachine()
        m.handle(.source(.started(aspectRatio: 16.0 / 9.0)), at: 0)
        return m
    }

    private func goBlack(_ m: inout VideoCapsuleStateMachine) {
        for t in stride(from: 1.0, through: 5.0, by: 1.0) { m.handle(.source(.brightness(0)), at: t) }
    }

    func testToggleAndUnpin() {
        var m = streaming()
        XCTAssertEqual(m.pinStyle, .none)
        m.handle(.togglePin, at: 1)
        XCTAssertEqual(m.pinStyle, .pinned)
        XCTAssertTrue(m.isPinned)
        m.handle(.togglePin, at: 2)
        XCTAssertEqual(m.pinStyle, .none)
        m.handle(.togglePin, at: 3)
        m.handle(.unpin, at: 4)
        XCTAssertEqual(m.pinStyle, .none, "視窗的 x、雙擊、右鍵取消釘選")
        m.handle(.unpin, at: 5)
        XCTAssertEqual(m.pinStyle, .none)
    }

    func testPinOnlyWhileStreaming() {
        var idle = VideoCapsuleStateMachine()
        idle.handle(.togglePin, at: 0)
        XCTAssertEqual(idle.pinStyle, .none)
        var choosing = VideoCapsuleStateMachine()
        choosing.handle(.requestPicker, at: 0)
        choosing.handle(.togglePin, at: 0)
        XCTAssertEqual(choosing.pinStyle, .none)
    }

    func testEveryStreamEndClosesPin() {
        let endings: [VideoCapsuleInput] = [.userStopped, .source(.sourceClosed), .source(.failed(.unknown)), .source(.failed(.streamStopped(code: -3817)))]
        for ending in endings {
            var m = streaming()
            m.handle(.togglePin, at: 1)
            m.handle(ending, at: 2)
            XCTAssertEqual(m.pinStyle, .none, "\(ending)")
            m.handle(.source(.started(aspectRatio: 1.5)), at: 3)
            XCTAssertEqual(m.pinStyle, .none, "結束後不能自己回來")
        }
    }

    func testPickerCropAndSizeKeepPin() {
        var m = streaming()
        m.handle(.togglePin, at: 1)
        m.handle(.requestPicker, at: 2)
        XCTAssertTrue(m.isPinned)
        m.handle(.source(.selectionCancelled), at: 3)
        m.handle(.source(.cropChanged(aspectRatio: 1)), at: 4)
        m.handle(.source(.frameSize(width: 100, height: 200)), at: 5)
        XCTAssertTrue(m.isPinned)
        m.handle(.requestPicker, at: 6)
        m.handle(.source(.sourceClosed), at: 7)
        XCTAssertFalse(m.isPinned, "挑選中舊串流被關閉")
    }

    func testBlackContentKeepsPin() {
        var m = streaming()
        m.handle(.togglePin, at: 0)
        goBlack(&m)
        guard case .blackContent = m.state else { return XCTFail("應為黑畫面") }
        XCTAssertTrue(m.isPinned)
        m.handle(.source(.brightness(120)), at: 7)
        XCTAssertTrue(m.isPinned)
    }

    // MARK: pause 規則（所有組合）

    func testPauseDecisionExhaustive() {
        let states: [VideoCapsuleState] = [.idle, .choosing, .streaming(aspectRatio: 2), .sourceClosed, .blackContent(aspectRatio: 2), .error(.unknown)]
        for state in states {
            for slotVisible in [true, false] {
                for pinned in [true, false] {
                    for cropEditing in [true, false] {
                        let d = VideoStreamPolicy.decision(state: state, isSlotVisible: slotVisible, isPinned: pinned, isCropEditing: cropEditing)
                        let label = "\(state) slot=\(slotVisible) pinned=\(pinned) crop=\(cropEditing)"
                        if !state.needsSource {
                            XCTAssertEqual(d, .notNeeded, label)
                        } else if pinned {
                            XCTAssertEqual(d, .run, "釘選（浮動視窗）開著一定不 pause：\(label)")
                        } else {
                            XCTAssertEqual(d, (slotVisible || cropEditing) ? .run : .pause, label)
                        }
                    }
                }
            }
        }
    }

    func testPauseRuleBasic() {
        XCTAssertTrue(VideoStreamPolicy.shouldPause(isSlotVisible: false, isPinned: false))
        XCTAssertFalse(VideoStreamPolicy.shouldPause(isSlotVisible: false, isPinned: true))
        XCTAssertFalse(VideoStreamPolicy.shouldPause(isSlotVisible: true, isPinned: false))
    }

    // MARK: 視窗內容策略

    func testFloatingContentPolicy() {
        let live = VideoCapsuleState.streaming(aspectRatio: 2)
        XCTAssertEqual(FloatingVideoPolicy.content(isPinned: true, state: live), .live)
        XCTAssertEqual(FloatingVideoPolicy.content(isPinned: true, state: .blackContent(aspectRatio: 2)), .protectedNotice)
        XCTAssertEqual(FloatingVideoPolicy.content(isPinned: false, state: live), .hidden)
        XCTAssertEqual(FloatingVideoPolicy.content(isPinned: true, state: live, health: .reconnecting), .reconnecting)
        XCTAssertEqual(FloatingVideoPolicy.content(isPinned: true, state: live, health: .stalled), .stalledNotice)
        XCTAssertEqual(FloatingVideoPolicy.content(isPinned: true, state: .blackContent(aspectRatio: 2), health: .stalled), .protectedNotice)
        for state in [VideoCapsuleState.idle, .choosing, .sourceClosed, .error(.unknown)] {
            XCTAssertEqual(FloatingVideoPolicy.content(isPinned: true, state: state, health: .stalled), .hidden)
        }
    }

    // MARK: 卡住監看

    func testWatchdogHealthyWhileHeartbeatsArrive() {
        var w = VideoStallWatchdog()
        w.start(at: 0)
        for t in stride(from: 1.0, through: 30.0, by: 1.0) {
            w.heartbeat(at: t)
            XCTAssertEqual(w.tick(at: t), .none)
        }
        XCTAssertEqual(w.health, .healthy)
    }

    func testWatchdogRestartsOnceThenStalls() {
        var w = VideoStallWatchdog()
        w.start(at: 0)
        XCTAssertEqual(w.tick(at: 2.9), .none)
        XCTAssertEqual(w.tick(at: 3.1), .restartStream)
        XCTAssertEqual(w.health, .reconnecting)
        XCTAssertEqual(w.tick(at: 5), .none, "重啟後再給 3 秒")
        XCTAssertEqual(w.tick(at: 6.2), .none)
        XCTAssertEqual(w.health, .stalled, "再失敗＝顯示可關閉的錯誤說明")
        XCTAssertEqual(w.tick(at: 20), .none, "不無限重啟")
    }

    func testWatchdogRecoversOnHeartbeat() {
        var w = VideoStallWatchdog()
        w.start(at: 0)
        _ = w.tick(at: 3.5)
        w.heartbeat(at: 4)
        XCTAssertEqual(w.health, .healthy)
        XCTAssertEqual(w.tick(at: 5), .none)
        var s = VideoStallWatchdog()
        s.start(at: 0)
        _ = s.tick(at: 3.5); _ = s.tick(at: 7)
        XCTAssertEqual(s.health, .stalled)
        s.heartbeat(at: 8)
        XCTAssertEqual(s.health, .healthy, "之後有幀就自動恢復")
    }

    func testWatchdogRestartCooldownAvoidsFlicker() {
        var w = VideoStallWatchdog()
        w.start(at: 0)
        XCTAssertEqual(w.tick(at: 3.5), .restartStream)
        w.heartbeat(at: 3.6)   // 重啟後的第一幀
        XCTAssertEqual(w.tick(at: 7), .none, "冷卻期內（距上次重啟 < 30 秒）再卡住不再重啟")
        XCTAssertEqual(w.health, .stalled)
        w.heartbeat(at: 8)
        XCTAssertEqual(w.tick(at: 12), .none)
        XCTAssertEqual(w.tick(at: 40), .restartStream, "冷卻過後可再重啟一次")
    }

    func testWatchdogInactiveDoesNothing() {
        var w = VideoStallWatchdog()
        XCTAssertEqual(w.tick(at: 100), .none)
        w.start(at: 0)
        w.stop()
        XCTAssertEqual(w.tick(at: 100), .none)
        XCTAssertEqual(w.health, .healthy)
    }
}
