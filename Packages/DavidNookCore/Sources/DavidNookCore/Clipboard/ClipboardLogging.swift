import Foundation

/// 持久化操作的種類（log 只記錄「哪種操作失敗」，不記錄路徑、檔名或內容）。
public enum ClipboardPersistenceOperation: String, Sendable, Equatable {
    /// 寫入索引檔。
    case saveIndex
    /// 寫入圖片檔。
    case saveImage
    /// 刪除圖片檔。
    case deleteImage
    /// 清除全部。
    case deleteAll
}

/// 剪貼簿子系統的 log 事件。
/// 刻意設計成「只帶操作類型與數量」的列舉：型別本身就裝不下剪貼簿內容、檔名、路徑或搜尋字串，
/// 因此任何 logger 實作都不可能洩漏內容。
public enum ClipboardLogEvent: Equatable, Sendable {
    /// 啟動時載入了 count 筆。
    case loaded(count: Int)
    /// 新增一筆條目。
    case itemAdded(kind: ClipboardKind)
    /// 重複內容，只更新使用時間。
    case itemDeduplicated(kind: ClipboardKind)
    /// 條目被 bump 到最前面。
    case itemBumped
    /// 因超出筆數上限淘汰了 count 筆。
    case itemsEvicted(count: Int)
    /// 因超過保留期移除了 count 筆。
    case itemsExpired(count: Int)
    /// 使用者移除一筆。
    case itemRemoved
    /// 釘選狀態改變。
    case pinChanged(isPinned: Bool)
    /// 清除了 count 筆（includingPinned 表示是否連釘選一起清）。
    case cleared(count: Int, includingPinned: Bool)
    /// 暫停記錄。
    case recordingPaused
    /// 恢復記錄。
    case recordingResumed
    /// 載入時丟棄了 count 筆無效條目（欄位損毀、圖片檔遺失等）。
    case itemsDropped(count: Int)
    /// 索引檔損毀，已改名保留為 .corrupt。
    case indexCorrupted
    /// 某種持久化操作失敗。
    case persistenceFailed(operation: ClipboardPersistenceOperation)
    /// monitor 讀到快照但決定略過（只記原因）。
    case snapshotSkipped(reason: ClipboardSkipReason)
    /// monitor 偵測到自己寫回的內容。
    case ownWriteDetected
    /// 已把某種類的條目寫回剪貼簿。
    case writtenBack(kind: ClipboardKind)
}

/// 可注入的 logger 協定。預設實作為 no-op；App 若要接 os_log，只能記錄 ClipboardLogEvent 本身（不含內容）。
public protocol ClipboardLogging: Sendable {
    /// 記錄一個事件。
    func log(_ event: ClipboardLogEvent)
}

/// 什麼都不做的 logger（預設）。
public struct NoOpClipboardLogger: ClipboardLogging {
    /// 建立 no-op logger。
    public init() {}

    /// 忽略事件。
    public func log(_ event: ClipboardLogEvent) {}
}
