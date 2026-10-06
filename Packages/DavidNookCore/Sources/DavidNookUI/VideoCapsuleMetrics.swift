import CoreGraphics
import DavidNookCore
import Foundation

/// 影片尺寸的夾限（純邏輯）。
///
/// **硬限制**：視窗已固定（收合＝`NotchSizing.legacyClosedWindowSize`、展開＝涵蓋尺寸），影片只在其中畫；
/// 這裡只算尺寸，絕不碰 NSWindow（動畫期間 setFrame 會讓 NSHostingView 版面更新迴圈而閃退，見 git log c30828f）。
public enum VideoCapsuleMetrics {
    public static let widthRange: ClosedRange<Double> = VideoCapsuleSettings.widthRange
    public static let defaultWidth: Double = VideoCapsuleSettings.defaultWidth
    /// 來源長寬比（寬 ÷ 高）夾在 1:2 … 2:1；異常值（NaN、≤ 0）當 16:9。
    public static let aspectRatioRange: ClosedRange<Double> = 0.5...2
    public static let fallbackAspectRatio: Double = 16.0 / 9.0
    /// 影片最小寬（pt）；縮到比這個小就不顯示。
    public static let minimumWidth: CGFloat = 96
    /// 影片最大高度（pt）：最大寬 480 的 16:9。
    public static let maximumHeight: CGFloat = 270

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

    /// 釘選膠囊的圓角：短邊的 12%，夾在 8…16 pt（短邊的一半以內）。
    public static func cornerRadius(for size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 8 }
        return min(max(min(size.width, size.height) * 0.12, 8), 16)
    }

    /// 等比縮小到放得進 `available`（不放大）；可用空間無效回傳 `.zero`。
    public static func fit(_ size: CGSize, into available: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0, available.width > 0, available.height > 0 else { return .zero }
        let scale = min(1, available.width / size.width, available.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

/// 收合瀏海下方「影片膠囊」與「歌詞膠囊」的垂直堆疊版面（純邏輯；M-C 的視圖直接用）。
///
/// 座標：原點在視窗左上角、y 向下、水平置中。預設歌詞膠囊在上（緊貼瀏海下方、維持現有位置），影片膠囊在其下，間距 6 pt；
/// 歌詞膠囊不顯示時影片膠囊上移到歌詞膠囊的位置。影片可用高度 = 收合視窗高 − 底部內縮 − 上緣 −（歌詞＋間距）；
/// 超過就等比縮小，縮到寬 < `VideoCapsuleMetrics.minimumWidth` 則不顯示（`video` 為 nil），絕不溢出視窗。
public enum VideoCapsuleStack {
    public enum Order: Sendable {
        case lyricsAbove
        case videoAbove
    }

    public static let gap: CGFloat = 6

    public struct Layout: Equatable, Sendable {
        public var video: CGRect?
        public var lyrics: CGRect?
    }

    public static func layout(
        window: CGSize = NotchSizing.legacyClosedWindowSize,
        notchBottom: CGFloat,
        dropDistance: CGFloat,
        lyricsVisible: Bool,
        lyricsWidth: CGFloat,
        videoWidth: Double,
        aspectRatio: Double,
        order: Order = .lyricsAbove
    ) -> Layout {
        let top = LyricsPillMetrics.topOffset(notchBottom: notchBottom.isFinite ? notchBottom : 0, dropDistance: dropDistance)
        let lyricsHeight = LyricsPillMetrics.height
        let lyricsBlock = lyricsVisible ? lyricsHeight + gap : 0
        let availableHeight = window.height - LyricsPillMetrics.windowBottomPadding - top - lyricsBlock
        let requested = VideoCapsuleMetrics.requestedSize(width: videoWidth, aspectRatio: aspectRatio)
        var size = VideoCapsuleMetrics.fit(requested, into: CGSize(width: window.width, height: availableHeight))
        if size.width < VideoCapsuleMetrics.minimumWidth { size = .zero }

        var lyricsRect: CGRect?
        if lyricsVisible {
            let w = min(max(lyricsWidth.isFinite ? lyricsWidth : LyricsPillMetrics.minimumWidth, LyricsPillMetrics.minimumWidth), min(LyricsPillMetrics.maxWidthRange.upperBound, window.width))
            lyricsRect = CGRect(x: (window.width - w) / 2, y: 0, width: w, height: lyricsHeight)
        }
        var videoRect: CGRect?
        if size != .zero {
            videoRect = CGRect(x: (window.width - size.width) / 2, y: 0, width: size.width, height: size.height)
        }

        // 垂直擺放。影片被隱藏時，歌詞回到最上面的位置。
        switch order {
        case .lyricsAbove:
            var y = top
            if lyricsRect != nil { lyricsRect?.origin.y = y; y += lyricsHeight + gap }
            videoRect?.origin.y = y
        case .videoAbove:
            var y = top
            if videoRect != nil { videoRect?.origin.y = y; y += (videoRect?.height ?? 0) + gap }
            lyricsRect?.origin.y = y
        }
        return Layout(video: videoRect, lyrics: lyricsRect)
    }
}

/// 釘選膠囊在收合視窗內的位置（純邏輯）：可見才有矩形；歌詞膠囊可見時在其下方（間距 6），不可見時上移到歌詞位置。
/// 座標原點在視窗左上角、y 向下、水平置中；一律委託 `VideoCapsuleStack.layout`（窮舉測試保證在視窗內且與歌詞不重疊）。
public enum VideoCapsulePlacement {
    public static func rect(
        isVisible: Bool, notchBottom: CGFloat, dropDistance: CGFloat, lyricsVisible: Bool, videoWidth: Double, aspectRatio: Double
    ) -> CGRect? {
        guard isVisible else { return nil }
        return VideoCapsuleStack.layout(
            notchBottom: notchBottom, dropDistance: LyricsPillMetrics.clampedDropDistance(dropDistance), lyricsVisible: lyricsVisible,
            lyricsWidth: LyricsPillMetrics.minimumWidth, videoWidth: videoWidth, aspectRatio: aspectRatio
        ).video
    }
}
