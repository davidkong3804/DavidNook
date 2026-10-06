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
        reconcileStreaming()
    }

    /// 同一條串流供封面槽與釘選膠囊共用：槽在畫面上要串流；槽不可見時，已釘選就持續串流（給收合膠囊），未釘選才 pause。
    /// 規則在 Core 的 `VideoStreamPolicy`（有測試）。`pause()`／`resume()` 都是冪等的，重複呼叫無害。
    /// 這也涵蓋「挑選器開著時瀏海已收合、挑完才開始的串流」以及「釘選期間偵測到黑畫面而自動取消釘選」。
    private func reconcileStreaming() {
        guard state.needsSource else { return }
        if VideoStreamPolicy.shouldPause(isSlotVisible: isSlotVisible, isPinned: machine.isPinned) {
            source.pause()
        } else {
            source.resume()
        }
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

    /// 點一下影片：釘選／取消釘選（釘成收合瀏海外面的影片膠囊，見 `VideoCapsuleHost`）。
    func togglePin() {
        apply(.togglePin)
    }

    /// 設定頁的「影片大小」：決定 Home 封面槽加寬後的上限，以及釘選膠囊的大小。
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
        reconcileStreaming()
    }

    func slotDidDisappear() {
        isSlotVisible = false
        // 已釘選：收合膠囊需要串流繼續，不 pause；未釘選才 pause（見 VideoStreamPolicy）。
        reconcileStreaming()
    }
}
