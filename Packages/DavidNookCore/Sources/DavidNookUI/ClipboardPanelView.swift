import AppKit
import DavidNookCore
import SwiftUI
import UniformTypeIdentifiers

/// 測試用：設為 true 時，列表不用 ScrollView、搜尋欄不用 TextField（兩者在 `ImageRenderer` 離屏渲染下不會畫出內容）。
/// 版面與資料完全相同，只是少了捲動與輸入。正式 App 一律是 false。
private struct ClipboardStaticRenderKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var clipboardStaticRender: Bool {
        get { self[ClipboardStaticRenderKey.self] }
        set { self[ClipboardStaticRenderKey.self] = newValue }
    }
}

/// 資料驅動的剪貼簿面板：頂部搜尋欄＋類型篩選＋暫停／恢復，下方是歷史列表，狀態以橫幅或空狀態表達。
///
/// 不含任何儲存、監看、寫回剪貼簿的邏輯：所有資料由 `model`（Core 的 `ClipboardPanelModel`）給定，
/// 所有操作以 `callbacks` 通知呼叫端；鍵盤操作（↑↓／Enter／⌘⌫／⌘P／Esc）由 App 端攔截後餵給模型，
/// 面板只負責顯示選取列並在選取改變時捲到可見處。
///
/// - 圖片列只顯示縮圖（見 `ClipboardThumbnailCache`：背景產生、有記憶體上限），原圖不進入視圖狀態。
/// - 文字列最多 2 行預覽（只取前 200 字，見 `ClipboardRowPreview`）；檔案列顯示檔名＋圖示＋「N 個項目」，完整路徑在 tooltip。
/// - 釘選狀態常駐可見；釘選／刪除按鈕在滑鼠停留或鍵盤選取時才出現。
/// - 版面為 578×128 pt 左右（展開瀏海內容區），列表可捲動。
public struct ClipboardPanelView: View {
    public var model: ClipboardPanelModel
    public var strings: ClipboardPanelStrings
    public var thumbnails: ClipboardThumbnailCache
    /// 圖片條目對應的磁碟檔 URL（由 App 端提供）。
    public var imageURL: (ClipboardItem) -> URL?
    /// 來源 App 的 bundle id → 顯示名稱；回傳 nil 就省略來源小字。
    public var appName: (String?) -> String?
    public var callbacks: ClipboardPanelCallbacks
    /// 出現時是否自動聚焦搜尋欄（視窗要能成為 key window 才會真的聚焦，由 App 端處理）。
    public var autoFocusSearch: Bool

    @FocusState private var searchFocused: Bool
    @Environment(\.clipboardStaticRender) private var staticRender

    public init(
        model: ClipboardPanelModel,
        strings: ClipboardPanelStrings = .zhHant,
        thumbnails: ClipboardThumbnailCache,
        imageURL: @escaping (ClipboardItem) -> URL?,
        appName: @escaping (String?) -> String? = { _ in nil },
        callbacks: ClipboardPanelCallbacks = ClipboardPanelCallbacks(),
        autoFocusSearch: Bool = true
    ) {
        self.model = model
        self.strings = strings
        self.thumbnails = thumbnails
        self.imageURL = imageURL
        self.appName = appName
        self.callbacks = callbacks
        self.autoFocusSearch = autoFocusSearch
    }

    public var body: some View {
        VStack(spacing: 6) {
            topBar
            if let banner = visibleBanner {
                bannerView(banner)
            }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            guard autoFocusSearch, !staticRender else { return }
            // 等視窗成為 key window 之後再聚焦（App 端在視圖出現時才讓視窗可成為 key）。
            try? await Task.sleep(for: .milliseconds(80))
            searchFocused = true
        }
    }

    // MARK: - 頂部列

