import DavidNookCore
import Foundation

// DavidNookProbe：以 Core 的真實歌詞管線批次跑 LRCLIB 真實資料的稽核工具（唯讀；報告只寫在 --out）。
//
//   swift run -c release DavidNookProbe --list <songs.tsv> --out <報告目錄>
//        [--cache <快取目錄，預設 <out>/cache>] [--max-requests 120] [--offline] [--survey-only] [--only <關鍵字>]
//
// 真實歌詞是受版權保護的內容：報告（含逐行對照）只放在 --out 指定的目錄，絕不可 commit。

struct Options {
    var list = ""
    var out = ""
    var cache: String?
    var maxRequests = 120
    var offline = false
    var surveyOnly = false
    var only: String?
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("DavidNookProbe: " + message + "\n").utf8))
    exit(2)
}

func log(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func parseOptions() -> Options {
    var options = Options()
    var args = Array(CommandLine.arguments.dropFirst())
    while !args.isEmpty {
        let flag = args.removeFirst()
        func value() -> String {
            guard !args.isEmpty else { fail("\(flag) 需要一個值") }
            return args.removeFirst()
        }
        switch flag {
        case "--list": options.list = value()
        case "--out": options.out = value()
        case "--cache": options.cache = value()
        case "--max-requests": options.maxRequests = Int(value()) ?? 120
        case "--offline": options.offline = true
        case "--survey-only": options.surveyOnly = true
        case "--only": options.only = value()
        case "-h", "--help":
            print("用法：DavidNookProbe --list <songs.tsv> --out <報告目錄> [--cache <目錄>] [--max-requests N] [--offline] [--survey-only] [--only <關鍵字>]")
            exit(0)
        default: fail("未知參數 \(flag)")
        }
    }
    guard !options.list.isEmpty, !options.out.isEmpty else { fail("必須提供 --list 與 --out") }
    return options
}

func csvField(_ s: String) -> String {
    if s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) { return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
    return s
}

func tsvField(_ s: String) -> String {
    s.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
}

func slug(_ s: String) -> String {
    let mapped = s.map { ($0.isLetter || $0.isNumber) ? String($0) : "_" }.joined()
    return String(mapped.prefix(40))
}

func writeJSON<T: Encodable>(_ value: T, to url: URL) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    do { try encoder.encode(value).write(to: url, options: .atomic) } catch { log("寫入失敗 \(url.path)：\(error)") }
}

func writeText(_ text: String, to url: URL) {
    do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { log("寫入失敗 \(url.path)：\(error)") }
}

func fmt(_ x: Double, _ digits: Int = 2) -> String { String(format: "%.\(digits)f", x) }

// MARK: - 主程式

let options = parseOptions()
let outURL = URL(fileURLWithPath: options.out, isDirectory: true)
let cacheURL = URL(fileURLWithPath: options.cache ?? options.out + "/cache", isDirectory: true)
let songsDir = outURL.appendingPathComponent("songs", isDirectory: true)
try? FileManager.default.createDirectory(at: songsDir, withIntermediateDirectories: true)

guard let tsv = try? String(contentsOfFile: options.list, encoding: .utf8) else { fail("讀不到歌單 \(options.list)") }
var songs = SongEntry.parse(tsv: tsv)
if let only = options.only { songs = songs.filter { $0.title.contains(only) || $0.artist.contains(only) } }
guard !songs.isEmpty else { fail("歌單是空的") }

let transport: ProbeTransport
let analyzer: SongAnalyzer
do {
    transport = try ProbeTransport(cacheDirectory: cacheURL, offline: options.offline, budget: options.maxRequests)
    analyzer = try SongAnalyzer(transport: transport)
} catch {
    fail("初始化失敗：\(error)")
}

// 階段 1：調查（每首歌一次 /api/search，同時是 A/B 對照與長度推估的資料來源）。
var surveys: [Int: SurveyResult] = [:]
var durations: [Int: (value: Double?, estimated: Bool)] = [:]
for song in songs {
    let result = await analyzer.survey(song)
    surveys[song.index] = result
    if let given = song.duration, given > 0 {
        durations[song.index] = (given, false)
    } else {
        durations[song.index] = (SongAnalyzer.estimateDuration(title: song.title, candidates: result.candidates), true)
    }
    let d = durations[song.index]?.value.map { fmt($0, 1) } ?? "-"
    log("[survey \(song.index)/\(songs.count)] \(song.title) / \(song.artist): HTTP \(result.status) 候選 \(result.candidates.count) 長度 \(d)\(result.error.map { " 錯誤 \($0)" } ?? "")")
}

