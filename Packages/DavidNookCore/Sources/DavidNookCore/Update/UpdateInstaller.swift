import Foundation

// MARK: - 抽象

public protocol UpdateDownloading: Sendable {
    /// 下載到 `destination`（呼叫端保證目錄存在）；`progress` 為 0…1。
    func download(from url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws
}

public protocol ArchiveExtracting: Sendable {
    func extract(archive: URL, to directory: URL) throws
}

// MARK: - 狀態與錯誤

public enum UpdatePhase: Equatable, Sendable {
    case downloading(progress: Double)
    case verifying
    case installing
    case finished(URL)

    public enum Kind: Equatable, Sendable { case downloading, verifying, installing, finished }

    public var kind: Kind {
        switch self {
        case .downloading: .downloading
        case .verifying: .verifying
        case .installing: .installing
        case .finished: .finished
        }
    }
}

public enum UpdatePreflight: Equatable, Sendable {
    case ok
    /// 從 DMG／下載資料夾直接開啟時，系統會把 App 放進 `/AppTranslocation/` 的唯讀副本；不能在那裡更新。
    case translocated
    case readOnlyVolume
    /// 沙盒下尚未取得所在資料夾的寫入授權（或該資料夾本來就不可寫）。
    case needsFolderAccess
}

public enum UpdateInstallError: Error, Equatable, Sendable {
    case translocated
    case readOnlyVolume
    case targetNotWritable
    case download(String)
    case extraction(String)
    case unexpectedArchiveContents
    case verification(UpdateVerificationFailure)
    case replaceFailed(String, restored: Bool)
    case postInstallVerificationFailed(UpdateVerificationFailure, restored: Bool)
    case cancelled

    /// 英文診斷文字（App 層對應成在地化句子，這串只當細節）。
    public var reason: String {
        switch self {
        case .translocated: "DavidNook is running from a temporary read-only copy. Move DavidNook to the Applications folder or your own folder first."
        case .readOnlyVolume: "DavidNook is on a read-only volume. Move it to the Applications folder or your own folder first."
        case .targetNotWritable: "Cannot write to the folder DavidNook is in."
        case .download(let detail): "download failed: \(detail)"
        case .extraction(let detail): "could not unpack the download: \(detail)"
        case .unexpectedArchiveContents: "the download does not contain exactly one DavidNook.app"
        case .verification(let failure): failure.reason
        case .replaceFailed(let detail, let restored): "could not replace the app (\(detail)); previous version \(restored ? "kept" : "NOT restored")"
        case .postInstallVerificationFailed(let failure, let restored):
            "the installed copy failed verification (\(failure.reason)); previous version \(restored ? "restored" : "NOT restored")"
        case .cancelled: "cancelled"
        }
    }
}

public struct UpdateInstallRequest: Sendable {
    public var candidate: UpdateCandidate
    public var currentVersion: SemanticVersion
    public var currentEntitlements: [String: EntitlementValue]
    /// 要被取代的 DavidNook.app。
    public var targetAppURL: URL
    /// 下載與解壓用的暫存目錄（App 容器內）；由呼叫端建立。
    public var workDirectory: URL

    public init(candidate: UpdateCandidate, currentVersion: SemanticVersion, currentEntitlements: [String: EntitlementValue],
                targetAppURL: URL, workDirectory: URL) {
        self.candidate = candidate
        self.currentVersion = currentVersion
        self.currentEntitlements = currentEntitlements
        self.targetAppURL = targetAppURL
        self.workDirectory = workDirectory
    }
}

/// 使用者用 NSOpenPanel 選的資料夾是否涵蓋這個 App 所在位置（等於上層資料夾，或更上層的祖先）。
public enum GrantedFolder {
    public static func covers(_ folder: URL, appURL: URL) -> Bool {
        let folderPath = folder.resolvingSymlinksInPath().standardizedFileURL.path
        let parentPath = appURL.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path
        if folderPath == parentPath { return true }
        let prefix = folderPath.hasSuffix("/") ? folderPath : folderPath + "/"
        return parentPath.hasPrefix(prefix)
    }
}

// MARK: - 安裝器

/// 下載 → 驗證 → 備份舊版 → 原子替換 →（失敗自動還原）。
/// 順序保證：驗證全部通過之前，不會動到已安裝的 App。
public final class UpdateInstaller: Sendable {
    public typealias ReplaceItem = @Sendable (_ target: URL, _ staged: URL, _ backupName: String) throws -> Void

    private let downloader: UpdateDownloading
    private let extractor: ArchiveExtracting
    private let verifier: UpdateVerifier
    private let volumeIsReadOnly: @Sendable (URL) -> Bool
    private let replaceItem: ReplaceItem

    public init(downloader: UpdateDownloading, extractor: ArchiveExtracting, verifier: UpdateVerifier,
                volumeIsReadOnly: (@Sendable (URL) -> Bool)? = nil, replaceItem: ReplaceItem? = nil) {
        self.downloader = downloader
        self.extractor = extractor
        self.verifier = verifier
        self.volumeIsReadOnly = volumeIsReadOnly ?? Self.defaultVolumeIsReadOnly
        self.replaceItem = replaceItem ?? Self.defaultReplaceItem
    }

    // MARK: 位置檢查

    public static let defaultVolumeIsReadOnly: @Sendable (URL) -> Bool = { url in
        (try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) ?? false
    }

    public static let defaultReplaceItem: ReplaceItem = { target, staged, backupName in
        _ = try FileManager.default.replaceItemAt(target, withItemAt: staged, backupItemName: backupName,
                                                  options: [.withoutDeletingBackupItem])
    }

