import Foundation

/// SCStream 每個回呼的畫面狀態（原始值與 SDK 標頭 `SCStream.h` 的 `SCFrameStatus` 一致：
/// complete 0、idle 1、blank 2、suspended 3、started 4、stopped 5）。純邏輯，不依賴 ScreenCaptureKit。
///
/// - `complete`（新畫面）與 `started`（串流開始後的**第一幀**）都帶有畫面，必須顯示——
///   只收 `complete` 會丟掉重啟／恢復串流後的第一幀，來源靜止時浮動視窗就一直是空的（看起來「卡住」）。
/// - `idle`（畫面沒變）、`blank`、`suspended` 沒有新畫面，但代表串流還活著：算「心跳」，卡住監看不可因此誤重啟。
/// - `stopped`＝串流已停，不是心跳。
public enum VideoFrameStatus: Int, Sendable, CaseIterable {
    case complete = 0, idle, blank, suspended, started, stopped

    public var carriesNewPicture: Bool { self == .complete || self == .started }
    public var isHeartbeat: Bool { self != .stopped }

    /// 未知的原始值（未來的 SDK 新增）：當作心跳、不顯示畫面。
    public static func isHeartbeat(rawStatus: Int?) -> Bool {
        guard let rawStatus, let status = VideoFrameStatus(rawValue: rawStatus) else { return true }
        return status.isHeartbeat
    }
}
