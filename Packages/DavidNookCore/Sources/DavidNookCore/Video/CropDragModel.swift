import Foundation

/// 正規化座標（0…1，左上為原點）上的一個點。
public struct CropPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
    var isFinite: Bool { x.isFinite && y.isFinite }
}

public enum CropHandle: Equatable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
}

public enum CropDragKind: Equatable, Sendable {
    /// 在框外按下：拖出新框。
    case create
    /// 在框內按下：移動整個框。
    case move
    /// 在邊角或邊緣按下：縮放。
    case resize(CropHandle)
}

public struct CropDragSession: Equatable, Sendable {
    public var kind: CropDragKind
    public var start: CropPoint
    /// 按下當時的框（沒有框為 nil）。
    public var original: NormalizedCropRect?
}

/// 裁切視窗的拖曳邏輯（純函式；視圖只負責把滑鼠座標換成 0…1 再呼叫這裡）。
/// 所有結果都夾在視窗內、邊長不小於 `NormalizedCropRect.minimumSide`，縮放不會翻轉。
public enum CropDragModel {
    /// 邊角／邊緣的命中容差（正規化）。
    public static let handleTolerance = 0.03

    public static func begin(at point: CropPoint, current: NormalizedCropRect?) -> CropDragSession {
        guard let current, point.isFinite else { return CropDragSession(kind: .create, start: point, original: nil) }
        let r = current.sanitized
        let l = r.x, t = r.y, rt = r.x + r.width, b = r.y + r.height
        let tol = handleTolerance
        let nearL = abs(point.x - l) <= tol, nearR = abs(point.x - rt) <= tol
        let nearT = abs(point.y - t) <= tol, nearB = abs(point.y - b) <= tol
        let withinX = point.x >= l - tol && point.x <= rt + tol
        let withinY = point.y >= t - tol && point.y <= b + tol
        let kind: CropDragKind
        if nearL && nearT { kind = .resize(.topLeft) }
        else if nearR && nearT { kind = .resize(.topRight) }
        else if nearL && nearB { kind = .resize(.bottomLeft) }
        else if nearR && nearB { kind = .resize(.bottomRight) }
        else if nearT && withinX { kind = .resize(.top) }
        else if nearB && withinX { kind = .resize(.bottom) }
        else if nearL && withinY { kind = .resize(.left) }
        else if nearR && withinY { kind = .resize(.right) }
        else if point.x > l, point.x < rt, point.y > t, point.y < b { kind = .move }
        else { kind = .create }
        return CropDragSession(kind: kind, start: point, original: kind == .create ? nil : r)
    }

    public static func update(_ session: CropDragSession, to point: CropPoint) -> NormalizedCropRect {
        guard point.isFinite else { return session.original ?? .full }
        let minSide = NormalizedCropRect.minimumSide
        func clamp01(_ v: Double) -> Double { min(max(v, 0), 1) }
        let px = clamp01(point.x), py = clamp01(point.y)

        switch session.kind {
        case .create:
            let sx = clamp01(session.start.x), sy = clamp01(session.start.y)
            let w = max(abs(px - sx), minSide), h = max(abs(py - sy), minSide)
            return NormalizedCropRect(x: min(px, sx), y: min(py, sy), width: w, height: h).sanitized
        case .move:
            guard let o = session.original else { return .full }
            let dx = point.x - session.start.x, dy = point.y - session.start.y
            return NormalizedCropRect(x: o.x + dx, y: o.y + dy, width: o.width, height: o.height).sanitized
        case .resize(let handle):
            guard let o = session.original else { return .full }
            var l = o.x, t = o.y, r = o.x + o.width, b = o.y + o.height
            switch handle {
            case .topLeft: l = min(px, r - minSide); t = min(py, b - minSide)
            case .top: t = min(py, b - minSide)
            case .topRight: r = max(px, l + minSide); t = min(py, b - minSide)
            case .right: r = max(px, l + minSide)
            case .bottomRight: r = max(px, l + minSide); b = max(py, t + minSide)
            case .bottom: b = max(py, t + minSide)
            case .bottomLeft: l = min(px, r - minSide); b = max(py, t + minSide)
            case .left: l = min(px, r - minSide)
            }
            return NormalizedCropRect(x: l, y: t, width: r - l, height: b - t).sanitized
        }
    }
}
