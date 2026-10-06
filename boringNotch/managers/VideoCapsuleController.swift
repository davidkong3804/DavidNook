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
    private var isTabVisible = false
    private var eventTask: Task<Void, Never>?
    private let log = Logger(subsystem: "io.github.davidkong3804.DavidNook", category: "video")

    private init() {
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
        if before != state { log.info("state \(String(describing: self.state), privacy: .public)") }
        switch state {
        case .idle, .sourceClosed, .error: display.clear()
        case .choosing, .streaming, .blackContent: break
        }
        // 挑選器開著時分頁可能已離開畫面（瀏海收合）；挑完才開始的串流不能在不可見時跑。
        if case .source(.started) = input, !isTabVisible { source.pause() }
    }

    // MARK: 使用者操作

    func choose() {
        apply(.requestPicker)
        source.start()
    }

    func stop() {
        apply(.userStopped)
        source.stop()
    }

    func setWidth(_ value: Double) {
        Defaults[.videoCapsuleWidth] = VideoCapsuleSettings.clampedWidth(value)
    }

    /// 滑桿放開才更新擷取解析度（拖動中只改顯示尺寸）。
    func commitWidth() { source.updateRequestedWidth(Defaults[.videoCapsuleWidth]) }

    /// 目前來源的長寬比（沒有串流時用 16:9）。
    var aspectRatio: Double {
        switch state {
        case .streaming(let r), .blackContent(let r): return r
        default: return VideoCapsuleStateMachine.fallbackAspectRatio
        }
    }

    func togglePinned() { Defaults[.videoCapsulePinned].toggle() }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: 分頁可見性（不可見就停止串流以省電；已選的視窗保留）

    func tabDidAppear() {
        isTabVisible = true
        if state.needsSource { source.resume() }
    }

    func tabDidDisappear() {
        isTabVisible = false
        // M-C 的釘選膠囊會在這裡保留串流；M-B 只存釘選狀態。
        source.pause()
    }
}
