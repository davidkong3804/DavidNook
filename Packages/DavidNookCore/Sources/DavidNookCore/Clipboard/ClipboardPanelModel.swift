import Foundation

// 紅燈階段的骨架：只有公開介面，行為尚未實作（測試應該失敗）。

/// 類型篩選（全部／文字／圖片／檔案）。
public enum ClipboardTypeFilter: String, CaseIterable, Sendable, Equatable {
    case all
    case text
    case image
    case files

    /// 這個篩選是否包含某種條目。
    public func includes(_ kind: ClipboardKind) -> Bool {
        false
    }
}

/// 面板能處理的鍵盤操作（已由 UI 層把按鍵翻成這些語意）。
public enum ClipboardPanelKey: Equatable, Sendable {
    case up
    case down
    case home
    case end
    case enter
    case commandDelete
    case commandP
    case escape
}

/// 鍵盤操作的結果：由呼叫端（服務層）去執行真正的寫回／刪除／釘選／收合。
public enum ClipboardPanelAction: Equatable, Sendable {
    case none
    case paste(UUID)
    case delete(UUID)
    case togglePin(UUID)
    case collapse
}

/// 列表是空的時候該顯示什麼。
public enum ClipboardPanelEmptyState: Equatable, Sendable {
    case needsPermission
    case paused
    case noHistory
    case noResults
}

/// 列表上方的狀態橫幅。
public enum ClipboardPanelBanner: Equatable, Sendable {
    case needsPermission
    case paused
}

/// 剪貼簿面板的狀態模型（純邏輯，不依賴 SwiftUI）。
public struct ClipboardPanelModel: Equatable, Sendable {
    public private(set) var allItems: [ClipboardItem] = []
    public private(set) var query: String = ""
    public private(set) var filter: ClipboardTypeFilter = .all
    public private(set) var isPaused = false
    public private(set) var needsPermission = false
    public private(set) var visibleItems: [ClipboardItem] = []
    public private(set) var selectedIndex: Int?

    public init(
        items: [ClipboardItem] = [],
        query: String = "",
        filter: ClipboardTypeFilter = .all,
        isPaused: Bool = false,
        needsPermission: Bool = false
    ) {}

    public var selectedItem: ClipboardItem? { nil }
    public var emptyState: ClipboardPanelEmptyState? { nil }
    public var banner: ClipboardPanelBanner? { nil }
    public var pinnedCount: Int { 0 }

    public mutating func setItems(_ items: [ClipboardItem]) {}
    public mutating func setQuery(_ query: String) {}
    public mutating func setFilter(_ filter: ClipboardTypeFilter) {}
    public mutating func setPaused(_ paused: Bool) {}
    public mutating func setNeedsPermission(_ needs: Bool) {}
    public mutating func select(index: Int) {}
    public mutating func select(id: UUID) {}

    @discardableResult
    public mutating func handle(_ key: ClipboardPanelKey) -> ClipboardPanelAction { .none }
}

public extension ClipboardItem {
    /// 是否符合搜尋字串（前後空白會先去掉；空字串視為全部符合）。
    func matches(searchQuery: String) -> Bool {
        false
    }
}
