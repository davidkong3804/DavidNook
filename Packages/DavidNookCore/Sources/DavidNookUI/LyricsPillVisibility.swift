import Foundation

/// 歌詞膠囊的可見性狀態機（純邏輯，時間由呼叫端傳入，便於測試）。
///
/// 顯示條件：功能開啟＋瀏海收合＋正在播放＋歌詞已載入＋當前句非空。任一不成立就立刻收起（視圖負責淡出動畫）；
/// 唯一例外是「暫停」：其他條件都成立但暫停了，膠囊維持 `pauseGrace` 秒後才收起（短暫暫停不閃爍）。
/// 暫停期間不會「新顯示」膠囊——沒在播放就不長出來。
public struct LyricsPillVisibility: Equatable, Sendable {
    public struct Input: Equatable, Sendable {
        public var isEnabled: Bool
        public var isNotchClosed: Bool
        public var isPlaying: Bool
        /// 歌詞已載入（載入中、失敗、查無歌詞都是 false）。
        public var hasLyrics: Bool
        /// 當前句非空白（間奏為 false）。
        public var hasCurrentText: Bool

        public init(isEnabled: Bool, isNotchClosed: Bool, isPlaying: Bool, hasLyrics: Bool, hasCurrentText: Bool) {
            self.isEnabled = isEnabled
            self.isNotchClosed = isNotchClosed
            self.isPlaying = isPlaying
            self.hasLyrics = hasLyrics
            self.hasCurrentText = hasCurrentText
        }
    }

    /// 暫停後多久才收起（秒）。
    public static let pauseGrace: TimeInterval = 1.5

    public private(set) var isVisible = false
    /// 非 nil＝到了這個時刻（呼叫 `tick(at:)`）就收起。
    public private(set) var hideDeadline: TimeInterval?

    public init() {}

    /// 輸入變動時呼叫。
    public mutating func update(_ input: Input, at now: TimeInterval) {
        guard input.isEnabled, input.isNotchClosed, input.hasLyrics, input.hasCurrentText else {
            isVisible = false
            hideDeadline = nil
            return
        }
        if input.isPlaying {
            isVisible = true
            hideDeadline = nil
        } else if isVisible {
            if hideDeadline == nil { hideDeadline = now + Self.pauseGrace }
        } else {
            hideDeadline = nil
        }
    }

    /// 時間流逝（到期時呼叫）；期限到了就收起。
    public mutating func tick(at now: TimeInterval) {
        guard let deadline = hideDeadline, now >= deadline else { return }
        isVisible = false
        hideDeadline = nil
    }
}
