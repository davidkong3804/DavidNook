// STUB（紅燈階段）：只有 API 形狀，尚無實作。

public struct LyricsLocalizationOptions: Sendable, Equatable {
    public var useTaiwanIdioms: Bool
    public init(useTaiwanIdioms: Bool = false) {
        self.useTaiwanIdioms = useTaiwanIdioms
    }
}

public struct LocalizedLyrics: Equatable, Sendable {
    public let lines: [String]
    public let script: LyricsScript
    public let lineScripts: [LyricsScript]?
    public let appliedMode: LyricsConversionMode?
}

public final class LyricsLocalizer: @unchecked Sendable {
    public static let shared = LyricsLocalizer()

    public init() {}

    public func localize(
        lines: [String],
        options: LyricsLocalizationOptions = LyricsLocalizationOptions(),
        skippingDetectionOfLineIndices: Set<Int> = []
    ) throws -> LocalizedLyrics {
        LocalizedLyrics(lines: lines, script: .neutral, lineScripts: nil, appliedMode: nil)
    }
}
