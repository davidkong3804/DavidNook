//
//  ScreenCaptureKitVideoSource.swift
//  DavidNook
//
//  影片膠囊的擷取層：系統挑選器（只允許單一視窗）＋ SCStream。只有這個檔案碰 ScreenCaptureKit。
//
//  隱私：
//  - 畫面只在記憶體：IOSurface 直接交給顯示層（VideoFrameDisplay），不存檔、不上傳、不快取、不截圖、不寫入剪貼簿。
//  - 每秒只算一次平均亮度（32×32 格點，只看裁切區域）餵給 Core 的黑畫面偵測，像素不保留。
//  - 裁切（只擷取視窗內一塊區域）：`SCStreamConfiguration.sourceRect`（單位 pt、視窗擷取時相對視窗；SDK 標頭未明說原點，採左上、y 向下，
//    需真機驗證）。裁切範圍以相對視窗的正規化矩形保存。編輯裁切時暫時串整個視窗（同一條串流改設定，不開第二條），
//    自動偵測只在記憶體裡保留約 12 張 64×36 的亮度小圖，偵測完即丟。
//  - log 只記狀態與錯誤碼，不含視窗標題、App 名稱或任何畫面內容。
//  - 不擷取音訊、不顯示游標；不呼叫 CGRequestScreenCaptureAccess（授權由系統挑選器處理）。
//

import AppKit
import CoreMedia
import CoreVideo
import DavidNookCore
import DavidNookUI
import IOSurface
import OSLog
import ScreenCaptureKit

final class ScreenCaptureKitVideoSource: NSObject, VideoFrameSource, @unchecked Sendable {
    /// 擷取寬度上限（再由視圖縮放）。
    static let maximumCaptureWidth = 480
    static let minimumCaptureWidth = 160
    static let frameInterval = CMTime(value: 1, timescale: 20)
    /// 編輯裁切時的擷取寬度（px）：裁切視窗顯示較大的畫面。
    static let editorCaptureWidth = 1200
    /// 自動偵測的取樣：間隔與小圖大小。
    static let regionSampleInterval: CFAbsoluteTime = 0.25
    static let regionSampleSize = (width: 64, height: 36)

    /// 新挑選視窗時，依來源 App 的 bundle id 取回記住的裁切（由控制器提供；可從任何執行緒呼叫）。
    var cropResolver: (@Sendable (String?) -> NormalizedCropRect?)?

    let events: AsyncStream<VideoSourceEvent>
    private let continuation: AsyncStream<VideoSourceEvent>.Continuation
    private let display: VideoFrameDisplay
    private let log = Logger(subsystem: "io.github.davidkong3804.DavidNook", category: "video")
    private let queue = DispatchQueue(label: "DavidNook.video.frames", qos: .userInitiated)

    /// 保護下面可變狀態（回呼來自多個佇列）。
    private let lock = NSLock()
    private var filter: SCContentFilter?
    private var stream: SCStream?
    private var stoppingByUs = false
    private var generation = 0
    private var lastBrightnessAt: CFAbsoluteTime = 0
    /// 來源視窗大小（pt）。有裁切（且不在編輯）時不再追蹤（框內畫面的 contentRect 不代表視窗大小）。
    private var windowSize = CGSize.zero
    private var currentCrop: NormalizedCropRect?
    private var isEditingCrop = false
    private var sourceBundleID: String?
    private var regionFrames: [LumaFrame]?
    private var lastRegionSampleAt: CFAbsoluteTime = 0
    private var pickerConfigured = false
    private var captureWidth = ScreenCaptureKitVideoSource.maximumCaptureWidth
    /// 最近一次收到串流回呼的時間（`ProcessInfo.systemUptime`；含「畫面沒變」的 idle 幀）。給卡住監看用。
    private var lastCallbackUptime: TimeInterval = 0
    /// 各幀狀態的回呼次數（只有計數，沒有內容；診斷「畫面停住」用，見 `drainStatusSummary`）。
    private var statusCounts: [Int: Int] = [:]

    init(display: VideoFrameDisplay) {
        self.display = display
        var c: AsyncStream<VideoSourceEvent>.Continuation!
        events = AsyncStream { c = $0 }
        continuation = c
        super.init()
    }

    /// 使用者的寬度（pt）→ 擷取寬度（Retina 2×，夾在 160…480）。滑桿放開時呼叫。
    func updateRequestedWidth(_ points: Double) {
        let w = min(max(Int((points * 2).rounded()), Self.minimumCaptureWidth), Self.maximumCaptureWidth)
        lock.lock()
        let changed = w != captureWidth
        captureWidth = w
        let stream = self.stream
        let known = windowSize.width > 0 && windowSize.height > 0
        lock.unlock()
        guard changed, let stream, known else { return }
        let config = makeConfiguration()
        stream.updateConfiguration(config) { [log] error in
            if let error { log.error("updateConfiguration failed code=\((error as NSError).code)") }
        }
    }

