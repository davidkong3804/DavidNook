import CoreGraphics
import Foundation

/// 「游標掃過選單列時不要因為 hover 展開瀏海」的判斷（純邏輯）。
///
/// 閉合瀏海的形體比實體瀏海寬：播放音樂時兩側各多出約 40 pt（專輯封面、波形），其他提示更寬。
/// 這些延伸出去的部分剛好蓋在瀏海兩側的選單列圖示上；游標停在圖示上（或往圖示移動途中停頓）達到
/// 停留時間就會 hover 展開，720 pt 的展開面板又把圖示整排蓋住，使用者夠不到。
///
/// 規則：游標在**選單列高度**內，且**不在實體瀏海正上方**（左右各容許 `sideTolerance`）時，不 hover 展開。
/// 游標在選單列下方（歌詞膠囊、提示列）不受限制；點擊瀏海任何位置仍然會展開（本類別只管 hover）。
/// 量測值不明（選單列高度或瀏海寬度非有限正數）時退回舊行為：允許展開。
public enum NotchHoverOpenGuard {
    /// 實體瀏海左右各多容許的寬度（pt）：貼著瀏海邊緣時不要太難觸發。
    public static let sideTolerance: CGFloat = 6

    /// - Parameters:
    ///   - pointer: 游標位置（AppKit 全域座標，y 向上）。
    ///   - screenFrame: 瀏海所在螢幕的 `frame`（全域座標）。
    ///   - menuBarHeight: 該螢幕的選單列高度（pt）。
    ///   - notchWidth: 實體瀏海（閉合瀏海本體，不含兩側延伸）的寬度（pt）。
    public static func allowsHoverOpen(
        pointer: CGPoint, screenFrame: CGRect, menuBarHeight: CGFloat, notchWidth: CGFloat
    ) -> Bool {
        guard menuBarHeight.isFinite, menuBarHeight > 0, notchWidth.isFinite, notchWidth > 0 else { return true }
        let inMenuBarBand = pointer.y >= screenFrame.maxY - menuBarHeight
        guard inMenuBarBand else { return true }
        return abs(pointer.x - screenFrame.midX) <= notchWidth / 2 + sideTolerance
    }
}
