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

    /// 列上動作的 tooltip（含快捷鍵）。
    public var copyHelp: String
    public var pinHelp: String
    public var unpinHelp: String
    public var deleteHelp: String
    /// 點擊後的回饋文字。
    public var copied: String
    public var copyFailed: String

    public var emptyHistory: String
    public var emptyHistoryHint: String
    public var noResults: String
    public var noResultsHint: String
    public var pausedTitle: String
    /// 暫停狀態「為什麼／怎麼辦」（空狀態用，可兩行）。
    public var pausedHint: String
    /// 暫停橫幅上的一行短說明（列表有資料時用）。
    public var pausedBannerDetail: String
    public var resume: String
    public var permissionTitle: String
    /// 權限狀態「為什麼」（空狀態用）。
    public var permissionWhy: String
    /// 權限狀態「怎麼辦」（到系統設定的哪裡）。
    public var permissionDetail: String
    public var openSettings: String

    /// 底部提示列：依「自動貼上」實際狀態切換的點擊說明。
    public var hintClick: (ClipboardAutoPasteMode) -> String
    /// 底部提示列：鍵盤操作。
    public var hintKeys: String
    public var showHintsHelp: String
    public var hideHintsHelp: String

    public init(
        searchPlaceholder: String, filterAll: String, filterText: String, filterImage: String, filterFiles: String,
        pauseHelp: String, resumeHelp: String, pin: String, unpin: String, delete: String, imageLabel: String,
        itemCount: @escaping (Int) -> String,
        copyHelp: String, pinHelp: String, unpinHelp: String, deleteHelp: String,
        copied: String, copyFailed: String,
        emptyHistory: String, emptyHistoryHint: String, noResults: String, noResultsHint: String,
        pausedTitle: String, pausedHint: String, pausedBannerDetail: String, resume: String,
        permissionTitle: String, permissionWhy: String, permissionDetail: String, openSettings: String,
        hintClick: @escaping (ClipboardAutoPasteMode) -> String, hintKeys: String,
        showHintsHelp: String, hideHintsHelp: String
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
        self.copyHelp = copyHelp
        self.pinHelp = pinHelp
        self.unpinHelp = unpinHelp
        self.deleteHelp = deleteHelp
        self.copied = copied
        self.copyFailed = copyFailed
        self.emptyHistory = emptyHistory
        self.emptyHistoryHint = emptyHistoryHint
        self.noResults = noResults
        self.noResultsHint = noResultsHint
        self.pausedTitle = pausedTitle
        self.pausedHint = pausedHint
        self.pausedBannerDetail = pausedBannerDetail
        self.resume = resume
        self.permissionTitle = permissionTitle
        self.permissionWhy = permissionWhy
        self.permissionDetail = permissionDetail
        self.openSettings = openSettings
        self.hintClick = hintClick
        self.hintKeys = hintKeys
        self.showHintsHelp = showHintsHelp
        self.hideHintsHelp = hideHintsHelp
    }

    /// 繁體中文（預設）。
    public static let zhHant = ClipboardPanelStrings(
        searchPlaceholder: "搜尋剪貼簿",
        filterAll: "全部", filterText: "文字", filterImage: "圖片", filterFiles: "檔案",
        pauseHelp: "暫停記錄", resumeHelp: "恢復記錄",
        pin: "釘選", unpin: "取消釘選", delete: "刪除", imageLabel: "圖片",
        itemCount: { "\($0) 個項目" },
        copyHelp: "複製回剪貼簿（Return）", pinHelp: "釘選（⌘P）", unpinHelp: "取消釘選（⌘P）", deleteHelp: "刪除（⌘⌫）",
        copied: "已複製", copyFailed: "複製失敗",
        emptyHistory: "剪貼簿是空的", emptyHistoryHint: "複製文字、圖片或檔案後會出現在這裡。點一下列，就能複製回剪貼簿",
        noResults: "找不到符合的項目", noResultsHint: "換個關鍵字，或把上方篩選改成「全部」",
        pausedTitle: "已暫停記錄",
        pausedHint: "暫停期間複製的內容不會被記下，恢復後也不會補記。想繼續記錄，請按「恢復」",
        pausedBannerDetail: "暫停期間複製的內容不會被記下",
        resume: "恢復",
        permissionTitle: "需要允許貼上權限",
        permissionWhy: "macOS 限制了 DavidNook 讀取剪貼簿（每次都詢問或已拒絕），所以暫時無法記錄",
        permissionDetail: "請在「系統設定 → 隱私權與安全性 → 從其他App貼上」把 DavidNook 設為「允許」",
        openSettings: "開啟系統設定",
        hintClick: { mode in
            switch mode {
            case .off: return "點一下列：複製回剪貼簿（要自動貼上，請到設定開啟）"
            case .needsPermission: return "點一下列：複製回剪貼簿（自動貼上尚未授權）"
            case .on: return "點一下列：複製並自動貼上"
            }
        },
        hintKeys: "↑↓ 選取　↩ 複製　⌘P 釘選　⌘⌫ 刪除　直接輸入即可搜尋",
        showHintsHelp: "顯示操作提示", hideHintsHelp: "隱藏操作提示"
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
    /// 提示列上的 ✕：關閉操作提示。
    public var onDismissHints: () -> Void
    /// 頂端列的說明按鈕：顯示／隱藏操作提示。
    public var onToggleHints: () -> Void

    public init(
        onQueryChange: @escaping (String) -> Void = { _ in },
        onFilterChange: @escaping (ClipboardTypeFilter) -> Void = { _ in },
        onActivate: @escaping (UUID) -> Void = { _ in },
        onTogglePin: @escaping (UUID) -> Void = { _ in },
        onDelete: @escaping (UUID) -> Void = { _ in },
        onTogglePause: @escaping () -> Void = {},
        onOpenPermissionSettings: @escaping () -> Void = {},
        onDismissHints: @escaping () -> Void = {},
        onToggleHints: @escaping () -> Void = {}
    ) {
        self.onQueryChange = onQueryChange
        self.onFilterChange = onFilterChange
        self.onActivate = onActivate
        self.onTogglePin = onTogglePin
        self.onDelete = onDelete
        self.onTogglePause = onTogglePause
        self.onOpenPermissionSettings = onOpenPermissionSettings
        self.onDismissHints = onDismissHints
        self.onToggleHints = onToggleHints
    }
}
