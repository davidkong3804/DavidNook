import CoreGraphics
import Foundation

/// 一句歌詞的跑馬燈時間軸（純邏輯）：起點停頓 → 勻速水平捲到句尾 → 句尾停頓。
///
/// - 句子放得下容器（超出不到 0.5 pt）就完全不捲。
/// - 速度由「句子可用時間」推算：可用時間＝句長 − 起點停頓 − 句尾停頓；一般倍率 1 只用其中 80%（句尾多留一點停頓），
///   倍率越大越快、倍率 ≤ 0.8 用滿可用時間（絕不為了「慢」而趕不上下一句）。速度夾在
///   `minSpeed`…`maxSpeed`：句子太長時間太緊就加速到上限（再緊就來不及，是可接受的取捨）；時間很充裕也不會慢到爬。
/// - `scrollOffset` 回傳「已向左捲了多少」（0…overflow，單位 pt）；視圖把它當作負的水平位移。
public struct LyricsMarquee: Equatable, Sendable {
    public enum Constants {
        /// 換句後先停多久才開始捲。
        public static let startPause: TimeInterval = 0.4
        /// 捲到句尾後、下一句開始前至少停多久。
        public static let endPause: TimeInterval = 0.6
        public static let minSpeed: CGFloat = 24
        public static let maxSpeed: CGFloat = 140
        /// 倍率 1 時，捲動時間占可用時間的比例。
        public static let relaxedFill: Double = 0.8
        /// 不知道這一句多長（最後一句、時間軸沒有下一行）時假設的句長。
        public static let fallbackLineDuration: TimeInterval = 6
        /// 超出這麼少就視為放得下。
        public static let fitTolerance: CGFloat = 0.5
    }

    public let overflow: CGFloat
    public let speed: CGFloat

    public init(containerWidth: CGFloat, textWidth: CGFloat, lineDuration: TimeInterval?, speedMultiplier: Double = 1) {
        let usable = containerWidth.isFinite && textWidth.isFinite && containerWidth > 0 && textWidth > 0
        let over = usable ? textWidth - containerWidth : 0
        guard over > Constants.fitTolerance else {
            overflow = 0
            speed = 0
            return
        }
        overflow = over

        let duration: TimeInterval
        if let lineDuration, lineDuration.isFinite, lineDuration > 0 {
            duration = lineDuration
        } else {
            duration = Constants.fallbackLineDuration
        }
        let multiplier = LyricsPillMetrics.clampedSpeed(speedMultiplier)
        let available = max(duration - Constants.startPause - Constants.endPause, 0.1)
        let scrollTime = min(available, available * Constants.relaxedFill / multiplier)
        let wanted = CGFloat(Double(over) / scrollTime)
        speed = min(max(wanted, Constants.minSpeed), Constants.maxSpeed)
    }

    public var needsScrolling: Bool { overflow > 0 }

    /// 勻速捲動花的時間（秒）；不需捲動為 0。
    public var scrollDuration: TimeInterval {
        needsScrolling ? Double(overflow / speed) : 0
    }

    /// 捲到句尾的時刻（自這一句開始起算，秒）；不需捲動為 0。
    public var finishTime: TimeInterval {
        needsScrolling ? Constants.startPause + scrollDuration : 0
    }

    /// 這一句開始後 `elapsed` 秒，已向左捲了多少 pt。負值與 NaN 視為 0。
    public func scrollOffset(at elapsed: TimeInterval) -> CGFloat {
        guard needsScrolling, elapsed.isFinite, elapsed > Constants.startPause else { return 0 }
        let travelled = CGFloat(elapsed - Constants.startPause) * speed
        return min(travelled, overflow)
    }

    /// 這個時刻是否還需要逐幀更新（捲完之後畫面靜止，可以停掉 TimelineView）。
    public func isScrolling(at elapsed: TimeInterval) -> Bool {
        needsScrolling && !(elapsed.isFinite && elapsed >= finishTime)
    }
}
