import Foundation

/// 剝除歌詞檔頭的中繼行（作詞／作曲／編曲／監製、`歌名 - 歌手`、單獨的歌名或歌手名…）。
///
/// 只處理「檔頭」：從第一行開始連續判斷，**遇到第一句真正的歌詞就停止**，而且只看
/// 前 `maxHeaderLines` 行（預設 10）且時間 < `maxHeaderTimeMs`（預設 25 秒）的行。
/// 因此歌詞中段剛好長得像「標籤：值」的句子不會被誤殺。
///
/// 判定為中繼行的條件（任一）：
/// 1. 「標籤：值」格式（半形 `:` 或全形 `：`），標籤在白名單內（詞／曲／作詞／編曲／監製／OP／SP／Lyrics by…，
///    簡繁與大小寫皆可，可用 `extraCreditLabels` 擴充）；值可為空。
/// 2. 文字本身是 ID tag 形式（例如 `[ti:歌名]`、`[ar:歌手]`）。
/// 3. 含歌名或歌手名的 `X - Y` 行（分隔符：空白包圍的 `-`、`–`、`—`）：任一側等於歌名／歌手名，
///    或任一側「包含」長度 ≥ 2 的歌名／歌手名。
/// 4. 單獨等於歌名或歌手名的行（忽略大小寫與空白）。
/// 5. 檔頭範圍內的空白行（順手丟掉，避免剝完留下孤立的空白）。
///
/// 安全網：若剝除後一行歌詞都不剩，視為誤判，原樣回傳。
///
/// 簡繁不同寫法的歌名（例如標題是繁體、歌詞檔是簡體）：注入 `normalize`（例如簡轉繁或繁轉簡）
/// 讓比對前先把兩邊轉成同一種寫法；預設不轉換。
public struct LyricsMetaStripper: Sendable {

    /// 剝除結果。
    public struct Result: Equatable, Sendable {
        /// 剝除後的歌詞行。
        public var lines: [LRCLine]
        /// 被剝掉的檔頭行（依原順序）。
        public var dropped: [LRCLine]

        public init(lines: [LRCLine], dropped: [LRCLine]) {
            self.lines = lines
            self.dropped = dropped
        }
    }

    /// 預設的「標籤」白名單（已轉小寫、去空白）。
    public static let defaultCreditLabels: Set<String> = [
        "詞", "词", "曲", "作詞", "作词", "作曲", "詞曲", "词曲", "編曲", "编曲", "填詞", "填词",
        "監製", "监制", "製作", "制作", "製作人", "制作人", "出品", "企劃", "企划", "統籌", "统筹", "發行", "发行",
        "原唱", "演唱", "歌手", "配唱", "和聲", "和声", "混音", "母帶", "母带", "錄音", "录音",
        "吉他", "貝斯", "贝斯", "鼓", "弦樂", "弦乐",
        "op", "sp",
        "lyrics", "lyricsby", "lyricist", "words", "wordsby", "writtenby",
        "music", "musicby", "composer", "composedby", "arranger", "arrangedby", "arrangement",
        "producer", "producedby", "vocal", "vocals", "singer", "artist", "title", "album",
    ]

    private static let idTagKeys: Set<String> = ["ti", "ar", "al", "au", "by", "offset", "length", "re", "ve", "la"]
    private static let dashSeparators = [" - ", " – ", " — "]

    private let maxHeaderLines: Int
    private let maxHeaderTimeMs: Int
    private let normalize: @Sendable (String) -> String
    private let creditLabels: Set<String>

    /// - Parameters:
    ///   - maxHeaderLines: 只檢查前幾行（預設 10）。
    ///   - maxHeaderTimeMs: 只檢查時間小於此值的行，單位毫秒（預設 25_000＝25 秒）。
    ///   - normalize: 比對歌名／歌手名前的正規化（例如簡繁互轉）；預設不轉換。
    ///   - extraCreditLabels: 額外的標籤名稱（會自動轉小寫、去空白）。
    public init(
        maxHeaderLines: Int = 10,
        maxHeaderTimeMs: Int = 25_000,
        normalize: @escaping @Sendable (String) -> String = { $0 },
        extraCreditLabels: Set<String> = []
    ) {
        self.maxHeaderLines = maxHeaderLines
        self.maxHeaderTimeMs = maxHeaderTimeMs
        self.normalize = normalize
        self.creditLabels = Self.defaultCreditLabels.union(extraCreditLabels.map { Self.foldLabel($0) })
    }

