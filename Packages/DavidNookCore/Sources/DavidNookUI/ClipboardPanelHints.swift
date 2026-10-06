import Foundation

/// 剪貼簿面板底部「操作提示」何時顯示、何時收起（純邏輯；App 端把兩個欄位存進 UserDefaults，**不存任何剪貼內容**）。
///
/// - 新使用者預設看得到提示。
/// - 成功把條目複製回剪貼簿滿 `autoHideAfterActivations` 次，就視為「已經會用了」，自動收起。
/// - 使用者可以隨時按提示列上的 ✕ 關閉，或按頂端列的說明按鈕重新叫出（叫出時計數歸零）。
public struct ClipboardHintPolicy: Equatable, Sendable {
    /// 成功複製幾次之後自動收起提示。
    public static let autoHideAfterActivations = 3

    /// 已成功複製回剪貼簿的次數（只是次數，不含內容）。
    public private(set) var activationCount: Int
    /// 使用者是否按了關閉。
    public private(set) var isDismissed: Bool

    public init(activationCount: Int = 0, isDismissed: Bool = false) {
        self.activationCount = max(activationCount, 0)
        self.isDismissed = isDismissed
    }

    /// 現在要不要顯示提示列。
    public var isVisible: Bool {
        !isDismissed && activationCount < Self.autoHideAfterActivations
    }

    /// 記一次成功的複製（不會溢位）。
    public mutating func recordActivation() {
        if activationCount < Int.max { activationCount += 1 }
    }

    /// 使用者關閉提示。
    public mutating func dismiss() {
        isDismissed = true
    }

    /// 重新顯示提示，並把計數歸零（否則剛叫出來又因為舊計數而收起）。
    public mutating func show() {
        activationCount = 0
        isDismissed = false
    }

    /// 說明按鈕：目前看得到就關閉，看不到就重新顯示。
    public mutating func toggle() {
        if isVisible { dismiss() } else { show() }
    }
}

/// 點擊（或 Return）一列之後的短暫回饋：被點的那一列顯示「已複製」勾勾，失敗則顯示紅色提示。
///
/// 這是純狀態機：計時由呼叫端做（`begin` 回傳一個世代編號，時間到時用同一編號 `expire`，
/// 編號對不上代表中間已經有更新的回饋，舊計時器不能清掉它）。
public struct ClipboardCopyFeedback: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case copied
        case failed
    }

    /// 「已複製」勾勾停留時間——夠看清楚，又不至於拖慢收合與自動貼上。
    public static let copiedDuration: TimeInterval = 0.35
    /// 失敗提示停留時間（失敗後瀏海不會收合，使用者需要時間讀）。
    public static let failedDuration: TimeInterval = 1.2

    public static func duration(for phase: Phase) -> TimeInterval {
        switch phase {
        case .copied: return copiedDuration
        case .failed: return failedDuration
        }
    }

    public private(set) var itemID: UUID?
    public private(set) var currentPhase: Phase?
    private var generation = 0

    public init() {}

    /// 有任何回饋正在顯示。
    public var isActive: Bool { currentPhase != nil }

    /// 「已複製」還在顯示時，不接受第二次啟動（避免同一次點擊送出兩次貼上）。失敗回饋不擋重試。
    public var blocksActivation: Bool { currentPhase == .copied }

    /// 這一列目前的回饋（沒有則 nil）。
    public func phase(for id: UUID) -> Phase? {
        itemID == id ? currentPhase : nil
    }

    /// 開始一個回饋。被「已複製」擋住時回傳 nil；否則回傳世代編號，時間到時交給 `expire(token:)`。
    @discardableResult
    public mutating func begin(_ phase: Phase, for id: UUID) -> Int? {
        guard !blocksActivation else { return nil }
        generation += 1
        itemID = id
        currentPhase = phase
        return generation
    }

    /// 時間到。只有編號仍是最新的才會清掉，回傳是否真的清掉。
    @discardableResult
    public mutating func expire(token: Int) -> Bool {
        guard token == generation, isActive else { return false }
        itemID = nil
        currentPhase = nil
        return true
    }
}

/// 「點選後自動貼上」目前實際會不會發生；提示文字依此切換，才不會說謊。
public enum ClipboardAutoPasteMode: Equatable, Sendable {
    /// 設定裡沒開：點一下只會複製回剪貼簿。
    case off
    /// 設定裡開了，但還沒授權事件傳送（輔助使用）：行為同上，只複製。
    case needsPermission
    /// 設定裡開了而且已授權：複製後會自動貼到前一個 App。
    case on

    public static func resolve(enabled: Bool, authorized: Bool) -> ClipboardAutoPasteMode {
        guard enabled else { return .off }
        return authorized ? .on : .needsPermission
    }
}
