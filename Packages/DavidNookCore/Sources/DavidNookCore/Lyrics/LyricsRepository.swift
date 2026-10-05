import Foundation

/// 歌詞快取的一筆紀錄。
public struct LyricsCacheEntry: Equatable, Sendable, Codable {
    /// 找到的歌詞；nil 代表「查過但找不到」（負快取）。
    public var lyrics: PickedLyrics?
    /// 寫入時間（負快取的 TTL 由它起算）。
    public var storedAt: Date

    public init(lyrics: PickedLyrics?, storedAt: Date) {
        self.lyrics = lyrics
        self.storedAt = storedAt
    }
}

/// 歌詞快取儲存抽象（以曲目鍵存取）。記憶體版本見 `MemoryLyricsCacheStore`；
/// 之後可另外實作磁碟版本而不必改動 `LyricsRepository`。
public protocol LyricsCacheStore: Sendable {
    func entry(for key: TrackKey) -> LyricsCacheEntry?
    func store(_ entry: LyricsCacheEntry, for key: TrackKey)
}

/// 記憶體快取（執行緒安全）。
public final class MemoryLyricsCacheStore: LyricsCacheStore, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [TrackKey: LyricsCacheEntry] = [:]

    public init() {}

    public func entry(for key: TrackKey) -> LyricsCacheEntry? {
        lock.lock()
        defer { lock.unlock() }
        return entries[key]
    }

    public func store(_ entry: LyricsCacheEntry, for key: TrackKey) {
        lock.lock()
        entries[key] = entry
        lock.unlock()
    }
}

/// 歌詞倉庫：先查本機快取，再查網路。
///
/// - 以 `TrackKey`（歌名 + 歌手 + 取整秒長度）為鍵。
/// - 找到的歌詞永久快取。
/// - **找不到**也快取一小段時間（負快取，`negativeTTL` 秒，預設 30 分鐘；0 代表不做負快取），避免狂打 API。
/// - **錯誤不快取**：網路錯誤、429、503、取消（`CancellationError`）都原樣往外拋，下次會重新查詢。
/// - **退而求其次的結果不快取**（`LyricsFetchOutcome.isDegraded`：search 失敗而退回 get 的單筆結果）：
///   這次照用，但不寫入快取，下次播放重新取得多版本共識的結果。
/// - **同一曲目的並發呼叫合併**成一次抓取（共用結果或錯誤）；所有等待者都取消時，才取消進行中的抓取。
/// - 歌名為空白的查詢直接回傳 nil，不發請求也不寫快取。
public struct LyricsRepository: Sendable {
    private let fetcher: any LyricsFetching
    private let store: any LyricsCacheStore
    private let negativeTTL: TimeInterval
    private let now: @Sendable () -> Date
    private let inflight = InflightFetches()

    /// - Parameters:
    ///   - fetcher: 實際抓歌詞的來源（`LrclibClient`）。
    ///   - store: 快取儲存。
    ///   - negativeTTL: 負快取存活秒數。
    ///   - now: 目前時間（可注入）。
    public init(
        fetcher: any LyricsFetching,
        store: any LyricsCacheStore,
        negativeTTL: TimeInterval = 1_800,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.fetcher = fetcher
        self.store = store
        self.negativeTTL = negativeTTL
        self.now = now
    }

    /// 取得歌詞。
    /// - Parameter forceRefresh: true 時略過快取（含負快取）強制重新查詢，並以新結果取代快取。
    /// - Returns: 歌詞；nil 代表確定找不到（或仍在負快取期內）。
    public func lyrics(for query: LyricsQuery, forceRefresh: Bool = false) async throws -> PickedLyrics? {
        guard query.hasUsableTitle else { return nil }
        let key = query.trackKey

        if !forceRefresh, let hit = cachedValue(for: key) { return hit }

        let fetcher = fetcher, store = store, negativeTTL = negativeTTL, now = now
        let result = try await inflight.run(key: key) { [self] in
            // 等到真的輪到這次抓取才再看一次快取：前一個同曲抓取剛好寫完快取、本次才加入時，不必再連網。
            if !forceRefresh, let hit = cachedValue(for: key) { return hit }
            let outcome = try await fetcher.fetch(query)
            if let lyrics = outcome.lyrics {
                if !outcome.isDegraded { store.store(LyricsCacheEntry(lyrics: lyrics, storedAt: now()), for: key) }
            } else if negativeTTL > 0 {
                store.store(LyricsCacheEntry(lyrics: nil, storedAt: now()), for: key)
            }
            return outcome.lyrics
        }
        return result
    }

    /// 快取查詢：有效的命中回傳 `.some(歌詞)`（負快取仍在 TTL 內回傳 `.some(nil)`），沒有有效快取回傳 nil。
    private func cachedValue(for key: TrackKey) -> PickedLyrics?? {
        guard let cached = store.entry(for: key) else { return nil }
        if let lyrics = cached.lyrics { return .some(lyrics) }
        if negativeTTL > 0, now().timeIntervalSince(cached.storedAt) < negativeTTL { return .some(nil) }
        return nil
    }
}

/// 進行中的抓取表：同一曲目鍵的並發呼叫共用同一個 `Task`。
///
/// 每個呼叫者是一個「等待者」；等待者被取消時只退出自己，**最後一個等待者離開時才取消底層抓取**
/// （避免快速切歌時白白繼續打 API）。底層 Task 結束（成功、失敗、被取消）後自己從表中移除。
private final class InflightFetches: @unchecked Sendable {
    private final class Slot: @unchecked Sendable {
        var task: Task<PickedLyrics?, Error>?
        var waiters = 0
    }

    private let lock = NSLock()
    private var slots: [TrackKey: Slot] = [:]

    func run(
        key: TrackKey,
        operation: @escaping @Sendable () async throws -> PickedLyrics?
    ) async throws -> PickedLyrics? {
        let slot: Slot = lock.withLock {
            if let existing = slots[key] {
                existing.waiters += 1
                return existing
            }
            let created = Slot()
            created.waiters = 1
            created.task = Task { [self] in
                defer { finish(key: key, slot: created) }
                return try await operation()
            }
            slots[key] = created
            return created
        }
        let task = lock.withLock { slot.task }!
        let value = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            leave(key: key, slot: slot)
        }
        try Task.checkCancellation()          // 被取消的呼叫者不論共用抓取是否已完成，都回報取消
        return value
    }

    private func finish(key: TrackKey, slot: Slot) {
        lock.withLock { if slots[key] === slot { slots[key] = nil } }
    }

    /// 取消的等待者離開；沒人在等時取消底層抓取，並讓之後的新呼叫另起一個抓取。
    private func leave(key: TrackKey, slot: Slot) {
        let orphan: Task<PickedLyrics?, Error>? = lock.withLock {
            slot.waiters -= 1
            guard slot.waiters <= 0 else { return nil }
            if slots[key] === slot { slots[key] = nil }
            return slot.task
        }
        orphan?.cancel()
    }
}
