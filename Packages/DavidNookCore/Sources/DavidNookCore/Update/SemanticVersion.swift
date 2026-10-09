import Foundation

/// 語意化版本（SemVer 2.0.0，https://semver.org/spec/v2.0.0.html）。
///
/// - 接受開頭的 `v`／`V`（GitHub tag 慣例）。
/// - 版本核心 `X.Y.Z` 必須是不含前導 0 的非負整數（規範第 2 條）。
/// - 預覽識別字只可含 `[0-9A-Za-z-]`，數字識別字不可有前導 0（第 9 條）。
/// - 建置後綴 `+…` 不參與排序也不參與相等比較（第 10 條）；解析時直接丟棄。
/// - 排序依第 11 條：核心逐項數值比；有預覽後綴者小於同核心的正式版；
///   預覽識別字逐項比，數字識別字依數值、小於文字識別字，文字識別字依 ASCII 順序，
///   前面都相同時識別字較少者較小。
public struct SemanticVersion: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    /// 預覽識別字（`beta.1` → `["beta", "1"]`）；正式版為空。
    public let prerelease: [String]

    public init(major: Int, minor: Int, patch: Int, prerelease: [String] = []) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    public init?(_ text: String) {
        var s = Substring(text)
        if s.first == "v" || s.first == "V" { s = s.dropFirst() }
        // 去掉建置後綴（但 `+` 之後必須非空且合法）。
        if let plus = s.firstIndex(of: "+") {
            let build = s[s.index(after: plus)...]
            guard Self.isValidIdentifierList(build, numericLeadingZeroAllowed: true) else { return nil }
            s = s[..<plus]
        }
        var core = s
        var pre: [String] = []
        if let dash = s.firstIndex(of: "-") {
            core = s[..<dash]
            let preText = s[s.index(after: dash)...]
            guard Self.isValidIdentifierList(preText, numericLeadingZeroAllowed: false) else { return nil }
            pre = preText.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        }
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let major = Self.parseNumber(parts[0]),
              let minor = Self.parseNumber(parts[1]),
              let patch = Self.parseNumber(parts[2])
        else { return nil }
        self.init(major: major, minor: minor, patch: patch, prerelease: pre)
    }

    public var isPrerelease: Bool { !prerelease.isEmpty }

    /// 標準寫法（無 `v`、無建置後綴）。
    public var description: String {
        let core = "\(major).\(minor).\(patch)"
        return prerelease.isEmpty ? core : core + "-" + prerelease.joined(separator: ".")
    }

    /// 防降版：只有「嚴格較新」才回傳 true。
    public func isStrictlyNewer(than other: SemanticVersion) -> Bool { self > other }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        switch (lhs.prerelease.isEmpty, rhs.prerelease.isEmpty) {
        case (true, true): return false
        case (false, true): return true
        case (true, false): return false
        case (false, false): return comparePrerelease(lhs.prerelease, rhs.prerelease) < 0
        }
    }

    // MARK: - 私有

    private static func parseNumber(_ part: Substring) -> Int? {
        guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        if part.count > 1 && part.first == "0" { return nil }
        return Int(part) // 溢位時回傳 nil
    }

    private static func isNumeric(_ s: String) -> Bool { !s.isEmpty && s.utf8.allSatisfy { $0 >= 0x30 && $0 <= 0x39 } }

    private static func isValidIdentifierList(_ text: Substring, numericLeadingZeroAllowed: Bool) -> Bool {
        guard !text.isEmpty else { return false }
        for id in text.split(separator: ".", omittingEmptySubsequences: false) {
            guard !id.isEmpty else { return false }
            let valid = id.utf8.allSatisfy {
                ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A) || $0 == 0x2D
            }
            guard valid else { return false }
            if !numericLeadingZeroAllowed, isNumeric(String(id)), id.count > 1, id.first == "0" { return false }
        }
        return true
    }

    private static func comparePrerelease(_ a: [String], _ b: [String]) -> Int {
        for (x, y) in zip(a, b) {
            let xn = isNumeric(x), yn = isNumeric(y)
            if xn && yn {
                // 以位數再以字典序比較，避免超長數字溢位。
                if x.count != y.count { return x.count < y.count ? -1 : 1 }
                if x != y { return x < y ? -1 : 1 }
            } else if xn != yn {
                return xn ? -1 : 1 // 數字識別字小於文字識別字
            } else if x != y {
                return Array(x.utf8).lexicographicallyPrecedes(Array(y.utf8)) ? -1 : 1
            }
        }
        if a.count != b.count { return a.count < b.count ? -1 : 1 }
        return 0
    }
}
