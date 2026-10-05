import Foundation

/// 系統「從其他 App 貼上」政策的 Core 版本（App 端把 `NSPasteboard.accessBehavior` 對應到這裡）。
public enum ClipboardAccessState: Equatable, Sendable {
    /// 可以讀取。
    case allowed
    /// 每次都會詢問：為了不反覆彈提示，暫停讀取內容。
    case askEveryTime
    /// 使用者設為拒絕：讀不到內容。
    case denied
}

/// 影響「要不要記錄、要不要輪詢」的全部輸入。
public struct ClipboardRecordingInputs: Equatable, Sendable {
    /// 記錄功能總開關。
    public var enabled: Bool
    /// 使用者按了暫停。
    public var userPaused: Bool
    /// 系統的剪貼簿存取政策。
    public var access: ClipboardAccessState

    /// 建立輸入。
    public init(enabled: Bool, userPaused: Bool, access: ClipboardAccessState) {
        self.enabled = enabled
        self.userPaused = userPaused
        self.access = access
    }
}

/// 把輸入套用到 store／monitor 的一個步驟。
public enum ClipboardRecordingStep: Equatable, Sendable {
    /// 讓 store 進入暫停。
    case pauseStore
    /// 把 monitor 的基準 changeCount 對齊到當下（不讀內容）。
    case syncBaseline
    /// 讓 store 恢復記錄。
    case resumeStore
    /// 啟動 monitor 輪詢。
    case startMonitor
    /// 停止 monitor 輪詢。
    case stopMonitor
}

/// 暫停／恢復／權限變化的決策與套用（純邏輯＋薄的執行層）。
public enum ClipboardRecordingPlanner {
    /// 有效暫停：功能關閉，或使用者暫停。
    public static func effectivePaused(_ inputs: ClipboardRecordingInputs) -> Bool {
        !inputs.enabled || inputs.userPaused
    }

    /// 是否該輪詢：功能開啟，且系統允許讀取。
    public static func shouldMonitor(_ inputs: ClipboardRecordingInputs) -> Bool {
        inputs.enabled && inputs.access == .allowed
    }

    /// 由目前狀態與期望輸入算出要執行的步驟（依序）。
    public static func steps(
        for inputs: ClipboardRecordingInputs,
        storeIsPaused: Bool,
        monitorIsRunning: Bool
    ) -> [ClipboardRecordingStep] {
        let wantPaused = effectivePaused(inputs)
        let wantMonitor = shouldMonitor(inputs)
        let resume = !wantPaused && storeIsPaused
        let start = wantMonitor && !monitorIsRunning

        var result: [ClipboardRecordingStep] = []
        if wantPaused, !storeIsPaused { result.append(.pauseStore) }
        // 任何「恢復讀取」的路徑（恢復記錄、重新啟用功能、權限由拒絕轉允許）都先對齊基準，
        // 這樣暫停／停止期間發生的複製不會在恢復後被補記。
        if resume || start { result.append(.syncBaseline) }
        if resume { result.append(.resumeStore) }
        if start { result.append(.startMonitor) }
        if !wantMonitor, monitorIsRunning { result.append(.stopMonitor) }
        return result
    }

    /// 依序執行步驟。呼叫端必須串行呼叫（App 端的 reconcile 已串成一條）。
    public static func apply(_ inputs: ClipboardRecordingInputs, store: ClipboardStore, monitor: ClipboardMonitor) async {
        let storeIsPaused = await store.isPaused
        let monitorIsRunning = await monitor.isRunning
        for step in steps(for: inputs, storeIsPaused: storeIsPaused, monitorIsRunning: monitorIsRunning) {
            switch step {
            case .pauseStore: await store.pause()
            case .syncBaseline: await monitor.syncBaseline()
            case .resumeStore: await store.resume()
            case .startMonitor: await monitor.start()
            case .stopMonitor: await monitor.stop()
            }
        }
    }
}

/// 定期維護：以固定間隔對 store 做 prune（保留期、隔離檔、索引重試）。
public final class ClipboardMaintenance: @unchecked Sendable {
    /// 預設維護間隔（秒）：每 5 分鐘一次，確保「保留 1 天」不會實際拖到 25 小時才清。
    public static let pruneInterval: TimeInterval = 300

    private let store: ClipboardStore
    private let scheduler: ClipboardScheduler
    private let interval: TimeInterval
    private let onTick: (@Sendable () -> Void)?
    private let lock = NSLock()
    private var token: ClipboardCancellable?

    /// 建立維護排程；`onTick` 在每次 prune 完成後呼叫（App 端用來刷新 UI）。
    public init(
        store: ClipboardStore,
        scheduler: ClipboardScheduler = TaskClipboardScheduler(),
        interval: TimeInterval = ClipboardMaintenance.pruneInterval,
        onTick: (@Sendable () -> Void)? = nil
    ) {
        self.store = store
        self.scheduler = scheduler
        self.interval = interval
        self.onTick = onTick
    }

    deinit { token?.cancel() }

    /// 是否已排程。
    public var isRunning: Bool { lock.withLock { token != nil } }

    /// 開始排程（重複呼叫不會重複排程）。
    public func start() {
        lock.withLock {
            guard token == nil else { return }
            let store = store
            let onTick = onTick
            token = scheduler.scheduleRepeating(interval: interval) {
                await store.prune()
                onTick?()
            }
        }
    }

    /// 停止排程。
    public func stop() {
        lock.withLock {
            token?.cancel()
            token = nil
        }
    }
}
