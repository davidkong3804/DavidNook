import SwiftUI

/// 一條「進度 0 → 1」的時間曲線。彈簧可以超過 1（過衝）；緩動曲線單調、不過衝。
///
/// 同一份定義有兩個用途：`animation` 交給 SwiftUI 實際播放，`progress(at:)` 讓測試與離屏渲染
/// 用完全相同的數學重現每一個時間點（彈簧走 `Spring.value(target:time:)`，與 SwiftUI 內部同一套公式）。
public enum NotchMotionCurve: Equatable, Sendable {
    /// 瞬間完成（動畫關閉）。
    case instant
    case spring(Spring)
    /// 與 SwiftUI `Animation.easeInOut(duration:)` 相同的三次貝茲曲線 (0.42, 0, 0.58, 1)。
    case easeInOut(duration: TimeInterval)
    /// 與 SwiftUI `Animation.easeOut(duration:)` 相同的三次貝茲曲線 (0, 0, 0.58, 1)。
    case easeOut(duration: TimeInterval)

    /// 經過 `time` 秒後的進度（目標為 1.0）。`time <= 0` 為 0（`.instant` 例外：永遠為 1）。
    public func progress(at time: TimeInterval) -> Double {
        switch self {
        case .instant:
            return 1
        case .spring(let spring):
            guard time > 0 else { return 0 }
            return spring.value(target: 1.0, time: time)
        case .easeInOut(let duration):
            return Self.bezierProgress(time: time, duration: duration, p1: (0.42, 0), p2: (0.58, 1))
        case .easeOut(let duration):
            return Self.bezierProgress(time: time, duration: duration, p1: (0, 0), p2: (0.58, 1))
        }
    }

    /// 交給 SwiftUI 播放的動畫。
    public var animation: Animation {
        switch self {
        case .instant: return .linear(duration: 0)
        case .spring(let spring): return .spring(spring)
        case .easeInOut(let duration): return .easeInOut(duration: duration)
        case .easeOut(let duration): return .easeOut(duration: duration)
        }
    }

    /// 最後一次離開「目標 ±1%」帶的時間（秒）。以 2 ms 間隔掃描到 4 秒；緩動曲線直接取其長度。
    public var settlingTime: TimeInterval {
        switch self {
        case .instant:
            return 0
        case .easeInOut(let duration), .easeOut(let duration):
            return duration
        case .spring:
            var settle = 0.0
            var t = 0.0
            while t <= 4.0 {
                if abs(progress(at: t) - 1) > 0.01 { settle = t }
                t += 0.002
            }
            return settle
        }
    }

    private static func bezierProgress(
        time: TimeInterval, duration: TimeInterval, p1: (Double, Double), p2: (Double, Double)
    ) -> Double {
        guard duration > 0 else { return 1 }
        let x = min(max(time / duration, 0), 1)
        // 解 x(s) = x 求參數 s（二分法即可，精度 1e-9），再取 y(s)。
        func coordinate(_ s: Double, _ a: Double, _ b: Double) -> Double {
            let u = 1 - s
            return 3 * u * u * s * a + 3 * u * s * s * b + s * s * s
        }
        var low = 0.0, high = 1.0
        for _ in 0..<40 {
            let mid = (low + high) / 2
            if coordinate(mid, p1.0, p2.0) < x { low = mid } else { high = mid }
        }
        return coordinate((low + high) / 2, p1.1, p2.1)
    }
}

