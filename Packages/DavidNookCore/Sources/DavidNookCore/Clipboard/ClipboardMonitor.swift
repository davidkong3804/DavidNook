import Foundation

/// 可取消的排程代表。
public protocol ClipboardCancellable: Sendable {
    /// 取消排程（可重複呼叫）。
    func cancel()
}

/// 排程器抽象：以固定間隔重複呼叫 handler。測試用手動排程器取代真實計時器。
public protocol ClipboardScheduler: Sendable {
    /// 每隔 interval 秒呼叫一次 handler，直到回傳的 token 被取消。
    func scheduleRepeating(interval: TimeInterval, handler: @escaping @Sendable () async -> Void) -> ClipboardCancellable
}

/// 以 Swift Task 睡眠迴圈實作的排程器（不佔用執行緒）。
public struct TaskClipboardScheduler: ClipboardScheduler {
    /// 建立排程器。
    public init() {}

    /// 每隔 interval 秒呼叫一次 handler；等 handler 做完才開始下一輪計時。
    public func scheduleRepeating(interval: TimeInterval, handler: @escaping @Sendable () async -> Void) -> ClipboardCancellable {
        let nanoseconds = UInt64(max(interval, 0.001) * 1_000_000_000)
        let task = Task(priority: .utility) {
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: nanoseconds) } catch { break }
                if Task.isCancelled { break }
                await handler()
            }
        }
        return TaskCancellable(task: task)
    }

    private final class TaskCancellable: ClipboardCancellable, @unchecked Sendable {
        let task: Task<Void, Never>
        init(task: Task<Void, Never>) { self.task = task }
        func cancel() { task.cancel() }
    }
}

/// ClipboardMonitor 的錯誤。
public enum ClipboardMonitorError: Error, Equatable {
    /// 圖片條目的圖片檔遺失，無法寫回。
    case imageDataUnavailable
    /// 這個條目無法轉成可寫入剪貼簿的表示法。
    case unsupportedItem
}

/// 以 changeCount 輪詢剪貼簿，把新內容經 policy 過濾後交給 ClipboardStore。
///
/// - changeCount 沒變 → 完全不讀內容（避免觸發 macOS 剪貼簿存取提示、也省資源）。
/// - 暫停中 → 只消耗 changeCount，不讀內容；暫停期間複製的東西，恢復後也不會被補記。
/// - 讀取途中 changeCount 又變了 → 丟棄這次結果，下次輪詢重讀（避免型別與資料來自不同次複製）。
/// - 啟動時以當下 changeCount 為基準，不會讀取、記錄「啟動前就在剪貼簿上的內容」。
///
/// 執行緒模型：actor；輪詢與 writeBack 串行執行。
public actor ClipboardMonitor {
    private let reader: PasteboardReading
    private let store: ClipboardStore
    private let policy: ClipboardPolicy
    private let scheduler: ClipboardScheduler
    private let interval: TimeInterval
    private let logger: ClipboardLogging
    private var lastChangeCount: Int?
    private var token: ClipboardCancellable?

    /// 建立 monitor。interval 預設 0.5 秒；scheduler 可注入以便測試。
    public init(
        reader: PasteboardReading,
        store: ClipboardStore,
        policy: ClipboardPolicy = ClipboardPolicy(),
        scheduler: ClipboardScheduler = TaskClipboardScheduler(),
        interval: TimeInterval = 0.5,
        logger: ClipboardLogging = NoOpClipboardLogger()
    ) {
        self.reader = reader
        self.store = store
        self.policy = policy
        self.scheduler = scheduler
        self.interval = interval
        self.logger = logger
    }

    deinit {
        token?.cancel()
    }

    /// 是否正在輪詢。
    public var isRunning: Bool { token != nil }

    /// 開始輪詢；已在執行則不做事。以當下 changeCount 為基準。
    public func start() {
        guard token == nil else { return }
        lastChangeCount = reader.changeCount
        token = scheduler.scheduleRepeating(interval: interval) { [weak self] in
            await self?.pollOnce()
        }
    }

    /// 把基準 changeCount 對齊到當下（不讀內容）。
    public func syncBaseline() {}

    /// 停止輪詢。
    public func stop() {
        token?.cancel()
        token = nil
    }

    /// 檢查一次剪貼簿（排程器每個 tick 呼叫；測試也可手動呼叫）。
    public func pollOnce(now: Date = Date()) async {
        let current = reader.changeCount
        guard current != lastChangeCount else { return }

        if await store.isPaused {
            lastChangeCount = current
            logger.log(.snapshotSkipped(reason: .paused))
            return
        }

        let snapshot = reader.snapshot()
        let decision = policy.evaluate(snapshot)

        // 讀取期間剪貼簿又變了：這次的型別與資料可能來自不同次複製，丟棄並保留舊基準，下次輪詢重讀。
        guard reader.changeCount == snapshot.changeCount else { return }
        lastChangeCount = snapshot.changeCount

        switch decision {
        case .record(let capture):
            await store.add(capture, now: now)
        case .ownWrite(let itemID):
            logger.log(.ownWriteDetected)
            if let itemID { await store.bump(id: itemID, now: now) }
        case .skip(let reason):
            logger.log(.snapshotSkipped(reason: reason))
        }
    }

    /// 把歷史條目寫回剪貼簿（內容＋本 app 的標記型別），並把該條目 bump 到最前面。
    /// 回傳寫入後的 changeCount；monitor 會記住它，因此不會把自己寫的內容再記一次。
    /// 圖片檔遺失時拋出 `.imageDataUnavailable`，且不會動到剪貼簿。
    @discardableResult
    public func writeBack(item: ClipboardItem, to writer: PasteboardWriting, now: Date = Date()) async throws -> Int {
        var imageData: Data?
        if item.kind == .image {
            imageData = await store.imageData(for: item)
            guard imageData != nil else { throw ClipboardMonitorError.imageDataUnavailable }
        }
        guard let representations = item.pasteboardRepresentations(imageData: imageData) else {
            throw ClipboardMonitorError.unsupportedItem
        }
        let newCount = writer.write(representations)
        lastChangeCount = newCount
        await store.bump(id: item.id, now: now)
        logger.log(.writtenBack(kind: item.kind))
        return newCount
    }
}
