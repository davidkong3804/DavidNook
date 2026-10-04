import Foundation
import XCTest
@testable import DavidNookCore

// 所有測試樣本皆為自編的虛構句子，不含任何受版權保護的真實歌詞。
// 所有 HTTP 一律走 StubTransport，測試不會連外網。

/// 簡短建構 LRCLine（時間單位：毫秒）。
func L(_ ms: Int, _ text: String) -> LRCLine { LRCLine(timeMs: ms, text: text) }

/// 以 NSLock 保護的可變盒子，供 @Sendable 閉包記錄呼叫。
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    @discardableResult
    func withLock<R>(_ body: (inout Value) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
    var snapshot: Value { withLock { $0 } }
}

/// 可手動撥動的時鐘（取代真實 Date()）。
final class ManualClock: @unchecked Sendable {
    static let reference = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let state: Locked<Date>
    init(_ start: Date = ManualClock.reference) { state = Locked(start) }
    func now() -> Date { state.snapshot }
    func advance(_ seconds: TimeInterval) { state.withLock { $0 = $0.addingTimeInterval(seconds) } }
    func set(_ date: Date) { state.withLock { $0 = date } }
    var provider: @Sendable () -> Date { { [self] in self.now() } }
}

/// 記錄 sleeper 被要求睡多久（不真的睡）。
final class SleepRecorder: @unchecked Sendable {
    private let calls = Locked<[TimeInterval]>([])
    var durations: [TimeInterval] { calls.snapshot }
    var sleeper: Sleeper {
        { [self] seconds in self.calls.withLock { $0.append(seconds) } }
    }
}

/// 以腳本或 handler 回應的假傳輸層；絕不連網。
final class StubTransport: HTTPTransport, @unchecked Sendable {
    enum Step {
        case response(HTTPResponse)
        case failure(Error)
    }
    typealias Handler = @Sendable (URLRequest, Int) -> Step

    private let handler: Handler
    private let state = Locked<[URLRequest]>([])

    init(handler: @escaping Handler) { self.handler = handler }

    /// 依序回放腳本；腳本用完仍被呼叫會讓測試失敗。
    convenience init(steps: [Step]) {
        self.init(handler: { request, index in
            if index < steps.count { return steps[index] }
            XCTFail("腳本用完後仍有請求 #\(index): \(request.url?.absoluteString ?? "nil")")
            return .response(HTTPResponse(statusCode: 599, headers: [:], body: Data()))
        })
    }

    var requests: [URLRequest] { state.snapshot }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let index = state.withLock { requests -> Int in
            requests.append(request)
            return requests.count - 1
        }
        switch handler(request, index) {
        case .response(let response): return response
        case .failure(let error): throw error
        }
    }
}

extension StubTransport.Step {
    static func ok(_ json: String, headers: [String: String] = [:]) -> Self {
        var h = headers
        h["Content-Type"] = "application/json"
        return .response(HTTPResponse(statusCode: 200, headers: h, body: Data(json.utf8)))
    }
    static func status(_ code: Int, retryAfter: String? = nil, body: String = "") -> Self {
        var h: [String: String] = [:]
        if let retryAfter { h["Retry-After"] = retryAfter }
        return .response(HTTPResponse(statusCode: code, headers: h, body: Data(body.utf8)))
    }
    static var notFound: Self {
        .status(404, body: #"{"message":"Failed to find specified track","name":"TrackNotFound","statusCode":404}"#)
    }
}

// MARK: - JSON 與請求檢視

func jsonString(_ object: Any) -> String {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(data: data, encoding: .utf8)!
}

/// 模擬 LRCLIB 回傳的單筆紀錄（含若干本模組不使用的欄位，以驗證解碼容錯）。
func recordObject(
    id: Int,
    track: String = "T",
    artist: String = "A",
    album: String? = "Alb",
    duration: Double = 200,
    instrumental: Bool = false,
    synced: String?
) -> [String: Any] {
    [
        "id": id,
        "name": track,
        "trackName": track,
        "artistName": artist,
        "albumName": album.map { $0 as Any } ?? NSNull(),
        "duration": duration,
        "instrumental": instrumental,
        "hasWordSync": false,
        "plainLyrics": NSNull(),
        "syncedLyrics": synced.map { $0 as Any } ?? NSNull(),
        "lyricsfile": "version: '1.0'",
    ]
}

/// 解碼後的 query items（已還原百分號編碼）。
func queryItems(_ request: URLRequest) -> [(name: String, value: String)] {
    guard let url = request.url,
          let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else { return [] }
    return (comps.queryItems ?? []).map { ($0.name, $0.value ?? "") }
}

func queryDict(_ request: URLRequest) -> [String: String] {
    Dictionary(uniqueKeysWithValues: queryItems(request).map { ($0.name, $0.value) })
}

/// 沒解碼的原始 query 字串。
func rawQuery(_ request: URLRequest) -> String? {
    guard let url = request.url,
          let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else { return nil }
    return comps.percentEncodedQuery
}

/// 不帶任何轉換的挑選器（分類器恆為 neutral）。
func neutralPicker() -> LyricsCandidatePicker {
    LyricsCandidatePicker(scriptClassifier: { _ in .neutral })
}

/// 以標記詞判斷文字種類的假分類器：測試樣本內嵌 TRAD / SIMP / MIX 字樣。
let markerClassifier: @Sendable (String) -> LyricsScript = { text in
    if text.contains("SIMP") { return .simplified }
    if text.contains("MIX") { return .mixed }
    if text.contains("TRAD") { return .traditional }
    return .neutral
}
