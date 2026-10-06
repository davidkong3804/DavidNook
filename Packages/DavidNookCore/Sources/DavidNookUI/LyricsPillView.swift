import AppKit
import SwiftUI

/// 膠囊的外觀設定（來自設定頁；在這裡再夾一次，視圖永遠拿到合法值）。
public struct LyricsPillStyle: Equatable, Sendable {
    public var fontSize: CGFloat
    public var maxWidth: CGFloat
    public var speedMultiplier: Double
    public var reduceMotion: Bool

    public init(
        fontSize: CGFloat = LyricsPillMetrics.defaultFontSize,
        maxWidth: CGFloat = LyricsPillMetrics.defaultMaxWidth,
        speedMultiplier: Double = LyricsPillMetrics.defaultSpeed,
        reduceMotion: Bool = false
    ) {
        self.fontSize = LyricsPillMetrics.clampedFontSize(fontSize)
        self.maxWidth = LyricsPillMetrics.clampedMaxWidth(maxWidth)
        self.speedMultiplier = LyricsPillMetrics.clampedSpeed(speedMultiplier)
        self.reduceMotion = reduceMotion
    }
}

/// 一句歌詞與它的播放時間範圍（已含使用者偏移；秒）。
public struct LyricsPillLine: Equatable, Sendable {
    public var index: Int
    public var text: String
    public var start: TimeInterval
    /// 下一行開始的時間；沒有下一行為 nil。
    public var end: TimeInterval?

    public init(index: Int, text: String, start: TimeInterval, end: TimeInterval?) {
        self.index = index
        self.text = text
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval? { end.map { $0 - start } }
}

/// 某一刻的取樣：目前行＋播放位置（秒）。
public struct LyricsPillSample: Equatable, Sendable {
    public var line: LyricsPillLine
    public var position: TimeInterval

    public init(line: LyricsPillLine, position: TimeInterval) {
        self.line = line
        self.position = position
    }

    public var elapsed: TimeInterval { max(position - line.start, 0) }
}

/// 一句歌詞在膠囊裡的版面：文字寬、膠囊寬、可用寬與跑馬燈時間軸。
struct LyricsPillLayout: Equatable {
    var textWidth: CGFloat
    var pillWidth: CGFloat
    var containerWidth: CGFloat
    var marquee: LyricsMarquee

    init(text: String, lineDuration: TimeInterval?, style: LyricsPillStyle) {
        let width = LyricsTextWidthCache.shared.width(text: text, fontSize: style.fontSize)
        textWidth = width
        pillWidth = LyricsPillMetrics.pillWidth(textWidth: width, maxWidth: style.maxWidth)
        containerWidth = LyricsPillMetrics.textContainerWidth(pillWidth: pillWidth)
        marquee = LyricsMarquee(
            containerWidth: containerWidth, textWidth: width, lineDuration: lineDuration,
            speedMultiplier: style.speedMultiplier
        )
    }
}

/// 膠囊的黑色底（寬度隨歌詞，高 22）。
struct LyricsPillBackground: View {
    var width: CGFloat

    var body: some View {
        Capsule(style: .continuous)
            .fill(Color.black)
            .frame(width: width, height: LyricsPillMetrics.height)
    }
}

/// 膠囊裡的文字層：放得下＝置中靜止；放不下＝依 `elapsed` 捲動；「減少動態」＝不捲、尾端漸層截斷。
struct LyricsPillTextLayer: View {
    var text: String
    var elapsed: TimeInterval
    var layout: LyricsPillLayout
    var style: LyricsPillStyle

    var body: some View {
        let label = Text(text)
            .font(LyricsFont.font(size: style.fontSize, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.9))
            .lineLimit(1)
            .fixedSize()
        let container = layout.containerWidth
        Group {
            if !layout.marquee.needsScrolling {
                label.frame(width: container, height: LyricsPillMetrics.height, alignment: .center)
            } else {
                let offset = style.reduceMotion ? 0 : layout.marquee.scrollOffset(at: elapsed)
                label
                    .offset(x: -offset)
                    .frame(width: container, height: LyricsPillMetrics.height, alignment: .leading)
                    .clipped()
                    .mask(edgeMask(container: container, offset: offset))
            }
        }
    }

    /// 兩側柔化：還有東西在左邊（已捲出去）才淡出左緣；右邊還有沒顯示完的才淡出右緣。
    private func edgeMask(container: CGFloat, offset: CGFloat) -> some View {
        let fade = min(LyricsPillMetrics.edgeFade, container / 3) / max(container, 1)
        let fadeLeft = offset > 0.5
        let fadeRight = offset < layout.marquee.overflow - 0.5
        return LinearGradient(
            stops: [
                .init(color: fadeLeft ? .clear : .black, location: 0),
                .init(color: .black, location: fade),
                .init(color: .black, location: 1 - fade),
                .init(color: fadeRight ? .clear : .black, location: 1),
            ],
            startPoint: .leading, endPoint: .trailing
        )
    }
}

/// 靜態的完整膠囊（底＋文字層）：離屏渲染與測試用；`elapsed` 為這一句開始後經過的秒數。
public struct LyricsPillContent: View {
    var text: String
    var elapsed: TimeInterval
    var lineDuration: TimeInterval?
    var style: LyricsPillStyle

    public init(text: String, elapsed: TimeInterval, lineDuration: TimeInterval?, style: LyricsPillStyle = LyricsPillStyle()) {
        self.text = text
        self.elapsed = elapsed
        self.lineDuration = lineDuration
        self.style = style
    }

