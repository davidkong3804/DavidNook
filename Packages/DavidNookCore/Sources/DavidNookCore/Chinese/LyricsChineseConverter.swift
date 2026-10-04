// STUB（紅燈階段）：只有 API 形狀，尚無實作。

public enum LyricsConversionMode: String, Sendable, CaseIterable {
    case conservative
    case taiwanIdioms
    case variantsOnly
}

public final class LyricsChineseConverter: @unchecked Sendable {
    public let mode: LyricsConversionMode

    public init(mode: LyricsConversionMode, overrides: LyricsOverrides = .bundled) throws {
        self.mode = mode
    }

    public static func cached(_ mode: LyricsConversionMode) throws -> LyricsChineseConverter {
        try LyricsChineseConverter(mode: mode)
    }

    public func convert(_ text: String) -> String { text }
}