// 解析後的歌單（補上長度；估計值在備註標 `長度為估計`）。
var resolved = "# 由 DavidNookProbe 產生：長度空白者以 LRCLIB search 結果的長度叢集中位數代入\n"
for song in songs {
    let d = durations[song.index]
    let length = d?.value.map { fmt($0, 1) } ?? ""
    let note = (d?.estimated ?? false) && d?.value != nil ? song.note + " 長度為估計" : song.note
    resolved += [song.title, song.artist, length, note].joined(separator: "\t") + "\n"
}
writeText(resolved, to: outURL.appendingPathComponent("songs.resolved.tsv"))

if options.surveyOnly {
    let ledger = transport.ledgerSnapshot
    log("調查完成。累計連網請求 \(ledger.total)（200：\(ledger.count(status: 200))、404：\(ledger.count(status: 404))、429：\(ledger.count(status: 429))、503：\(ledger.count(status: 503))）")
    exit(0)
}

// 階段 2：真實管線。
var reports: [SongReport] = []
var flagged: [FlaggedRow] = []
var headers: [HeaderRow] = []
for song in songs {
    guard let survey = surveys[song.index], let d = durations[song.index] else { continue }
    let output = await analyzer.analyze(song: song, survey: survey, duration: d.value, durationEstimated: d.estimated)
    reports.append(output.report)
    flagged += output.flagged
    headers += output.headers
    writeJSON(output.report, to: songsDir.appendingPathComponent(String(format: "%02d-%@-%@.json", song.index, song.category, slug(song.title))))
    let r = output.report
    log("[pipeline \(song.index)/\(songs.count)] \(song.title): \(r.outcome) id=\(r.picked.map { String($0.id) } ?? "-") 來源=\(r.pickSource ?? "-") 字體=\(r.localization?.detected ?? "-") 轉換字=\(r.localization?.changedCharCount ?? 0)\(r.ab != nil ? " A/B" : "")")
}

// MARK: - 彙總 CSV

var csv = "index,category,title,artist,duration,duration_estimated,outcome,candidates,viable,picked_id,pick_source,ideal_pick_id,pick_differs_from_ideal,duration_diff,picked_script,detected_script,applied_mode,converted,changed_chars,kana_chars,hangul_chars,ab_pair,ab_aligned_chars,ab_semantic,ab_style,ab_semantic_rate,ab_style_rate,rt_aligned_chars,rt_semantic,rt_style,div_median_s,div_frac_over_1s,live_requests,cached_requests,parser_anomalies,header_leak_suspect,same_timestamp_lines\n"
for r in reports {
    let l = r.localization
    let ab = r.ab
    let aligned = ab?.alignedChars ?? 0
    let semantic = ab?.vsDisplayRef.semantic ?? 0
    let style = ab?.vsDisplayRef.style ?? 0
    let row: [String] = [
        String(r.index), r.category, r.title, r.artist, r.duration.map { fmt($0, 1) } ?? "", r.durationEstimated ? "1" : "0",
        r.outcome, String(r.survey.total), String(r.survey.viable), r.picked.map { String($0.id) } ?? "",
        r.pickSource ?? "", r.idealPickID.map(String.init) ?? "", r.picked == nil ? "" : (r.pickDiffersFromIdeal ? "1" : "0"),
        r.picked?.durationDiff.map { fmt($0, 2) } ?? "", r.picked?.script ?? "", l?.detected ?? "", l?.mode ?? "",
        l == nil ? "" : ((l?.converted ?? false) ? "1" : "0"), String(l?.changedCharCount ?? 0),
        String(l?.kanaChars ?? 0), String(l?.hangulChars ?? 0),
        ab == nil ? "0" : "1", String(aligned), String(semantic), String(style),
        ab == nil || aligned == 0 ? "" : fmt(Double(semantic) / Double(aligned) * 100, 3),
        ab == nil || aligned == 0 ? "" : fmt(Double(style) / Double(aligned) * 100, 3),
        r.roundTrip.map { String($0.alignedChars) } ?? "", r.roundTrip.map { String($0.vsDisplayRef.semantic) } ?? "",
        r.roundTrip.map { String($0.vsDisplayRef.style) } ?? "",
        r.divergence.map { fmt($0.medianLineDeltaSec, 2) } ?? "", r.divergence.map { fmt($0.fractionOver1s, 2) } ?? "",
        String(r.requests.filter { $0.source == "live" }.count), String(r.requests.filter { $0.source == "cache" }.count),
        r.parserAnomalies.joined(separator: "; "), r.header.map { $0.leakSuspect ? "1" : "0" } ?? "",
        r.picked.map { String($0.sameTimestampLines) } ?? "",
    ]
    csv += row.map(csvField).joined(separator: ",") + "\n"
}
writeText(csv, to: outURL.appendingPathComponent("summary.csv"))

