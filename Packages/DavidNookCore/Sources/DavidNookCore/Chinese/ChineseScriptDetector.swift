/// 簡/繁專有字的統計（以出現次數計，不去重）。
public struct ScriptEvidence: Equatable, Sendable {
    /// 簡體專有字出現次數。
    public var simplified: Int
    /// 繁體專有字出現次數。
    public var traditional: Int

    public init(simplified: Int = 0, traditional: Int = 0) {
        self.simplified = simplified
        self.traditional = traditional
    }

    /// 專有字總數；0 代表沒有任何證據（中性）。
    public var total: Int { simplified + traditional }
}

/// 以「專有字」統計判斷歌詞是簡體、繁體、混合或中性。
///
/// - 簡體專有字：GB2312 有、Big5 沒有、且 OpenCC s2t 會改它。
/// - 繁體專有字：Big5 有、GB2312 沒有、且 OpenCC t2s 會改它。
/// - 排除 `麽`、`着` 以及兩邊通用易誤判字 `里后干发面台群於`（字集由
///   `Tools/gen_charsets.py` 產生，見 `GeneratedCharsets.swift`）。
///
/// 日文／韓文守衛：日文新字體（国・恋・声・会・残…）同時是 GB2312 有、Big5 沒有的「簡體專有字」，
/// 若不排除，整首日文歌詞會被偵測成簡體／混合並被簡轉繁（国→國、恋→戀）。因此：
/// - 一行裡假名＋諺文占（漢字＋假名＋諺文）≥ 5% → 日韓行：不計入證據，也不該被轉換（見 `isJapaneseOrKorean`）。
/// - 日韓行占「含 CJK 字元的行」≥ 30% → 整份視為日文／韓文歌詞，`.neutral`。
/// - 其餘（例如簡體華語歌夾一句日文）→ 日韓行不計入證據，整首仍依華語行判斷。
///
/// 判斷規則（以專有字總數為分母，整數比較避免浮點誤差）：
/// - 沒有任何專有字 → `.neutral`
/// - 繁體專有字佔比 ≤ 3% → `.simplified`
/// - 簡體專有字佔比 ≤ 3% → `.traditional`
/// - 其他 → `.mixed`
///
/// 標題不可靠，請對「全文歌詞」判斷；歌名／歌手名不應進入此偵測（也不應被轉換）。
public struct ChineseScriptDetector: Sendable {
    /// 少數派占比上限（≤ 此值視為雜訊）：3%。
    public static let minorityPercentLimit = 3
    /// 一行裡假名＋諺文占 CJK 字元（漢字＋假名＋諺文）的百分比下限（≥ 此值視為日韓行）：5%。
    public static let kanaHangulLinePercentLimit = 5
    /// 日韓行占「含 CJK 字元的行」的百分比下限（≥ 此值整份視為日韓歌詞）：30%。
    public static let japaneseKoreanDocumentPercentLimit = 30

    public init() {}

    /// 這一行是不是日文／韓文：至少有一個假名或諺文，且假名＋諺文 ≥ 5% 的 CJK 字元。
    /// 日韓行不是中文，不該被簡繁轉換（日文新字體不是簡體）。
    public func isJapaneseOrKorean(_ line: String) -> Bool {
        let counts = Self.cjkCounts(line)
        return Self.isJapaneseOrKorean(counts)
    }

    private struct CJKCounts {
        var ideographs = 0
        var kanaHangul = 0
        var hasCJK: Bool { ideographs + kanaHangul > 0 }
    }

    private static func cjkCounts(_ line: String) -> CJKCounts {
        var counts = CJKCounts()
        for scalar in line.unicodeScalars {
            if isKanaOrHangul(scalar) {
                counts.kanaHangul += 1
            } else if isIdeograph(scalar) {
                counts.ideographs += 1
            }
        }
        return counts
    }