    public var body: some View {
        let layout = LyricsPillLayout(text: text, lineDuration: lineDuration, style: style)
        ZStack {
            LyricsPillBackground(width: layout.pillWidth)
            LyricsPillTextLayer(text: text, elapsed: elapsed, layout: layout, style: style)
        }
        .frame(width: layout.pillWidth, height: LyricsPillMetrics.height)
    }
}

/// 膠囊（含換句動畫）的寬度；App 用它讓點擊／hover 的透明區域與畫面上的膠囊同寬。
public enum LyricsPillSizing {
    public static func pillWidth(text: String, style: LyricsPillStyle) -> CGFloat {
        LyricsPillLayout(text: text, lineDuration: nil, style: style).pillWidth
    }
}

/// 即時的歌詞膠囊（App 用）。
///
/// 取樣（目前行）由呼叫端的 `TimelineView`（10 Hz，不播放／不顯示時暫停＝零成本）提供；只有「這一句放不下、
/// 正在捲動」時，這裡的內層 `TimelineView(.animation)` 才逐幀更新位移，捲完或靜止就停。換句以 `id` 做交叉淡入＋
/// 微小上移，底（膠囊）不跟著淡，所以換句時外形穩定、只有寬度平順變化。
public struct LyricsPillView: View {
    var sample: LyricsPillSample?
    var isVisible: Bool
    var isTicking: Bool
    var style: LyricsPillStyle
    var motion: NotchMotion
    var positionAt: (Date) -> TimeInterval

    public init(
        sample: LyricsPillSample?, isVisible: Bool, isTicking: Bool, style: LyricsPillStyle, motion: NotchMotion,
        positionAt: @escaping (Date) -> TimeInterval
    ) {
        self.sample = sample
        self.isVisible = isVisible
        self.isTicking = isTicking
        self.style = style
        self.motion = motion
        self.positionAt = positionAt
    }

    public var body: some View {
        LyricsPillBody(
            sample: sample, isVisible: isVisible, isTicking: isTicking,
            style: style, motion: motion, positionAt: positionAt
        )
    }
}

private struct LyricsPillBody: View {
    var sample: LyricsPillSample?
    var isVisible: Bool
    var isTicking: Bool
    var style: LyricsPillStyle
    var motion: NotchMotion
    var positionAt: (Date) -> TimeInterval

    /// 最後一句非空的歌詞：淡出期間（間奏、暫停、展開）沿用它，膠囊不會在淡出途中變空。
    @State private var held: LyricsPillSample?

    var body: some View {
        let shown = sample ?? held
        let change = LyricsPillMetrics.lineChangeMotion(motion)
        let animation: Animation = change.duration > 0 ? .easeInOut(duration: change.duration) : .linear(duration: 0)
        ZStack {
            if let shown {
                let layout = LyricsPillLayout(text: shown.line.text, lineDuration: shown.line.duration, style: style)
                LyricsPillBackground(width: layout.pillWidth)
                    .animation(animation, value: layout.pillWidth)
                scrolling(shown, layout: layout)
                    .id(shown.line.index)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: change.offsetY)),
                        removal: .opacity.combined(with: .offset(y: -change.offsetY))
                    ))
            }
        }
        .animation(animation, value: shown?.line.index)
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : -change.offsetY)
        .animation(animation, value: isVisible)
        .onChange(of: sample) { _, new in if let new { held = new } }
        .onAppear { if let sample { held = sample } }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func scrolling(_ shown: LyricsPillSample, layout: LyricsPillLayout) -> some View {
        let moving = isTicking && !style.reduceMotion && layout.marquee.isScrolling(at: shown.elapsed)
        TimelineView(.animation(paused: !moving)) { context in
            let elapsed = moving
                ? max(positionAt(context.date) - shown.line.start, 0)
                : shown.elapsed
            LyricsPillTextLayer(text: shown.line.text, elapsed: elapsed, layout: layout, style: style)
        }
        .frame(width: layout.pillWidth, height: LyricsPillMetrics.height)
    }
}

/// 歌詞文字寬度的量測快取（鍵＝文字＋字級）：換句才重新量測，TimelineView 每個 tick 只算捲動位移。
/// （原本每個 tick 都重做字型查找與文字量測，是收合時 CPU 的熱點。）有容量上限，只存數字不存畫面。
final class LyricsTextWidthCache: @unchecked Sendable {
    static let shared = LyricsTextWidthCache()

    private struct Key: Hashable { var text: String; var size: CGFloat }
    private let measure: (String, CGFloat) -> CGFloat
    private let capacity: Int
    private let lock = NSLock()
    private var values: [Key: CGFloat] = [:]
    private var order: [Key] = []
    private(set) var measureCount = 0

    init(capacity: Int = 64, measure: @escaping (String, CGFloat) -> CGFloat = LyricsTextWidthCache.measureWithFont) {
        self.capacity = max(capacity, 1)
        self.measure = measure
    }

    var count: Int { lock.lock(); defer { lock.unlock() }; return values.count }

    func width(text: String, fontSize: CGFloat) -> CGFloat {
        let key = Key(text: text, size: fontSize)
        lock.lock()
        if let hit = values[key] { lock.unlock(); return hit }
        measureCount += 1
        lock.unlock()
        let width = measure(text, fontSize)
        lock.lock()
        if values[key] == nil {
            if order.count >= capacity, let oldest = order.first { order.removeFirst(); values[oldest] = nil }
            values[key] = width
            order.append(key)
        }
        lock.unlock()
        return width
    }

    static func measureWithFont(_ text: String, _ size: CGFloat) -> CGFloat {
        let font = LyricsFont.nsFont(size: size, weight: .medium)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
}
