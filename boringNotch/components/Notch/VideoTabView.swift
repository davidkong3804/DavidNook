//
//  VideoTabView.swift
//  DavidNook
//
//  展開瀏海的「影片」分頁：把 VideoCapsuleController（狀態與擷取）與 DavidNookUI 的 VideoPanelView（畫面）接在一起。
//  只做接線；沒有任何 log／print，不碰畫面內容。
//

import DavidNookCore
import DavidNookUI
import Defaults
import SwiftUI

struct VideoTabView: View {
    let layout: VideoCapsuleMetrics.Layout
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var controller = VideoCapsuleController.shared
    @Default(.videoCapsuleWidth) private var width
    @Default(.videoCapsulePinned) private var pinned

    private static let strings = VideoPanelStrings(
        emptyTitle: String(localized: "Watch a window in the notch", comment: "Video tab: title of the empty state before any window is picked."),
        emptyHint: String(localized: "Pick a window and its live picture shows here, scaled down. The picture stays in memory only, and is never saved or uploaded", comment: "Video tab: hint under the empty state; explains what happens and the privacy guarantee."),
        chooseWindow: String(localized: "Choose Window", comment: "Video tab: button that opens the system window picker."),
        choosingTitle: String(localized: "Pick a window in the system picker", comment: "Video tab: shown while the system window picker is open."),
        choosingHint: String(localized: "Only the one window you pick is shown. Press Esc to cancel", comment: "Video tab: hint while the system window picker is open."),
        changeWindow: String(localized: "Change Window", comment: "Video tab: toolbar button to pick a different window."),
        stop: String(localized: "Stop", comment: "Video tab: toolbar button that stops showing the window."),
        pin: String(localized: "Pin", comment: "Video tab: toolbar button that pins the video."),
        unpin: String(localized: "Unpin", comment: "Video tab: toolbar button that removes the pin."),
        pinHelp: String(localized: "Pin it to the collapsed notch (the collapsed capsule is not available yet)", comment: "Video tab: tooltip of the pin button."),
        widthLabel: { points in
            String(localized: "Width \(points) pt", comment: "Video tab: label above the width slider. Placeholder is the width in points.")
        },
        sourceClosedTitle: String(localized: "The window was closed", comment: "Video tab: shown when the picked window no longer exists."),
        sourceClosedHint: String(localized: "The window you picked is gone. Choose another window to continue", comment: "Video tab: hint when the picked window was closed."),
        blackTitle: String(localized: "This source is content-protected", comment: "Video tab: shown over a black picture that looks like protected (DRM) content."),
        blackHint: String(localized: "The system does not allow capturing it. Try the source's own picture-in-picture, or a source without protection such as YouTube or a local video", comment: "Video tab: explains protected content and what to try instead."),
        permissionTitle: String(localized: "Screen recording permission needed", comment: "Video tab: shown when macOS does not allow capturing."),
        permissionWhy: String(localized: "macOS is not allowing DavidNook to capture the picture. The picture is only scaled down in your Mac's memory, and is never saved or uploaded", comment: "Video tab: explains why permission is needed and the privacy guarantee."),
        permissionDetail: String(localized: "In System Settings → Privacy & Security → Screen & System Audio Recording, allow DavidNook, then reopen the app", comment: "Video tab: what to do about the missing permission."),
        openSettings: String(localized: "Open System Settings", comment: "Clipboard panel: button that opens System Settings."),
        errorTitle: String(localized: "Couldn't show the video", comment: "Video tab: title of a generic error."),
        pickerFailedHint: String(localized: "The system picker did not open. Please try again", comment: "Video tab: error hint when the system picker failed to open."),
        streamErrorHint: String(localized: "Capture was interrupted by the system. Choose the window again", comment: "Video tab: error hint when the system stopped the capture."),
        unknownErrorHint: String(localized: "Something unexpected happened. Choose the window again", comment: "Video tab: error hint for an unknown error.")
    )

    var body: some View {
        VideoPanelView(
            state: controller.state,
            layout: layout,
            strings: Self.strings,
            display: controller.display,
            width: width,
            isPinned: pinned,
            callbacks: VideoPanelCallbacks(
                onChoose: { controller.choose() },
                onStop: { controller.stop() },
                onTogglePin: { controller.togglePinned() },
                onWidthChange: { controller.setWidth($0) },
                onWidthCommit: { controller.commitWidth() },
                onOpenSettings: { controller.openSystemSettings() }
            )
        )
        .frame(maxHeight: .infinity)
        .onAppear { controller.tabDidAppear() }
        .onDisappear {
            vm.isPopoverActive = false
            controller.tabDidDisappear()
        }
        // 系統挑選器開著時，滑鼠移到挑選器上不要讓瀏海自動收合。
        .onChange(of: controller.state) { _, newState in
            vm.isPopoverActive = (newState == .choosing)
        }
    }
}
