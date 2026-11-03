import Foundation

/// 膠囊文字的染色結果（sRGB，0…1）。
public struct LyricsPillTintColor: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// 歌詞膠囊的文字顏色跟著專輯封面（蘋果風格）：把封面的平均色變成「黑色膠囊上讀得清楚的淡彩色」。
///
/// 做法：保留封面的色相，亮度拉到最高，飽和度夾在 0.30–0.70（偏灰的封面也看得出顏色、太鮮豔的封面不刺眼）；
/// 若這個色相在黑底上亮度不夠（藍、紫這類本來就暗的色相），再逐步降低飽和度，直到對比 ≥ 7:1（WCAG AAA）。
/// 幾乎沒有顏色的封面（灰、黑、白，飽和度 < 0.10）回傳 nil，膠囊維持原本的白字。
public enum LyricsPillTint {
    /// 封面飽和度低於這個值就不染色。
    public static let minimumSourceSaturation = 0.10
    public static let saturationRange: ClosedRange<Double> = 0.30...0.70
    /// 與黑色的最低對比。
    public static let minimumContrast = 7.0

    public static func textColor(red: Double, green: Double, blue: Double) -> LyricsPillTintColor? {
        guard red.isFinite, green.isFinite, blue.isFinite else { return nil }
        let r = min(max(red, 0), 1), g = min(max(green, 0), 1), b = min(max(blue, 0), 1)
        let (hue, saturation, _) = hsb(r, g, b)
        guard saturation >= minimumSourceSaturation else { return nil }

        var target = min(max(saturation, saturationRange.lowerBound), saturationRange.upperBound)
        while true {
            let color = rgb(hue: hue, saturation: target, brightness: 1)
            if contrastWithBlack(color) >= minimumContrast || target <= 0 { return color }
            target = max(target - 0.01, 0)
        }
    }

    /// 與黑色背景的 WCAG 對比（相對亮度＋0.05 的比值）。
    public static func contrastWithBlack(_ color: LyricsPillTintColor) -> Double {
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
        return (luminance + 0.05) / 0.05
    }

    private static func hsb(_ r: Double, _ g: Double, _ b: Double) -> (hue: Double, saturation: Double, brightness: Double) {
        let maximum = max(r, g, b), minimum = min(r, g, b)
        let delta = maximum - minimum
        guard maximum > 0, delta > 0 else { return (0, 0, maximum) }
        var hue: Double
        if maximum == r {
            hue = (g - b) / delta
        } else if maximum == g {
            hue = 2 + (b - r) / delta
        } else {
            hue = 4 + (r - g) / delta
        }
        hue /= 6
        if hue < 0 { hue += 1 }
        return (hue, delta / maximum, maximum)
    }

    private static func rgb(hue: Double, saturation: Double, brightness: Double) -> LyricsPillTintColor {
        let h = (hue - hue.rounded(.down)) * 6
        let sector = Int(h) % 6
        let f = h - Double(Int(h))
        let p = brightness * (1 - saturation)
        let q = brightness * (1 - saturation * f)
        let t = brightness * (1 - saturation * (1 - f))
        switch sector {
        case 0: return LyricsPillTintColor(red: brightness, green: t, blue: p)
        case 1: return LyricsPillTintColor(red: q, green: brightness, blue: p)
        case 2: return LyricsPillTintColor(red: p, green: brightness, blue: t)
        case 3: return LyricsPillTintColor(red: p, green: q, blue: brightness)
        case 4: return LyricsPillTintColor(red: t, green: p, blue: brightness)
        default: return LyricsPillTintColor(red: brightness, green: p, blue: q)
        }
    }
}
