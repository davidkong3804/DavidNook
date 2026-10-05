import DavidNookCore
import Foundation

/// 單首歌的完整稽核：真實管線（LrclibClient＋Picker＋Stripper＋Detector＋Localizer）＋周邊診斷。
final class SongAnalyzer {

    private let transport: ProbeTransport
    private let picker: LyricsCandidatePicker
    private let detector = ChineseScriptDetector()
    private let localizer = LyricsLocalizer.shared
    private let ab: ABComparer
    private let client: LrclibClient

    init(transport: ProbeTransport) throws {
        self.transport = transport
        self.picker = LyricsPipeline.makePicker()
        self.ab = try ABComparer()
        // 連網節流由 ProbeTransport 負責（≥1.25 秒）；client 自己的 requestSpacing 設 0，離線重跑才不會空等。
        self.client = LyricsPipeline.makeClient(transport: transport, appVersion: "probe", requestSpacing: 0)
    }

    // MARK: - 調查

    static func decodeSearch(_ data: Data) -> [LrclibCandidate] {
        ((try? JSONDecoder().decode([LossyCandidate].self, from: data)) ?? []).compactMap(\.value)
    }

    func survey(_ song: SongEntry) async -> SurveyResult {
        transport.beginSong()
        defer { _ = transport.endSong() }
        var result: SurveyResult
        do {
            let response = try await transport.send(ProbeTransport.searchRequest(title: song.title, artist: song.artist))
            if response.statusCode == 200 {
                result = SurveyResult(status: 200, candidates: Self.decodeSearch(response.body), error: nil)
            } else {
                result = SurveyResult(status: response.statusCode, candidates: [], error: "HTTP \(response.statusCode)")
            }
        } catch {
            return SurveyResult(status: -1, candidates: [], error: "\(error)")
        }

        // 備註含 +ab：再查 App 在 search 階段會送出的簡繁變體寫法，取得另一種字體的版本供 A/B 對照。
        if song.note.contains("+ab") {
            let base = LyricsQuery(title: song.title, artist: song.artist, album: nil, duration: 0)
            for variant in LyricsPipeline.queryVariants(for: base) where !(variant.title == song.title && variant.artist == song.artist) {
                do {
                    let response = try await transport.send(ProbeTransport.searchRequest(title: variant.title, artist: variant.artist))
                    result.altStatuses.append(response.statusCode)
                    if response.statusCode == 200 { result.altCandidates += Self.decodeSearch(response.body) }
                } catch {
                    result.altStatuses.append(-1)
                }
            }
        }
        return result
    }

    private static func fold(_ s: String) -> String {
        s.lowercased().filter { !$0.isWhitespace }
    }

