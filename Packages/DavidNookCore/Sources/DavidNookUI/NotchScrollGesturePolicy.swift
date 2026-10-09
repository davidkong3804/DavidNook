import Foundation

// 瀏海外層的滾動手勢（上滑關閉、下滑展開、左右切歌）何時該略過的純決策。

/// 展開瀏海目前的分頁（只列出與滾動決策有關的種類；App 端的 `NotchViews` 對應到這裡）。
public enum NotchScrollTab: Equatable, Sendable {
    case home
    case clipboard
}

/// 手勢方向（與 App 端 `PanDirection` 對應）。
public enum NotchScrollGestureDirection: CaseIterable, Equatable, Sendable {
    case up, down, left, right

    var isVertical: Bool { self == .up || self == .down }
}

/// 滑鼠停在可捲動內容上時，滾輪／觸控板的垂直滾動只用來捲那份內容，不能同時被當成瀏海手勢
/// （否則剪貼簿清單往下捲＝手指上滑＝「上滑關閉」，清單滑不了幾列瀏海就收了）。
public enum NotchScrollGesturePolicy {
    /// 這個滾動事件要不要交給瀏海手勢處理。
    ///
    /// - Parameters:
    ///   - tab: 目前分頁。
    ///   - pointerOverScrollable: 滑鼠是否正在該分頁的可捲動清單上。
    ///   - direction: 手勢方向。
    ///   - isEnd: 是不是手勢結束事件；結束事件一律處理，避免進度卡在中間。
    public static func shouldHandle(
        tab: NotchScrollTab,
        pointerOverScrollable: Bool,
        direction: NotchScrollGestureDirection,
        isEnd: Bool = false
    ) -> Bool {
        if isEnd { return true }
        switch tab {
        case .home:
            return true
        case .clipboard:
            return !(pointerOverScrollable && direction.isVertical)
        }
    }
}
