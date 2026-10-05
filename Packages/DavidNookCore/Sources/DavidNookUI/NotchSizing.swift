import CoreGraphics

// 紅燈階段的介面骨架：簽名已定案，行為尚未實作。

public struct NotchSizing: Equatable, Sendable {
    public enum Panel: CaseIterable, Sendable {
        case home
        case clipboard
    }

    public static let widthRange: ClosedRange<CGFloat> = 0...0
    public static let widthStep: CGFloat = 0
    public static let defaultWidth: CGFloat = 0
    public static let heightScaleRange: ClosedRange<CGFloat> = 0...0
    public static let defaultHeightScale: CGFloat = 0
    public static let minimumBodyHeight: CGFloat = 0
    public static let bottomInset: CGFloat = 0
    public static let shadowPadding: CGFloat = 0
    public static let legacyClosedWindowSize = CGSize.zero
    public static var maximumOpenSize: CGSize { .zero }

    public let width: CGFloat
    public let heightScale: CGFloat

    public init(width: Double = 0, heightScale: Double = 0) {
        self.width = CGFloat(width)
        self.heightScale = CGFloat(heightScale)
    }

    public var isDefault: Bool { false }
    public static func snappedWidth(_ value: Double) -> CGFloat { 0 }
    public func openSize(for panel: Panel, headerHeight: CGFloat = 38) -> CGSize { .zero }
    public func bodyHeight(for panel: Panel, headerHeight: CGFloat = 38) -> CGFloat { 0 }
    public func contentWidth(earInset: CGFloat) -> CGFloat { 0 }
    public static func windowSize(isOpen: Bool) -> CGSize { .zero }
    public static func anchoredFrame(from frame: CGRect, to size: CGSize) -> CGRect { .zero }
}
