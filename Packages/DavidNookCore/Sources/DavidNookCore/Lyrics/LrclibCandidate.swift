import Foundation

/// LRCLIB 回傳的一筆歌詞紀錄（`/api/get` 單筆、`/api/search` 陣列元素）。
///
/// 解碼容錯：只有 `id` 是必要欄位；其餘欄位缺少、為 null 或型別不符時取預設值，
/// 未使用的欄位（`name`、`hasWordSync`、`lyricsfile`…）直接忽略。
public struct LrclibCandidate: Decodable, Equatable, Sendable {
    public var id: Int
    public var trackName: String
    public var artistName: String
    /// 專輯名。**僅保留供除錯；來源資料很髒，本模組任何比對與排序都不得使用它。**
    public var albumName: String?
    /// 曲目長度，單位：秒（可為小數）；缺少時為 nil。
    public var duration: Double?
    /// 是否為純音樂（沒有歌詞）。
    public var instrumental: Bool
    public var plainLyrics: String?
    /// LRC 格式的逐行同步歌詞；沒有時為 nil。
    public var syncedLyrics: String?

    public init(
        id: Int,
        trackName: String,
        artistName: String,
        albumName: String?,
        duration: Double?,
        instrumental: Bool,
        plainLyrics: String?,
        syncedLyrics: String?
    ) {
        self.id = id
        self.trackName = trackName
        self.artistName = artistName
        self.albumName = albumName
        self.duration = duration
        self.instrumental = instrumental
        self.plainLyrics = plainLyrics
        self.syncedLyrics = syncedLyrics
    }

    private enum CodingKeys: String, CodingKey {
        case id, trackName, artistName, albumName, duration, instrumental, plainLyrics, syncedLyrics
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        trackName = Self.lenient(c, .trackName) ?? ""
        artistName = Self.lenient(c, .artistName) ?? ""
        albumName = Self.lenient(c, .albumName)
        duration = Self.lenient(c, .duration)
        instrumental = Self.lenient(c, .instrumental) ?? false
        plainLyrics = Self.lenient(c, .plainLyrics)
        syncedLyrics = Self.lenient(c, .syncedLyrics)
    }

    private static func lenient<T: Decodable>(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> T? {
        (try? c.decodeIfPresent(T.self, forKey: key)) ?? nil
    }
}

/// 一次歌詞查詢：目前曲目的中繼資料。
public struct LyricsQuery: Equatable, Hashable, Sendable {
    public var title: String
    public var artist: String
    /// 專輯名（選填，只會放進 `/api/get` 的 `album_name`，不參與挑選）。
    public var album: String?
    /// 曲目長度，單位：秒；≤ 0 或 NaN 代表未知。
    public var duration: TimeInterval
    /// 來源 App 的 bundle id（選填；來自「正在播放」資料）。只用於判斷「標題是否為影片標題」，**不會送出、不參與快取鍵**。
    public var sourceBundleID: String?
    /// true＝這筆查詢的歌名／歌手是從影片標題萃取出來的，`duration` 是影片長度（常比歌長）：
    /// 挑選器改用較寬鬆且不對稱的長度規則，並要求候選的歌名／歌手與查詢相符（寧缺勿錯）。
    public var isVideoDerived: Bool

    public init(
        title: String, artist: String, album: String? = nil, duration: TimeInterval,
        sourceBundleID: String? = nil, isVideoDerived: Bool = false
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.sourceBundleID = sourceBundleID
        self.isVideoDerived = isVideoDerived
    }

    /// 快取／偏移用的曲目鍵（歌名 + 歌手 + 取整秒長度）。
    public var trackKey: TrackKey { TrackKey(title: title, artist: artist, duration: duration) }

    /// 歌名非空白才有查詢意義。
    public var hasUsableTitle: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// 挑選完成的歌詞：已剝除檔頭中繼行，**尚未做簡繁轉換**。
public struct PickedLyrics: Equatable, Sendable, Codable {
    /// LRCLIB 紀錄 id。
    public var candidateID: Int
    public var trackName: String
    public var artistName: String
    /// 由注入的分類器判定的簡繁屬性（用於後續是否需要轉換）。
    public var script: LyricsScript
    /// 已排序、已剝除檔頭中繼行的歌詞行（時間為檔案內原始值，未套偏移）。
    public var lines: [LRCLine]
    /// 檔內 `[offset:]`，毫秒，正值＝歌詞提早（見 `LRCDocument.offsetMs`）。
    public var offsetMs: Int
    /// 檔內 ID tag。
    public var metadata: [String: String]

    public init(
        candidateID: Int,
        trackName: String,
        artistName: String,
        script: LyricsScript,
        lines: [LRCLine],
        offsetMs: Int = 0,
        metadata: [String: String] = [:]
    ) {
        self.candidateID = candidateID
        self.trackName = trackName
        self.artistName = artistName
        self.script = script
        self.lines = lines
        self.offsetMs = offsetMs
        self.metadata = metadata
    }

    /// 方便建立時間軸（已帶入檔內 offset；使用者偏移在查詢時另外傳入）。
    public var timeline: LyricsTimeline { LyricsTimeline(lines: lines, lrcOffsetMs: offsetMs) }
}