// MARK: - flagged.tsv／header_audit.tsv

var flaggedText = "song\ttag\tcandidate_id\tline\ttime_ms\tsuspect\trisk_pairs\tsource\toutput\n"
for f in flagged {
    flaggedText += [f.song, f.tag, String(f.candidateID), String(f.lineIndex), String(f.timeMs), f.suspect, f.riskPairs, f.source, f.output]
        .map(tsvField).joined(separator: "\t") + "\n"
}
writeText(flaggedText, to: outURL.appendingPathComponent("flagged.tsv"))

var headerText = "tag\tsong\tcandidate_id\tleak_suspect\tdropped\tfirst_kept\n"
for h in headers {
    headerText += [h.tag, h.song, String(h.candidateID), h.leakSuspect ? "1" : "0", h.dropped.joined(separator: " ⏎ "), h.firstKept.prefix(3).joined(separator: " ⏎ ")]
        .map(tsvField).joined(separator: "\t") + "\n"
}
writeText(headerText, to: outURL.appendingPathComponent("header_audit.tsv"))

// MARK: - A/B 彙總

struct ABSummary: Codable {
    var pairs: Int
    var songs: [String]
    var alignedChars: Int
    var unalignedChars: Int
    var vsDisplayRef: DiffTally
    var vsRawRef: DiffTally
    var occurrences: [String: Int]
    var semanticRatePercent: Double
    var styleRatePercent: Double
    var rawSemanticRatePercent: Double
    var rawStyleRatePercent: Double
    var topSemanticExamples: [DiffExample]
}

var abSongs: [String] = []
var abAligned = 0, abUnaligned = 0
var abDisplay = DiffTally(), abRaw = DiffTally()
var abOcc: [String: Int] = [:]
var abExamples: [DiffExample] = []
for r in reports {
    guard let ab = r.ab else { continue }
    abSongs.append("\(r.title) / \(r.artist)")
    abAligned += ab.alignedChars
    abUnaligned += ab.unalignedChars
    abDisplay.add(ab.vsDisplayRef)
    abRaw.add(ab.vsRawRef)
    for (k, v) in ab.occurrences { abOcc[k, default: 0] += v }
    abExamples += ab.examples.filter { $0.kind == "semantic" }.map { example in
        var copy = example
        copy.category = "\(r.title)｜\(example.category)"
        return copy
    }
}
let abSummary = ABSummary(
    pairs: abSongs.count, songs: abSongs, alignedChars: abAligned, unalignedChars: abUnaligned,
    vsDisplayRef: abDisplay, vsRawRef: abRaw, occurrences: abOcc,
    semanticRatePercent: abAligned == 0 ? 0 : Double(abDisplay.semantic) / Double(abAligned) * 100,
    styleRatePercent: abAligned == 0 ? 0 : Double(abDisplay.style) / Double(abAligned) * 100,
    rawSemanticRatePercent: abAligned == 0 ? 0 : Double(abRaw.semantic) / Double(abAligned) * 100,
    rawStyleRatePercent: abAligned == 0 ? 0 : Double(abRaw.style) / Double(abAligned) * 100,
    topSemanticExamples: Array(abExamples.prefix(300))
)
writeJSON(abSummary, to: outURL.appendingPathComponent("ab_summary.json"))

// MARK: - 合成對照（round-trip）彙總

struct RoundTripSummary: Codable {
    var songs: Int
    var songList: [String]
    var lines: Int
    var alignedChars: Int
    var vsDisplayRef: DiffTally
    var vsRawRef: DiffTally
    var occurrences: [String: Int]
    /// 每個歧義簡體字：出現次數、轉錯（語意）次數、風格差異次數。
    var perCanon: [String: [String: Int]]
    var semanticRatePercent: Double
    var styleRatePercent: Double
    var perSong: [String: [String: Int]]
    var examples: [DiffExample]
}

