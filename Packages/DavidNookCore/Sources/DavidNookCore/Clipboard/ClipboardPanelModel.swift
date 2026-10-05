import Foundation

/// 類型篩選（全部／文字／圖片／檔案）。
public enum ClipboardTypeFilter: String, CaseIterable, Sendable, Equatable {
    case all
    case text
    case image
    case files

    /// 這個篩選是否包含某種條目。
    public func includes(_ kind: ClipboardKind) -> Bool {
        switch self {
        case .all: return true
        case .text: return kind == .text
        case .image: return kind == .image
        case .files: return kind == .files
        }
    }
}

/// 面板能處理的鍵盤操作（已由 UI 層把按鍵翻成這些語意）。
public enum ClipboardPanelKey: Equatable, Sendable {
    /// ↑
    case up
    /// ↓
    case down
    /// Home
    case home
    /// End
    case end
    /// Enter（貼回目前選取的條目）
    case enter
    /// ⌘⌫（刪除目前選取的條目）
    case commandDelete
    /// ⌘P（切換釘選）
    case commandP
    /// Esc（先清搜尋，沒有搜尋字串時收合面板）
    case escape
}

/// 鍵盤操作的結果：由呼叫端（服務層）去執行真正的寫回／刪除／釘選／收合；模型本身不改動歷史資料。
public enum ClipboardPanelAction: Equatable, Sendable {
    /// 沒有需要執行的動作（可能只是移動了選取或清掉搜尋字串）。
    case none
    /// 把該條目寫回剪貼簿。
    case paste(UUID)
    /// 刪除該條目。
    case delete(UUID)
    /// 切換該條目的釘選。
    case togglePin(UUID)
    /// 收合面板。
    case collapse
}

/// 列表（套用搜尋與篩選後）是空的時候該顯示什麼。優先序：需要權限 ＞ 暫停中 ＞ 沒有歷史；
/// 有歷史但被搜尋或篩選排除光了則是「找不到符合的項目」。
public enum ClipboardPanelEmptyState: Equatable, Sendable {
    /// 需要「允許從其他 App 貼上」才能記錄，而且還沒有任何歷史。
    case needsPermission
    /// 暫停記錄中，而且還沒有任何歷史。
    case paused
    /// 還沒有任何歷史。
    case noHistory
    /// 有歷史，但搜尋或篩選結果為空。
    case noResults
}

/// 列表上方的狀態橫幅。權限問題比暫停更要緊，兩者同時成立時只顯示權限。
public enum ClipboardPanelBanner: Equatable, Sendable {
    case needsPermission
    case paused
}

/// 剪貼簿面板的狀態模型（純邏輯，不依賴 SwiftUI；值型別，方便測試與在 UI 層以 `@Published` 持有）。
///
/// 輸入：store 的條目快照、搜尋字串、類型篩選、暫停／權限旗標、使用者的鍵盤操作。
/// 輸出：可顯示列表、選取索引、空狀態與橫幅、鍵盤操作對應的動作。
///
/// 選取規則：
/// - 列表非空時永遠有一列被選取，預設第一列（Enter 直接貼最上面那筆）；列表為空時 `selectedIndex == nil`。
/// - 使用者用鍵盤或滑鼠明確選過某列之後（explicit），快照更新或搜尋字串改變時：該條目仍在列表中就跟著它，
///   否則把原索引夾回 `0…count-1`（因此刪掉一筆後，同一索引上的下一筆被選取；列表變短不會越界）。
/// - 還沒明確選過（implicit）時，選取永遠跟著第一列。
/// - 切換類型篩選一律重設到第一列。
public struct ClipboardPanelModel: Equatable, Sendable {
    /// store 給的原始條目（顯示前會依釘選與 lastUsedAt 重新排序）。
    public private(set) var allItems: [ClipboardItem] = []
    /// 搜尋字串（原樣保存；比對時才去除前後空白）。
    public private(set) var query: String = ""
    /// 類型篩選。
    public private(set) var filter: ClipboardTypeFilter = .all
    /// 是否暫停記錄中。
    public private(set) var isPaused = false
    /// 是否因為系統的剪貼簿存取設定而無法記錄。
    public private(set) var needsPermission = false
    /// 套用排序、篩選與搜尋後的列表（釘選在前，其餘依 lastUsedAt 由新到舊）。
    public private(set) var visibleItems: [ClipboardItem] = []
    /// 目前選取的列（列表為空時為 nil）。
    public private(set) var selectedIndex: Int?

    /// 使用者是否明確選過列（見型別說明）。
    private var selectionIsExplicit = false

    /// 建立模型並立即計算列表與預設選取。
    public init(
        items: [ClipboardItem] = [],
        query: String = "",
        filter: ClipboardTypeFilter = .all,
        isPaused: Bool = false,
        needsPermission: Bool = false
    ) {
        self.allItems = items
        self.query = query
        self.filter = filter
        self.isPaused = isPaused
        self.needsPermission = needsPermission
        rebuild(resettingSelection: true)
    }

    // MARK: 輸出

    /// 目前選取的條目。
    public var selectedItem: ClipboardItem? {
        guard let selectedIndex, visibleItems.indices.contains(selectedIndex) else { return nil }
        return visibleItems[selectedIndex]
    }

    /// 列表為空時該顯示的狀態；列表有列時為 nil。
    public var emptyState: ClipboardPanelEmptyState? {
        guard visibleItems.isEmpty else { return nil }
        if !allItems.isEmpty { return .noResults }
        if needsPermission { return .needsPermission }
        if isPaused { return .paused }
        return .noHistory
    }

