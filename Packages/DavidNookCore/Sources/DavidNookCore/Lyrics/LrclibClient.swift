import Foundation

/// 可注入的睡眠函式（單位：秒）。測試以記錄器取代，不會真的等待。
public typealias Sleeper = @Sendable (TimeInterval) async throws -> Void

/// 一次抓取的結果：歌詞（nil＝確定找不到）與「是否為退而求其次的結果」。
public struct LyricsFetchOutcome: Equatable, Sendable {
    public var lyrics: PickedLyrics?
    /// true＝`/api/search` 失敗，只好採用 `/api/get` 的單筆結果（沒有經過多版本共識排序）。
    /// 倉庫不會把這種結果寫進快取，下次播放會重新嘗試取得共識版本。
    public var isDegraded: Bool

    public init(lyrics: PickedLyrics?, isDegraded: Bool = false) {
        self.lyrics = lyrics
        self.isDegraded = isDegraded
    }
}

/// 抓取歌詞的抽象：`LrclibClient` 實作它，`LyricsRepository` 依賴它。
public protocol LyricsFetching: Sendable {
    /// - Returns: 挑選後的歌詞；**nil 代表確定找不到**（與網路錯誤明確區分）。
    /// - Throws: 網路或伺服器錯誤（`LrclibError`）、或 `CancellationError`；這些都不代表「找不到」。
    func lyrics(for query: LyricsQuery) async throws -> PickedLyrics?

    /// 同 `lyrics(for:)`，但附帶「是否為退而求其次的結果」。預設實作回傳非 degraded。
    func fetch(_ query: LyricsQuery) async throws -> LyricsFetchOutcome
}

extension LyricsFetching {
    public func fetch(_ query: LyricsQuery) async throws -> LyricsFetchOutcome {
        LyricsFetchOutcome(lyrics: try await lyrics(for: query))
    }
}

/// LRCLIB 用戶端錯誤。都不代表「找不到歌詞」（找不到是回傳 nil）。
public enum LrclibError: Error, Equatable, Sendable {
    /// 傳輸層失敗（無網路、逾時、DNS…），附錯誤描述。
    case network(String)
    /// 被 429 限流且無法（或不該）繼續等：`retryAfter` 為伺服器要求等待的秒數。
    case rateLimited(retryAfter: TimeInterval)
    /// 503 重試用盡仍然忙碌。
    case serverOverloaded
    /// 非預期的 HTTP 狀態碼（例如 400、500）。
    case unexpectedStatus(Int)
    /// 200 但內容無法解碼。
    case invalidResponse

    /// `/api/get` 失敗後是否仍值得改試 `/api/search`。
    /// 限流（429）、伺服器忙碌（503 用盡）、網路錯誤代表伺服器正要我們退讓或根本連不上，再送請求只是浪費；
    /// 其餘（非預期狀態碼、壞掉的回應內容）是 get 端點自己的問題，search 仍可能成功。
    var allowsSearchAfterGetFailure: Bool {
        switch self {
        case .unexpectedStatus, .invalidResponse: return true
        case .network, .rateLimited, .serverOverloaded: return false
        }
    }
}

