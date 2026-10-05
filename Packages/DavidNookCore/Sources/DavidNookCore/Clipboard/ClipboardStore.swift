import Foundation

/// `ClipboardStore.add` 的結果。
public enum ClipboardAddResult: Equatable, Sendable {
    /// 新增了一筆條目。
    case inserted(ClipboardItem)
    /// 內容重複：沒有新增，而是更新既有條目的 lastUsedAt 並移到最前面。
    case bumped(ClipboardItem)
    /// 沒有處理（暫停中，或圖片檔寫入失敗）。
    case ignored
}

/// 剪貼簿歷史：記憶體狀態＋持久化。
///
/// 執行緒模型：這是一個 actor。所有狀態讀寫與持久化寫入都在 actor 內串行執行，
/// 因此多個任務並發存取不會產生資料競爭，記憶體與磁碟索引、圖片檔始終一致。
/// 代價是呼叫端需要 `await`；持久化為同步磁碟 I/O，在 actor 上執行（資料量小，可接受）。
///
/// 規則摘要：
/// - 去重鍵 = kind + contentHash；重複內容只更新 lastUsedAt 並移到最前面（保留釘選）。
/// - 筆數上限 `maxItems` 只計「未釘選」條目；超出時淘汰最舊的未釘選項目。釘選項目不被上限與保留期淘汰。
/// - 保留期 `retention` 以 lastUsedAt 計算（重新複製或貼回會重新計時）；nil = 永久。
/// - `clearAll()` 刪除全部（含釘選、含磁碟上的圖片檔）。
public actor ClipboardStore {
    /// 未釘選條目的筆數上限（至少 1）。
    public private(set) var maxItems: Int
    /// 保留時間（秒）；nil 表示永久保留。
    public private(set) var retention: TimeInterval?
    /// 是否暫停記錄中。
    public private(set) var isPaused = false

    /// 以「最近使用在前」排列的條目（新增/bump 一律插到最前面）。對外請用 `items`。
    private var storage: [ClipboardItem]
    private let persistence: ClipboardPersistence
    private let logger: ClipboardLogging

    /// 建立 store 並從持久化載入既有條目（載入時會合併重複內容、清掉沒有條目參照的殘留圖片檔、套用筆數上限）。
    public init(
        persistence: ClipboardPersistence,
        maxItems: Int = 100,
        retention: TimeInterval? = nil,
        logger: ClipboardLogging = NoOpClipboardLogger()
    ) {
        let limit = max(1, maxItems)
        var loaded = Self.sortedByLastUsed(persistence.loadItems())

        // 合併索引內重複內容，只留最近使用的一筆
        var seen = Set<String>()
        loaded = loaded.filter { seen.insert($0.dedupKey).inserted }

        // 套用上限
        let evicted = Self.overflowIDs(loaded, maxItems: limit)
        let evictedImages = loaded.filter { evicted.contains($0.id) }.compactMap(\.imageFileName)
        loaded.removeAll { evicted.contains($0.id) }
        for name in evictedImages { try? persistence.deleteImage(fileName: name) }

        // 清掉沒有任何條目參照的圖片檔（例如索引寫入失敗後的殘留）
        let referenced = Set(loaded.compactMap(\.imageFileName))
        for name in persistence.imageFileNames() where !referenced.contains(name) {
            try? persistence.deleteImage(fileName: name)
        }

        self.persistence = persistence
        self.logger = logger
        self.maxItems = limit
        self.retention = retention
        self.storage = loaded
        logger.log(.loaded(count: loaded.count))
        if !evicted.isEmpty { logger.log(.itemsEvicted(count: evicted.count)) }
    }

    // MARK: 讀取

    /// 全部條目：釘選在前，其餘依 lastUsedAt 由新到舊。
    public var items: [ClipboardItem] {
        Self.displayOrder(storage)
    }

    /// 依 id 取得條目。
    public func item(id: UUID) -> ClipboardItem? {
        storage.first { $0.id == id }
    }

    /// 讀取圖片條目的圖片資料；非圖片或檔案遺失回傳 nil。
    public func imageData(for item: ClipboardItem) -> Data? {
        guard item.kind == .image, let name = item.imageFileName else { return nil }
        return persistence.loadImage(fileName: name)
    }

    /// 搜尋。空（或純空白）查詢回傳全部。
    /// 文字：內容不分大小寫；檔案：路徑片段；圖片：只比對來源 App（沒有來源 App 的圖片不會被命中）。
    /// 結果順序與 `items` 相同：釘選在前、其餘依 lastUsedAt 由新到舊。
    public func search(query: String) -> [ClipboardItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let ordered = items
        guard !trimmed.isEmpty else { return ordered }
        return ordered.filter { $0.matches(searchQuery: trimmed) }
    }

    // MARK: 寫入

    /// 記錄一份內容。暫停中回傳 `.ignored`；重複內容回傳 `.bumped`。
    @discardableResult
    public func add(_ capture: ClipboardCapture, now: Date = Date()) -> ClipboardAddResult {
        guard !isPaused else { return .ignored }
        let key = capture.dedupKey

        if let index = storage.firstIndex(where: { $0.dedupKey == key }) {
            var item = storage.remove(at: index)
            item.lastUsedAt = now
            if let source = capture.sourceAppBundleID { item.sourceAppBundleID = source }
            // 圖片檔被外部刪掉時，重複複製會把它補回
            if case .image(let data, _) = capture.payload, let name = item.imageFileName, !persistence.imageExists(fileName: name) {
                saveImage(data, fileName: name)
            }
            storage.insert(item, at: 0)
            logger.log(.itemDeduplicated(kind: item.kind))
            persistIndex()
            return .bumped(item)
        }

        let item = ClipboardItem(capture: capture, now: now)
        if case .image(let data, _) = capture.payload, let name = item.imageFileName {
            guard saveImage(data, fileName: name) else { return .ignored }
        }
        storage.insert(item, at: 0)
        logger.log(.itemAdded(kind: item.kind))
        enforceLimit()
        persistIndex()
        return .inserted(item)
    }

    /// 把條目標為「剛用過」並移到最前面（例如自己寫回剪貼簿時）。找不到回傳 false。
    @discardableResult
    public func bump(id: UUID, now: Date = Date()) -> Bool {
        guard let index = storage.firstIndex(where: { $0.id == id }) else { return false }
        var item = storage.remove(at: index)
        item.lastUsedAt = now
        storage.insert(item, at: 0)
        logger.log(.itemBumped)
        persistIndex()
        return true
    }

    /// 切換釘選；回傳新的狀態，找不到回傳 nil。取消釘選後若未釘選筆數超出上限，會淘汰最舊的未釘選項目。
    @discardableResult
    public func togglePin(id: UUID) -> Bool? {
        guard let index = storage.firstIndex(where: { $0.id == id }) else { return nil }
        storage[index].isPinned.toggle()
        let state = storage[index].isPinned
        logger.log(.pinChanged(isPinned: state))
        if !state { enforceLimit() }
        persistIndex()
        return state
    }

    /// 移除一筆（含圖片檔）。找不到回傳 false。
    @discardableResult
    public func remove(id: UUID) -> Bool {
        guard storage.contains(where: { $0.id == id }) else { return false }
        removeItems(ids: [id])
        logger.log(.itemRemoved)
        persistIndex()
        return true
    }

    /// 依保留期移除過期且未釘選的條目，回傳移除筆數。`now` 可注入。
    /// 年齡剛好等於保留期視為尚未過期。
    @discardableResult
    public func prune(now: Date = Date()) -> Int {
        guard let retention else { return 0 }
        let expired = Set(storage.filter { !$0.isPinned && now.timeIntervalSince($0.lastUsedAt) > retention }.map(\.id))
        guard !expired.isEmpty else { return 0 }
        removeItems(ids: expired)
        logger.log(.itemsExpired(count: expired.count))
        persistIndex()
        return expired.count
    }

    /// 暫停記錄。
    public func pause() {
        guard !isPaused else { return }
        isPaused = true
        logger.log(.recordingPaused)
    }

    /// 恢復記錄。
    public func resume() {
        guard isPaused else { return }
        isPaused = false
        logger.log(.recordingResumed)
    }

    /// 修改筆數上限（至少 1），立即淘汰超出的最舊未釘選項目。
    public func setMaxItems(_ value: Int) {
        maxItems = max(1, value)
        enforceLimit()
        persistIndex()
    }

    /// 修改保留時間（nil = 永久）；於下次 `prune(now:)` 生效。
    public func setRetention(_ value: TimeInterval?) {
        retention = value
    }

    /// 清除全部：刪除所有條目（包含釘選）與磁碟上的全部檔案（索引、圖片檔、損毀備份）。
    /// 記憶體一律先清空；磁碟刪除失敗時拋出錯誤。
    public func clearAll() throws {
        let count = storage.count
        storage.removeAll()
        logger.log(.cleared(count: count, includingPinned: true))
        do {
            try persistence.deleteAll()
        } catch {
            logger.log(.persistenceFailed(operation: .deleteAll))
            throw error
        }
    }

    /// 只清除未釘選的條目（含其圖片檔）。
    public func clearUnpinned() {
        let ids = Set(storage.filter { !$0.isPinned }.map(\.id))
        removeItems(ids: ids)
        logger.log(.cleared(count: ids.count, includingPinned: false))
        persistIndex()
    }

    // MARK: 內部

    @discardableResult
    private func saveImage(_ data: Data, fileName: String) -> Bool {
        do {
            try persistence.saveImage(data, fileName: fileName)
            return true
        } catch {
            logger.log(.persistenceFailed(operation: .saveImage))
            return false
        }
    }

    private func persistIndex() {
        do {
            try persistence.saveItems(storage)
        } catch {
            logger.log(.persistenceFailed(operation: .saveIndex))
        }
    }

    /// 從記憶體移除並刪除對應圖片檔（不寫索引、不記錄事件，由呼叫端決定）。
    private func removeItems(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let removed = storage.filter { ids.contains($0.id) }
        storage.removeAll { ids.contains($0.id) }
        for name in removed.compactMap(\.imageFileName) {
            do {
                try persistence.deleteImage(fileName: name)
            } catch {
                logger.log(.persistenceFailed(operation: .deleteImage))
            }
        }
    }

    private func enforceLimit() {
        let victims = Self.overflowIDs(storage, maxItems: maxItems)
        guard !victims.isEmpty else { return }
        removeItems(ids: victims)
        logger.log(.itemsEvicted(count: victims.count))
    }

    // MARK: 純函式

    /// 依 lastUsedAt 由新到舊排序；時間相同時維持原本（最近使用在前）的相對順序。
    private static func sortedByLastUsed(_ items: [ClipboardItem]) -> [ClipboardItem] {
        items.enumerated()
            .sorted { a, b in
                a.element.lastUsedAt != b.element.lastUsedAt ? a.element.lastUsedAt > b.element.lastUsedAt : a.offset < b.offset
            }
            .map(\.element)
    }

    /// 顯示順序：釘選在前，其餘依 lastUsedAt 由新到舊（同時間者維持最近使用在前）。
    private static func displayOrder(_ items: [ClipboardItem]) -> [ClipboardItem] {
        items.enumerated()
            .sorted { a, b in
                if a.element.isPinned != b.element.isPinned { return a.element.isPinned }
                if a.element.lastUsedAt != b.element.lastUsedAt { return a.element.lastUsedAt > b.element.lastUsedAt }
                return a.offset < b.offset
            }
            .map(\.element)
    }

    /// 超出筆數上限、應被淘汰的未釘選條目 id（最舊者優先）。
    private static func overflowIDs(_ items: [ClipboardItem], maxItems: Int) -> Set<UUID> {
        let unpinned = sortedByLastUsed(items.filter { !$0.isPinned })
        guard unpinned.count > maxItems else { return [] }
        return Set(unpinned.dropFirst(maxItems).map(\.id))
    }
}
