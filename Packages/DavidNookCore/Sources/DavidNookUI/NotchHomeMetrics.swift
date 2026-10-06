import CoreGraphics
import DavidNookCore
import Foundation

/// Home 分頁（Now Playing＋歌詞）在給定內容尺寸下的版面度量（純邏輯，App 與離屏渲染共用）。
///
/// 規則：
/// - 封面為正方形，高度不超過內容區（上下各留 `artPadding`），最大 144；寬度不夠時優先縮封面，
///   保證控制區 ≥ `controlsMinimumWidth`（放得下 5 顆按鈕的工具列）與歌詞 ≥ `lyricsMinimumWidth`。
/// - 歌詞寬 ≈ 內容寬的 38%（夾在 190–320）；可見行數依內容高度決定（預設高度 5 行，高度不足降為 4 行，再不足 3 行）。
/// - 控制區高度預算：標準 112（資訊 32＋滑桿 32＋播放鈕 40＋間距 2×4），精簡 98（資訊 32＋滑桿 30＋播放鈕 30＋間距 2×3）；
///   內容區 ≥ 116 用標準，否則精簡。內容區下限 `NotchSizing.minimumBodyHeight`（100）保證精簡版放得下。
public struct NotchHomeMetrics: Equatable, Sendable {
    public enum Density: Sendable {
        case regular
        case compact
    }

    // MARK: - 常數

    public static let spacing: CGFloat = 12
    public static let controlsMinimumWidth: CGFloat = 184
    public static let lyricsMinimumWidth: CGFloat = 190
    public static let lyricsMaximumWidth: CGFloat = 320
    public static let lyricsWidthFraction: CGFloat = 0.38
    public static let artMaximumSize: CGFloat = 144
    public static let artPadding: CGFloat = 3
    /// 控制區裡歌名歌手與進度條相對左緣的內縮（與舊版相同）。
    public static let controlsLeadingInset: CGFloat = 5

    /// 控制區各塊高度（資訊＝歌名＋歌手；滑桿＝進度條＋時間）。
    public static let infoHeight: CGFloat = 32
    public static let regularSliderHeight: CGFloat = 32
    public static let compactSliderHeight: CGFloat = 30
    /// 控制區各塊之間的最小間距（標準／精簡）。
    public static let regularMinimumGap: CGFloat = 4
    public static let compactMinimumGap: CGFloat = 3
    public static let regularPrimaryButtonSize: CGFloat = 40
    public static let compactPrimaryButtonSize: CGFloat = 30
    public static let regularControlsHeight: CGFloat = 112
    public static let compactControlsHeight: CGFloat = 98

    // MARK: - 輸入

    public let contentWidth: CGFloat
    public let bodyHeight: CGFloat
    public let showsLyrics: Bool

    // MARK: - 結果

    public let density: Density
    /// 封面槽高度（也是沒有影片時的邊長）。
    public let artSize: CGFloat
    /// 封面槽寬度：沒有影片＝`artSize`；有橫向影片時加寬（見 init），但整排仍不超過內容寬、控制區與歌詞不低於最小寬。
    public let artWidth: CGFloat
    public let lyricsVisibleLines: Int
    public let lyricsHeight: CGFloat
    public let lyricsWidth: CGFloat
    public let controlsWidth: CGFloat

    public var artPadding: CGFloat { Self.artPadding }
    public var spacing: CGFloat { Self.spacing }
    public var artBlockSize: CGFloat { artSize + 2 * Self.artPadding }
    public var artBlockWidth: CGFloat { artWidth + 2 * Self.artPadding }
    public var primaryButtonSize: CGFloat {
        density == .regular ? Self.regularPrimaryButtonSize : Self.compactPrimaryButtonSize
    }
    public var sliderHeight: CGFloat {
        density == .regular ? Self.regularSliderHeight : Self.compactSliderHeight
    }
    public var minimumGap: CGFloat {
        density == .regular ? Self.regularMinimumGap : Self.compactMinimumGap
    }

    /// 封面區塊＋控制區＋歌詞（含各自間距）的水平總長；一律 ≤ `contentWidth`。
    public var horizontalExtent: CGFloat {
        artBlockWidth + Self.spacing + controlsWidth + (showsLyrics ? Self.spacing + lyricsWidth : 0)
    }

    public var controlsMinimumHeight: CGFloat {
        density == .regular ? Self.regularControlsHeight : Self.compactControlsHeight
    }

    /// - Parameters:
    ///   - artAspectRatio: 封面槽正在顯示的影片長寬比（寬 ÷ 高）；nil＝顯示專輯封面（方形）。橫向（> 1）才加寬，直向維持方形。
    ///   - videoMaximumWidth: 設定頁的影片寬度（夾在 160…480）；槽加寬後的寬度上限。
    public init(
        contentWidth: CGFloat, bodyHeight: CGFloat, showsLyrics: Bool,
        artAspectRatio: Double? = nil, videoMaximumWidth: Double = VideoCapsuleSettings.defaultWidth
    ) {
        self.contentWidth = contentWidth
        self.bodyHeight = bodyHeight
        self.showsLyrics = showsLyrics

        density = bodyHeight >= Self.regularControlsHeight + 4 ? .regular : .compact

        let lyricsReserve = showsLyrics ? Self.spacing + Self.lyricsMinimumWidth : 0
        let heightLimit = bodyHeight - 2 * Self.artPadding
        let widthLimit = contentWidth - Self.spacing - Self.controlsMinimumWidth - lyricsReserve - 2 * Self.artPadding
        let art = max(0, min(heightLimit, Self.artMaximumSize, widthLimit)).rounded(.down)
        artSize = art

        // 橫向影片：槽寬 = 高 × 長寬比，上限是 min(版面容許寬、設定寬度)；版面容許寬已保留控制區與歌詞的最小寬，所以不會擠壞它們。
        var width = art
        if let ratio = artAspectRatio {
            let r = CGFloat(VideoCapsuleMetrics.clampedAspectRatio(ratio))
            let cap = max(art, min(widthLimit, CGFloat(VideoCapsuleSettings.clampedWidth(videoMaximumWidth))))
            width = min(max((art * r).rounded(.down), art), cap)
        }
        artWidth = width

        let artBlock = width + 2 * Self.artPadding
        let lines = LyricsPanelMetrics.visibleLines(forAvailableHeight: bodyHeight)
        lyricsVisibleLines = lines
        if showsLyrics {
            let room = contentWidth - artBlock - 2 * Self.spacing - Self.controlsMinimumWidth
            let preferred = min(Self.lyricsMaximumWidth, (Self.lyricsWidthFraction * contentWidth).rounded())
            lyricsWidth = min(max(Self.lyricsMinimumWidth, preferred), room)
            lyricsHeight = LyricsPanelMetrics.height(forVisibleLines: lines)
            controlsWidth = contentWidth - artBlock - 2 * Self.spacing - lyricsWidth
        } else {
            lyricsWidth = 0
            lyricsHeight = 0
            controlsWidth = contentWidth - artBlock - Self.spacing
        }
    }
}