    // MARK: VideoFrameSource

    func start() {
        DispatchQueue.main.async { [self] in
            let picker = SCContentSharingPicker.shared
            if !pickerConfigured {
                pickerConfigured = true
                var configuration = SCContentSharingPickerConfiguration()
                configuration.allowedPickerModes = .singleWindow
                if let bundleID = Bundle.main.bundleIdentifier { configuration.excludedBundleIDs = [bundleID] }
                picker.defaultConfiguration = configuration
                picker.maximumStreamCount = 1
                picker.add(self)
            }
            picker.isActive = true
            picker.present(using: .window)
            log.info("picker presented")
        }
    }

    func stop() {
        lock.lock()
        currentCrop = nil
        isEditingCrop = false
        regionFrames = nil
        sourceBundleID = nil
        lock.unlock()
        teardownStream(keepFilter: false)
        display.clear()
        DispatchQueue.main.async { SCContentSharingPicker.shared.isActive = false }
        log.info("stopped")
    }

    func pause() {
        teardownStream(keepFilter: true)
        display.clear()
        log.info("paused")
    }

    /// 最近一次串流回呼的時間（0＝還沒收過）。
    var lastCallbackTime: TimeInterval { lock.lock(); defer { lock.unlock() }; return lastCallbackUptime }

    /// 取出並清空自上次以來各幀狀態的次數（例如 `complete=19 idle=0 started=0`）。只含數字，供 log 診斷。
    func drainStatusSummary() -> String {
        lock.lock(); let counts = statusCounts; statusCounts = [:]; lock.unlock()
        let names = ["complete", "idle", "blank", "suspended", "started", "stopped"]
        let known = names.enumerated().map { "\($1)=\(counts[$0] ?? 0)" }
        let other = counts.filter { !(0...5).contains($0.key) }.values.reduce(0, +)
        return (known + ["other=\(other)"]).joined(separator: " ")
    }

    /// 卡住監看用：沿用同一個視窗與裁切重新開始串流（會回報 `.started`）。
    func restart() {
        lock.lock(); let filter = self.filter; lock.unlock()
        guard let filter else { return }
        startStream(filter: filter, resolveCrop: false)
        log.info("restarted by watchdog")
    }

    func resume() {
        lock.lock()
        let filter = self.filter
        let alreadyRunning = stream != nil
        lock.unlock()
        guard let filter, !alreadyRunning else { return }
        startStream(filter: filter, resolveCrop: false)   // 同一個視窗恢復串流：沿用目前的裁切
        log.info("resumed")
    }

    // MARK: 串流

    /// 目前輸出畫面的長寬比：有裁切（且不在編輯）＝裁切區域的比例，否則＝視窗比例。
    private func currentRatio() -> Double {
        lock.lock(); defer { lock.unlock() }
        return ratioLocked()
    }

    private func ratioLocked() -> Double {
        let window = windowSize
        if !isEditingCrop, let crop = currentCrop, let ratio = crop.aspectRatio(windowSize: window) { return ratio }
        guard window.width > 0, window.height > 0 else { return VideoCapsuleStateMachine.fallbackAspectRatio }
        return Double(window.width / window.height)
    }

    private func makeConfiguration() -> SCStreamConfiguration {
        lock.lock()
        let editing = isEditingCrop
        let width = editing ? Self.editorCaptureWidth : captureWidth
        let crop = editing ? nil : currentCrop
        let window = windowSize
        let ratio = ratioLocked()
        lock.unlock()
        let config = SCStreamConfiguration()
        config.width = width
        config.height = max(1, Int((Double(width) / max(ratio, 0.01)).rounded()))
        // 裁切：只擷取視窗內這一塊（單位 pt，相對視窗；原點假設見上方說明，未經真機驗證）。
        if let crop, window.width > 0, window.height > 0 { config.sourceRect = crop.sourceRect(in: window) }
        config.minimumFrameInterval = Self.frameInterval
        config.capturesAudio = false
        config.showsCursor = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 3
        return config
    }

