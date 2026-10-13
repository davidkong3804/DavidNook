import CoreGraphics
import Foundation

/// 展開瀏海的「游標離開就收合」看門狗（純邏輯）。
///
/// 原本只靠 SwiftUI `.onHover` 的離開事件：視窗被別的視窗（挑選器、浮動視窗、裁切視窗）蓋住、
/// 視窗隱藏／換螢幕時離開事件會漏掉，`isHovering` 就永遠卡在 true，瀏海再也收不起來。
/// 這裡改成直接比對游標座標與展開瀏海的矩形（定時取樣），不依賴任何事件，漏事件也一定會收。
public struct NotchCloseWatchdog: Equatable, Sendable {
    public enum Decision: Equatable, Sendable {
        case keepOpen
        case close
    }

    /// 游標離開矩形多久（秒）才收合：夠長到不會在往控制鈕移動途中誤收，夠短到使用者不覺得卡。
    public static let graceInterval: TimeInterval = 0.5
    /// 矩形外多留的邊（pt）：游標貼著邊緣、陰影區、彈簧過衝都算在裡面。
    public static let margin: CGFloat = 8

    private var outsideSince: TimeInterval?
    /// 游標進過瀏海才「上膛」：用快捷鍵展開、游標一直在別處時不能被自動收掉（與舊行為一致）。
    private var hasBeenInside = false

    public init() {}

    /// 展開瀏海在螢幕上的矩形（AppKit 座標，y 向上）：貼齊螢幕上緣、水平置中。
    public static func openRect(screenFrame: CGRect, size: CGSize) -> CGRect {
        CGRect(x: screenFrame.midX - size.width / 2, y: screenFrame.maxY - size.height, width: size.width, height: size.height)
    }

    /// - Parameters:
    ///   - holdOpen: 有東西正在使用瀏海（系統挑選器、剪貼簿輸入框…）時為 true，計時歸零。
    ///   - mouseButtonDown: 滑鼠鍵按著（拖曳進度條、選取文字）時不收。
    public mutating func evaluate(
        now: TimeInterval, isOpen: Bool, pointer: CGPoint, notchRect: CGRect, holdOpen: Bool, mouseButtonDown: Bool
    ) -> Decision {
        guard isOpen else {
            outsideSince = nil
            hasBeenInside = false
            return .keepOpen
        }
        let isInside = Self.isInside(pointer, notchRect: notchRect)
        if isInside { hasBeenInside = true }
        guard hasBeenInside, !isInside, !holdOpen, !mouseButtonDown else {
            outsideSince = nil
            return .keepOpen
        }
        let since = outsideSince ?? now
        outsideSince = since
        if now - since >= Self.graceInterval {
            outsideSince = nil
            hasBeenInside = false
            return .close
        }
        return .keepOpen
    }

    /// 上緣不設限（游標頂到螢幕最上緣、甚至 y 略大於 maxY 時，只要水平在範圍內就算在裡面）。
    static func isInside(_ point: CGPoint, notchRect: CGRect) -> Bool {
        point.x >= notchRect.minX - margin
            && point.x <= notchRect.maxX + margin
            && point.y >= notchRect.minY - margin
    }
}
