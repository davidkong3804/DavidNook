// STUB（紅燈階段）：只有 API 形狀，尚無實作。

/// 簡/繁專有字的統計（以出現次數計，不去重）。
public struct ScriptEvidence: Equatable, Sendable {
    public var simplified: Int
    public var traditional: Int
    public init(simplified: Int = 0, traditional: Int = 0) {
        self.simplified = simplified
        self.traditional = traditional
    }
}

public struct ChineseScriptDetector: Sendable {
    public init() {}

    public func evidence(in text: String) -> ScriptEvidence { ScriptEvidence() }

    public static func classify(_ evidence: ScriptEvidence) -> LyricsScript { .neutral }

    public func detect(_ text: String) -> LyricsScript { .neutral }

    public func detect(lines: [String], skippingLineIndices: Set<Int> = []) -> LyricsScript { .neutral }

    public func detectEachLine(_ lines: [String]) -> [LyricsScript] { lines.map { _ in .neutral } }
}
