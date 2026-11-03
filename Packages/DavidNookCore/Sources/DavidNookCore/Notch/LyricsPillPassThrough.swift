import CoreGraphics
import Foundation

/// 歌詞膠囊的「滑鼠透過去」（純邏輯）。
///
/// 膠囊常常剛好蓋在瀏覽器分頁上。游標在膠囊上停留超過 `engageDelay` 後，膠囊暫時變淡、視窗不再接收滑鼠事件
/// （點擊直接落到底下的視窗）；游標離開膠囊（含 `releaseMargin` 的緩衝）就立刻恢復。
///
/// 視窗不接收滑鼠事件後就收不到 hover 了，所以這裡完全靠定時取樣游標座標（與 `NotchCloseWatchdog` 同一招），
/// 不依賴任何事件。
public struct LyricsPillPassThrough: Equatable, Sendable {
    /// 游標停留多久（秒）才透過去：快速掃過（例如往瀏海移動）不會閃一下。
    public static let engageDelay: TimeInterval = 0.12
    /// 已透過去之後，游標要離開矩形多遠（pt）才恢復：貼著邊緣的小抖動不閃爍。
    public static let releaseMargin: CGFloat = 6

    public private(set) var isPassingThrough = false
    private var insideSince: TimeInterval?

    public init() {}

    /// 膠囊在螢幕上的矩形（AppKit 座標，y 向上）：水平置中於視窗，上緣在視窗上緣往下 `topOffset`。
    public static func pillRect(windowFrame: CGRect, topOffset: CGFloat, size: CGSize) -> CGRect {
        CGRect(
            x: windowFrame.midX - size.width / 2, y: windowFrame.maxY - topOffset - size.height,
            width: size.width, height: size.height
        )
    }

    /// 取樣一次，回傳目前是否該透過去。
    /// - Parameters:
    ///   - pillRect: 膠囊目前的矩形；nil＝膠囊沒顯示（展開、淡出、關閉功能…），狀態歸零。
    ///   - mouseButtonDown: 按著滑鼠進來（拖曳東西）時不啟動；已透過去時按下（正在點分頁）則維持。
    @discardableResult
    public mutating func update(now: TimeInterval, pointer: CGPoint, pillRect: CGRect?, mouseButtonDown: Bool) -> Bool {
        guard let pillRect, Self.isFinite(pillRect), pointer.x.isFinite, pointer.y.isFinite else {
            reset()
            return false
        }
        if isPassingThrough {
            if !pillRect.insetBy(dx: -Self.releaseMargin, dy: -Self.releaseMargin).contains(pointer) { reset() }
            return isPassingThrough
        }
        guard pillRect.contains(pointer), !mouseButtonDown else {
            insideSince = nil
            return false
        }
        let since = insideSince ?? now
        insideSince = since
        if now - since >= Self.engageDelay { isPassingThrough = true }
        return isPassingThrough
    }

    public mutating func reset() {
        isPassingThrough = false
        insideSince = nil
    }

    private static func isFinite(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite && rect.width.isFinite && rect.height.isFinite
    }
}
