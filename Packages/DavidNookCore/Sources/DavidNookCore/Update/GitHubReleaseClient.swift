import Foundation

/// 一個可安裝的新版本（已通過「有 arm64 zip、有 SHA-256」的檢查）。
public struct UpdateCandidate: Equatable, Sendable {
    public let version: SemanticVersion
    public let tag: String
    public let title: String
    public let isPrerelease: Bool
    /// 在瀏覽器查看這個版本用的 GitHub release 頁面（必在白名單內）。
    public let releasePageURL: URL
    public let archiveURL: URL
    public let archiveName: String
    public let archiveSize: Int?
    /// 小寫 64 位十六進位。
    public let sha256: String
    /// 純文字發行說明摘要（已去連結／HTML、已截斷）。
    public let notes: String

    public init(version: SemanticVersion, tag: String, title: String, isPrerelease: Bool, releasePageURL: URL,
                archiveURL: URL, archiveName: String, archiveSize: Int?, sha256: String, notes: String) {
        self.version = version
        self.tag = tag
        self.title = title
        self.isPrerelease = isPrerelease
        self.releasePageURL = releasePageURL
        self.archiveURL = archiveURL
        self.archiveName = archiveName
        self.archiveSize = archiveSize
        self.sha256 = sha256
        self.notes = notes
    }
}

public enum UpdateCheckResult: Equatable, Sendable {
    /// 已是最新；`latest` 是 GitHub 上看得到的最高版本（沒有任何 release 時為 nil）。
    case upToDate(latest: SemanticVersion?)
    case available(UpdateCandidate)
}

public enum UpdateCheckError: Error, Equatable, Sendable {
    case network(String)
    case httpStatus(Int)
    case rateLimited
    case malformedResponse
    case missingArchive(tag: String)
    /// 找不到任何 SHA-256：拒絕更新（不得跳過驗證）。
    case missingChecksum(tag: String)
    case invalidChecksumFile(tag: String)
    /// 發布者給的多個雜湊彼此不一致。
    case checksumConflict(tag: String)
    case disallowedURL(String)
}

/// 讀 GitHub releases 清單、挑出最高版本並取得安裝所需資訊。
/// 隱私：只送 GET，標頭只有 `User-Agent: DavidNook/<版本>` 與 `Accept`；不帶 token、cookie 或任何識別資料。
public struct GitHubReleaseClient: Sendable {
    public static let maxNotesLength = 1200
    public static let maxResponseBytes = 2_000_000
    public static let maxChecksumFileBytes = 4096

    private let transport: HTTPTransport
    private let appVersion: String
    private let repository: String
    private let includePrereleases: Bool

    public init(transport: HTTPTransport, appVersion: String, repository: String = "davidkong3804/DavidNook",
                includePrereleases: Bool = true) {
        self.transport = transport
        self.appVersion = appVersion
        self.repository = repository
        self.includePrereleases = includePrereleases
    }

    // MARK: - 檢查

    public func check(current: SemanticVersion) async throws -> UpdateCheckResult {
        let listURL = URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=10")!
        let response = try await send(makeRequest(listURL, accept: "application/vnd.github+json"))
        try Self.validate(status: response)
        guard response.body.count <= Self.maxResponseBytes,
              let json = try? JSONSerialization.jsonObject(with: response.body),
              let array = json as? [[String: Any]]
        else { throw UpdateCheckError.malformedResponse }

        // 挑最高版本（不依清單順序）；略過草稿、tag 不是 SemVer 的項目。
        var best: (version: SemanticVersion, release: [String: Any])?
        for release in array {
            if (release["draft"] as? Bool) == true { continue }
            guard let tag = release["tag_name"] as? String, let version = SemanticVersion(tag) else { continue }
            if version.isPrerelease && !includePrereleases { continue }
            if best == nil || version > best!.version { best = (version, release) }
        }
        guard let best else { return .upToDate(latest: nil) }
        guard best.version.isStrictlyNewer(than: current) else { return .upToDate(latest: best.version) }
        return .available(try await candidate(from: best.release, version: best.version))
    }

    // MARK: - 單一 release → 候選

