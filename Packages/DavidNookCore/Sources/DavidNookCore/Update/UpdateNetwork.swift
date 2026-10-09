import Foundation

/// 用 `/usr/bin/ditto -x -k` 解壓（沙盒內實測可執行；ditto 繼承沙盒，只能寫 App 容器）。
/// 解壓前先讀 zip 中央目錄，擋掉路徑穿越與 `DavidNook.app/` 以外的項目。
public struct DittoArchiveExtractor: ArchiveExtracting {
    public init() {}

    public func extract(archive: URL, to directory: URL) throws {
        try ZipEntryListing.validateLayout(try ZipEntryListing.entryNames(of: archive), appName: "DavidNook.app")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, directory.path]
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = Pipe()
        try process.run()
        let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let text = String(decoding: errorData.prefix(300), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(domain: "DavidNook.Update", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "ditto exited with status \(process.terminationStatus) \(text)"])
        }
    }
}

/// 只允許白名單主機的 URLSession 包裝：初始請求與每一次重新導向都要通過 `UpdateHostPolicy`。
/// 不使用共用 session、不存 cookie、不寫快取、不帶憑證。
public final class AllowlistedSession: NSObject, URLSessionTaskDelegate, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var progressHandlers: [Int: @Sendable (Double) -> Void] = [:]
    private var downloadContinuations: [Int: CheckedContinuation<URL, Error>] = [:]
    private var downloadDestinations: [Int: URL] = [:]
    private var movedFiles: [Int: Result<URL, Error>] = [:]
    private var blockedRedirects: Set<Int> = []
    private var _session: URLSession!

    public override init() {
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 600
        configuration.waitsForConnectivity = false
        _session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    deinit { _session.invalidateAndCancel() }

    // MARK: 記憶體內的小請求（releases 清單、.sha256）

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url, UpdateHostPolicy.isAllowed(url) else { throw URLError(.appTransportSecurityRequiresSecureConnection) }
        let (data, response) = try await _session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if let final = http.url, !UpdateHostPolicy.isAllowed(final) { throw URLError(.cancelled) }
        return (data, http)
    }

    // MARK: 下載

    public func download(_ request: URLRequest, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let url = request.url, UpdateHostPolicy.isAllowed(url) else { throw URLError(.appTransportSecurityRequiresSecureConnection) }
        let task = _session.downloadTask(with: request)
        let id = task.taskIdentifier
        lock.withLock {
            progressHandlers[id] = progress
            downloadDestinations[id] = destination
        }
        let temp: URL = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                lock.withLock { downloadContinuations[id] = continuation }
                task.resume()
            }
        } onCancel: { task.cancel() }
        _ = temp
    }

    // MARK: Delegate

    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, UpdateHostPolicy.allowsRedirect(to: url) else {
            lock.withLock { _ = blockedRedirects.insert(task.taskIdentifier) }
            completionHandler(nil) // 不跟隨；任務會以收到的 3xx 回應結束，下面視為失敗
            task.cancel()
            return
        }
        // 重新導向後仍只帶 User-Agent（URLSession 預設不會把 Authorization 帶去別的主機，我們本來也沒有）。
        completionHandler(request)
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                           totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let handler = lock.withLock { progressHandlers[downloadTask.taskIdentifier] }
        handler?(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let id = downloadTask.taskIdentifier
        let destination = lock.withLock { downloadDestinations[id] }
        var result: Result<URL, Error>
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            result = .failure(URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"]))
        } else if let final = downloadTask.response?.url, !UpdateHostPolicy.isAllowed(final) {
            result = .failure(URLError(.cancelled))
        } else if let destination {
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: location, to: destination)
                result = .success(destination)
            } catch { result = .failure(error) }
        } else {
            result = .failure(URLError(.unknown))
        }
        lock.withLock { movedFiles[id] = result }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let id = task.taskIdentifier
        let (continuation, moved, blocked) = lock.withLock { () -> (CheckedContinuation<URL, Error>?, Result<URL, Error>?, Bool) in
            let c = downloadContinuations.removeValue(forKey: id)
            let m = movedFiles.removeValue(forKey: id)
            let b = blockedRedirects.remove(id) != nil
            progressHandlers.removeValue(forKey: id)
            downloadDestinations.removeValue(forKey: id)
            return (c, m, b)
        }
        guard let continuation else { return }
        if blocked {
            continuation.resume(throwing: URLError(.cancelled, userInfo: [NSLocalizedDescriptionKey: "redirect to a host that is not allowed"]))
        } else if let error {
            continuation.resume(throwing: error)
        } else if let moved {
            continuation.resume(with: moved)
        } else {
            continuation.resume(throwing: URLError(.unknown))
        }
    }
}

/// `HTTPTransport`（給 `GitHubReleaseClient`）：走白名單 session。
public struct AllowlistedTransport: HTTPTransport {
    private let session: AllowlistedSession
    public init(session: AllowlistedSession = AllowlistedSession()) { self.session = session }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, http) = try await session.data(for: request)
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String, let value = value as? String { headers[key] = value }
        }
        return HTTPResponse(statusCode: http.statusCode, headers: headers, body: data)
    }
}

/// `UpdateDownloading`：GET、只帶 User-Agent，進度回報 0…1。
public struct AllowlistedDownloader: UpdateDownloading {
    private let session: AllowlistedSession
    private let userAgent: String

    public init(session: AllowlistedSession = AllowlistedSession(), appVersion: String) {
        self.session = session
        self.userAgent = "DavidNook/\(appVersion)"
    }

    public func download(from url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        try await session.download(request, to: destination, progress: progress)
    }
}
