import CoreGraphics
import Foundation

/// 浮動視窗記住的位置與寬度（螢幕座標，AppKit 座標系：原點左下、y 向上）。
/// 隱私：只有三個數字，不含任何視窗標題或畫面內容。高度永遠由寬度與目前畫面比例推出，所以不存。
public struct FloatingVideoPlacement: Codable, Equatable, Sendable {
    public static let defaultsKey = "videoFloatingPlacement"

    public var x: Double
    public var y: Double
    public var width: Double

    public init(x: Double, y: Double, width: Double) {
        self.x = x; self.y = y; self.width = width
    }

    public init(frame: CGRect) {
        self.init(x: Double(frame.minX), y: Double(frame.minY), width: Double(frame.width))
    }
}

/// 浮動視窗透明度（0.4…1.0）。
public enum FloatingVideoOpacity {
    public static let defaultsKey = "videoFloatingOpacity"
    public static let range: ClosedRange<Double> = 0.4...1.0
    public static let defaultValue: Double = 1.0
    /// 點一下循環的刻度（由不透明到最透明，再回到不透明）。
    public static let steps: [Double] = [1.0, 0.8, 0.6, 0.4]

    public static func clamped(_ value: Double) -> Double {
        guard !value.isNaN else { return defaultValue }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    /// 下一格：先靠到最近的刻度，再往下一格（最後一格回到 1.0）。
    public static func next(after value: Double) -> Double {
        let v = clamped(value)
        let index = steps.indices.min { abs(steps[$0] - v) < abs(steps[$1] - v) } ?? 0
        return steps[(index + 1) % steps.count]
    }
}

/// 四角（AppKit 座標：top＝y 較大）。
public enum FloatingVideoCorner: Equatable, Sendable, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
}

/// 浮動視窗的幾何（純函式；視窗與螢幕範圍都用 AppKit 螢幕座標，螢幕範圍＝`NSScreen.visibleFrame`）。
public enum FloatingVideoGeometry {
    public static let minimumWidth: Double = 160
    public static let defaultWidth: Double = 320
    /// 第一次出現時，視窗上緣離螢幕可視範圍上緣（瀏海／選單列下緣）的距離。
    public static let topMargin: Double = 6
    /// 視窗比例（寬÷高）夾在 1:4…4:1，避免極端來源讓視窗變成細線。
    public static let aspectRatioRange: ClosedRange<Double> = 0.25...4.0
    static let fallbackAspectRatio: Double = 16.0 / 9.0

    static func sanitized(ratio: Double) -> Double {
        guard ratio.isFinite, ratio > 0 else { return fallbackAspectRatio }
        return min(max(ratio, aspectRatioRange.lowerBound), aspectRatioRange.upperBound)
    }

    /// 夾限後的視窗大小：寬在「最小寬…螢幕可容納的最大寬」之間，高由比例決定且不超過螢幕。
    /// 螢幕本身比最小寬還小時，以螢幕為準（不超出螢幕）。
    public static func clampedSize(width: Double, aspectRatio: Double, in visible: CGRect) -> CGSize {
        let ratio = sanitized(ratio: aspectRatio)
        var w = width.isNaN ? defaultWidth : width
        var upper = Double.greatestFiniteMagnitude
        if visible.width > 0, visible.height > 0 {
            upper = min(Double(visible.width), Double(visible.height) * ratio)
        }
        let lower = min(minimumWidth, upper)
        w = min(max(w, lower), upper)
        return CGSize(width: w, height: w / ratio)
    }

