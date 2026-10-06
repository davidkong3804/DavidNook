import Foundation

/// 影片來源的長度規則（影片長度＝`query.duration`，常比歌長：前奏、片尾、對白）。
public struct VideoDurationPolicy: Equatable, Sendable {
    /// 影片比歌長最多幾秒仍接受。
    public var maxLonger: TimeInterval
    /// 影片比歌短最多幾秒仍接受。
    public var maxShorter: TimeInterval
    /// 歌手未知、只靠歌名查詢時，影片比歌長最多幾秒（更嚴格）。
    public var titleOnlyMaxLonger: TimeInterval

    public init(maxLonger: TimeInterval = 60, maxShorter: TimeInterval = 5, titleOnlyMaxLonger: TimeInterval = 20) {
        self.maxLonger = maxLonger
        self.maxShorter = maxShorter
        self.titleOnlyMaxLonger = titleOnlyMaxLonger
    }
}

/// 從 LRCLIB 候選紀錄中挑出最合適的一筆同步歌詞。
///
/// ## 過濾（任一不符即剔除）
/// - `instrumental == true`。
/// - `syncedLyrics` 為 nil、空白，或解析後（剝除檔頭中繼行後）沒有任何歌詞行。
/// - 目標長度已知時：候選 `duration` 缺少，或與目標相差超過 `durationTolerance`（預設 2 秒）。
///   目標長度未知（≤ 0、NaN）時不以長度過濾、也不以長度排序。
///
/// ## 清理
/// 雙語檔（逐行附翻譯、共用時間戳）先以 `LyricsTranslationCollapser` 收合，再剝檔頭。
///
/// ## 排序（由先到後，前一項相同才看下一項）
/// 1. 長度差，以**整秒（四捨五入）**比較，避免 0.3 秒與 0.4 秒這種無意義差異壓過後面的準則。
/// 2. 原生繁體優先：`traditional`、`neutral` 同級最優；`simplified`、`mixed`（需要轉換者）次之。
/// 3. 首句（剝除檔頭後第一個非空白行，並扣掉檔內 `[offset:]`）時間貼近**候選群中位數**；
///    以 0.5 秒為一格，同一格視為相同。中位數只用通過過濾的候選計算，偶數個時取中間兩個的平均。
/// 4. **簡體殘留字數較少者優先**（只計 `traditional`／`mixed` 候選，由注入的 `residualSimplifiedCounter` 計算；
///    預設恆為 0）。放在時間軸共識之後：殘留的簡體字可由後續轉換修復，錯誤的時間軸卻無法修復。
/// 5. LRCLIB `id`（小者優先），確保結果與輸入順序無關。
///
/// 絕不使用 `albumName`（來源資料很髒）。
///
/// 簡繁分類由注入的 `scriptClassifier` 提供（餵入的是剝除檔頭後、非空白行以換行串接的全文）。
public struct LyricsCandidatePicker: Sendable {

    public let scriptClassifier: @Sendable (String) -> LyricsScript
    /// 允許的長度差，單位：秒。
    public let durationTolerance: TimeInterval
    public let stripper: LyricsMetaStripper
    /// 計算一份歌詞（逐行文字）裡「殘留的簡體字」個數；只用於排序的次要準則（見類別說明第 4 項）。
    public let residualSimplifiedCounter: @Sendable ([String]) -> Int

    /// - Parameters:
    ///   - scriptClassifier: 判斷一段歌詞全文的簡繁屬性。
    ///   - durationTolerance: 允許的長度差（秒），預設 2。
    ///   - stripper: 檔頭中繼行剝除器；需要跨簡繁比對歌名時請在其中注入 normalize。
    ///   - residualSimplifiedCounter: 殘留簡體字計數器；預設恆為 0（不影響排序）。
    public init(
        scriptClassifier: @escaping @Sendable (String) -> LyricsScript,
        durationTolerance: TimeInterval = 2,
        stripper: LyricsMetaStripper = LyricsMetaStripper(),
        residualSimplifiedCounter: @escaping @Sendable ([String]) -> Int = { _ in 0 }
    ) {
        self.scriptClassifier = scriptClassifier
        self.durationTolerance = durationTolerance
        self.stripper = stripper
        self.residualSimplifiedCounter = residualSimplifiedCounter
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
            var residue: Int
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
            // 雙語檔（原文＋翻譯共用時間戳）先收合成只剩原文，再剝檔頭、再做簡繁分類。
            let collapsed = LyricsTranslationCollapser.collapse(document.lines).lines
            let lines = stripper.strip(collapsed, title: query.title, artist: query.artist).lines
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
            let residue = (script == .traditional || script == .mixed)
                ? residualSimplifiedCounter(spoken.map(\.text)) : 0
            pool.append(Entry(
                picked: picked, durationDiff: diff, firstLineMs: first.timeMs - document.offsetMs, residue: residue
            ))
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
            return [durationRank, scriptRank, medianBucket, e.residue, e.picked.candidateID]
        }

        return pool.min { rankKey($0).lexicographicallyPrecedes(rankKey($1)) }?.picked
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let n = sorted.count
        return n % 2 == 1 ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2
    }
}
