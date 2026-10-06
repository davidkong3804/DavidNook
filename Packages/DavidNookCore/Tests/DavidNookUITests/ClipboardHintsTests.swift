import Foundation
import XCTest
@testable import DavidNookUI

/// 剪貼簿面板的「操作提示何時顯示／收起」與「點擊後回饋」狀態機（純邏輯，不涉及 SwiftUI 與系統剪貼簿）。
final class ClipboardHintPolicyTests: XCTestCase {
    func testFreshStateShowsHints() {
        let policy = ClipboardHintPolicy()
        XCTAssertTrue(policy.isVisible)
        XCTAssertEqual(policy.activationCount, 0)
        XCTAssertFalse(policy.isDismissed)
    }

    func testAutoHidesAfterEnoughSuccessfulCopies() {
        var policy = ClipboardHintPolicy()
        for _ in 0..<(ClipboardHintPolicy.autoHideAfterActivations - 1) {
            policy.recordActivation()
            XCTAssertTrue(policy.isVisible, "用過幾次之前提示都要在")
        }
        policy.recordActivation()
        XCTAssertFalse(policy.isVisible, "用過 \(ClipboardHintPolicy.autoHideAfterActivations) 次後自動收起")
        XCTAssertFalse(policy.isDismissed, "自動收起不等於使用者關閉")
    }

    func testManualDismissHidesImmediately() {
        var policy = ClipboardHintPolicy()
        policy.dismiss()
        XCTAssertFalse(policy.isVisible)
        XCTAssertTrue(policy.isDismissed)
    }

    func testShowResetsCountAndDismissal() {
        var policy = ClipboardHintPolicy(activationCount: 10, isDismissed: true)
        XCTAssertFalse(policy.isVisible)
        policy.show()
        XCTAssertTrue(policy.isVisible)
        XCTAssertEqual(policy.activationCount, 0)
        XCTAssertFalse(policy.isDismissed)
    }

    func testToggleFlipsVisibility() {
        var policy = ClipboardHintPolicy()
        policy.toggle()
        XCTAssertFalse(policy.isVisible)
        policy.toggle()
        XCTAssertTrue(policy.isVisible)
        // 自動收起後再 toggle，應該重新顯示（並重新計數）。
        for _ in 0..<ClipboardHintPolicy.autoHideAfterActivations { policy.recordActivation() }
        XCTAssertFalse(policy.isVisible)
        policy.toggle()
        XCTAssertTrue(policy.isVisible)
        XCTAssertEqual(policy.activationCount, 0)
    }

    func testCountSaturatesAndNegativeInputIsClamped() {
        var policy = ClipboardHintPolicy(activationCount: Int.max)
        policy.recordActivation()
        XCTAssertEqual(policy.activationCount, Int.max, "不得溢位")
        XCTAssertEqual(ClipboardHintPolicy(activationCount: -5).activationCount, 0)
    }

    func testCopiesAfterDismissStillCountButStayHidden() {
        var policy = ClipboardHintPolicy()
        policy.dismiss()
        policy.recordActivation()
        XCTAssertFalse(policy.isVisible)
    }
}

final class ClipboardCopyFeedbackTests: XCTestCase {
    private let a = UUID()
    private let b = UUID()

    func testStartsIdle() {
        let feedback = ClipboardCopyFeedback()
        XCTAssertNil(feedback.phase(for: a))
        XCTAssertFalse(feedback.isActive)
        XCTAssertFalse(feedback.blocksActivation)
    }

    func testBeginCopiedMarksOnlyThatRow() throws {
        var feedback = ClipboardCopyFeedback()
        _ = try XCTUnwrap(feedback.begin(.copied, for: a))
        XCTAssertEqual(feedback.phase(for: a), .copied)
        XCTAssertNil(feedback.phase(for: b))
        XCTAssertTrue(feedback.isActive)
    }

    func testCopiedBlocksSecondActivationWhileShowing() throws {
        var feedback = ClipboardCopyFeedback()
        _ = try XCTUnwrap(feedback.begin(.copied, for: a))
        XCTAssertTrue(feedback.blocksActivation, "回饋顯示期間不可重複貼上（避免 ⌘V 送兩次）")
        XCTAssertNil(feedback.begin(.copied, for: b), "第二次啟動被忽略")
        XCTAssertEqual(feedback.phase(for: a), .copied)
        XCTAssertNil(feedback.phase(for: b))
    }

    func testExpireWithMatchingTokenClears() throws {
        var feedback = ClipboardCopyFeedback()
        let token = try XCTUnwrap(feedback.begin(.copied, for: a))
        XCTAssertTrue(feedback.expire(token: token))
        XCTAssertFalse(feedback.isActive)
        XCTAssertNil(feedback.phase(for: a))
        XCTAssertFalse(feedback.blocksActivation)
    }

