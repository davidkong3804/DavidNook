import Foundation

/// 小型的 LCS 對齊工具（歌詞單行最長約百字，O(n·m) 足夠）。
enum TextDiff {

    /// 最長共同子序列的配對索引（遞增）。
    static func lcsPairs<T: Equatable>(_ a: [T], _ b: [T]) -> [(Int, Int)] {
        let n = a.count, m = b.count
        if n == 0 || m == 0 { return [] }
        var table = [Int](repeating: 0, count: (n + 1) * (m + 1))
        let w = m + 1
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                table[i * w + j] = a[i] == b[j]
                    ? table[(i + 1) * w + j + 1] + 1
                    : max(table[(i + 1) * w + j], table[i * w + j + 1])
            }
        }
        var pairs: [(Int, Int)] = []
        var i = 0, j = 0
        while i < n, j < m {
            if a[i] == b[j] {
                pairs.append((i, j)); i += 1; j += 1
            } else if table[(i + 1) * w + j] >= table[i * w + j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return pairs
    }

    /// 一行轉換前後的變更：`from → to`（可能是多字片段）。
    struct Change: Equatable {
        var from: String
        var to: String
    }

    /// 轉換前後的字元層級差異（以 Character 為單位）。回傳每個「連續變更片段」，
    /// 長度相同的片段逐字拆成單字變更（例如 `发→髮`），長度不同的整段保留。
    static func changes(before: String, after: String) -> [Change] {
        if before == after { return [] }
        let a = Array(before), b = Array(after)
        let pairs = lcsPairs(a, b)
        var result: [Change] = []
        var i = 0, j = 0
        func flush(_ i1: Int, _ j1: Int) {
            guard i < i1 || j < j1 else { return }
            let lhs = Array(a[i..<i1]), rhs = Array(b[j..<j1])
            if lhs.count == rhs.count {
                for (x, y) in zip(lhs, rhs) { result.append(Change(from: String(x), to: String(y))) }
            } else {
                result.append(Change(from: String(lhs), to: String(rhs)))
            }
        }
        for (pi, pj) in pairs {
            flush(pi, pj)
            i = pi + 1; j = pj + 1
        }
        flush(a.count, b.count)
        return result
    }
}

enum CJK {
    /// 漢字（含擴充 A、相容漢字）。
    static func isIdeograph(_ s: Unicode.Scalar) -> Bool {
        let v = s.value
        return (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) || (0xF900...0xFAFF).contains(v)
            || (0x20000...0x2FA1F).contains(v)
    }

    static func isIdeograph(_ c: Character) -> Bool {
        c.unicodeScalars.count == 1 && isIdeograph(c.unicodeScalars.first!)
    }

    /// 假名（平假名、片假名、半形片假名，不含中點與長音符之外的標點）。
    static func isKana(_ s: Unicode.Scalar) -> Bool {
        let v = s.value
        return (0x3041...0x3096).contains(v) || (0x309D...0x309F).contains(v) || (0x30A1...0x30FA).contains(v)
            || (0x30FD...0x30FF).contains(v) || (0x31F0...0x31FF).contains(v) || (0xFF66...0xFF9D).contains(v)
    }

    static func isHangul(_ s: Unicode.Scalar) -> Bool {
        let v = s.value
        return (0xAC00...0xD7AF).contains(v) || (0x1100...0x11FF).contains(v) || (0x3130...0x318F).contains(v)
            || (0xA960...0xA97F).contains(v) || (0xD7B0...0xD7FF).contains(v)
    }
}
