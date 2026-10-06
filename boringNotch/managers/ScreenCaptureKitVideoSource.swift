//
//  ScreenCaptureKitVideoSource.swift
//  DavidNook
//
//  影片膠囊的擷取層：系統挑選器（只允許單一視窗）＋ SCStream。只有這個檔案碰 ScreenCaptureKit。
//
//  隱私：
//  - 畫面只在記憶體：IOSurface 直接交給顯示層（VideoFrameDisplay），不存檔、不上傳、不快取、不截圖、不寫入剪貼簿。
//  - 每秒只算一次平均亮度（32×32 格點）餵給 Core 的黑畫面偵測，像素不保留。
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
    private var lastRatio: Double = 0
    private var lastBrightnessAt: CFAbsoluteTime = 0
    private var lastReportedSize = CGSize.zero
    private var pickerConfigured = false
    private var captureWidth = ScreenCaptureKitVideoSource.maximumCaptureWidth

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
        let ratio = lastRatio
        lock.unlock()
        guard changed, let stream, ratio > 0 else { return }
        let config = makeConfiguration(ratio: ratio)
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

    func resume() {
        lock.lock()
        let filter = self.filter
        let alreadyRunning = stream != nil
        lock.unlock()
        guard let filter, !alreadyRunning else { return }
        startStream(filter: filter)
        log.info("resumed")
    }

    // MARK: 串流

    private func makeConfiguration(ratio: Double) -> SCStreamConfiguration {
        lock.lock(); let width = captureWidth; lock.unlock()
        let config = SCStreamConfiguration()
        config.width = width
        config.height = max(1, Int((Double(width) / max(ratio, 0.01)).rounded()))
        config.minimumFrameInterval = Self.frameInterval
        config.capturesAudio = false
        config.showsCursor = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 3
        return config
    }

    private func startStream(filter: SCContentFilter) {
        let rect = filter.contentRect
        let ratio = rect.height > 0 && rect.width > 0 ? Double(rect.width / rect.height) : VideoCapsuleStateMachine.fallbackAspectRatio

        teardownStream(keepFilter: true)
        lock.lock()
        self.filter = filter
        generation += 1
        let myGeneration = generation
        lastRatio = ratio
        lastBrightnessAt = 0
        lastReportedSize = rect.size
        stoppingByUs = false
        lock.unlock()

        let newStream = SCStream(filter: filter, configuration: makeConfiguration(ratio: ratio), delegate: self)
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
        startStream(filter: filter)
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
        // 只處理 complete 的幀（idle／blank 等狀態幀沒有新畫面）。
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        if let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() {
            display.present(surface)
        }

        // 來源視窗被縮放：contentRect 的長寬比改變 → 回報並調整擷取高度。
        if let info = attachments.first, let rectDict = info[.contentRect] as? NSDictionary,
           let rect = CGRect(dictionaryRepresentation: rectDict as CFDictionary), rect.width > 0, rect.height > 0 {
            reportSizeIfChanged(rect.size)
        }

        // 每秒一次的平均亮度。
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock()
        let due = now - lastBrightnessAt >= 1.0
        if due { lastBrightnessAt = now }
        lock.unlock()
        guard due else { return }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        if let value = BlackFrameDetector.averageBrightness(
            baseAddress: UnsafeRawPointer(base), byteCount: bytesPerRow * height,
            width: width, height: height, bytesPerRow: bytesPerRow, grid: 32
        ) {
            continuation.yield(.brightness(value))
        }
    }

    private func reportSizeIfChanged(_ size: CGSize) {
        lock.lock()
        let previous = lastReportedSize
        let changed = abs(size.width - previous.width) > 1 || abs(size.height - previous.height) > 1
        if changed {
            lastReportedSize = size
            lastRatio = Double(size.width / size.height)
        }
        let ratio = lastRatio
        let stream = self.stream
        lock.unlock()
        guard changed else { return }
        continuation.yield(.frameSize(width: Int(size.width.rounded()), height: Int(size.height.rounded())))
        stream?.updateConfiguration(makeConfiguration(ratio: ratio)) { _ in }
    }
}
