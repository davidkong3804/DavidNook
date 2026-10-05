import XCTest
@testable import DavidNookCore

/// F4：自動貼上前的閘門。送出 ⌘V 之前必須確認：設定開啟、有事件授權、最前景不是自己、
/// 系統沒有啟用安全輸入（焦點在密碼欄位時不得對它送出 ⌘V）。
final class AutoPasteGateTests: XCTestCase {
    private func inputs(
        enabled: Bool = true, permission: Bool = true, frontmostIsSelf: Bool = false, secureInput: Bool = false
    ) -> AutoPasteInputs {
        AutoPasteInputs(isEnabled: enabled, hasEventPermission: permission, frontmostIsSelf: frontmostIsSelf, secureEventInputEnabled: secureInput)
    }

    // MARK: 純函式閘門

    func testAllClearPastes() {
        XCTAssertEqual(AutoPasteGate.decide(inputs()), .paste)
    }

    func testSettingDisabledSkips() {
        XCTAssertEqual(AutoPasteGate.decide(inputs(enabled: false)), .skip(.settingDisabled))
    }

    func testMissingEventPermissionSkips() {
        XCTAssertEqual(AutoPasteGate.decide(inputs(permission: false)), .skip(.noEventPermission))
    }

    func testSecureEventInputSkips() {
        XCTAssertEqual(AutoPasteGate.decide(inputs(secureInput: true)), .skip(.secureInputActive))
    }

    func testFrontmostBeingDavidNookItselfSkips() {
        XCTAssertEqual(AutoPasteGate.decide(inputs(frontmostIsSelf: true)), .skip(.frontmostIsSelf))
    }

    func testPriorityIsSettingThenPermissionThenSelfThenSecureInput() {
        XCTAssertEqual(AutoPasteGate.decide(inputs(enabled: false, permission: false, frontmostIsSelf: true, secureInput: true)), .skip(.settingDisabled))
        XCTAssertEqual(AutoPasteGate.decide(inputs(permission: false, frontmostIsSelf: true, secureInput: true)), .skip(.noEventPermission))
        XCTAssertEqual(AutoPasteGate.decide(inputs(frontmostIsSelf: true, secureInput: true)), .skip(.frontmostIsSelf))
    }

    func testOnlySecureInputSkipNotifiesTheUser() {
        XCTAssertTrue(AutoPasteDecision.skip(.secureInputActive).shouldNotifyUser)
        XCTAssertFalse(AutoPasteDecision.skip(.settingDisabled).shouldNotifyUser)
        XCTAssertFalse(AutoPasteDecision.skip(.noEventPermission).shouldNotifyUser)
        XCTAssertFalse(AutoPasteDecision.skip(.frontmostIsSelf).shouldNotifyUser)
        XCTAssertFalse(AutoPasteDecision.paste.shouldNotifyUser)
    }

    func testExhaustiveTruthTableOnlyPastesWhenEveryConditionIsMet() {
        for enabled in [true, false] {
            for permission in [true, false] {
                for frontmostSelf in [true, false] {
                    for secure in [true, false] {
                        let decision = AutoPasteGate.decide(inputs(enabled: enabled, permission: permission, frontmostIsSelf: frontmostSelf, secureInput: secure))
                        let shouldPaste = enabled && permission && !frontmostSelf && !secure
                        XCTAssertEqual(decision == .paste, shouldPaste, "enabled=\(enabled) permission=\(permission) self=\(frontmostSelf) secure=\(secure)")
                    }
                }
            }
        }
    }

    // MARK: 協調器（延遲後才做最終判斷）

    /// 可變的環境，讓測試能在「延遲期間」改變狀態。
    @MainActor
    private final class World {
        var enabled = true
        var permission = true
        var frontmostIsSelf = false
        var secureInput = false
        var sleeps: [TimeInterval] = []
        var sends = 0
        var onSleep: (() -> Void)?

        var environment: AutoPasteEnvironment {
            AutoPasteEnvironment(
                isEnabled: { self.enabled },
                hasEventPermission: { self.permission },
                isFrontmostSelf: { self.frontmostIsSelf },
                isSecureEventInputEnabled: { self.secureInput }
            )
        }

        func run() async -> AutoPasteOutcome {
            await AutoPasteCoordinator.run(
                environment: environment,
                sleep: { seconds in
                    self.sleeps.append(seconds)
                    self.onSleep?()
                },
                send: { self.sends += 1 }
            )
        }
    }

    @MainActor
    func testClearEnvironmentWaitsTheDelayThenSendsExactlyOnce() async {
        let world = World()
        let outcome = await world.run()
        XCTAssertEqual(outcome, .pasted)
        XCTAssertEqual(world.sends, 1)
        XCTAssertEqual(world.sleeps, [AutoPasteCoordinator.delay])
        XCTAssertEqual(AutoPasteCoordinator.delay, 0.18, accuracy: 0.0001, "維持原本 180ms，讓瀏海先收起")
    }

    @MainActor
    func testSecureInputAtSendTimeDoesNotSendAndReportsTheReason() async {
        let world = World()
        world.secureInput = true
        let outcome = await world.run()
        XCTAssertEqual(outcome, .skipped(.secureInputActive))
        XCTAssertEqual(world.sends, 0, "安全輸入啟用中不得送出 ⌘V")
    }

    @MainActor
    func testSecureInputThatAppearsDuringTheDelayIsStillRespected() async {
        let world = World()
        world.onSleep = { world.secureInput = true }   // 瀏海收起、焦點回到密碼欄位
        let outcome = await world.run()
        XCTAssertEqual(outcome, .skipped(.secureInputActive))
        XCTAssertEqual(world.sends, 0, "判斷必須在延遲之後、送出前一刻做")
    }

    @MainActor
    func testFrontmostBecomingDavidNookDuringTheDelayDoesNotSend() async {
        let world = World()
        world.onSleep = { world.frontmostIsSelf = true }
        let outcome = await world.run()
        XCTAssertEqual(outcome, .skipped(.frontmostIsSelf))
        XCTAssertEqual(world.sends, 0)
    }

    @MainActor
    func testSettingTurnedOffDuringTheDelayDoesNotSend() async {
        let world = World()
        world.onSleep = { world.enabled = false }
        let outcome = await world.run()
        XCTAssertEqual(outcome, .skipped(.settingDisabled))
        XCTAssertEqual(world.sends, 0)
    }

    @MainActor
    func testDisabledOrUnauthorizedReturnsImmediatelyWithoutWaiting() async {
        let off = World()
        off.enabled = false
        let offOutcome = await off.run()
        XCTAssertEqual(offOutcome, .skipped(.settingDisabled))
        XCTAssertTrue(off.sleeps.isEmpty)

        let unauthorized = World()
        unauthorized.permission = false
        let unauthorizedOutcome = await unauthorized.run()
        XCTAssertEqual(unauthorizedOutcome, .skipped(.noEventPermission))
        XCTAssertTrue(unauthorized.sleeps.isEmpty)
        XCTAssertEqual(off.sends + unauthorized.sends, 0)
    }
}
