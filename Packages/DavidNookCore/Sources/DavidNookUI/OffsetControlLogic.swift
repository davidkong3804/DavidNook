import CoreGraphics
import DavidNookCore
import Foundation

// 對時控制的純邏輯（步進、滾輪累積、文字格式、點擊次數）。方向約定與 Core 相同：正值＝歌詞提早顯示、負值＝延後。

/// 一次微調的方向。
public enum OffsetNudge: Equatable, Sendable {
    /// 歌詞太晚出現 → 提早（偏移加大）。
    case advance
    /// 歌詞太早出現 → 延後（偏移減小）。
    case delay

    /// 偏移的變化量（毫秒）：細調 0.1 秒、粗調 0.5 秒。
    public func deltaMs(coarse: Bool) -> Int {
        let step = coarse ? LyricsOffsetFormat.coarseStepMs : LyricsOffsetFormat.fineStepMs
        return self == .advance ? step : -step
    }
}

extension LyricsOffsetFormat {
    /// 細調步長（毫秒）：0.1 秒。滾輪每一格、按鈕預設都是這一級。
    public static let fineStepMs = 100
    /// 粗調步長（毫秒）：0.5 秒。按住 Option 或 Shift 點按鈕，或開啟「粗調」。
    public static let coarseStepMs = 500

    /// 偏移加上變化量，夾在 ±60 秒內（與 Core 的 `LyricsOffsetAlignment.limitMs` 同一個上限）。
    public static func adjusted(_ offsetMs: Int, byMs delta: Int) -> Int {
        let (sum, overflow) = offsetMs.addingReportingOverflow(delta)
        return LyricsOffsetAlignment.clamp(overflow ? (delta > 0 ? Int.max : Int.min) : sum)
    }

    /// 偏移大小（不含方向）的秒數文字：100 ms 的倍數用一位小數（1.2），其餘用兩位（1.24、0.04）。
    public static func seconds(abs ms: Int) -> String {
        let magnitude = ms == Int.min ? Int.max : Swift.abs(ms)
        let value = Double(magnitude) / 1000
        return magnitude % 100 == 0 ? String(format: "%.1f", value) : String(format: "%.2f", value)
    }

    public enum Direction: Equatable, Sendable {
        case none, advanced, delayed
    }

    public static func direction(ofOffsetMs ms: Int) -> Direction {
        ms > 0 ? .advanced : (ms < 0 ? .delayed : .none)
    }
}

/// 滾輪／觸控板捲動 → 偏移變化量（毫秒）的累積器。
///
/// - 實體滑鼠滾輪（non-precise）：每個事件一格（0.1 秒），不看大小——快速轉動會產生很多事件，自然就走得快。
/// - 觸控板（precise）：累積捲動點數，每滿 `pointsPerStep` 點一格，餘數留到下一個事件；中途改變方向就丟掉餘數。
/// - 慣性（momentum）事件一律忽略，手指離開後不會繼續滑掉偏移。
///
/// 方向：`deltaY > 0`（內容往下捲，也就是未開自然捲動時滾輪向上）＝**延後**（回傳負值）；
/// `deltaY < 0`（內容往上捲，歌詞面板本身也是往上捲）＝**提早**（回傳正值）。
public struct OffsetWheelAccumulator: Sendable {
    /// 觸控板每一格需要的捲動點數。
    public static let pointsPerStep: Double = 10

    private var remainder: Double = 0

    public init() {}

    public mutating func reset() { remainder = 0 }

    /// - Returns: 這個事件造成的偏移變化量（毫秒，0 代表還沒累積到一格）。
    public mutating func consume(deltaY: Double, isPrecise: Bool, isMomentum: Bool) -> Int {
        guard !isMomentum, deltaY.isFinite, deltaY != 0 else { return 0 }
        let fine = LyricsOffsetFormat.fineStepMs

        guard isPrecise else {
            remainder = 0
            return deltaY > 0 ? -fine : fine
        }

        if remainder != 0, (remainder > 0) != (deltaY > 0) { remainder = 0 }
        remainder += deltaY
        let steps = (abs(remainder) / Self.pointsPerStep).rounded(.down)
        guard steps >= 1 else { return 0 }
        remainder -= (remainder > 0 ? 1 : -1) * steps * Self.pointsPerStep
        let signedSteps = Int(steps)
        return deltaY > 0 ? -signedSteps * fine : signedSteps * fine
    }
}

/// 「點歌詞對齊」的手勢選擇。
public enum LyricsLineAlignGesture {
    /// 對時控制展開時（使用者明確進入對時、畫面上有提示）單擊即可；平常只有雙擊才生效，避免誤觸。
    public static func tapCount(syncControlsOpen: Bool) -> Int {
        syncControlsOpen ? 1 : 2
    }
}

extension LyricsPanelMetrics {
    /// 對時控制展開時，歌詞可用的捲動區高度：面板高度扣掉控制卡片，但至少留兩行。
    public static func scrollRegionHeight(panelHeight: CGFloat, reserved: CGFloat, fontSize: CGFloat = 14) -> CGFloat {
        let floor = 2 * linePitch(fontSize: fontSize)
        guard reserved > 0 else { return panelHeight }
        return max(panelHeight - reserved, min(floor, panelHeight))
    }

    /// 捲動區縮小後的焦點位置：目前行放在「上面留一行」的位置（上一行、目前行、下一行都看得到），
    /// 區域太小時最多放到 60% 處。
    public static func reservedFocusFraction(regionHeight: CGFloat, fontSize: CGFloat = 14) -> CGFloat {
        guard regionHeight > 0 else { return 0.5 }
        let y = 2 + linePitch(fontSize: fontSize) * 1.5
        return min(max(y / regionHeight, 0.3), 0.6)
    }
}
