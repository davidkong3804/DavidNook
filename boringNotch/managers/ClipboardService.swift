//
//  ClipboardService.swift
//  DavidNook
//
//  薄適配層：把 DavidNookCore 的剪貼簿管線（ClipboardStore ＋ ClipboardMonitor ＋ NSPasteboard 讀寫端）
//  接到 App：啟動時依設定決定是否監看、設定變更即時套用、每 5 分鐘 prune、處理 macOS 的剪貼簿存取隱私設定。
//  過濾（密碼管理員標記型別、大小上限、自己寫回的標記）、去重、釘選、保留期都在 Core，有測試。
//
//  隱私：
//  - 本檔沒有任何 log／print；Core 的 logger 事件只含「操作種類與數量」，這裡只拿來觸發 UI 重新整理。
//  - 資料只存在本機 Application Support/DavidNook/Clipboard（目錄 0700、檔案 0600，沙盒內）。
//  - `NSPasteboard.general` 在這個 App 只有三種用途（見各處註解）：輪詢 changeCount（不讀內容）、
//    變更後交給 Core 讀取內容、使用者點選歷史項目時寫回、讀取 `accessBehavior`（只是屬性，不碰內容）。
//

import AppKit
import Carbon.HIToolbox
import DavidNookCore
import Defaults
import Foundation

// MARK: - 系統的「從其他 App 貼上」設定

/// 系統對本 App 讀取剪貼簿的政策。
///
/// macOS 15.4 起，程式在背景讀取 `NSPasteboard.general` 的內容（不是使用者按 ⌘V 觸發）會跳系統提示，
/// 使用者可在「系統設定 → 隱私權與安全性 → 從其他 App 貼上」逐 App 設為詢問／允許／拒絕。
/// 對應 `NSPasteboard.accessBehavior`（AppKit 標頭：`API_AVAILABLE(macos(15.4))`）：
/// - `.default`：從沒觸發過提示；第一次讀內容時系統會問一次，之後狀態自動變 `.ask`。
/// - `.ask`：每次程式存取都會詢問 → 背景輪詢會反覆跳提示。
/// - `.alwaysAllow`：自動允許。
/// - `.alwaysDeny`：自動拒絕（讀不到內容）。
enum ClipboardAccess: Equatable, Sendable {
    /// 可以讀取（`.default`、`.alwaysAllow`，或 macOS 15.4 以前沒有這個機制）。
    case allowed
    /// 每次都會詢問：為了不反覆彈提示，暫停讀取內容，請使用者改成「允許」。
    case askEveryTime
    /// 使用者設為拒絕：讀不到內容。
    case denied

    var needsPermission: Bool { self != .allowed }

    /// 對應到 Core 的存取狀態（暫停／恢復的決策在 Core，有測試）。
    var coreState: ClipboardAccessState {
        switch self {
        case .allowed: return .allowed
        case .askEveryTime: return .askEveryTime
        case .denied: return .denied
        }
    }

    /// 讀取目前狀態。`accessBehavior` 只是個屬性（標頭沒有說讀它會觸發提示），不會讀剪貼簿內容。
    static func current(of pasteboard: NSPasteboard) -> ClipboardAccess {
        guard #available(macOS 15.4, *) else { return .allowed }
        switch pasteboard.accessBehavior {
        case .default, .alwaysAllow: return .allowed
        case .ask: return .askEveryTime
        case .alwaysDeny: return .denied
        @unknown default: return .allowed
        }
    }
}

// MARK: - Core logger → UI 重新整理

/// 讓 Core 的 logger 事件（只含操作種類與數量，不含內容）能觸發 UI 重新整理；不輸出任何 log。
/// 以獨立物件串接，避免在 `ClipboardService.shared` 初始化期間（store 建立時就會 log 一次）回頭存取 `shared`。
private final class ClipboardChangeSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?

    func setHandler(_ handler: @escaping @Sendable () -> Void) {
        lock.withLock { self.handler = handler }
    }

    func fire() {
        let current = lock.withLock { handler }
        current?()
    }
}

