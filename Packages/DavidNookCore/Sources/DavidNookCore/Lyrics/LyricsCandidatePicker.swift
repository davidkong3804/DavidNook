import Foundation

/// 從 LRCLIB 候選紀錄中挑出最合適的一筆同步歌詞。
///
/// ## 過濾（任一不符即剔除）
/// - `instrumental == true`。
/// - `syncedLyrics` 為 nil、空白，或解析後（剝除檔頭中繼行後）沒有任何歌詞行。
/// - 目標長度已知時：候選 `duration` 缺少，或與目標相差超過 `durationTolerance`（預設 2 秒）。
///   目標長度未知（≤ 0、NaN）時不以長度過濾、也不以長度排序。
///
/// ## 排序（由先到後，前一項相同才看下一項）
/// 1. 長度差，以**整秒（四捨五入）**比較，避免 0.3 秒與 0.4 秒這種無意義差異壓過後面的準則。
/// 2. 原生繁體優先：`traditional`、`neutral` 同級最優；`simplified`、`mixed`（需要轉換者）次之。
/// 3. 首句（剝除檔頭後第一個非空白行，並扣掉檔內 `[offset:]`）時間貼近**候選群中位數**；
///    以 0.5 秒為一格，同一格視為相同。中位數只用通過過濾的候選計算，偶數個時取中間兩個的平均。
/// 4. LRCLIB `id`（小者優先），確保結果與輸入順序無關。
///
/// 絕不使用 `albumName`（來源資料很髒）。
///
/// 簡繁分類由注入的 `scriptClassifier` 提供（餵入的是剝除檔頭後、非空白行以換行串接的全文）。
public struct LyricsCandidatePicker: Sendable {

    public let scriptClassifier: @Sendable (String) -> LyricsScript
    /// 允許的長度差，單位：秒。
    public let durationTolerance: TimeInterval
    public let stripper: LyricsMetaStripper

    /// - Parameters:
    ///   - scriptClassifier: 判斷一段歌詞全文的簡繁屬性。
    ///   - durationTolerance: 允許的長度差（秒），預設 2。
    ///   - stripper: 檔頭中繼行剝除器；需要跨簡繁比對歌名時請在其中注入 normalize。
    public init(
        scriptClassifier: @escaping @Sendable (String) -> LyricsScript,
        durationTolerance: TimeInterval = 2,
        stripper: LyricsMetaStripper = LyricsMetaStripper()
    ) {
        self.scriptClassifier = scriptClassifier
        self.durationTolerance = durationTolerance
        self.stripper = stripper
    }

    /// 挑出最佳候選；沒有任何候選通過過濾回傳 nil。
    /// - Parameters:
    ///   - candidates: LRCLIB 候選（`/api/get` 的單筆或 `/api/search` 的結果）。
    ///   - query: 目前曲目（長度單位：秒）。
    public func pick(from candidates: [LrclibCandidate], for query: LyricsQuery) -> PickedLyrics? {
        let knownDuration = query.duration.isFinite && query.duration > 0

        struct Entry {
            var picked: PickedLyrics
            var durationDiff: Double
            var firstLineMs: Int
        }

        var pool: [Entry] = []
        for candidate in candidates {
            if candidate.instrumental { continue }
            guard let synced = candidate.syncedLyrics,
                  !synced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }

            var diff = 0.0
            if knownDuration {
                guard let d = candidate.duration, d.isFinite else { continue }
                diff = abs(d - query.duration)
                if diff > durationTolerance { continue }
            }

            let document = LRCParser.parse(synced)
            let lines = stripper.strip(document.lines, title: query.title, artist: query.artist).lines
            let spoken = lines.filter { !$0.isBlank }
            guard let first = spoken.first else { continue }

            let script = scriptClassifier(spoken.map(\.text).joined(separator: "\n"))
            let picked = PickedLyrics(
                candidateID: candidate.id,
                trackName: candidate.trackName,
                artistName: candidate.artistName,
                script: script,
                lines: lines,
                offsetMs: document.offsetMs,
                metadata: document.metadata
            )
            pool.append(Entry(picked: picked, durationDiff: diff, firstLineMs: first.timeMs - document.offsetMs))
        }
        guard !pool.isEmpty else { return nil }

        let median = Self.median(pool.map { Double($0.firstLineMs) })

        func rankKey(_ e: Entry) -> [Int] {
            let durationRank = Int(e.durationDiff.rounded())
            let scriptRank: Int
            switch e.picked.script {
            case .traditional, .neutral: scriptRank = 0
            case .simplified, .mixed: scriptRank = 1
            }
            let medianBucket = Int((abs(Double(e.firstLineMs) - median) / 500).rounded())
            return [durationRank, scriptRank, medianBucket, e.picked.candidateID]
        }

        return pool.min { rankKey($0).lexicographicallyPrecedes(rankKey($1)) }?.picked
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let n = sorted.count
        return n % 2 == 1 ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2
    }
}
