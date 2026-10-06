import Foundation

/// 從影片標題萃取出的一組查詢候選。`artist` 為 nil 代表歌手未知（只用歌名查）。
public struct TrackTitleCandidate: Equatable, Hashable, Sendable {
    public var title: String
    public var artist: String?

    public init(_ title: String, _ artist: String?) {
        self.title = title
        self.artist = artist
    }
}

/// 把「影片標題＋頻道名」解析成歌名／歌手候選（純函式：沒有 UI、沒有網路、沒有狀態）。
///
/// 瀏覽器播 YouTube 時，「正在播放」給的 title 是影片標題（`周杰倫 Jay Chou【告白氣球 Balloon】Official MV`）、
/// artist 常是頻道名（唱片公司、`xxx - Topic`、VEVO、空白）、duration 是影片長度。本型別只負責前兩者。
///
/// ## 輸出
/// 有序候選，由最有把握到最沒把握；去重、最多 `maxCandidates` 筆。
/// 呼叫端依序嘗試，第一個查到歌詞的勝出。
///
/// ## 解析規則（細節見測試）
/// 1. **雜訊**：emoji／音符／符號、全形轉半形（只用於解析）。
/// 2. **裝飾詞**：Official MV／Music Video／Lyrics／歌詞／動態歌詞／完整版／HD／4K／官方／高音質／字幕…（中英）。
///    Latin 裝飾詞只認「片語」（`official video`、`music video`、`lyrics`、`mv`、`hd`…），不認單字 `video`／`audio`，
///    以免吃掉真正的歌名（Video Games）；括號內另外多認 `live`／`remix`／`remastered`／`version`／年份等。
///    括號內容去掉裝飾詞後為空 → 整組括號丟棄。
/// 3. **括號**：`《》「」『』` 是歌名標記；`【】` 通常也是（但也常拿來放裝飾，且方向不確定）；`()[]` 內的非裝飾內容視為別名。
///    `feat.`／`ft.`／`featuring`／`with` 的客串歌手一律丟棄。
/// 4. **分隔符**：` - `、`–`、`—`、`|`、`｜`、`:`／`：`、` / `、CJK 之間的 `-`。
///    兩段時「歌手 - 歌名」「歌名 - 歌手」方向不明：以頻道名吻合哪一側判斷；沒有線索時兩種方向都輸出（歌手在前優先）。
///    由挑選器的歌名／歌手比對把關，方向猜錯只會查不到、不會放錯歌。
/// 5. **雙語**：`周杰倫 Jay Chou`、`告白氣球 Balloon` 這種「中文＋英文」整齊拆成兩半；中文為主、英文為次候選。
/// 6. **頻道名**：去掉 ` - Topic`、`VEVO`、`Official`；唱片公司／歌詞頻道（Records、Music、Entertainment、唱片、音樂、Lyrics、Channel…）
///    不可靠，直接丟棄；可靠時只當弱提示（決定方向、補歌手），標題裡有歌手時以標題為準。
/// 7. **乾淨的標題**不被弄壞：沒有裝飾、沒有分隔的標題原樣成為第一候選（歌手＝整理過的頻道名）。
///
/// 非影片來源（bundle id 已知且不是瀏覽器，例如 Apple Music）：只回傳原值一筆，完全不解析。
/// 影片長度超過 `maxVideoDuration`（合輯、直播、整張專輯）：回傳空（寧缺勿錯）。
public enum TrackTitleExtractor {

    /// 候選數量上限（每個候選最多花 2～4 個 LRCLIB 請求）。
    public static let maxCandidates = 6
    /// 超過這個長度（秒）的影片不是單曲，不查。
    public static let maxVideoDuration: TimeInterval = 900

    // MARK: - 對外 API

