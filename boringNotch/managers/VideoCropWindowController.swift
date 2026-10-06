//
//  VideoCropWindowController.swift
//  DavidNook
//
//  裁切視窗：一個獨立的一般 NSWindow（不是瀏海視窗；從不對瀏海視窗 setFrame），建立時就定好大小，之後不改。
//  顯示來源視窗目前的畫面（與封面槽同一條串流的最新幀，不另開 SCStream），讓使用者拖曳框選要保留的區域。
//  畫面只在記憶體；不存檔、不上傳、不截圖。
//

import AppKit
import DavidNookCore
import DavidNookUI
import SwiftUI

@MainActor
final class VideoCropWindowController: NSObject, NSWindowDelegate {
    let model: VideoCropEditorModel
    private var window: NSWindow?
    private var finished = false
    /// 視窗被關閉（含按左上角關閉鈕）時呼叫一次：`true`＝確定、`false`＝取消。
    var onFinish: ((Bool) -> Void)?

    init(model: VideoCropEditorModel, display: VideoFrameDisplay, windowAspectRatio: Double) {
        self.model = model
        super.init()
        let size = VideoCropEditorLayout.windowContentSize(windowAspectRatio: windowAspectRatio)
        let root = VideoCropEditorView(model: model, display: display, strings: Self.strings, windowAspectRatio: windowAspectRatio)
            .frame(width: size.width, height: size.height)
        let hosting = NSHostingView(rootView: root)
        // 視窗大小由我們在建立時決定；不讓 SwiftUI 內容去協商視窗大小（避免版面更新迴圈）。
        hosting.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.title = String(localized: "Crop Video", comment: "Title of the window where you drag a rectangle to choose which part of the picked window to show.")
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.level = .floating
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.delegate = self
        window.center()
        self.window = window
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// 由控制器呼叫：關閉視窗並回報結果（只回報一次）。
    func close(applied: Bool) {
        guard !finished else { return }
        finished = true
        window?.delegate = nil
        window?.orderOut(nil)
        window?.close()
        window = nil
        onFinish?(applied)
    }

    func windowWillClose(_ notification: Notification) {
        // 按左上角關閉鈕＝取消。
        guard !finished else { return }
        finished = true
        window?.delegate = nil
        window = nil
        onFinish?(false)
    }

    private static var strings: VideoCropEditorStrings {
        VideoCropEditorStrings(
            hint: String(localized: "Drag to choose the area to keep. Drag a corner or edge to adjust.", comment: "Crop window: instruction under the picture."),
            autoDetect: String(localized: "Auto-detect", comment: "Crop window: button that finds the video area automatically."),
            detecting: String(localized: "Detecting… (about 3 seconds)", comment: "Crop window: shown while auto-detect is watching the picture."),
            notFound: String(localized: "No clear video area found. Drag to choose it by hand.", comment: "Crop window: shown when auto-detect could not find a video area."),
            resetToFullWindow: String(localized: "Reset to Whole Window", comment: "Crop window: button that removes the crop and uses the whole window."),
            confirm: String(localized: "OK", comment: "Crop window: confirm button."),
            cancel: String(localized: "Cancel", comment: "Crop window: cancel button.")
        )
    }
}
