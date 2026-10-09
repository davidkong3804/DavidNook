//
//  FloatingVideoWindowController.swift
//  DavidNook
//
//  桌面浮動視窗（自由的畫中畫）：一個無邊框、不搶焦點的 NSPanel，顯示與封面槽、收合膠囊同一份即時畫面
//  （共用 `VideoFrameDisplay`，不另開 SCStream；有裁切就是裁切後的畫面）。
//  這是一般桌面視窗，**不是瀏海視窗**——瀏海視窗仍絕不 setFrame。內容是純 AppKit（`FloatingVideoView`），沒有 NSHostingView。
//  隱私：只記位置與寬度（三個數字）與透明度；不存任何內容或標題；畫面不存檔不上傳。
//

import AppKit
import DavidNookCore
import DavidNookUI
import Defaults

@MainActor
final class FloatingVideoWindowController {
    private let panel: FloatingVideoPanel
    private let view: FloatingVideoView
    private var aspectRatio: Double

    /// 取消釘選（✕、雙擊、右鍵選單）。
    var onUnpin: (() -> Void)?
    /// 視窗大小或所在螢幕的 scale 改變（拖曳縮放中會連續呼叫；由接收端節流）。
    var onSizeChange: (() -> Void)?
    private var observers: [NSObjectProtocol] = []

    /// 視窗寬（pt）與所在螢幕的 backingScaleFactor：擷取輸出尺寸依此決定。
    var widthPoints: Double { Double(panel.frame.width) }
    var backingScale: Double { Double(panel.backingScaleFactor) }

    /// `defaultWidth`：第一次釘選（沒有記住的位置與大小）時的寬度＝設定頁的「釘選視窗的預設大小」。
    init(display: VideoFrameDisplay, aspectRatio: Double, defaultWidth: Double) {
        self.aspectRatio = aspectRatio
        let screens = NSScreen.screens.map(\.visibleFrame)
        // 第一次出現在有瀏海（或選單列）的螢幕、瀏海正下方置中；沒有瀏海的螢幕取主螢幕。
        let primary = (NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first ?? NSScreen.main)?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let saved = Defaults[.videoFloatingPlacement].flatMap { try? JSONDecoder().decode(FloatingVideoPlacement.self, from: $0) }
        let frame = FloatingVideoGeometry.restoredFrame(saved: saved, aspectRatio: aspectRatio, screens: screens, primary: primary, defaultWidth: defaultWidth)
        panel = FloatingVideoPanel(contentRect: frame)
        view = FloatingVideoView(display: display, strings: Self.strings)
        view.aspectRatio = aspectRatio
        view.frame = CGRect(origin: .zero, size: frame.size)
        view.visibleFrameProvider = { [weak panel] in
            panel?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        }
        panel.contentView = view

        let opacity = FloatingVideoOpacity.clamped(Defaults[.videoFloatingOpacity])
        panel.alphaValue = CGFloat(opacity)
        view.setOpacity(opacity)

        view.onUnpin = { [weak self] in self?.onUnpin?() }
        view.onOpacityChange = { [weak self] value in self?.setOpacity(value) }
        view.onInteractionEnd = { [weak self] _ in self?.savePlacement() }

        for name in [NSWindow.didResizeNotification, NSWindow.didChangeBackingPropertiesNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onSizeChange?() }
            })
        }
    }

    func show() {
        panel.orderFrontRegardless()   // 不啟用 App、不搶焦點
    }

    func setContent(_ content: FloatingVideoView.Content) { view.content = content }

    /// 畫面比例改變（裁切、來源視窗被縮放）：寬度不變、左上角不動，高度跟著變。
    func setAspectRatio(_ ratio: Double) {
        guard ratio.isFinite, ratio > 0, abs(ratio - aspectRatio) > 0.001 else { return }
        aspectRatio = ratio
        view.aspectRatio = ratio
        let visible = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? panel.frame
        let next = FloatingVideoGeometry.adjustedForAspect(frame: panel.frame, aspectRatio: ratio, in: visible)
        if next != panel.frame { panel.setFrame(next, display: true) }
        savePlacement()
    }

    func close() {
        savePlacement()
        view.onUnpin = {}; view.onOpacityChange = { _ in }; view.onInteractionEnd = { _ in }
        onSizeChange = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        panel.orderOut(nil)
        panel.close()
    }

    private func setOpacity(_ value: Double) {
        let v = FloatingVideoOpacity.clamped(value)
        panel.alphaValue = CGFloat(v)
        view.setOpacity(v)
        Defaults[.videoFloatingOpacity] = v
    }

    /// 只存左下角座標與寬度。
    private func savePlacement() {
        Defaults[.videoFloatingPlacement] = try? JSONEncoder().encode(FloatingVideoPlacement(frame: panel.frame))
    }

    private static var strings: FloatingVideoStrings {
        FloatingVideoStrings(
            unpin: String(localized: "Unpin", comment: "Floating video window: tooltip of the x button, menu item and double-click action that unpin the video."),
            opacity: String(localized: "Opacity", comment: "Floating video window: tooltip of the button (and menu title) that changes the window opacity."),
            protectedTitle: String(localized: "This source is content-protected", comment: "Video tab: shown over a black picture that looks like protected (DRM) content."),
            protectedHint: String(localized: "The system does not allow capturing it. Try the source's own picture-in-picture, or an unprotected source such as YouTube", comment: "Album art slot: explains protected content and what to try instead."),
            reconnecting: String(localized: "Reconnecting…", comment: "Floating video window: shown while the picture stopped coming in and the capture is being restarted."),
            stalledTitle: String(localized: "No picture is coming in", comment: "Floating video window: title of the error shown when the picture did not come back after a restart."),
            stalledHint: String(localized: "Unpin and pin the video again, or choose the window again.", comment: "Floating video window: hint under the no-picture error.")
        )
    }
}
