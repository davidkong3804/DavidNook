//
//  LyricsService.swift
//  DavidNook
//
//  薄適配層：把 DavidNookCore 的歌詞管線（LrclibClient → LyricsCandidatePicker → LyricsRepository →
//  LyricsLocalizer → LyricsTimeline）接到 App 的狀態。原上游的 LyricsService（Apple Music 內嵌歌詞、
//  取搜尋結果第一筆、無簡轉繁、無偏移）已整個移除；歌詞只來自 LRCLIB。
//
//  隱私：歌名、歌手、歌詞內容一律不寫進 log（本檔沒有任何 log 呼叫）。
//  顯示與查詢一律使用播放器提供的原始歌名／歌手名，不做簡繁轉換；只有「歌詞內文」會被本地化，
//  而查詢用的簡／繁變體只在原樣查不到時才額外嘗試（由 LrclibClient 處理）。
//

import DavidNookCore
import Defaults
import Foundation

/// 目前曲目（來自播放器的原始值）。
struct LyricsTrack: Equatable, Sendable {
    var title: String
    var artist: String
    var album: String
    /// 秒；0 代表未知。
    var duration: TimeInterval
    /// 來源 App 的 bundle id（「正在播放」資料的 parentApplicationBundleIdentifier ?? bundleIdentifier）。
    /// 只用來判斷標題是不是影片標題（瀏覽器）；不送出、不參與曲目鍵。nil／空字串＝未知。
    var sourceBundleID: String? = nil

    /// 沒有實際曲目時 Music.app 備援會回報的占位內容，不拿去查歌詞。
    var isPlaceholder: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (title == MusicPlaceholder.notPlaying && artist == MusicPlaceholder.unknown)
    }

    var key: TrackKey { TrackKey(title: title, artist: artist, duration: duration) }
}

@MainActor
final class LyricsService: ObservableObject {
    static let shared = LyricsService()

    enum Status: Equatable {
        /// 沒有要查的曲目，或歌詞功能關閉。
        case idle
        case loading
        case loaded
        /// LRCLIB 確定沒有符合的同步歌詞（也包含純音樂；目前管線無法區分兩者）。
        case notFound
        /// 網路或伺服器錯誤（不會被快取，下一次換歌會重查）。
        case error
    }

    @Published private(set) var status: Status = .idle
    /// 已本地化（簡→繁）的顯示行，與 `timeline.lines` 一一對應；空字串是間奏／空白行。
    @Published private(set) var lines: [String] = []
    /// 目前曲目的使用者偏移（毫秒；正值＝歌詞提早）。
    @Published private(set) var offsetMs: Int = 0

    private(set) var timeline = LyricsTimeline(lines: [])

    var isFetchingLyrics: Bool { status == .loading }

    // MARK: 內部狀態

    private let repository: LyricsRepository
    private let cacheStore: FileLyricsCacheStore?
    private let offsetStore: any TrackOffsetStore
    private let localizer = LyricsLocalizer.shared
    private var track: LyricsTrack?
    private var loadedKey: TrackKey?
    private var picked: PickedLyrics?
    private var fetchTask: Task<Void, Never>?
    private var localizeTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var enableObservation: Task<Void, Never>?
    private var idiomObservation: Task<Void, Never>?

    /// 換歌後等多久才真的查詢：duration、artist 常常比 title 晚幾十毫秒到，等它們穩定可避免白打一次請求。
    private static let debounce: Duration = .milliseconds(450)
    /// 網路／伺服器錯誤後的自動重試間隔與次數（LRCLIB 有限流，不要打太密）。
    private static let retryDelay: Duration = .seconds(15)
    private static let maxRetries = 3

