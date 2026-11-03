import SwiftUI
import XCTest
@testable import DavidNookUI

/// 歌詞膠囊的文字顏色跟著專輯封面：封面平均色 → 黑色膠囊上讀得清楚的淡彩色。
@MainActor
final class LyricsPillTintTests: XCTestCase {

    /// HSB（0…1）→ RGB，測試用。
    private func rgb(h: Double, s: Double, v: Double) -> (r: Double, g: Double, b: Double) {
        let c = NSColor(hue: h, saturation: s, brightness: v, alpha: 1).usingColorSpace(.sRGB)!
        return (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
    }

    private func hue(of color: LyricsPillTintColor) -> Double {
        NSColor(red: color.red, green: color.green, blue: color.blue, alpha: 1).usingColorSpace(.sRGB)!.hueComponent.native
    }

    private func saturation(of color: LyricsPillTintColor) -> Double {
        NSColor(red: color.red, green: color.green, blue: color.blue, alpha: 1).usingColorSpace(.sRGB)!.saturationComponent.native
    }

    func testEveryHueGivesAReadableTintOnBlack() throws {
        for step in stride(from: 0.0, to: 1.0, by: 0.025) {
            let source = rgb(h: step, s: 0.8, v: 0.6)
            let tint = try XCTUnwrap(LyricsPillTint.textColor(red: source.r, green: source.g, blue: source.b), "hue \(step)")
            XCTAssertGreaterThanOrEqual(LyricsPillTint.contrastWithBlack(tint), 7, "hue \(step) 在黑底上對比不足")
        }
    }

    func testTintKeepsTheHueOfTheCover() throws {
        for step in stride(from: 0.0, to: 1.0, by: 0.05) {
            let source = rgb(h: step, s: 0.7, v: 0.5)
            let tint = try XCTUnwrap(LyricsPillTint.textColor(red: source.r, green: source.g, blue: source.b))
            let difference = abs(hue(of: tint) - step)
            XCTAssertLessThan(min(difference, 1 - difference), 0.02, "hue \(step)")
        }
    }

    func testTintIsAVisibleButSoftPastel() throws {
        // 太淡看不出顏色、太濃又刺眼：飽和度落在一個範圍內。
        for step in stride(from: 0.0, to: 1.0, by: 0.1) {
            for sourceSaturation in [0.25, 0.5, 1.0] {
                let source = rgb(h: step, s: sourceSaturation, v: 0.6)
                let tint = try XCTUnwrap(LyricsPillTint.textColor(red: source.r, green: source.g, blue: source.b))
                XCTAssertLessThanOrEqual(saturation(of: tint), 0.7 + 0.001)
            }
        }
        let mutedRed = rgb(h: 0, s: 0.25, v: 0.5)
        let tint = try XCTUnwrap(LyricsPillTint.textColor(red: mutedRed.r, green: mutedRed.g, blue: mutedRed.b))
        XCTAssertGreaterThanOrEqual(saturation(of: tint), 0.25, "偏灰的封面也要看得出顏色")
    }

    func testGrayWhiteAndBlackCoversKeepTheDefaultText() {
        XCTAssertNil(LyricsPillTint.textColor(red: 0.5, green: 0.5, blue: 0.5))
        XCTAssertNil(LyricsPillTint.textColor(red: 1, green: 1, blue: 1))
        XCTAssertNil(LyricsPillTint.textColor(red: 0, green: 0, blue: 0))
        XCTAssertNil(LyricsPillTint.textColor(red: 0.52, green: 0.5, blue: 0.5), "幾乎沒有顏色的封面不染色")
    }

    func testOutOfRangeInputIsClamped() throws {
        XCTAssertNotNil(LyricsPillTint.textColor(red: 2, green: -1, blue: 0))
        let tint = try XCTUnwrap(LyricsPillTint.textColor(red: 2, green: -1, blue: 0))
        for value in [tint.red, tint.green, tint.blue] { XCTAssertTrue((0...1).contains(value)) }
        XCTAssertNil(LyricsPillTint.textColor(red: .nan, green: 0.2, blue: 0.2))
    }

    func testStyleCarriesTheTextColor() {
        let plain = LyricsPillStyle()
        var tinted = LyricsPillStyle()
        tinted.textColor = Color(red: 0.9, green: 0.7, blue: 0.7)
        XCTAssertNil(plain.textColor)
        XCTAssertNotEqual(plain, tinted)
    }

    // MARK: - 渲染（輸出 PNG 供人工檢視）

    func testRendersTintedCapsulesForSeveralCovers() throws {
        let covers: [(name: String, red: Double, green: Double, blue: Double)] = [
            ("red", 0.75, 0.20, 0.22), ("orange", 0.85, 0.55, 0.20), ("green", 0.25, 0.60, 0.35),
            ("blue", 0.20, 0.30, 0.80), ("purple", 0.50, 0.25, 0.70), ("gray", 0.5, 0.5, 0.5),
        ]
        var plainPNG: Data?
        for cover in covers {
            let tint = LyricsPillTint.textColor(red: cover.red, green: cover.green, blue: cover.blue)
            let style = LyricsPillStyle(textColor: tint.map { Color(red: $0.red, green: $0.green, blue: $0.blue) })
            let view = NotchBackdrop(size: CGSize(width: 300, height: 44)) {
                LyricsPillContent(text: "夜晚的車站裡貓正在睡覺", elapsed: 0, lineDuration: 4, style: style)
            }
            let image = try renderImage(view)
            try writeSnapshot(image, named: "pill-tint-\(cover.name)")
            if cover.name == "gray" { plainPNG = try pngData(image) }
            else { XCTAssertNotNil(tint, cover.name) }
        }
        let tintedRed = try pngData(renderImage(NotchBackdrop(size: CGSize(width: 300, height: 44)) {
            let t = LyricsPillTint.textColor(red: 0.75, green: 0.20, blue: 0.22)!
            LyricsPillContent(text: "夜晚的車站裡貓正在睡覺", elapsed: 0, lineDuration: 4,
                              style: LyricsPillStyle(textColor: Color(red: t.red, green: t.green, blue: t.blue)))
        }))
        XCTAssertNotEqual(tintedRed, plainPNG, "染色的膠囊和預設白字應該不同")
    }
}
