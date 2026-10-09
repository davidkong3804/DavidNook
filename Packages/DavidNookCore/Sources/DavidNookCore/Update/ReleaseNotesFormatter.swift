import Foundation

/// 把 GitHub release 內文（Markdown）轉成「只能當純文字顯示」的短摘要。
/// 目的：發行說明來自網路，不可信——不渲染 Markdown／HTML、不保留連結目標、去掉控制與雙向覆寫字元、限制長度。
public enum ReleaseNotesFormatter {
    public static func plainSummary(_ markdown: String, maxLength: Int) -> String {
        var text = markdown.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")

        // 整行的校驗碼說明（SHA-256：`…`）不放進摘要。
        text = text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                let lower = line.lowercased()
                return !(lower.contains("sha-256") || lower.contains("sha256"))
            }
            .joined(separator: "\n")

        // <script>/<style> 連同內容一起移除，其餘 HTML 標籤只去掉標籤本身。
        text = text.replacingOccurrences(of: "(?is)<(script|style)\\b.*?</\\1\\s*>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?s)<[^>]*>", with: "", options: .regularExpression)
        // 圖片整個丟掉；連結只留文字。
        text = text.replacingOccurrences(of: "!\\[[^\\]]*\\]\\([^)]*\\)", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\[([^\\]]*)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
        // 標題與強調記號。
        text = text.replacingOccurrences(of: "(?m)^\\s{0,3}#{1,6}\\s*", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(\\*\\*|__|`|~~)", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?<![\\w])[_*](?=\\S)|(?<=\\S)[_*](?![\\w])", with: "", options: .regularExpression)

        // 過濾控制、格式與雙向覆寫字元（保留換行；Tab 變空白）。
        var cleaned = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if scalar == "\n" { cleaned.append(scalar); continue }
            if scalar == "\t" { cleaned.append(" "); continue }
            switch scalar.properties.generalCategory {
            case .control, .format, .surrogate, .privateUse, .unassigned, .lineSeparator, .paragraphSeparator:
                continue
            default:
                cleaned.append(scalar)
            }
        }
        text = String(cleaned)

        // 空白整理：每行去頭尾、連續 3 個以上換行壓成 1 個空行。
        text = text.split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard maxLength > 0 else { return "" }
        if text.count > maxLength {
            text = String(text.prefix(maxLength - 1)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }
        return text
    }
}
