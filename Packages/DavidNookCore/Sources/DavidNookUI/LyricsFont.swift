import AppKit
import SwiftUI

/// 歌詞用字型：基底為系統字型（英文、數字維持系統字型），中日韓字元明確指定 PingFang TC（繁體字形）。
///
/// 做法：以系統字型為基底，加上 `cascadeList = [PingFang TC]`。拉丁字母由系統字型（SF）繪製；
/// 漢字交給 PingFang TC，而不是由系統依使用者語言偏好挑 PingFang SC／JP——否則「直」「骨」「令」等字會畫成簡體／日文字形。
enum LyricsFont {
    /// PingFang TC 的 PostScript 家族名稱。
    static let cjkFamily = "PingFang TC"

    static func nsFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        let cjk = NSFontDescriptor(fontAttributes: [.family: cjkFamily])
        let descriptor = base.fontDescriptor.addingAttributes([.cascadeList: [cjk]])
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    static func font(size: CGFloat, weight: NSFont.Weight) -> Font {
        Font(nsFont(size: size, weight: weight) as CTFont)
    }
}
