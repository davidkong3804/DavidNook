import Foundation

/// 持久化層的錯誤（刻意不夾帶路徑或內容）。
public enum ClipboardPersistenceError: Error, Equatable {
    /// 圖片檔名不合法（可能是路徑穿越）。
    case invalidFileName
    /// 寫入檔案失敗。
    case writeFailed
    /// 存放目錄無法建立或設定權限。
    case directoryUnavailable
    /// 刪除檔案失敗。
    case deleteFailed
}

/// 剪貼簿資料的持久化抽象：索引（條目清單）＋圖片檔。
/// 所有方法皆為同步；由 ClipboardStore（actor）串行呼叫。
public protocol ClipboardPersistence: Sendable {
    /// 載入索引。損毀時回傳空陣列（不崩潰）；圖片檔遺失的條目會被丟棄。
    func loadItems() -> [ClipboardItem]
    /// 以原子方式寫入整份索引。
    func saveItems(_ items: [ClipboardItem]) throws
    /// 寫入圖片檔（檔名須為 `<64 位小寫十六進位>.<副檔名>`）。
    func saveImage(_ data: Data, fileName: String) throws
    /// 讀取圖片檔；不存在或檔名不合法回傳 nil。
    func loadImage(fileName: String) -> Data?
    /// 圖片檔是否存在。
    func imageExists(fileName: String) -> Bool
    /// 刪除圖片檔；檔案不存在不算錯誤。
    func deleteImage(fileName: String) throws
    /// 目前存放的所有圖片檔名（已排序）。
    func imageFileNames() -> [String]
    /// 刪除本 app 產生的全部檔案（索引、圖片、損毀備份、暫存檔）。
    func deleteAll() throws
}

/// 記憶體版持久化（測試、SwiftUI 預覽用；不碰磁碟）。
public final class InMemoryClipboardPersistence: ClipboardPersistence, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [ClipboardItem] = []
    private var images: [String: Data] = [:]

    /// 建立空的記憶體持久化。
    public init() {}

    /// 載入已儲存的索引。
    public func loadItems() -> [ClipboardItem] {
        lock.withLock { items }
    }

    /// 儲存索引。
    public func saveItems(_ items: [ClipboardItem]) throws {
        lock.withLock { self.items = items }
    }

    /// 儲存圖片資料。
    public func saveImage(_ data: Data, fileName: String) throws {
        lock.withLock { images[fileName] = data }
    }

    /// 讀取圖片資料。
    public func loadImage(fileName: String) -> Data? {
        lock.withLock { images[fileName] }
    }

    /// 圖片是否存在。
    public func imageExists(fileName: String) -> Bool {
        lock.withLock { images[fileName] != nil }
    }

    /// 刪除圖片（不存在不算錯誤）。
    public func deleteImage(fileName: String) throws {
        lock.withLock { _ = images.removeValue(forKey: fileName) }
    }

    /// 所有圖片檔名（已排序）。
    public func imageFileNames() -> [String] {
        lock.withLock { images.keys.sorted() }
    }

    /// 清空索引與圖片。
    public func deleteAll() throws {
        lock.withLock {
            items = []
            images = [:]
        }
    }
}
