import DavidNookCore
import Foundation

/// 剪貼簿面板上的所有文案；預設為繁體中文，App 傳入在地化後的字串。
public struct ClipboardPanelStrings {
    public var searchPlaceholder: String
    public var filterAll: String
    public var filterText: String
    public var filterImage: String
    public var filterFiles: String
    public var pauseHelp: String
    public var resumeHelp: String
    public var pin: String
    public var unpin: String
    public var delete: String
    public var imageLabel: String
    /// 檔案列的「N 個項目」。
    public var itemCount: (Int) -> String

    public var emptyHistory: String
    public var emptyHistoryHint: String
    public var noResults: String
    public var pausedTitle: String
    public var pausedHint: String
    public var resume: String
    public var permissionTitle: String
    public var permissionDetail: String
    public var openSettings: String

    public init(
        searchPlaceholder: String, filterAll: String, filterText: String, filterImage: String, filterFiles: String,
        pauseHelp: String, resumeHelp: String, pin: String, unpin: String, delete: String, imageLabel: String,
        itemCount: @escaping (Int) -> String,
        emptyHistory: String, emptyHistoryHint: String, noResults: String,
        pausedTitle: String, pausedHint: String, resume: String,
        permissionTitle: String, permissionDetail: String, openSettings: String
    ) {
        self.searchPlaceholder = searchPlaceholder
        self.filterAll = filterAll
        self.filterText = filterText
        self.filterImage = filterImage
        self.filterFiles = filterFiles
        self.pauseHelp = pauseHelp
        self.resumeHelp = resumeHelp
        self.pin = pin
        self.unpin = unpin
        self.delete = delete
        self.imageLabel = imageLabel
        self.itemCount = itemCount
        self.emptyHistory = emptyHistory
        self.emptyHistoryHint = emptyHistoryHint
        self.noResults = noResults
        self.pausedTitle = pausedTitle
        self.pausedHint = pausedHint
        self.resume = resume
        self.permissionTitle = permissionTitle
        self.permissionDetail = permissionDetail
        self.openSettings = openSettings
    }

    /// 繁體中文（預設）。
    public static let zhHant = ClipboardPanelStrings(
        searchPlaceholder: "搜尋剪貼簿",
        filterAll: "全部", filterText: "文字", filterImage: "圖片", filterFiles: "檔案",
        pauseHelp: "暫停記錄", resumeHelp: "恢復記錄",
        pin: "釘選", unpin: "取消釘選", delete: "刪除", imageLabel: "圖片",
        itemCount: { "\($0) 個項目" },
        emptyHistory: "剪貼簿是空的", emptyHistoryHint: "複製文字、圖片或檔案後會出現在這裡",
        noResults: "找不到符合的項目",
        pausedTitle: "已暫停記錄", pausedHint: "暫停期間複製的內容不會被補記", resume: "恢復",
        permissionTitle: "需要允許貼上權限",
        permissionDetail: "請在「系統設定 → 隱私權與安全性 → 從其他App貼上」把 DavidNook 設為「允許」",
        openSettings: "開啟系統設定"
    )
}

/// 剪貼簿面板的使用者操作回呼（面板本身不含儲存或監看邏輯）。
public struct ClipboardPanelCallbacks {
    public var onQueryChange: (String) -> Void
    public var onFilterChange: (ClipboardTypeFilter) -> Void
    public var onActivate: (UUID) -> Void
    public var onTogglePin: (UUID) -> Void
    public var onDelete: (UUID) -> Void
    public var onTogglePause: () -> Void
    public var onOpenPermissionSettings: () -> Void

    public init(
        onQueryChange: @escaping (String) -> Void = { _ in },
        onFilterChange: @escaping (ClipboardTypeFilter) -> Void = { _ in },
        onActivate: @escaping (UUID) -> Void = { _ in },
        onTogglePin: @escaping (UUID) -> Void = { _ in },
        onDelete: @escaping (UUID) -> Void = { _ in },
        onTogglePause: @escaping () -> Void = {},
        onOpenPermissionSettings: @escaping () -> Void = {}
    ) {
        self.onQueryChange = onQueryChange
        self.onFilterChange = onFilterChange
        self.onActivate = onActivate
        self.onTogglePin = onTogglePin
        self.onDelete = onDelete
        self.onTogglePause = onTogglePause
        self.onOpenPermissionSettings = onOpenPermissionSettings
    }
}
