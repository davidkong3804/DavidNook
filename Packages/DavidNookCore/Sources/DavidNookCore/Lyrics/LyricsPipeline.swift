import Foundation

/// 把 Core 的歌詞零件組成 App 實際使用的管線：簡繁感知的候選挑選、檔頭剝除與查詢變體。
///
/// - **剝檔頭的比對**：歌名／歌手名與歌詞檔內的檔頭行兩邊都先轉成簡體（`.traditionalToSimplified`）再比，
///   所以標題是繁體、歌詞檔是簡體（或相反）也認得出「歌名 - 歌手」這類中繼行。
/// - **簡繁分類**：`ChineseScriptDetector`（專有字統計）。
/// - **查詢變體**（原樣固定最先；原樣查不到才試這些）：
///   歌名＋歌手為簡體 → 加「轉繁」變體（`.conservative`）；為繁體 → 加「轉簡」變體；混合 → 兩者都加；
///   沒有專有字（英文等）→ 不加。**變體只用於查詢**，顯示一律用播放器的原值。
/// - 轉換器載入失敗（字典資源缺失，屬封裝錯誤）時退化為不轉換，不讓歌詞功能整個壞掉。
public enum LyricsPipeline {

    /// 依歌名＋歌手的簡繁判斷產生查詢變體（專輯名不帶入變體）。
    public static func queryVariants(for query: LyricsQuery) -> [LyricsQuery] {
        let script = ChineseScriptDetector().detect(query.title + "\n" + query.artist)
        func converted(_ converter: LyricsChineseConverter) -> LyricsQuery {
            var copy = query
            copy.title = converter.convert(query.title)
            copy.artist = converter.convert(query.artist)
            copy.album = nil
            return copy
        }
        var result: [LyricsQuery] = []
        if script == .simplified || script == .mixed, let toTraditional = try? LyricsChineseConverter.cached(.conservative) {
            result.append(converted(toTraditional))
        }
        if script == .traditional || script == .mixed, let toSimplified = try? LyricsChineseConverter.cached(.traditionalToSimplified) {
            result.append(converted(toSimplified))
        }
        return result
    }

    /// 候選挑選器（簡繁分類＋簡繁不敏感的檔頭剝除）。
    public static func makePicker() -> LyricsCandidatePicker {
        let detector = ChineseScriptDetector()
        let toSimplified = try? LyricsChineseConverter.cached(.traditionalToSimplified)
        let stripper = LyricsMetaStripper(normalize: { toSimplified?.convert($0) ?? $0 })
        return LyricsCandidatePicker(scriptClassifier: { detector.detect($0) }, stripper: stripper)
    }

    /// LRCLIB 用戶端（原樣＋簡繁變體；`User-Agent` 帶 `appVersion`）。
    public static func makeClient(
        transport: any HTTPTransport,
        appVersion: String = DavidNookCore.version,
        sleeper: @escaping Sleeper = LrclibClient.defaultSleeper,
        requestSpacing: TimeInterval = 0.25,
        baseURL: URL = URL(string: "https://lrclib.net")!
    ) -> LrclibClient {
        LrclibClient(
            transport: transport,
            picker: makePicker(),
            variants: { queryVariants(for: $0) },
            sleeper: sleeper,
            appVersion: appVersion,
            baseURL: baseURL,
            requestSpacing: requestSpacing
        )
    }

    /// 歌詞倉庫（快取＋用戶端）。
    public static func makeRepository(
        transport: any HTTPTransport,
        store: any LyricsCacheStore,
        appVersion: String = DavidNookCore.version,
        negativeTTL: TimeInterval = 1_800,
        sleeper: @escaping Sleeper = LrclibClient.defaultSleeper,
        requestSpacing: TimeInterval = 0.25,
        baseURL: URL = URL(string: "https://lrclib.net")!
    ) -> LyricsRepository {
        let client = makeClient(
            transport: transport, appVersion: appVersion, sleeper: sleeper,
            requestSpacing: requestSpacing, baseURL: baseURL
        )
        return LyricsRepository(fetcher: client, store: store, negativeTTL: negativeTTL)
    }
}