    private func candidate(from release: [String: Any], version: SemanticVersion) async throws -> UpdateCandidate {
        let tag = release["tag_name"] as? String ?? ""
        let bareTag = tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
        let archiveName = "DavidNook-\(bareTag)-arm64.zip"
        let assets = (release["assets"] as? [[String: Any]]) ?? []

        guard let zip = assets.first(where: {
            ($0["name"] as? String) == archiveName && ($0["state"] as? String ?? "uploaded") == "uploaded"
        }), let zipURLText = zip["browser_download_url"] as? String
        else { throw UpdateCheckError.missingArchive(tag: tag) }
        guard let zipURL = URL(string: zipURLText), UpdateHostPolicy.isAllowed(zipURL) else {
            throw UpdateCheckError.disallowedURL(zipURLText)
        }

        // 雜湊來源：同 release 的 <zip>.sha256 優先，其次內文；兩者都有但不同＝拒絕；都沒有＝拒絕。
        let body = release["body"] as? String ?? ""
        let bodyHash = try Self.hashFromBody(body, tag: tag)
        var assetHash: String?
        if let shaAsset = assets.first(where: { ($0["name"] as? String) == archiveName + ".sha256" }) {
            guard let urlText = shaAsset["browser_download_url"] as? String, let url = URL(string: urlText),
                  UpdateHostPolicy.isAllowed(url)
            else { throw UpdateCheckError.disallowedURL(shaAsset["browser_download_url"] as? String ?? "") }
            let response = try await send(makeRequest(url, accept: "text/plain, application/octet-stream"))
            try Self.validate(status: response)
            guard response.body.count <= Self.maxChecksumFileBytes,
                  let text = String(data: response.body, encoding: .utf8),
                  let parsed = Self.parseChecksumFile(text, archiveName: archiveName)
            else { throw UpdateCheckError.invalidChecksumFile(tag: tag) }
            assetHash = parsed
        }
        let published: String
        switch (assetHash, bodyHash) {
        case (nil, nil): throw UpdateCheckError.missingChecksum(tag: tag)
        case (let a?, nil): published = a
        case (nil, let b?): published = b
        case (let a?, let b?):
            guard a == b else { throw UpdateCheckError.checksumConflict(tag: tag) }
            published = a
        }
        // GitHub 自己為 asset 算的 digest（若有）必須一致，否則上傳內容與發布者宣告的不同。
        if let digest = zip["digest"] as? String, digest.lowercased().hasPrefix("sha256:") {
            guard digest.dropFirst(7).lowercased() == published else { throw UpdateCheckError.checksumConflict(tag: tag) }
        }

        var page = URL(string: "https://github.com/\(repository)/releases/tag/\(tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tag)")!
        if let text = release["html_url"] as? String, let url = URL(string: text), UpdateHostPolicy.isAllowed(url) { page = url }

        return UpdateCandidate(
            version: version, tag: tag, title: (release["name"] as? String) ?? tag,
            isPrerelease: (release["prerelease"] as? Bool) ?? version.isPrerelease,
            releasePageURL: page, archiveURL: zipURL, archiveName: archiveName,
            archiveSize: zip["size"] as? Int, sha256: published,
            notes: ReleaseNotesFormatter.plainSummary(body, maxLength: Self.maxNotesLength)
        )
    }

    // MARK: - 雜湊解析

    private static let hexPattern = "[0-9A-Fa-f]{64}"

    /// 內文中的 ``SHA-256：`<hex>` ``（全形或半形冒號）。找不到回 nil；出現多個不同值丟 checksumConflict。
    static func hashFromBody(_ body: String, tag: String) throws -> String? {
        let pattern = "(?i)sha-?256\\s*[：:]\\s*`?(\(hexPattern))`?(?![0-9A-Fa-f])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = body as NSString
        var found = Set<String>()
        for match in regex.matches(in: body, range: NSRange(location: 0, length: ns.length)) where match.numberOfRanges > 1 {
            found.insert(ns.substring(with: match.range(at: 1)).lowercased())
        }
        if found.count > 1 { throw UpdateCheckError.checksumConflict(tag: tag) }
        return found.first
    }

    /// `<hex>  <檔名>`（也接受 `*` 二進位標記，或只有雜湊）；檔名若有寫必須等於 zip 名稱。
    static func parseChecksumFile(_ text: String, archiveName: String) -> String? {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard lines.count == 1 else { return nil }
        let line = lines[0]
        guard line.count >= 64 else { return nil }
        let hash = String(line.prefix(64))
        guard hash.range(of: "^\(hexPattern)$", options: .regularExpression) != nil else { return nil }
        var rest = line.dropFirst(64)
        if rest.isEmpty { return hash.lowercased() }
        guard rest.first == " " || rest.first == "\t" else { return nil }
        rest = Substring(rest.trimmingCharacters(in: .whitespaces))
        if rest.hasPrefix("*") { rest = rest.dropFirst() }
        return rest == archiveName ? hash.lowercased() : nil
    }

    // MARK: - 傳輸

    private func makeRequest(_ url: URL, accept: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.timeoutInterval = 20
        request.setValue("DavidNook/\(appVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        return request
    }

    private func send(_ request: URLRequest) async throws -> HTTPResponse {
        do {
            return try await transport.send(request)
        } catch let error as UpdateCheckError {
            throw error
        } catch {
            throw UpdateCheckError.network((error as NSError).localizedDescription)
        }
    }

    private static func validate(status response: HTTPResponse) throws {
        if response.statusCode == 429 || (response.statusCode == 403 && response.header("X-RateLimit-Remaining") == "0") {
            throw UpdateCheckError.rateLimited
        }
        guard (200..<300).contains(response.statusCode) else { throw UpdateCheckError.httpStatus(response.statusCode) }
    }
}