private struct ClipboardChangeLogger: ClipboardLogging {
    let signal: ClipboardChangeSignal

    func log(_ event: ClipboardLogEvent) {
        switch event {
        case .snapshotSkipped, .ownWriteDetected, .recordingPaused, .recordingResumed,
             .persistenceFailed, .indexCorrupted, .itemsDropped:
            return
        default:
            signal.fire()
        }
    }
}

// MARK: - 服務

@MainActor
final class ClipboardService: ObservableObject {
    static let shared = ClipboardService()

    /// 歷史條目快照（Core 的顯示順序：釘選在前、其餘依最近使用）。
    @Published private(set) var items: [ClipboardItem] = []
    /// 目前是否「有效暫停」：使用者暫停，或整個記錄功能被關閉。
    @Published private(set) var isPaused: Bool = false
    /// 系統的剪貼簿存取設定；不是 `.allowed` 時不讀取內容。
    @Published private(set) var access: ClipboardAccess = .allowed

    var needsPermission: Bool { access.needsPermission }

    private let pasteboard: NSPasteboard
    private let store: ClipboardStore
    private let monitor: ClipboardMonitor
    /// 定期維護（prune）：Core 排程，間隔見 `ClipboardMaintenance.pruneInterval`（≤ 5 分鐘）。
    private let maintenance: ClipboardMaintenance
    private let writer: NSPasteboardWriter
    /// 圖片檔所在目錄（磁碟版持久化才有；記憶體後備模式為 nil）。
    private let imageDirectory: URL?

    private var started = false
    private var settingsTask: Task<Void, Never>?
    private var accessTask: Task<Void, Never>?
    private var reconcileTask: Task<Void, Never>?
    private var refreshPending = false
    private var appNameCache: [String: String?] = [:]

    /// 檢查系統存取設定的間隔（只讀屬性，很便宜）。
    private static let accessPollInterval: Duration = .seconds(3)

    private init() {
        let signal = ClipboardChangeSignal()
        let logger = ClipboardChangeLogger(signal: signal)

        // 這是整個 App 唯一取得系統剪貼簿的地方（讀取端、寫入端與 accessBehavior 都用同一個參考）。
        let general = NSPasteboard.general
        pasteboard = general

        let persistence: ClipboardPersistence
        var directory: URL?
        if let dir = Self.storageDirectory(), let file = try? FileClipboardPersistence(directory: dir, logger: logger) {
            persistence = file
            directory = dir
        } else {
            // 存放目錄無法建立：退回記憶體版（不寫磁碟；重開 App 就沒有歷史）。
            persistence = InMemoryClipboardPersistence()
        }
        imageDirectory = directory

        store = ClipboardStore(
            persistence: persistence,
            maxItems: Defaults[.clipboardMaxItems],
            retention: Self.retention(days: Defaults[.clipboardRetentionDays]),
            logger: logger
        )
        // 單項大小上限用 Core 預設（文字 1MB、圖片 20MB），不開放設定。
        monitor = ClipboardMonitor(
            reader: NSPasteboardReader(pasteboard: general),
            store: store,
            policy: ClipboardPolicy(),
            logger: logger
        )
        maintenance = ClipboardMaintenance(store: store) { signal.fire() }
        writer = NSPasteboardWriter(pasteboard: general)
        let initialAccess = ClipboardAccess.current(of: general)
        access = initialAccess
        isPaused = ClipboardRecordingPlanner.effectivePaused(Self.recordingInputs(access: initialAccess))

        signal.setHandler { [weak self] in
            Task { @MainActor in self?.scheduleRefresh() }
        }
    }

    // MARK: 啟動／停止