    private init() {
        let store = Self.makeCacheStore()
        cacheStore = store
        repository = Self.makeRepository(store: store)
        offsetStore = UserDefaultsTrackOffsetStore(suiteName: nil) ?? MemoryTrackOffsetStore()

        enableObservation = Task { @MainActor [weak self] in
            for await _ in Defaults.updates(.enableLyrics, initial: false) {
                self?.evaluate()
            }
        }
        idiomObservation = Task { @MainActor [weak self] in
            for await _ in Defaults.updates(.lyricsTaiwanIdioms, initial: false) {
                self?.relocalize()
            }
        }
    }

    // MARK: - 公開 API

    /// 告知目前曲目（nil＝沒有曲目）。可重複呼叫；曲目鍵（歌名＋歌手＋取整秒長度）沒變就什麼都不做。
    func setTrack(_ newTrack: LyricsTrack?) {
        let normalized = (newTrack?.isPlaceholder ?? true) ? nil : newTrack
        track = normalized
        evaluate()
    }

    /// 清除目前的歌詞狀態（例如切換播放來源）。
    func clear() {
        track = nil
        evaluate()
    }

    /// 目前行索引（對應 `lines`／`timeline.lines`）；尚未開始或沒有歌詞回傳 nil。
    func currentIndex(at position: TimeInterval) -> Int? {
        guard status == .loaded else { return nil }
        return timeline.currentIndex(at: position, userOffsetMs: offsetMs)
    }

    /// 逐曲偏移：增減 `deltaMs` 毫秒（正值＝歌詞提早；細調 ±100、粗調 ±500），夾在 ±60 秒內並依曲目記住。
    func adjustOffset(byMs deltaMs: Int) {
        setOffset(offsetMs + deltaMs)
    }

    /// 點歌詞對齊：把偏移設成讓第 `index` 行「剛好是現在播放的那一行」，並依曲目記住。
    /// 行時間用 `timeline.lines` 的原始時間（不含偏移），所以不論現有偏移是多少結果都一樣。
    /// - Parameter position: 點擊當下的播放位置（秒）；播放中時請傳「點擊那一刻」的時鐘讀數。
    /// - Returns: 沒有可對齊的行（沒載入、索引無效、空白行、位置無效）回傳 nil。
    @discardableResult
    func alignOffset(toLine index: Int, atPosition position: TimeInterval) -> LyricsOffsetAlignment.Result? {
        guard status == .loaded, timeline.lines.indices.contains(index) else { return nil }
        let line = timeline.lines[index]
        guard !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let result = LyricsOffsetAlignment.aligned(
            position: position, lineTimeMs: line.timeMs, lrcOffsetMs: timeline.lrcOffsetMs
        ) else { return nil }
        setOffset(result.offsetMs)
        return result
    }

    func resetOffset() {
        setOffset(0)
    }

    /// 清除磁碟上的歌詞快取（設定頁的按鈕）。回傳刪除的檔案數；失敗回傳 nil。
    @discardableResult
    func clearCache() -> Int? {
        try? cacheStore?.removeAll()
    }

    // MARK: - 流程

    /// 依「功能是否開啟」與「目前曲目」決定要清除、保持或重新載入。
    private func evaluate() {
        guard Defaults[.enableLyrics], let track else {
            reset(to: .idle)
            return
        }
        let key = track.key
        // 同一首（含錯誤狀態）不重複查：錯誤由有限次數的自動重試處理，避免每次狀態更新都打網路。
        if key == loadedKey { return }

        cancelWork()
        loadedKey = key
        picked = nil
        timeline = LyricsTimeline(lines: [])
        lines = []
        offsetMs = offsetStore.offsetMs(for: key)
        load(track, key: key, attempt: 0, delay: Self.debounce)
    }

