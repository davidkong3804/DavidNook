import Foundation
import XCTest
@testable import DavidNookCore

// 剪貼簿測試共用輔助。
// 規則：任何測試都不得讀寫使用者真正的系統剪貼簿；
// 需要真實 NSPasteboard 的測試只能用 NSPasteboard(name:) 建立的具名剪貼簿，並在 tearDown 釋放。

typealias PBType = ClipboardPasteboardType

/// 測試用的固定時間基準（秒偏移）。
func t(_ seconds: Double) -> Date {
    Date(timeIntervalSince1970: 1_700_000_000 + seconds)
}

func utf8(_ string: String) -> Data {
    Data(string.utf8)
}

/// 建立臨時目錄，測試結束後自動刪除（同時還原可能被改掉的權限）。
func makeTempDirectory(for testCase: XCTestCase) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("DavidNookTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    testCase.addTeardownBlock {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        try? FileManager.default.removeItem(at: url)
    }
    return url
}

func posixPermissions(of url: URL) throws -> Int {
    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attrs[.posixPermissions] as? NSNumber)?.intValue ?? -1
}

func directoryEntries(_ url: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
}

/// 該路徑是否被標為「不納入備份」（Time Machine 等；`URLResourceValues.isExcludedFromBackup`）。
func isExcludedFromBackup(_ url: URL) throws -> Bool {
    try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup ?? false
}

/// 1x1 PNG（最小的合法 PNG，用於圖片案例）。
let tinyPNG: Data = Data(base64Encoded:
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!

// MARK: - Snapshot 輔助

/// 記錄 snapshot 的資料被讀了幾次、讀了哪些型別（用來證明「被略過的內容不會被讀取」）。
final class DataReadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var types: [String] = []
    var readTypes: [String] { lock.withLock { types } }
    var count: Int { lock.withLock { types.count } }
    func record(_ type: String) { lock.withLock { types.append(type) } }
}

func makeSnapshot(_ entries: [String: Data], changeCount: Int = 1, source: String? = nil) -> PasteboardSnapshot {
    PasteboardSnapshot(
        changeCount: changeCount,
        types: entries.keys.sorted(),
        data: entries.mapValues { [$0] },
        sourceAppBundleID: source
    )
}

func makeCountingSnapshot(_ entries: [String: Data], counter: DataReadCounter, changeCount: Int = 1) -> PasteboardSnapshot {
    PasteboardSnapshot(changeCount: changeCount, types: entries.keys.sorted()) { type in
        counter.record(type)
        return entries[type].map { [$0] } ?? []
    }
}

func fileURLData(_ path: String) -> Data {
    utf8(URL(fileURLWithPath: path).absoluteString)
}

// MARK: - 假剪貼簿（可讀可寫）

final class FakePasteboard: PasteboardReading, PasteboardWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var items: [[String: Data]] = []
    private var snapshotCalls = 0
    private var dataReads: [String] = []
    private var writes: [[[PasteboardRepresentation]]] = []
    /// 每次「資料被讀取」後呼叫（用來模擬讀取途中剪貼簿又變了）。
    var onDataRead: (@Sendable () -> Void)?

    var changeCount: Int { lock.withLock { count } }
    var snapshotCallCount: Int { lock.withLock { snapshotCalls } }
    var dataReadTypes: [String] { lock.withLock { dataReads } }
    var writtenItems: [[[PasteboardRepresentation]]] { lock.withLock { writes } }
    var currentItems: [[String: Data]] { lock.withLock { items } }

    /// 模擬另一個 App 複製內容（changeCount +1）。
    func copy(_ entries: [String: Data]) {
        copyItems([entries])
    }

    func copyItems(_ newItems: [[String: Data]]) {
        lock.withLock {
            items = newItems
            count += 1
        }
    }

    /// 只增加 changeCount、不改內容（模擬「換了擁有者但內容相同」）。
    func touch() {
        lock.withLock { count += 1 }
    }

    func snapshot() -> PasteboardSnapshot {
        let (c, snapshotItems): (Int, [[String: Data]]) = lock.withLock {
            snapshotCalls += 1
            return (count, items)
        }
        var types: [String] = []
        for item in snapshotItems {
            for key in item.keys.sorted() where !types.contains(key) { types.append(key) }
        }
        return PasteboardSnapshot(changeCount: c, types: types) { [weak self] type in
            guard let self else { return [] }
            let result: [Data] = self.lock.withLock {
                self.dataReads.append(type)
                return snapshotItems.compactMap { $0[type] }
            }
            self.onDataRead?()
            return result
        }
    }

    func write(_ newItems: [[PasteboardRepresentation]]) -> Int {
        lock.withLock {
            writes.append(newItems)
            items = newItems.map { rep in
                Dictionary(rep.map { ($0.type, $0.data) }, uniquingKeysWith: { _, last in last })
            }
            count += 1
            return count
        }
    }
}

// MARK: - 手動排程器

