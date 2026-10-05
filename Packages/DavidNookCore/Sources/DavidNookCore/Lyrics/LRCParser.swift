import Foundation

/// LRC 的一行歌詞。
public struct LRCLine: Equatable, Hashable, Sendable, Codable {
    /// 該行開始時間，單位：毫秒（檔案內的原始時間，未套用任何偏移）。
    public var timeMs: Int
    /// 歌詞文字（已去除前後空白與 Enhanced-LRC 行內時間標籤）。
    /// 空字串代表「間奏／空白」標記：保留時間點，讓顯示端知道前一行已經結束。
    public var text: String

    public init(timeMs: Int, text: String) {
        self.timeMs = timeMs
        self.text = text
    }

    /// 開始時間，單位：秒。
    public var time: TimeInterval { Double(timeMs) / 1000 }

    /// 是否為空白（間奏）標記行。
    public var isBlank: Bool { text.isEmpty }
}

/// LRC 解析結果。
public struct LRCDocument: Equatable, Sendable, Codable {
    /// 已依時間排序（穩定）的歌詞行；不含 ID tag。
    public var lines: [LRCLine]
    /// ID tag（`[ar:]`、`[ti:]`、`[al:]`、`[by:]`、`[length:]`、`[offset:]`…）；key 一律轉小寫，value 去除前後空白。
    public var metadata: [String: String]
    /// `[offset:±ms]` 的值，單位：毫秒；沒有或格式錯誤為 0。
    ///
    /// 方向（LRC 慣例）：**正值＝歌詞提早顯示**，也就是第 N 行在「播放位置 + offset ≥ 該行時間」時成為目前行。
    /// 解析階段只記錄、不改寫 `lines` 的時間，因此解析結果與使用者偏移無關，可安全快取。
    /// 實際套用見 `LyricsTimeline`。
    public var offsetMs: Int

    public init(lines: [LRCLine] = [], metadata: [String: String] = [:], offsetMs: Int = 0) {
        self.lines = lines
        self.metadata = metadata
        self.offsetMs = offsetMs
    }
}

/// LRC 歌詞解析器（純函式，不連網、不丟錯；壞掉的行一律略過）。
///
/// 支援：
/// - 時間標籤 `[mm:ss.xx]`、`[mm:ss.xxx]`、`[mm:ss]`（分鐘可超過 59、秒 0–59、小數 1 位以上，超過 3 位截斷到毫秒）。
/// - 同一行多個時間標籤 `[00:12.00][00:45.10]歌詞` 展開成多行。
/// - ID tag 解析成 `metadata`，不當歌詞；`[offset:]` 另存於 `offsetMs`（方向見 `LRCDocument.offsetMs`）。
/// - CRLF／CR 換行、開頭 BOM。
/// - 行內 Enhanced-LRC `<mm:ss.xxx>` 標籤一律剝除。
///
/// 空白（間奏）行策略（輸出已整理）：
/// 1. 文字為空的時間戳行會保留，作為「前一行已結束」的標記（尾端的 `[03:25.72]` 也保留）。
/// 2. 連續多個空白行只保留時間最早的那一個。
/// 3. 與非空白行同一時間戳的空白行直接丟棄（會被立刻取代）。
/// 4. 檔頭（第一句歌詞之前）的空白行丟棄：「還沒有目前行」本來就由 `LyricsTimeline` 回傳 nil 表示。
///
/// 輸出依時間排序，時間相同者維持檔案內的出現順序（穩定）。
public enum LRCParser {