    /// App 啟動時呼叫（可重複呼叫）。依設定決定是否開始監看；之後設定變更與存取設定變更都會即時套用。
    func start() {
        guard !started else { return }
        started = true

        access = ClipboardAccess.current(of: pasteboard)
        settingsTask = Task { [weak self] in
            let keys: [Defaults._AnyKey] = [
                Defaults.Keys.clipboardEnabled, Defaults.Keys.clipboardPaused,
                Defaults.Keys.clipboardMaxItems, Defaults.Keys.clipboardRetentionDays,
            ]
            // initial: true → 啟動時先套用一次（含啟動時的 prune）。
            for await _ in Defaults.updates(keys, initial: true) {
                self?.requestReconcile()
            }
        }
        accessTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.accessPollInterval)
                guard let self, !Task.isCancelled else { return }
                let current = ClipboardAccess.current(of: self.pasteboard)
                if current != self.access {
                    self.access = current
                    self.requestReconcile()
                }
            }
        }
        maintenance.start()
        scheduleRefresh()
    }

    /// App 結束前呼叫：停止輪詢與計時。
    func stop() {
        settingsTask?.cancel()
        accessTask?.cancel()
        maintenance.stop()
        reconcileTask?.cancel()
        let monitor = monitor
        Task { await monitor.stop() }
    }

    // MARK: 使用者操作

    /// 把某筆歷史寫回剪貼簿（Core 會附自身標記，所以不會被重複記錄，並把它 bump 到最前面）。
    /// 回傳是否成功（圖片檔遺失或無法轉成剪貼簿表示法時為 false，剪貼簿不會被動到）。
    func paste(_ item: ClipboardItem) async -> Bool {
        do {
            try await monitor.writeBack(item: item, to: writer)
            scheduleRefresh()
            return true
        } catch {
            return false
        }
    }

    func togglePin(id: UUID) {
        Task { await store.togglePin(id: id) }
    }

    func remove(id: UUID) {
        Task { await store.remove(id: id) }
    }

    /// 清除未釘選項目（含其圖片檔）。
    func clearUnpinned() {
        Task { await store.clearUnpinned() }
    }

    /// 清除全部（含釘選、含磁碟上的圖片檔與索引）。記憶體一律先清空；磁碟刪除失敗回傳 false。
    @discardableResult
    func clearAll() async -> Bool {
        let result: Bool
        do {
            try await store.clearAll()
            result = true
        } catch {
            result = false
        }
        items = []
        scheduleRefresh()
        return result
    }

    /// 面板上的「暫停／恢復」按鈕：目前有效暫停（暫停或整個功能關閉）就一律恢復記錄，否則暫停。
    func togglePause() {
        if isPaused {
            Defaults[.clipboardEnabled] = true
            Defaults[.clipboardPaused] = false
        } else {
            Defaults[.clipboardPaused] = true
        }
    }

    // MARK: 圖片與來源 App

    /// 圖片條目的磁碟檔位置（給縮圖用；不會把整張圖讀進記憶體）。
    func imageURL(for item: ClipboardItem) -> URL? {
        guard item.kind == .image, let name = item.imageFileName, let imageDirectory else { return nil }
        let url = imageDirectory.appendingPathComponent(name)
        // 檔名由 Core 產生（<hash>.<副檔名>）；多一道防線，索引被改成含路徑的字串時不採用。
        guard url.lastPathComponent == name else { return nil }
        return url
    }

    /// 來源 App 的顯示名稱（沒有或找不到回傳 nil，UI 會省略）。
    func appName(forBundleID bundleID: String?) -> String? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        if let cached = appNameCache[bundleID] { return cached }
        var name: String?
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let display = FileManager.default.displayName(atPath: url.path)
            name = display.hasSuffix(".app") ? String(display.dropLast(4)) : display
        }
        appNameCache[bundleID] = name
        return name
    }

    // MARK: 系統設定

    /// 開啟「系統設定 → 隱私權與安全性 → 從其他 App 貼上」。
    ///
    /// 公開文件沒有這個窗格的 URL（有開發者向 Apple 提過需求 FB17587724）。`Privacy_Pasteboard` 這個錨點
    /// 是在本機 macOS 的 Settings 擴充（SecurityPrivacyExtension）二進位內找到的，格式與其他隱私窗格
    /// （`Privacy_Camera` 等）一致，且該擴充宣告 `allowsXAppleSystemPreferencesURLScheme`；
    /// 但屬於未公開細節，所以找不到窗格時退回一般的「隱私權與安全性」頁。
    func openPasteboardPrivacySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Pasteboard",
            "x-apple.systempreferences:com.apple.preference.security?Privacy",
        ]
        for string in candidates {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    // MARK: 選用：點選後自動貼上（實驗性）

    /// 是否已取得「事件傳送」授權。沙盒內的 App 不能用 `AXIsProcessTrusted()`（輔助使用 TCC 服務與 App Sandbox
    /// 不相容）；Apple DTS 在開發者論壇的說明是：`CGEvent.post` 走 PostEvent 權限，在沙盒內可用，
    /// 檢查用 `CGPreflightPostEventAccess()`，在系統設定中顯示在「輔助使用」之下。這裡只做檢查，不會跳提示。
    var isAutoPasteAuthorized: Bool {
        CGPreflightPostEventAccess()
    }

    /// 只在使用者於設定頁按下明確按鈕時呼叫：向系統請求事件傳送授權（會跳系統提示）。
    @discardableResult
    func requestAutoPasteAuthorization() -> Bool {
        CGRequestPostEventAccess()
    }

    /// 寫回剪貼簿後，若使用者開啟了自動貼上且已授權，短延遲後送出 ⌘V（延遲是為了讓瀏海面板先收起、
    /// 把鍵盤焦點還給原本的 App）。沒授權時什麼都不做，不會彈任何提示。
    func performAutoPasteIfEnabled() {
        guard Defaults[.clipboardAutoPaste], CGPreflightPostEventAccess() else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            Self.postCommandV()
        }
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let key = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }

    // MARK: 內部

    /// 把設定與存取狀態套用到 store／monitor。多次呼叫會串成一條，確保依序執行。
    private func requestReconcile() {
        let previous = reconcileTask
        reconcileTask = Task { [weak self] in
            await previous?.value
            await self?.reconcile()
        }
    }

    private func reconcile() async {
        let inputs = Self.recordingInputs(access: access)
        let effectivePaused = ClipboardRecordingPlanner.effectivePaused(inputs)
        if isPaused != effectivePaused { isPaused = effectivePaused }

        // 暫停／恢復／啟停 monitor 的決策與順序在 Core（ClipboardRecordingPlanner，有測試）：
        // 暫停中 monitor 只消耗 changeCount，不讀內容；任何恢復路徑都會先 syncBaseline，
        // 所以暫停期間複製的內容不會在恢復後被補記。功能關閉，或系統設定需要使用者先處理（詢問／拒絕）時完全不讀。
        await ClipboardRecordingPlanner.apply(inputs, store: store, monitor: monitor)
        await store.setMaxItems(Defaults[.clipboardMaxItems])
        await store.setRetention(Self.retention(days: Defaults[.clipboardRetentionDays]))
        await store.prune()
        scheduleRefresh()
    }

    /// 合併短時間內的多次事件，之後從 store 取一次快照。
    private func scheduleRefresh() {
        guard !refreshPending else { return }
        refreshPending = true
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(30))
            guard let self else { return }
            self.refreshPending = false
            let snapshot = await self.store.items
            if snapshot != self.items { self.items = snapshot }
        }
    }

    private static func recordingInputs(access: ClipboardAccess) -> ClipboardRecordingInputs {
        ClipboardRecordingInputs(
            enabled: Defaults[.clipboardEnabled],
            userPaused: Defaults[.clipboardPaused],
            access: access.coreState
        )
    }

    /// 保留天數 → 秒；0（或負值）= 永久。
    private static func retention(days: Int) -> TimeInterval? {
        days > 0 ? TimeInterval(days) * 86_400 : nil
    }

    private static func storageDirectory() -> URL? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        return support.appendingPathComponent("DavidNook/Clipboard", isDirectory: true)
    }
}
