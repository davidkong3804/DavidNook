//
//  NotchWindowManager.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//
//  Extracted from AppDelegate: all notch-window and per-screen view-model
//  lifecycle in one place. AppDelegate keeps app-lifecycle
//  glue (shortcuts, onboarding, termination) and forwards to this manager.
//

import Combine
import DavidNookUI
import Defaults
import SwiftUI

@MainActor
final class NotchWindowManager {
    /// All per-screen state in one value — replaces the parallel
    /// windows/viewModels dictionaries that previously had to be mutated
    /// in lockstep (a missed mutation leaked observers).
    struct ScreenContext {
        let viewModel: BoringViewModel
        var window: NSWindow?
    }

    private(set) var contexts: [String: ScreenContext] = [:] // UUID -> ScreenContext
    private(set) var primaryWindow: NSWindow?
    let primaryViewModel: BoringViewModel

    private(set) var isScreenLocked: Bool = false
    private var windowScreenDidChangeObserver: Any?
    private var previousScreens: [NSScreen]?

    /// 每個視窗跟著瀏海開／關調整大小的訂閱，以及「收合後延遲縮回」的待辦（以視窗為鍵）。
    private var windowSizeObservers: [ObjectIdentifier: AnyCancellable] = [:]
    private var pendingWindowShrinks: [ObjectIdentifier: DispatchWorkItem] = [:]

    init() {
        primaryViewModel = BoringViewModel()
    }

    // MARK: - Public lookups (preserve AppDelegate's old API shape)

    var windows: [String: NSWindow] {
        contexts.compactMapValues { $0.window }
    }

    var viewModels: [String: BoringViewModel] {
        contexts.mapValues { $0.viewModel }
    }

    var window: NSWindow? { primaryWindow }

    // MARK: - Screen lock / unlock

    func screenLocked() {
        isScreenLocked = true
        if !Defaults[.showOnLockScreen] {
            cleanupWindows()
        } else {
            enableSkyLightOnAllWindows()
        }
    }

    func screenUnlocked() {
        isScreenLocked = false
        if !Defaults[.showOnLockScreen] {
            adjustWindowPosition(changeAlpha: true)
        } else {
            disableSkyLightOnAllWindows()
        }
    }

    private func enableSkyLightOnAllWindows() {
        if Defaults[.showOnAllDisplays] {
            contexts.values.forEach { context in
                (context.window as? BoringNotchSkyLightWindow)?.enableSkyLight()
            }
        } else {
            (primaryWindow as? BoringNotchSkyLightWindow)?.enableSkyLight()
        }
    }