    public static func parse(_ text: String) -> LRCDocument {
        var metadata: [String: String] = [:]
        var offsetMs = 0
        var entries: [(order: Int, line: LRCLine)] = []

        let source = text.drop(while: { $0 == "\u{FEFF}" })
        // Swift 的 Character 會把 "\r\n" 視為單一換行字元，CR、LF、CRLF 都能正確切開。
        for rawLine in source.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }) {
            parseLine(Substring(rawLine), metadata: &metadata, offsetMs: &offsetMs) { ms, lineText in
                entries.append((entries.count, LRCLine(timeMs: ms, text: lineText)))
            }
        }

        entries.sort { a, b in
            a.line.timeMs != b.line.timeMs ? a.line.timeMs < b.line.timeMs : a.order < b.order
        }
        return LRCDocument(lines: tidy(entries.map(\.line)), metadata: metadata, offsetMs: offsetMs)
    }

    // MARK: - 單行解析

    private static func parseLine(
        _ line: Substring,
        metadata: inout [String: String],
        offsetMs: inout Int,
        emit: (Int, String) -> Void
    ) {
        var cursor = line.drop(while: { $0.isWhitespace })
        var times: [Int] = []

        while cursor.first == "[" {
            guard let close = cursor.firstIndex(of: "]") else { break }
            let inner = String(cursor[cursor.index(after: cursor.startIndex)..<close])
            if let ms = parseTimeTag(inner) {
                times.append(ms)
                cursor = cursor[cursor.index(after: close)...]
                continue
            }
            if times.isEmpty, let (key, value) = parseIDTag(inner) {
                metadata[key] = value
                if key == "offset", let parsed = parseOffset(value) { offsetMs = parsed }
                return
            }
            break
        }

        guard !times.isEmpty else { return }
        let lyric = cleanText(cursor)
        for ms in times { emit(ms, lyric) }
    }

    /// 解析 `mm:ss`、`mm:ss.x…`；失敗回傳 nil。單位：毫秒。
    static func parseTimeTag(_ raw: String) -> Int? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        let u = Array(s.utf8)
        var i = 0

        var minutes = 0
        var digits = 0
        while i < u.count, isDigit(u[i]) {
            minutes = minutes * 10 + Int(u[i] - 48)
            i += 1
            digits += 1
            if digits > 6 { return nil }
        }
        guard digits >= 1, i < u.count, u[i] == 58 /* : */ else { return nil }
        i += 1

        var seconds = 0
        digits = 0
        while i < u.count, isDigit(u[i]), digits < 2 {
            seconds = seconds * 10 + Int(u[i] - 48)
            i += 1
            digits += 1
        }
        guard digits >= 1, seconds < 60 else { return nil }

        var fraction = 0
        if i < u.count {
            guard u[i] == 46 /* . */ else { return nil }
            i += 1
            var kept = 0
            var total = 0
            while i < u.count, isDigit(u[i]) {
                if kept < 3 {
                    fraction = fraction * 10 + Int(u[i] - 48)
                    kept += 1
                }
                total += 1
                i += 1
            }
            guard total >= 1, i == u.count else { return nil }
            while kept < 3 {
                fraction *= 10
                kept += 1
            }
        }
        return (minutes * 60 + seconds) * 1000 + fraction
    }

    private static func isDigit(_ b: UInt8) -> Bool { b >= 48 && b <= 57 }

    /// `[key:value]` 形式的 ID tag；key 必須以字母或 # 開頭。
    private static func parseIDTag(_ inner: String) -> (String, String)? {
        guard let colon = inner.firstIndex(of: ":") else { return nil }
        let key = inner[..<colon].trimmingCharacters(in: .whitespaces)
        guard let first = key.first, first.isLetter || first == "#" else { return nil }
        guard key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "#" }) else { return nil }
        let value = inner[inner.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        return (key.lowercased(), value)
    }

    private static func parseOffset(_ value: String) -> Int? {
        Int(value.trimmingCharacters(in: .whitespaces))
    }

    /// 剝除行內 Enhanced-LRC `<mm:ss.xxx>` 標籤並去除前後空白。
    private static func cleanText(_ s: Substring) -> String {
        var out = ""
        var index = s.startIndex
        while index < s.endIndex {
            let ch = s[index]
            if ch == "<",
               let close = s[index...].firstIndex(of: ">"),
               parseTimeTag(String(s[s.index(after: index)..<close])) != nil {
                index = s.index(after: close)
                continue
            }
            out.append(ch)
            index = s.index(after: index)
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 空白行整理

    private static func tidy(_ sorted: [LRCLine]) -> [LRCLine] {
        let textTimes = Set(sorted.lazy.filter { !$0.isBlank }.map(\.timeMs))
        var out: [LRCLine] = []
        for line in sorted {
            if line.isBlank {
                if textTimes.contains(line.timeMs) { continue }   // 規則 3
                if out.isEmpty { continue }                       // 規則 4
                if out.last?.isBlank == true { continue }         // 規則 2
            }
            out.append(line)
        }
        return out
    }
}