/// LRCLIB（https://lrclib.net）用戶端：`/api/get` + `/api/search` + 變體重試 + 禮貌性節流。
///
/// ## 流程（多版本共識）
/// 同一首歌在 LRCLIB 有許多版本，時間軸可差 10 秒以上；`/api/get` 只回「一筆」，可能正是離群版本。
/// 所以 get 的結果**不直接採用**，而是併入 search 的候選池，統一由 `LyricsCandidatePicker` 以多數版本共識排序。
/// 1. 以「原樣」與注入的變體（例如簡轉繁、繁轉簡的歌名／歌手名）依序呼叫 `/api/get`（帶長度，秒）；
///    **只有 404（或該筆不合用）才換下一個變體**。變體會去除重複與空歌名。沒有歌手名的變體不呼叫 `/api/get`。
/// 2. 再呼叫 `/api/search`（只帶 track_name、artist_name）：get 命中時只送一次、用命中的那種寫法；
///    沒有 get 結果時依序嘗試各變體，到第一個有可用候選的為止。get 的單筆（以 id 去重）併入候選池。
/// 3. 候選一律交給 `LyricsCandidatePicker` 過濾與挑選（`/api/get` 的單筆也要通過長度、同步歌詞檢查）。
/// 4. 回傳挑選結果；全部找不到回傳 nil；網路／伺服器錯誤拋出 `LrclibError`。
///
/// ## 失敗處理
/// - search 失敗（429／503 用盡、網路、壞回應）而手上有 get 的結果：退而使用它，並標記 `isDegraded`
///   （倉庫不快取，下次重新取得共識版本）。沒有 get 結果就照實拋出。
/// - get 因 429／503 用盡／網路錯誤失敗：直接拋出，不再送 search（伺服器正要我們退讓）；
///   get 回其他非預期狀態碼或壞內容：仍試 search，search 沒有可用結果時才拋出 get 的錯誤。
/// - 兩者都 404（或 search 空）→ nil。
///
/// ## 遵守伺服器規範
/// - 每個請求都帶 `User-Agent: DavidNook/<版本> (https://github.com/davidkong3804/DavidNook)`。
/// - 429：讀 `Retry-After`（秒）睡滿再重試，最多重試 2 次；等待時間超過 `maxRetryAfter` 或重試用盡則拋
///   `LrclibError.rateLimited`。429 也會設下「冷卻期」，期間內後續呼叫會先睡到冷卻結束（過長則直接拋錯、不發請求）。
/// - 503：重試最多 2 次；有 `Retry-After` 就遵守，否則等 1 秒。
/// - 連續請求之間睡 `requestSpacing`（預設 0.25 秒，LRCLIB 建議 200–500ms）。
public final class LrclibClient: LyricsFetching, @unchecked Sendable {

    /// 429 沒有（可解析的）`Retry-After` 時的等待秒數。
    public static let fallbackRetryAfter: TimeInterval = 2
    /// 503 沒有（可解析的）`Retry-After` 時的等待秒數（LRCLIB 文件：通常 1 秒）。
    public static let fallbackServerRetryAfter: TimeInterval = 1
    /// 429 最多重試次數。
    public static let maxRateLimitRetries = 2
    /// 503 最多重試次數。
    public static let maxServerRetries = 2