    /// - Parameters:
    ///   - title: 播放器給的標題（影片標題）。
    ///   - artist: 播放器給的歌手欄（影片來源時是頻道名；可為空字串）。
    ///   - durationSeconds: 影片長度（秒；≤ 0 或 NaN 代表未知）。
    ///   - sourceBundleID: 來源 App 的 bundle id；nil／空字串時以標題特徵判斷。
    public static func candidates(
        title: String, artist: String, durationSeconds: TimeInterval, sourceBundleID: String?
    ) -> [TrackTitleCandidate] {
        let rawTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawTitle.isEmpty else { return [] }
        let rawArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)

        if let id = sourceBundleID?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty,
           !isVideoSource(bundleID: id, title: rawTitle) {
            return [TrackTitleCandidate(rawTitle, rawArtist.isEmpty ? nil : rawArtist)]
        }
        if durationSeconds.isFinite, durationSeconds > maxVideoDuration { return [] }

        let hint = channelHint(rawArtist)
        let parsed = parse(rawTitle, hint: hint)

        var seen = Set<String>()
        var result: [TrackTitleCandidate] = []
        for candidate in parsed {
            let key = fold(candidate.title) + "\u{1F}" + fold(candidate.artist ?? "")
            guard !fold(candidate.title).isEmpty, seen.insert(key).inserted else { continue }
            result.append(candidate)
            if result.count == maxCandidates { break }
        }
        return result
    }

    /// 這筆「正在播放」是不是影片：
    /// - 已知瀏覽器 → 是；已知音樂 App（Apple Music、Spotify…）→ 否（行為與影片功能加入前完全相同）；
    /// - 其他（bundle id 不認得，或 nil／空）→ 以標題特徵判斷。實測：使用者用清單外的瀏覽器（Comet）播 YouTube，
    ///   若「不認得就當乾淨來源」會讓影片標題原樣去查而找不到歌詞。
    public static func isVideoSource(bundleID: String?, title: String) -> Bool {
        if let id = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            if isBrowserBundleID(id) { return true }
            if isKnownMusicAppBundleID(id) { return false }
        }
        return looksLikeVideoTitle(title)
    }

    /// 已知的音樂播放器：標題一定是乾淨的曲名，不做影片標題解析。
    public static func isKnownMusicAppBundleID(_ id: String) -> Bool {
        let lowered = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return knownMusicAppBundleIDs.contains { lowered == $0 || lowered.hasPrefix($0 + ".") }
    }

    private static let knownMusicAppBundleIDs: [String] = [
        "com.apple.Music", "com.apple.iTunes", "com.spotify.client", "com.netease.163music",
    ].map { $0.lowercased() }

    /// 瀏覽器（含 helper、PWA／網頁 App：以 `.` 邊界做前綴比對）。
    public static func isBrowserBundleID(_ id: String) -> Bool {
        let lowered = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return browserBundleIDs.contains { lowered == $0 || lowered.hasPrefix($0 + ".") }
    }

    /// 標題長得像影片標題（只在拿不到來源 bundle id 時使用）：含 `【】｜|` 或常見影片裝飾詞。
    public static func looksLikeVideoTitle(_ title: String) -> Bool {
        if title.contains(where: { "【】｜|".contains($0) }) { return true }
        let normalized = normalize(title)
        return stripDecorations(normalized, inBrackets: false) != normalized
    }

    private static let browserBundleIDs: [String] = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.apple.WebKit",
        "com.google.Chrome", "org.chromium.Chromium",
        "org.mozilla.firefox", "org.mozilla.nightly", "org.mozilla.firefoxdeveloperedition",
        "company.thebrowser.Browser", "company.thebrowser.dia",
        "com.microsoft.edgemac", "com.brave.Browser",
        "com.operasoftware.Opera", "com.operasoftware.OperaGX", "com.vivaldi.Vivaldi",
        "com.kagi.kagimacOS", "com.duckduckgo.macos.browser", "ru.yandex.desktop.yandex-browser",
        "app.zen-browser.zen", "org.torproject.torbrowser", "com.sigmaos.sigmaos.macos",
        "ai.perplexity.comet",
    ].map { $0.lowercased() }

    // MARK: - 解析

    private enum GroupKind { case strongTitle, weakTitle, alias }
    private struct Group { var kind: GroupKind; var content: String }
    private enum Segment { case text(String); case group(Group) }

    private static func parse(_ rawTitle: String, hint: String?) -> [TrackTitleCandidate] {
        let normalized = normalize(rawTitle)
        var texts: [String] = []
        var groups: [Group] = []
        for segment in segments(normalized) {
            switch segment {
            case .text(let raw):
                let stripped = stripDecorations(raw, inBrackets: false)
                if hasContent(stripped) { texts.append(stripped) }
            case .group(let group):
                let stripped = stripDecorations(group.content, inBrackets: true)
                guard hasContent(stripped), !isFeatureText(stripped) else { continue }
                groups.append(Group(kind: group.kind, content: stripped))
            }
        }
        let outside = texts.joined(separator: " ")
        let pieces = splitSeparators(outside)

        let titleGroups = groups.filter { $0.kind != .alias }
        let aliasGroups = groups.filter { $0.kind == .alias }.map { cleanPiece($0.content) }.filter { !$0.isEmpty }

        var out: [TrackTitleCandidate] = []

        // 歌名標記括號：《》「」『』（強）、【】（弱：外側已有「A - B」結構時視為裝飾）。
        if let main = titleGroups.first(where: { $0.kind == .strongTitle })
            ?? (pieces.count >= 2 ? nil : titleGroups.first) {
            let mainTitle = cleanPiece(main.content)
            let others = titleGroups.filter { $0.content != main.content }.map { cleanPiece($0.content) }
            if let artistText = pieces.first {
                out += expand(title: mainTitle, artist: artistText)
                if main.kind == .weakTitle, pieces.count == 1 {
                    // 【周杰倫】稻香：括號可能是歌手。方向不明時補上反向（較不確定，排在後面）。
                    if let h = hint, matches(mainTitle, h) { out = expand(title: artistText, artist: mainTitle) }
                    else if let h = hint, matches(artistText, h) { out = expand(title: mainTitle, artist: artistText) }
                    else { out += expand(title: artistText, artist: mainTitle) }
                }
                for alias in others + aliasGroups { out += expand(title: alias, artist: artistText) }
            } else {
                // 外面沒有歌手：成對的括號（【周杰倫】【稻香】）以兩段處理；單一括號＝歌名，歌手取頻道名。
                if titleGroups.count >= 2 {
                    out += pairCandidates(cleanPiece(titleGroups[0].content), cleanPiece(titleGroups[1].content), hint: hint)
                } else {
                    out += withHint(title: mainTitle, hint: hint)
                    for alias in aliasGroups { out += withHint(title: alias, hint: hint) }
                }
            }
            return out
        }

        switch pieces.count {
        case 0:
            guard let alias = aliasGroups.first else { return [] }
            out += withHint(title: alias, hint: hint)
        case 1:
            out += singlePieceCandidates(pieces[0], hint: hint)
            for alias in aliasGroups { out += withHint(title: alias, hint: hint) }
        default:
            out += pairCandidates(pieces[0], pieces[1], hint: hint)
            // 沒有頻道線索時，連字號可能是歌名的一部分：整串（去裝飾後）當作最後的備援歌名。
            if !(matches(pieces[0], hint) || matches(pieces[1], hint)) {
                let whole = cleanPiece(outside)
                if !whole.isEmpty { out.append(TrackTitleCandidate(whole, hint)) }
            }
        }
        return out
    }

    // MARK: 候選組裝

    /// 只有歌名：頻道名可靠就當歌手（再補一筆純歌名備援），否則只有歌名。
    private static func withHint(title: String, hint: String?) -> [TrackTitleCandidate] {
        let expanded = expand(title: title, artist: hint)
        guard hint != nil, let first = bilingualParts(title).first else { return expanded }
        return expanded + [TrackTitleCandidate(first, nil)]
    }

    private static func singlePieceCandidates(_ piece: String, hint: String?) -> [TrackTitleCandidate] {
        // 「歌手 歌名」沒有分隔符：頻道名吻合開頭／結尾的字 → 剝掉當歌手。
        if let hint, let rest = removingHintAffix(from: piece, hint: hint) {
            return expand(title: rest, artist: hint)
        }
        // 兩段都是 CJK（周杰倫 稻香）：沒有頻道可信時，先當「歌手 歌名」，再退回整串。
        let tokens = piece.split(whereSeparator: \.isWhitespace).map(String.init)
        var splitCandidates: [TrackTitleCandidate] = []
        if tokens.count >= 2, isAllCJK(tokens[0]), tokens[0].count >= 2, tokens.dropFirst().allSatisfy(isAllCJK) {
            splitCandidates = expand(title: tokens.dropFirst().joined(separator: " "), artist: tokens[0])
        }
        let whole = withHint(title: piece, hint: hint)
        return hint == nil ? splitCandidates + whole : whole + splitCandidates
    }

    /// 兩段 A、B：頻道名吻合哪一側，那一側就是歌手；沒有線索兩種方向都輸出（A 為歌手優先）。
    private static func pairCandidates(_ a: String, _ b: String, hint: String?) -> [TrackTitleCandidate] {
        let aIsArtist = expand(title: b, artist: a)
        let bIsArtist = expand(title: a, artist: b)
        if matches(a, hint) { return aIsArtist }
        if matches(b, hint) { return bIsArtist }
        return aIsArtist + bIsArtist
    }

    /// 歌名（含雙語拆分）× 歌手（含雙語、合作歌手拆分）。
    private static func expand(title: String, artist: String?) -> [TrackTitleCandidate] {
        let titles = bilingualParts(cleanPiece(title)).filter { !$0.isEmpty }
        guard let first = titles.first else { return [] }
        guard let artist, !cleanPiece(artist).isEmpty else {
            return titles.map { TrackTitleCandidate($0, nil) }
        }
        let parts = bilingualParts(cleanPiece(artist))
        var artists: [String] = []
        for part in parts { artists.append(primaryArtist(part)) }
        for part in parts where primaryArtist(part) != part { artists.append(part) }
        artists = artists.filter { !$0.isEmpty }.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        guard let firstArtist = artists.first else { return titles.map { TrackTitleCandidate($0, nil) } }
        var out = artists.map { TrackTitleCandidate(first, $0) }
        if titles.count > 1 { out.append(TrackTitleCandidate(titles[1], firstArtist)) }
        return out
    }

    private static func primaryArtist(_ s: String) -> String {
        let separators = #"\s*(?:&|,|，|、|\+|×|\s[xX]\s|\band\b|\bvs\.?)\s*"#
        let parts = replacing(s, pattern: separators, with: "\u{1}").split(separator: "\u{1}").map(String.init)
        return cleanPiece(parts.first ?? s)
    }

    // MARK: 頻道名

    private static let labelWords = [
        "records", "recordings", "entertainment", "music group", "publishing", "studios", "media", "label",
        "network", "channel", "lyrics", "lyric", "playlist", "radio", "hits", "vevo", "music",
        "唱片", "娛樂", "娱乐", "傳媒", "传媒", "影業", "影业", "文化", "音樂", "音乐", "頻道", "频道", "歌詞", "歌词", "影音", "官方",
    ]

    /// 頻道名整理：去掉 ` - Topic`／VEVO／Official；唱片公司、歌詞頻道、泛用字回傳 nil（不可靠）。
    private static func channelHint(_ raw: String) -> String? {
        var s = normalize(raw)
        guard !s.isEmpty else { return nil }
        s = replacing(s, pattern: #"(?i)\s*-\s*topic$"#, with: "")
        var hadVevo = false
        if s.range(of: #"(?i)vevo$"#, options: .regularExpression) != nil {
            hadVevo = true
            s = replacing(s, pattern: #"(?i)\s*vevo$"#, with: "")
        }
        var previous = ""
        while previous != s {
            previous = s
            s = replacing(s, pattern: #"(?i)\s*(?:official\s+(?:youtube\s+)?(?:channel|page|account)|official|官方頻道|官方频道|官方帳號|官方账号)$"#, with: "")
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if hadVevo, !s.contains(" ") {
            s = replacing(s, pattern: #"(?<=[a-z])(?=[A-Z])"#, with: " ")     // EdSheeran → Ed Sheeran
        }
        let lowered = s.lowercased()
        guard hasContent(s), !labelWords.contains(where: { lowered.contains($0) }) else { return nil }
        return s
    }

    private static func removingHintAffix(from piece: String, hint: String) -> String? {
        let tokens = piece.split(whereSeparator: \.isWhitespace).map(String.init)
        guard tokens.count >= 2 else { return nil }
        let names = ([hint] + bilingualParts(hint)).map(fold).filter { !$0.isEmpty }
        for k in 1..<tokens.count {
            let head = fold(tokens[..<k].joined()), tail = fold(tokens[k...].joined())
            if names.contains(head) { return tokens[k...].joined(separator: " ") }
            if names.contains(tail) { return tokens[..<k].joined(separator: " ") }
        }
        return nil
    }

    private static func matches(_ piece: String, _ hint: String?) -> Bool {
        guard let hint else { return false }
        let pieceNames = ([piece] + bilingualParts(piece)).map(fold).filter { !$0.isEmpty }
        let hintNames = ([hint] + bilingualParts(hint)).map(fold).filter { !$0.isEmpty }
        for p in pieceNames {
            for h in hintNames {
                if p == h { return true }
                let (short, long) = p.count <= h.count ? (p, h) : (h, p)
                if short.count >= 2, long.contains(short) { return true }
            }
        }
        return false
    }

    // MARK: 正規化、括號、分隔

    /// 解析用正規化：全形→半形、移除符號／emoji／不可見字元、收合空白。
    /// `：`、`｜` 在轉半形前先換成帶空白的分隔符，避免 `周杰倫：稻香` 失去分隔。
    private static func normalize(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "：", with: " : ")
            .replacingOccurrences(of: "｜", with: " | ")
            .replacingOccurrences(of: "│", with: " | ")
        t = t.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? t
        // 這個轉換連 CJK 標點也轉成半形（「」、。）：還原成原本的全形，括號與頓號才認得出來。
        for (half, full) in [("｢", "「"), ("｣", "」"), ("､", "、"), ("｡", "。"), ("･", "·")] {
            t = t.replacingOccurrences(of: half, with: full)
        }
        t = t.precomposedStringWithCanonicalMapping
        var kept = String.UnicodeScalarView()
        for scalar in t.unicodeScalars {
            if scalar.isASCII, scalar.value < 0x20 || scalar.value == 0x7F { kept.append(" "); continue }
            if (0xFE00...0xFE0F).contains(scalar.value) { continue }        // variation selectors
            switch scalar.properties.generalCategory {
            case .otherSymbol, .format: continue                             // emoji、♪、©、零寬字元…
            default: kept.append(scalar)
            }
        }
        t = String(kept).replacingOccurrences(of: "\u{3000}", with: " ")
        return t.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static let openers: [Character: (close: Character, kind: GroupKind)] = [
        "《": ("》", .strongTitle), "「": ("」", .strongTitle), "『": ("』", .strongTitle),
        "【": ("】", .weakTitle), "〔": ("〕", .weakTitle), "〈": ("〉", .weakTitle),
        "(": (")", .alias), "[": ("]", .alias), "{": ("}", .alias), "<": (">", .alias),
    ]

    /// 切成「文字」與「頂層括號群組」（支援巢狀；沒配對的括號當一般字元）。
    private static func segments(_ s: String) -> [Segment] {
        var result: [Segment] = []
        var text = ""
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if let (close, kind) = openers[ch], let end = matchingClose(chars, from: i, open: ch, close: close) {
                if !text.isEmpty { result.append(.text(text)); text = "" }
                result.append(.group(Group(kind: kind, content: String(chars[(i + 1)..<end]))))
                i = end + 1
            } else {
                text.append(ch)
                i += 1
            }
        }
        if !text.isEmpty { result.append(.text(text)) }
        return result
    }

    private static func matchingClose(_ chars: [Character], from start: Int, open: Character, close: Character) -> Int? {
        var depth = 0
        for j in start..<chars.count {
            if chars[j] == open { depth += 1 }
            else if chars[j] == close { depth -= 1; if depth == 0 { return j } }
        }
        return nil
    }

    private static let separatorPattern =
        #"\s*[|｜]\s*|\s+[-–—―−]\s+|\s*[–—―]\s*|\s*:\s+|\s+:\s*|\s+/\s+|(?<=[\p{Han}\p{Hiragana}\p{Katakana}\p{Hangul}])-(?=[\p{Han}\p{Hiragana}\p{Katakana}\p{Hangul}])"#

    private static func splitSeparators(_ s: String) -> [String] {
        replacing(s, pattern: separatorPattern, with: "\u{1}")
            .split(separator: "\u{1}", omittingEmptySubsequences: true)
            .map { cleanPiece(String($0)) }
            .filter(hasContent)
    }

    private static func isFeatureText(_ s: String) -> Bool {
        s.range(of: #"(?i)^\s*(?:feat|ft|featuring|with|prod|w/)\b\.?"#, options: .regularExpression) != nil
    }

    /// 單段整理：砍掉 feat./ft. 之後、去頭尾引號與分隔符號、收合空白。
    private static func cleanPiece(_ raw: String) -> String {
        var s = replacing(raw, pattern: #"(?i)\s*[\(\[]?\s*\b(?:feat|ft|featuring)\b\.?.*$"#, with: "")
        s = s.trimmingCharacters(in: Self.trimSet)
        let quotePairs: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("‘", "’"), ("'", "'")]
        if s.count > 2, let first = s.first, let last = s.last, quotePairs.contains(where: { $0.0 == first && $0.1 == last }) {
            s = String(s.dropFirst().dropLast()).trimmingCharacters(in: Self.trimSet)
        }
        return s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static let trimSet: CharacterSet = {
        var set = CharacterSet.whitespacesAndNewlines
        set.insert(charactersIn: "-–—―|:/~·•,;、，()[]{}<>【】《》「」『』〔〕")
        return set
    }()

    /// 有任何字母／漢字才算有內容（只剩數字、標點＝空）。
    private static func hasContent(_ s: String) -> Bool { s.contains { $0.isLetter } }

    // MARK: 裝飾詞

    private static let latinBoundaryStart = "(?<![A-Za-z0-9])"
    private static let latinBoundaryEnd = "(?![A-Za-z0-9])"

    /// 一般文字與括號內都認的裝飾詞（Latin 片語；前後以 ASCII 字母數字為邊界，緊鄰 CJK 也算邊界：`官方MV`）。
    private static let commonLatin = [
        #"official\s+(?:music\s+|lyric\s+|lyrics\s+|hd\s+|visual\s+|animated\s+|dance\s+|live\s+)?(?:video|mv|m/v|audio|visuali[sz]er|clip|trailer)"#,
        #"(?:music|lyric|lyrics|visual|animated)\s+video"#,
        #"official\s+(?:channel|site|version|release|premiere|page|account)"#,
        #"with\s+lyrics"#, #"lyrics?(?:\s+on\s+screen)?"#,
        #"m/v"#, #"mv"#, #"hd"#, #"hq"#, #"uhd"#, #"fhd"#, #"[48]k"#, #"\d{3,4}p(?:60)?"#,
        #"(?:full|complete)\s+(?:song|version|album|video|mv|hd)"#,
        #"official"#,
    ]

    /// 只在括號內才當裝飾詞的字（單獨出現在標題文字裡可能是歌名的一部分）。
    private static let bracketOnlyLatin = [
        #"audio"#, #"video"#, #"visuali[sz]er"#, #"clip"#, #"teaser"#, #"trailer"#,
        #"live(?:\s+(?:at|in|from|on|@)\s+.+)?"#, #"acoustic(?:\s+version)?"#, #"remix(?:ed)?"#,
        #"(?:\d{4}\s+)?remaster(?:ed)?(?:\s+\d{4})?"#, #"[\w']+'s\s+version"#,
        #"(?:radio|single|album|extended|short|clean|explicit|original|new)\s+(?:version|edit|mix)"#,
        #"version"#, #"ver\.?"#, #"edit"#, #"cover"#, #"karaoke"#, #"instrumental"#, #"explicit"#,
        #"eng(?:lish)?\s*sub(?:title)?s?"#, #"subtitles?"#, #"sub"#, #"\d{4}"#, #"from\s+.+"#,
    ]

    /// CJK 裝飾詞（子字串比對，長的在前）。
    private static let cjkDecorations = [
        "官方完整版", "官方高清", "官方音樂影片", "官方音乐视频", "官方版", "官方",
        "完整高清", "完整版", "高音質", "高音质", "無損音質", "无损音质", "超高清", "超清", "高清",
        "動態歌詞", "动态歌词", "歌詞版", "歌词版", "歌詞", "歌词",
        "中英文字幕", "中英字幕", "中文字幕", "雙語字幕", "双语字幕", "字幕", "中字",
        "音樂影片", "音乐视频", "首播", "正式版",
    ]

    private static func stripDecorations(_ s: String, inBrackets: Bool) -> String {
        var t = s
        let latin = inBrackets ? commonLatin + bracketOnlyLatin : commonLatin
        let pattern = latinBoundaryStart + "(?:" + latin.joined(separator: "|") + ")" + latinBoundaryEnd
        t = replacing(t, pattern: "(?i)" + pattern, with: " ")
        for phrase in cjkDecorations { t = t.replacingOccurrences(of: phrase, with: " ") }
        return t.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // MARK: 雙語拆分

    /// `告白氣球 Balloon`、`Jay Chou 周杰倫` 這種「CJK 段＋Latin 段」整齊相接的字串拆成 [CJK 段, Latin 段]；
    /// 不是剛好一次轉換（`我的 Love 你的`）就原樣回傳 [s]。
    private static func bilingualParts(_ s: String) -> [String] {
        let tokens = s.split(whereSeparator: \.isWhitespace).map(String.init)
        guard tokens.count >= 2 else { return [s] }
        enum Kind { case cjk, latin, neutral }
        func kind(_ token: String) -> Kind {
            if token.unicodeScalars.contains(where: isCJKScalar) { return .cjk }
            return token.contains { $0.isLetter } ? .latin : .neutral
        }
        var kinds = tokens.map(kind)
        for i in kinds.indices where kinds[i] == .neutral {
            kinds[i] = i > 0 ? kinds[i - 1] : (kinds.first { $0 != .neutral } ?? .latin)
        }
        let switches = (1..<kinds.count).filter { kinds[$0] != kinds[$0 - 1] }
        guard switches.count == 1, let at = switches.first else { return [s] }
        let head = tokens[..<at].joined(separator: " "), tail = tokens[at...].joined(separator: " ")
        return kinds[0] == .cjk ? [head, tail] : [tail, head]
    }

    private static func isCJKScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0x20000...0x2A6DF, 0xF900...0xFAFF,
             0x3040...0x30FF, 0xAC00...0xD7AF, 0x3100...0x312F: return true
        default: return false
        }
    }

    private static func isAllCJK(_ s: String) -> Bool {
        !s.isEmpty && s.unicodeScalars.allSatisfy { isCJKScalar($0) }
    }

    // MARK: 小工具

    /// 比對用：小寫，只留字母與數字。
    private static func fold(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func replacing(_ s: String, pattern: String, with template: String) -> String {
        s.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
    }
}