    private var topBar: some View {
        HStack(spacing: 6) {
            searchField
            filterBar
            pauseButton
        }
        .frame(height: 26)
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.45))
            if staticRender {
                Text(verbatim: model.query.isEmpty ? strings.searchPlaceholder : model.query)
                    .font(LyricsFont.font(size: 12, weight: .regular))
                    .foregroundStyle(model.query.isEmpty ? Color.white.opacity(0.35) : Color.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField(
                    "",
                    text: Binding(get: { model.query }, set: { callbacks.onQueryChange($0) }),
                    prompt: Text(verbatim: strings.searchPlaceholder).foregroundStyle(Color.white.opacity(0.35))
                )
                .textFieldStyle(.plain)
                .font(LyricsFont.font(size: 12, weight: .regular))
                .foregroundStyle(Color.white)
                .focused($searchFocused)
            }
            if !model.query.isEmpty {
                Button { callbacks.onQueryChange("") } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity)
        .frame(height: 26)
        .background(Capsule().fill(Color.white.opacity(0.09)))
    }

    private var filterBar: some View {
        HStack(spacing: 2) {
            ForEach(ClipboardTypeFilter.allCases, id: \.self) { filter in
                let selected = model.filter == filter
                Button { callbacks.onFilterChange(filter) } label: {
                    Text(verbatim: label(for: filter))
                        .font(LyricsFont.font(size: 11, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Color.white : Color.white.opacity(0.55))
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(Capsule().fill(selected ? Color.white.opacity(0.18) : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    private var pauseButton: some View {
        Button { callbacks.onTogglePause() } label: {
            Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(model.isPaused ? Color.orange : Color.white.opacity(0.7))
                .frame(width: 26, height: 26)
                .background(Circle().fill(model.isPaused ? Color.orange.opacity(0.2) : Color.white.opacity(0.09)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(model.isPaused ? strings.resumeHelp : strings.pauseHelp)
        .accessibilityLabel(model.isPaused ? strings.resumeHelp : strings.pauseHelp)
    }

    private func label(for filter: ClipboardTypeFilter) -> String {
        switch filter {
        case .all: return strings.filterAll
        case .text: return strings.filterText
        case .image: return strings.filterImage
        case .files: return strings.filterFiles
        }
    }

    // MARK: - 橫幅

    /// 空狀態本身已經在講「暫停」或「需要權限」時，就不再重複顯示橫幅。
    private var visibleBanner: ClipboardPanelBanner? {
        switch model.emptyState {
        case .paused, .needsPermission: return nil
        default: return model.banner
        }
    }

    private func bannerView(_ banner: ClipboardPanelBanner) -> some View {
        HStack(spacing: 8) {
            Image(systemName: banner == .paused ? "pause.circle.fill" : "lock.shield.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: banner == .paused ? strings.pausedTitle : strings.permissionTitle)
                    .font(LyricsFont.font(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                if banner == .needsPermission {
                    Text(verbatim: strings.permissionDetail)
                        .font(LyricsFont.font(size: 9.5, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            bannerButton(banner)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.orange.opacity(0.14)))
        .accessibilityElement(children: .combine)
    }

    private func bannerButton(_ banner: ClipboardPanelBanner) -> some View {
        Button {
            if banner == .paused { callbacks.onTogglePause() } else { callbacks.onOpenPermissionSettings() }
        } label: {
            Text(verbatim: banner == .paused ? strings.resume : strings.openSettings)
                .font(LyricsFont.font(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 9)
                .frame(height: 20)
                .background(Capsule().fill(Color.orange.opacity(0.55)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 內容

    @ViewBuilder
    private var content: some View {
        if let state = model.emptyState {
            emptyView(state)
        } else {
            list
        }
    }

    private var rows: some View {
        ForEach(Array(model.visibleItems.enumerated()), id: \.element.id) { index, item in
            ClipboardRowView(
                item: item,
                isSelected: model.selectedIndex == index,
                strings: strings,
                thumbnails: thumbnails,
                imageURL: item.kind == .image ? imageURL(item) : nil,
                sourceAppName: appName(item.sourceAppBundleID),
                onActivate: { callbacks.onActivate(item.id) },
                onTogglePin: { callbacks.onTogglePin(item.id) },
                onDelete: { callbacks.onDelete(item.id) }
            )
            .id(item.id)
            // 釘選區與其餘之間的分隔線。
            if index == model.pinnedCount - 1, model.pinnedCount < model.visibleItems.count {
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 1)
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        if staticRender {
            VStack(spacing: 2) { rows }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 2) { rows }
                }
                .scrollIndicators(.never)
                .onChange(of: model.selectedItem?.id) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
        }
    }

    private func emptyView(_ state: ClipboardPanelEmptyState) -> some View {
        let title: String
        let hint: String?
        let symbol: String
        switch state {
        case .noHistory:
            title = strings.emptyHistory; hint = strings.emptyHistoryHint; symbol = "doc.on.clipboard"
        case .noResults:
            title = strings.noResults; hint = nil; symbol = "magnifyingglass"
        case .paused:
            title = strings.pausedTitle; hint = strings.pausedHint; symbol = "pause.circle"
        case .needsPermission:
            title = strings.permissionTitle; hint = strings.permissionDetail; symbol = "lock.shield"
        }
        return VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(state == .paused || state == .needsPermission ? Color.orange : Color.white.opacity(0.4))
            Text(verbatim: title)
                .font(LyricsFont.font(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.7))
            if let hint {
                Text(verbatim: hint)
                    .font(LyricsFont.font(size: 10, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            if state == .paused {
                emptyActionButton(strings.resume) { callbacks.onTogglePause() }
            } else if state == .needsPermission {
                emptyActionButton(strings.openSettings) { callbacks.onOpenPermissionSettings() }
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func emptyActionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(LyricsFont.font(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 10)
                .frame(height: 20)
                .background(Capsule().fill(Color.orange.opacity(0.55)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }
}

// MARK: - 列

struct ClipboardRowView: View {
    let item: ClipboardItem
    let isSelected: Bool
    let strings: ClipboardPanelStrings
    let thumbnails: ClipboardThumbnailCache
    let imageURL: URL?
    let sourceAppName: String?
    let onActivate: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    private var showsControls: Bool { isSelected || isHovering }

    var body: some View {
        HStack(spacing: 8) {
            leading
            titleBlock
                .frame(maxWidth: .infinity, alignment: .leading)
            if let sourceAppName {
                Text(verbatim: sourceAppName)
                    .font(LyricsFont.font(size: 9.5, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.38))
                    .lineLimit(1)
                    .frame(maxWidth: 84, alignment: .trailing)
            }
            pinButton
            deleteButton
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(minHeight: 36)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.16) : (isHovering ? Color.white.opacity(0.07) : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onActivate)
        .onHover { isHovering = $0 }
        .help(ClipboardRowPreview.tooltip(for: item) ?? "")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: Text(verbatim: item.isPinned ? strings.unpin : strings.pin), onTogglePin)
        .accessibilityAction(named: Text(verbatim: strings.delete), onDelete)
    }

    // MARK: 左側圖示／縮圖

    @ViewBuilder
    private var leading: some View {
        switch item.kind {
        case .text:
            Image(systemName: "text.alignleft")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.4))
                .frame(width: 30, height: 30)
        case .image:
            ClipboardThumbnailView(url: imageURL, cache: thumbnails, size: 30)
        case .files:
            Image(nsImage: ClipboardFileIcon.image(forPath: item.filePaths?.first ?? ""))
                .resizable()
                .scaledToFit()
                .frame(width: 26, height: 26)
                .frame(width: 30, height: 30)
        }
    }

    // MARK: 標題

    @ViewBuilder
    private var titleBlock: some View {
        switch item.kind {
        case .text:
            Text(verbatim: ClipboardRowPreview.text(item.text ?? ""))
                .font(LyricsFont.font(size: 12, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        case .image:
            Text(verbatim: strings.imageLabel)
                .font(LyricsFont.font(size: 12, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.8))
        case .files:
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: ClipboardRowPreview.fileTitle(item.filePaths ?? []))
                    .font(LyricsFont.font(size: 12, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: strings.itemCount(item.filePaths?.count ?? 0))
                    .font(LyricsFont.font(size: 9.5, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.42))
            }
        }
    }

    // MARK: 按鈕

    private var pinButton: some View {
        Button(action: onTogglePin) {
            Image(systemName: item.isPinned ? "pin.fill" : "pin")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(item.isPinned ? Color.orange : Color.white.opacity(0.6))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 釘選狀態常駐可見；未釘選時只有滑鼠停留／被選取才出現。
        .opacity(item.isPinned || showsControls ? 1 : 0)
        .help(item.isPinned ? strings.unpin : strings.pin)
        .accessibilityLabel(item.isPinned ? strings.unpin : strings.pin)
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "trash")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.6))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(showsControls ? 1 : 0)
        .help(strings.delete)
        .accessibilityLabel(strings.delete)
    }
}

// MARK: - 縮圖視圖

/// 圖片縮圖方塊：先查記憶體快取，沒有就在背景產生；視圖狀態只持有縮圖（≤ 96px），不持有原圖。
struct ClipboardThumbnailView: View {
    let url: URL?
    let cache: ClipboardThumbnailCache
    let size: CGFloat

    @State private var image: NSImage?

    init(url: URL?, cache: ClipboardThumbnailCache, size: CGFloat) {
        self.url = url
        self.cache = cache
        self.size = size
        _image = State(initialValue: url.flatMap { cache.cachedThumbnail(for: $0) })
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white.opacity(0.08))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.35))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .task(id: url) {
            guard let url else { image = nil; return }
            if let cached = cache.cachedThumbnail(for: url) { image = cached; return }
            image = await cache.thumbnail(for: url)
        }
    }
}

// MARK: - 檔案圖示

/// 以副檔名（UTType）取得系統圖示。不碰檔案系統（沙盒內讀不到的路徑也不影響），沒有副檔名就用一般文件圖示。
@MainActor
enum ClipboardFileIcon {
    private static var cache: [String: NSImage] = [:]

    static func image(forPath path: String) -> NSImage {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        if let hit = cache[ext] { return hit }
        let type = ext.isEmpty ? UTType.data : (UTType(filenameExtension: ext) ?? UTType.data)
        let icon = NSWorkspace.shared.icon(for: type)
        cache[ext] = icon
        return icon
    }
}
