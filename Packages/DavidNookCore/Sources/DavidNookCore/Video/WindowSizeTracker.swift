import CoreGraphics
import Foundation

/// 來源視窗大小（點）的追蹤（純邏輯）。
///
/// SCStream 每幀附帶的 contentRect 是「輸出畫面裡的內容」，單位與視窗的點數不同（隨輸出像素尺寸、scale 而變）。
/// 把它直接當視窗大小，會把 480、1200 之類的輸出尺寸當成點數，之後裁切（sourceRect＝正規化矩形 × 視窗大小）就會取錯區域。
/// 做法：以挑選時已知的視窗大小為準；第一個樣本只用來校準單位係數 k（與已知大小相符＝k 為 1），之後 `size = raw × k`，
/// 只有超過 1 pt 的真實縮放才更新。
public struct WindowSizeTracker: Equatable, Sendable {
    public private(set) var size: CGSize
    private var factor: Double?

    public init(initial: CGSize) {
        size = Self.isValid(initial) ? initial : .zero
    }

    /// 以新挑選視窗的已知大小重來（重新校準）。
    public mutating func reset(to known: CGSize) {
        size = Self.isValid(known) ? known : .zero
        factor = nil
    }

    private static func isValid(_ s: CGSize) -> Bool {
        s.width.isFinite && s.height.isFinite && s.width > 0 && s.height > 0
    }

    /// `rawSize`：幀的 contentRect 大小除以 contentScale（無此值就直接傳 contentRect 大小）。回傳視窗大小是否因此改變。
    @discardableResult
    public mutating func ingest(rawSize: CGSize) -> Bool {
        guard Self.isValid(rawSize) else { return false }
        guard size != .zero else {
            size = rawSize; factor = 1
            return true
        }
        if factor == nil {
            let kw = Double(size.width / rawSize.width), kh = Double(size.height / rawSize.height)
            if abs(kw - kh) / kw > 0.05 {
                // 兩邊係數不一致＝形狀不同：這是真的縮放（不是單位差異），直接採用。
                factor = 1
            } else {
                factor = abs(kw - 1) < 0.03 ? 1 : kw
                return false
            }
        }
        let k = CGFloat(factor ?? 1)
        let next = CGSize(width: rawSize.width * k, height: rawSize.height * k)
        guard abs(next.width - size.width) > 1 || abs(next.height - size.height) > 1 else { return false }
        size = next
        return true
    }
}
