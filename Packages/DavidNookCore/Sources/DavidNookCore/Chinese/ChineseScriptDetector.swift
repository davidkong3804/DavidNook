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

    public init() {}

    /// （紅燈階段的占位實作：尚未實作日韓守衛。）
    public func isJapaneseOrKorean(_ line: String) -> Bool { false }

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

    /// 判斷一段文字（整首歌詞串成一個字串，或單行）。
    public func detect(_ text: String) -> LyricsScript {
        Self.classify(evidence(in: text))
    }

    /// 判斷整首歌詞（多行）。空行自然不貢獻證據；`skippingLineIndices` 為呼叫端要略過的
    /// 中繼行索引（例如殘留的「作詞：…」行），這些行不計入統計。超出範圍的索引會被忽略。
    public func detect(lines: [String], skippingLineIndices: Set<Int> = []) -> LyricsScript {
        var total = ScriptEvidence()
        for (index, line) in lines.enumerated() where !skippingLineIndices.contains(index) {
            if line.isEmpty { continue }
            let lineEvidence = evidence(in: line)
            total.simplified += lineEvidence.simplified
            total.traditional += lineEvidence.traditional
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
