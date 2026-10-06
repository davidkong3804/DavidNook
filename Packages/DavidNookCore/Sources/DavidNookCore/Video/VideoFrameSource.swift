import Foundation

/// 影片來源失敗的原因。只含種類與錯誤碼——**不含視窗標題、App 名稱或任何畫面內容**，所以可以安全寫進 log。
public enum VideoFailure: Equatable, Sendable {
    /// 系統不允許擷取（尚未授權螢幕錄製，或被拒絕）。
    case permissionDenied
    /// 系統挑選器無法啟動。
    case pickerFailed
    /// 串流中途被系統停止（`code` 為 SCStreamError 的錯誤碼）。
    case streamStopped(code: Int)
    case unknown

    /// 給 log 用的描述（無任何內容資訊）。
    public var logDescription: String {
        switch self {
        case .permissionDenied: return "permissionDenied"
        case .pickerFailed: return "pickerFailed"
        case .streamStopped(let code): return "streamStopped(\(code))"
        case .unknown: return "unknown"
        }
    }
}

/// 來源回報的事件。畫面本身**不**經過這裡（像素由 App 端直接交給顯示層，不經 Core、不保存）；
/// 這裡只有狀態與每秒一次的平均亮度。
public enum VideoSourceEvent: Equatable, Sendable {
    /// 使用者在挑選器選了視窗、串流已開始。
    case started(aspectRatio: Double)
    /// 使用者關閉挑選器沒有選。
    case selectionCancelled
    /// 畫面尺寸（像素）改變（來源視窗被縮放）。
    case frameSize(width: Int, height: Int)
    /// 每秒一次的平均亮度（0…255）。只看裁切區域（有裁切時）。
    case brightness(Double)
    /// 裁切範圍改變（或套用／重設）：輸出畫面的新長寬比。
    case cropChanged(aspectRatio: Double)
    /// 來源視窗關閉（或串流被正常結束）。
    case sourceClosed
    case failed(VideoFailure)
}

/// 影片畫面來源：App 端以 ScreenCaptureKit 實作；測試用 `FakeVideoFrameSource`。
public protocol VideoFrameSource: AnyObject, Sendable {
    /// 狀態事件串流。
    var events: AsyncStream<VideoSourceEvent> { get }
    /// 開始：彈出（系統）挑選器；使用者選定後以 `.started` 回報。
    func start()
    /// 停止擷取並釋放所有畫面緩衝與已選的視窗（不結束 `events`，之後可再 `start()`）。
    func stop()
    /// 暫停：影片分頁不在畫面上時停止串流（省電），但記住已選的視窗。沒有選過就什麼都不做。
    func pause()
    /// 從 `pause()` 恢復：以原來選的視窗重新開始串流。
    func resume()
}

/// 測試與離屏渲染用的假來源：由測試呼叫 `emit` 推事件；記錄 start／stop 次數。
public final class FakeVideoFrameSource: VideoFrameSource, @unchecked Sendable {
    public let events: AsyncStream<VideoSourceEvent>
    private let continuation: AsyncStream<VideoSourceEvent>.Continuation
    private let lock = NSLock()
    private var _startCount = 0
    private var _stopCount = 0
    private var _pauseCount = 0
    private var _resumeCount = 0

    public init() {
        var c: AsyncStream<VideoSourceEvent>.Continuation!
        events = AsyncStream { c = $0 }
        continuation = c
    }

    public var startCount: Int { lock.lock(); defer { lock.unlock() }; return _startCount }
    public var stopCount: Int { lock.lock(); defer { lock.unlock() }; return _stopCount }

    public func start() { lock.lock(); _startCount += 1; lock.unlock() }
    public func stop() { lock.lock(); _stopCount += 1; lock.unlock() }
    public var pauseCount: Int { lock.lock(); defer { lock.unlock() }; return _pauseCount }
    public var resumeCount: Int { lock.lock(); defer { lock.unlock() }; return _resumeCount }
    public func pause() { lock.lock(); _pauseCount += 1; lock.unlock() }
    public func resume() { lock.lock(); _resumeCount += 1; lock.unlock() }

    public func emit(_ event: VideoSourceEvent) { continuation.yield(event) }
    public func finish() { continuation.finish() }
}
