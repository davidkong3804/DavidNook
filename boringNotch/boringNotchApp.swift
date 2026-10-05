//
//  boringNotchApp.swift
//  boringNotchApp
//
//  Created by Harsh Vardhan  Goswami  on 02/08/24.
//

import Defaults
import KeyboardShortcuts
import SwiftUI

@main
struct DynamicNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Default(.menubarIcon) var showMenuBarIcon
    @Environment(\.openWindow) var openWindow

    var body: some Scene {
        MenuBarExtra("DavidNook", systemImage: "rectangle.topthird.inset.filled", isInserted: $showMenuBarIcon) {
            Button("Settings") {
                DispatchQueue.main.async {
                    SettingsWindowController.shared.showWindow()
                }
            }
            .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
            Button("Restart DavidNook") {
                ApplicationRelauncher.restart()
            }
            Button("Quit", role: .destructive) {
                NSApplication.shared.terminate(self)
            }
            .keyboardShortcut(KeyEquivalent("Q"), modifiers: .command)
        }
    }
}

/// App-lifecycle glue: shortcuts, onboarding, termination, observer wiring.
/// All notch-window / per-screen view-model / drag-detector lifecycle lives
/// in `NotchWindowManager` (see managers/NotchWindowManager.swift).
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    var closeNotchTask: Task<Void, Never>?
    private lazy var windowManager = NotchWindowManager()
    private var onboardingWindowController: NSWindowController?
    private var screenLockedObserver: Any?
    private var screenUnlockedObserver: Any?
    private var observers: [Any] = []
    private var terminationSignalSource: DispatchSourceSignal?

    /// Kept for existing internal readers; the state itself moved to the manager.
    var windows: [String: NSWindow] { windowManager.windows }
    var viewModels: [String: BoringViewModel] { windowManager.viewModels }
    var window: NSWindow? { windowManager.window }
    var vm: BoringViewModel { windowManager.primaryViewModel }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        if let observer = screenLockedObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            screenLockedObserver = nil
        }
        if let observer = screenUnlockedObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            screenUnlockedObserver = nil
        }
        MainActor.assumeIsolated {
            MusicManager.shared.destroy()
            ClipboardService.shared.stop()
            windowManager.cleanup()
        }

        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    @MainActor
    func onScreenLocked(_ notification: Notification) {
        windowManager.screenLocked()
    }

    @MainActor
    func onScreenUnlocked(_ notification: Notification) {
        windowManager.screenUnlocked()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
#if DEBUG
        // 僅 Debug：`-davidnookSnapshot YES` 時只離屏渲染畫面成 PNG 並結束（見 SnapshotHarness.swift）。
        if SnapshotHarness.isRequested {
            Task { @MainActor in SnapshotHarness.runAndTerminate(into: SnapshotHarness.outputDirectory) }
            return
        }
#endif
        // SIGTERM（例如 pkill、關機）預設不會走 applicationWillTerminate，adapter 的 perl 子行程會變成孤兒
        // 一直活著；改成走正常的終止流程（MusicManager.destroy 會關掉子行程）。
        signal(SIGTERM, SIG_IGN)
        let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        termination.setEventHandler { NSApplication.shared.terminate(nil) }
        termination.resume()
        terminationSignalSource = termination

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name.selectedScreenChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.windowManager.adjustWindowPosition(changeAlpha: true)
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name.notchHeightChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.windowManager.adjustWindowPosition()
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name.automaticallySwitchDisplayChanged, object: nil, queue: nil
        ) { [weak self] _ in
            guard let self = self, let window = self.window else { return }
            Task { @MainActor in
                window.alphaValue = self.coordinator.selectedScreenUUID == self.coordinator.preferredScreenUUID ? 1 : 0
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name.showOnAllDisplaysChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.windowManager.cleanupWindows(shouldInvert: true)
                self.windowManager.adjustWindowPosition(changeAlpha: true)
            }
        })

        // Use closure-based observers for DistributedNotificationCenter and keep tokens for removal
        screenLockedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(rawValue: "com.apple.screenIsLocked"),
            object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    self?.onScreenLocked(notification)
                }
        }

        screenUnlockedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(rawValue: "com.apple.screenIsUnlocked"),
            object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    self?.onScreenUnlocked(notification)
                }
        }

        KeyboardShortcuts.onKeyDown(for: .toggleSneakPeek) { [weak self] in
            guard let self = self else { return }
            if Defaults[.sneakPeekStyles] == .inline {
                let newStatus = !self.coordinator.expandingView.show
                self.coordinator.toggleExpandingView(status: newStatus, type: .music)
                KeyboardShortcuts.onKeyUp(for: .toggleSneakPeek) {
                    self.coordinator.toggleSneakPeek(
                        status: !self.coordinator.isAnySneakPeekShowing,
                        type: .music
                    )
                }
            } else {
                self.coordinator.toggleSneakPeek(
                    status: !self.coordinator.isAnySneakPeekShowing,
                    type: .music,
                    duration: 3.0
                )
            }
        }

        KeyboardShortcuts.onKeyDown(for: .toggleNotchOpen) { [weak self] in
            Task { [weak self] in
                guard let self = self else { return }

                let mouseLocation = NSEvent.mouseLocation

                var viewModel = self.vm

                if Defaults[.showOnAllDisplays] {
                    for screen in NSScreen.screens {
                        if screen.frame.contains(mouseLocation) {
                            if let uuid = screen.displayUUID, let screenViewModel = self.viewModels[uuid] {
                                viewModel = screenViewModel
                                break
                            }
                        }
                    }
                }

                self.closeNotchTask?.cancel()
                self.closeNotchTask = nil

                switch viewModel.notchState {
                case .closed:
                    var didOpen = false
                    await MainActor.run {
                        didOpen = viewModel.open()
                    }
                    guard didOpen else { return }

                    let task = Task { [weak viewModel] in
                        do {
                            try await Task.sleep(for: .seconds(3))
                            await MainActor.run {
                                viewModel?.close()
                            }
                        } catch { }
                    }
                    self.closeNotchTask = task
                case .open:
                    await MainActor.run {
                        viewModel.close()
                    }
                }
            }
        }

        KeyboardShortcuts.onKeyDown(for: .openClipboard) { [weak self] in
            Task { @MainActor [weak self] in
                self?.showClipboardTab()
            }
        }

        // 剪貼簿歷史：依設定開始監看（輪詢 changeCount；暫停、關閉或系統需要使用者先授權時不讀內容）。
        ClipboardService.shared.start()

        // Sync notch height with real value on app launch if mode is matchRealNotchSize
        syncNotchHeightIfNeeded()

        windowManager.prepareInitialWindows()

        if coordinator.firstLaunch {
            DispatchQueue.main.async {
                self.showOnboardingWindow()
            }
        }
    }

    /// 「開啟剪貼簿」快捷鍵：展開瀏海並切到剪貼簿分頁；已經在剪貼簿分頁就收合（與 toggleNotchOpen 一樣是開關）。
    /// 精簡模式（compactMode）沒有分頁列，看不到剪貼簿，這個快捷鍵在精簡模式下不做事。
    @MainActor
    private func showClipboardTab() {
        guard !Defaults[.compactMode] else { return }
        let mouseLocation = NSEvent.mouseLocation
        var viewModel = self.vm
        if Defaults[.showOnAllDisplays] {
            for screen in NSScreen.screens where screen.frame.contains(mouseLocation) {
                if let uuid = screen.displayUUID, let screenViewModel = self.viewModels[uuid] {
                    viewModel = screenViewModel
                    break
                }
            }
        }

        closeNotchTask?.cancel()
        closeNotchTask = nil

        if viewModel.notchState == .open, coordinator.currentView == .clipboard {
            viewModel.close()
            return
        }
        coordinator.currentView = .clipboard
        if viewModel.notchState == .closed {
            // 打開失敗（例如首次啟動的歡迎動畫）就還原分頁。
            if !viewModel.open() { coordinator.currentView = .home }
        }
    }

    @objc func screenConfigurationDidChange() {
        windowManager.screenConfigurationDidChange()
    }

    @objc func togglePopover(_ sender: Any?) {
        if window?.isVisible == true {
            window?.orderOut(nil)
        } else {
            window?.orderFrontRegardless()
        }
    }

    @objc func showMenu() {
        statusItem?.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc func quitAction() {
        NSApplication.shared.terminate(self)
    }

    private func showOnboardingWindow(step: OnboardingStep = .welcome) {
        let isNewWindow = onboardingWindowController == nil
        if isNewWindow {
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: OnboardingView.windowSize),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = String(localized: "Welcome to DavidNook", comment: "Accessibility title of the first-launch window (the title bar is hidden).")
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.level = .floating
            window.alphaValue = 0 // 彈出時淡入（見下方）；內容的彈性進場在 OnboardingView 內
            window.contentView = NSHostingView(
                rootView: OnboardingView(
                    step: step,
                    onFinish: {
                        window.orderOut(nil)
//                        NSApp.setActivationPolicy(.accessory)
                        window.close()
                        NSApp.deactivate()
                    },
                    onOpenSettings: {
                        window.close()
                        SettingsWindowController.shared.showWindow()
                    }
                ))
            window.isRestorable = false
            window.identifier = NSUserInterfaceItemIdentifier("OnboardingWindow")

            onboardingWindowController = NSWindowController(window: window)
        }

//        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindowController?.window?.level = .floating
        onboardingWindowController?.window?.makeKeyAndOrderFront(nil)
        onboardingWindowController?.window?.orderFrontRegardless()
        if isNewWindow, let window = onboardingWindowController?.window {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1
            }
        }
    }
}
