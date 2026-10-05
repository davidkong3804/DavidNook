import Foundation

/// 簡→繁轉換後的「易錯字」稽核：列出含易錯字的行供人工複核，並以前後文啟發式標出明顯可疑的行。
/// 啟發式只是篩選輔助（寧可多報），不是判決；判決在人工複核。
enum FlaggedAudit {

    /// 來源（簡體）端的易錯字：一個簡體字對應多個繁體字，轉換器要靠詞典猜。
    static let riskSources: Set<Character> = Set("发里后干面台征只斗范于托云系钟志仆复制周历表卷采获余松向冲谷签折蒙")

    /// 可疑樣式：(規則名稱, 條件)。條件拿到「輸出行」的字元陣列與目前索引。
    private struct Rule {
        var name: String
        var char: Character
        var test: ([Character], Int) -> Bool
    }

    private static func prev(_ s: [Character], _ i: Int) -> Character? { i > 0 ? s[i - 1] : nil }
    private static func next(_ s: [Character], _ i: Int) -> Character? { i + 1 < s.count ? s[i + 1] : nil }
    private static func has(_ c: Character?, _ set: String) -> Bool { c.map { set.contains($0) } ?? false }

    private static let rules: [Rule] = [
        Rule(name: "髮用在非頭髮詞", char: "髮") { s, i in
            has(next(s, i), "展現生燒呆抖瘋洩光出誓脾財表揮射") || has(prev(s, i), "出啟爆萌開引激揮")
        },
        Rule(name: "發疑似頭髮", char: "發") { s, i in
            has(prev(s, i), "頭白青長短金銀秀理洗剪黑捲燙") && !has(next(s, i), "展現生財布表揮射出動燒愁呆瘋狂怒泄洩作達行票送言問") ||
                has(next(s, i), "絲型梢尾尖線夾廊")
        },
        Rule(name: "乾疑似幹", char: "乾") { s, i in
            has(next(s, i), "嘛什麼麼活啥掉架") || has(prev(s, i), "能才主")
        },
        Rule(name: "幹疑似乾", char: "幹") { s, i in
            has(next(s, i), "杯淨燥涸脆枯透爽")
        },
        Rule(name: "干未轉", char: "干") { s, i in
            !has(next(s, i), "涉預擾戈部") && !has(prev(s, i), "若相天")
        },
        Rule(name: "麵疑似面", char: "麵") { s, i in
            has(next(s, i), "對前臨容積孔板具相試談孔紗") || has(prev(s, i), "前後裡外上下對場局表正反地一方封畫海水")
        },
        Rule(name: "里未轉", char: "里") { s, i in
            has(prev(s, i), "心夢眼這那哪腦手懷家城山水夜海風雨天地本影景涼間國界世生活記憶空氣中") && !has(prev(s, i), "公千萬鄰鄉")
        },
        Rule(name: "註疑似注", char: "註") { s, i in
            has(next(s, i), "定意視重")
        },
        Rule(name: "谷疑似穀", char: "谷") { s, i in
            has(next(s, i), "堆物倉粒類")
        },
        Rule(name: "扎疑似紮", char: "扎") { s, i in
            has(next(s, i), "馬辮頭根營實起")
        },
        Rule(name: "后未轉", char: "后") { s, i in
            !has(prev(s, i), "皇太王母貴")
        },
        Rule(name: "徵疑似征", char: "徵") { s, i in
            has(next(s, i), "人途程戰服鴻帆") || has(prev(s, i), "遠長出")
        },
        Rule(name: "征疑似徵", char: "征") { s, i in
            has(next(s, i), "兆求詢稅收召聘") || has(prev(s, i), "特象")
        },
        Rule(name: "隻疑似只", char: "隻") { s, i in
            has(next(s, i), "是有要能好為管顧")
        },
        Rule(name: "只疑似隻", char: "只") { s, i in
            has(prev(s, i), "一兩二三四五六七八九十幾每這那數") && has(next(s, i), "鳥貓狗鷹蝶蝴船手眼腳羊雞鴨蟲兔蜂")
        },
        Rule(name: "鬥疑似斗", char: "鬥") { s, i in
            has(next(s, i), "轉星篷笠")
        },
        Rule(name: "斗疑似鬥", char: "斗") { s, i in
            has(next(s, i), "爭志士牛雞毆") || has(prev(s, i), "戰奮搏打決")
        },
        Rule(name: "范未轉", char: "范") { s, i in
            has(next(s, i), "圍疇本例式")
        },
        Rule(name: "于未轉", char: "于") { _, _ in true },
        Rule(name: "託疑似托", char: "託") { s, i in
            has(next(s, i), "起著舉腮肩") || has(prev(s, i), "手")
        },
        Rule(name: "云未轉", char: "云") { s, i in
            !has(prev(s, i), "人所亦") && !has(next(s, i), "云")
        },
        Rule(name: "係疑似系", char: "係") { s, i in
            has(next(s, i), "統列別所")
        },
        Rule(name: "繫疑似系", char: "繫") { s, i in
            has(next(s, i), "統")
        },
        Rule(name: "系疑似係", char: "系") { s, i in
            has(prev(s, i), "關聯")
        },
        Rule(name: "鍾疑似鐘", char: "鍾") { s, i in
            has(next(s, i), "聲點樓錶")
        },
        Rule(name: "鐘疑似鍾", char: "鐘") { s, i in
            has(next(s, i), "情愛意")
        },
        Rule(name: "誌疑似志", char: "誌") { s, i in
            has(prev(s, i), "意壯鬥立")
        },
        Rule(name: "仆未轉", char: "仆") { _, _ in true },
        Rule(name: "僕疑似仆", char: "僕") { s, i in
            has(prev(s, i), "前") && has(next(s, i), "後")
        },
        Rule(name: "復疑似複", char: "復") { s, i in
            has(next(s, i), "雜製合")
        },
        Rule(name: "複疑似復", char: "複") { s, i in
            has(next(s, i), "活原興蘇仇")
        },
        Rule(name: "复未轉", char: "复") { _, _ in true },
    ]

