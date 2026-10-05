import Foundation

/// 「同一首曲目」的識別鍵：歌名 + 歌手 + 長度（取整秒）。
///
/// 歌詞快取與逐曲偏移都以它為鍵。
/// - 歌名、歌手：Unicode 正規化（NFC）、去前後空白、轉小寫。
/// - 長度：四捨五入到整秒；NaN、無限大、負值、0（未知）一律記為 0。
/// - 刻意不含專輯名（來源資料很髒）。
public struct TrackKey: Hashable, Codable, Sendable {
    public let title: String
    public let artist: String
    /// 長度，單位：整秒（四捨五入）。
    public let durationSeconds: Int

    /// - Parameter duration: 曲目長度，單位：秒。
    public init(title: String, artist: String, duration: TimeInterval) {
        self.title = Self.normalize(title)
        self.artist = Self.normalize(artist)
        if duration.isFinite, duration > 0 {
            self.durationSeconds = Int(min(duration, 1e9).rounded())
        } else {
            self.durationSeconds = 0
        }
    }

    /// 可用作 UserDefaults／檔案的字串鍵（以不可見的分隔字元 U+001F 串接，避免歌名含分隔符時產生歧義）。
    public var storageString: String {
        "\(title)\u{1F}\(artist)\u{1F}\(durationSeconds)"
    }

    private static func normalize(_ s: String) -> String {
        s.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