    /// 剝除檔頭中繼行。
    /// - Parameters:
    ///   - lines: 已排序的歌詞行（`LRCParser` 輸出）。
    ///   - title: 目前曲目的歌名（用於比對；可為空字串，空字串不會比對任何東西）。
    ///   - artist: 目前曲目的歌手名（同上）。
    public func strip(_ lines: [LRCLine], title: String, artist: String) -> Result {
        let foldedTitle = fold(title)
        let foldedArtist = fold(artist)

        var cut = 0
        while cut < min(lines.count, maxHeaderLines), lines[cut].timeMs < maxHeaderTimeMs {
            let line = lines[cut]
            guard line.isBlank || isMeta(line.text, title: foldedTitle, artist: foldedArtist) else { break }
            cut += 1
        }

        guard cut > 0 else { return Result(lines: lines, dropped: []) }
        let remaining = Array(lines[cut...])
        guard remaining.contains(where: { !$0.isBlank }) else { return Result(lines: lines, dropped: []) }
        return Result(lines: remaining, dropped: Array(lines[..<cut]))
    }

    // MARK: - 判定

    private func isMeta(_ text: String, title: String, artist: String) -> Bool {
        isIDTagText(text) || isCreditLine(text) || isBareName(text, title: title, artist: artist)
            || isDashNameLine(text, title: title, artist: artist)
    }

    private func isIDTagText(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("["), t.hasSuffix("]"), let colon = t.firstIndex(of: ":") else { return false }
        let key = t[t.index(after: t.startIndex)..<colon].trimmingCharacters(in: .whitespaces).lowercased()
        return Self.idTagKeys.contains(key)
    }

    private func isCreditLine(_ text: String) -> Bool {
        guard let colon = text.firstIndex(where: { $0 == ":" || $0 == "：" }) else { return false }
        let label = Self.foldLabel(String(text[..<colon]))
        return !label.isEmpty && creditLabels.contains(label)
    }

    private func isBareName(_ text: String, title: String, artist: String) -> Bool {
        let t = fold(text)
        guard !t.isEmpty else { return false }
        return t == title || t == artist
    }

    private func isDashNameLine(_ text: String, title: String, artist: String) -> Bool {
        // 以最先出現的分隔符切成左右兩側。
        let found = Self.dashSeparators.compactMap { text.range(of: $0) }
        guard let range = found.min(by: { $0.lowerBound < $1.lowerBound }) else { return false }
        let left = fold(String(text[..<range.lowerBound]))
        let right = fold(String(text[range.upperBound...]))
        guard !left.isEmpty, !right.isEmpty else { return false }
        return [left, right].contains { side in
            Self.sideMatches(side, name: title) || Self.sideMatches(side, name: artist)
        }
    }

    private static func sideMatches(_ side: String, name: String) -> Bool {
        guard !name.isEmpty else { return false }
        if side == name { return true }
        return name.count >= 2 && side.contains(name)
    }

    // MARK: - 正規化

    /// 比對用折疊（先套用注入的 normalize，再轉小寫、去掉空白）；供挑選器比對歌名／歌手名時與檔頭剝除一致。
    public func foldForMatching(_ s: String) -> String { fold(s) }

    /// 比對用正規化：先套用注入的 normalize，再轉小寫並去掉所有空白。
    private func fold(_ s: String) -> String {
        normalize(s).lowercased().filter { !$0.isWhitespace }
    }

    private static func foldLabel(_ s: String) -> String {
        s.lowercased().filter { !$0.isWhitespace }
    }
}
