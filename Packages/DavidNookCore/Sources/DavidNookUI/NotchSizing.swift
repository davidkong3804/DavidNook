import CoreGraphics
import Foundation

/// 展開瀏海的尺寸模型（純邏輯）：每個分頁的預設尺寸、使用者的寬／高係數、夾限，以及視窗要涵蓋的範圍。
///
/// 「尺寸」一律指形體外框（含上緣兩側各 `earInset` 的圓角「耳朵」與上方瀏海高度區），與舊版的 `openNotchSize`（640×190）同義：
/// 內容寬 = 寬 − 2 × (耳朵 + `contentSideInset`)；內容高（`bodyHeight`）= 高 − 表頭高度 − `bottomInset`。
///
/// 預設值的取捨（相對舊版 640×190）：
/// - 寬 720：多出 80 pt，Now Playing 的控制區與歌詞面板有餘裕，剪貼簿列也有空間顯示來源 App。
/// - Home 高 176：舊版內容自然高度約 188；扣掉表頭 38 與底部 12 後內容區 126，剛好放得下 120 pt 的封面與 5 行歌詞（124 pt）。
/// - 剪貼簿高 232：內容區 182 = 搜尋列 26 + 間距 6 + 4 列（每列 36 + 間距 2）整整 150，不會把第 4 列切掉一半。
public struct NotchSizing: Equatable, Sendable {
    public enum Panel: CaseIterable, Sendable {
        case home
        case clipboard
    }

    // MARK: - 可調範圍與預設

    /// 設定頁「展開寬度」滑桿：560–900，步進 10，預設 720。
    public static let widthRange: ClosedRange<CGFloat> = 560...900
    public static let widthStep: CGFloat = 10
    public static let defaultWidth: CGFloat = 720
    /// 設定頁「展開高度」滑桿：85%–130%（步進 5%），預設 100%。
    public static let heightScaleRange: ClosedRange<CGFloat> = 0.85...1.30
    public static let heightScaleStep: CGFloat = 0.05
    public static let defaultHeightScale: CGFloat = 1.0

    // MARK: - 各分頁基準高度（係數 1.0）

    public static let homeBaseHeight: CGFloat = 176
    public static let clipboardBaseHeight: CGFloat = 232

    // MARK: - 版面骨架

    /// 表頭（分頁列＋瀏海缺口）的最小高度。
    public static let minimumHeaderHeight: CGFloat = 38
    /// 內容區的最小高度：Home 在這個高度仍放得下 4 行歌詞與精簡控制區。
    public static let minimumBodyHeight: CGFloat = 100
    /// 形體底部到內容區的內縮。
    public static let bottomInset: CGFloat = 12
    /// 圓角耳朵到內容區之間的內縮（每側）。
    public static let contentSideInset: CGFloat = 12

    // MARK: - 視窗

    /// 形體外的陰影空間。
    public static let shadowPadding: CGFloat = 20
    /// 彈簧過衝時形體會暫時比目標大一點；視窗每側（寬）／下方（高）多留的空間。
    /// 實際過衝上限見測試 `testOpenWindowAlsoCoversTheSpringOvershootAndShadow`。
    public static let overshootMargin: CGFloat = 24
    /// 關閉狀態的視窗大小：與舊版 `windowSize`（640×(190+20)）相同，所以關閉時的點擊／hover 行為與改版前一致。
    public static let legacyClosedWindowSize = CGSize(width: 640, height: 210)

    // MARK: - 使用者係數

    public let width: CGFloat
    public let heightScale: CGFloat

    /// 輸入會被夾到可調範圍；非數值回到預設。
    public init(width: Double = Double(NotchSizing.defaultWidth), heightScale: Double = Double(NotchSizing.defaultHeightScale)) {
        self.width = width.isNaN
            ? Self.defaultWidth
            : min(max(CGFloat(width), Self.widthRange.lowerBound), Self.widthRange.upperBound)
        self.heightScale = heightScale.isNaN
            ? Self.defaultHeightScale
            : min(max(CGFloat(heightScale), Self.heightScaleRange.lowerBound), Self.heightScaleRange.upperBound)
    }

    /// 是否等於預設值（高度係數容許滑桿步進造成的浮點誤差）。
    public var isDefault: Bool {
        width == Self.defaultWidth && abs(heightScale - Self.defaultHeightScale) < 0.001
    }

    /// 把任意寬度吸附到滑桿步進（並夾到範圍）。
    public static func snappedWidth(_ value: Double) -> CGFloat {
        guard !value.isNaN else { return defaultWidth }
        let lower = Double(widthRange.lowerBound)
        let step = Double(widthStep)
        let snapped = lower + ((value - lower) / step).rounded() * step
        return min(max(CGFloat(snapped), widthRange.lowerBound), widthRange.upperBound)
    }

    // MARK: - 尺寸

    private static func baseHeight(for panel: Panel) -> CGFloat {
        switch panel {
        case .home: return homeBaseHeight
        case .clipboard: return clipboardBaseHeight
        }
    }

    /// 分頁的展開尺寸（整點）。表頭比預設高（自訂瀏海高度）時，高度會跟著加高，內容區不會被壓到 `minimumBodyHeight` 以下。
    public func openSize(for panel: Panel, headerHeight: CGFloat = NotchSizing.minimumHeaderHeight) -> CGSize {
        let scaled = (Self.baseHeight(for: panel) * heightScale).rounded()
        let floorHeight = headerHeight + Self.minimumBodyHeight + Self.bottomInset
        return CGSize(width: width, height: max(scaled, floorHeight))
    }

    /// 內容區（表頭之下、底部內縮之上）的高度。
    public func bodyHeight(for panel: Panel, headerHeight: CGFloat = NotchSizing.minimumHeaderHeight) -> CGFloat {
        openSize(for: panel, headerHeight: headerHeight).height - headerHeight - Self.bottomInset
    }

    /// 內容寬（形體寬扣掉兩側的耳朵與內縮）。
    public func contentWidth(earInset: CGFloat) -> CGFloat {
        width - 2 * (earInset + Self.contentSideInset)
    }

    /// 所有可調上限下最大的展開尺寸（寬 900；高為剪貼簿 × 130%）。
    public static var maximumOpenSize: CGSize {
        let sizing = NotchSizing(width: Double(widthRange.upperBound), heightScale: Double(heightScaleRange.upperBound))
        let height = Panel.allCases.map { sizing.openSize(for: $0).height }.max() ?? 0
        return CGSize(width: widthRange.upperBound, height: height)
    }

    // MARK: - 視窗大小

    /// 展開時的視窗：涵蓋所有分頁、所有可調上限、彈簧過衝與陰影；因此調整寬高滑桿或切換分頁都不必改視窗大小。
    public static var coveringWindowSize: CGSize {
        let maximum = maximumOpenSize
        return CGSize(
            width: maximum.width + 2 * overshootMargin,
            height: maximum.height + overshootMargin + shadowPadding
        )
    }

    /// 視窗大小：關閉＝舊版大小（不新增任何可能遮擋點擊的區域），展開＝涵蓋尺寸。
    public static func windowSize(isOpen: Bool) -> CGSize {
        isOpen ? coveringWindowSize : legacyClosedWindowSize
    }

    /// 改變視窗大小時保持「頂端置中」不動（AppKit 座標：y 向上，所以固定 maxY 與 midX）。
    public static func anchoredFrame(from frame: CGRect, to size: CGSize) -> CGRect {
        CGRect(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}