    private func startStream(filter: SCContentFilter, resolveCrop: Bool) {
        let rect = filter.contentRect
        let bundleID = Self.bundleIdentifier(of: filter)
        // 記住的裁切依 bundle id 取回（只在新挑選視窗時；恢復串流沿用目前的）。
        let remembered = resolveCrop ? cropResolver?(bundleID) : nil

        teardownStream(keepFilter: true)
        lock.lock()
        self.filter = filter
        generation += 1
        let myGeneration = generation
        lastBrightnessAt = 0
        windowSize = rect.size
        if resolveCrop {
            sourceBundleID = bundleID
            currentCrop = remembered
            isEditingCrop = false
        }
        stoppingByUs = false
        lock.unlock()
        let ratio = currentRatio()

        let newStream = SCStream(filter: filter, configuration: makeConfiguration(), delegate: self)
        do {
            try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        } catch {
            log.error("addStreamOutput failed code=\((error as NSError).code)")
            continuation.yield(.failed(.streamStopped(code: (error as NSError).code)))
            return
        }
        lock.lock(); stream = newStream; lock.unlock()
        continuation.yield(.started(aspectRatio: ratio))
        newStream.startCapture { [weak self] error in
            guard let self, let error else { return }
            self.lock.lock()
            let current = self.generation == myGeneration
            self.lock.unlock()
            guard current else { return }
            let ns = error as NSError
            self.log.error("startCapture failed code=\(ns.code)")
            self.continuation.yield(.failed(Self.failure(for: ns)))
        }
    }

    private func teardownStream(keepFilter: Bool) {
        lock.lock()
        let old = stream
        stream = nil
        if old != nil { stoppingByUs = true }
        generation += 1
        if !keepFilter { filter = nil }
        lock.unlock()
        guard let old else { return }
        old.stopCapture { _ in }
    }

    /// 錯誤碼 → 事件。視窗關閉在不同情況下回的碼不同（使用者按系統的「停止分享」、來源消失、系統收回）：一律視為「來源已關閉」。
    static func failure(for error: NSError) -> VideoFailure {
        guard error.domain == SCStreamErrorDomain else { return .streamStopped(code: error.code) }
        switch SCStreamError.Code(rawValue: error.code) {
        case .userDeclined: return .permissionDenied
        default: return .streamStopped(code: error.code)
        }
    }

    static func isSourceGone(_ error: NSError) -> Bool {
        guard error.domain == SCStreamErrorDomain else { return false }
        switch SCStreamError.Code(rawValue: error.code) {
        case .noCaptureSource, .noWindowList, .systemStoppedStream, .removingStream, .userStopped: return true
        default: return false
        }
    }
}

// MARK: - 挑選器

extension ScreenCaptureKitVideoSource: SCContentSharingPickerObserver {
    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        log.info("picker selected")
        startStream(filter: filter, resolveCrop: true)
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        log.info("picker cancelled")
        continuation.yield(.selectionCancelled)
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        log.error("picker start failed code=\((error as NSError).code)")
        continuation.yield(.failed(.pickerFailed))
    }
}

// MARK: - 串流輸出

extension ScreenCaptureKitVideoSource: SCStreamDelegate, SCStreamOutput {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.lock()
        let isCurrent = self.stream === stream
        let byUs = stoppingByUs && !isCurrent
        lock.unlock()
        // 我們自己停掉的（換視窗、暫停）不回報。
        guard isCurrent, !byUs else { return }
        let ns = error as NSError
        log.info("stream stopped code=\(ns.code)")
        lock.lock(); self.stream = nil; lock.unlock()
        display.clear()
        continuation.yield(Self.isSourceGone(ns) ? .sourceClosed : .failed(Self.failure(for: ns)))
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]]
        let rawStatus = attachments?.first?[.status] as? Int
        // 心跳：任何「串流還活著」的回呼（含畫面沒變的 idle）都算，卡住監看才不會在來源靜止時誤重啟（規則在 Core 的 VideoFrameStatus）。
        lock.lock()
        statusCounts[rawStatus ?? -1, default: 0] += 1
        if VideoFrameStatus.isHeartbeat(rawStatus: rawStatus) { lastCallbackUptime = ProcessInfo.processInfo.systemUptime }
        lock.unlock()
        // 只顯示帶畫面的幀：complete 與 started（重啟／恢復後的第一幀；只收 complete 會丟掉它，靜止來源就一直沒畫面）。
        guard let attachments, let rawStatus, VideoFrameStatus(rawValue: rawStatus)?.carriesNewPicture == true,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        if let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() {
            display.present(surface)
        }

        // 來源視窗被縮放：contentRect 的長寬比改變 → 回報並調整擷取高度。
        if let info = attachments.first, let rectDict = info[.contentRect] as? NSDictionary,
           let rect = CGRect(dictionaryRepresentation: rectDict as CFDictionary), rect.width > 0, rect.height > 0 {
            reportSizeIfChanged(rect.size)
        }

        // 每秒一次的平均亮度（只看裁切區域）；自動偵測期間另外每 0.25 秒取一張小圖。
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock()
        let due = now - lastBrightnessAt >= 1.0
        if due { lastBrightnessAt = now }
        let collecting = regionFrames != nil && now - lastRegionSampleAt >= Self.regionSampleInterval
        if collecting { lastRegionSampleAt = now }
        // 沒在編輯時，輸出畫面本身就是裁切區域（sourceRect 已套用），整張都看；編輯中輸出整個視窗，只看目前的裁切區域。
        let region: NormalizedCropRect? = isEditingCrop ? currentCrop : nil
        lock.unlock()
        guard due || collecting else { return }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        if collecting,
           let frame = LumaFrame.fromBGRA(
               baseAddress: UnsafeRawPointer(base), byteCount: bytesPerRow * height, width: width, height: height, bytesPerRow: bytesPerRow,
               targetWidth: Self.regionSampleSize.width, targetHeight: Self.regionSampleSize.height
           ) {
            lock.lock(); regionFrames?.append(frame); lock.unlock()
        }
        guard due else { return }
        if let value = BlackFrameDetector.averageBrightness(
            baseAddress: UnsafeRawPointer(base), byteCount: bytesPerRow * height,
            width: width, height: height, bytesPerRow: bytesPerRow, grid: 32, region: region
        ) {
            continuation.yield(.brightness(value))
        }
    }

    private func reportSizeIfChanged(_ size: CGSize) {
        lock.lock()
        // 有裁切（且不在編輯）時，框內畫面的 contentRect 不代表視窗大小：不追蹤視窗縮放（需要時請重新裁切）。
        if currentCrop != nil, !isEditingCrop { lock.unlock(); return }
        let previous = windowSize
        let changed = abs(size.width - previous.width) > 1 || abs(size.height - previous.height) > 1
        if changed { windowSize = size }
        let editing = isEditingCrop
        let stream = self.stream
        lock.unlock()
        guard changed else { return }
        if !editing { continuation.yield(.frameSize(width: Int(size.width.rounded()), height: Int(size.height.rounded()))) }
        stream?.updateConfiguration(makeConfiguration()) { _ in }
    }
}