    public static func preflight(targetAppURL: URL,
                                 volumeIsReadOnly: @Sendable (URL) -> Bool = UpdateInstaller.defaultVolumeIsReadOnly) -> UpdatePreflight {
        if targetAppURL.path.contains("/AppTranslocation/") { return .translocated }
        let parent = targetAppURL.deletingLastPathComponent()
        if volumeIsReadOnly(parent) { return .readOnlyVolume }
        if !FileManager.default.isWritableFile(atPath: parent.path) { return .needsFolderAccess }
        return .ok
    }

    // MARK: 流程

    /// 執行完整更新；成功回傳新版 App 位置（＝targetAppURL）。
    public func run(_ request: UpdateInstallRequest, onPhase: @escaping @Sendable (UpdatePhase) -> Void) async throws -> URL {
        let fm = FileManager.default
        let target = request.targetAppURL
        switch Self.preflight(targetAppURL: target, volumeIsReadOnly: volumeIsReadOnly) {
        case .ok: break
        case .translocated: throw UpdateInstallError.translocated
        case .readOnlyVolume: throw UpdateInstallError.readOnlyVolume
        case .needsFolderAccess: throw UpdateInstallError.targetNotWritable
        }

        let candidate = request.candidate
        let archive = request.workDirectory.appendingPathComponent(candidate.archiveName)
        let extracted = request.workDirectory.appendingPathComponent("extracted", isDirectory: true)
        try? fm.removeItem(at: archive)
        try? fm.removeItem(at: extracted)
        defer {
            try? fm.removeItem(at: archive)
            try? fm.removeItem(at: extracted)
        }

        // 1. 下載
        onPhase(.downloading(progress: 0))
        do {
            try await downloader.download(from: candidate.archiveURL, to: archive) { onPhase(.downloading(progress: $0)) }
        } catch is CancellationError {
            throw UpdateInstallError.cancelled
        } catch {
            throw UpdateInstallError.download((error as NSError).localizedDescription)
        }
        try checkCancelled()

        // 2. 驗證下載檔，再解壓，再驗證 App
        onPhase(.verifying)
        do { try verifier.verifyArchive(at: archive, expectedSHA256: candidate.sha256) }
        catch let failure as UpdateVerificationFailure { throw UpdateInstallError.verification(failure) }

        do { try extractor.extract(archive: archive, to: extracted) }
        catch { throw UpdateInstallError.extraction((error as NSError).localizedDescription) }

        let items = (try? fm.contentsOfDirectory(atPath: extracted.path)) ?? []
        guard items == ["DavidNook.app"] else { throw UpdateInstallError.unexpectedArchiveContents }
        let newApp = extracted.appendingPathComponent("DavidNook.app")
        do {
            try verifier.verifyApp(at: newApp, expectedVersion: candidate.version, currentVersion: request.currentVersion,
                                   currentEntitlements: request.currentEntitlements)
        } catch let failure as UpdateVerificationFailure { throw UpdateInstallError.verification(failure) }
        try checkCancelled()

        // 3. 安裝：先在目標資料夾內暫存一份（同一個磁碟區），再原子替換並保留 .previous 備份
        onPhase(.installing)
        let parent = target.deletingLastPathComponent()
        let backupName = target.lastPathComponent + ".previous"
        let backup = parent.appendingPathComponent(backupName)
        let staged = parent.appendingPathComponent(".\(target.lastPathComponent).update-\(UUID().uuidString.prefix(8))")
        do { try fm.copyItem(at: newApp, to: staged) } catch {
            try? fm.removeItem(at: staged)
            throw UpdateInstallError.replaceFailed((error as NSError).localizedDescription, restored: true)
        }
        // 舊的備份先移到暫時名稱；整個流程成功才刪，失敗就搬回去。
        let oldBackupHolder = parent.appendingPathComponent(".\(backupName).discard-\(UUID().uuidString.prefix(8))")
        var heldOldBackup = false
        if fm.fileExists(atPath: backup.path) {
            do { try fm.moveItem(at: backup, to: oldBackupHolder); heldOldBackup = true } catch {
                try? fm.removeItem(at: staged)
                throw UpdateInstallError.replaceFailed((error as NSError).localizedDescription, restored: true)
            }
        }
        func restoreOldBackup() { if heldOldBackup { try? fm.moveItem(at: oldBackupHolder, to: backup) } }

        do { try replaceItem(target, staged, backupName) } catch {
            try? fm.removeItem(at: staged)
            try? fm.removeItem(at: backup) // 若替換做到一半留下備份，目標仍是舊版
            restoreOldBackup()
            throw UpdateInstallError.replaceFailed((error as NSError).localizedDescription, restored: fm.fileExists(atPath: target.path))
        }

        // 4. 安裝後再驗一次；不過就把舊版換回來
        do {
            try verifier.verifyApp(at: target, expectedVersion: candidate.version, currentVersion: request.currentVersion,
                                   currentEntitlements: request.currentEntitlements)
        } catch let failure as UpdateVerificationFailure {
            let restored = rollback(target: target, backup: backup)
            restoreOldBackup()
            throw UpdateInstallError.postInstallVerificationFailed(failure, restored: restored)
        }
        if heldOldBackup { try? fm.removeItem(at: oldBackupHolder) }
        onPhase(.finished(target))
        return target
    }

    // MARK: 私有

    private func checkCancelled() throws {
        if Task.isCancelled { throw UpdateInstallError.cancelled }
    }

    /// 把 `.previous` 換回正式位置；成功回 true。
    private func rollback(target: URL, backup: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: backup.path) else { return false }
        do {
            _ = try fm.replaceItemAt(target, withItemAt: backup, backupItemName: nil, options: [])
            return true
        } catch {
            return false
        }
    }
}
