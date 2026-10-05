import DavidNookCore
import Foundation

/// A/B 對照：同一首歌在 LRCLIB 同時有簡體版 S 與原生繁體版 T 時，
/// 把 S 跑完整管線（`LyricsLocalizer`），與 T（經同一管線的 t2tw 後的「顯示結果」，另外也比原文）逐行逐字比對。
///
/// 為了把「轉換錯誤」跟「兩份歌詞本來措辭就不同」分開，比較以**正規化簡體**為對齊基準：
/// 先把每個字單獨轉成簡體（`canon`：髮／發→发、裡／裏→里、後→后、乾／幹→干、麵→面、臺→台、瞭→了…），
/// 對兩邊的正規化序列做 LCS；只有「正規化後相同、但實際字不同」的位置才算轉換不一致，
/// 正規化後就不同的字屬於措辭差異，不計入（另外以 `unalignedChars` 回報）。
final class ABComparer {

    private let canonConverter: LyricsChineseConverter
    private let detector = ChineseScriptDetector()
    private var canonCache: [Character: Character] = [:]

    init() throws {
        canonConverter = try LyricsChineseConverter(mode: .traditionalToSimplified)
    }

    /// 單字轉簡體；轉出不是單一字元時原樣保留。
    func canon(_ c: Character) -> Character {
        if let hit = canonCache[c] { return hit }
        let converted = canonConverter.convert(String(c))
        let result = converted.count == 1 ? converted.first! : c
        canonCache[c] = result
        return result
    }

    // MARK: - 分類

    /// 風格差異（兩邊都可接受的字形選擇），與「語意錯誤」（換了字意思就不對）分開統計。
    private static let styleGroups: [Set<Character>] = [
        ["台", "臺"], ["了", "瞭"], ["着", "著"], ["為", "爲"], ["群", "羣"], ["眾", "衆"], ["啟", "啓"],
        ["線", "綫"], ["峰", "峯"], ["說", "説"], ["污", "汙"], ["麼", "麽"], ["才", "纔"], ["並", "并"],
        ["吃", "喫"], ["跡", "蹟", "迹"], ["裡", "裏"],
        // 異體字：兩種寫法在臺灣都通行（OpenCC 的 twStandard 會選其中一種）。
        ["悽", "淒"], ["搜", "蒐"], ["嘆", "歎"], ["昇", "升"], ["週", "周"], ["溼", "濕"], ["汙", "污"],
    ]

    func classify(ours c1: Character, ref c2: Character) -> (category: String, kind: String) {
        // 對照版本身殘留簡體專有字（沒轉乾淨）：不是我們的錯，另外統計。
        if detector.evidence(in: String(c2)).simplified > 0 { return ("對照版殘留簡體", "ref-residue") }
        let pair: Set<Character> = [c1, c2]
        if Self.styleGroups.contains(where: { pair.isSubset(of: $0) }) {
            switch canon(c1) {
            case "台": return ("台/臺", "style")
            case "了": return ("了/瞭", "style")
            default: return ("其他風格(\(c1)/\(c2))", "style")
            }
        }
        switch canon(c1) {
        case "发": return ("髮/發", "semantic")
        case "里": return ("里/裡", "semantic")
        case "后": return ("后/後", "semantic")
        case "干": return ("干/乾/幹", "semantic")
        case "面": return ("面/麵", "semantic")
        default: return ("其他", "semantic")
        }
    }

    // MARK: - 配對

    struct TimedText {
        var timeMs: Int
        var text: String
        var source: String
    }

    /// 以時間戳最接近配對：先估計整體偏移（最近鄰差的中位數），再貪婪一對一配對（距離小者優先，容差 1.5 秒）。
    static func timePairs(_ a: [TimedText], _ b: [TimedText], toleranceMs: Int = 1500) -> (pairs: [(Int, Int)], offsetMs: Int) {
        guard !a.isEmpty, !b.isEmpty else { return ([], 0) }
        var deltas: [Int] = []
        for x in a {
            if let nearest = b.min(by: { abs($0.timeMs - x.timeMs) < abs($1.timeMs - x.timeMs) }) {
                deltas.append(nearest.timeMs - x.timeMs)
            }
        }
        deltas.sort()
        let offset = deltas[deltas.count / 2]
        var candidates: [(i: Int, j: Int, d: Int)] = []
        for (i, x) in a.enumerated() {
            for (j, y) in b.enumerated() {
                let d = abs(y.timeMs - (x.timeMs + offset))
                if d <= toleranceMs { candidates.append((i, j, d)) }
            }
        }
        candidates.sort { $0.d != $1.d ? $0.d < $1.d : ($0.i != $1.i ? $0.i < $1.i : $0.j < $1.j) }
        var usedA = Set<Int>(), usedB = Set<Int>()
        var pairs: [(Int, Int)] = []
        for c in candidates where !usedA.contains(c.i) && !usedB.contains(c.j) {
            usedA.insert(c.i); usedB.insert(c.j)
            pairs.append((c.i, c.j))
        }
        return (pairs.sorted { $0.0 < $1.0 }, offset)
    }

