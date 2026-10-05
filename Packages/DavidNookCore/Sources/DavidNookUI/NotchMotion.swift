import SwiftUI

// 紅燈階段的介面骨架：型別與簽名已定案，行為尚未實作（所有曲線都是瞬間、所有數值為預設）。

/// 一條「進度 0 → 1」的曲線（彈簧可超過 1，即過衝）。
public enum NotchMotionCurve: Equatable, Sendable {
    case instant
    case spring(Spring)
    case easeInOut(duration: TimeInterval)
    case easeOut(duration: TimeInterval)

    public func progress(at time: TimeInterval) -> Double { 1 }

    public var animation: Animation { .linear(duration: 0) }
}

/// 瀏海動畫的全部常數與純邏輯（骨架）。
public struct NotchMotion: Equatable, Sendable {
    public enum Phase: CaseIterable, Sendable {
        case open, close, tabSwitch, anticipate
    }

    public struct ContentStyle: Equatable, Sendable {
        public var opacity: Double
        public var blur: CGFloat
        public var scale: CGFloat
        public var offsetY: CGFloat

        public init(opacity: Double, blur: CGFloat, scale: CGFloat, offsetY: CGFloat) {
            self.opacity = opacity
            self.blur = blur
            self.scale = scale
            self.offsetY = offsetY
        }
    }

    public static let speedRange: ClosedRange<Double> = 0.1...4.0

    public let speed: Double
    public let reduceMotion: Bool
    public let isEnabled: Bool

    public init(speed: Double = 1, reduceMotion: Bool = false, isEnabled: Bool = true) {
        self.speed = speed
        self.reduceMotion = reduceMotion
        self.isEnabled = isEnabled
    }

    public func curve(_ phase: Phase) -> NotchMotionCurve { .instant }
    public func animation(_ phase: Phase) -> Animation { .linear(duration: 0) }

    public var anticipationScale: CGFloat { 1 }

    public var contentRevealDelay: TimeInterval { 0 }
    public var contentRevealCurve: NotchMotionCurve { .instant }
    public var contentHideCurve: NotchMotionCurve { .instant }
    public var contentRevealAnimation: Animation { .linear(duration: 0) }
    public var contentHideAnimation: Animation { .linear(duration: 0) }
    public var hiddenContentStyle: ContentStyle { ContentStyle(opacity: 1, blur: 0, scale: 1, offsetY: 0) }

    public func contentStyle(revealing: Bool, at time: TimeInterval) -> ContentStyle {
        ContentStyle(opacity: 1, blur: 0, scale: 1, offsetY: 0)
    }

    public func settleTime(for phase: Phase) -> TimeInterval { 0 }
    public var openSettleTime: TimeInterval { 0 }
}
