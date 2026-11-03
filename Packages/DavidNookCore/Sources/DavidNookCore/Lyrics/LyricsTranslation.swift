import Foundation

/// 支援中文對照的歌詞原文語言（目前只有日文、韓文）。
public enum LyricsSourceLanguage: String, Codable, Sendable, Equatable {
    case japanese
    case korean
}

/// 一首歌的中文翻譯快取（與歌詞行一一對應；空字串＝該行沒有翻譯，例如間奏）。
public struct TranslationCacheEntry: Codable, Equatable, Sendable {
    public var source: LyricsSourceLanguage
    public var lines: [String]

    public init(source: LyricsSourceLanguage, lines: [String]) {
        self.source = source
        self.lines = lines
    }
}

/// 翻譯快取儲存抽象（以曲目鍵存取）。磁碟版本是 `FileLyricsCacheStore`，與歌詞快取放在同一個資料夾，
/// 所以「清除快取」會一起清掉。
public protocol TranslationCacheStore: Sendable {
    func translation(for key: TrackKey) -> TranslationCacheEntry?
    func storeTranslation(_ entry: TranslationCacheEntry, for key: TrackKey)
}

/// 記憶體翻譯快取（執行緒安全）；磁碟快取建立失敗時的備援。
public final class MemoryTranslationCacheStore: TranslationCacheStore, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [TrackKey: TranslationCacheEntry] = [:]

    public init() {}

    public func translation(for key: TrackKey) -> TranslationCacheEntry? {
        lock.withLock { entries[key] }
    }

    public func storeTranslation(_ entry: TranslationCacheEntry, for key: TrackKey) {
        lock.withLock { entries[key] = entry }
    }
}

/// 日文／韓文歌詞的中文對照：判斷要不要翻、翻哪些行、結果怎麼放回去。純邏輯，不含任何翻譯引擎。
///
/// 中文翻譯有三個來源，依序：
/// 1. LRCLIB 的版本本身就是雙語檔，附有中文翻譯（`PickedLyrics.embeddedTranslations`）。
/// 2. 之前翻過的快取（`TranslationCacheEntry`）。
/// 3. 現場翻譯（App 端用系統的離線翻譯；歌詞不離開這台 Mac）。
public enum LyricsTranslation {

    /// 要送去翻譯的一行。
    public struct Request: Equatable, Sendable {
        /// 該行在歌詞中的索引。
        public var index: Int
        public var text: String

        public init(index: Int, text: String) {
            self.index = index
            self.text = text
        }
    }

    /// 這份歌詞該怎麼取得中文翻譯。
    public enum Plan: Equatable, Sendable {
        /// 不用翻：不是日文／韓文歌，或目前不允許翻譯。
        case none
        case useEmbedded([String])
        case useCached([String])
        case translate(LyricsSourceLanguage, [Request])
    }

    /// 歌詞是日文還是韓文；不是回傳 nil。
    public static func sourceLanguage(of lines: [String]) -> LyricsSourceLanguage? {
        ChineseScriptDetector().japaneseOrKoreanLanguage(of: lines)
    }

    /// 這行是不是中文翻譯（有漢字、沒有假名或諺文）。
    public static func isChineseTranslation(_ text: String) -> Bool {
        ChineseScriptDetector().isChineseText(text)
    }

    /// 要翻譯的行：略過空白行，保留原本的索引。
    public static func requests(for lines: [String]) -> [Request] {
        lines.enumerated().compactMap { index, text in
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : Request(index: index, text: text)
        }
    }

    /// 把翻譯結果依索引放回與歌詞等長的陣列（沒有請求的行是空字串）。結果筆數不對回傳 nil。
    public static func align(count: Int, requests: [Request], translated: [String]) -> [String]? {
        guard translated.count == requests.count else { return nil }
        var result = [String](repeating: "", count: count)
        for (request, text) in zip(requests, translated) where result.indices.contains(request.index) {
            result[request.index] = text
        }
        return result
    }

    /// 決定翻譯來源。`embedded`／`cached` 的筆數必須與歌詞行數相同才採用（換了別的 LRCLIB 版本就不能沿用）。
    /// - Parameter allowTranslating: false 時只會用現成的（內嵌或快取），不會要求現場翻譯（「只顯示原文」開著時）。
    public static func plan(
        lines: [String], embedded: [String]?, cached: TranslationCacheEntry?, allowTranslating: Bool
    ) -> Plan {
        guard let language = sourceLanguage(of: lines) else { return .none }
        if let embedded, embedded.count == lines.count { return .useEmbedded(embedded) }
        if let cached, cached.source == language, cached.lines.count == lines.count { return .useCached(cached.lines) }
        guard allowTranslating else { return .none }
        let pending = requests(for: lines)
        return pending.isEmpty ? .none : .translate(language, pending)
    }
}
