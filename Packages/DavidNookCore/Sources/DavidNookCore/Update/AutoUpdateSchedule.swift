import Foundation

/// 「自動檢查更新」的排程規則（純邏輯；時間由呼叫端傳入，方便測試）。
///
/// 只決定「現在該不該去查」，不做任何網路請求，也不下載、不安裝。
/// - 每次成功檢查之後，至少隔 `checkInterval`（24 小時）才再查。
/// - 檢查失敗（斷網、限流）不算成功：同一次啟動內最多重試 1 次，且距離失敗至少 `retryInterval`（1 小時）；
///   重試也失敗就不再重試，等到下次啟動，避免形成輪詢風暴。
/// - 系統時鐘被調回過去（現在比上次檢查時間還早）時視為該查；因為「重試一次」的上限仍然有效，不會因此狂查。
public struct AutoUpdateSchedule: Equatable, Sendable {
    public enum Decision: Equatable, Sendable {
        case checkNow
        /// 還沒到時間；到 `until` 再問一次。
        case wait(until: Date)
        /// 目前不該查（停用、更新進行中、已知有新版，或本次啟動的重試額度用完）。
        case skip
    }

    /// 兩次成功檢查之間的最短間隔：24 小時。
    public static let checkInterval: TimeInterval = 24 * 3_600
    /// 失敗後重試前的最短等待：1 小時。
    public static let retryInterval: TimeInterval = 3_600
    /// App 啟動後第一次檢查前的延遲：30 秒（避免拖慢開機）。
    public static let initialDelay: TimeInterval = 30

    public init() {}

    /// - Parameters:
    ///   - lastSuccessfulCheck: 上次「成功」檢查的時間（手動或自動；跨啟動保存）。
    ///   - lastAttempt: 本次啟動內最近一次自動嘗試的時間（不論成功與否）；還沒試過為 nil。
    ///   - retriedThisLaunch: 本次啟動內是否已經為了失敗而重試過一次。
    ///   - enabled: 使用者是否開啟自動檢查；關閉就絕不連線。
    ///   - isBusy: 是否正在檢查或更新流程中。
    ///   - alreadyAvailable: 是否已經知道有新版（不重複查）。
    public func decision(
        now: Date,
        lastSuccessfulCheck: Date?,
        lastAttempt: Date?,
        retriedThisLaunch: Bool,
        enabled: Bool,
        isBusy: Bool,
        alreadyAvailable: Bool
    ) -> Decision {
        guard enabled, !isBusy, !alreadyAvailable else { return .skip }

        // 有一次「還沒被成功取代」的失敗嘗試：走重試規則。
        if let attempt = lastAttempt, lastSuccessfulCheck.map({ $0 < attempt }) ?? true {
            if retriedThisLaunch { return .skip }
            let retryAt = attempt.addingTimeInterval(Self.retryInterval)
            // now < attempt：時鐘被調回過去，視為該查。
            if now < attempt || now >= retryAt { return .checkNow }
            return .wait(until: retryAt)
        }

        guard let last = lastSuccessfulCheck else { return .checkNow }
        let dueAt = last.addingTimeInterval(Self.checkInterval)
        // now < last：時鐘被調回過去，視為該查。
        if now < last || now >= dueAt { return .checkNow }
        return .wait(until: dueAt)
    }
}