    private static func isJapaneseOrKorean(_ counts: CJKCounts) -> Bool {
        counts.kanaHangul > 0
            && counts.kanaHangul * 100 >= kanaHangulLinePercentLimit * (counts.ideographs + counts.kanaHangul)
    }

    /// 平假名、片假名（含長音符，不含中點）、半形片假名、諺文音節與字母。
    private static func isKanaOrHangul(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x3041...0x3096, 0x309D...0x309F, 0x30A1...0x30FA, 0x30FD...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9D:
            return true   // 假名
        case 0xAC00...0xD7AF, 0x1100...0x11FF, 0x3130...0x318F, 0xA960...0xA97F, 0xD7B0...0xD7FF:
            return true   // 諺文
        default:
            return false
        }
    }

    private static func isIdeograph(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0xF900...0xFAFF, 0x20000...0x2FA1F: return true
        default: return false
        }
    }

    // MARK: - 統計

    /// 統計一段文字中的簡體／繁體專有字出現次數。
    public func evidence(in text: String) -> ScriptEvidence {
        var evidence = ScriptEvidence()
        let charsets = ScriptCharsets.shared
        for scalar in text.unicodeScalars {
            if charsets.simplified.contains(scalar) {
                evidence.simplified += 1
            } else if charsets.traditional.contains(scalar) {
                evidence.traditional += 1
            }
        }
        return evidence
    }

    /// 由統計值得出結論（純算術）。
    public static func classify(_ evidence: ScriptEvidence) -> LyricsScript {
        let total = evidence.total
        if total == 0 { return .neutral }
        if evidence.traditional * 100 <= minorityPercentLimit * total { return .simplified }
        if evidence.simplified * 100 <= minorityPercentLimit * total { return .traditional }
        return .mixed
    }

    // MARK: - 判斷

    /// 判斷一段文字（整首歌詞串成一個字串，或單行）。換行會被當成行分隔（日韓守衛逐行判斷）。
    public func detect(_ text: String) -> LyricsScript {
        detect(lines: text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init))
    }

    /// 判斷整首歌詞（多行）。空行自然不貢獻證據；`skippingLineIndices` 為呼叫端要略過的
    /// 中繼行索引（例如殘留的「作詞：…」行），這些行不計入統計。超出範圍的索引會被忽略。
    /// 日韓行（見 `isJapaneseOrKorean`）不計入證據；日韓行占比過高時整份為 `.neutral`。
    public func detect(lines: [String], skippingLineIndices: Set<Int> = []) -> LyricsScript {
        var total = ScriptEvidence()
        var cjkLines = 0
        var japaneseKoreanLines = 0
        for (index, line) in lines.enumerated() where !skippingLineIndices.contains(index) {
            if line.isEmpty { continue }
            let counts = Self.cjkCounts(line)
            if counts.hasCJK { cjkLines += 1 }
            if Self.isJapaneseOrKorean(counts) {
                japaneseKoreanLines += 1
                continue
            }
            let lineEvidence = evidence(in: line)
            total.simplified += lineEvidence.simplified
            total.traditional += lineEvidence.traditional
        }
        if cjkLines > 0, japaneseKoreanLines * 100 >= Self.japaneseKoreanDocumentPercentLimit * cjkLines {
            return .neutral
        }
        return Self.classify(total)
    }

    /// 逐行判斷（歌詞整體為 `.mixed` 時使用）。沒有專有字的行為 `.neutral`，呼叫端不應轉換。
    public func detectEachLine(_ lines: [String]) -> [LyricsScript] {
        lines.map { detect($0) }
    }
}

/// 把產生的字集字串轉成查找表（只建一次）。
private final class ScriptCharsets: Sendable {
    static let shared = ScriptCharsets()

    let simplified: Set<Unicode.Scalar>
    let traditional: Set<Unicode.Scalar>

    private init() {
        simplified = Set(GeneratedCharsets.simplifiedOnly.unicodeScalars)
        traditional = Set(GeneratedCharsets.traditionalOnly.unicodeScalars)
    }
}