    static func indexPairs(_ a: [TimedText], _ b: [TimedText]) -> [(Int, Int)] {
        guard abs(a.count - b.count) <= max(2, a.count / 10) else { return [] }
        return (0..<min(a.count, b.count)).map { ($0, $0) }
    }

    // MARK: - 比對

    /// 比較用的字序列：只留字母與數字（含漢字），去掉標點與空白。
    private static func sequence(_ s: String) -> [Character] {
        s.filter { $0.isLetter || $0.isNumber }.map { $0 }
    }

    struct Evaluation {
        var linesPaired = 0
        var linesCompared = 0
        var linesSkipped = 0
        var alignedChars = 0
        var unalignedChars = 0
        var vsDisplay = DiffTally()
        var vsRaw = DiffTally()
        var occurrences: [String: Int] = [:]
        var examples: [DiffExample] = []
    }

    /// 錯誤率分母要統計的「歧義簡體字」。
    static let ambiguousCanon: Set<Character> = Set("发里后干面台了征只斗范于托云系钟志仆复制周历表卷采获余松向冲谷签折蒙欲")

    /// - Parameters:
    ///   - ours: S 經管線轉換後的行（含時間）；`source` 是 S 原文。
    ///   - refDisplay: T 經管線（t2tw）後的行。
    ///   - refRaw: T 原文（與 `refDisplay` 同序、同時間）。
    func evaluate(pairs: [(Int, Int)], ours: [TimedText], refDisplay: [TimedText], refRaw: [TimedText], maxExamples: Int = 200) -> Evaluation {
        var result = Evaluation()
        result.linesPaired = pairs.count
        for (i, j) in pairs {
            let o = Self.sequence(ours[i].text)
            let rd = Self.sequence(refDisplay[j].text)
            let rr = Self.sequence(refRaw[j].text)
            let co = o.map(canon), crd = rd.map(canon)
            let lcs = TextDiff.lcsPairs(co, crd)
            let shorter = min(o.count, rd.count)
            if shorter == 0 || Double(lcs.count) / Double(shorter) < 0.5 {
                result.linesSkipped += 1
                continue
            }
            result.linesCompared += 1
            var matchedOurs = Set<Int>()
            for (p, q) in lcs {
                matchedOurs.insert(p)
                guard CJK.isIdeograph(o[p]) else { continue }
                result.alignedChars += 1
                if Self.ambiguousCanon.contains(co[p]) { result.occurrences[String(co[p]), default: 0] += 1 }
                if o[p] != rd[q] {
                    let (cat, kind) = classify(ours: o[p], ref: rd[q])
                    tally(&result.vsDisplay, cat, kind, "\(o[p])→\(rd[q])", canon: co[p])
                    if result.examples.count < maxExamples {
                        result.examples.append(DiffExample(
                            category: cat, kind: kind, ours: String(o[p]), ref: String(rd[q]), timeMs: ours[i].timeMs,
                            sourceLine: ours[i].source, oursLine: ours[i].text, refLine: refDisplay[j].text
                        ))
                    }
                }
            }
            for (p, ch) in o.enumerated() where !matchedOurs.contains(p) && CJK.isIdeograph(ch) {
                result.unalignedChars += 1
            }
            // 同一組配對對原文再比一次（以 ours 為準，用原文序列做 LCS）。
            let crr = rr.map(canon)
            for (p, q) in TextDiff.lcsPairs(co, crr) where CJK.isIdeograph(o[p]) && o[p] != rr[q] {
                let (cat, kind) = classify(ours: o[p], ref: rr[q])
                tally(&result.vsRaw, cat, kind, "\(o[p])→\(rr[q])", canon: co[p])
            }
        }
        return result
    }

    private func tally(_ t: inout DiffTally, _ category: String, _ kind: String, _ pair: String, canon: Character) {
        switch kind {
        case "semantic": t.semantic += 1
        case "style": t.style += 1
        default: t.refResidue += 1
        }
        t.byCategory[category, default: 0] += 1
        t.byPair[pair, default: 0] += 1
        t.byCanon[String(canon), default: 0] += 1
    }
}
