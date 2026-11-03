import SwiftUI
import XCTest
@testable import DavidNookUI

/// 膠囊的雙語顯示：有中文翻譯時變兩行（原文＋較小的翻譯），寬度取兩行較寬者。
@MainActor
final class LyricsPillBilingualTests: XCTestCase {
    private typealias M = LyricsPillMetrics
    private let japanese = "夜の街を歩いていた"
    private let chinese = "我曾在夜晚的街道上行走"

    func testHeightGrowsOnlyWhenThereIsATranslation() {
        XCTAssertEqual(M.height(hasTranslation: false), M.height)
        XCTAssertGreaterThan(M.height(hasTranslation: true), M.height)
        XCTAssertEqual(M.height(hasTranslation: true), M.twoLineHeight)
    }

    func testTranslationFontIsSmallerButNeverTiny() {
        XCTAssertEqual(M.translationFontSize(for: 12), 10)
        XCTAssertEqual(M.translationFontSize(for: 11), 9)
        XCTAssertGreaterThanOrEqual(M.translationFontSize(for: 5), 9)
        XCTAssertEqual(M.translationFontSize(for: .nan), M.translationFontSize(for: M.defaultFontSize))
    }

    func testWorstCaseWithTwoLinesStillFitsTheWindows() {
        XCTAssertGreaterThanOrEqual(M.maximumBottomExtent,
                                    M.topOffset(notchBottom: M.maximumAssumedNotchBottom, dropDistance: 999) + M.twoLineHeight)
        XCTAssertLessThanOrEqual(M.maximumBottomExtent, NotchSizing.legacyClosedWindowSize.height - M.windowBottomPadding)
    }

    func testLineCarriesAnOptionalTranslation() {
        let plain = LyricsPillLine(index: 1, text: japanese, start: 0, end: 4)
        XCTAssertNil(plain.translation)
        let bilingual = LyricsPillLine(index: 1, text: japanese, start: 0, end: 4, translation: chinese)
        XCTAssertNotEqual(plain, bilingual)
        XCTAssertEqual(bilingual.translation, chinese)
    }

    func testSizeHasTwoLinesWhenTranslationIsPresentAndBlankCountsAsNone() {
        let style = LyricsPillStyle()
        let single = LyricsPillSizing.pillSize(text: japanese, translation: nil, style: style)
        let blank = LyricsPillSizing.pillSize(text: japanese, translation: "  ", style: style)
        let double = LyricsPillSizing.pillSize(text: japanese, translation: chinese, style: style)
        XCTAssertEqual(single.height, M.height)
        XCTAssertEqual(blank, single)
        XCTAssertEqual(double.height, M.twoLineHeight)
        XCTAssertEqual(single.width, LyricsPillSizing.pillWidth(text: japanese, style: style))
    }

    func testWidthFollowsTheWiderLine() {
        let style = LyricsPillStyle()
        let longTranslation = "我曾在夜晚的街道上一個人慢慢地走了很久很久"
        let narrow = LyricsPillSizing.pillSize(text: japanese, translation: "好", style: style)
        let wide = LyricsPillSizing.pillSize(text: japanese, translation: longTranslation, style: style)
        XCTAssertGreaterThan(wide.width, narrow.width)
        XCTAssertLessThanOrEqual(wide.width, style.maxWidth)
    }

    // MARK: - 渲染

    func testRendersSingleAndBilingualCapsules() throws {
        let japanese = self.japanese
        let chinese = self.chinese
        let style = LyricsPillStyle()
        func scene(_ translation: String?, elapsed: TimeInterval = 0) -> some View {
            let size = LyricsPillSizing.pillSize(text: japanese, translation: translation, style: style)
            return NotchBackdrop(size: CGSize(width: 340, height: 56)) {
                LyricsPillContent(text: japanese, translation: translation, elapsed: elapsed, lineDuration: 4, style: style)
                    .frame(width: size.width, height: size.height)
            }
        }
        let single = try renderImage(scene(nil))
        let double = try renderImage(scene(chinese))
        try writeSnapshot(single, named: "pill-bilingual-single")
        try writeSnapshot(double, named: "pill-bilingual-double")
        XCTAssertNotEqual(try pngData(single), try pngData(double))

        var tinted = style
        tinted.textColor = Color(red: 0.95, green: 0.7, blue: 0.7)
        let tintedImage = try renderImage(NotchBackdrop(size: CGSize(width: 340, height: 56)) {
            LyricsPillContent(text: japanese, translation: chinese, elapsed: 0, lineDuration: 4, style: tinted)
        })
        try writeSnapshot(tintedImage, named: "pill-bilingual-tinted")
        XCTAssertNotEqual(try pngData(tintedImage), try pngData(double))

        let long = "我曾在夜晚的街道上一個人慢慢地走了很久很久，直到路燈一盞一盞熄滅，天空慢慢亮起來"
        let early = try renderImage(NotchBackdrop(size: CGSize(width: 400, height: 56)) {
            LyricsPillContent(text: japanese, translation: long, elapsed: 0.2, lineDuration: 6, style: style)
        })
        let late = try renderImage(NotchBackdrop(size: CGSize(width: 400, height: 56)) {
            LyricsPillContent(text: japanese, translation: long, elapsed: 5, lineDuration: 6, style: style)
        })
        try writeSnapshot(early, named: "pill-bilingual-long-early")
        try writeSnapshot(late, named: "pill-bilingual-long-late")
        XCTAssertNotEqual(try pngData(early), try pngData(late), "翻譯行太長時也要跟著捲動")
    }
}
