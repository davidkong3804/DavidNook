//
//  UpdateController.swift
//  DavidNook
//
//  「檢查更新」與「更新並重新啟動」的流程控制。純邏輯（版本比較、GitHub 解析、驗證、安裝）都在
//  DavidNookCore 的 Update/；這裡只負責：目前版本、狀態、NSOpenPanel 授權資料夾、重新啟動、在地化文字。
//
//  隱私：只有使用者按下按鈕才連線（沒有背景輪詢、沒有啟動時檢查）；只送 GET 與 `User-Agent: DavidNook/<版本>`，
//  不帶 token、cookie、識別資料。只連 UpdateHostPolicy 白名單內的 https 主機（含每一次重新導向）。
//

import AppKit
import DavidNookCore
import DavidNookUI
import SwiftUI

@MainActor
final class UpdateController: ObservableObject {
    static let shared = UpdateController()

    @Published private(set) var state: UpdatePanelState = .idle

    private var candidate: UpdateCandidate?
    private var installedAppURL: URL?
    private var task: Task<Void, Never>?
    /// 使用者用 NSOpenPanel 授權的資料夾（沙盒 powerbox 授權，只在更新期間持有）。
    private var scopedFolder: URL?
    private let session = AllowlistedSession()

    private init() {}

    // MARK: - 目前版本

    private var currentVersionText: String { Bundle.main.releaseVersionNumber ?? "" }
    private var targetAppURL: URL { Bundle.main.bundleURL }

    // MARK: - 檢查

    func check() {
        guard !state.isBusy else { return }
        guard let current = SemanticVersion(currentVersionText) else {
            state = .failed(message: String(localized: "Couldn't read the current version of DavidNook.", comment: "Update error."),
                            detail: nil, canOpenReleasePage: false)
            return
        }
        candidate = nil
        state = .checking
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            let client = GitHubReleaseClient(transport: AllowlistedTransport(session: self.session), appVersion: self.currentVersionText)
            do {
                let result = try await client.check(current: current)
                guard !Task.isCancelled else { return }
                switch result {
                case .upToDate:
                    self.state = .upToDate
                case .available(let found):
                    self.candidate = found
                    self.state = .available(version: found.version.description, notes: found.notes, isPrerelease: found.isPrerelease)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.state = Self.failureState(for: error, canOpenReleasePage: false)
            }
        }
    }

    // MARK: - 更新

    func startUpdate() {
        guard case .available = state, let candidate else { return }
        switch UpdateInstaller.preflight(targetAppURL: targetAppURL) {
        case .ok:
            install(candidate)
        case .translocated:
            fail(UpdateInstallError.translocated)
        case .readOnlyVolume:
            fail(UpdateInstallError.readOnlyVolume)
        case .needsFolderAccess:
            state = .needsFolderAccess(folder: targetAppURL.deletingLastPathComponent().lastPathComponent)
            chooseFolder()
        }
    }

    /// 彈出系統的資料夾選擇面板，請使用者授權 DavidNook 所在的資料夾。
    func chooseFolder() {
        guard case .needsFolderAccess(let folderName) = state, let candidate else { return }
        let parent = targetAppURL.deletingLastPathComponent()
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = parent
        panel.title = String(localized: "Authorize the update", comment: "Title of the folder picker shown when updating.")
        panel.message = String(localized: "Please choose the folder DavidNook is in to authorize the update.",
                               comment: "Message in the folder picker shown when updating.")
        panel.prompt = String(localized: "Authorize", comment: "Confirm button of the folder picker shown when updating.")
        guard panel.runModal() == .OK, let url = panel.url else { return } // 取消：留在提示畫面，可再按「選擇資料夾…」
        guard GrantedFolder.covers(url, appURL: targetAppURL) else {
            state = .failed(
                message: String(localized: "That isn't the folder DavidNook is in. Choose “\(folderName)” (or a folder that contains it).",
                                comment: "Update error: the user picked the wrong folder."),
                detail: nil, canOpenReleasePage: true)
            return
        }
        if url.startAccessingSecurityScopedResource() { scopedFolder = url }
        guard UpdateInstaller.preflight(targetAppURL: targetAppURL) == .ok else {
            releaseScopedFolder()
            fail(UpdateInstallError.targetNotWritable)
            return
        }
        install(candidate)
    }

