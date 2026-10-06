import Foundation

/// 釘選影片膠囊（收合瀏海外面）的可見性（純邏輯）。
///
/// 顯示條件（缺一不可）：功能開啟＋瀏海收合＋已釘選＋串流中且**非黑畫面**。
/// - 展開時影片在 Home 封面槽，外面的膠囊一律不顯示（兩處不重複）。
/// - 黑畫面（疑似受保護）不顯示黑塊：狀態機在偵測到黑畫面時同時自動取消釘選，這裡再以 `.streaming` 限定一次作雙重保險。
/// - 與音樂播放狀態無關（使用者在 Music 暫停歌曲不影響影片）。
public enum VideoCapsuleVisibility {
    public static func isVisible(isEnabled: Bool, isNotchClosed: Bool, isPinned: Bool, state: VideoCapsuleState) -> Bool {
        guard isEnabled, isNotchClosed, isPinned else { return false }
        if case .streaming = state { return true }
        return false
    }
}

/// 串流的 pause 規則（純邏輯）：同一條 SCStream 同時供封面槽與釘選膠囊使用。
/// 封面槽在畫面上要串流；槽離開畫面時，**已釘選就不 pause**（持續串流給膠囊），未釘選才 pause。
public enum VideoStreamPolicy {
    /// 浮動視窗開著（`isFloating`）＝一定要串流，不 pause。
    public static func shouldPause(isSlotVisible: Bool, isPinned: Bool, isFloating: Bool = false) -> Bool {
        !isSlotVisible && !isPinned && !isFloating
    }
}

/// 桌面浮動視窗要顯示什麼（純邏輯）。
/// 黑畫面（疑似受內容保護）時**不自動關閉**，視窗內顯示簡短說明並提供關閉（與膠囊「不顯示黑塊」的策略一致，但說明比直接消失友善）。
public enum FloatingVideoPolicy {
    public enum Content: Equatable, Sendable {
        case hidden
        case live
        case protectedNotice
    }

    public static func content(style: VideoPinStyle, state: VideoCapsuleState) -> Content {
        guard style == .floating else { return .hidden }
        switch state {
        case .streaming: return .live
        case .blackContent: return .protectedNotice
        case .idle, .choosing, .sourceClosed, .error: return .hidden
        }
    }
}
