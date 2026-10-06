import CoreGraphics
import Foundation

/// 收合瀏海下方「歌詞膠囊」的尺寸、設定夾限與動畫常數（純邏輯）。
///
/// 膠囊畫在既有的視窗範圍內（收合＝`NotchSizing.legacyClosedWindowSize`、展開＝涵蓋尺寸），**不改視窗大小**
/// （動畫期間 setFrame 會讓 NSHostingView 版面更新迴圈而閃退）。因此「下拉距離」與「最大寬度」都夾在
/// 最壞情況仍落在收合視窗內的範圍，測試 `testWorstCaseStaysInsideTheClosedAndCoveringWindows` 鎖定這點。
public enum LyricsPillMetrics {
    // MARK: 設定範圍與預設

    /// 以瀏海底緣為基準往下的距離（pt）；負值＝往上蓋進瀏海一點。
    public static let dropDistanceRange: ClosedRange<CGFloat> = -8...40
    public static let defaultDropDistance: CGFloat = 6
    public static let maxWidthRange: ClosedRange<CGFloat> = 240...520
    public static let defaultMaxWidth: CGFloat = 360
    public static let fontSizeRange: ClosedRange<CGFloat> = 11...16
    public static let defaultFontSize: CGFloat = 12
    public static let speedRange: ClosedRange<Double> = 0.5...2
    public static let defaultSpeed: Double = 1

    // MARK: 版面

    public static let height: CGFloat = 22
    public static let horizontalPadding: CGFloat = 12
    public static let minimumWidth: CGFloat = 96
    /// 文字兩側的漸層邊緣寬度（捲動時文字滑入／滑出邊緣的柔化）。
    public static let edgeFade: CGFloat = 8
    /// 收合視窗內容底部保留的空間（ContentView 的 `.padding(.bottom, 8)`）。
    public static let windowBottomPadding: CGFloat = 8
    /// 夾限用的最大瀏海底緣假設（真實瀏海高約 32–38，自訂高度滑桿上限更低；留餘裕）。
    public static let maximumAssumedNotchBottom: CGFloat = 60

    // MARK: 夾限

    public static func clampedDropDistance(_ value: CGFloat) -> CGFloat {
        guard !value.isNaN else { return defaultDropDistance }
        return min(max(value, dropDistanceRange.lowerBound), dropDistanceRange.upperBound)
    }

    public static func clampedMaxWidth(_ value: CGFloat) -> CGFloat {
        guard !value.isNaN else { return defaultMaxWidth }
        return min(max(value, maxWidthRange.lowerBound), maxWidthRange.upperBound)
    }

    public static func clampedFontSize(_ value: CGFloat) -> CGFloat {
        guard !value.isNaN else { return defaultFontSize }
        return min(max(value, fontSizeRange.lowerBound), fontSizeRange.upperBound)
    }

    public static func clampedSpeed(_ value: Double) -> Double {
        guard !value.isNaN else { return defaultSpeed }
        return min(max(value, speedRange.lowerBound), speedRange.upperBound)
    }

    // MARK: 尺寸與位置

    /// 膠囊寬：貼合文字寬（加兩側內縮），不小於 `minimumWidth`、不大於（夾限後的）最大寬度。
    public static func pillWidth(textWidth: CGFloat, maxWidth: CGFloat) -> CGFloat {
        let upper = clampedMaxWidth(maxWidth)
        let text = textWidth.isFinite ? max(textWidth, 0) : 0
        return min(max(text + 2 * horizontalPadding, minimumWidth), upper)
    }

    /// 文字可用寬度（跑馬燈的容器寬）。
    public static func textContainerWidth(pillWidth: CGFloat) -> CGFloat {
        max(pillWidth - 2 * horizontalPadding, 0)
    }

    /// 膠囊上緣到視窗上緣的距離：瀏海底緣＋（夾限後的）下拉距離；不會跑到視窗上方。
    public static func topOffset(notchBottom: CGFloat, dropDistance: CGFloat) -> CGFloat {
        max(notchBottom + clampedDropDistance(dropDistance), 0)
    }

    /// 最壞情況（瀏海底緣 60、下拉 40）膠囊底緣離視窗上緣的距離。
    public static var maximumBottomExtent: CGFloat {
        topOffset(notchBottom: maximumAssumedNotchBottom, dropDistance: dropDistanceRange.upperBound) + height
    }

    // MARK: 動畫

    /// 換句動畫：交叉淡入淡出＋微小上移。`offsetY` 是新句子由下方滑入、舊句子往上滑出的距離。
    public struct LineChangeMotion: Equatable, Sendable {
        public var duration: TimeInterval
        public var offsetY: CGFloat
    }

    public static let lineChangeOffsetY: CGFloat = 3

    /// 沿用 `NotchMotion` 的速度倍率、「減少動態」與「關閉動畫」：
    /// 一般＝內容層淡入時間（0.30 s ÷ 速度）＋ 3 pt 位移；減少動態＝0.2 s 純淡入淡出；關閉動畫＝瞬間。
    public static func lineChangeMotion(_ motion: NotchMotion) -> LineChangeMotion {
        guard motion.isEnabled else { return LineChangeMotion(duration: 0, offsetY: 0) }
        if motion.reduceMotion {
            return LineChangeMotion(duration: NotchMotion.Constants.reducedDuration / motion.speed, offsetY: 0)
        }
        return LineChangeMotion(
            duration: NotchMotion.Constants.contentRevealResponse / motion.speed,
            offsetY: lineChangeOffsetY
        )
    }
}
