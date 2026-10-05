import Foundation

/// Now Playing 來源（mediaremote-adapter）在某個瞬間回報的播放狀態。
public struct PlaybackSnapshot: Equatable, Sendable {
    /// 在 `timestamp` 那一刻的已播放時間，單位：秒。
    public var elapsedTime: TimeInterval
    /// `elapsedTime` 對應的絕對時間（回報當下的時間點）。
    public var timestamp: Date
    /// 播放速率（1.0＝正常；0＝暫停；0.5＝半速）。
    public var playbackRate: Double
    /// 是否正在播放。
    public var isPlaying: Bool
    /// 曲目總長度，單位：秒；nil、0 或負值代表未知（串流、廣播），此時位置不設上限。
    public var duration: TimeInterval?

    public init(elapsedTime: TimeInterval, timestamp: Date, playbackRate: Double, isPlaying: Bool, duration: TimeInterval?) {
        self.elapsedTime = elapsedTime
        self.timestamp = timestamp
        self.playbackRate = playbackRate
        self.isPlaying = isPlaying
        self.duration = duration
    }
}

/// 播放位置內插時鐘：不靠輪詢，由最近一次快照推算「現在」的播放位置。
///
///     播放中：位置 = elapsedTime + (現在 − timestamp) × playbackRate
///     暫停（isPlaying == false 或 rate == 0）：位置固定為 elapsedTime
///
/// 結果夾在 `[0, duration]`（duration 未知則只夾下限 0）。
/// 現在時間由注入的 `now` 提供，方便測試。
///
/// 換歌或 seek：收到新快照時呼叫 `update(_:)` 即整個取代舊錨點；換歌時可先 `reset()` 清空。
/// 執行緒安全（內部以鎖保護）。
public final class PlaybackClock: @unchecked Sendable {

    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var snapshot: PlaybackSnapshot?

    /// - Parameter now: 取得目前時間的閉包；預設為系統時間。
    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    /// 以新快照取代舊錨點（播放、暫停、seek、換歌時都呼叫它）。
    public func update(_ newSnapshot: PlaybackSnapshot) {
        lock.lock()
        snapshot = newSnapshot
        lock.unlock()
    }

    /// 清空狀態（例如換歌、或播放器關閉）；之後 `position()` 回傳 nil，直到下一次 `update`。
    public func reset() {
        lock.lock()
        snapshot = nil
        lock.unlock()
    }

    /// 目前的播放位置（秒）；尚無快照回傳 nil。
    public func position() -> TimeInterval? {
        position(at: now())
    }

    /// 指定時間點的播放位置（秒）；尚無快照回傳 nil。
    ///
    /// 邊界處理：`timestamp` 晚於指定時間（時鐘偏差）時，經過時間視為 0（不會倒退）；
    /// `elapsedTime` 或 `playbackRate` 不是有限數時，分別視為 0 與「暫停」。
    public func position(at date: Date) -> TimeInterval? {
        lock.lock()
        let current = snapshot
        lock.unlock()
        guard let s = current else { return nil }

        let elapsed = s.elapsedTime.isFinite ? s.elapsedTime : 0
        let rate = s.playbackRate.isFinite ? s.playbackRate : 0
        var position = elapsed
        if s.isPlaying && rate != 0 {
            let delta = max(0, date.timeIntervalSince(s.timestamp))
            position = elapsed + delta * rate
        }
        position = max(0, position)
        if let duration = s.duration, duration.isFinite, duration > 0 {
            position = min(position, duration)
        }
        return position
    }
}