// MARK: - 裁切（只擷取視窗內一塊區域）

extension ScreenCaptureKitVideoSource {
    /// 目前的裁切（正規化）；沒有＝整個視窗。
    var crop: NormalizedCropRect? { lock.lock(); defer { lock.unlock() }; return currentCrop }
    /// 來源 App 的 bundle id（macOS 15.2 以下取不到＝nil；只用來記住裁切，不含視窗標題）。
    var currentBundleID: String? { lock.lock(); defer { lock.unlock() }; return sourceBundleID }
    /// 來源視窗的長寬比（編輯裁切時畫面區的形狀）。
    var windowAspectRatio: Double {
        lock.lock(); defer { lock.unlock() }
        return windowSize.width > 0 && windowSize.height > 0 ? Double(windowSize.width / windowSize.height) : VideoCapsuleStateMachine.fallbackAspectRatio
    }

    /// 開始編輯：同一條串流改成串整個視窗（較大尺寸），讓裁切視窗看得到全貌。
    func beginCropEditing() {
        lock.lock()
        isEditingCrop = true
        let stream = self.stream
        lock.unlock()
        stream?.updateConfiguration(makeConfiguration()) { [log] error in
            if let error { log.error("updateConfiguration failed code=\((error as NSError).code)") }
        }
        log.info("crop editing began")
    }

    /// 結束編輯。`apply` 為 true 時套用 `selection`（nil／整個視窗＝不裁切）；false 時維持原本的裁切。回傳實際生效的裁切。
    @discardableResult
    func finishCropEditing(selection: NormalizedCropRect?, apply: Bool) -> NormalizedCropRect? {
        lock.lock()
        isEditingCrop = false
        regionFrames = nil
        if apply {
            if let selection, !selection.isFullWindow { currentCrop = selection.sanitized } else { currentCrop = nil }
        }
        let result = currentCrop
        let ratio = ratioLocked()
        let stream = self.stream
        lock.unlock()
        stream?.updateConfiguration(makeConfiguration()) { [log] error in
            if let error { log.error("updateConfiguration failed code=\((error as NSError).code)") }
        }
        continuation.yield(.cropChanged(aspectRatio: ratio))
        log.info("crop editing finished")
        return result
    }

    /// 自動偵測：串流約 `duration` 秒，期間每 0.25 秒取一張 64×36 的亮度小圖（只在記憶體），回傳後即丟。需在編輯中（輸出整個視窗）呼叫。
    func collectRegionFrames(duration: TimeInterval) async -> [LumaFrame] {
        lock.lock(); regionFrames = []; lastRegionSampleAt = 0; lock.unlock()
        try? await Task.sleep(for: .seconds(duration))
        lock.lock()
        let frames = regionFrames ?? []
        regionFrames = nil
        lock.unlock()
        return frames
    }

    /// 來源 App 的 bundle id（`SCContentFilter.includedWindows` 需要 macOS 15.2；更舊的系統取不到）。
    static func bundleIdentifier(of filter: SCContentFilter) -> String? {
        if #available(macOS 15.2, *) {
            return filter.includedWindows.first?.owningApplication?.bundleIdentifier
        }
        return nil
    }
}
