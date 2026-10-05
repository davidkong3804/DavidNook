import Foundation

/// 精簡的 HTTP 回應（供注入的傳輸層回傳，測試可直接建構，不需要 `HTTPURLResponse`）。
public struct HTTPResponse: Sendable {
    public var statusCode: Int
    public var headers: [String: String]
    public var body: Data

    public init(statusCode: Int, headers: [String: String], body: Data) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    /// 取得標頭值；標頭名稱不分大小寫（HTTP 規範）。
    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

/// HTTP 傳輸層抽象：`LrclibClient` 只依賴它，測試時以 stub 取代，絕不連外網。
public protocol HTTPTransport: Sendable {
    /// 送出請求並回傳回應；傳輸失敗（無網路、逾時…）以拋錯表示。
    /// 注意：HTTP 4xx／5xx 不是錯誤，照常回傳 `HTTPResponse`。
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

/// 以 `URLSession` 實作的預設傳輸層（整個模組唯一使用 `URLSession.shared` 的地方）。
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    /// - Parameter session: 預設使用共用 session；測試可傳入掛了 `URLProtocol` 的 session。
    public init(session: URLSession = URLSession.shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String, let value = value as? String { headers[key] = value }
        }
        return HTTPResponse(statusCode: http.statusCode, headers: headers, body: data)
    }
}
