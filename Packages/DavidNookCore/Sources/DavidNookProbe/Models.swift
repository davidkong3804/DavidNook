import DavidNookCore
import Foundation

// MARK: - 歌單

struct SongEntry {
    var index: Int
    var title: String
    var artist: String
    var duration: Double?
    var note: String
    /// 備註的第一個詞（tw／cn／hk／en／jp／kr／inst／special）。
    var category: String { note.split(separator: " ").first.map(String.init) ?? "" }

    static func parse(tsv: String) -> [SongEntry] {
        var songs: [SongEntry] = []
        for raw in tsv.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = String(raw)
            if line.trimmingCharacters(in: .whitespaces).isEmpty || line.hasPrefix("#") { continue }
            let f = line.components(separatedBy: "\t")
            guard f.count >= 2 else { continue }
            let durationText = f.count > 2 ? f[2].trimmingCharacters(in: .whitespaces) : ""
            songs.append(SongEntry(
                index: songs.count + 1,
                title: f[0].trimmingCharacters(in: .whitespaces),
                artist: f[1].trimmingCharacters(in: .whitespaces),
                duration: Double(durationText),
                note: f.count > 3 ? f[3].trimmingCharacters(in: .whitespaces) : ""
            ))
        }
        return songs
    }
}

// MARK: - 調查階段（/api/search 結果）

struct SurveyResult {
    var status: Int
    var candidates: [LrclibCandidate]
    var error: String?
    /// 備註含 `+ab` 的歌，另外查簡繁變體寫法（與 App 在 search 階段會送出的變體請求相同）得到的候選，只用於 A/B 對照。
    var altCandidates: [LrclibCandidate] = []
    var altStatuses: [Int] = []
}

/// 單筆壞資料不拖垮整個陣列。
struct LossyCandidate: Decodable {
    let value: LrclibCandidate?
    init(from decoder: Decoder) throws { value = try? LrclibCandidate(from: decoder) }
}

// MARK: - 報告結構（逐首 JSON）

struct SurveyInfo: Codable {
    var status: Int
    var total: Int
    var instrumental: Int
    var noSynced: Int
    var noDuration: Int
    var durationRejected: Int
    var viable: Int
    var error: String?
    /// 變體寫法 search 額外取得的候選數（只用於 A/B）。
    var alt: Int = 0
}

struct ViableInfo: Codable {
    var id: Int
    var trackName: String
    var artistName: String
    var duration: Double
    var durationDiff: Double
    var script: String
    var firstLineSeconds: Double
    var spokenLines: Int
    var enhancedTags: Bool
    var droppedHeaderLines: Int
    var droppedTexts: [String]
    /// 與前一行時間戳相同的非空白行數（雙語／翻譯行常見的特徵）。
    var sameTimestampLines: Int
    var leakSuspect: Bool
    var parserAnomalies: [String]
}

struct PickedInfo: Codable {
    var id: Int
    var trackName: String
    var artistName: String
    var duration: Double?
    var durationDiff: Double?
    var script: String
    var lineCount: Int
    var spokenCount: Int
    var offsetMs: Int
    var firstLineSeconds: Double
    var sameTimestampLines: Int
}

struct HeaderInfo: Codable {
    var dropped: [String]
    var firstKept: [String]
    var leakSuspect: Bool
}

struct LineRow: Codable {
    var timeMs: Int
    var before: String
    var after: String
}

struct LocalizationInfo: Codable {
    var detected: String
    var mode: String?
    var converted: Bool
    var changedLineCount: Int
    var changedCharCount: Int
    var changedChars: [String: Int]
    var kanaChars: Int
    var hangulChars: Int
    var lines: [LineRow]
}

struct DiffExample: Codable {
    var category: String
    var kind: String
    var ours: String
    var ref: String
    var timeMs: Int
    var sourceLine: String
    var oursLine: String
    var refLine: String
}

