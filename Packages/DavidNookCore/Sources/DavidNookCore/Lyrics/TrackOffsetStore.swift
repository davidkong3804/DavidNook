import Foundation

/// 逐曲偏移儲存：記住使用者為「某一首曲目」調整的歌詞偏移。
///
/// 偏移單位為**毫秒**，方向與 `LyricsTimeline` 一致：**正值＝歌詞提早顯示，負值＝歌詞延後顯示**。
/// 曲目以 `TrackKey`（歌名 + 歌手 + 取整秒長度）識別。沒有紀錄的曲目偏移為 0。
public protocol TrackOffsetStore: Sendable {
    /// 該曲目的偏移（毫秒）；沒有紀錄回傳 0。
    func offsetMs(for key: TrackKey) -> Int
    /// 設定偏移（毫秒）；設為 0 等同移除紀錄。
    func setOffsetMs(_ ms: Int, for key: TrackKey)
    /// 移除該曲目的偏移紀錄。
    func removeOffset(for key: TrackKey)
}

/// 記憶體版本（執行緒安全）；主要用於測試與預覽。
public final class MemoryTrackOffsetStore: TrackOffsetStore, @unchecked Sendable {
    private let lock = NSLock()
    private var offsets: [TrackKey: Int] = [:]

    public init() {}

    public func offsetMs(for key: TrackKey) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return offsets[key] ?? 0
    }

    public func setOffsetMs(_ ms: Int, for key: TrackKey) {
        lock.lock()
        defer { lock.unlock() }
        if ms == 0 { offsets[key] = nil } else { offsets[key] = ms }
    }

    public func removeOffset(for key: TrackKey) {
        lock.lock()
        offsets[key] = nil
        lock.unlock()
    }

    /// 目前所有非 0 的偏移（毫秒）。
    public func allOffsets() -> [TrackKey: Int] {
        lock.lock()
        defer { lock.unlock() }
        return offsets
    }
}

/// UserDefaults 版本：所有偏移存成單一字典（`TrackKey.storageString` → 毫秒）放在固定的 key 底下。
public final class UserDefaultsTrackOffsetStore: TrackOffsetStore, @unchecked Sendable {
    /// 存放偏移字典的 UserDefaults key。
    static let storageKey = "DavidNook.trackOffsets"

    private let defaults: UserDefaults
    private let lock = NSLock()

    /// - Parameter suiteName: UserDefaults 的 suite 名稱；nil 使用 `UserDefaults.standard`。
    ///   suite 名稱不合法（例如與 bundle id 相同）時回傳 nil。測試請傳入獨一無二的名稱，結束後自行清除。
    public init?(suiteName: String?) {
        if let suiteName {
            guard let suite = UserDefaults(suiteName: suiteName) else { return nil }
            defaults = suite
        } else {
            defaults = .standard
        }
    }

    public func offsetMs(for key: TrackKey) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return load()[key.storageString] ?? 0
    }

    public func setOffsetMs(_ ms: Int, for key: TrackKey) {
        lock.lock()
        defer { lock.unlock() }
        var all = load()
        if ms == 0 { all[key.storageString] = nil } else { all[key.storageString] = ms }
        defaults.set(all, forKey: Self.storageKey)
    }

    public func removeOffset(for key: TrackKey) {
        lock.lock()
        defer { lock.unlock() }
        var all = load()
        all[key.storageString] = nil
        defaults.set(all, forKey: Self.storageKey)
    }

    /// 讀出字典；內容不是預期型別（被壞資料覆蓋）時視為空。
    private func load() -> [String: Int] {
        (defaults.object(forKey: Self.storageKey) as? [String: Int]) ?? [:]
    }
}