var rtSongs: [String] = []
var rtLines = 0, rtAligned = 0
var rtDisplay = DiffTally(), rtRaw = DiffTally()
var rtOcc: [String: Int] = [:]
var rtPerSong: [String: [String: Int]] = [:]
var rtExamples: [DiffExample] = []
var rtSemanticByCanon: [String: Int] = [:]
var rtStyleByCanon: [String: Int] = [:]
for r in reports {
    guard let rt = r.roundTrip else { continue }
    let name = "\(r.title) / \(r.artist)"
    rtSongs.append(name)
    rtLines += rt.lines
    rtAligned += rt.alignedChars
    rtDisplay.add(rt.vsDisplayRef)
    rtRaw.add(rt.vsRawRef)
    for (k, v) in rt.occurrences { rtOcc[k, default: 0] += v }
    rtPerSong[name] = ["aligned": rt.alignedChars, "semantic": rt.vsDisplayRef.semantic, "style": rt.vsDisplayRef.style]
    rtExamples += rt.examples.filter { $0.kind == "semantic" }.map { e in
        var c = e
        c.category = "\(r.title)｜\(e.category)"
        return c
    }
    for e in rt.examples {
        let key = e.sourceLine.isEmpty ? "?" : e.category
        if e.kind == "semantic" { rtSemanticByCanon[key, default: 0] += 1 } else { rtStyleByCanon[key, default: 0] += 1 }
    }
}
var rtPerCanon: [String: [String: Int]] = [:]
for (canon, count) in rtOcc {
    rtPerCanon[canon] = ["occurrences": count, "diffs": rtDisplay.byCanon[canon] ?? 0]
}
for (canon, count) in rtDisplay.byCanon where rtPerCanon[canon] == nil {
    rtPerCanon[canon] = ["occurrences": 0, "diffs": count]
}
let rtSummary = RoundTripSummary(
    songs: rtSongs.count, songList: rtSongs, lines: rtLines, alignedChars: rtAligned,
    vsDisplayRef: rtDisplay, vsRawRef: rtRaw, occurrences: rtOcc, perCanon: rtPerCanon,
    semanticRatePercent: rtAligned == 0 ? 0 : Double(rtDisplay.semantic) / Double(rtAligned) * 100,
    styleRatePercent: rtAligned == 0 ? 0 : Double(rtDisplay.style) / Double(rtAligned) * 100,
    perSong: rtPerSong, examples: Array(rtExamples.prefix(2000))
)
writeJSON(rtSummary, to: outURL.appendingPathComponent("roundtrip_summary.json"))

// MARK: - 帳本與結尾彙總

let ledger = transport.ledgerSnapshot
writeJSON(ledger, to: outURL.appendingPathComponent("requests_ledger.json"))

let found = reports.filter { $0.picked != nil }.count
let converted = reports.filter { $0.localization?.converted ?? false }.count
// 語意不一致逐條清單（人工複核用）：A/B 與合成對照，同句同字去重。
var reviewText = "source\tsong\tcategory\tours_vs_ref\tcount\tsource_line\tours_line\tref_line\n"
var reviewSeen: [String: Int] = [:]
var reviewRows: [[String]] = []
func addReview(_ origin: String, _ title: String, _ examples: [DiffExample]) {
    for e in examples where e.kind == "semantic" {
        let key = [origin, title, e.ours, e.ref, e.sourceLine].joined(separator: "|")
        if let at = reviewSeen[key] {
            reviewRows[at][4] = String((Int(reviewRows[at][4]) ?? 1) + 1)
        } else {
            reviewSeen[key] = reviewRows.count
            reviewRows.append([origin, title, e.category, "\(e.ours)→\(e.ref)", "1", e.sourceLine, e.oursLine, e.refLine])
        }
    }
}
for r in reports {
    if let ab = r.ab { addReview("A/B", r.title, ab.examples) }
    if let rt = r.roundTrip { addReview("roundtrip", r.title, rt.examples) }
}
for row in reviewRows { reviewText += row.map(tsvField).joined(separator: "\t") + "\n" }
writeText(reviewText, to: outURL.appendingPathComponent("semantic_review.tsv"))

print("==== DavidNookProbe 彙總 ====")
print("歌單 \(songs.count) 首；命中（有挑到同步歌詞）\(found)；被轉換 \(converted)")
print("A/B 對照 \(abSongs.count) 首；對齊漢字 \(abAligned)；語意不一致 \(abDisplay.semantic)（\(fmt(abSummary.semanticRatePercent, 3))%）；風格差異 \(abDisplay.style)（\(fmt(abSummary.styleRatePercent, 3))%）；對照版殘留簡體 \(abDisplay.refResidue)")
print("合成對照（繁體原文→t2s→我們的 s2t）\(rtSongs.count) 首；對齊漢字 \(rtAligned)；語意不一致 \(rtDisplay.semantic)（\(fmt(rtSummary.semanticRatePercent, 3))%）；風格差異 \(rtDisplay.style)（\(fmt(rtSummary.styleRatePercent, 3))%）；對照版殘留簡體 \(rtDisplay.refResidue)")
print("累計連網請求 \(ledger.total)（200：\(ledger.count(status: 200))、404：\(ledger.count(status: 404))、429：\(ledger.count(status: 429))、503：\(ledger.count(status: 503))）")
print("報告目錄：\(outURL.path)")
