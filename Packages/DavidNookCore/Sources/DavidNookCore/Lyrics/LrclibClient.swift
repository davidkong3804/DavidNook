import Foundation

/// 可注入的睡眠函式（單位：秒）。測試以記錄器取代，不會真的等待。
public typealias Sleeper = @Sendable (TimeInterval) async throws -> Void

/// 抓取歌詞的抽象：`LrclibClient` 實作它，`LyricsRepository` 依賴它。
public protocol LyricsFetching: Sendable {
    /// - Returns: 挑選後的歌詞；**nil 代表確定找不到**（與網路錯誤明確區分）。
    /// - Throws: 網路或伺服器錯誤（`LrclibError`）、或 `CancellationError`；這些都不代表「找不到」。
    func lyrics(for query: LyricsQuery) async throws -> PickedLyrics?
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
}

/// LRCLIB（https://lrclib.net）用戶端：`/api/get` + `/api/search` + 變體重試 + 禮貌性節流。
///
/// ## 流程
/// 1. 以「原樣」與注入的變體（例如簡轉繁、繁轉簡的歌名／歌手名）依序呼叫 `/api/get`（帶長度，秒）；
///    **只有 404（或該筆不合用）才換下一個變體**。變體會去除重複與空歌名。沒有歌手名的變體不呼叫 `/api/get`。
/// 2. 全部沒結果才退到 `/api/search`（只帶 track_name、artist_name），同樣依序嘗試各變體。
/// 3. 候選一律交給 `LyricsCandidatePicker` 過濾與挑選（`/api/get` 的單筆也要通過長度、同步歌詞檢查）。
/// 4. 回傳挑選結果；全部找不到回傳 nil；網路／伺服器錯誤拋出 `LrclibError`。
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
        let original = Self.trimmed(query)
        guard original.hasUsableTitle else { return nil }
        let attempts = distinctAttempts(original)
        var sent = 0

        // 1. /api/get：404 或該筆不合用才換下一個變體。
        for attempt in attempts where !attempt.artist.isEmpty {
            let response = try await send(getRequest(attempt), sentSoFar: &sent)
            switch response.statusCode {
            case 200:
                let candidate = try decode(LrclibCandidate.self, from: response.body)
                if let picked = picker.pick(from: [candidate], for: original) { return picked }
            case 404:
                continue
            default:
                throw LrclibError.unexpectedStatus(response.statusCode)
            }
        }

        // 2. /api/search：同樣依序嘗試各變體。
        for attempt in attempts {
            let response = try await send(searchRequest(attempt), sentSoFar: &sent)
            switch response.statusCode {
            case 200:
                let list = try decode([LossyCandidate].self, from: response.body).compactMap(\.value)
                if let picked = picker.pick(from: list, for: original) { return picked }
            case 404:
                continue
            default:
                throw LrclibError.unexpectedStatus(response.statusCode)
            }
        }
        return nil
    }

    // MARK: - 請求建構

    private func getRequest(_ q: LyricsQuery) -> URLRequest {
        var items: [(String, String)] = [("track_name", q.title), ("artist_name", q.artist)]
        if let album = q.album, !album.isEmpty { items.append(("album_name", album)) }
        if q.duration.isFinite {
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
