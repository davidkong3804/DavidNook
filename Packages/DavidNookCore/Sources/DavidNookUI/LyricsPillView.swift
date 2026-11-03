import AppKit
import SwiftUI

/// 膠囊的外觀設定（來自設定頁；在這裡再夾一次，視圖永遠拿到合法值）。
public struct LyricsPillStyle: Equatable, Sendable {
    public var fontSize: CGFloat
    public var maxWidth: CGFloat
    public var speedMultiplier: Double
    public var reduceMotion: Bool
    /// 歌詞文字顏色；nil＝預設的白字（90% 不透明）。App 傳入跟著專輯封面染色的顏色（見 `LyricsPillTint`）。
    public var textColor: Color?

    public init(
        fontSize: CGFloat = LyricsPillMetrics.defaultFontSize,
        maxWidth: CGFloat = LyricsPillMetrics.defaultMaxWidth,
        speedMultiplier: Double = LyricsPillMetrics.defaultSpeed,
        reduceMotion: Bool = false,
        textColor: Color? = nil
    ) {
        self.textColor = textColor
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
    /// 中文翻譯（日文／韓文歌且沒關閉雙語時）；nil 或空白＝只顯示原文。
    public var translation: String?

    public init(index: Int, text: String, start: TimeInterval, end: TimeInterval?, translation: String? = nil) {
        self.index = index
        self.text = text
        self.start = start
        self.end = end
        self.translation = translation
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

/// 翻譯文字去頭尾空白；空白視為沒有翻譯。
private func usableTranslation(_ translation: String?) -> String? {
    guard let trimmed = translation?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
    return trimmed
}

/// 一句歌詞在膠囊裡的版面：文字寬、膠囊寬、可用寬與跑馬燈時間軸。有翻譯時是兩行（原文＋較小的翻譯），
/// 膠囊寬取兩行較寬者，兩行各自有跑馬燈（放得下就不捲）。
struct LyricsPillLayout: Equatable {
    var textWidth: CGFloat
    var pillWidth: CGFloat
    var containerWidth: CGFloat
    var marquee: LyricsMarquee
    var translation: String?
    var translationMarquee: LyricsMarquee?
    var height: CGFloat

    init(text: String, translation: String? = nil, lineDuration: TimeInterval?, style: LyricsPillStyle) {
        let width = LyricsTextWidthCache.shared.width(text: text, fontSize: style.fontSize)
        let translation = usableTranslation(translation)
        let translationWidth = translation.map {
            LyricsTextWidthCache.shared.width(text: $0, fontSize: LyricsPillMetrics.translationFontSize(for: style.fontSize))
        }
        let pillWidth = LyricsPillMetrics.pillWidth(textWidth: max(width, translationWidth ?? 0), maxWidth: style.maxWidth)
        let containerWidth = LyricsPillMetrics.textContainerWidth(pillWidth: pillWidth)
        self.textWidth = width
        self.pillWidth = pillWidth
        self.containerWidth = containerWidth
        self.marquee = LyricsMarquee(
            containerWidth: containerWidth, textWidth: width, lineDuration: lineDuration,
            speedMultiplier: style.speedMultiplier
        )
        self.translation = translation
        self.translationMarquee = translationWidth.map {
            LyricsMarquee(
                containerWidth: containerWidth, textWidth: $0, lineDuration: lineDuration,
                speedMultiplier: style.speedMultiplier
            )
        }
        self.height = LyricsPillMetrics.height(hasTranslation: translation != nil)
    }
}

/// 膠囊的黑色底（寬度隨歌詞，高 22；有翻譯時 38）。
struct LyricsPillBackground: View {
    var width: CGFloat
    var height: CGFloat = LyricsPillMetrics.height

    var body: some View {
        Capsule(style: .continuous)
            .fill(Color.black)
            .frame(width: width, height: height)
    }
}

/// 膠囊裡的一行文字：放得下＝置中靜止；放不下＝依 `elapsed` 捲動；「減少動態」＝不捲、尾端漸層截斷。
struct LyricsPillLineLabel: View {
    var text: String
    var elapsed: TimeInterval
    var marquee: LyricsMarquee
    var containerWidth: CGFloat
    var fontSize: CGFloat
    var lineHeight: CGFloat
    var color: Color
    var reduceMotion: Bool

    var body: some View {
        let label = Text(text)
            .font(LyricsFont.font(size: fontSize, weight: .medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
        Group {
            if !marquee.needsScrolling {
                label.frame(width: containerWidth, height: lineHeight, alignment: .center)
            } else {
                let offset = reduceMotion ? 0 : marquee.scrollOffset(at: elapsed)
                label
                    .offset(x: -offset)
                    .frame(width: containerWidth, height: lineHeight, alignment: .leading)
                    .clipped()
                    .mask(edgeMask(offset: offset))
            }
        }
    }

    /// 兩側柔化：還有東西在左邊（已捲出去）才淡出左緣；右邊還有沒顯示完的才淡出右緣。
    private func edgeMask(offset: CGFloat) -> some View {
        let fade = min(LyricsPillMetrics.edgeFade, containerWidth / 3) / max(containerWidth, 1)
        let fadeLeft = offset > 0.5
        let fadeRight = offset < marquee.overflow - 0.5
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

/// 膠囊裡的文字層：單行，或原文＋較小、較淡的翻譯兩行。
struct LyricsPillTextLayer: View {
    var text: String
    var elapsed: TimeInterval
    var layout: LyricsPillLayout
    var style: LyricsPillStyle

    var body: some View {
        let base = style.textColor ?? Color.white.opacity(0.9)
        if let translation = layout.translation, let translationMarquee = layout.translationMarquee {
            VStack(spacing: 0) {
                LyricsPillLineLabel(
                    text: text, elapsed: elapsed, marquee: layout.marquee, containerWidth: layout.containerWidth,
                    fontSize: style.fontSize, lineHeight: LyricsPillMetrics.primaryLineHeight, color: base,
                    reduceMotion: style.reduceMotion
                )
                LyricsPillLineLabel(
                    text: translation, elapsed: elapsed, marquee: translationMarquee, containerWidth: layout.containerWidth,
                    fontSize: LyricsPillMetrics.translationFontSize(for: style.fontSize),
                    lineHeight: LyricsPillMetrics.translationLineHeight, color: base.opacity(0.72),
                    reduceMotion: style.reduceMotion
                )
            }
            .frame(width: layout.containerWidth, height: layout.height)
        } else {
            LyricsPillLineLabel(
                text: text, elapsed: elapsed, marquee: layout.marquee, containerWidth: layout.containerWidth,
                fontSize: style.fontSize, lineHeight: LyricsPillMetrics.height, color: base,
                reduceMotion: style.reduceMotion
            )
        }
    }
}

/// 靜態的完整膠囊（底＋文字層）：離屏渲染與測試用；`elapsed` 為這一句開始後經過的秒數。
public struct LyricsPillContent: View {
    var text: String
    var translation: String?
    var elapsed: TimeInterval
    var lineDuration: TimeInterval?
    var style: LyricsPillStyle

    public init(
        text: String, translation: String? = nil, elapsed: TimeInterval, lineDuration: TimeInterval?,
        style: LyricsPillStyle = LyricsPillStyle()
    ) {
        self.text = text
        self.translation = translation
        self.elapsed = elapsed
        self.lineDuration = lineDuration
        self.style = style
    }

    public var body: some View {
        let layout = LyricsPillLayout(text: text, translation: translation, lineDuration: lineDuration, style: style)
        ZStack {
            LyricsPillBackground(width: layout.pillWidth, height: layout.height)
            LyricsPillTextLayer(text: text, elapsed: elapsed, layout: layout, style: style)
        }
        .frame(width: layout.pillWidth, height: layout.height)
    }
}

/// 膠囊（含換句動畫）的尺寸；App 用它讓點擊／hover／穿透的區域與畫面上的膠囊一樣大。
public enum LyricsPillSizing {
    public static func pillWidth(text: String, style: LyricsPillStyle) -> CGFloat {
        LyricsPillLayout(text: text, lineDuration: nil, style: style).pillWidth
    }

    /// 寬＝兩行較寬者；高＝單行 22、有翻譯（非空白）時 38。
    public static func pillSize(text: String, translation: String?, style: LyricsPillStyle) -> CGSize {
        let layout = LyricsPillLayout(text: text, translation: translation, lineDuration: nil, style: style)
        return CGSize(width: layout.pillWidth, height: layout.height)
    }
}

/// 即時的歌詞膠囊（App 用）。
///
/// 取樣（目前行）由呼叫端的 `TimelineView`（10 Hz，不播放／不顯示時暫停＝零成本）提供；只有「這一句放不下、
/// 正在捲動」時，這裡的內層 `TimelineView(.animation)` 才逐幀更新位移，捲完或靜止就停。換句以 `id` 做交叉淡入＋
/// 微小上移，底（膠囊）不跟著淡，所以換句時外形穩定、只有寬度（與單行↔雙行的高度）平順變化。
public struct LyricsPillView: View {
    var sample: LyricsPillSample?
    var isVisible: Bool
    var isTicking: Bool
    var style: LyricsPillStyle
    var motion: NotchMotion
    /// 滑鼠停在膠囊上、膠囊暫時「透過去」時的不透明度（1＝正常）。
    var passThroughOpacity: Double
    var positionAt: (Date) -> TimeInterval

    public init(
        sample: LyricsPillSample?, isVisible: Bool, isTicking: Bool, style: LyricsPillStyle, motion: NotchMotion,
        passThroughOpacity: Double = 1,
        positionAt: @escaping (Date) -> TimeInterval
    ) {
        self.sample = sample
        self.isVisible = isVisible
        self.isTicking = isTicking
        self.style = style
        self.motion = motion
        self.passThroughOpacity = passThroughOpacity
        self.positionAt = positionAt
    }

    public var body: some View {
        LyricsPillBody(
            sample: sample, isVisible: isVisible, isTicking: isTicking,
            style: style, motion: motion, passThroughOpacity: passThroughOpacity, positionAt: positionAt
        )
    }
}

private struct LyricsPillBody: View {
    var sample: LyricsPillSample?
    var isVisible: Bool
    var isTicking: Bool
    var style: LyricsPillStyle
    var motion: NotchMotion
    var passThroughOpacity: Double
    var positionAt: (Date) -> TimeInterval

    /// 最後一句非空的歌詞：淡出期間（間奏、暫停、展開）沿用它，膠囊不會在淡出途中變空。
    @State private var held: LyricsPillSample?

    var body: some View {
        let shown = sample ?? held
        let change = LyricsPillMetrics.lineChangeMotion(motion)
        let animation: Animation = change.duration > 0 ? .easeInOut(duration: change.duration) : .linear(duration: 0)
        ZStack(alignment: .top) {
            if let shown {
                let layout = LyricsPillLayout(
                    text: shown.line.text, translation: shown.line.translation,
                    lineDuration: shown.line.duration, style: style
                )
                LyricsPillBackground(width: layout.pillWidth, height: layout.height)
                    .animation(animation, value: layout.pillWidth)
                    .animation(animation, value: layout.height)
                scrolling(shown, layout: layout)
                    .id(shown.line.index)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: change.offsetY)),
                        removal: .opacity.combined(with: .offset(y: -change.offsetY))
                    ))
            }
        }
        .animation(animation, value: shown?.line.index)
        .opacity(isVisible ? passThroughOpacity : 0)
        .offset(y: isVisible ? 0 : -change.offsetY)
        .animation(animation, value: isVisible)
        .animation(.easeOut(duration: 0.15), value: passThroughOpacity)
        .onChange(of: sample) { _, new in if let new { held = new } }
        .onAppear { if let sample { held = sample } }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func scrolling(_ shown: LyricsPillSample, layout: LyricsPillLayout) -> some View {
        let moving = isTicking && !style.reduceMotion
            && (layout.marquee.isScrolling(at: shown.elapsed) || layout.translationMarquee?.isScrolling(at: shown.elapsed) == true)
        TimelineView(.animation(paused: !moving)) { context in
            let elapsed = moving
                ? max(positionAt(context.date) - shown.line.start, 0)
                : shown.elapsed
            LyricsPillTextLayer(text: shown.line.text, elapsed: elapsed, layout: layout, style: style)
        }
        .frame(width: layout.pillWidth, height: layout.height)
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
