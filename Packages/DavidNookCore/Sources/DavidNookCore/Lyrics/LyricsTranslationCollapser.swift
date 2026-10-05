import Foundation

/// 雙語歌詞收合器（紅燈階段的占位實作：尚未實作）。
public enum LyricsTranslationCollapser {
    public struct Result: Equatable, Sendable {
        public var lines: [LRCLine]
        public var dropped: [LRCLine]
    }

    public static func collapse(_ lines: [LRCLine]) -> Result {
        Result(lines: lines, dropped: [])
    }
}
