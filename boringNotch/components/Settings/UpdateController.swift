//
//  UpdateController.swift
//  DavidNook
//
//  「檢查更新」與「更新並重新啟動」的流程控制。純邏輯（版本比較、GitHub 解析、驗證、安裝）都在
//  DavidNookCore 的 Update/；這裡只負責：目前版本、狀態、NSOpenPanel 授權資料夾、重新啟動、在地化文字。
//
//  隱私：連線只有兩種——使用者按下按鈕，或（預設開、可在設定關閉的）自動檢查：啟動後約 30 秒第一次，之後每天最多一次，
//  只「檢查有沒有新版」，絕不自動下載或安裝（規則在 Core 的 AutoUpdateSchedule）。只送 GET 與 `User-Agent: DavidNook/<版本>`，
//  不帶 token、cookie、識別資料。只連 UpdateHostPolicy 白名單內的 https 主機（含每一次重新導向）。
//

import AppKit
import Defaults
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

    // 自動檢查（見 startAutoChecking）。只存在記憶體；跨啟動保存的只有「上次成功檢查時間」。
    private var autoTask: Task<Void, Never>?
    private let schedule = AutoUpdateSchedule()
    private var lastAutoAttempt: Date?
    private var retriedThisLaunch = false

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
            do {
                let result = try await self.fetchLatest(current: current)
                guard !Task.isCancelled else { return }
                Defaults[.lastSuccessfulUpdateCheck] = Date()
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

    private func fetchLatest(current: SemanticVersion) async throws -> UpdateCheckResult {
        let client = GitHubReleaseClient(transport: AllowlistedTransport(session: session), appVersion: currentVersionText)
        return try await client.check(current: current)
    }

    // MARK: - 自動檢查

    /// 在背景定期「檢查」有沒有新版（由 App 啟動時呼叫一次）。只檢查，絕不下載或安裝；有新版時只是把狀態變成 `.available`，
    /// 設定頁「關於」與選單列就會顯示提示。沒有開啟、更新進行中、已有新版時都不連線。失敗（斷網、限流）靜默處理，不顯示紅字。
    func startAutoChecking() {
        guard autoTask == nil else { return }
        autoTask = Task { [weak self] in
            // 啟動後先等一下，不拖慢開機。
            try? await Task.sleep(for: .seconds(AutoUpdateSchedule.initialDelay))
            while !Task.isCancelled {
                guard let self else { return }
                let pause = await self.autoCheckStep()
                try? await Task.sleep(for: .seconds(pause))
            }
        }
    }

    /// 問排程「現在該不該查」，該查就查一次；回傳下一次再問之前要睡多久（秒）。睡眠最長 1 小時，系統時鐘被改動時也能很快重新判斷。
    private func autoCheckStep() async -> TimeInterval {
        let now = Date()
        let lastSuccess = Defaults[.lastSuccessfulUpdateCheck]
        let alreadyAvailable: Bool = { if case .available = state { true } else { false } }()
        switch schedule.decision(
            now: now, lastSuccessfulCheck: lastSuccess, lastAttempt: lastAutoAttempt, retriedThisLaunch: retriedThisLaunch,
            enabled: Defaults[.autoCheckUpdates], isBusy: state.isBusy, alreadyAvailable: alreadyAvailable
        ) {
        case .skip:
            return 10 * 60 // 只是重新問本機規則（例如使用者剛打開開關），不連線
        case .wait(let until):
            return min(3_600, max(60, until.timeIntervalSince(now)))
        case .checkNow:
            // 上一次自動嘗試失敗、尚未被成功取代：這次是重試，本次啟動只允許一次。
            if let previous = lastAutoAttempt, lastSuccess.map({ $0 < previous }) ?? true { retriedThisLaunch = true }
            lastAutoAttempt = now
            await runAutomaticCheck()
            return 60
        }
    }

    private func runAutomaticCheck() async {
        guard let current = SemanticVersion(currentVersionText) else { return }
        do {
            let result = try await fetchLatest(current: current)
            guard !Task.isCancelled else { return }
            Defaults[.lastSuccessfulUpdateCheck] = Date()
            // 使用者這時已經手動檢查或開始更新：不去動畫面，讓那個流程自己收尾。
            guard !state.isBusy else { return }
            if case .available(let found) = result {
                candidate = found
                state = .available(version: found.version.description, notes: found.notes, isPrerelease: found.isPrerelease)
            }
            // 已是最新版：不改畫面（不跳「已是最新版本」）。
        } catch {
            // 自動檢查失敗一律靜默：不改狀態、不顯示紅字；不更新「上次成功時間」，由排程決定要不要重試。
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

    /// 選單列的更新項目：有新版時直接寫出版本號，否則是一般的「檢查更新…」。
    var menuBarTitle: String {
        if case .available(let version, _, _) = state {
            return String(localized: "Update Available: \(version)…", comment: "Menu bar item shown when a new version was found; the argument is a version such as 0.2.0.")
        }
        return String(localized: "Check for Updates…", comment: "Menu bar item.")
    }

    /// 選單列項目的動作：開啟設定的「關於」；已經有新版就直接讓使用者看到更新面板，不重查。
    func openFromMenuBar() {
        SettingsWindowController.shared.showWindow()
        NotificationCenter.default.post(name: .showAboutSettings, object: nil)
        if case .available = state { return }
        check()
    }

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
