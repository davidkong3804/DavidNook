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
/// - `traditional`：逐行以 `.variantsOnly`（只做台灣變體正規化，不改原生繁體用字）；
///   行內殘留的簡體專有字（上傳者轉換不完整）另外修復，見 `TraditionalLineRepairer`。
/// - `mixed`：逐行判斷——簡體行轉換、繁體行 variantsOnly（同樣修復殘留簡體字）、中性行（沒有專有字，如英文）原樣。
///   一行內簡繁並存時，視為簡體行轉換（簡體殘留比誤改罕見的繁體用字更顯眼）。
/// - `neutral`：原樣。
/// - 日文／韓文行（假名／諺文占比 ≥ 5%）一律原樣，不論整篇是哪一種：日文新字體（国・恋・声）不是簡體，
///   不可轉成「國・戀・聲」；整份歌詞多數是日韓行時整篇為 `neutral`（見 `ChineseScriptDetector`）。
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
                lines: lines.map { $0.isEmpty || detector.isJapaneseOrKorean($0) ? $0 : finish(converter.convert($0)) },
                script: .simplified, lineScripts: nil, appliedMode: simplifiedMode
            )

        case .traditional:
            let repairer = try TraditionalLineRepairer(detector: detector, converterProvider: converterProvider)
            return LocalizedLyrics(
                lines: try lines.map { line in
                    guard !line.isEmpty, !detector.isJapaneseOrKorean(line) else { return line }
                    return finish(try repairer.convert(line))
                },
                script: .traditional, lineScripts: nil, appliedMode: .variantsOnly
            )

        case .mixed:
            let lineScripts = detector.detectEachLine(lines)
            var simplifiedConverter: LyricsChineseConverter?
            var repairer: TraditionalLineRepairer?
            var converted: [String] = []
            converted.reserveCapacity(lines.count)
            for (line, lineScript) in zip(lines, lineScripts) {
                switch lineScript {
                case .neutral:
                    // 沒有專有字的行：文件已確定是華語，只套用「里」子句尾規則（日韓行不動）。
                    converted.append(line.isEmpty || detector.isJapaneseOrKorean(line) ? line : finish(line))
                case .simplified, .mixed:
                    if simplifiedConverter == nil { simplifiedConverter = try converterProvider(simplifiedMode) }
                    converted.append(finish(simplifiedConverter!.convert(line)))
                case .traditional:
                    if repairer == nil {
                        repairer = try TraditionalLineRepairer(detector: detector, converterProvider: converterProvider)
                    }
                    converted.append(finish(try repairer!.convert(line)))
                }
            }
            return LocalizedLyrics(lines: converted, script: .mixed, lineScripts: lineScripts, appliedMode: nil)
        }
    }

    /// 轉換的最後一步：「里」子句尾啟發式（見 `ClauseFinalLiRule`）。
    private func finish(_ line: String) -> String {
        ClauseFinalLiRule.apply(to: line)
    }
}

/// 原生繁體行的轉換：t2tw 變體正規化＋殘留簡體字修復。
///
/// 原生繁體歌詞常夾雜上傳者沒轉乾淨的簡體字（整句繁體卻留著「红」、「这」）。逐行處理：
/// - 日文／韓文行、空行：原樣。
/// - 行內沒有簡體專有字：只做 t2tw（`.variantsOnly`）。
/// - 有簡體專有字、**沒有**繁體專有字：整行是簡體 → 整行 `.conservative`（始終不用慣用詞層）。
/// - 簡體與繁體專有字並存：**只改簡體專有字那幾個位置**（取 `.conservative` 整行轉換結果中同一位置的字），
///   其餘字元原樣，之後再做 t2tw。這樣「红塵」→「紅塵」，而同行的「鄰里」不會被轉成「鄰裡」。
///   `.conservative` 若改變了字數（理論上不會）就退回逐字轉換。
///
/// 「里」「复」這類兩邊通用的歧義字不是簡體專有字，這裡不處理（見 `ClauseFinalLiRule` 與覆寫表）。
private struct TraditionalLineRepairer {
    let detector: ChineseScriptDetector
    let variants: LyricsChineseConverter
    private let conservativeProvider: () throws -> LyricsChineseConverter

    init(
        detector: ChineseScriptDetector,
        converterProvider: @escaping (LyricsConversionMode) throws -> LyricsChineseConverter
    ) throws {
        self.detector = detector
        self.variants = try converterProvider(.variantsOnly)
        // `.conservative` 要載入字典（約 20 ms），只有真的遇到殘留簡體字的行才載入。
        let lazy = LazyConverter { try converterProvider(.conservative) }
        self.conservativeProvider = { try lazy.get() }
    }

    func convert(_ line: String) throws -> String {
        if line.isEmpty || detector.isJapaneseOrKorean(line) { return line }
        let evidence = detector.evidence(in: line)
        guard evidence.simplified > 0 else { return variants.convert(line) }

        let conservative = try conservativeProvider()
        if evidence.traditional == 0 { return conservative.convert(line) }
        return variants.convert(replacingSimplifiedOnlyCharacters(in: line, using: conservative))
    }

    private func replacingSimplifiedOnlyCharacters(in line: String, using conservative: LyricsChineseConverter) -> String {
        let original = Array(line.unicodeScalars)
        let wholeLine = Array(conservative.convert(line).unicodeScalars)
        var output = String.UnicodeScalarView()
        for (index, scalar) in original.enumerated() {
            guard detector.isSimplifiedOnly(scalar) else {
                output.append(scalar)
                continue
            }
            if wholeLine.count == original.count {
                output.append(wholeLine[index])
            } else {
                output.append(contentsOf: conservative.convert(String(scalar)).unicodeScalars)
            }
        }
        return String(output)
    }
}

/// 第一次用到才建立的轉換器（執行緒安全）。
private final class LazyConverter: @unchecked Sendable {
    private let make: () throws -> LyricsChineseConverter
    private let lock = NSLock()
    private var value: LyricsChineseConverter?

    init(_ make: @escaping () throws -> LyricsChineseConverter) { self.make = make }

    func get() throws -> LyricsChineseConverter {
        lock.lock()
        defer { lock.unlock() }
        if let value { return value }
        let created = try make()
        value = created
        return created
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