/// 瀏海動畫的全部常數與純邏輯。
///
/// 設計取向是「有彈性、輕盈、有回彈但不誇張」：
/// - 展開：寬高同一條彈簧（response 0.46、dampingRatio 0.72，過衝約 3.8%、約 0.48 秒進入 ±1% 帶）。
/// - 收合：較硬的彈簧（response 0.34、dampingRatio 0.9），沒有可見過衝，比展開更快。
/// - 分頁切換：response 0.38、dampingRatio 0.82，形體在兩個分頁尺寸間彈性變形。
/// - 內容層：展開時延遲約 0.09 秒才淡入（同時 blur 10→0、scale 0.97→1、下移 4pt→0）；收合時無延遲、約 0.12 秒淡出。
/// - Hover 預期動作：游標進入觸發區但尚未達到停留時間時，閉合瀏海輕微鼓起（scale 1.04）。
///
/// 速度倍率（設定的 `animationSpeedMultiplier`）把所有 response／duration／delay 除以倍率（純時間軸縮放，形狀不變）；
/// 「減少動態」改為 0.2 秒 easeInOut、無過衝、無 blur／位移／縮放／預期鼓起；`isEnabled == false`（設定關閉瀏海動畫）則全部瞬間完成。
public struct NotchMotion: Equatable, Sendable {
    public enum Phase: CaseIterable, Sendable {
        case open
        case close
        case tabSwitch
        /// hover 預期動作（鼓起與復原）。
        case anticipate
    }

    /// 內容層的外觀（不透明度、模糊半徑、縮放、垂直位移）。
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

        /// 完整顯示。
        public static let shown = ContentStyle(opacity: 1, blur: 0, scale: 1, offsetY: 0)

