//
//  VideoCapsuleController.swift
//  DavidNook
//
//  影片功能的接線：把擷取來源（ScreenCaptureKitVideoSource）的事件灌進 Core 的狀態機，並提供給 SwiftUI。
//  沒有擷取邏輯、沒有儲存；隱私規則見 ScreenCaptureKitVideoSource。
//

import AppKit
import DavidNookCore
import DavidNookUI
import Defaults
import Foundation
import OSLog

@MainActor
final class VideoCapsuleController: ObservableObject {
    static let shared = VideoCapsuleController()

    @Published private(set) var state: VideoCapsuleState = .idle

    let display = VideoFrameDisplay()
    private let source: ScreenCaptureKitVideoSource
    private var machine = VideoCapsuleStateMachine()
    private var isSlotVisible = false
    private var eventTask: Task<Void, Never>?
    private let log = Logger(subsystem: "io.github.davidkong3804.DavidNook", category: "video")

    private init() {
        Defaults[.videoCapsulePinned] = false
        source = ScreenCaptureKitVideoSource(display: display)
        source.updateRequestedWidth(Defaults[.videoCapsuleWidth])
        let events = source.events
        eventTask = Task { [weak self] in
            for await event in events {
                self?.apply(.source(event))
            }
        }
    }

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private func apply(_ input: VideoCapsuleInput) {
        let before = state
        machine.handle(input, at: now)
        state = machine.state
        // 釘選狀態只在執行期有意義（沒有串流就沒有膠囊），所以每次變化就同步到 Defaults，App 啟動時重設為 false（見 init）。
        if Defaults[.videoCapsulePinned] != machine.isPinned { Defaults[.videoCapsulePinned] = machine.isPinned }
        if before != state { log.info("state \(String(describing: self.state), privacy: .public)") }
        switch state {
        case .idle, .sourceClosed, .error: display.clear()
        case .choosing, .streaming, .blackContent: break
        }
        // 挑選器開著時瀏海可能已收合（瀏海收合）；挑完才開始的串流不能在不可見時跑。
        if case .source(.started) = input, !isSlotVisible { source.pause() }
    }

    // MARK: 使用者操作

    func choose() {
        apply(.requestPicker)
        source.start()
    }

    /// 停止擷取並回到專輯封面（也會取消釘選）。
    func stop() {
        apply(.userStopped)
        source.stop()
    }

    /// 點一下影片：釘選／取消釘選（釘成瀏海外面的影片膠囊；膠囊本身是 M-C，這裡只有狀態）。
    func togglePin() {
        apply(.togglePin)
    }

    /// 設定頁的影片寬度：只作用於 M-C 的收合膠囊，以及 Home 封面槽加寬後的上限。
    func commitWidth() { source.updateRequestedWidth(Defaults[.videoCapsuleWidth]) }

    /// 封面槽要用的長寬比（nil＝顯示專輯封面）；功能關閉時一律 nil。
    var slotAspectRatio: Double? {
        Defaults[.videoCapsuleEnabled] ? state.slotAspectRatio : nil
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: 封面槽可見性（不可見就停止串流以省電；已選的視窗保留）

    func slotDidAppear() {
        isSlotVisible = true
        if state.needsSource { source.resume() }
    }

    func slotDidDisappear() {
        isSlotVisible = false
        // M-C：已釘選時，收合膠囊需要串流繼續，屆時在這裡依 machine.isPinned 保留；M-B 只有釘選狀態，沒有膠囊可看，一律暫停。
        source.pause()
    }
}