    private func load(_ track: LyricsTrack, key: TrackKey, attempt: Int, delay: Duration) {
        status = .loading
        // 查詢一律用播放器原值；不送專輯名（來源資料很髒，只會降低命中率；也與設定頁的揭露文字一致）。
        // 來源是瀏覽器（影片標題）時，Core 的 VideoAwareLyricsFetcher 會先萃取歌名／歌手再查；
        // 快取鍵仍是原始曲目鍵（歌名＋歌手＋長度）。Apple Music 等乾淨來源的行為完全不變。
        let query = LyricsQuery(
            title: track.title, artist: track.artist, album: nil, duration: track.duration,
            sourceBundleID: track.sourceBundleID
        )
        let repository = repository
        fetchTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: delay)
                let result = try await repository.lyrics(for: query)
                guard let self, !Task.isCancelled, self.loadedKey == key else { return }
                self.apply(result)
            } catch is CancellationError {
                return
            } catch {
                guard let self, !Task.isCancelled, self.loadedKey == key else { return }
                self.status = .error
                self.scheduleRetry(track, key: key, attempt: attempt)
            }
        }
    }

    private func scheduleRetry(_ track: LyricsTrack, key: TrackKey, attempt: Int) {
        guard attempt < Self.maxRetries else { return }
        retryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.retryDelay)
            guard let self, !Task.isCancelled, self.loadedKey == key, self.status == .error else { return }
            self.load(track, key: key, attempt: attempt + 1, delay: .zero)
        }
    }

    private func cancelWork() {
        fetchTask?.cancel()
        localizeTask?.cancel()
        retryTask?.cancel()
        fetchTask = nil
        localizeTask = nil
        retryTask = nil
    }

    private func reset(to newStatus: Status) {
        // 每次狀態更新都會呼叫 setTrack；已經是空狀態就不要再發布變更（@Published 賦值一律會通知觀察者）。
        if status == newStatus, loadedKey == nil, lines.isEmpty, picked == nil { return }
        cancelWork()
        loadedKey = nil
        picked = nil
        timeline = LyricsTimeline(lines: [])
        lines = []
        offsetMs = 0
        status = newStatus
    }

    private func apply(_ result: PickedLyrics?) {
        guard let result else {
            picked = nil
            status = .notFound
            return
        }
        picked = result
        timeline = result.timeline
        localize(result, publishAs: .loaded)
    }

    /// 簡繁設定（台灣慣用詞）變更時，用已載入的歌詞重新轉換，不必重查。
    private func relocalize() {
        guard let picked, status == .loaded else { return }
        localize(picked, publishAs: .loaded)
    }

    private func localize(_ lyrics: PickedLyrics, publishAs newStatus: Status) {
        localizeTask?.cancel()
        let texts = lyrics.timeline.lines.map(\.text)
        let options = LyricsLocalizationOptions(useTaiwanIdioms: Defaults[.lyricsTaiwanIdioms])
        let localizer = localizer
        let key = loadedKey
        localizeTask = Task { @MainActor [weak self] in
            // 首次使用要載入字典（約 20–30 ms），放到背景做，避免卡住主執行緒。
            let converted = await Task.detached(priority: .userInitiated) {
                (try? localizer.localize(lines: texts, options: options).lines) ?? texts
            }.value
            guard let self, !Task.isCancelled, self.loadedKey == key else { return }
            self.lines = converted
            self.status = newStatus
        }
    }

    private func setOffset(_ ms: Int) {
        guard let key = loadedKey else { return }
        let clamped = LyricsOffsetAlignment.clamp(ms)
        offsetMs = clamped
        offsetStore.setOffsetMs(clamped, for: key)
    }

    // MARK: - 組裝 Core 管線

    private static func makeCacheStore() -> FileLyricsCacheStore? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        let directory = support.appendingPathComponent("DavidNook/Lyrics", isDirectory: true)
        return try? FileLyricsCacheStore(directory: directory)
    }

    private static func makeRepository(store: FileLyricsCacheStore?) -> LyricsRepository {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? DavidNookCore.version
        let cache: any LyricsCacheStore = store ?? MemoryLyricsCacheStore()
        // 組裝（簡繁感知的挑選／剝檔頭／查詢變體）在 Core 的 LyricsPipeline，有離線測試；HTTP 走 URLSessionTransport。
        return LyricsPipeline.makeRepository(transport: URLSessionTransport(), store: cache, appVersion: version)
    }
}
