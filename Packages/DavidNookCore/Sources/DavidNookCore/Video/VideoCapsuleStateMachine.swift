import Foundation

/// 影片功能的狀態（展開瀏海的「影片」分頁與之後的釘選膠囊共用）。
public enum VideoCapsuleState: Equatable, Sendable {
    /// 還沒選來源。
    case idle
    /// 系統挑選器開著。
    case choosing
    /// 串流中；`aspectRatio` = 寬 ÷ 高。
    case streaming(aspectRatio: Double)
    /// 來源視窗已關閉。
    case sourceClosed
    /// 持續全黑：多半是受內容保護（DRM）的來源，系統不允許擷取。
    case blackContent(aspectRatio: Double)
    case error(VideoFailure)

    /// Home 封面槽要用的長寬比：nil＝顯示專輯封面（方形）；串流中／黑畫面＝來源長寬比；
    /// 來源關閉與錯誤的說明也放進加寬的槽（16:9），才放得下完整的說明文字。
    public var slotAspectRatio: Double? {
        switch self {
        case .idle, .choosing: return nil
        case .streaming(let ratio), .blackContent(let ratio): return ratio
        case .sourceClosed, .error: return VideoCapsuleStateMachine.fallbackAspectRatio
        }
    }

    /// 是否需要來源在跑（要不要保持串流；idle／sourceClosed／error／choosing 都不需要）。
    public var needsSource: Bool {
        switch self {
        case .streaming, .blackContent: return true
        case .idle, .choosing, .sourceClosed, .error: return false
        }
    }
}

public enum VideoCapsuleInput: Equatable, Sendable {
    /// 使用者按「選擇視窗」或「換視窗」。
    case requestPicker
    /// 使用者按「停止」。
    case userStopped
    /// 使用者點一下影片：釘選／取消釘選（釘成瀏海外面的影片膠囊；膠囊本身屬 M-C）。
    case togglePin
    case source(VideoSourceEvent)
}

/// 影片功能狀態機（純邏輯，時間由呼叫端傳入）。無效的轉移一律忽略。
///
/// - 挑選取消：回到挑選前的狀態（串流中換視窗取消，原串流繼續）。
/// - 任何時候收到 `.started`（含挑選器自己的「換視窗」）→ 串流中，並重置黑畫面計時。
/// - 釘選：只在串流中可釘；串流結束、偵測到黑畫面一律自動取消（見 `isPinned`）。
/// - 串流中持續全黑 → `blackContent`；一有非黑畫面立刻恢復 `streaming`。
public struct VideoCapsuleStateMachine: Equatable, Sendable {
    public static let fallbackAspectRatio: Double = 16.0 / 9.0

    public private(set) var state: VideoCapsuleState = .idle
    /// 是否已釘選。只在串流中才能釘；串流結束（停止、來源關閉、錯誤）與偵測到黑畫面（疑似受保護）一律自動取消；換視窗期間維持。
    public private(set) var isPinned = false
    private var stateBeforePicking: VideoCapsuleState = .idle
    private var detector = BlackFrameDetector()

    public init() {}

    private static func sanitized(_ ratio: Double) -> Double {
        ratio.isFinite && ratio > 0 ? ratio : fallbackAspectRatio
    }

    public mutating func handle(_ input: VideoCapsuleInput, at time: TimeInterval) {
        switch input {
        case .requestPicker:
            if state != .choosing { stateBeforePicking = state }
            state = .choosing
        case .togglePin:
            if isPinned {
                isPinned = false
            } else if case .streaming = state {
                isPinned = true
            }
        case .userStopped:
            isPinned = false
            detector.reset()
            stateBeforePicking = .idle
            state = .idle
        case .source(let event):
            handle(event, at: time)
        }
    }

    private mutating func handle(_ event: VideoSourceEvent, at time: TimeInterval) {
        switch event {
        case .started(let ratio):
            detector.reset()
            state = .streaming(aspectRatio: Self.sanitized(ratio))
        case .cropChanged(let ratio):
            // 裁切改變：新長寬比，黑畫面計時重來（裁切前的樣本不算數）；釘選不受影響。
            switch state {
            case .streaming, .blackContent:
                detector.reset()
                state = .streaming(aspectRatio: Self.sanitized(ratio))
            default: break
            }
        case .selectionCancelled:
            guard state == .choosing else { return }
            state = stateBeforePicking
        case .frameSize(let width, let height):
            guard width > 0, height > 0 else { return }
            let ratio = Double(width) / Double(height)
            switch state {
            case .streaming: state = .streaming(aspectRatio: ratio)
            case .blackContent: state = .blackContent(aspectRatio: ratio)
            default: break
            }
        case .brightness(let value):
            switch state {
            case .streaming(let ratio):
                if detector.ingest(brightness: value, at: time) {
                    state = .blackContent(aspectRatio: ratio)
                    // 疑似受保護的內容：釘選的膠囊不顯示黑塊，直接取消釘選（恢復非黑後也不會自己再釘）。
                    isPinned = false
                }
            case .blackContent(let ratio):
                if !detector.ingest(brightness: value, at: time) { state = .streaming(aspectRatio: ratio) }
            default: break
            }
        case .sourceClosed:
            switch state {
            case .streaming, .blackContent:
                detector.reset()
                isPinned = false
                state = .sourceClosed
            case .choosing:
                // 挑選中舊串流被關閉：取消後應回到「來源已關閉」。
                if stateBeforePicking.needsSource {
                    stateBeforePicking = .sourceClosed
                    isPinned = false
                }
            default: break
            }
        case .failed(let failure):
            isPinned = false
            detector.reset()
            state = .error(failure)
        }
    }
}