final class ManualClipboardScheduler: ClipboardScheduler, @unchecked Sendable {
    private final class Token: ClipboardCancellable, @unchecked Sendable {
        let onCancel: @Sendable () -> Void
        init(onCancel: @escaping @Sendable () -> Void) { self.onCancel = onCancel }
        func cancel() { onCancel() }
    }

    private let lock = NSLock()
    private var entries: [Int: @Sendable () async -> Void] = [:]
    private var nextID = 0
    private var intervals: [TimeInterval] = []
    private var cancels = 0

    var scheduledIntervals: [TimeInterval] { lock.withLock { intervals } }
    var cancelCount: Int { lock.withLock { cancels } }
    var activeCount: Int { lock.withLock { entries.count } }

    func scheduleRepeating(interval: TimeInterval, handler: @escaping @Sendable () async -> Void) -> ClipboardCancellable {
        let id: Int = lock.withLock {
            nextID += 1
            entries[nextID] = handler
            intervals.append(interval)
            return nextID
        }
        return Token { [weak self] in
            self?.lock.withLock {
                if self?.entries.removeValue(forKey: id) != nil { self?.cancels += 1 }
            }
        }
    }

    /// 觸發所有仍有效的排程（相當於時間走了一個 interval）。
    func fire() async {
        let handlers = lock.withLock { Array(entries.values) }
        for handler in handlers { await handler() }
    }
}

// MARK: - logger spy

final class SpyClipboardLogger: ClipboardLogging, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [ClipboardLogEvent] = []

    var events: [ClipboardLogEvent] { lock.withLock { recorded } }

    /// 所有事件轉成字串後的內容（describing 與 reflecting 兩種），用來掃描是否含有敏感內容。
    var renderedMessages: [String] {
        events.flatMap { [String(describing: $0), String(reflecting: $0)] }
    }

    func log(_ event: ClipboardLogEvent) {
        lock.withLock { recorded.append(event) }
    }

    func assertNoneContain(_ secrets: [String], file: StaticString = #filePath, line: UInt = #line) {
        for message in renderedMessages {
            for secret in secrets {
                XCTAssertFalse(message.contains(secret), "logger 收到含內容的訊息：\(message)", file: file, line: line)
            }
        }
    }
}

// MARK: - 會讓存圖失敗的 persistence

final class FailingImagePersistence: ClipboardPersistence, @unchecked Sendable {
    struct Failure: Error {}
    let inner = InMemoryClipboardPersistence()
    func loadItems() -> [ClipboardItem] { inner.loadItems() }
    func saveItems(_ items: [ClipboardItem]) throws { try inner.saveItems(items) }
    func saveImage(_ data: Data, fileName: String) throws { throw Failure() }
    func loadImage(fileName: String) -> Data? { inner.loadImage(fileName: fileName) }
    func imageExists(fileName: String) -> Bool { inner.imageExists(fileName: fileName) }
    func deleteImage(fileName: String) throws { try inner.deleteImage(fileName: fileName) }
    func imageFileNames() -> [String] { inner.imageFileNames() }
    func deleteAll() throws { try inner.deleteAll() }
}

// MARK: - 索引寫入可被切換成失敗的 persistence（F3：失敗後的 dirty／重試）

final class FlakyIndexPersistence: ClipboardPersistence, @unchecked Sendable {
    struct Failure: Error {}
    private let lock = NSLock()
    private var failSave = false
    private var failDelete = false
    private var attempts = 0
    let inner = InMemoryClipboardPersistence()

    /// 為 true 時 `saveItems` 一律拋錯（磁碟已滿、唯讀等）。
    var failSaveItems: Bool {
        get { lock.withLock { failSave } }
        set { lock.withLock { failSave = newValue } }
    }
    /// 為 true 時 `deleteAll` 一律拋錯。
    var failDeleteAll: Bool {
        get { lock.withLock { failDelete } }
        set { lock.withLock { failDelete = newValue } }
    }
    var saveAttempts: Int { lock.withLock { attempts } }
    /// 磁碟上（記憶體模擬）實際保存的條目——重啟後會被載入的就是它。
    var persistedItems: [ClipboardItem] { inner.loadItems() }

    func loadItems() -> [ClipboardItem] { inner.loadItems() }
    func saveItems(_ items: [ClipboardItem]) throws {
        let shouldFail: Bool = lock.withLock {
            attempts += 1
            return failSave
        }
        if shouldFail { throw Failure() }
        try inner.saveItems(items)
    }
    func saveImage(_ data: Data, fileName: String) throws { try inner.saveImage(data, fileName: fileName) }
    func loadImage(fileName: String) -> Data? { inner.loadImage(fileName: fileName) }
    func imageExists(fileName: String) -> Bool { inner.imageExists(fileName: fileName) }
    func deleteImage(fileName: String) throws { try inner.deleteImage(fileName: fileName) }
    func imageFileNames() -> [String] { inner.imageFileNames() }
    func deleteAll() throws {
        if lock.withLock({ failDelete }) { throw Failure() }
        try inner.deleteAll()
    }
}
