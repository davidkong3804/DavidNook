import DavidNookCore
import Foundation

/// 列表每一列的預覽字串（純函式，有測試）。
///
/// 重點是「不要把整段超大文字（上限 1MB）交給 SwiftUI 排版」：預覽只取前 `maxCharacters` 個字。
public enum ClipboardRowPreview {
    /// 文字預覽最多字數。
    public static let maxCharacters = 200
    /// tooltip 最多字數。
    public static let maxTooltipCharacters = 600

    /// 文字列的預覽：略過開頭的空白與空行，取前 `maxCharacters` 個字，超過加「…」。
    /// 換行保留（視圖以 lineLimit(2) 截成兩行）。
    public static func text(_ string: String) -> String {
        clipped(string, limit: maxCharacters)
    }

    /// 檔案列的主標題：第一個檔案的檔名（路徑只有 "/" 時顯示 "/"）。
    public static func fileTitle(_ paths: [String]) -> String {
        guard let first = paths.first else { return "" }
        let name = URL(fileURLWithPath: first).lastPathComponent
        return name.isEmpty ? first : name
    }

    /// 該列的 tooltip：檔案列為完整路徑（一行一個）；文字列為較長一點的內容預覽；圖片列沒有。
    public static func tooltip(for item: ClipboardItem) -> String? {
        switch item.kind {
        case .files:
            return item.filePaths?.joined(separator: "\n")
        case .text:
            return item.text.map { clipped($0, limit: maxTooltipCharacters) }
        case .image:
            return nil
        }
    }

    private static func clipped(_ string: String, limit: Int) -> String {
        let trimmed = string.drop(while: { $0.isWhitespace || $0.isNewline })
        let head = trimmed.prefix(limit)
        // 去掉尾端空白，避免「…」前面一串空白。
        var result = String(head)
        while let last = result.last, last.isWhitespace || last.isNewline { result.removeLast() }
        // 不用 count（對 1MB 字串是 O(n)）：只看第 limit 個字之後還有沒有東西。
        return trimmed.dropFirst(limit).isEmpty ? result : result + "…"
    }
}
