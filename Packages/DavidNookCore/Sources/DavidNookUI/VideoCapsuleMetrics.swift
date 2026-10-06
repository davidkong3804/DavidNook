import CoreGraphics
import DavidNookCore
import Foundation

/// 展開瀏海「影片」分頁的尺寸與版面夾限（純邏輯）。
///
/// **硬限制**：視窗已固定為涵蓋尺寸（見 `NotchSizing.coveringWindowSize`），影片區塊與面板形體只在其中畫；
/// 這裡只算尺寸，絕不碰 NSWindow（動畫期間 setFrame 會讓 NSHostingView 版面更新迴圈而閃退，見 git log c30828f）。
public enum VideoCapsuleMetrics {
    // MARK: 範圍與預設

    public static let widthRange: ClosedRange<Double> = VideoCapsuleSettings.widthRange
    public static let defaultWidth: Double = VideoCapsuleSettings.defaultWidth
    /// 來源長寬比（寬 ÷ 高）夾在 1:2 … 2:1；異常值（NaN、≤ 0）當 16:9。
    public static let aspectRatioRange: ClosedRange<Double> = 0.5...2
    public static let fallbackAspectRatio: Double = 16.0 / 9.0
    /// 影片區塊最小寬（pt）。
    public static let minimumWidth: CGFloat = 96
    /// 右側工具列（換視窗、停止、釘選、寬度滑桿）的寬度與它跟影片的間距。
    public static let controlsWidth: CGFloat = 132
    public static let controlsSpacing: CGFloat = 12

    /// 影片區塊最大高度：放得進「最高的面板」（所有可調上限下的最大形體高 − 最小表頭 − 底部內縮）。
    public static var maximumHeight: CGFloat {
        NotchSizing.maximumOpenSize.height - NotchSizing.minimumHeaderHeight - NotchSizing.bottomInset
    }

    // MARK: 夾限

    public static func clampedAspectRatio(_ ratio: Double) -> Double {
        guard !ratio.isNaN, ratio > 0 else { return fallbackAspectRatio }
        return min(max(ratio, aspectRatioRange.lowerBound), aspectRatioRange.upperBound)
    }

    /// 依使用者的寬度（夾在 160…480）與來源長寬比算出的期望尺寸；高度超過 `maximumHeight` 就等比縮小。
    public static func requestedSize(width: Double, aspectRatio: Double) -> CGSize {
        let ratio = CGFloat(clampedAspectRatio(aspectRatio))
        var w = CGFloat(VideoCapsuleSettings.clampedWidth(width))
        var h = w / ratio
        if h > maximumHeight {
            h = maximumHeight
            w = h * ratio
        }
        if w < minimumWidth {
            w = minimumWidth
            h = w / ratio
        }
        return CGSize(width: w, height: h)
    }

    /// 等比縮小到放得進 `available`（不放大）；可用空間無效回傳 `.zero`。
    public static func fit(_ size: CGSize, into available: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0, available.width > 0, available.height > 0 else { return .zero }
        let scale = min(1, available.width / size.width, available.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    // MARK: 展開面板內的版面

    public struct Layout: Equatable, Sendable {
        /// 影片區塊（等比、已夾限）。
        public var videoSize: CGSize
        /// 影片可用的寬度（內容寬扣掉右側工具列與間距）。
        public var availableWidth: CGFloat
        /// 面板內容區高度。
        public var bodyHeight: CGFloat
        /// 面板形體尺寸（會隨影片加高，但不超過涵蓋視窗內的最大面板）。
        public var panelSize: CGSize
    }

    public static func layout(
        width: Double, aspectRatio: Double, sizing: NotchSizing, headerHeight: CGFloat, earInset: CGFloat
    ) -> Layout {
        let requested = requestedSize(width: width, aspectRatio: aspectRatio)
        let panel = sizing.openSize(for: .video, headerHeight: headerHeight, videoContentHeight: requested.height)
        let body = panel.height - headerHeight - NotchSizing.bottomInset
        let availableWidth = max(sizing.contentWidth(earInset: earInset) - controlsWidth - controlsSpacing, 0)
        let video = fit(requested, into: CGSize(width: availableWidth, height: body))
        return Layout(videoSize: video, availableWidth: availableWidth, bodyHeight: body, panelSize: panel)
    }
}
