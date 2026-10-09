import Foundation

/// 解壓前先看 zip 內有哪些項目（只讀中央目錄，不展開內容），擋掉路徑穿越與非預期的頂層項目。
public enum ZipEntryListing {
    public enum Failure: Error, Equatable, Sendable {
        case notAZip
        case unsafeEntry(String)
        case empty
    }

    /// 回傳 zip 中央目錄裡所有項目名稱。
    public static func entryNames(of file: URL) throws -> [String] {
        let data: Data
        do { data = try Data(contentsOf: file, options: .mappedIfSafe) } catch { throw Failure.notAZip }
        // 尋找 End Of Central Directory（簽章 0x06054b50），最遠在檔尾往前 22 + 65535 位元組。
        guard data.count >= 22 else { throw Failure.notAZip }
        let bytes = [UInt8](data)
        let lowest = max(0, bytes.count - 22 - 65535)
        var eocd = -1
        var i = bytes.count - 22
        while i >= lowest {
            if bytes[i] == 0x50, bytes[i + 1] == 0x4b, bytes[i + 2] == 0x05, bytes[i + 3] == 0x06 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw Failure.notAZip }
        func u16(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        let total = u16(eocd + 10)
        let cdSize = u32(eocd + 12)
        let cdOffset = u32(eocd + 16)
        // Zip64 或欄位飽和：不支援（我們自己的發布流程不會產生）。
        guard total != 0xFFFF, cdSize != 0xFFFF_FFFF, cdOffset != 0xFFFF_FFFF,
              cdOffset + cdSize <= eocd else { throw Failure.notAZip }

        var names: [String] = []
        var p = cdOffset
        for _ in 0..<total {
            guard p + 46 <= bytes.count, bytes[p] == 0x50, bytes[p + 1] == 0x4b, bytes[p + 2] == 0x01, bytes[p + 3] == 0x02 else {
                throw Failure.notAZip
            }
            let nameLength = u16(p + 28), extraLength = u16(p + 30), commentLength = u16(p + 32)
            guard p + 46 + nameLength <= bytes.count else { throw Failure.notAZip }
            names.append(String(decoding: bytes[(p + 46)..<(p + 46 + nameLength)], as: UTF8.self))
            p += 46 + nameLength + extraLength + commentLength
        }
        return names
    }

    /// 每個項目都必須是 `<appName>/…` 的相對路徑：不得有絕對路徑、`..`、反斜線、NUL 或其他頂層項目。
    public static func validateLayout(_ names: [String], appName: String) throws {
        guard !names.isEmpty else { throw Failure.empty }
        for name in names {
            let components = name.split(separator: "/", omittingEmptySubsequences: false)
            let bad = name.hasPrefix("/") || name.contains("\\") || name.contains("\u{0}")
                || components.contains("..") || components.first.map(String.init) != appName
            if bad { throw Failure.unsafeEntry(name) }
        }
    }
}
