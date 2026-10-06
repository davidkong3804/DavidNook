import Foundation

/// 影片功能的設定鍵與預設值（純常數；App 端的 `Defaults.Keys` 引用這裡，所以名稱與預設值有測試鎖定）。
public enum VideoCapsuleSettings {
    public static let enabledKey = "videoCapsuleEnabled"
    public static let widthKey = "videoCapsuleWidth"
    /// 釘選狀態（M-C 才使用；先保留鍵）。
    public static let pinnedKey = "videoCapsulePinned"

    public static let defaultEnabled = true
    public static let defaultPinned = false

    /// 影片寬度（pt）：展開瀏海內影片區塊的寬度。
    public static let widthRange: ClosedRange<Double> = 160...480
    public static let defaultWidth: Double = 320

    public static func clampedWidth(_ value: Double) -> Double {
        guard !value.isNaN else { return defaultWidth }
        return min(max(value, widthRange.lowerBound), widthRange.upperBound)
    }
}