    /// 預設睡眠：以 `Task.sleep` 實作，可被取消。
    public static let defaultSleeper: Sleeper = { seconds in
        guard seconds > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(min(seconds, 3_600) * 1_000_000_000))
    }

    /// 自報身分用的 User-Agent。
    public static func userAgent(appVersion: String) -> String {
        "DavidNook/\(appVersion) (https://github.com/davidkong3804/DavidNook)"
    }

    private let transport: any HTTPTransport
    private let picker: LyricsCandidatePicker
    private let variants: @Sendable (LyricsQuery) -> [LyricsQuery]
    private let sleeper: Sleeper
    private let now: @Sendable () -> Date
    private let baseURL: URL
    private let userAgent: String
    private let requestSpacing: TimeInterval
    private let maxRetryAfter: TimeInterval

    private let lock = NSLock()
    private var cooldownUntil: Date?

    /// - Parameters:
    ///   - transport: HTTP 傳輸層（正式用 `URLSessionTransport()`，測試用 stub）。
    ///   - picker: 候選挑選器（簡繁分類閉包由它帶入）。
    ///   - variants: 變體產生器：給原始查詢，回傳其他寫法（依嘗試順序，例如 [簡轉繁, 繁轉簡]）；「原樣」固定最先嘗試。
    ///   - sleeper: 睡眠函式（可注入）。
    ///   - now: 目前時間（用於 429 冷卻期；可注入）。
    ///   - appVersion: 放進 User-Agent 的版本字串。
    ///   - baseURL: API 主機，預設 https://lrclib.net。
    ///   - requestSpacing: 連續請求之間的間隔（秒）。
    ///   - maxRetryAfter: 願意等待的 `Retry-After` 上限（秒）；超過就不等、直接拋錯。
    public init(
        transport: any HTTPTransport,
        picker: LyricsCandidatePicker,
        variants: @escaping @Sendable (LyricsQuery) -> [LyricsQuery] = { _ in [] },
        sleeper: @escaping Sleeper = LrclibClient.defaultSleeper,
        now: @escaping @Sendable () -> Date = { Date() },
        appVersion: String = DavidNookCore.version,
        baseURL: URL = URL(string: "https://lrclib.net")!,
        requestSpacing: TimeInterval = 0.25,
        maxRetryAfter: TimeInterval = 30
    ) {
        self.transport = transport
        self.picker = picker
        self.variants = variants
        self.sleeper = sleeper
        self.now = now
        self.baseURL = baseURL
        self.userAgent = Self.userAgent(appVersion: appVersion)
        self.requestSpacing = requestSpacing
        self.maxRetryAfter = maxRetryAfter
    }

    // MARK: - LyricsFetching

    public func lyrics(for query: LyricsQuery) async throws -> PickedLyrics? {
        try await fetch(query).lyrics
    }

    public func fetch(_ query: LyricsQuery) async throws -> LyricsFetchOutcome {
        let original = Self.trimmed(query)
        guard original.hasUsableTitle else { return LyricsFetchOutcome(lyrics: nil) }
        let attempts = distinctAttempts(original)
        var sent = 0

        // 1. /api/get：404 或該筆不合用才換下一個變體；命中就記下「候選＋是哪一種寫法命中的」。
        var getHit: (candidate: LrclibCandidate, attempt: LyricsQuery)?
        var getFailure: LrclibError?
        for attempt in attempts where !attempt.artist.isEmpty {
            do {
                let response = try await send(getRequest(attempt), sentSoFar: &sent)
                switch response.statusCode {
                case 200:
                    let candidate = try decode(LrclibCandidate.self, from: response.body)
                    if picker.pick(from: [candidate], for: original) != nil { getHit = (candidate, attempt) }
                case 404:
                    break
                default:
                    throw LrclibError.unexpectedStatus(response.statusCode)
                }
            } catch let error as LrclibError where error.allowsSearchAfterGetFailure {
                getFailure = error          // get 端點本身怪怪的：不再試其他 get 變體，改走 search
            }
            if getHit != nil || getFailure != nil { break }
        }

        // 2. /api/search：get 的單筆併入搜尋結果（以 id 去重），統一交給 Picker 以多版本共識排序。
        //    get 命中時只送一次 search（用 get 命中的那種寫法，最可能列出同曲的其他版本）；
        //    沒有 get 結果時才依序嘗試各變體。
        let getPick = getHit.flatMap { picker.pick(from: [$0.candidate], for: original) }
        let searchAttempts = getHit.map { [$0.attempt] } ?? attempts
        for attempt in searchAttempts {
            do {
                let response = try await send(searchRequest(attempt), sentSoFar: &sent)
                switch response.statusCode {
                case 200:
                    let list = try decode([LossyCandidate].self, from: response.body).compactMap(\.value)
                    if let getHit {
                        let pool = Self.merged(getHit.candidate, list)
                        return LyricsFetchOutcome(lyrics: picker.pick(from: pool, for: original) ?? getPick)
                    }
                    if let picked = picker.pick(from: list, for: original) { return LyricsFetchOutcome(lyrics: picked) }
                case 404:
                    continue
                default:
                    throw LrclibError.unexpectedStatus(response.statusCode)
                }
            } catch let error as LrclibError {
                // search 失敗（429／503 用盡、網路、壞回應…）：有 get 的結果就退而用它；否則照實拋出。
                if let getPick { return LyricsFetchOutcome(lyrics: getPick, isDegraded: true) }
                throw error
            }
        }

        if let getPick { return LyricsFetchOutcome(lyrics: getPick) }     // search 成功但沒有結果：get 是唯一版本
        if let getFailure { throw getFailure }                             // get 失敗、search 又沒結果：不能宣稱「找不到」
        return LyricsFetchOutcome(lyrics: nil)
    }

    /// 把 get 的單筆放在最前面併入搜尋結果，以 id 去重（同一筆紀錄不算兩票）。
    private static func merged(_ first: LrclibCandidate, _ rest: [LrclibCandidate]) -> [LrclibCandidate] {
        var seen: Set<Int> = []
        return ([first] + rest).filter { seen.insert($0.id).inserted }
    }

    // MARK: - 請求建構

    private func getRequest(_ q: LyricsQuery) -> URLRequest {
        var items: [(String, String)] = [("track_name", q.title), ("artist_name", q.artist)]
        if let album = q.album, !album.isEmpty { items.append(("album_name", album)) }
        // 影片來源（isVideoDerived）：duration 是影片長度、不是歌長，LRCLIB 的 get 會以它比對而查不到，所以不帶；
        // 長度由挑選器的影片規則把關。
        if q.duration.isFinite, !q.isVideoDerived {
            let seconds = Int(min(max(q.duration, -1), 1e9).rounded())
            if (1...3_600).contains(seconds) { items.append(("duration", String(seconds))) }
        }
        return makeRequest(path: "/api/get", items: items)
    }

    private func searchRequest(_ q: LyricsQuery) -> URLRequest {
        var items: [(String, String)] = [("track_name", q.title)]
        if !q.artist.isEmpty { items.append(("artist_name", q.artist)) }
        return makeRequest(path: "/api/search", items: items)
    }

    private func makeRequest(path: String, items: [(String, String)]) -> URLRequest {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        components.path = path
        components.percentEncodedQuery = items.map { "\(Self.encode($0.0))=\(Self.encode($0.1))" }.joined(separator: "&")
        var request = URLRequest(url: components.url ?? baseURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// 只保留 RFC 3986 unreserved 字元，其餘（含空白、`+`、`&`、`=`、中文）一律百分號編碼。
    private static let queryValueAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    private static func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: queryValueAllowed) ?? s
    }

    private static func trimmed(_ q: LyricsQuery) -> LyricsQuery {
        var copy = q
        copy.title = q.title.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.artist = q.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.album = q.album?.trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }

    /// 「原樣」＋注入的變體，去除空歌名與（歌名, 歌手）重複者，保留順序。
    private func distinctAttempts(_ original: LyricsQuery) -> [LyricsQuery] {
        var seen = Set<[String]>()
        var result: [LyricsQuery] = []
        for candidate in [original] + variants(original).map(Self.trimmed) {
            guard candidate.hasUsableTitle else { continue }
            if seen.insert([candidate.title, candidate.artist]).inserted { result.append(candidate) }
        }
        return result
    }

    // MARK: - 發送、重試、節流

    /// 連續請求之間先睡 `requestSpacing`（第一個請求前不睡），再走重試迴圈。
    private func send(_ request: URLRequest, sentSoFar sent: inout Int) async throws -> HTTPResponse {
        if sent > 0, requestSpacing > 0 { try await sleeper(requestSpacing) }
        sent += 1
        return try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> HTTPResponse {
        var rateLimitRetries = 0
        var serverRetries = 0
        while true {
            try await waitForCooldown()

            let response: HTTPResponse
            do {
                response = try await transport.send(request)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            } catch {
                throw LrclibError.network(error.localizedDescription)
            }

            switch response.statusCode {
            case 429:
                let wait = Self.retryAfter(response) ?? Self.fallbackRetryAfter
                setCooldown(wait)
                if rateLimitRetries >= Self.maxRateLimitRetries || wait > maxRetryAfter {
                    throw LrclibError.rateLimited(retryAfter: wait)
                }
                rateLimitRetries += 1
                continue                                   // 迴圈開頭的 waitForCooldown 會睡滿 Retry-After
            case 503:
                let wait = Self.retryAfter(response) ?? Self.fallbackServerRetryAfter
                if serverRetries >= Self.maxServerRetries || wait > maxRetryAfter {
                    throw LrclibError.serverOverloaded
                }
                serverRetries += 1
                try await sleeper(wait)
                continue
            default:
                return response
            }
        }
    }

    private func setCooldown(_ seconds: TimeInterval) {
        let until = now().addingTimeInterval(seconds)
        lock.withLock { cooldownUntil = until }
    }

    private func currentCooldown() -> Date? {
        lock.withLock { cooldownUntil }
    }

    private func clearCooldown(ifStill until: Date) {
        lock.withLock { if cooldownUntil == until { cooldownUntil = nil } }
    }

    /// 若仍在 429 冷卻期內：剩餘時間 ≤ 上限就睡完，否則直接拋 `rateLimited`（不發請求）。
    private func waitForCooldown() async throws {
        guard let until = currentCooldown() else { return }
        let remaining = until.timeIntervalSince(now())
        if remaining > 0 {
            if remaining > maxRetryAfter { throw LrclibError.rateLimited(retryAfter: remaining) }
            try await sleeper(remaining)
        }
        clearCooldown(ifStill: until)
    }

    /// 解析 `Retry-After` 的秒數（整數或小數）；HTTP-date 或亂碼回傳 nil（改用預設值）。
    private static func retryAfter(_ response: HTTPResponse) -> TimeInterval? {
        guard let raw = response.header("Retry-After") else { return nil }
        guard let value = Double(raw.trimmingCharacters(in: .whitespaces)), value.isFinite, value >= 0 else { return nil }
        return value
    }

    // MARK: - 解碼

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw LrclibError.invalidResponse
        }
    }

    /// 陣列解碼時單筆壞資料不拖垮整體。
    private struct LossyCandidate: Decodable {
        let value: LrclibCandidate?
        init(from decoder: Decoder) throws {
            value = try? LrclibCandidate(from: decoder)
        }
    }
}