    /// 狀態橫幅（暫停或需要權限時才有）。
    public var banner: ClipboardPanelBanner? {
        if needsPermission { return .needsPermission }
        if isPaused { return .paused }
        return nil
    }

    /// 可顯示列表中釘選項目的數量（釘選都排在最前面；UI 可據此畫分隔線）。
    public var pinnedCount: Int {
        visibleItems.prefix { $0.isPinned }.count
    }

    // MARK: 輸入

    /// 換上新的 store 快照。
    public mutating func setItems(_ items: [ClipboardItem]) {
        allItems = items
        rebuild(resettingSelection: false)
    }

    /// 設定搜尋字串。選取索引夾限（而不是重設）；沒有明確選過時跟著第一列。
    public mutating func setQuery(_ query: String) {
        guard query != self.query else { return }
        self.query = query
        rebuild(resettingSelection: false)
    }

    /// 切換類型篩選；真的改變時選取重設到第一列。
    public mutating func setFilter(_ filter: ClipboardTypeFilter) {
        guard filter != self.filter else { return }
        self.filter = filter
        rebuild(resettingSelection: true)
    }

    /// 暫停／恢復狀態（只影響橫幅與空狀態）。
    public mutating func setPaused(_ paused: Bool) {
        isPaused = paused
    }

    /// 是否需要權限（只影響橫幅與空狀態）。
    public mutating func setNeedsPermission(_ needs: Bool) {
        needsPermission = needs
    }

    /// 以索引選取一列（例如滑鼠 hover）；超出範圍的索引被忽略。
    public mutating func select(index: Int) {
        guard visibleItems.indices.contains(index) else { return }
        selectedIndex = index
        selectionIsExplicit = true
    }

    /// 以 id 選取一列；不在目前列表中的 id 被忽略。
    public mutating func select(id: UUID) {
        guard let index = visibleItems.firstIndex(where: { $0.id == id }) else { return }
        select(index: index)
    }

    /// 處理一個鍵盤操作。移動類按鍵回傳 `.none`；Enter／⌘⌫／⌘P 回傳對應動作（沒有選取列時為 `.none`）。
    @discardableResult
    public mutating func handle(_ key: ClipboardPanelKey) -> ClipboardPanelAction {
        switch key {
        case .up:
            move(to: { index, _ in index - 1 })
            return .none
        case .down:
            move(to: { index, _ in index + 1 })
            return .none
        case .home:
            move(to: { _, _ in 0 })
            return .none
        case .end:
            move(to: { _, count in count - 1 })
            return .none
        case .enter:
            return selectedItem.map { .paste($0.id) } ?? .none
        case .commandDelete:
            return selectedItem.map { .delete($0.id) } ?? .none
        case .commandP:
            return selectedItem.map { .togglePin($0.id) } ?? .none
        case .escape:
            if !query.isEmpty {
                setQuery("")
                return .none
            }
            return .collapse
        }
    }

    // MARK: 內部

    private mutating func move(to target: (_ current: Int, _ count: Int) -> Int) {
        guard !visibleItems.isEmpty else { return }
        let count = visibleItems.count
        let current = selectedIndex ?? 0
        selectedIndex = min(max(target(current, count), 0), count - 1)
        selectionIsExplicit = true
    }

    /// 重新計算 `visibleItems` 與選取。
    private mutating func rebuild(resettingSelection: Bool) {
        let previousID = selectedItem?.id
        let previousIndex = selectedIndex
        visibleItems = Self.displayList(allItems, query: query, filter: filter)

        guard !visibleItems.isEmpty else {
            selectedIndex = nil
            if resettingSelection { selectionIsExplicit = false }
            return
        }
        if resettingSelection {
            selectionIsExplicit = false
            selectedIndex = 0
            return
        }
        guard selectionIsExplicit else {
            selectedIndex = 0
            return
        }
        if let previousID, let index = visibleItems.firstIndex(where: { $0.id == previousID }) {
            selectedIndex = index
        } else {
            selectedIndex = min(previousIndex ?? 0, visibleItems.count - 1)
        }
    }

    /// 篩選、搜尋、排序：釘選在前；其餘依 lastUsedAt 由新到舊；同時間者維持輸入順序。
    static func displayList(_ items: [ClipboardItem], query: String, filter: ClipboardTypeFilter) -> [ClipboardItem] {
        items.enumerated()
            .filter { filter.includes($0.element.kind) && $0.element.matches(searchQuery: query) }
            .sorted { a, b in
                if a.element.isPinned != b.element.isPinned { return a.element.isPinned }
                if a.element.lastUsedAt != b.element.lastUsedAt { return a.element.lastUsedAt > b.element.lastUsedAt }
                return a.offset < b.offset
            }
            .map(\.element)
    }
}

public extension ClipboardItem {
    /// 是否符合搜尋字串（前後空白會先去掉；空字串視為全部符合）。
    /// 文字：內容不分大小寫；檔案：路徑片段；圖片：只比對來源 App（沒有來源 App 的圖片不會被命中）。
    func matches(searchQuery: String) -> Bool {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        switch kind {
        case .text:
            return text?.range(of: trimmed, options: .caseInsensitive) != nil
        case .files:
            return filePaths?.contains { $0.range(of: trimmed, options: .caseInsensitive) != nil } ?? false
        case .image:
            return sourceAppBundleID?.range(of: trimmed, options: .caseInsensitive) != nil
        }
    }
}
