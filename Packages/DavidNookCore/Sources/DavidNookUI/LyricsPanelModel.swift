import Foundation

/// 歌詞面板的狀態。
public enum LyricsPanelStatus: Equatable, Sendable {
    /// 查詢中。
    case loading
    /// 查不到同步歌詞。
    case noLyrics
    /// 純音樂（沒有歌詞）。
    case instrumental
    /// 已載入；內容見 `lines`。
    case loaded
    /// 網路或伺服器錯誤。
    case error
}

/// 面板上的一行歌詞（只含顯示需要的資料；時間軸與目前行由呼叫端算好傳入）。
public struct LyricsPanelLine: Identifiable, Equatable, Sendable {
    public let id: Int
    /// 空字串代表間奏／空白行（以留白呈現）。
    public let text: String

    public init(id: Int, text: String) {
        self.id = id
        self.text = text
    }

    public var isBlank: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// 由一組文字建立（id 為索引）。
    public static func make(from texts: [String]) -> [LyricsPanelLine] {
        texts.enumerated().map { LyricsPanelLine(id: $0.offset, text: $0.element) }
    }
}

/// 面板上的狀態文案；預設為繁體中文，App 可傳入在地化後的字串。
public struct LyricsPanelStrings: Equatable, Sendable {
    public var loading: String
    public var noLyrics: String
    public var instrumental: String
    public var error: String

    public init(loading: String, noLyrics: String, instrumental: String, error: String) {
        self.loading = loading
        self.noLyrics = noLyrics
        self.instrumental = instrumental
        self.error = error
    }

    /// 繁體中文（預設）。
    public static let zhHant = LyricsPanelStrings(
        loading: "載入歌詞中…",
        noLyrics: "這首歌沒有歌詞",
        instrumental: "純音樂",
        error: "無法取得歌詞"
    )
}

/// 偏移（毫秒）的顯示與步進；方向約定與 Core 的 `LyricsTimeline` 相同：**正值＝歌詞提早顯示**。
public enum LyricsOffsetFormat {
    /// 每次調整的步長（毫秒）。
    public static let stepMs = 500

    /// 例如 `+0.5s`、`−1.0s`（使用真正的減號 U+2212）、`0.0s`。
    public static func label(offsetMs: Int) -> String {
        let seconds = Double(abs(offsetMs)) / 1000
        let body = String(format: "%.1fs", seconds)
        if offsetMs > 0 { return "+" + body }
        if offsetMs < 0 { return "\u{2212}" + body }
        return body
    }
}

/// 歌詞面板的尺寸度量（骨架）。
public enum LyricsPanelMetrics {
    public static let defaultVisibleLines = 5
    public static func clampedVisibleLines(_ n: Int) -> Int { n }
    public static func height(forVisibleLines n: Int, fontSize: CGFloat = 14) -> CGFloat { 0 }
    public static func visibleLines(forAvailableHeight h: CGFloat, fontSize: CGFloat = 14) -> Int { 0 }
}
