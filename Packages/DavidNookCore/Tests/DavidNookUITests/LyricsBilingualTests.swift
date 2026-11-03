import SwiftUI
import XCTest
@testable import DavidNookUI

/// 日文／韓文歌詞的中文對照：資料模型（原文＋翻譯）與面板離屏渲染。樣本皆為自編句子。
@MainActor
final class LyricsBilingualTests: XCTestCase {

    private let originals = [
        "夜の駅で猫が眠っている", "窓の外に小さな雨が降る", "", "明日はきっと晴れるだろう", "ひとりで歩く帰り道",
    ]
    private let translations = ["夜晚的車站裡貓正在睡覺", "窗外下著細細的小雨", "", "明天一定會放晴吧", "一個人走著回家的路"]

    // MARK: - 資料模型

    func testMakeAttachesTranslationsByIndex() {
        let lines = LyricsPanelLine.make(from: originals, translations: translations)
        XCTAssertEqual(lines.map(\.text), originals)
        XCTAssertEqual(lines.map(\.translation), ["夜晚的車站裡貓正在睡覺", "窗外下著細細的小雨", nil, "明天一定會放晴吧", "一個人走著回家的路"])
    }

    func testBlankTranslationBecomesNil() {
        let lines = LyricsPanelLine.make(from: ["a", "b"], translations: ["甲", "  "])
        XCTAssertEqual(lines.map(\.translation), ["甲", nil])
    }

    func testMismatchedTranslationCountIsIgnored() {
        let lines = LyricsPanelLine.make(from: originals, translations: ["甲"])
        XCTAssertTrue(lines.allSatisfy { $0.translation == nil })
    }

    func testNoTranslationsLeavesLinesLikeBefore() {
        XCTAssertEqual(LyricsPanelLine.make(from: originals, translations: nil), LyricsPanelLine.make(from: originals))
        XCTAssertTrue(LyricsPanelLine.make(from: originals).allSatisfy { $0.translation == nil })
    }

    func testBlankOriginalLineNeverCarriesATranslation() {
        let lines = LyricsPanelLine.make(from: ["", "b"], translations: ["不該出現", "乙"])
        XCTAssertNil(lines[0].translation)
        XCTAssertEqual(lines[1].translation, "乙")
    }

    // MARK: - 渲染

    private func render(_ lines: [LyricsPanelLine], name: String) throws -> Data {
        let view = NotchBackdrop(size: CGSize(width: 300, height: 170)) {
            LyricsPanelView(lines: lines, currentIndex: 1, status: .loaded, visibleLineCount: 5)
                .frame(width: 240)
        }
        let image = try renderImage(view)
        try writeSnapshot(image, named: name)
        return try pngData(image)
    }

    func testPanelRendersTranslationsBelowTheOriginal() throws {
        let plain = try render(LyricsPanelLine.make(from: originals), name: "lyrics-original-only")
        let bilingual = try render(LyricsPanelLine.make(from: originals, translations: translations), name: "lyrics-bilingual")
        XCTAssertFalse(bilingual.isEmpty)
        XCTAssertNotEqual(plain, bilingual, "有翻譯時面板應該多畫出翻譯行")
    }
}