        static func lerp(_ from: ContentStyle, _ to: ContentStyle, _ p: Double) -> ContentStyle {
            func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * p }
            return ContentStyle(
                opacity: min(max(mix(from.opacity, to.opacity), 0), 1),
                blur: CGFloat(max(mix(Double(from.blur), Double(to.blur)), 0)),
                scale: CGFloat(mix(Double(from.scale), Double(to.scale))),
                offsetY: CGFloat(mix(Double(from.offsetY), Double(to.offsetY)))
            )
        }
    }

    // MARK: - 常數（全部動畫數值都在這裡）

    public enum Constants {
        public static let openResponse = 0.46
        public static let openDampingRatio = 0.72
        public static let closeResponse = 0.34
        public static let closeDampingRatio = 0.9
        public static let tabSwitchResponse = 0.38
        public static let tabSwitchDampingRatio = 0.82
        public static let anticipateResponse = 0.2
        public static let anticipateDampingRatio = 0.7
        public static let anticipationScale: CGFloat = 1.04

        public static let contentRevealDelay = 0.09
        public static let contentRevealResponse = 0.30
        public static let contentHideDuration = 0.12
        public static let hiddenBlur: CGFloat = 10
        public static let hiddenScale: CGFloat = 0.97
        public static let hiddenOffsetY: CGFloat = 4

        /// 「減少動態」：一律 0.2 秒 easeInOut。
        public static let reducedDuration = 0.2
    }

    /// 設定裡的動畫速度倍率可調範圍（0.1× – 4×；設定頁實際只給 0.1–2.0）。
    public static let speedRange: ClosedRange<Double> = 0.1...4.0

    public let speed: Double
    public let reduceMotion: Bool
    public let isEnabled: Bool

    /// - Parameters:
    ///   - speed: `animationSpeedMultiplier`；夾到 `speedRange`，非數值視為 1。
    ///   - reduceMotion: 系統「減少動態」。
    ///   - isEnabled: 設定中「Notch animation」開關；關閉時全部瞬間完成。
    public init(speed: Double = 1, reduceMotion: Bool = false, isEnabled: Bool = true) {
        if speed.isNaN {
            self.speed = 1
        } else {
            self.speed = min(max(speed, Self.speedRange.lowerBound), Self.speedRange.upperBound)
        }
        self.reduceMotion = reduceMotion
        self.isEnabled = isEnabled
    }

    // MARK: - 形體曲線

    public func curve(_ phase: Phase) -> NotchMotionCurve {
        guard isEnabled else { return .instant }
        if reduceMotion { return .easeInOut(duration: Constants.reducedDuration / speed) }
        switch phase {
        case .open:
            return .spring(Spring(response: Constants.openResponse / speed, dampingRatio: Constants.openDampingRatio))
        case .close:
            return .spring(Spring(response: Constants.closeResponse / speed, dampingRatio: Constants.closeDampingRatio))
        case .tabSwitch:
            return .spring(Spring(response: Constants.tabSwitchResponse / speed, dampingRatio: Constants.tabSwitchDampingRatio))
        case .anticipate:
            return .spring(Spring(response: Constants.anticipateResponse / speed, dampingRatio: Constants.anticipateDampingRatio))
        }
    }

    public func animation(_ phase: Phase) -> Animation {
        let curve = curve(phase)
        // hover 預期動作用 interactiveSpring：游標快速進出時能無縫接手上一段動畫的速度。
        if phase == .anticipate, case .spring(let spring) = curve {
            return .interactiveSpring(response: spring.response, dampingFraction: spring.dampingRatio, blendDuration: 0.25)
        }
        return curve.animation
    }

    /// 游標進入觸發區（尚未展開）時，閉合瀏海鼓起的倍率。
    public var anticipationScale: CGFloat {
        guard isEnabled, !reduceMotion else { return 1 }
        return Constants.anticipationScale
    }

    // MARK: - 內容層

    /// 展開時內容層延遲多久才開始淡入。
    public var contentRevealDelay: TimeInterval {
        guard isEnabled, !reduceMotion else { return 0 }
        return Constants.contentRevealDelay / speed
    }

    public var contentRevealCurve: NotchMotionCurve {
        guard isEnabled else { return .instant }
        if reduceMotion { return .easeInOut(duration: Constants.reducedDuration / speed) }
        // 臨界阻尼：內容不過衝，只是平順地淡入。
        return .spring(Spring(response: Constants.contentRevealResponse / speed, dampingRatio: 1))
    }

    public var contentHideCurve: NotchMotionCurve {
        guard isEnabled else { return .instant }
        if reduceMotion { return .easeInOut(duration: Constants.reducedDuration / speed) }
        return .easeOut(duration: Constants.contentHideDuration / speed)
    }

    /// 含延遲的淡入動畫。
    public var contentRevealAnimation: Animation {
        let base = contentRevealCurve.animation
        let delay = contentRevealDelay
        return delay > 0 ? base.delay(delay) : base
    }

    public var contentHideAnimation: Animation { contentHideCurve.animation }

    /// 內容層「隱藏」時的外觀（淡入的起點、淡出的終點）。
    public var hiddenContentStyle: ContentStyle {
        guard isEnabled else { return .shown }
        if reduceMotion { return ContentStyle(opacity: 0, blur: 0, scale: 1, offsetY: 0) }
        return ContentStyle(
            opacity: 0,
            blur: Constants.hiddenBlur,
            scale: Constants.hiddenScale,
            offsetY: Constants.hiddenOffsetY
        )
    }

    /// 狀態切換後經過 `time` 秒的內容層外觀（`revealing` 為 true＝展開淡入，false＝收合淡出）。
    public func contentStyle(revealing: Bool, at time: TimeInterval) -> ContentStyle {
        let hidden = hiddenContentStyle
        if revealing {
            let delay = contentRevealDelay
            let p = time < delay ? 0 : contentRevealCurve.progress(at: time - delay)
            return .lerp(hidden, .shown, p)
        } else {
            let p = contentHideCurve.progress(at: time)
            return .lerp(hidden, .shown, 1 - p)
        }
    }

    // MARK: - 穩定時間

    public func settleTime(for phase: Phase) -> TimeInterval {
        curve(phase).settlingTime
    }

    /// 展開從開始到形體與內容都穩定的時間。
    public var openSettleTime: TimeInterval {
        max(settleTime(for: .open), contentRevealDelay + contentRevealCurve.settlingTime)
    }

    /// 收合從開始到形體與內容都穩定的時間。
    public var closeSettleTime: TimeInterval {
        max(settleTime(for: .close), contentHideCurve.settlingTime)
    }
}
