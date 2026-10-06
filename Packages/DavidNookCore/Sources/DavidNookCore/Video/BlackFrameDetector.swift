import Foundation

/// 偵測「持續全黑」的畫面（純邏輯，時間由呼叫端傳入）。
///
/// 受內容保護（DRM）的視窗會被系統擷取成黑畫面。本功能**不會也不應**繞過它；偵測到持續全黑時只顯示說明。
/// 輸入是每秒一次的平均亮度（0…255）：連續 `requiredDuration` 秒都低於 `blackThreshold` 才判為全黑；
/// 任何一個不夠黑的樣本立刻恢復；樣本之間隔太久（來源暫停、最小化）視為空窗，重新計時。
public struct BlackFrameDetector: Equatable, Sendable {
    /// 平均亮度低於此值（0…255 刻度）視為黑。
    public static let blackThreshold: Double = 2.0
    /// 連續黑多久（秒）才判定為受保護／全黑；轉場的短暫黑場遠短於此。
    public static let requiredDuration: TimeInterval = 3.0
    /// 兩個樣本相隔超過此秒數，不把空窗當成持續全黑。
    public static let maximumSampleGap: TimeInterval = 2.0

    public private(set) var isBlack = false
    private var darkSince: TimeInterval?
    private var lastDarkSample: TimeInterval?

    public init() {}

    public mutating func reset() {
        isBlack = false
        darkSince = nil
        lastDarkSample = nil
    }

    /// 餵入一個樣本，回傳目前是否判定為全黑。無效亮度（NaN、負值、無限大）與時間倒退的樣本會被忽略。
    @discardableResult
    public mutating func ingest(brightness: Double, at time: TimeInterval) -> Bool {
        guard brightness.isFinite, brightness >= 0, time.isFinite else { return isBlack }
        if let last = lastDarkSample, time < last { return isBlack }

        guard brightness < Self.blackThreshold else {
            isBlack = false
            darkSince = nil
            lastDarkSample = nil
            return false
        }
        if let last = lastDarkSample, time - last > Self.maximumSampleGap {
            darkSince = time
        } else if darkSince == nil {
            darkSince = time
        }
        lastDarkSample = time
        if let start = darkSince, time - start >= Self.requiredDuration {
            isBlack = true
        }
        return isBlack
    }

    /// 在 BGRA 緩衝上取 `grid × grid` 個格點的平均亮度（0…255，Rec.601 係數）；緩衝為空或尺寸無效回傳 nil。
    /// 只讀取、不保留、不記錄任何像素。
    public static func averageBrightness(bgra: [UInt8], width: Int, height: Int, bytesPerRow: Int, grid: Int) -> Double? {
        bgra.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return nil }
            return averageBrightness(baseAddress: base, byteCount: raw.count, width: width, height: height, bytesPerRow: bytesPerRow, grid: grid)
        }
    }

    public static func averageBrightness(
        baseAddress: UnsafeRawPointer, byteCount: Int, width: Int, height: Int, bytesPerRow: Int, grid: Int
    ) -> Double? {
        guard width > 0, height > 0, grid > 0, bytesPerRow >= width * 4,
              byteCount >= bytesPerRow * (height - 1) + width * 4 else { return nil }
        let p = baseAddress.assumingMemoryBound(to: UInt8.self)
        var sum = 0.0
        for gy in 0..<grid {
            let y = min(height - 1, (gy * height) / grid + height / (2 * grid))
            for gx in 0..<grid {
                let x = min(width - 1, (gx * width) / grid + width / (2 * grid))
                let i = y * bytesPerRow + x * 4
                sum += 0.114 * Double(p[i]) + 0.587 * Double(p[i + 1]) + 0.299 * Double(p[i + 2])
            }
        }
        return sum / Double(grid * grid)
    }
}
