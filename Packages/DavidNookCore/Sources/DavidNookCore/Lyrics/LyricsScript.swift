/// 一段歌詞文字的簡繁屬性。
///
/// 這是 `Lyrics/` 目錄內的最小版本，只供 `LyricsCandidatePicker` 的 `scriptClassifier`
/// 閉包回傳值使用。整合時由 `Chinese/` 的實作提供分類閉包，再對接到本型別。
public enum LyricsScript: String, Codable, Sendable, Equatable, CaseIterable {
    /// 原生繁體（簡體專有字比例低於門檻）。
    case traditional
    /// 簡體（繁體專有字比例低於門檻）。
    case simplified
    /// 簡繁混雜，無法整份判定。
    case mixed
    /// 沒有任何簡繁專有字（例如純英文、純數字、純標點）。
    case neutral
}
