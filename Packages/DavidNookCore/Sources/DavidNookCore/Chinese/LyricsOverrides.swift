import Foundation

/// 歌詞簡轉繁「覆寫表」：在 OpenCC 之前套用的詞級修正，資料來自
/// `Resources/lyrics_overrides.txt`（每行 `簡體詞=繁體詞`，`#` 開頭為註解）。
///
/// 套用方式：由左到右掃描，同一位置採「最長匹配優先」；命中的片段直接輸出繁體詞，
/// **不會再交給轉換器**，其餘片段才交給轉換器。因此：
/// - 值等於鍵的條目是「保護條目」，用來擋住 OpenCC 會轉錯的字（例如 `征人=征人`）。
/// - 覆寫表優先於 OpenCC 的詞典，也能避開 OpenCC 斷詞陷阱（例如「不断发展」被切成「断发」）。
public struct LyricsOverrides: Sendable {
    public struct Entry: Equatable, Sendable {
        public let key: String
        public let value: String
    }

    /// 解析出的條目（依檔案順序；重複的鍵都保留，實際生效的是最後一個）。
    public let entries: [Entry]
    /// 出現不只一次的鍵。內建覆寫表不得有重複鍵（測試把關）。
    public let duplicateKeys: [String]
    /// 格式錯誤的行號（從 1 起算；註解與空行不算錯誤）。
    public let malformedLineNumbers: [Int]

    private let candidatesByFirstScalar: [UInt32: [Candidate]]

    private struct Candidate {
        let key: [Unicode.Scalar]
        let value: String
    }

    // MARK: - 解析

    public init(parsing text: String) {
        var entries: [Entry] = []
        var seen = Set<String>()
        var duplicates: [String] = []
        var malformed: [Int] = []

        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        for (offset, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let separator = line.firstIndex(of: "=") else {
                malformed.append(offset + 1)
                continue
            }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            if key.isEmpty || value.isEmpty {
                malformed.append(offset + 1)
                continue
            }
            if !seen.insert(key).inserted, !duplicates.contains(key) {
                duplicates.append(key)
            }
            entries.append(Entry(key: key, value: value))
        }

        self.init(entries: entries, duplicateKeys: duplicates, malformedLineNumbers: malformed)
    }

    private init(entries: [Entry], duplicateKeys: [String], malformedLineNumbers: [Int]) {
        self.entries = entries
        self.duplicateKeys = duplicateKeys
        self.malformedLineNumbers = malformedLineNumbers

        // 重複的鍵：後面的覆蓋前面的。
        var effective: [String: String] = [:]
        for entry in entries { effective[entry.key] = entry.value }
        var index: [UInt32: [Candidate]] = [:]
        for (key, value) in effective {
            let scalars = Array(key.unicodeScalars)
            index[scalars[0].value, default: []].append(Candidate(key: scalars, value: value))
        }
        for first in index.keys {
            // 最長優先；長度相同時用鍵排序，讓結果與檔案順序、字典雜湊順序無關。
            index[first]?.sort { lhs, rhs in
                lhs.key.count != rhs.key.count ? lhs.key.count > rhs.key.count : lhs.value < rhs.value
            }
        }
        self.candidatesByFirstScalar = index
    }

    public var isEmpty: Bool { entries.isEmpty }

    /// 原生繁體路徑用的子集合：「值不等於鍵」的條目只留「鍵含簡體字形」者；保護條目（值＝鍵）全留。
    ///
    /// 覆寫表的鍵是簡體詞。簡體路徑整張表都套用；原生繁體文字本來就是繁體，只有鍵裡含**簡體字形**的條目
    /// （`isSimplified` 為真的字）才可能命中上傳者沒轉乾淨的殘留，而不會命中正確的繁體——
    /// 例如「谷堆→穀堆」「后街→後街」「想象→想像」的鍵全由繁體也會用的字組成，會誤傷「山谷堆滿了雪」
    /// 「皇后街」，所以排除。保護條目輸出原文，留著不會改字，卻能維持「最長匹配優先」的保護作用
    /// （「千里美」擋住「里美丽→裡美麗」吃掉千里的「里」）。
    func restrictedToSimplifiedKeys(isSimplified: (Unicode.Scalar) -> Bool) -> LyricsOverrides {
        let kept = entries.filter { entry in
            entry.key == entry.value || entry.key.unicodeScalars.contains(where: isSimplified)
        }
        return LyricsOverrides(entries: kept, duplicateKeys: [], malformedLineNumbers: [])
    }

    // MARK: - 內建覆寫表

    /// 內建覆寫表（`Resources/lyrics_overrides.txt`），只載入一次。
    public static let bundled: LyricsOverrides = {
        // `.process("Chinese/Resources")` 會把檔案平放在資源 bundle 的根目錄。
        guard let url = Bundle.module.url(forResource: "lyrics_overrides", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            assertionFailure("找不到或無法讀取 lyrics_overrides.txt")
            return LyricsOverrides(parsing: "")
        }
        return LyricsOverrides(parsing: text)
    }()

    // MARK: - 套用

    /// 把覆寫表套用到 `text`：命中的片段輸出繁體詞，其餘連續片段交給 `convert`。
    /// - 沒有任何命中時，`convert` 只會被呼叫一次（對整段文字）。
    /// - 空字串直接回傳空字串，不呼叫 `convert`。
    public func apply(to text: String, convertingRest convert: (String) -> String) -> String {
        if text.isEmpty { return "" }
        if candidatesByFirstScalar.isEmpty { return convert(text) }

        let scalars = Array(text.unicodeScalars)
        var output = ""
        var pending = String.UnicodeScalarView()
        var matchedAny = false
        var position = 0

        while position < scalars.count {
            if let hit = longestMatch(in: scalars, at: position) {
                if !pending.isEmpty {
                    output += convert(String(pending))
                    pending = String.UnicodeScalarView()
                }
                output += hit.value
                position += hit.key.count
                matchedAny = true
            } else {
                pending.append(scalars[position])
                position += 1
            }
        }

        if !matchedAny { return convert(text) }
        if !pending.isEmpty { output += convert(String(pending)) }
        return output
    }

    private func longestMatch(in scalars: [Unicode.Scalar], at position: Int) -> Candidate? {
        guard let candidates = candidatesByFirstScalar[scalars[position].value] else { return nil }
        let remaining = scalars.count - position
        for candidate in candidates where candidate.key.count <= remaining {
            var matches = true
            for offset in 1..<max(candidate.key.count, 1) where scalars[position + offset] != candidate.key[offset] {
                matches = false
                break
            }
            if matches { return candidate }
        }
        return nil
    }
}
