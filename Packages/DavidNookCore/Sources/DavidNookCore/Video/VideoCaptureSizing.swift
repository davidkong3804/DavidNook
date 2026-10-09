import CoreGraphics
import Foundation

/// 擷取串流的輸出計畫：像素尺寸與更新率。
public struct VideoCapturePlan: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var framesPerSecond: Int

    public init(width: Int, height: Int, framesPerSecond: Int) {
        self.width = width; self.height = height; self.framesPerSecond = framesPerSecond
    }
}

/// 擷取輸出尺寸跟著「顯示大小」走（純邏輯）。
///
/// - 浮動視窗（釘選）：寬 = 視窗寬 pt × 螢幕 scale，夾在 480…1920 px；高度（依來源比例）不超過 1080；30 fps。
/// - 封面槽（未釘選）：寬 = 槽寬 pt × scale，夾在 160…480 px 以省 GPU；20 fps。
/// - 寬度以 8 px 為階梯、高度取偶數；縮放浮動視窗時只有目標變動 ≥ 10%（或更新率／長寬比改變）才需要重設串流設定。
public enum VideoCaptureSizing {
    public enum Mode: Equatable, Sendable { case slot, floating }

    public static let floatingWidthRange = 480...1920
    public static let slotWidthRange = 160...480
    public static let maximumHeight = 1080
    public static let widthStep = 8
    public static let reconfigureThreshold = 0.10

    public static func plan(mode: Mode, displayWidthPoints: Double, scale: Double, aspectRatio: Double) -> VideoCapturePlan {
        let range = mode == .floating ? floatingWidthRange : slotWidthRange
        let ratio = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 16.0 / 9.0
        let s = scale.isFinite && scale >= 1 ? min(scale, 4) : 2
        var raw = displayWidthPoints.isFinite && displayWidthPoints > 0 ? displayWidthPoints * s : Double(range.lowerBound)
        raw = min(max(raw, Double(range.lowerBound)), Double(range.upperBound))
        // 高度上限：寬度跟著降（可低於下限；直式來源會是這樣）。
        raw = min(raw, Double(maximumHeight) * ratio)
        var width = max(widthStep * 2, Int((raw / Double(widthStep)).rounded(.down)) * widthStep)
        // 量化用 round 會讓寬度略微超過上限，所以先 floor 再看是否更接近下一階（不超過上限時）。
        let up = width + widthStep
        if Double(up) - raw < raw - Double(width), up <= range.upperBound, Double(up) / ratio <= Double(maximumHeight) { width = up }
        var height = even(Double(width) / ratio)
        if height > maximumHeight {
            width = max(widthStep * 2, Int((Double(maximumHeight) * ratio / Double(widthStep)).rounded(.down)) * widthStep)
            height = min(even(Double(width) / ratio), maximumHeight)
        }
        return VideoCapturePlan(width: width, height: height, framesPerSecond: mode == .floating ? 30 : 20)
    }

    private static func even(_ value: Double) -> Int {
        max(2, Int((value / 2).rounded()) * 2)
    }

    /// 是否需要對進行中的串流呼叫 `updateConfiguration`。
    public static func shouldReconfigure(current: VideoCapturePlan?, target: VideoCapturePlan) -> Bool {
        guard let current else { return true }
        if current.framesPerSecond != target.framesPerSecond { return true }
        guard current.width > 0, current.height > 0 else { return true }
        let widthChange = abs(Double(target.width - current.width)) / Double(current.width)
        if widthChange >= reconfigureThreshold { return true }
        // 長寬比改變（裁切、來源視窗縮放）：高度相對寬度的比例差超過 3%。
        let currentRatio = Double(current.width) / Double(current.height)
        let targetRatio = Double(target.width) / Double(target.height)
        return abs(targetRatio - currentRatio) / currentRatio > 0.03
    }
}
