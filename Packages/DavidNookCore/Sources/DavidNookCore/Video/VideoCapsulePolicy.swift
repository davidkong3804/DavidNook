import Foundation

/// 串流的 pause 規則（純邏輯）：同一條 SCStream 供封面槽與釘選的浮動視窗共用。
/// 封面槽在畫面上（或正在編輯裁切）要串流；槽離開畫面時，**已釘選（浮動視窗開著）就不 pause**，未釘選才 pause。
public enum VideoStreamPolicy {
    public enum Decision: Equatable, Sendable {
        /// 目前不需要來源在跑（idle／挑選中／來源已關閉／錯誤）。
        case notNeeded
        case run
        case pause
    }

    public static func shouldPause(isSlotVisible: Bool, isPinned: Bool) -> Bool {
        !isSlotVisible && !isPinned
    }

    /// 完整決策：狀態、封面槽是否可見、是否釘選、是否正在編輯裁切的所有組合。
    public static func decision(state: VideoCapsuleState, isSlotVisible: Bool, isPinned: Bool, isCropEditing: Bool) -> Decision {
        guard state.needsSource else { return .notNeeded }
        return shouldPause(isSlotVisible: isSlotVisible || isCropEditing, isPinned: isPinned) ? .pause : .run
    }
}

/// 畫面是否還在進來（卡住監看的輸出）。
public enum VideoConnectionHealth: Equatable, Sendable {
    case healthy
    /// 一段時間沒有新幀，已自動重啟串流一次。
    case reconnecting
    /// 重啟後仍然沒有新幀。
    case stalled
}

/// 桌面浮動視窗要顯示什麼（純邏輯）。
/// 黑畫面（疑似受內容保護）時**不自動關閉**，視窗內顯示簡短說明並提供關閉；沒有畫面進來時顯示「重新連線中…」，再失敗顯示可關閉的錯誤說明。
public enum FloatingVideoPolicy {
    public enum Content: Equatable, Sendable {
        case hidden
        case live
        case protectedNotice
        case reconnecting
        case stalledNotice
    }

    public static func content(isPinned: Bool, state: VideoCapsuleState, health: VideoConnectionHealth = .healthy) -> Content {
        guard isPinned else { return .hidden }
        switch state {
        case .streaming:
            switch health {
            case .healthy: return .live
            case .reconnecting: return .reconnecting
            case .stalled: return .stalledNotice
            }
        case .blackContent: return .protectedNotice
        case .idle, .choosing, .sourceClosed, .error: return .hidden
        }
    }
}

/// 卡住監看（純邏輯，時間由呼叫端傳入）：串流中且未 pause 時，**任何**來自串流的回呼（含「畫面沒變」的 idle 幀）都算心跳；
/// 超過 3 秒沒有心跳 → 自動重啟串流一次（`reconnecting`）→ 再 3 秒仍沒有 → `stalled`（顯示可關閉的錯誤說明）。
/// 之後任何心跳都會自動恢復。重啟有 30 秒冷卻，避免「重啟後第一幀 → 又判卡住」造成閃爍。
public struct VideoStallWatchdog: Equatable, Sendable {
    public enum Action: Equatable, Sendable { case none, restartStream }

    public static let threshold: TimeInterval = 3
    public static let restartCooldown: TimeInterval = 30

    public private(set) var health: VideoConnectionHealth = .healthy
    private var active = false
    private var lastBeat: TimeInterval = 0
    private var lastRestart: TimeInterval?

    public init() {}

    /// 開始監看（串流中且未 pause）。
    public mutating func start(at time: TimeInterval) {
        active = true
        lastBeat = time
        health = .healthy
    }

    /// 停止監看（pause、串流結束、取消釘選）。
    public mutating func stop() {
        active = false
        health = .healthy
    }

    public mutating func heartbeat(at time: TimeInterval) {
        guard active else { return }
        lastBeat = max(lastBeat, time)
        health = .healthy
    }

    /// 每秒呼叫一次。
    public mutating func tick(at time: TimeInterval) -> Action {
        guard active, time - lastBeat > Self.threshold else { return .none }
        switch health {
        case .reconnecting:
            health = .stalled
            return .none
        case .healthy, .stalled:
            if let lastRestart, time - lastRestart < Self.restartCooldown {
                health = .stalled
                return .none
            }
            lastRestart = time
            lastBeat = time
            health = .reconnecting
            return .restartStream
        case .reconnecting:
            health = .stalled
            return .none
        }
    }
}
