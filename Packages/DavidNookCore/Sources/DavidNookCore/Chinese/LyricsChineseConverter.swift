import Foundation
import OpenCC

/// 歌詞轉換模式（對應 SwiftyOpenCC 的選項組合）。
public enum LyricsConversionMode: String, Sendable, CaseIterable {
    /// 簡→繁字形＋台灣字形（`[.traditionalize, .twStandard]`），**不含**台灣慣用詞。歌詞預設。
    /// 套用覆寫表。只應用於簡體文字：對原生繁體會誤改（鄰里→鄰裡、台灣→臺灣）。
    case conservative

    /// 同上再加台灣慣用詞層（`[.traditionalize, .twStandard, .twIdiom]`，等同 s2twp）：
    /// 軟件→軟體、鼠標→滑鼠、信息→資訊；但也會把「支持」改成「支援」、「打开」改成「開啟」，
    /// 所以只在使用者於設定中開啟時使用。套用覆寫表。
    case taiwanIdioms

    /// 只做台灣變體正規化（`[.twStandard]`，t2tw）：用於原生繁體歌詞。
    /// 不改「台灣」「鄰里」「裡面」；會把 着→著、裏→裡、爲→為 等變體統一成台灣字形。
    /// 轉換器本身不套用覆寫表（表內的鍵是簡體詞）；`LyricsLocalizer` 會另外在這之前套用覆寫表中
    /// 「鍵含簡體字形」的條目（見 `LyricsOverrides.restrictedToSimplifiedKeys`），修殘留的「重复」。
    case variantsOnly

    /// 繁→簡（t2s，含台灣字形反查，等同 OpenCC 的 tw2s，**不含**慣用詞）。
    /// 只用於產生 LRCLIB 的查詢變體（繁體歌名／歌手名 → 簡體寫法）；**不可用於顯示**，也不套用覆寫表
    /// （覆寫表的鍵是簡體詞、值是繁體詞，方向相反）。
    case traditionalToSimplified
}

/// 包裝 SwiftyOpenCC 的歌詞轉換器：先套覆寫表，再交給 OpenCC。
///
/// 建立實例需載入字典（約 15–30 ms），請重複使用同一個實例（`cached(_:)`），不要每行重建。
/// 實例不可變、可多執行緒共用。
///
/// - Important: 只用於**歌詞內文**。歌名、歌手名不得經過此轉換（顯示原樣）。
public final class LyricsChineseConverter: @unchecked Sendable {
    public let mode: LyricsConversionMode

    private let converter: ChineseConverter
    /// `.variantsOnly` 為 nil（不套覆寫表）。
    private let overrides: LyricsOverrides?

    public init(mode: LyricsConversionMode, overrides: LyricsOverrides = .bundled) throws {
        self.mode = mode
        switch mode {
        case .conservative:
            converter = try ChineseConverter(options: [.traditionalize, .twStandard])
            self.overrides = overrides
        case .taiwanIdioms:
            converter = try ChineseConverter(options: [.traditionalize, .twStandard, .twIdiom])
            self.overrides = overrides
        case .variantsOnly:
            converter = try ChineseConverter(options: [.twStandard])
            self.overrides = nil
        case .traditionalToSimplified:
            // tw2s：先把台灣字形還原（裡→裏、著→著 等），再繁→簡；不含慣用詞（twIdiom）。
            converter = try ChineseConverter(options: [.simplify, .twStandard])
            self.overrides = nil
        }
    }

    public func convert(_ text: String) -> String {
        guard let overrides else { return converter.convert(text) }
        return overrides.apply(to: text) { converter.convert($0) }
    }

    // MARK: - 快取（使用內建覆寫表）

    private static let cache = ConverterCache()

    /// 取得（並快取）使用內建覆寫表的轉換器；每個模式在程式生命週期內只建立一次。
    public static func cached(_ mode: LyricsConversionMode) throws -> LyricsChineseConverter {
        try cache.converter(for: mode)
    }
}

private final class ConverterCache: @unchecked Sendable {
    private let lock = NSLock()
    private var converters: [LyricsConversionMode: LyricsChineseConverter] = [:]

    func converter(for mode: LyricsConversionMode) throws -> LyricsChineseConverter {
        lock.lock()
        defer { lock.unlock() }
        if let existing = converters[mode] { return existing }
        let created = try LyricsChineseConverter(mode: mode)
        converters[mode] = created
        return created
    }
}
