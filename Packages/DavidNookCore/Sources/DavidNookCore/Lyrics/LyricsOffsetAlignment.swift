import Foundation

/// 「點歌詞對齊」的計算：使用者聽到某一句正在唱時點那一行，要把逐曲偏移設成讓這一行剛好是目前行。
///
/// 偏移語意與 `LyricsTimeline` 完全相同（毫秒；**正值＝歌詞提早、負值＝延後**）：
///
///     查詢時間 = 播放位置 + lrcOffsetMs + userOffsetMs
///     要讓「行時間 == 查詢時間」：userOffsetMs = 行時間 − lrcOffsetMs − 播放位置
///
/// 行時間是 `LRCLine.timeMs`（檔案內的原始時間，不含任何偏移），所以**目前已套用的偏移不影響結果**：
/// 不論先前調過多少，點同一行都會得到同一個偏移，也因此函式不需要「現有偏移」這個輸入。
///
/// 進位：結果往上進位到 10 ms（不是四捨五入）。往上進位只會讓歌詞「多提早 0–9 ms」，
/// 保證套用後被點的那一行立刻成為目前行（四捨五入有一半機率差幾毫秒、要再等一下才亮）；
/// 同時讓顯示的數字乾淨（1.24 秒而不是 1.237 秒）。
public enum LyricsOffsetAlignment {

    /// 偏移的上下限（毫秒，±60 秒）；整個 App 共用這一個值。
    public static let limitMs = 60_000

    /// 夾在 ±`limitMs` 內。
    public static func clamp(_ ms: Int) -> Int {
        min(max(ms, -limitMs), limitMs)
    }

    public struct Result: Equatable, Sendable {
        /// 要寫入的逐曲偏移（毫秒），已夾在上下限內。
        public let offsetMs: Int
        /// 算出來的偏移超出上下限而被夾住（此時那一行並沒有真的對齊）。
        public let isClamped: Bool

        public init(offsetMs: Int, isClamped: Bool) {
            self.offsetMs = offsetMs
            self.isClamped = isClamped
        }
    }

    /// - Parameters:
    ///   - positionMs: 點擊當下的播放位置（毫秒）。播放中時位置會持續前進，呼叫端要用「點擊那一刻」的時鐘讀數。
    ///   - lineTimeMs: 被點那一行的原始時間（`LRCLine.timeMs`）。
    ///   - lrcOffsetMs: 檔內 `[offset:]`（`LyricsTimeline.lrcOffsetMs`）。
    public static func aligned(positionMs: Int, lineTimeMs: Int, lrcOffsetMs: Int = 0) -> Result {
        // 輸入先夾在 ±1e12 ms（約 31 年），三項相加減不會溢位。
        let bound = 1_000_000_000_000
        func tame(_ v: Int) -> Int { min(max(v, -bound), bound) }
        let raw = tame(lineTimeMs) - tame(lrcOffsetMs) - tame(positionMs)

        let (quotient, remainder) = raw.quotientAndRemainder(dividingBy: 10)
        let rounded = remainder > 0 ? (quotient + 1) * 10 : quotient * 10

        let clamped = clamp(rounded)
        return Result(offsetMs: clamped, isClamped: clamped != rounded)
    }

    /// 同上，播放位置以秒為單位（先四捨五入到最接近的毫秒）。位置不是有限數時回傳 nil。
    public static func aligned(position: TimeInterval, lineTimeMs: Int, lrcOffsetMs: Int = 0) -> Result? {
        guard position.isFinite else { return nil }
        let ms = (position * 1000).rounded()
        let limit = 1e15
        let positionMs = Int(min(max(ms, -limit), limit))
        return aligned(positionMs: positionMs, lineTimeMs: lineTimeMs, lrcOffsetMs: lrcOffsetMs)
    }
}
