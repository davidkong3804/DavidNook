import Foundation

/// 把資料目錄標為「不納入備份」（`URLResourceValues.isExcludedFromBackup`，Time Machine 與 iCloud 備份都會遵守）。
///
/// 為什麼需要：剪貼簿歷史與歌詞快取（聽歌紀錄）是明文存放在本機的私密資料。若被 Time Machine 備份，
/// 「清除全部」只能刪掉現在的檔案，刪不到已經進入備份快照的舊副本。對目錄設定一次即可，
/// 標記對整個子樹生效（之後在目錄下建立的檔案也不會被備份）。
enum BackupExclusion {
    /// 對目錄設定排除備份；失敗時拋出（呼叫端視為「目錄不可用」，不在無法保證隱私的目錄存資料）。
    static func exclude(_ directory: URL) throws {
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}
