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
    /// 目前的裁切（正規化；nil＝整個視窗）。給封面槽決定要不要顯示「重設裁切」。
    @Published private(set) var crop: NormalizedCropRect?
    /// 目前的釘選樣式（無／收合膠囊／桌面浮動視窗；同一時間只會有一種，規則在 Core 的狀態機）。
    @Published private(set) var pinStyle: VideoPinStyle = .none

    let display = VideoFrameDisplay()
    private let source: ScreenCaptureKitVideoSource
    private var machine = VideoCapsuleStateMachine()
    private var isSlotVisible = false
    private var cropWindow: VideoCropWindowController?
    private var floatingWindow: FloatingVideoWindowController?
    private var isCropEditing: Bool { cropWindow != nil }
    private var eventTask: Task<Void, Never>?
    private let log = Logger(subsystem: "io.github.davidkong3804.DavidNook", category: "video")

    private init() {
        Defaults[.videoCapsulePinned] = false
        source = ScreenCaptureKitVideoSource(display: display)
        source.updateRequestedWidth(Defaults[.videoCapsuleWidth])
        // 新挑選視窗時，依來源 App 的 bundle id 取回記住的裁切（記憶只含 bundle id 與矩形）。
        source.cropResolver = { bundleID in VideoCropStore.load().rect(for: bundleID) }
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
        if pinStyle != machine.pinStyle { pinStyle = machine.pinStyle }
        switch state {
        case .idle, .sourceClosed, .error: display.clear()
        case .choosing, .streaming, .blackContent: break
        }
        // 串流結束（沒有畫面可裁）→ 關掉裁切視窗；裁切狀態與來源同步。
        if !state.needsSource {
            closeCropWindow(applied: false)
            if crop != nil { crop = nil }
        } else if case .source(let event) = input {
            switch event {
            case .started, .cropChanged: if crop != source.crop { crop = source.crop }
            default: break
            }
        }
        syncFloatingWindow()
        reconcileStreaming()
    }

    /// 依 Core 的 `FloatingVideoPolicy` 開／關／更新桌面浮動視窗：串流結束一律關；黑畫面維持並在視窗內顯示說明。
    private func syncFloatingWindow() {
        switch FloatingVideoPolicy.content(style: machine.pinStyle, state: state) {
        case .hidden:
            // 換視窗（系統挑選器開著）期間狀態機維持浮動樣式，視窗留著不閃；取消或選好後繼續使用。
            if case .choosing = state, machine.isFloating { return }
            closeFloatingWindow()
        case .live, .protectedNotice:
            let ratio = state.slotAspectRatio ?? VideoCapsuleStateMachine.fallbackAspectRatio
            if let floatingWindow {
                floatingWindow.setAspectRatio(ratio)
            } else {
                let window = FloatingVideoWindowController(display: display, aspectRatio: ratio)
                window.onClose = { [weak self] in self?.closeFloating() }
                window.onReturnToNotch = { [weak self] in self?.closeFloating() }
                window.onPinToNotch = { [weak self] in self?.pinFloatingToCapsule() }
                floatingWindow = window
                window.show()
            }
            floatingWindow?.setContent(FloatingVideoPolicy.content(style: machine.pinStyle, state: state) == .live ? .live : .protectedNotice)
        }
    }

    private func closeFloatingWindow() {
        floatingWindow?.close()
        floatingWindow = nil
    }

    /// 同一條串流供封面槽與釘選膠囊共用：槽在畫面上要串流；槽不可見時，已釘選就持續串流（給收合膠囊），未釘選才 pause。
    /// 規則在 Core 的 `VideoStreamPolicy`（有測試）。`pause()`／`resume()` 都是冪等的，重複呼叫無害。
    /// 這也涵蓋「挑選器開著時瀏海已收合、挑完才開始的串流」以及「釘選期間偵測到黑畫面而自動取消釘選」。
    private func reconcileStreaming() {
        guard state.needsSource else { return }
        // 裁切視窗開著時瀏海可能已收合（滑鼠移到裁切視窗）；編輯期間要繼續串流。
        if VideoStreamPolicy.shouldPause(isSlotVisible: isSlotVisible || isCropEditing, isPinned: machine.isPinned, isFloating: machine.isFloating) {
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
        closeCropWindow(applied: false)
        apply(.userStopped)
        source.stop()
    }

    /// 點一下影片：釘選／取消釘選（釘成收合瀏海外面的影片膠囊，見 `VideoCapsuleHost`）。
    func togglePin() {
        apply(.togglePin)
    }

    /// 封面槽的浮動視窗按鈕：沒開就開桌面浮動視窗（收合膠囊同時隱藏）；已開就收回。
    func toggleFloating() {
        apply(machine.isFloating ? .closeFloating : .openFloating)
    }

    /// 關閉浮動視窗（✕、收回瀏海、雙擊都是這個）：影片回到展開瀏海的封面槽；串流依 pause 規則（槽不可見且沒釘就 pause，已選視窗保留）。
    func closeFloating() {
        apply(.closeFloating)
    }

    /// 浮動視窗的「釘選到瀏海」：改成收合膠囊樣式（浮動視窗關閉）。
    func pinFloatingToCapsule() {
        apply(.pinToCapsule)
    }

    /// 設定頁的「影片大小」：決定 Home 封面槽加寬後的上限，以及釘選膠囊的大小。
    func commitWidth() { source.updateRequestedWidth(Defaults[.videoCapsuleWidth]) }

    // MARK: 裁切

    /// 開裁切視窗（獨立的一般視窗，不是瀏海視窗）。只在串流中可用。
    func openCropEditor() {
        if let cropWindow { cropWindow.show(); return }
        guard case .streaming = state else { return }
        let model = VideoCropEditorModel(selection: crop)
        let window = VideoCropWindowController(model: model, display: display, windowAspectRatio: source.windowAspectRatio)
        cropWindow = window
        model.onConfirm = { [weak self] in self?.closeCropWindow(applied: true) }
        model.onCancel = { [weak self] in self?.closeCropWindow(applied: false) }
        model.onAutoDetect = { [weak self, weak model] in
            guard let self, let model, !model.isDetecting else { return }
            Task { @MainActor in
                model.isDetecting = true
                model.detectionFailed = false
                // 串流約 3 秒、取樣後交給 Core 的純函式偵測；找不到就顯示說明、不亂框。
                let frames = await self.source.collectRegionFrames(duration: 3)
                let found = VideoRegionDetector.detect(frames: frames)
                model.isDetecting = false
                if let found { model.selection = found } else { model.detectionFailed = true }
            }
        }
        window.onFinish = { [weak self, weak model] applied in
            guard let self else { return }
            self.cropWindow = nil
            let selection = model?.selection
            let result = self.source.finishCropEditing(selection: selection, apply: applied)
            if applied { VideoCropStore.save(result, bundleID: self.source.currentBundleID) }
            self.crop = result
            self.reconcileStreaming()
        }
        source.beginCropEditing()
        window.show()
    }

    private func closeCropWindow(applied: Bool) {
        cropWindow?.close(applied: applied)
    }

    /// 重設裁切（回到整個視窗），並忘記這個 App 記住的裁切。
    func resetCrop() {
        guard state.needsSource, !isCropEditing else { return }
        source.finishCropEditing(selection: nil, apply: true)
        VideoCropStore.save(nil, bundleID: source.currentBundleID)
        crop = nil
    }

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


/// 記住的裁切（依來源 App 的 bundle id）的儲存：只存 bundle id 與正規化矩形，存在 UserDefaults（Defaults）。
enum VideoCropStore {
    static func load() -> VideoCropMemory {
        guard let data = Defaults[.videoCropMemory], let memory = try? JSONDecoder().decode(VideoCropMemory.self, from: data) else { return VideoCropMemory() }
        return memory
    }

    /// 儲存（`nil`／整個視窗＝移除）。bundle id 取不到就不存（只套用於本次串流）。
    static func save(_ rect: NormalizedCropRect?, bundleID: String?) {
        guard let bundleID, !bundleID.isEmpty else { return }
        var memory = load()
        memory.set(rect, for: bundleID)
        Defaults[.videoCropMemory] = try? JSONEncoder().encode(memory)
    }
}