    /// 長度未知時，從 search 結果推估：優先取「歌名完全相同且有同步歌詞」的候選，找出 ±2 秒內成員最多的長度叢集，回傳叢集中位數。
    static func estimateDuration(title: String, candidates: [LrclibCandidate]) -> Double? {
        func hasSynced(_ c: LrclibCandidate) -> Bool {
            !(c.syncedLyrics ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !c.instrumental
        }
        let exact = candidates.filter { fold($0.trackName) == fold(title) && ($0.duration ?? 0) > 0 }
        let tiers = [exact.filter(hasSynced), exact, candidates.filter { ($0.duration ?? 0) > 0 }]
        guard let pool = tiers.first(where: { !$0.isEmpty }) else { return nil }
        let ds = pool.compactMap(\.duration)
        var best: [Double] = []
        for d in ds {
            let members = ds.filter { abs($0 - d) <= 2 }
            if members.count > best.count { best = members }
        }
        let sorted = best.sorted()
        guard !sorted.isEmpty else { return nil }
        let median = sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        return median.rounded()
    }

    // MARK: - 候選診斷

    private struct Viable {
        var candidate: LrclibCandidate
        var diff: Double
        var script: LyricsScript
        var lines: [LRCLine]      // 已剝檔頭（含空白行）
        var dropped: [LRCLine]
        var spoken: [LRCLine]
        var offsetMs: Int
        var enhanced: Bool
        var anomalies: [String]
    }

    private static let enhancedRegex = try! NSRegularExpression(pattern: #"<\d{1,3}:\d{2}[.:]\d{1,3}>"#)
    private static let leadingTags = try! NSRegularExpression(pattern: #"^\s*(\[[^\]]*\])+"#)
    private static let timeTag = try! NSRegularExpression(pattern: #"\[\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?\]"#)
    private static let colonFraction = try! NSRegularExpression(pattern: #"^\s*\[\d{1,3}:\d{2}:\d{1,3}\]"#)

    private static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    /// 比對原始 LRC 與解析結果：回報被解析器悄悄丟掉的行、冒號小數格式、行內 Enhanced 標籤殘留。
    static func parserAnomalies(raw: String, document: LRCDocument) -> [String] {
        var expected = 0
        var colonFractionLines = 0
        for rawLine in raw.split(omittingEmptySubsequences: true, whereSeparator: { $0.isNewline }) {
            let line = String(rawLine)
            if matches(colonFraction, line) { colonFractionLines += 1 }
            guard let m = leadingTags.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let r = Range(m.range, in: line) else { continue }
            let tags = String(line[r])
            let timeTags = timeTag.numberOfMatches(in: tags, range: NSRange(tags.startIndex..., in: tags))
            guard timeTags > 0 else { continue }
            var rest = String(line[r.upperBound...])
            rest = enhancedRegex.stringByReplacingMatches(in: rest, range: NSRange(rest.startIndex..., in: rest), withTemplate: "")
            if !rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { expected += timeTags }
        }
        let parsed = document.lines.filter { !$0.isBlank }.count
        var result: [String] = []
        if expected != parsed { result.append("原始有字時間行 \(expected) 筆，解析出 \(parsed) 筆") }
        if colonFractionLines > 0 { result.append("[mm:ss:xx] 冒號小數格式 \(colonFractionLines) 行") }
        let leaked = document.lines.filter { matches(enhancedRegex, $0.text) }.count
        if leaked > 0 { result.append("解析後仍殘留 <mm:ss.xx> 標籤 \(leaked) 行") }
        return result
    }

    private func makeViable(_ candidate: LrclibCandidate, query: LyricsQuery) -> Viable? {
        let known = query.duration.isFinite && query.duration > 0
        var diff = 0.0
        if known {
            guard let d = candidate.duration, d.isFinite else { return nil }
            diff = abs(d - query.duration)
            if diff > picker.durationTolerance { return nil }
        }
        guard !candidate.instrumental, let synced = candidate.syncedLyrics,
              !synced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let document = LRCParser.parse(synced)
        let collapsed = LyricsTranslationCollapser.collapse(document.lines)
        let stripped = picker.stripper.strip(collapsed.lines, title: query.title, artist: query.artist)
        let spoken = stripped.lines.filter { !$0.isBlank }
        guard !spoken.isEmpty else { return nil }
        let script = picker.scriptClassifier(spoken.map(\.text).joined(separator: "\n"))
        return Viable(
            candidate: candidate, diff: diff, script: script, lines: stripped.lines, dropped: stripped.dropped,
            spoken: spoken, offsetMs: document.offsetMs,
            enhanced: Self.matches(Self.enhancedRegex, synced),
            anomalies: Self.parserAnomalies(raw: synced, document: document)
        )
    }

    // MARK: - 主流程

    struct Output {
        var report: SongReport
        var flagged: [FlaggedRow]
        var headers: [HeaderRow]
    }

    func analyze(song: SongEntry, survey: SurveyResult, duration: Double?, durationEstimated: Bool) async -> Output {
        let query = LyricsQuery(title: song.title, artist: song.artist, album: nil, duration: duration ?? 0)
        let songName = "\(song.title) - \(song.artist)"

        // 診斷：從 search 結果還原過濾漏斗。
        let known = (duration ?? 0) > 0
        var instrumental = 0, noSynced = 0, noDuration = 0, durationRejected = 0
        var viables: [Viable] = []
        for c in survey.candidates {
            if c.instrumental { instrumental += 1; continue }
            if (c.syncedLyrics ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { noSynced += 1; continue }
            if known {
                guard let d = c.duration, d.isFinite else { noDuration += 1; continue }
                if abs(d - (duration ?? 0)) > picker.durationTolerance { durationRejected += 1; continue }
            }
            if let v = makeViable(c, query: query) { viables.append(v) }
        }
        let ideal = picker.pick(from: survey.candidates, for: query)
        let surveyInfo = SurveyInfo(
            status: survey.status, total: survey.candidates.count, instrumental: instrumental, noSynced: noSynced,
            noDuration: noDuration, durationRejected: durationRejected, viable: viables.count, error: survey.error,
            alt: survey.altCandidates.count
        )

        // 真實管線：LrclibClient（get 變體 → search 變體）。
        transport.beginSong()
        var picked: PickedLyrics?
        var degraded = false
        var outcome = "not_found"
        do {
            let fetched = try await client.fetch(query)
            picked = fetched.lyrics
            degraded = fetched.isDegraded
            if picked != nil { outcome = degraded ? "picked_degraded" : "picked" }
        } catch {
            outcome = "error: \(error)"
        }
        let (records, bodies) = transport.endSong()
        // get 命中的候選 id（回應本文裡的單筆紀錄）；新流程會把它併入 search 候選池再排序。
        var getCandidateID: Int?
        for b in bodies where b.status == 200 && b.path.hasPrefix("/api/get") {
            if let one = try? JSONDecoder().decode(LrclibCandidate.self, from: b.body) { getCandidateID = one.id }
        }

        var report = SongReport(
            index: song.index, category: song.category, title: song.title, artist: song.artist,
            duration: duration, durationEstimated: durationEstimated, survey: surveyInfo, requests: records,
            outcome: outcome, pickSource: nil, degraded: degraded, getCandidateID: getCandidateID, pickedIsGetCandidate: nil,
            picked: nil, idealPickID: ideal?.candidateID, pickDiffersFromIdeal: false, divergence: nil,
            viable: viables.map { v in
                ViableInfo(
                    id: v.candidate.id, trackName: v.candidate.trackName, artistName: v.candidate.artistName,
                    duration: v.candidate.duration ?? 0, durationDiff: v.diff, script: v.script.rawValue,
                    firstLineSeconds: Double((v.spoken.first?.timeMs ?? 0) - v.offsetMs) / 1000,
                    spokenLines: v.spoken.count, enhancedTags: v.enhanced, droppedHeaderLines: v.dropped.count,
                    droppedTexts: v.dropped.map(\.text), sameTimestampLines: Self.sameTimestampCount(v.spoken),
                    leakSuspect: v.spoken.prefix(5).contains { Self.looksLikeCredit($0.text) },
                    parserAnomalies: v.anomalies
                )
            },
            parserAnomalies: [], header: nil, localization: nil, ab: nil, roundTrip: nil
        )
        var flagged: [FlaggedRow] = []
        var headers: [HeaderRow] = []

        if let picked {
            // 來源：這首歌有哪些端點回了 200（新流程 get 命中後仍會 search，統一排序）。
            let gotGet = records.contains { $0.status == 200 && $0.path.hasPrefix("/api/get") }
            let gotSearch = records.contains { $0.status == 200 && $0.path.hasPrefix("/api/search") }
            report.pickSource = gotGet && gotSearch ? "get+search" : (gotGet ? "get" : "search")
            report.pickedIsGetCandidate = getCandidateID.map { $0 == picked.candidateID }
            report.pickDiffersFromIdeal = ideal.map { $0.candidateID != picked.candidateID } ?? true
            if let ideal, ideal.candidateID != picked.candidateID {
                report.divergence = divergence(picked: picked, ideal: ideal)
            }

            // 找回被選中候選的原始內容（search 清單或 get 回應）。
            var raw: LrclibCandidate? = survey.candidates.first { $0.id == picked.candidateID }
            if raw == nil {
                for b in bodies where b.status == 200 && b.path.hasPrefix("/api/get") {
                    if let one = try? JSONDecoder().decode(LrclibCandidate.self, from: b.body), one.id == picked.candidateID {
                        raw = one
                    }
                }
            }
            let pickedDuration = raw?.duration
            let spoken = picked.lines.filter { !$0.isBlank }
            report.picked = PickedInfo(
                id: picked.candidateID, trackName: picked.trackName, artistName: picked.artistName,
                duration: pickedDuration, durationDiff: pickedDuration.map { abs($0 - (duration ?? 0)) },
                script: picked.script.rawValue, lineCount: picked.lines.count, spokenCount: spoken.count,
                offsetMs: picked.offsetMs, firstLineSeconds: Double((spoken.first?.timeMs ?? 0) - picked.offsetMs) / 1000,
                sameTimestampLines: Self.sameTimestampCount(spoken)
            )

            if let raw, let synced = raw.syncedLyrics {
                let document = LRCParser.parse(synced)
                let stripped = picker.stripper.strip(
                    LyricsTranslationCollapser.collapse(document.lines).lines, title: query.title, artist: query.artist
                )
                let firstKept = Array(stripped.lines.filter { !$0.isBlank }.prefix(5)).map(\.text)
                let leak = firstKept.contains { Self.looksLikeCredit($0) }
                report.header = HeaderInfo(dropped: stripped.dropped.map(\.text), firstKept: firstKept, leakSuspect: leak)
                headers.append(HeaderRow(
                    tag: "picked", song: songName, candidateID: picked.candidateID, dropped: stripped.dropped.map(\.text),
                    firstKept: firstKept, leakSuspect: leak
                ))
                report.parserAnomalies = Self.parserAnomalies(raw: synced, document: document)
            }

            // 在地化（與 App 相同：全部行、預設選項）。
            let texts = picked.lines.map(\.text)
            if let result = try? localizer.localize(lines: texts) {
                report.localization = Self.localizationInfo(picked.lines, result, detector: detector)
                if result.script == .simplified || result.script == .mixed {
                    flagged += Self.flaggedRows(
                        song: songName, tag: "picked", id: picked.candidateID, lines: picked.lines, output: result.lines
                    )
                }
            }
        }

        // A/B：同曲同時有簡體版與原生繁體版（長度差 ≤ 2 秒）。
        for v in viables where v.candidate.id != report.picked?.id {
            headers.append(HeaderRow(
                tag: "viable", song: songName, candidateID: v.candidate.id, dropped: v.dropped.map(\.text),
                firstKept: v.spoken.prefix(5).map(\.text), leakSuspect: v.spoken.prefix(5).contains { Self.looksLikeCredit($0.text) }
            ))
        }
        var abPool = viables
        for c in survey.altCandidates where !abPool.contains(where: { $0.candidate.id == c.id }) {
            if let v = makeViable(c, query: query) { abPool.append(v) }
        }
        let chinese = !["jp", "kr", "en", "inst", "special"].contains(song.category)
        if chinese, let comparison = compare(viables: abPool) {
            report.ab = comparison.result
            if report.picked?.id != comparison.simplifiedID {
                flagged += Self.flaggedRows(
                    song: songName, tag: "ab-simplified", id: comparison.simplifiedID,
                    lines: comparison.simplifiedLines, output: comparison.simplifiedOutput
                )
            }
        }

        // 合成對照（round-trip）：選中的原生繁體版 → t2s → 我們的 s2t 管線 → 與原版逐字比對。
        if chinese, let picked, picked.script == .traditional, let rt = roundTrip(picked: picked, songName: songName) {
            report.roundTrip = rt.result
            flagged += rt.flagged
        }

        return Output(report: report, flagged: flagged, headers: headers)
    }

    // MARK: - 合成對照

    private func roundTrip(picked: PickedLyrics, songName: String) -> (result: RoundTripResult, flagged: [FlaggedRow])? {
        guard let toSimplified = try? LyricsChineseConverter.cached(.traditionalToSimplified),
              let displayAll = try? localizer.localize(lines: picked.lines.map(\.text)).lines else { return nil }
        let simplifiedLines = picked.lines.map { toSimplified.convert($0.text) }
        guard let result = try? localizer.localize(lines: simplifiedLines) else { return nil }
        var ours: [ABComparer.TimedText] = []
        var refDisplay: [ABComparer.TimedText] = []
        var refRaw: [ABComparer.TimedText] = []
        for (i, line) in picked.lines.enumerated() where !line.isBlank {
            ours.append(.init(timeMs: line.timeMs, text: result.lines[i], source: simplifiedLines[i]))
            refDisplay.append(.init(timeMs: line.timeMs, text: displayAll[i], source: line.text))
            refRaw.append(.init(timeMs: line.timeMs, text: line.text, source: line.text))
        }
        let pairs = (0..<ours.count).map { ($0, $0) }
        let eval = ab.evaluate(pairs: pairs, ours: ours, refDisplay: refDisplay, refRaw: refRaw, maxExamples: 300)
        let rt = RoundTripResult(
            sourceID: picked.candidateID, lines: ours.count, alignedChars: eval.alignedChars,
            detectedAsSimplified: result.script.rawValue, vsDisplayRef: eval.vsDisplay, vsRawRef: eval.vsRaw,
            occurrences: eval.occurrences, examples: eval.examples
        )
        let simplifiedAsLRC = zip(picked.lines, simplifiedLines).map { LRCLine(timeMs: $0.timeMs, text: $1) }
        let rows = Self.flaggedRows(song: songName, tag: "roundtrip", id: picked.candidateID, lines: simplifiedAsLRC, output: result.lines)
        return (rt, rows)
    }

    // MARK: - 挑選分歧

    private func divergence(picked: PickedLyrics, ideal: PickedLyrics) -> DivergenceInfo {
        func spoken(_ p: PickedLyrics) -> [(text: [Character], time: Int)] {
            p.lines.filter { !$0.isBlank }.map { line in
                (line.text.filter { $0.isLetter || $0.isNumber }.map { ab.canon($0) }, line.timeMs - p.offsetMs)
            }
        }
        let a = spoken(picked), b = spoken(ideal)
        let firstDelta = Double((b.first?.time ?? 0) - (a.first?.time ?? 0)) / 1000
        let pairs = TextDiff.lcsPairs(a.map { String($0.text) }, b.map { String($0.text) })
        let deltas = pairs.map { Double(b[$0.1].time - a[$0.0].time) / 1000 }.sorted()
        let median = deltas.isEmpty ? 0 : deltas[deltas.count / 2]
        let over = deltas.isEmpty ? 0 : Double(deltas.filter { abs($0) > 1 }.count) / Double(deltas.count)
        return DivergenceInfo(
            pickedID: picked.candidateID, idealID: ideal.candidateID, firstLineDeltaSec: firstDelta,
            matchedLines: pairs.count, medianLineDeltaSec: median, fractionOver1s: over
        )
    }

    // MARK: - A/B

    private struct Comparison {
        var result: ABResult
        var simplifiedID: Int
        var simplifiedLines: [LRCLine]
        var simplifiedOutput: [String]
    }

    private func compare(viables: [Viable]) -> Comparison? {
        let simplified = viables.filter { $0.script == .simplified }.sorted { ($0.diff, $0.candidate.id) < ($1.diff, $1.candidate.id) }
        let traditional = viables.filter { $0.script == .traditional }
        guard !simplified.isEmpty, !traditional.isEmpty else { return nil }
        for s in simplified {
            guard let sd = s.candidate.duration else { continue }
            let refs = traditional.filter { ($0.candidate.duration.map { abs($0 - sd) } ?? 99) <= 2 }
                .sorted { a, b in
                    let da = abs((a.candidate.duration ?? 0) - sd), db = abs((b.candidate.duration ?? 0) - sd)
                    return (da, a.diff, a.candidate.id) < (db, b.diff, b.candidate.id)
                }
            guard let t = refs.first, let td = t.candidate.duration else { continue }

            guard let oursAll = try? localizer.localize(lines: s.lines.map(\.text)).lines,
                  let refAll = try? localizer.localize(lines: t.lines.map(\.text)).lines else { continue }
            var ours: [ABComparer.TimedText] = []
            for (line, out) in zip(s.lines, oursAll) where !line.isBlank {
                ours.append(.init(timeMs: line.timeMs - s.offsetMs, text: out, source: line.text))
            }
            var refDisplay: [ABComparer.TimedText] = []
            var refRaw: [ABComparer.TimedText] = []
            for (line, out) in zip(t.lines, refAll) where !line.isBlank {
                refDisplay.append(.init(timeMs: line.timeMs - t.offsetMs, text: out, source: line.text))
                refRaw.append(.init(timeMs: line.timeMs - t.offsetMs, text: line.text, source: line.text))
            }

            let byTime = ABComparer.timePairs(ours, refDisplay)
            let evalTime = ab.evaluate(pairs: byTime.pairs, ours: ours, refDisplay: refDisplay, refRaw: refRaw)
            let idx = ABComparer.indexPairs(ours, refDisplay)
            let evalIndex = ab.evaluate(pairs: idx, ours: ours, refDisplay: refDisplay, refRaw: refRaw)
            let useIndex = evalIndex.alignedChars > evalTime.alignedChars
            let eval = useIndex ? evalIndex : evalTime

            let result = ABResult(
                simplifiedID: s.candidate.id, traditionalID: t.candidate.id,
                simplifiedDuration: sd, traditionalDuration: td,
                simplifiedCandidates: simplified.count, traditionalCandidates: traditional.count,
                pairingMode: useIndex ? "index" : "time", offsetMs: byTime.offsetMs,
                simplifiedLines: ours.count, traditionalLines: refDisplay.count,
                linesPaired: eval.linesPaired, linesCompared: eval.linesCompared, linesSkippedLowSimilarity: eval.linesSkipped,
                alignedChars: eval.alignedChars, unalignedChars: eval.unalignedChars,
                vsDisplayRef: eval.vsDisplay, vsRawRef: eval.vsRaw, occurrences: eval.occurrences, examples: eval.examples
            )
            return Comparison(result: result, simplifiedID: s.candidate.id, simplifiedLines: s.lines, simplifiedOutput: oursAll)
        }
        return nil
    }

    // MARK: - 在地化結果

    private static func localizationInfo(_ lines: [LRCLine], _ result: LocalizedLyrics, detector: ChineseScriptDetector) -> LocalizationInfo {
        var rows: [LineRow] = []
        var changedLines = 0
        var changedChars = 0
        var tally: [String: Int] = [:]
        for (line, after) in zip(lines, result.lines) {
            rows.append(LineRow(timeMs: line.timeMs, before: line.text, after: after))
            guard line.text != after else { continue }
            changedLines += 1
            for change in TextDiff.changes(before: line.text, after: after) {
                changedChars += change.from.count
                tally["\(change.from)→\(change.to)", default: 0] += 1
            }
        }
        let all = lines.map(\.text).joined()
        return LocalizationInfo(
            detected: result.script.rawValue, mode: result.appliedMode?.rawValue,
            converted: changedLines > 0, changedLineCount: changedLines, changedCharCount: changedChars,
            changedChars: tally,
            kanaChars: all.unicodeScalars.filter { CJK.isKana($0) }.count,
            hangulChars: all.unicodeScalars.filter { CJK.isHangul($0) }.count,
            lines: rows
        )
    }

    // MARK: - 稽核輔助

    private static func flaggedRows(song: String, tag: String, id: Int, lines: [LRCLine], output: [String]) -> [FlaggedRow] {
        var rows: [FlaggedRow] = []
        for (index, (line, out)) in zip(lines, output).enumerated() where !line.isBlank {
            let pairs = FlaggedAudit.riskPairs(source: line.text, output: out)
            guard !pairs.isEmpty else { continue }
            rows.append(FlaggedRow(
                song: song, tag: tag, candidateID: id, lineIndex: index, timeMs: line.timeMs,
                source: line.text, output: out, riskPairs: pairs, suspect: FlaggedAudit.suspects(in: out)
            ))
        }
        return rows
    }

    /// 與前一個非空白行時間戳相同的行數。
    static func sameTimestampCount(_ spoken: [LRCLine]) -> Int {
        var n = 0
        for (a, b) in zip(spoken, spoken.dropFirst()) where a.timeMs == b.timeMs { n += 1 }
        return n
    }

    private static let creditHint = try! NSRegularExpression(
        pattern: #"^\s*(作?[詞词曲]|编曲|編曲|制作|製作|监制|監製|lyrics|composer|producer|arranger|written by|music by|words by)\s*[:：]|\s[-–—]\s"#,
        options: [.caseInsensitive]
    )

    /// 剝完檔頭後的前幾句仍長得像中繼行（疑似漏殺）。
    private static func looksLikeCredit(_ text: String) -> Bool {
        matches(creditHint, text)
    }
}
