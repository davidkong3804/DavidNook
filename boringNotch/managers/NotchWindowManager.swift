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
                    NotchSpaceManager.shared.notchSpace.windows.remove(window)
                }
                contexts.removeValue(forKey: uuid)
            }
        } else {
            if let window = primaryWindow {
                window.close()
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
        // 視窗大小固定為涵蓋尺寸（涵蓋所有分頁與可調上限）。不要在開／關時改視窗大小：
        // 實測（2026-10-06）在 SwiftUI 動畫進行中 setFrame 會讓 NSHostingView 陷入版面更新迴圈而閃退
        // （NSWindow _postWindowNeedsUpdateConstraints 丟例外；有縮放時 3/3 崩潰，關掉後 3/3 正常）。
        let size = NotchSizing.windowSize(isOpen: true)
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

        return window
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
