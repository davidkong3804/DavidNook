import Foundation

/// 影片來源感知的抓取器：包在 `LrclibClient`（或任何 `LyricsFetching`）外面。
///
/// - **乾淨來源**（Apple Music、Spotify…，或 bundle id 未知且標題不像影片標題）：原樣直通，一個請求都不多、不少。
/// - **影片來源**（瀏覽器，見 `TrackTitleExtractor.isVideoSource`）：
///   1. 以 `TrackTitleExtractor` 從影片標題＋頻道名萃取有序候選 (歌名, 歌手?)；
///   2. 依序用 `isVideoDerived` 查詢交給底層（先 `/api/get` 再 `/api/search`，沿用簡繁變體、挑選、節流與重試）；
///   3. 第一個有歌詞者勝出；全部找不到回傳 nil（**寧缺勿錯**：挑選器在影片模式要求歌名／歌手相符）。
/// - 底層丟出的錯誤（網路、429、503…）原樣往外拋，不當成「找不到」，也不繼續試後面的候選（伺服器正要我們退讓）。
/// - 候選查詢不帶專輯名；送出的只有歌名、歌手、（乾淨來源才有的）長度，與原管線相同。
///
/// 快取由外層 `LyricsRepository` 以「原始曲目鍵」處理，所以同一支影片不會重複查。
public struct VideoAwareLyricsFetcher: LyricsFetching {
    private let base: any LyricsFetching

    public init(base: any LyricsFetching) { self.base = base }

    public func lyrics(for query: LyricsQuery) async throws -> PickedLyrics? {
        try await fetch(query).lyrics
    }

    public func fetch(_ query: LyricsQuery) async throws -> LyricsFetchOutcome {
        guard TrackTitleExtractor.isVideoSource(bundleID: query.sourceBundleID, title: query.title) else {
            return try await base.fetch(query)
        }
        let candidates = TrackTitleExtractor.candidates(
            title: query.title, artist: query.artist, durationSeconds: query.duration, sourceBundleID: query.sourceBundleID
        )
        for candidate in candidates {
            try Task.checkCancellation()
            let derived = LyricsQuery(
                title: candidate.title, artist: candidate.artist ?? "", album: nil, duration: query.duration,
                sourceBundleID: query.sourceBundleID, isVideoDerived: true
            )
            let outcome = try await base.fetch(derived)
            if outcome.lyrics != nil { return outcome }
        }
        return LyricsFetchOutcome(lyrics: nil)
    }
}
