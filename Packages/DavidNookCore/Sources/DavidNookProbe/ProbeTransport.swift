import CryptoKit
import DavidNookCore
import Foundation

/// 稽核工具專用的 HTTP 傳輸層：磁碟快取＋全域節流＋請求預算。
///
/// - 同一個 URL 只要在快取（200／404）就不再連網，所以「修程式前後」各跑一次管線，第二次完全離線、零請求。
/// - 連網請求之間至少間隔 `minInterval` 秒（預設 1.25，任務規定 ≥ 1.2）。
/// - 預算（預設 120）以**連網請求數**計，跨多次執行累計（寫在 `<cache>/_ledger.json`）；超過就拋 `budgetExhausted`，
///   不會悄悄多送。429／503 也計入（重試也是請求），並逐筆記在帳本。
/// - 一律把 `User-Agent` 覆寫成任務規定的 probe 身分。
final class ProbeTransport: HTTPTransport, @unchecked Sendable {

    static let userAgent = "DavidNook-probe/0.1 (https://github.com/davidkong3804/DavidNook)"

    enum Failure: Error, CustomStringConvertible {
        case budgetExhausted(limit: Int)
        case offlineCacheMiss(String)
        var description: String {
            switch self {
            case .budgetExhausted(let limit): return "請求預算已用盡（上限 \(limit)）"
            case .offlineCacheMiss(let url): return "--offline 且快取沒有：\(url)"
            }
        }
    }

    struct LedgerEntry: Codable {
        var time: String
        var url: String
        var status: Int
        var bytes: Int
        var retryAfter: String?
    }

    struct Ledger: Codable {
        var entries: [LedgerEntry] = []
        var total: Int { entries.count }
        func count(status: Int) -> Int { entries.filter { $0.status == status }.count }
    }

    struct Record: Codable {
        var path: String
        var status: Int
        var source: String   // "live" | "cache"
        var bytes: Int
    }

    private struct CacheFile: Codable {
        var url: String
        var status: Int
        var headers: [String: String]
        var body: String
    }

    private let cacheDirectory: URL
    private let offline: Bool
    private let budget: Int
    private let minInterval: TimeInterval
    private let live = URLSessionTransport()
    private let lock = NSLock()
    private var ledger: Ledger
    private var lastLive: Date?
    private var misses = 0
    private var current: [Record] = []
    private var currentBodies: [(path: String, status: Int, body: Data)] = []

    init(cacheDirectory: URL, offline: Bool, budget: Int, minInterval: TimeInterval = 1.25) throws {
        self.cacheDirectory = cacheDirectory
        self.offline = offline
        self.budget = budget
        self.minInterval = minInterval
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let ledgerURL = cacheDirectory.appendingPathComponent("_ledger.json")
        if let data = try? Data(contentsOf: ledgerURL), let decoded = try? JSONDecoder().decode(Ledger.self, from: data) {
            ledger = decoded
        } else {
            ledger = Ledger()
        }
    }

    // MARK: - 每首歌的請求記錄

    func beginSong() { lock.withLock { current = []; currentBodies = [] } }

    /// 取回這首歌發出的請求記錄與回應本文（供管線階段回頭查被選中的候選原始內容）。
    func endSong() -> (records: [Record], bodies: [(path: String, status: Int, body: Data)]) {
        lock.withLock {
            let result = (current, currentBodies)
            current = []
            currentBodies = []
            return result
        }
    }

    var ledgerSnapshot: Ledger { lock.withLock { ledger } }

    /// `--offline` 時快取沒有而被拒絕的請求數（離線重跑應為 0，否則對照不完整）。
    var offlineMissCount: Int { lock.withLock { misses } }

    // MARK: - HTTPTransport

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        guard let url = request.url else { throw URLError(.badURL) }
        let path = url.path + (url.query.map { "?\($0)" } ?? "")
        let cacheURL = cacheDirectory.appendingPathComponent(Self.key(url.absoluteString) + ".json")

        if let data = try? Data(contentsOf: cacheURL), let cached = try? JSONDecoder().decode(CacheFile.self, from: data) {
            let body = Data(cached.body.utf8)
            lock.withLock {
                current.append(Record(path: path, status: cached.status, source: "cache", bytes: body.count))
                currentBodies.append((path, cached.status, body))
            }
            return HTTPResponse(statusCode: cached.status, headers: cached.headers, body: body)
        }
        if offline {
            lock.withLock { misses += 1 }
            log("離線快取未命中：\(path)")
            throw Failure.offlineCacheMiss(path)
        }

        // 預算檢查＋預先計數（先寫帳本再送，連失敗的請求也算）。
        let wait: TimeInterval = try lock.withLock {
            if ledger.total >= budget { throw Failure.budgetExhausted(limit: budget) }
            guard let last = lastLive else { return 0 }
            return max(0, minInterval - Date().timeIntervalSince(last))
        }
        if wait > 0 { try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }

        var liveRequest = request
        liveRequest.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        lock.withLock { lastLive = Date() }
        let response: HTTPResponse
        do {
            response = try await self.live.send(liveRequest)
        } catch {
            record(url: path, status: -1, bytes: 0, retryAfter: nil)
            lock.withLock { current.append(Record(path: path, status: -1, source: "live", bytes: 0)) }
            throw error
        }
        lock.withLock { lastLive = Date() }
        record(url: path, status: response.statusCode, bytes: response.body.count, retryAfter: response.header("Retry-After"))
        lock.withLock {
            current.append(Record(path: path, status: response.statusCode, source: "live", bytes: response.body.count))
            currentBodies.append((path, response.statusCode, response.body))
        }

        if response.statusCode == 200 || response.statusCode == 404 {
            let file = CacheFile(
                url: url.absoluteString, status: response.statusCode, headers: response.headers,
                body: String(decoding: response.body, as: UTF8.self)
            )
            if let data = try? JSONEncoder().encode(file) { try? data.write(to: cacheURL, options: .atomic) }
        }
        return response
    }

    // MARK: - 內部

    private func record(url: String, status: Int, bytes: Int, retryAfter: String?) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        lock.withLock {
            ledger.entries.append(LedgerEntry(time: stamp, url: url, status: status, bytes: bytes, retryAfter: retryAfter))
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            if let data = try? enc.encode(ledger) {
                try? data.write(to: cacheDirectory.appendingPathComponent("_ledger.json"), options: .atomic)
            }
        }
    }

    static func key(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// 與 `LrclibClient` 的 `/api/search` 請求完全相同的 URL（快取鍵相同，管線階段才能命中調查階段的結果）。
    static func searchRequest(title: String, artist: String) -> URLRequest {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s }
        var items: [(String, String)] = [("track_name", title)]
        if !artist.isEmpty { items.append(("artist_name", artist)) }
        var components = URLComponents(url: URL(string: "https://lrclib.net")!, resolvingAgainstBaseURL: false) ?? URLComponents()
        components.path = "/api/search"
        components.percentEncodedQuery = items.map { "\(enc($0.0))=\(enc($0.1))" }.joined(separator: "&")
        var request = URLRequest(url: components.url ?? URL(string: "https://lrclib.net")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}
