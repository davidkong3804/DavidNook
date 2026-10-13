import Foundation

/// 展開瀏海的播放按鈕列（純邏輯；App 端把 `MusicControlButton` 的 rawValue 字串交進來）。
///
/// 為什麼預設拿掉隨機播放與重複播放：五顆 30–40 pt 的按鈕擠在一排，影片槽加寬後控制區只剩最小寬度，
/// 很容易誤點到「重複播放」——播放器就此進入單曲／全部循環，使用者以為「播完一首就一直重播」。
/// 預設只留上一首、播放／暫停、下一首；要用的人仍可在設定頁自己加回去。
public enum MusicControlLayoutMigration {
    /// 版面版本：存在使用者的設定裡，遷移只會執行一次，之後使用者自己加回去的按鈕不會再被動到。
    public static let currentVersion = 2
    public static let versionKey = "musicControlLayoutVersion"

    /// 舊版預設（五顆）。
    public static let legacyDefault = ["shuffle", "previous", "playPause", "next", "repeatMode"]
    /// 新版預設（三顆）。
    public static let newDefault = ["previous", "playPause", "next"]
    public static let emptySlot = "none"

    /// 回傳要換成的新版面；`nil`＝不用改（已遷移過、使用者自訂過、或內容無法辨識）。
    public static func migrate(saved: [String], savedVersion: Int) -> [String]? {
        guard savedVersion < currentVersion else { return nil }
        guard trimmingTrailingEmptySlots(saved) == legacyDefault else { return nil }
        return newDefault
    }

    /// 去掉尾端的空格（設定頁會把版面補滿格數）；中間的空格是使用者刻意留的間隔，保留。
    public static func trimmingTrailingEmptySlots(_ slots: [String]) -> [String] {
        var result = slots
        while result.last == emptySlot { result.removeLast() }
        return result
    }
}
