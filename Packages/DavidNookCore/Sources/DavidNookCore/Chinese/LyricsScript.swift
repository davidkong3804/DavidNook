/// 歌詞文字的字體判斷結果（簡/繁/混合/中性）。
///
/// - `traditional`：繁體專有字為主，簡體專有字佔比 ≤ 3%。
/// - `simplified`：簡體專有字為主，繁體專有字佔比 ≤ 3%。
/// - `mixed`：兩邊都有足夠證據，需逐行判斷。
/// - `neutral`：沒有任何專有字（英文、純符號、只含兩邊通用字等），不轉換。
public enum LyricsScript: String, Codable, Sendable, Equatable, CaseIterable {
    case traditional
    case simplified
    case mixed
    case neutral
}
