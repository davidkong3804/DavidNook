import Foundation

/// 雙語歌詞收合器：LRCLIB 上有些版本是逐行附翻譯的雙語檔（原文一行、翻譯一行，**共用同一個時間戳**）。
/// 若不處理，時間軸的「目前行」會直接跳到翻譯行，原文一閃而過；翻譯行也會干擾簡繁判斷。
///
/// 規則：把非空白行依序看，「時間戳與前一個非空白行相同」的行稱為「同刻行」。
/// - 同刻行數 ≥ `minimumPairs`（3）**且** ≥ 非空白行的 `minimumSharePercent`（30%）→ 判定為雙語檔，
///   每組同刻行只留第一行（慣例是原文在前、翻譯在後），其餘移到 `dropped`。
/// - 否則原樣回傳：一般歌詞偶爾有兩行同時間（重疊的合唱），不能誤刪真歌詞。
///
/// 已知限制：若某個檔把翻譯放在原文前面，會留下翻譯；這種檔在實測資料中沒有出現。空白（間奏）標記行一律保留。
/// 在檔頭剝除**之前**呼叫較好：雙語檔的檔頭中繼行（作詞／作曲…）也是成對的，收合後行數減半，不會超過檔頭掃描上限。
public enum LyricsTranslationCollapser {

    /// 至少要有這麼多「同刻行」才會判定為雙語檔。
    public static let minimumPairs = 3
    /// 同刻行占非空白行的百分比下限。
    public static let minimumSharePercent = 30

    public struct Result: Equatable, Sendable {
        /// 收合後的行（保留順序與時間）。
        public var lines: [LRCLine]
        /// 被移除的翻譯行。
        public var dropped: [LRCLine]

        public init(lines: [LRCLine], dropped: [LRCLine]) {
            self.lines = lines
            self.dropped = dropped
        }
    }

    public static func collapse(_ lines: [LRCLine]) -> Result {
        let spoken = lines.filter { !$0.isBlank }
        guard spoken.count > 1 else { return Result(lines: lines, dropped: []) }

        var sameMoment = 0
        for (previous, current) in zip(spoken, spoken.dropFirst()) where previous.timeMs == current.timeMs {
            sameMoment += 1
        }
        guard sameMoment >= minimumPairs, sameMoment * 100 >= minimumSharePercent * spoken.count else {
            return Result(lines: lines, dropped: [])
        }

        var kept: [LRCLine] = []
        var dropped: [LRCLine] = []
        var lastKeptSpokenTime: Int?
        for line in lines {
            if line.isBlank {
                kept.append(line)
            } else if line.timeMs == lastKeptSpokenTime {
                dropped.append(line)
            } else {
                kept.append(line)
                lastKeptSpokenTime = line.timeMs
            }
        }
        return Result(lines: kept, dropped: dropped)
    }
}
