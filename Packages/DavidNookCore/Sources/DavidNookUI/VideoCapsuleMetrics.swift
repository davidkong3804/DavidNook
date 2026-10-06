import CoreGraphics
import DavidNookCore
import Foundation

/// 影片來源長寬比與寬度設定的夾限（純邏輯；封面槽加寬與浮動視窗預設大小用）。
///
/// **硬限制**：視窗已固定（收合＝`NotchSizing.legacyClosedWindowSize`、展開＝涵蓋尺寸），影片只在其中畫；
/// 這裡只算尺寸，絕不碰 NSWindow（動畫期間 setFrame 會讓 NSHostingView 版面更新迴圈而閃退，見 git log c30828f）。
public enum VideoCapsuleMetrics {
    public static let widthRange: ClosedRange<Double> = VideoCapsuleSettings.widthRange
    public static let defaultWidth: Double = VideoCapsuleSettings.defaultWidth
    /// 來源長寬比（寬 ÷ 高）夾在 1:2 … 2:1；異常值（NaN、≤ 0）當 16:9。
    public static let aspectRatioRange: ClosedRange<Double> = 0.5...2
    public static let fallbackAspectRatio: Double = 16.0 / 9.0

    public static func clampedAspectRatio(_ ratio: Double) -> Double {
        guard !ratio.isNaN, ratio > 0 else { return fallbackAspectRatio }
        return min(max(ratio, aspectRatioRange.lowerBound), aspectRatioRange.upperBound)
    }
}