    func cancel() {
        task?.cancel()
        releaseScopedFolder()
        if let candidate {
            state = .available(version: candidate.version.description, notes: candidate.notes, isPrerelease: candidate.isPrerelease)
        } else {
            state = .idle
        }
    }

    func openReleasePage() {
        let url = candidate?.releasePageURL ?? URL(string: "https://github.com/davidkong3804/DavidNook/releases")!
        if UpdateHostPolicy.isAllowed(url) { NSWorkspace.shared.open(url) }
    }

    // MARK: - 安裝

    private func install(_ candidate: UpdateCandidate) {
        guard let current = SemanticVersion(currentVersionText) else { return }
        let version = candidate.version.description
        let inspector = SecurityAppBundleInspector()
        let entitlements: [String: EntitlementValue]
        do {
            entitlements = try inspector.inspect(appAt: targetAppURL).entitlements
        } catch {
            fail(UpdateInstallError.verification(.unreadable("current app")))
            return
        }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("DavidNookUpdate", isDirectory: true)
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let installer = UpdateInstaller(
            downloader: AllowlistedDownloader(session: session, appVersion: currentVersionText),
            extractor: DittoArchiveExtractor(),
            verifier: UpdateVerifier(inspector: inspector)
        )
        let request = UpdateInstallRequest(candidate: candidate, currentVersion: current, currentEntitlements: entitlements,
                                           targetAppURL: targetAppURL, workDirectory: work)
        state = .downloading(version: version, progress: 0)
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await installer.run(request) { phase in
                    Task { @MainActor in self.apply(phase, version: version) }
                }
                self.installedAppURL = url
                self.releaseScopedFolder()
                self.state = .finished(version: version)
            } catch {
                self.releaseScopedFolder()
                if let error = error as? UpdateInstallError, error == .cancelled { return }
                self.fail(error)
            }
        }
    }

    private func apply(_ phase: UpdatePhase, version: String) {
        switch phase {
        case .downloading(let progress):
            if case .downloading = state { state = .downloading(version: version, progress: progress) }
        case .verifying:
            state = .verifying(version: version)
        case .installing:
            state = .installing(version: version)
        case .finished:
            break
        }
    }

    private func releaseScopedFolder() {
        scopedFolder?.stopAccessingSecurityScopedResource()
        scopedFolder = nil
    }

    // MARK: - 重新啟動

    /// 開新版；成功啟動後才結束自己。若 macOS 擋下（新版第一次開啟的 Gatekeeper），舊版繼續執行並說明該怎麼做。
    func relaunch() {
        guard let url = installedAppURL else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            Task { @MainActor in
                if error == nil {
                    NSApplication.shared.terminate(nil)
                } else {
                    self.state = .relaunchBlocked
                }
            }
        }
    }

    // MARK: - 錯誤文字

    private func fail(_ error: Error) {
        state = Self.failureState(for: error, canOpenReleasePage: candidate != nil)
    }

    static func failureState(for error: Error, canOpenReleasePage: Bool) -> UpdatePanelState {
        let (message, detail) = describe(error)
        return .failed(message: message, detail: detail, canOpenReleasePage: canOpenReleasePage)
    }

    private static func describe(_ error: Error) -> (String, String?) {
        switch error {
        case let error as UpdateCheckError:
            switch error {
            case .network(let text):
                return (String(localized: "Couldn't reach GitHub. Check your internet connection and try again.", comment: "Update error."), text)
            case .httpStatus(let code):
                return (String(localized: "GitHub returned an error (HTTP \(code)).", comment: "Update error."), nil)
            case .rateLimited:
                return (String(localized: "GitHub is limiting requests right now. Try again in a few minutes.", comment: "Update error."), nil)
            case .malformedResponse:
                return (String(localized: "GitHub's answer could not be understood.", comment: "Update error."), nil)
            case .missingArchive(let tag):
                return (String(localized: "The new version has no Apple Silicon download, so the update was not started.", comment: "Update error."), tag)
            case .missingChecksum(let tag):
                return (String(localized: "The new version has no SHA-256 checksum, so the update was refused.", comment: "Update error."), tag)
            case .invalidChecksumFile(let tag):
                return (String(localized: "The checksum file of the new version is malformed, so the update was refused.", comment: "Update error."), tag)
            case .checksumConflict(let tag):
                return (String(localized: "The published checksums disagree with each other, so the update was refused.", comment: "Update error."), tag)
            case .disallowedURL(let url):
                return (String(localized: "The release points to a download host that is not allowed, so the update was refused.", comment: "Update error."), url)
            }
        case let error as UpdateInstallError:
            return describe(error)
        default:
            return (String(localized: "The update failed.", comment: "Update error."), (error as NSError).localizedDescription)
        }
    }

    private static func describe(_ error: UpdateInstallError) -> (String, String?) {
        switch error {
        case .translocated:
            return (String(localized: "Please move DavidNook to the Applications folder or your own folder before updating.",
                           comment: "Update error: the app runs from a translocated (temporary read-only) location."), nil)
        case .readOnlyVolume:
            return (String(localized: "DavidNook is on a read-only disk. Please move it to the Applications folder or your own folder before updating.",
                           comment: "Update error."), nil)
        case .targetNotWritable:
            return (String(localized: "DavidNook can't write to its own folder. Choose that folder when asked, or move DavidNook to the Applications folder.",
                           comment: "Update error."), nil)
        case .download(let text):
            return (String(localized: "The download failed.", comment: "Update error."), text)
        case .extraction(let text):
            return (String(localized: "The download couldn't be unpacked.", comment: "Update error."), text)
        case .unexpectedArchiveContents:
            return (String(localized: "The download doesn't contain exactly one DavidNook app, so it was not installed.", comment: "Update error."), nil)
        case .verification(let failure):
            return (describe(failure), failure.reason)
        case .replaceFailed(let text, let restored):
            return (restored
                ? String(localized: "Replacing the app failed. The previous version was kept.", comment: "Update error.")
                : String(localized: "Replacing the app failed and the previous version could not be restored. Your previous copy is DavidNook.app.previous in the same folder.", comment: "Update error."),
                    text)
        case .postInstallVerificationFailed(let failure, let restored):
            return (restored
                ? String(localized: "The installed copy failed verification, so the previous version was restored.", comment: "Update error.")
                : String(localized: "The installed copy failed verification and the previous version could not be restored. Your previous copy is DavidNook.app.previous in the same folder.", comment: "Update error."),
                    failure.reason)
        case .cancelled:
            return (String(localized: "The update was cancelled.", comment: "Update error."), nil)
        }
    }

    private static func describe(_ failure: UpdateVerificationFailure) -> String {
        switch failure {
        case .checksumMismatch:
            String(localized: "The downloaded file doesn't match the SHA-256 published by the author, so it was not installed.", comment: "Update error.")
        case .unexpectedBundleIdentifier:
            String(localized: "The downloaded app is not DavidNook (wrong identifier), so it was not installed.", comment: "Update error.")
        case .versionMismatch:
            String(localized: "The downloaded app's version doesn't match the release, so it was not installed.", comment: "Update error.")
        case .notNewer:
            String(localized: "The downloaded version is not newer than the one you have, so it was not installed.", comment: "Update error.")
        case .missingArm64:
            String(localized: "The downloaded app doesn't run on Apple Silicon, so it was not installed.", comment: "Update error.")
        case .invalidSignature:
            String(localized: "The downloaded app's code signature is invalid, so it was not installed.", comment: "Update error.")
        case .hardenedRuntimeMissing:
            String(localized: "The downloaded app has Hardened Runtime turned off, so it was not installed.", comment: "Update error.")
        case .entitlementsExpanded:
            String(localized: "The downloaded app asks for more permissions than the current one, so it was not installed.", comment: "Update error.")
        case .sandboxMissing:
            String(localized: "The downloaded app is not sandboxed, so it was not installed.", comment: "Update error.")
        case .unreadable:
            String(localized: "The downloaded app couldn't be inspected, so it was not installed.", comment: "Update error.")
        }
    }

    // MARK: - 給畫面用的文字與動作

    var strings: UpdatePanelStrings {
        var s = UpdatePanelStrings()
        s.check = String(localized: "Check for Updates", comment: "Updates: button.")
        s.checkAgain = String(localized: "Check Again", comment: "Updates: button.")
        s.checking = String(localized: "Checking…", comment: "Updates: status while contacting GitHub.")
        s.upToDate = String(localized: "DavidNook is up to date", comment: "Updates: status.")
        s.available = { String(localized: "New version available: \($0)", comment: "Updates: status; the argument is a version such as 0.2.0.") }
        s.prereleaseBadge = String(localized: "Pre-release", comment: "Updates: label for a beta release.")
        s.updateAndRestart = String(localized: "Update and Restart", comment: "Updates: button.")
        s.viewInBrowser = String(localized: "View This Version in Browser", comment: "Updates: button; opens the GitHub release page.")
        s.releaseNotes = String(localized: "Release notes (summary)", comment: "Updates: heading above the plain-text release notes.")
        s.needsFolderTitle = String(localized: "Permission needed to update", comment: "Updates: status.")
        s.needsFolderBody = {
            String(localized: "DavidNook runs in the macOS sandbox and can't change its own folder without your permission. Choose the “\($0)” folder to authorize this update. You are asked only while updating; DavidNook does not remember or reuse this permission.",
                   comment: "Updates: explanation before the folder picker; the argument is a folder name such as Applications.")
        }
        s.chooseFolder = String(localized: "Choose Folder…", comment: "Updates: button.")
        s.cancel = String(localized: "Cancel", comment: "Updates: button.")
        s.downloading = { String(localized: "Downloading \($0)…", comment: "Updates: status; the argument is a version.") }
        s.verifying = { String(localized: "Verifying \($0) (checksum, signature, permissions)…", comment: "Updates: status; the argument is a version.") }
        s.installing = { String(localized: "Installing \($0)…", comment: "Updates: status; the argument is a version.") }
        s.finishedTitle = { String(localized: "Installed \($0)", comment: "Updates: status; the argument is a version.") }
        s.finishedBody = String(localized: "The old version is kept as DavidNook.app.previous. DavidNook is signed by its author and not notarized by Apple, so macOS treats the new version as a fresh download: the first launch may be blocked once. If so, open System Settings → Privacy & Security and click “Open Anyway”. After an update the code signature changes, so Screen Recording and Automation permissions may need to be allowed again.",
                                comment: "Updates: explanation after a successful update (Gatekeeper and re-authorization).")
        s.relaunch = String(localized: "Restart and Open New Version", comment: "Updates: button.")
        s.relaunchBlockedTitle = String(localized: "The new version is installed but not open yet", comment: "Updates: status after macOS blocked the first launch.")
        s.relaunchBlocked = String(localized: "macOS did not open the new version yet. This is normal after an update: open System Settings → Privacy & Security, click “Open Anyway”, then open DavidNook again. This version keeps running until then.",
                                   comment: "Shown when macOS (Gatekeeper) blocks the first launch of the updated app.")
        s.retry = String(localized: "Try Again", comment: "Updates: button.")
        return s
    }

    var callbacks: UpdatePanelCallbacks {
        UpdatePanelCallbacks(
            onCheck: { [weak self] in self?.check() },
            onUpdate: { [weak self] in self?.startUpdate() },
            onChooseFolder: { [weak self] in self?.chooseFolder() },
            onCancel: { [weak self] in self?.cancel() },
            onOpenReleasePage: { [weak self] in self?.openReleasePage() },
            onRelaunch: { [weak self] in self?.relaunch() }
        )
    }
}