    /// 拖四角縮放：對角固定，大小取「指標到對角的水平距離」與「垂直距離換算的寬」中較大者，鎖定長寬比；
    /// 拖過對角不翻轉（取最小寬）；結果夾在最小寬…螢幕範圍。
    public static func resize(frame: CGRect, corner: FloatingVideoCorner, pointer: CGPoint, aspectRatio: Double, in visible: CGRect) -> CGRect {
        let ratio = sanitized(ratio: aspectRatio)
        let anchor: CGPoint
        let dx: CGFloat
        let dy: CGFloat
        switch corner {
        case .bottomRight:
            anchor = CGPoint(x: frame.minX, y: frame.maxY); dx = pointer.x - anchor.x; dy = anchor.y - pointer.y
        case .topLeft:
            anchor = CGPoint(x: frame.maxX, y: frame.minY); dx = anchor.x - pointer.x; dy = pointer.y - anchor.y
        case .topRight:
            anchor = CGPoint(x: frame.minX, y: frame.minY); dx = pointer.x - anchor.x; dy = pointer.y - anchor.y
        case .bottomLeft:
            anchor = CGPoint(x: frame.maxX, y: frame.maxY); dx = anchor.x - pointer.x; dy = anchor.y - pointer.y
        }
        let proposed = max(Double(dx), Double(dy) * ratio, 0)
        let size = clampedSize(width: proposed, aspectRatio: ratio, in: visible)
        let w = CGFloat(size.width), h = CGFloat(size.height)
        let x: CGFloat
        let y: CGFloat
        switch corner {
        case .bottomRight: x = anchor.x; y = anchor.y - h
        case .topLeft: x = anchor.x - w; y = anchor.y
        case .topRight: x = anchor.x; y = anchor.y
        case .bottomLeft: x = anchor.x - w; y = anchor.y - h
        }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// 來源畫面比例改變（裁切、來源視窗被縮放）：寬度不變、左上角不動，高度跟著比例變，再推回螢幕內。
    public static func adjustedForAspect(frame: CGRect, aspectRatio: Double, in visible: CGRect) -> CGRect {
        let size = clampedSize(width: Double(frame.width), aspectRatio: aspectRatio, in: visible)
        let rect = CGRect(x: frame.minX, y: frame.maxY - CGFloat(size.height), width: CGFloat(size.width), height: CGFloat(size.height))
        return nudgedInside(rect, in: visible)
    }

    /// 平移到完全落在螢幕範圍內（比螢幕大時靠左下對齊）。
    public static func nudgedInside(_ rect: CGRect, in visible: CGRect) -> CGRect {
        let x = max(min(rect.minX, visible.maxX - rect.width), visible.minX)
        let y = max(min(rect.minY, visible.maxY - rect.height), visible.minY)
        return CGRect(x: x, y: y, width: rect.width, height: rect.height)
    }

    /// 釘選時的位置：記住的位置的中心還在某個螢幕範圍內 → 沿用（夾限大小並推回螢幕內）；
    /// 否則（第一次、螢幕被拔掉、解析度改變）→ 瀏海正下方置中（寬度沿用記住的，沒有就用 `defaultWidth`＝設定頁的預設大小）。
    public static func restoredFrame(
        saved: FloatingVideoPlacement?, aspectRatio: Double, screens: [CGRect], primary: CGRect, defaultWidth: Double = FloatingVideoGeometry.defaultWidth
    ) -> CGRect {
        let ratio = sanitized(ratio: aspectRatio)
        if let saved, saved.width.isFinite, saved.x.isFinite, saved.y.isFinite, saved.width > 0 {
            let center = CGPoint(x: saved.x + saved.width / 2, y: saved.y + saved.width / ratio / 2)
            if let screen = screens.first(where: { $0.contains(center) }) {
                let size = clampedSize(width: saved.width, aspectRatio: ratio, in: screen)
                return nudgedInside(CGRect(x: saved.x, y: saved.y, width: size.width, height: size.height), in: screen)
            }
        }
        let width = saved.flatMap { $0.width.isFinite && $0.width > 0 ? $0.width : nil } ?? defaultWidth
        let size = clampedSize(width: width, aspectRatio: ratio, in: primary)
        let rect = CGRect(
            x: primary.midX - size.width / 2, y: primary.maxY - topMargin - size.height, width: size.width, height: size.height
        )
        return nudgedInside(rect, in: primary)
    }
}
