import CoreGraphics
import Foundation

/// 相對來源視窗的正規化裁切矩形：每個值在 0…1，原點在視窗**左上角**、y 向下（與 SwiftUI／視窗座標一致）。
/// 以比例儲存，視窗大小改變（或下次重新挑選同一個 App 的視窗）時仍大致對得上。
public struct NormalizedCropRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    /// 任一邊的最小比例（避免框到幾乎沒有東西）。
    public static let minimumSide: Double = 0.05
    public static let full = NormalizedCropRect(x: 0, y: 0, width: 1, height: 1)

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    private var isFinite: Bool { x.isFinite && y.isFinite && width.isFinite && height.isFinite }

    /// 夾回合法範圍：非數值＝整個視窗；寬高夾在 `minimumSide…1`；位置夾到框完全在視窗內。
    public var sanitized: NormalizedCropRect {
        guard isFinite else { return .full }
        let w = min(max(width, Self.minimumSide), 1)
        let h = min(max(height, Self.minimumSide), 1)
        return NormalizedCropRect(x: min(max(x, 0), 1 - w), y: min(max(y, 0), 1 - h), width: w, height: h)
    }

    /// 幾乎整個視窗（寬、高 ≥ 0.99）＝沒有裁切。
    public var isFullWindow: Bool {
        let s = sanitized
        return s.width >= 0.99 && s.height >= 0.99
    }

    /// 裁切後輸出畫面的長寬比（寬 ÷ 高）；視窗尺寸無效回傳 nil。
    public func aspectRatio(windowSize: CGSize) -> Double? {
        guard windowSize.width.isFinite, windowSize.height.isFinite, windowSize.width > 0, windowSize.height > 0 else { return nil }
        let s = sanitized
        return (s.width * Double(windowSize.width)) / (s.height * Double(windowSize.height))
    }

    /// 給 `SCStreamConfiguration.sourceRect` 的矩形：單位 pt（視窗的邏輯座標），視窗擷取時相對視窗。
    /// SDK 標頭（SCStream.h）只寫「in points in the display's logical coordinate system；視窗串流不設則串整個視窗」，
    /// **未明說原點**；這裡採「視窗左上為原點、y 向下」，需真機驗證（見設計文件）。
    public func sourceRect(in windowSize: CGSize) -> CGRect {
        let s = sanitized
        let w = Double(windowSize.width), h = Double(windowSize.height)
        return CGRect(x: s.x * w, y: s.y * h, width: s.width * w, height: s.height * h)
    }

    // MARK: 儲存形式

    public var asArray: [Double] { [x, y, width, height] }

    public init?(array: [Double]) {
        guard array.count == 4, array.allSatisfy({ $0.isFinite }) else { return nil }
        self.init(x: array[0], y: array[1], width: array[2], height: array[3])
    }
}
