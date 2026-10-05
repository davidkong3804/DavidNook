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
/// - 歌名為空白的查詢直接回傳 nil，不發請求也不寫快取。
public struct LyricsRepository: Sendable {
    private let fetcher: any LyricsFetching
    private let store: any LyricsCacheStore
    private let negativeTTL: TimeInterval
    private let now: @Sendable () -> Date

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

        if !forceRefresh, let cached = store.entry(for: key) {
            if let lyrics = cached.lyrics { return lyrics }
            if negativeTTL > 0, now().timeIntervalSince(cached.storedAt) < negativeTTL { return nil }
        }

        let result = try await fetcher.lyrics(for: query)
        if let result {
            store.store(LyricsCacheEntry(lyrics: result, storedAt: now()), for: key)
        } else if negativeTTL > 0 {
            store.store(LyricsCacheEntry(lyrics: nil, storedAt: now()), for: key)
        }
        return result
    }
}
