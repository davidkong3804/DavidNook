//
//  ClipboardTabView.swift
//  DavidNook
//
//  展開瀏海的「剪貼簿」分頁：把 ClipboardService（資料）與 DavidNookUI 的 ClipboardPanelView（畫面）、
//  Core 的 ClipboardPanelModel（選取與鍵盤導覽邏輯）接在一起。這裡只做接線，沒有儲存或監看邏輯。
//
//  隱私：這個檔案沒有任何 log／print；不讀寫系統剪貼簿（寫回由 ClipboardService → Core 的 writeBack 負責）。
//

import AppKit
import Combine
import DavidNookCore
import DavidNookUI
import SwiftUI

// MARK: - 控制器

/// 持有面板的 `ClipboardPanelModel`，把服務的狀態灌進模型，並執行模型回報的動作。
@MainActor
final class ClipboardPanelController: ObservableObject {
    @Published private(set) var model: ClipboardPanelModel

    /// 縮圖快取（跨分頁切換共用；有張數與總成本上限）。
    static let thumbnails = ClipboardThumbnailCache()

    /// 收合瀏海（由視圖在出現時注入）。
    var closeNotch: () -> Void = {}

    private let service = ClipboardService.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        let service = ClipboardService.shared
        model = ClipboardPanelModel(items: service.items, isPaused: service.isPaused, needsPermission: service.needsPermission)
        service.$items
            .sink { [weak self] in self?.model.setItems($0) }
            .store(in: &cancellables)
        service.$isPaused
            .sink { [weak self] in self?.model.setPaused($0) }
            .store(in: &cancellables)
        service.$access
            .sink { [weak self] in self?.model.setNeedsPermission($0.needsPermission) }
            .store(in: &cancellables)
    }

    func setQuery(_ query: String) { model.setQuery(query) }
    func setFilter(_ filter: ClipboardTypeFilter) { model.setFilter(filter) }

    /// 處理鍵盤操作（↑↓ Home End Enter ⌘⌫ ⌘P Esc）。
    func handle(_ key: ClipboardPanelKey) {
        perform(model.handle(key))
    }

    func activate(id: UUID) {
        guard let item = model.allItems.first(where: { $0.id == id }) else { return }
        Task {
            // 寫回剪貼簿（Core 附自身標記，不會重複記錄）；成功後收合瀏海，並在已授權且使用者開啟時自動貼上。
            guard await service.paste(item) else { return }
            closeNotch()
            service.performAutoPasteIfEnabled()
        }
    }

    func togglePin(id: UUID) { service.togglePin(id: id) }
    func delete(id: UUID) { service.remove(id: id) }
    func togglePause() { service.togglePause() }
    func openPermissionSettings() { service.openPasteboardPrivacySettings() }

    func imageURL(for item: ClipboardItem) -> URL? { service.imageURL(for: item) }
    func appName(for bundleID: String?) -> String? { service.appName(forBundleID: bundleID) }

    private func perform(_ action: ClipboardPanelAction) {
        switch action {
        case .none: break
        case .paste(let id): activate(id: id)
        case .delete(let id): service.remove(id: id)
        case .togglePin(let id): service.togglePin(id: id)
        case .collapse: closeNotch()
        }
    }
}

// MARK: - 視圖

struct ClipboardTabView: View {
    @EnvironmentObject var vm: BoringViewModel
    @StateObject private var controller = ClipboardPanelController()

    private static let strings = ClipboardPanelStrings(
        searchPlaceholder: String(localized: "Search clipboard", comment: "Clipboard panel: placeholder of the search field."),
        filterAll: String(localized: "All", comment: "Clipboard panel: filter chip showing every kind of item."),
        filterText: String(localized: "Text", comment: "Clipboard panel: filter chip for text items."),
        filterImage: String(localized: "Images", comment: "Clipboard panel: filter chip for image items."),
        filterFiles: String(localized: "Files", comment: "Clipboard panel: filter chip for file items."),
        pauseHelp: String(localized: "Pause recording", comment: "Clipboard panel: tooltip of the pause button."),
        resumeHelp: String(localized: "Resume recording", comment: "Clipboard panel: tooltip of the resume button."),
        pin: String(localized: "Pin", comment: "Clipboard panel: pin an item so it is never evicted."),
        unpin: String(localized: "Unpin", comment: "Clipboard panel: remove the pin from an item."),
        delete: String(localized: "Delete", comment: "Clipboard panel: delete one item from the history."),
        imageLabel: String(localized: "Image", comment: "Clipboard panel: label of an image row."),
        itemCount: { count in
            String(localized: "\(count) items", comment: "Clipboard panel: number of files in a file row. Placeholder is the count.")
        },
        emptyHistory: String(localized: "Clipboard is empty", comment: "Clipboard panel: empty state when there is no history."),
        emptyHistoryHint: String(localized: "Text, images and files you copy will show up here", comment: "Clipboard panel: hint under the empty state."),
        noResults: String(localized: "No matching items", comment: "Clipboard panel: nothing matches the search or filter."),
        pausedTitle: String(localized: "Recording paused", comment: "Clipboard panel: banner shown while recording is paused."),
        pausedHint: String(localized: "Anything you copy while paused is not recorded afterwards", comment: "Clipboard panel: hint under the paused state."),
        resume: String(localized: "Resume", comment: "Clipboard panel: button that resumes recording."),
        permissionTitle: String(localized: "Paste permission needed", comment: "Clipboard panel: banner shown when macOS requires the user to allow pasting from other apps."),
        permissionDetail: String(localized: "In System Settings → Privacy & Security → Paste from Other Apps, set DavidNook to Allow", comment: "Clipboard panel: instructions under the permission banner."),
        openSettings: String(localized: "Open System Settings", comment: "Clipboard panel: button that opens System Settings.")
    )

