import CoreGraphics

// 紅燈階段的介面骨架。

public struct NotchHomeMetrics: Equatable, Sendable {
    public enum Density: Sendable { case regular, compact }

    public static let controlsMinimumWidth: CGFloat = 0
    public static let lyricsMinimumWidth: CGFloat = 0
    public static let lyricsMaximumWidth: CGFloat = 0
    public static let regularControlsHeight: CGFloat = 0

    public let contentWidth: CGFloat
    public let bodyHeight: CGFloat
    public let showsLyrics: Bool
    public var density: Density { .regular }
    public var artSize: CGFloat { 0 }
    public var artPadding: CGFloat { 0 }
    public var lyricsVisibleLines: Int { 0 }
    public var lyricsHeight: CGFloat { 0 }
    public var lyricsWidth: CGFloat { 0 }
    public var controlsWidth: CGFloat { 0 }
    public var horizontalExtent: CGFloat { 0 }
    public var controlsMinimumHeight: CGFloat { 0 }

    public init(contentWidth: CGFloat, bodyHeight: CGFloat, showsLyrics: Bool) {
        self.contentWidth = contentWidth
        self.bodyHeight = bodyHeight
        self.showsLyrics = showsLyrics
    }
}
