import Foundation

/// 歌詞在地化（簡轉繁）選項。
public struct LyricsLocalizationOptions: Sendable, Equatable {
    /// 簡體歌詞是否啟用台灣慣用詞層（軟件→軟體、信息→資訊…）。預設關閉：慣用詞層對歌詞有風險
    /// （支持→支援、打开→開啟）。原生繁體歌詞不受此選項影響。
    public var useTaiwanIdioms: Bool

    public init(useTaiwanIdioms: Bool = false) {
        self.useTaiwanIdioms = useTaiwanIdioms
    }
}

/// `LyricsLocalizer.localize` 的結果。
public struct LocalizedLyrics: Equatable, Sendable {
    /// 轉換後的行，與輸入的行數、順序完全一致（呼叫端可直接與時間戳對齊）。
    public let lines: [String]
    /// 全文的字體判斷。
    public let script: LyricsScript
    /// 逐行判斷結果；僅在 `script == .mixed` 時有值，否則為 nil。
    public let lineScripts: [LyricsScript]?
    /// 整篇套用的轉換模式；`.neutral` 與 `.mixed`（逐行各自決定）時為 nil。
    public let appliedMode: LyricsConversionMode?
}

/// 歌詞簡繁整合管線：偵測全文字體 → 選轉換模式 → 轉換。
///
/// - `simplified`：全部以 `.conservative`（使用者開啟慣用詞時 `.taiwanIdioms`）轉換。
/// - `traditional`：全部以 `.variantsOnly`（只做台灣變體正規化，不改原生繁體用字）。
/// - `mixed`：逐行判斷——簡體行轉換、繁體行 variantsOnly、中性行（沒有專有字，如英文）原樣。
///   一行內簡繁並存時，視為簡體行轉換（簡體殘留比誤改罕見的繁體用字更顯眼）。
/// - `neutral`：原樣。
///
/// - Important: **只傳入歌詞內文的行**。歌名、歌手名等中繼資料不得進入此管線——它們不經過轉換，
///   以播放器提供的原樣顯示（簡轉繁可能把人名/曲名改錯，標題也不是可靠的字體證據）。
public final class LyricsLocalizer: @unchecked Sendable {
    /// 使用內建覆寫表與轉換器快取的共用實例（App 內建議用它）。
    public static let shared = LyricsLocalizer()

    private let detector: ChineseScriptDetector
    private let converterProvider: (LyricsConversionMode) throws -> LyricsChineseConverter

    /// 使用內建覆寫表；轉換器由 `LyricsChineseConverter.cached` 全域快取。
    public init(detector: ChineseScriptDetector = ChineseScriptDetector()) {
        self.detector = detector
        self.converterProvider = { try LyricsChineseConverter.cached($0) }
    }

    /// 使用自訂覆寫表（主要供測試）；轉換器在此實例內快取。
    public init(overrides: LyricsOverrides, detector: ChineseScriptDetector = ChineseScriptDetector()) {
        self.detector = detector
        let store = LocalConverterStore(overrides: overrides)
        self.converterProvider = { try store.converter(for: $0) }
    }

    /// - Parameters:
    ///   - lines: 已解析的歌詞行（只含內文，不含歌名/歌手；空行允許，會原樣保留）。
    ///   - options: 轉換選項。
    ///   - skippingDetectionOfLineIndices: 呼叫端認定為中繼行的索引（例如殘留的「作詞：…」）。
    ///     這些行**不計入字體偵測**，但仍會依整篇（或 mixed 時依該行）的結果被轉換。
    /// - Throws: 轉換器初始化失敗（字典資源缺失，屬封裝錯誤）。
    public func localize(
        lines: [String],
        options: LyricsLocalizationOptions = LyricsLocalizationOptions(),
        skippingDetectionOfLineIndices: Set<Int> = []
    ) throws -> LocalizedLyrics {
        let script = detector.detect(lines: lines, skippingLineIndices: skippingDetectionOfLineIndices)
        let simplifiedMode: LyricsConversionMode = options.useTaiwanIdioms ? .taiwanIdioms : .conservative

        switch script {
        case .neutral:
            return LocalizedLyrics(lines: lines, script: .neutral, lineScripts: nil, appliedMode: nil)

        case .simplified:
            let converter = try converterProvider(simplifiedMode)
            return LocalizedLyrics(
                lines: lines.map { $0.isEmpty ? $0 : converter.convert($0) },
                script: .simplified, lineScripts: nil, appliedMode: simplifiedMode
            )

        case .traditional:
            let converter = try converterProvider(.variantsOnly)
            return LocalizedLyrics(
                lines: lines.map { $0.isEmpty ? $0 : converter.convert($0) },
                script: .traditional, lineScripts: nil, appliedMode: .variantsOnly
            )

        case .mixed:
            let lineScripts = detector.detectEachLine(lines)
            var simplifiedConverter: LyricsChineseConverter?
            var variantsConverter: LyricsChineseConverter?
            var converted: [String] = []
            converted.reserveCapacity(lines.count)
            for (line, lineScript) in zip(lines, lineScripts) {
                switch lineScript {
                case .neutral:
                    converted.append(line)
                case .simplified, .mixed:
                    if simplifiedConverter == nil { simplifiedConverter = try converterProvider(simplifiedMode) }
                    converted.append(simplifiedConverter!.convert(line))
                case .traditional:
                    if variantsConverter == nil { variantsConverter = try converterProvider(.variantsOnly) }
                    converted.append(variantsConverter!.convert(line))
                }
            }
            return LocalizedLyrics(lines: converted, script: .mixed, lineScripts: lineScripts, appliedMode: nil)
        }
    }
}

/// 自訂覆寫表時，各模式轉換器的實例內快取。
private final class LocalConverterStore: @unchecked Sendable {
    private let overrides: LyricsOverrides
    private let lock = NSLock()
    private var converters: [LyricsConversionMode: LyricsChineseConverter] = [:]

    init(overrides: LyricsOverrides) {
        self.overrides = overrides
    }

    func converter(for mode: LyricsConversionMode) throws -> LyricsChineseConverter {
        lock.lock()
        defer { lock.unlock() }
        if let existing = converters[mode] { return existing }
        let created = try LyricsChineseConverter(mode: mode, overrides: overrides)
        converters[mode] = created
        return created
    }
}