    var body: some View {
        ClipboardPanelView(
            model: controller.model,
            strings: Self.strings,
            thumbnails: ClipboardPanelController.thumbnails,
            imageURL: { controller.imageURL(for: $0) },
            appName: { controller.appName(for: $0) },
            callbacks: ClipboardPanelCallbacks(
                onQueryChange: { controller.setQuery($0) },
                onFilterChange: { controller.setFilter($0) },
                onActivate: { controller.activate(id: $0) },
                onTogglePin: { controller.togglePin(id: $0) },
                onDelete: { controller.delete(id: $0) },
                onTogglePause: { controller.togglePause() },
                onOpenPermissionSettings: { controller.openPermissionSettings() }
            )
        )
        .frame(height: 128)
        .background(ClipboardKeyboardHost(viewModel: vm) { controller.handle($0) })
        .onAppear {
            controller.closeNotch = { vm.close() }
        }
    }
}

// MARK: - 鍵盤與焦點

/// 分頁顯示期間：讓瀏海視窗可成為 key window（搜尋欄才收得到輸入）、攔截面板的鍵盤操作，並在視窗為 key 時讓瀏海保持展開。
///
/// - 視窗平常不會成為 key window（點瀏海不會搶走其他 App 的焦點）；只有這個分頁在畫面上的期間才打開
///   `wantsKeyForTextInput`，離開分頁（切分頁、收合、換螢幕）時立刻還原。
/// - 以 `NSEvent` 區域監聽（只處理發給這個視窗的 keyDown）攔截 ↑↓ Home End Enter ⌘⌫ ⌘P Esc；
///   **輸入法組字中（`hasMarkedText`）一律放行**，所以用注音／拼音輸入搜尋字串時 Enter／Esc／方向鍵仍歸輸入法。
/// - 視窗是 key 時 `isPopoverActive = true`，滑鼠移出瀏海不會自動收合；視窗失去 key（使用者點了別處）才恢復。
struct ClipboardKeyboardHost: NSViewRepresentable {
    let viewModel: BoringViewModel
    let onKey: (ClipboardPanelKey) -> Void

    func makeNSView(context: Context) -> HostView {
        let view = HostView()
        view.viewModel = viewModel
        view.onKey = onKey
        return view
    }

    func updateNSView(_ view: HostView, context: Context) {
        view.viewModel = viewModel
        view.onKey = onKey
    }

    static func dismantleNSView(_ view: HostView, coordinator: ()) {
        view.teardown()
    }

    final class HostView: NSView {
        var viewModel: BoringViewModel?
        var onKey: ((ClipboardPanelKey) -> Void)?
        private var monitor: Any?
        private var observers: [NSObjectProtocol] = []
        private weak var attachedWindow: BoringNotchSkyLightWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            teardown()
            guard let window = window as? BoringNotchSkyLightWindow else { return }
            attach(to: window)
        }

        private func attach(to window: BoringNotchSkyLightWindow) {
            attachedWindow = window
            window.wantsKeyForTextInput = true

            let center = NotificationCenter.default
            observers = [
                center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.viewModel?.isPopoverActive = true }
                },
                center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.viewModel?.isPopoverActive = false }
                },
            ]
            if window.isKeyWindow { viewModel?.isPopoverActive = true }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
                guard let self, let window, event.window === window else { return event }
                // 輸入法組字中：方向鍵、Enter、Esc 都屬於輸入法，不攔截。
                if let editor = window.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
                guard let key = ClipboardKeyMapping.key(for: event) else { return event }
                self.onKey?(key)
                return nil
            }
        }

        func teardown() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers = []
            if let window = attachedWindow {
                window.wantsKeyForTextInput = false
                viewModel?.isPopoverActive = false
            }
            attachedWindow = nil
        }
    }
}