    /// 輸出行裡命中的可疑規則名稱（以「、」連接；沒有則空字串）。
    static func suspects(in output: String) -> String {
        let chars = Array(output)
        var names: [String] = []
        for rule in rules {
            for (i, c) in chars.enumerated() where c == rule.char && rule.test(chars, i) {
                if !names.contains(rule.name) { names.append(rule.name) }
            }
        }
        // 反覆／重複等詞級樣式。
        for (needle, name) in [("反複", "反複應為反覆"), ("重復", "重復應為重複")] where output.contains(needle) {
            names.append(name)
        }
        return names.joined(separator: "、")
    }

    /// 這一行來源裡有哪些易錯字，以及它們在輸出的對應字（用 LCS 對齊；對不到的標 `∅`）。
    static func riskPairs(source: String, output: String) -> String {
        guard source.contains(where: { riskSources.contains($0) }) else { return "" }
        let a = Array(source), b = Array(output)
        let pairs = TextDiff.lcsPairs(a, b)
        var mapped = [Int: Int]()
        for (i, j) in pairs { mapped[i] = j }
        // 夾在兩個匹配之間、長度相同的缺口逐字對應。
        var prevI = -1, prevJ = -1
        func fill(_ i1: Int, _ j1: Int) {
            let gapA = i1 - prevI - 1, gapB = j1 - prevJ - 1
            if gapA == gapB, gapA > 0 { for k in 1...gapA { mapped[prevI + k] = prevJ + k } }
        }
        for (i, j) in pairs {
            fill(i, j)
            prevI = i; prevJ = j
        }
        fill(a.count, b.count)
        var parts: [String] = []
        for (i, c) in a.enumerated() where riskSources.contains(c) {
            if let j = mapped[i] { parts.append("\(c)→\(b[j])") } else { parts.append("\(c)→∅") }
        }
        return parts.joined(separator: " ")
    }
}
