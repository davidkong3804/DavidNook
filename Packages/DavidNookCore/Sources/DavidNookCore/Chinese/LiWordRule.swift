/// 「里→裡」詞級規則：把殘留的「里」改成「裡」。
///
/// 「里」「裡」在簡體都寫「里」。OpenCC 對沒有詞組支援的組合（書本里、電影里）會保留「里」，
/// 原生繁體歌詞也常殘留（心里卻…、家里沒有…、場景里出現…）。「里」不是簡體專有字（「千里」「公里」「鄰里」
/// 是正確的繁體），偵測器無法靠字集判斷，所以改看前後字（真實資料稽核：殘留的「里」後面幾乎都接字，
/// 只看子句尾的舊啟發式改不到）：
///
/// - 前一字是漢字，且**不在前綴排除集**；
/// - 後一字（若有）**不在後綴排除集**；
/// - 且不屬於**整詞保護清單**（鄰里、公里、里程、阿里山、斯里蘭卡…）→ 改成「裡」。
///
/// 前綴排除集（前一字是這些時保留「里」）：
/// - 數詞與量詞：零〇一二三四五六七八九十百千万萬億亿兩两幾几半（千里、萬里、十里桃花、幾里路）；
/// - 單位：公、英（公里、英里）；
/// - 轉寫與專名常見前綴：阿斯加卡艾哈安莫馬俄哥約波德塞達賽沙福奧（簡體字形一併列入）；
/// - 整詞保護：鄰邻鄉乡故（鄰里、鄉里、故里）；
/// - 辭典掃描補充：OpenCC `STPhrases` 裡保留「里」的 867 個詞位置中，這規則原本會誤改 403 處，
///   絕大多數是轉寫專名（克里米亞、烏蘇里江、佛羅里達、薩里、弗里曼…），把這些詞的前綴字補進來：
///   克蘇苏羅罗薩萨弗佛伊尤亞亚烏乌費费歐欧瓦庫库凱凯餘余托貝贝；以及「里」本身。
///   「格、巴、西、梅、大、美」雖然也常見於這類專名，但在歌詞裡常是「性格里」「嘴巴里」「東西里」，所以**不**排除。
///
/// 後綴排除集（後一字是這些時保留「里」）：程長弄巷約昂斯爾尼加奧德根正甲坊民鄰鄉（簡體字形一併列入）
/// （里程、里長、里弄、里巷、里約、里昂、里斯本、里爾、里尼、里加、里奧、里德、里根、里正、里甲、里坊、里民）。
///
/// 已知取捨：後綴「長」「正」「民」「加」「德」使「家里長大」「心里正在」之類少數句子漏改（保守：寧可不改）；
/// 前綴「福」「安」使「幸福里」「平安里」也保留（任務指定的排除集）。行首的「里面」「里邊」（前面沒有字）不改。
///
/// 這是 `LyricsLocalizer` 的最後一步，只對已判定為華語的文件使用（簡體、繁體、混合；中性文件與日韓行不動）。
enum LiWordRule {
    private static let li: Unicode.Scalar = "里"
    private static let replacement: Unicode.Scalar = "裡"

    /// 前一字在此集合時保留「里」。
    private static let keepAfter: Set<Unicode.Scalar> = Set((
        "零〇一二三四五六七八九十百千万萬億亿兩两幾几半"
            + "公英"
            + "阿斯加卡艾哈安莫马馬俄哥约約波德塞达達赛賽沙福奥奧"
            + "鄰邻鄉乡故"
            + "克蘇苏羅罗薩萨弗佛伊尤亞亚烏乌費费歐欧瓦庫库凱凯餘余托貝贝"
            + "里"
    ).unicodeScalars)

    /// 後一字在此集合時保留「里」。
    private static let keepBefore: Set<Unicode.Scalar> = Set("程长長弄巷约約昂斯尔爾尼加奥奧德根正甲坊民邻鄰乡鄉".unicodeScalars)

    /// 整詞保護清單（詞內的「里」一律保留）。
    private static let protectedWords: [ProtectedWord] = [
        "鄰里", "邻里", "鄉里", "乡里", "故里", "公里", "英里", "里程", "里長", "里长", "里民", "里約", "里约", "里昂",
        "阿里山", "阿里巴巴", "斯里蘭卡", "斯里兰卡", "千里", "萬里", "万里", "百里", "十里",
        // 辭典掃描補充：歌詞常見、前綴字又不宜整個排除的詞。
        "卡路里", "歇斯底里", "香格里拉", "西西里", "格里高利", "劈里啪啦", "稀里嘩啦", "稀里哗啦", "里脊",
    ].map(ProtectedWord.init)

    private struct ProtectedWord {
        let scalars: [Unicode.Scalar]
        /// 詞內每個「里」的位置。
        let liOffsets: [Int]

        init(_ word: String) {
            let chars = Array(word.unicodeScalars)
            scalars = chars
            liOffsets = chars.indices.filter { chars[$0] == LiWordRule.li }
        }

        func covers(index: Int, in text: [Unicode.Scalar]) -> Bool {
            for offset in liOffsets {
                let start = index - offset
                guard start >= 0, start + scalars.count <= text.count else { continue }
                if text[start..<(start + scalars.count)].elementsEqual(scalars) { return true }
            }
            return false
        }
    }

    static func apply(to line: String) -> String {
        let scalars = Array(line.unicodeScalars)
        guard scalars.count > 1, scalars.contains(li) else { return line }

        var output = scalars
        var changed = false
        for index in 1..<scalars.count where scalars[index] == li {
            let previous = scalars[index - 1]
            guard isHan(previous), !keepAfter.contains(previous) else { continue }
            if index + 1 < scalars.count, keepBefore.contains(scalars[index + 1]) { continue }
            if protectedWords.contains(where: { $0.covers(index: index, in: scalars) }) { continue }
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
}
