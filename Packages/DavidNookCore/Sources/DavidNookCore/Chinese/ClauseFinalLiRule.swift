/// 「里」子句尾啟發式：把殘留在子句尾的「里」改成「裡」。
///
/// 「里」「裡」在簡體都寫「里」，OpenCC 對沒有詞組支援的組合（書本里、電影里）會保留「里」；
/// 原生繁體歌詞也常殘留這種寫法（場景里、秋涼里）。「里」不是簡體專有字（「千里」「公里」「鄰里」是正確的繁體），
/// 偵測器無法靠字集判斷，所以改看位置：
///
/// - 「里」後面是**標點、符號、空白或行尾**（子句尾），且
/// - 前一個字元是漢字，且不在「保留集合」中 → 改成「裡」。
///
/// 保留集合（前一字是這些時，「里」是長度單位、數量或固定詞，保留）：
/// 數字與數詞（零〇一二三四五六七八九十百千万萬億兩两幾几半）、單位（公、英）、
/// 鄰里／鄉里／故里（鄰邻鄉乡故）。「村里」「海里」「家里」「心里」會轉成「裡」。
///
/// 「里」後面還有字（里程、里約、里斯本、十里桃花、心里想著）不是子句尾，完全不受影響。
///
/// 這是 `LyricsLocalizer` 的最後一步，只對已判定為華語的文件使用（簡體、繁體、混合；中性文件與日韓行不動）。
enum ClauseFinalLiRule {
    private static let li: Unicode.Scalar = "里"
    private static let replacement: Unicode.Scalar = "裡"

    /// 前一字在此集合時保留「里」。
    private static let keepAfter: Set<Unicode.Scalar> = Set("零〇一二三四五六七八九十百千万萬億兩两幾几半公英鄰邻鄉乡故".unicodeScalars)

    static func apply(to line: String) -> String {
        let scalars = Array(line.unicodeScalars)
        guard scalars.count > 1, scalars.contains(li) else { return line }

        var output = scalars
        var changed = false
        for index in 1..<scalars.count where scalars[index] == li {
            let previous = scalars[index - 1]
            guard isHan(previous), !keepAfter.contains(previous) else { continue }
            let atClauseEnd = index + 1 == scalars.count || isClauseBoundary(scalars[index + 1])
            guard atClauseEnd else { continue }
            output[index] = replacement
            changed = true
        }
        guard changed else { return line }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: output)
        return String(view)
    }

    private static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0xF900...0xFAFF, 0x20000...0x2FA1F: return true
        default: return false
        }
    }

    /// 空白、標點與符號（含 …、～、♪）都算子句邊界。
    private static func isClauseBoundary(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.properties.isWhitespace { return true }
        switch scalar.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation,
             .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol:
            return true
        default:
            return false
        }
    }
}