struct DiffTally: Codable {
    var semantic = 0
    var style = 0
    /// 對照版本身殘留簡體專有字造成的不一致（不算我們的錯）。
    var refResidue = 0
    var byCategory: [String: Int] = [:]
    var byPair: [String: Int] = [:]
    /// 以「正規化簡體字」為鍵的不一致數（用來算每個歧義字的錯誤率）。
    var byCanon: [String: Int] = [:]

    var total: Int { semantic + style + refResidue }

    mutating func add(_ other: DiffTally) {
        semantic += other.semantic
        style += other.style
        refResidue += other.refResidue
        for (k, v) in other.byCategory { byCategory[k, default: 0] += v }
        for (k, v) in other.byPair { byPair[k, default: 0] += v }
        for (k, v) in other.byCanon { byCanon[k, default: 0] += v }
    }
}

struct ABResult: Codable {
    var simplifiedID: Int
    var traditionalID: Int
    var simplifiedDuration: Double
    var traditionalDuration: Double
    var simplifiedCandidates: Int
    var traditionalCandidates: Int
    var pairingMode: String
    var offsetMs: Int
    var simplifiedLines: Int
    var traditionalLines: Int
    var linesPaired: Int
    var linesCompared: Int
    var linesSkippedLowSimilarity: Int
    /// 對齊成功的漢字數（比較分母）。
    var alignedChars: Int
    /// 我方輸出裡找不到對應（措辭不同）的漢字數；不計入轉換不一致。
    var unalignedChars: Int
    /// 對照基準＝原生繁體版經 pipeline（t2tw）後的顯示結果。
    var vsDisplayRef: DiffTally
    /// 對照基準＝原生繁體版原文。
    var vsRawRef: DiffTally
    /// 對齊位置中，歧義簡體字（发／里／后／干…）各出現幾次（錯誤率的分母）。
    var occurrences: [String: Int]
    var examples: [DiffExample]
}

/// 合成對照（round-trip）：把原生繁體歌詞（已選中的版本）經 t2s 變成簡體，再走一次我們的 s2t 管線，與原繁體逐字比對。
/// 簡體歌詞本來就把髮／發、裡／裏、乾／幹…合併成同一個字，所以這等價於「完美簡體來源」的轉換準確度（不含轉錄措辭差異）。
struct RoundTripResult: Codable {
    var sourceID: Int
    var lines: Int
    var alignedChars: Int
    var detectedAsSimplified: String
    var vsDisplayRef: DiffTally
    var vsRawRef: DiffTally
    var occurrences: [String: Int]
    var examples: [DiffExample]
}

/// 「App 實際挑到的版本」與「Picker 排名第一的版本」的時間軸分歧。
struct DivergenceInfo: Codable {
    var pickedID: Int
    var idealID: Int
    var firstLineDeltaSec: Double
    var matchedLines: Int
    var medianLineDeltaSec: Double
    var fractionOver1s: Double
}

struct SongReport: Codable {
    var index: Int
    var category: String
    var title: String
    var artist: String
    var duration: Double?
    var durationEstimated: Bool
    var survey: SurveyInfo
    var requests: [ProbeTransport.Record]
    var outcome: String
    var pickSource: String?
    var picked: PickedInfo?
    var idealPickID: Int?
    var pickDiffersFromIdeal: Bool
    var divergence: DivergenceInfo?
    var viable: [ViableInfo]
    var parserAnomalies: [String]
    var header: HeaderInfo?
    var localization: LocalizationInfo?
    var ab: ABResult?
    var roundTrip: RoundTripResult?
}

struct FlaggedRow {
    var song: String
    var tag: String
    var candidateID: Int
    var lineIndex: Int
    var timeMs: Int
    var source: String
    var output: String
    var riskPairs: String
    var suspect: String
}

struct HeaderRow {
    var tag: String
    var song: String
    var candidateID: Int
    var dropped: [String]
    var firstKept: [String]
    var leakSuspect: Bool
}