    func testStaleTokenDoesNotClearNewerFeedback() throws {
        var feedback = ClipboardCopyFeedback()
        let first = try XCTUnwrap(feedback.begin(.failed, for: a))
        let second = try XCTUnwrap(feedback.begin(.copied, for: b), "失敗回饋不擋重試")
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(feedback.expire(token: first), "舊計時器不能清掉新回饋")
        XCTAssertEqual(feedback.phase(for: b), .copied)
        XCTAssertTrue(feedback.expire(token: second))
        XCTAssertFalse(feedback.isActive)
    }

    func testFailedDoesNotBlockRetry() throws {
        var feedback = ClipboardCopyFeedback()
        _ = try XCTUnwrap(feedback.begin(.failed, for: a))
        XCTAssertFalse(feedback.blocksActivation)
        XCTAssertNotNil(feedback.begin(.copied, for: a))
        XCTAssertEqual(feedback.phase(for: a), .copied)
    }

    func testDurations() {
        XCTAssertEqual(ClipboardCopyFeedback.duration(for: .copied), ClipboardCopyFeedback.copiedDuration)
        XCTAssertEqual(ClipboardCopyFeedback.duration(for: .failed), ClipboardCopyFeedback.failedDuration)
        XCTAssertGreaterThan(ClipboardCopyFeedback.copiedDuration, 0.2, "要停得夠久才看得到")
        XCTAssertLessThan(ClipboardCopyFeedback.copiedDuration, 0.6, "但不能拖慢收合與自動貼上")
        XCTAssertGreaterThan(ClipboardCopyFeedback.failedDuration, ClipboardCopyFeedback.copiedDuration)
    }
}

final class ClipboardAutoPasteModeTests: XCTestCase {
    func testResolve() {
        XCTAssertEqual(ClipboardAutoPasteMode.resolve(enabled: false, authorized: false), .off)
        XCTAssertEqual(ClipboardAutoPasteMode.resolve(enabled: false, authorized: true), .off)
        XCTAssertEqual(ClipboardAutoPasteMode.resolve(enabled: true, authorized: false), .needsPermission)
        XCTAssertEqual(ClipboardAutoPasteMode.resolve(enabled: true, authorized: true), .on)
    }
}

/// 提示文字必須與真實行為一致：點一下列＝寫回剪貼簿並收合瀏海；只有「設定開啟＋已授權」才會自動貼上。
final class ClipboardHintStringsTests: XCTestCase {
    private let s = ClipboardPanelStrings.zhHant

    func testClickHintMatchesActualBehaviourPerMode() {
        XCTAssertTrue(s.hintClick(.off).contains("複製回剪貼簿"))
        XCTAssertTrue(s.hintClick(.off).contains("設定"), "自動貼上沒開：要告訴使用者去設定開")
        XCTAssertFalse(s.hintClick(.off).contains("已授權"))

        XCTAssertTrue(s.hintClick(.on).contains("自動貼上"))
        XCTAssertFalse(s.hintClick(.on).contains("設定開啟"), "已經在運作就不要再叫人去開")

        XCTAssertTrue(s.hintClick(.needsPermission).contains("複製回剪貼簿"))
        XCTAssertTrue(s.hintClick(.needsPermission).contains("授權"), "開了但沒授權：只會複製，並說明缺什麼")
    }

    func testKeyHintListsOnlyRealShortcuts() {
        let keys = s.hintKeys
        for token in ["↑↓", "↩", "⌘P", "⌘⌫", "搜尋"] {
            XCTAssertTrue(keys.contains(token), "鍵盤提示應包含 \(token)")
        }
        XCTAssertFalse(keys.contains("⌘F"), "⌘F 沒有實作，不能出現在提示裡")
    }

    func testRowActionTooltipsCarryShortcuts() {
        XCTAssertTrue(s.copyHelp.contains("Return"))
        XCTAssertTrue(s.pinHelp.contains("⌘P"))
        XCTAssertTrue(s.unpinHelp.contains("⌘P"))
        XCTAssertTrue(s.deleteHelp.contains("⌘⌫"))
    }

    func testStateTextsExplainWhyAndWhatToDo() {
        XCTAssertTrue(s.pausedHint.contains("恢復"), "暫停：怎麼辦＝按恢復")
        XCTAssertTrue(s.pausedHint.contains("不會"), "暫停：為什麼／後果")
        XCTAssertTrue(s.permissionWhy.contains("macOS"), "權限：為什麼")
        XCTAssertTrue(s.permissionDetail.contains("系統設定"), "權限：怎麼辦")
        XCTAssertTrue(s.emptyHistoryHint.contains("點一下"), "空狀態要教怎麼用")
        XCTAssertFalse(s.noResultsHint.isEmpty)
        XCTAssertEqual(s.copied, "已複製")
        XCTAssertFalse(s.copyFailed.isEmpty)
    }
}
