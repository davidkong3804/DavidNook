import Foundation

/// mediaremote-adapter（上游 tag v0.7.7）輸出欄位的時間換算。
///
/// ## 欄位格式（依上游 README 與原始碼 `src/adapter/now_playing.m`、`src/utility/helpers.m`）
/// - 預設輸出：`elapsedTime`、`duration` 為秒（Double）；`timestamp` 是 **UTC、秒級解析度** 的字串
///   `yyyy-MM-dd'T'HH:mm:ss'Z'`——小數秒被截掉，若拿它當錨點，位置推算最多差 1 秒。
/// - 加上 `--micros`：這三個欄位改成 `elapsedTimeMicros`、`durationMicros`（微秒）與
///   `timestampEpochMicros`（自 1970-01-01 UTC 起算的微秒，整數）。
///
/// DavidNook 一律以 `--micros` 啟動 adapter（毫秒級同步需要），並在欄位缺少時退回預設欄位。
/// - Important: 以上格式出自文件與原始碼，**尚未用真實播放驗證**。
public enum AdapterTime {

    /// 微秒優先、秒數備援；兩者都沒有（或不是有限數）回傳 nil。
    public static func seconds(micros: Double?, seconds: Double?) -> TimeInterval? {
        if let micros, micros.isFinite { return micros / 1_000_000 }
        if let seconds, seconds.isFinite { return seconds }
        return nil
    }

    /// epoch 微秒優先、ISO-8601 字串備援；都不可用回傳 nil。
    /// - 負值或非有限數的微秒視為無效。
    public static func date(epochMicros: Double?, iso8601: String?) -> Date? {
        if let epochMicros, epochMicros.isFinite, epochMicros >= 0 {
            return Date(timeIntervalSince1970: epochMicros / 1_000_000)
        }
        guard let iso8601 else { return nil }
        return parseISO8601(iso8601)
    }

    /// 解析 `yyyy-MM-dd'T'HH:mm:ss'Z'`（上游預設格式）；也接受帶小數秒的寫法。
    public static func parseISO8601(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        // ISO8601DateFormatter 不是 Sendable；每次呼叫各建一個（低頻路徑，只在沒有微秒欄位時才會走到）。
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: trimmed) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: trimmed)
    }
}

extension PlaybackSnapshot {

    /// 此快照在指定時間點的播放位置（秒）：播放中為 `elapsed + (date − timestamp) × rate`，
    /// 暫停時固定為 `elapsed`；夾在 `[0, duration]`。`PlaybackClock` 使用同一個算法。
    public func position(at date: Date) -> TimeInterval {
        let elapsed = elapsedTime.isFinite ? elapsedTime : 0
        let rate = playbackRate.isFinite ? playbackRate : 0
        var position = elapsed
        if isPlaying && rate != 0 {
            let delta = max(0, date.timeIntervalSince(timestamp))
            position = elapsed + delta * rate
        }
        position = max(0, position)
        if let duration, duration.isFinite, duration > 0 {
            position = min(position, duration)
        }
        return position
    }

    /// 把錨點移到 `date`：`elapsedTime` 改為當下位置、`timestamp` 改為 `date`，位置軌跡不變。
    ///
    /// 用於「狀態變了但來源沒有給新錨點」的情況（例如只更新 `playing`／`playbackRate` 的差量更新）：
    /// 先固定住舊狀態下的位置，再改欄位，就不會在暫停→恢復時多算暫停那段時間。
    public func rebased(at date: Date) -> PlaybackSnapshot {
        var copy = self
        copy.elapsedTime = position(at: date)
        copy.timestamp = date
        return copy
    }
}
