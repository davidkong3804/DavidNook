import Foundation

/// 為什麼這次不自動貼上。
public enum AutoPasteSkipReason: Equatable, Sendable {
    /// 使用者沒有開啟「點選後自動貼上」。
    case settingDisabled
    /// 沒有取得送出按鍵事件的授權。
    case noEventPermission
    /// 最前景的就是 DavidNook 自己（沒有別的 App 可貼）。
    case frontmostIsSelf
    /// 系統目前啟用了安全輸入（焦點在密碼欄位等），不該對它送出 ⌘V。
    case secureInputActive
}

/// 自動貼上的決定。
public enum AutoPasteDecision: Equatable, Sendable {
    /// 送出 ⌘V。
    case paste
    /// 不貼，附原因。
    case skip(AutoPasteSkipReason)

    /// 是否該讓使用者知道「沒貼」：只有安全輸入這種「使用者預期會貼、卻被擋下」的情況才需要提示。
    public var shouldNotifyUser: Bool {
        self == .skip(.secureInputActive)
    }
}

/// 決定時需要的全部輸入（皆為「送出前一刻」的狀態）。
public struct AutoPasteInputs: Equatable, Sendable {
    /// 使用者是否開啟自動貼上。
    public var isEnabled: Bool
    /// 是否已取得事件傳送授權。
    public var hasEventPermission: Bool
    /// 最前景的是否是 DavidNook 自己。
    public var frontmostIsSelf: Bool
    /// 系統是否啟用了安全輸入（`IsSecureEventInputEnabled()`）。
    public var secureEventInputEnabled: Bool

    /// 建立輸入。
    public init(isEnabled: Bool, hasEventPermission: Bool, frontmostIsSelf: Bool, secureEventInputEnabled: Bool) {
        self.isEnabled = isEnabled
        self.hasEventPermission = hasEventPermission
        self.frontmostIsSelf = frontmostIsSelf
        self.secureEventInputEnabled = secureEventInputEnabled
    }
}

/// 自動貼上的閘門（純函式）。優先序：設定 → 事件授權 → 最前景是自己 → 安全輸入。
public enum AutoPasteGate {
    /// 依輸入決定貼或不貼。
    public static func decide(_ inputs: AutoPasteInputs) -> AutoPasteDecision {
        guard inputs.isEnabled else { return .skip(.settingDisabled) }
        guard inputs.hasEventPermission else { return .skip(.noEventPermission) }
        return .paste
    }
}

/// 可注入的環境查詢（每次呼叫都讀「當下」的狀態）。
public struct AutoPasteEnvironment {
    /// 使用者是否開啟自動貼上。
    public var isEnabled: () -> Bool
    /// 是否已取得事件傳送授權。
    public var hasEventPermission: () -> Bool
    /// 最前景的是否是 DavidNook 自己。
    public var isFrontmostSelf: () -> Bool
    /// 系統是否啟用了安全輸入。
    public var isSecureEventInputEnabled: () -> Bool

    /// 建立環境。
    public init(
        isEnabled: @escaping () -> Bool,
        hasEventPermission: @escaping () -> Bool,
        isFrontmostSelf: @escaping () -> Bool,
        isSecureEventInputEnabled: @escaping () -> Bool
    ) {
        self.isEnabled = isEnabled
        self.hasEventPermission = hasEventPermission
        self.isFrontmostSelf = isFrontmostSelf
        self.isSecureEventInputEnabled = isSecureEventInputEnabled
    }

    /// 讀取當下全部狀態。
    public func currentInputs() -> AutoPasteInputs {
        AutoPasteInputs(
            isEnabled: isEnabled(),
            hasEventPermission: hasEventPermission(),
            frontmostIsSelf: isFrontmostSelf(),
            secureEventInputEnabled: isSecureEventInputEnabled()
        )
    }
}

/// 一次自動貼上嘗試的結果。
public enum AutoPasteOutcome: Equatable, Sendable {
    /// 已送出 ⌘V。
    case pasted
    /// 沒有送出，附原因。
    case skipped(AutoPasteSkipReason)
}

/// 執行一次自動貼上嘗試：先做不需等待的預檢（設定、授權），延遲讓瀏海面板收起並把焦點還給原本的 App，
/// 然後在「送出前一刻」重新讀取全部狀態、經過閘門才真的送出。
@MainActor
public enum AutoPasteCoordinator {
    /// 寫回剪貼簿後到送出 ⌘V 的延遲（秒）。
    public static let delay: TimeInterval = 0.18

    /// 嘗試自動貼上；`sleep` 與 `send` 可注入以便測試。
    public static func run(
        environment: AutoPasteEnvironment,
        delay: TimeInterval = AutoPasteCoordinator.delay,
        sleep: (TimeInterval) async -> Void,
        send: () -> Void
    ) async -> AutoPasteOutcome {
        guard environment.isEnabled() else { return .skipped(.settingDisabled) }
        guard environment.hasEventPermission() else { return .skipped(.noEventPermission) }
        await sleep(delay)
        switch AutoPasteGate.decide(environment.currentInputs()) {
        case .paste:
            send()
            return .pasted
        case .skip(let reason):
            return .skipped(reason)
        }
    }
}
