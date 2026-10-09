import CryptoKit
import Foundation

// MARK: - 檢查結果的資料型別

/// entitlement 值的最小表示（可比較、可跨執行緒）。
public enum EntitlementValue: Equatable, Sendable {
    case bool(Bool)
    case string(String)
    case array([EntitlementValue])
    case other(String)
}

/// 從 .app 讀出的「事實」。純資料，驗證邏輯只看這些。
public struct AppBundleFacts: Equatable, Sendable {
    public var bundleIdentifier: String?
    public var shortVersion: String?
    public var architectures: [String]
    /// nil＝簽章（strict、含巢狀程式碼、所有架構）驗證通過；否則為系統回報的原因。
    public var signatureError: String?
    public var hardenedRuntime: Bool
    public var entitlements: [String: EntitlementValue]

    public init(bundleIdentifier: String?, shortVersion: String?, architectures: [String], signatureError: String?,
                hardenedRuntime: Bool, entitlements: [String: EntitlementValue]) {
        self.bundleIdentifier = bundleIdentifier
        self.shortVersion = shortVersion
        self.architectures = architectures
        self.signatureError = signatureError
        self.hardenedRuntime = hardenedRuntime
        self.entitlements = entitlements
    }
}

/// 讀取 .app 事實的抽象（真實實作用 Security.framework；測試用假的）。
public protocol AppBundleInspecting: Sendable {
    func inspect(appAt url: URL) throws -> AppBundleFacts
}

public enum UpdateVerificationFailure: Error, Equatable, Sendable {
    case checksumMismatch(expected: String, actual: String)
    case unexpectedBundleIdentifier(String?)
    case versionMismatch(expected: String, actual: String?)
    case notNewer(candidate: String, current: String)
    case missingArm64
    case invalidSignature(String)
    case hardenedRuntimeMissing
    case entitlementsExpanded([String])
    case sandboxMissing
    case unreadable(String)

    /// 英文診斷文字（App 層會對應成在地化句子，這串只當細節附上）。
    public var reason: String {
        switch self {
        case .checksumMismatch(let expected, let actual): "SHA-256 mismatch (expected \(expected), got \(actual))"
        case .unexpectedBundleIdentifier(let id): "unexpected bundle identifier \(id ?? "(none)")"
        case .versionMismatch(let expected, let actual): "app version \(actual ?? "(none)") does not match release \(expected)"
        case .notNewer(let candidate, let current): "version \(candidate) is not newer than \(current)"
        case .missingArm64: "the app has no arm64 code"
        case .invalidSignature(let detail): "invalid code signature: \(detail)"
        case .hardenedRuntimeMissing: "Hardened Runtime is not enabled"
        case .entitlementsExpanded(let keys): "entitlements expanded: \(keys.joined(separator: ", "))"
        case .sandboxMissing: "App Sandbox is not enabled"
        case .unreadable(let detail): "cannot read file: \(detail)"
        }
    }
}

// MARK: - SHA-256

public enum SHA256Hasher {
    /// 串流計算檔案的 SHA-256（小寫十六進位），不把整個檔案讀進記憶體。
    public static func hexDigest(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - 驗證

public struct UpdateVerifier: Sendable {
    public static let expectedBundleIdentifier = "io.github.davidkong3804.DavidNook"
    /// 新版唯一允許「多出來」的 entitlement。
    public static let allowedNewEntitlements: Set<String> = ["com.apple.security.files.user-selected.read-write"]
    private static let sandboxKey = "com.apple.security.app-sandbox"

    private let inspector: AppBundleInspecting

    public init(inspector: AppBundleInspecting) { self.inspector = inspector }

    /// 下載檔的 SHA-256 必須與發布者公佈的相同。
    public func verifyArchive(at file: URL, expectedSHA256: String) throws {
        let actual: String
        do { actual = try SHA256Hasher.hexDigest(of: file) } catch {
            throw UpdateVerificationFailure.unreadable((error as NSError).localizedDescription)
        }
        guard actual == expectedSHA256.lowercased() else {
            throw UpdateVerificationFailure.checksumMismatch(expected: expectedSHA256.lowercased(), actual: actual)
        }
    }

    /// 驗證解壓（或安裝）後的 App；任何一項失敗就拋錯。
    public func verifyApp(at app: URL, expectedVersion: SemanticVersion, currentVersion: SemanticVersion,
                          currentEntitlements: [String: EntitlementValue]) throws {
        let facts: AppBundleFacts
        do { facts = try inspector.inspect(appAt: app) } catch let error as UpdateVerificationFailure { throw error } catch {
            throw UpdateVerificationFailure.unreadable((error as NSError).localizedDescription)
        }

        guard facts.bundleIdentifier == Self.expectedBundleIdentifier else {
            throw UpdateVerificationFailure.unexpectedBundleIdentifier(facts.bundleIdentifier)
        }
        guard let text = facts.shortVersion, let bundleVersion = SemanticVersion(text), bundleVersion == expectedVersion else {
            throw UpdateVerificationFailure.versionMismatch(expected: expectedVersion.description, actual: facts.shortVersion)
        }
        guard bundleVersion.isStrictlyNewer(than: currentVersion) else {
            throw UpdateVerificationFailure.notNewer(candidate: bundleVersion.description, current: currentVersion.description)
        }
        guard facts.architectures.contains("arm64") else { throw UpdateVerificationFailure.missingArm64 }
        if let error = facts.signatureError { throw UpdateVerificationFailure.invalidSignature(error) }
        guard facts.hardenedRuntime else { throw UpdateVerificationFailure.hardenedRuntimeMissing }
        guard facts.entitlements[Self.sandboxKey] == .bool(true) else { throw UpdateVerificationFailure.sandboxMissing }

        var expanded: [String] = []
        for (key, value) in facts.entitlements {
            if let existing = currentEntitlements[key] {
                if !Self.isNoBroader(value, than: existing) { expanded.append(key) }
            } else if Self.allowedNewEntitlements.contains(key) {
                if value != .bool(true) { expanded.append(key) }
            } else if value != .bool(false) {
                // 新增且為 false 的鍵不授權任何東西；其餘一律視為擴權。
                expanded.append(key)
            }
        }
        if !expanded.isEmpty { throw UpdateVerificationFailure.entitlementsExpanded(expanded.sorted()) }
    }

    /// `new` 的權限是否不大於 `old`：布林不可由 false 變 true、陣列只能是子集、其他必須相同。
    static func isNoBroader(_ new: EntitlementValue, than old: EntitlementValue) -> Bool {
        switch (new, old) {
        case (.bool(let n), .bool(let o)): return !n || o
        case (.array(let n), .array(let o)): return n.allSatisfy { o.contains($0) }
        default: return new == old
        }
    }
}