    private func disableSkyLightOnAllWindows() {
        // Delay disabling SkyLight to avoid flicker during unlock transition
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            await MainActor.run {
                if Defaults[.showOnAllDisplays] {
                    contexts.values.forEach { context in
                        (context.window as? BoringNotchSkyLightWindow)?.disableSkyLight()
                    }
                } else {
                    (primaryWindow as? BoringNotchSkyLightWindow)?.disableSkyLight()
                }
            }
        }
    }

    // MARK: - Window lifecycle

    func cleanupWindows(shouldInvert: Bool = false) {
        let shouldCleanupMulti = shouldInvert ? !Defaults[.showOnAllDisplays] : Defaults[.showOnAllDisplays]

        if shouldCleanupMulti {
            for (uuid, context) in contexts {
                context.window?.close()
                if let window = context.window {
                    forgetWindowSizeTracking(for: window)
                    NotchSpaceManager.shared.notchSpace.windows.remove(window)
                }
                contexts.removeValue(forKey: uuid)
            }
        } else {
            if let window = primaryWindow {
                window.close()
                forgetWindowSizeTracking(for: window)
                NotchSpaceManager.shared.notchSpace.windows.remove(window)
            }
            if let obs = windowScreenDidChangeObserver {
                NotificationCenter.default.removeObserver(obs)
                windowScreenDidChangeObserver = nil
            }
            primaryWindow = nil
        }
    }

    private func createBoringNotchWindow(for screen: NSScreen, with viewModel: BoringViewModel) -> NSWindow {
        // 視窗大小隨瀏海開／關改變（見 trackWindowSize）：關閉時與舊版相同（640×210），展開時涵蓋所有分頁與可調上限。
        let size = NotchSizing.windowSize(isOpen: viewModel.notchState == .open)
        let rect = NSRect(x: 0, y: 0, width: size.width, height: size.height)
        let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]

        let window = BoringNotchSkyLightWindow(contentRect: rect, styleMask: styleMask, backing: .buffered, defer: false)

        // Enable SkyLight only when screen is locked
        if isScreenLocked {
            window.enableSkyLight()
        } else {
            window.disableSkyLight()
        }

        let hostingView = NSHostingView(
            rootView: ContentView()
                .environmentObject(viewModel)
        )
        // 視窗大小完全由本類別決定；不讓 SwiftUI 內容的最小／最大尺寸去夾視窗（否則放大視窗會被內容的 frame 上限擋回去）。
        hostingView.sizingOptions = []
        window.contentView = hostingView

        window.orderFrontRegardless()
        NotchSpaceManager.shared.notchSpace.windows.insert(window)
        trackWindowSize(of: window, viewModel: viewModel)

        return window
    }

    // MARK: - Window size follows the notch state

    /// 展開時視窗放大到涵蓋尺寸（在 SwiftUI 開始動畫之前就先放大，形體不會被視窗邊緣切到）；
    /// 收合後等彈簧穩定（再多留一點餘裕）才縮回舊版大小。
    ///
    /// 為什麼不讓視窗一直是涵蓋尺寸：視窗是透明的，點擊能否穿透透明區域取決於 WindowServer 對 alpha 的處理，
    /// 專案裡沒有任何 `ignoresMouseEvents`／`hitTest` 保證；關閉狀態維持舊版 640×210，就不會比改版前多擋任何地方。
    private func trackWindowSize(of window: NSWindow, viewModel: BoringViewModel) {
        let key = ObjectIdentifier(window)
        windowSizeObservers[key] = viewModel.$notchState
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self, weak window, weak viewModel] state in
                // @Published 在設定值的當下同步送出（主執行緒），這裡不能再非同步跳一次，否則第一格動畫會先於視窗放大。
                MainActor.assumeIsolated {
                    guard let self, let window, let viewModel else { return }
                    self.windowSizeFollows(state, window: window, viewModel: viewModel)
                }
            }
    }

    private func windowSizeFollows(_ state: NotchState, window: NSWindow, viewModel: BoringViewModel) {
        let key = ObjectIdentifier(window)
        pendingWindowShrinks[key]?.cancel()
        pendingWindowShrinks[key] = nil

        switch state {
        case .open:
            setWindowSize(window, to: NotchSizing.windowSize(isOpen: true))
        case .closed:
            let delay = NotchMotion.current.closeSettleTime + 0.25
            let shrink = DispatchWorkItem { [weak self, weak window, weak viewModel] in
                MainActor.assumeIsolated {
                    guard let self, let window, let viewModel, viewModel.notchState == .closed else { return }
                    self.pendingWindowShrinks[ObjectIdentifier(window)] = nil
                    self.setWindowSize(window, to: NotchSizing.windowSize(isOpen: false))
                }
            }
            pendingWindowShrinks[key] = shrink
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: shrink)
        }
    }

    private func setWindowSize(_ window: NSWindow, to size: CGSize) {
        guard window.frame.size != size else { return }
        window.setFrame(NotchSizing.anchoredFrame(from: window.frame, to: size), display: false)
    }

    private func forgetWindowSizeTracking(for window: NSWindow) {
        let key = ObjectIdentifier(window)
        windowSizeObservers[key]?.cancel()
        windowSizeObservers[key] = nil
        pendingWindowShrinks[key]?.cancel()
        pendingWindowShrinks[key] = nil
    }

    private func positionWindow(_ window: NSWindow, on screen: NSScreen, changeAlpha: Bool = false) {
        if changeAlpha {
            window.alphaValue = 0
        }

        let screenFrame = screen.frame
        window.setFrameOrigin(
            NSPoint(
                x: screenFrame.origin.x + (screenFrame.width / 2) - window.frame.width / 2,
                y: screenFrame.origin.y + screenFrame.height - window.frame.height
            ))
        window.alphaValue = 1
    }

    func adjustWindowPosition(changeAlpha: Bool = false) {
        let coordinator = BoringViewCoordinator.shared
        if Defaults[.showOnAllDisplays] {
            let currentScreenUUIDs = Set(NSScreen.screens.compactMap { $0.displayUUID })

            // Remove windows for screens that no longer exist
            for uuid in contexts.keys where !currentScreenUUIDs.contains(uuid) {
                if let window = contexts[uuid]?.window {
                    window.close()
                    forgetWindowSizeTracking(for: window)
                    NotchSpaceManager.shared.notchSpace.windows.remove(window)
                }
                contexts.removeValue(forKey: uuid)
            }

            // Create or update windows for all screens
            for screen in NSScreen.screens {
                guard let uuid = screen.displayUUID else { continue }

                if contexts[uuid] == nil {
                    contexts[uuid] = ScreenContext(
                        viewModel: BoringViewModel(screenUUID: uuid),
                        window: nil
                    )
                }

                if contexts[uuid]?.window == nil {
                    let viewModel = contexts[uuid]!.viewModel
                    let window = createBoringNotchWindow(for: screen, with: viewModel)
                    contexts[uuid]?.window = window
                }

                if let window = contexts[uuid]?.window {
                    let viewModel = contexts[uuid]!.viewModel
                    positionWindow(window, on: screen, changeAlpha: changeAlpha)

                    if viewModel.notchState == .closed {
                        viewModel.close()
                    }
                }
            }
        } else {
            let selectedScreen: NSScreen

            if let preferredScreen = NSScreen.screen(withUUID: coordinator.preferredScreenUUID ?? "") {
                coordinator.selectedScreenUUID = coordinator.preferredScreenUUID ?? ""
                selectedScreen = preferredScreen
            } else if Defaults[.automaticallySwitchDisplay], let mainScreen = NSScreen.main,
                      let mainUUID = mainScreen.displayUUID {
                coordinator.selectedScreenUUID = mainUUID
                selectedScreen = mainScreen
            } else {
                if let window = primaryWindow {
                    window.alphaValue = 0
                }
                return
            }

            primaryViewModel.screenUUID = selectedScreen.displayUUID
            primaryViewModel.notchSize = getClosedNotchSize(screenUUID: selectedScreen.displayUUID)

            if primaryWindow == nil {
                primaryWindow = createBoringNotchWindow(for: selectedScreen, with: primaryViewModel)
            }

            if let window = primaryWindow {
                positionWindow(window, on: selectedScreen, changeAlpha: changeAlpha)

                if primaryViewModel.notchState == .closed {
                    primaryViewModel.close()
                }
            }
        }
    }

    func screenConfigurationDidChange() {
        let currentScreens = NSScreen.screens

        let screensChanged =
            currentScreens.count != previousScreens?.count
            || Set(currentScreens.compactMap { $0.displayUUID })
                != Set(previousScreens?.compactMap { $0.displayUUID } ?? [])
            || Set(currentScreens.map { $0.frame }) != Set(previousScreens?.map { $0.frame } ?? [])

        previousScreens = currentScreens

        if screensChanged {
            DispatchQueue.main.async { [weak self] in
                // Sync notch height with real value if mode is matchRealNotchSize
                syncNotchHeightIfNeeded()

                self?.cleanupWindows()
                self?.adjustWindowPosition()
            }
        }
    }

    func noteInitialScreens() {
        previousScreens = NSScreen.screens
    }

    // MARK: - Initial setup

    /// Creates the windows for the current configuration (previously inlined
    /// in applicationDidFinishLaunching).
    func prepareInitialWindows() {
        if !Defaults[.showOnAllDisplays] {
            let viewModel = primaryViewModel
            if let screen = NSScreen.main ?? NSScreen.screens.first {
                primaryWindow = createBoringNotchWindow(for: screen, with: viewModel)
            }
            adjustWindowPosition(changeAlpha: true)
        } else {
            adjustWindowPosition(changeAlpha: true)
        }

        noteInitialScreens()
    }

    func togglePopover(_ sender: Any?) {
        if primaryWindow?.isVisible == true {
            primaryWindow?.orderOut(nil)
        } else {
            primaryWindow?.orderFrontRegardless()
        }
    }

    func cleanup() {
        cleanupWindows()
    }
}
