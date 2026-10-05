import SwiftUI
import XCTest
@testable import DavidNookUI

/// Home 分頁（Now Playing＋歌詞）的版面度量：在 560–900 寬、85%–130% 高的每一種組合下都不得重疊或超出。
final class NotchHomeMetricsTests: XCTestCase {
    private let ear: CGFloat = 19

    private func metrics(width: Double, scale: Double, header: CGFloat = 38, lyrics: Bool = true) -> NotchHomeMetrics {
        let sizing = NotchSizing(width: width, heightScale: scale)
        return NotchHomeMetrics(
            contentWidth: sizing.contentWidth(earInset: ear),
            bodyHeight: sizing.bodyHeight(for: .home, headerHeight: header),
            showsLyrics: lyrics
        )
    }

    func testDefaultSizeKeepsTheFamiliarProportions() {
        let m = metrics(width: 720, scale: 1.0)
        XCTAssertEqual(m.contentWidth, 658)
        XCTAssertEqual(m.bodyHeight, 126)
        XCTAssertEqual(m.density, .regular)
        XCTAssertEqual(m.artSize, 120)
        XCTAssertEqual(m.lyricsVisibleLines, 5)
        XCTAssertEqual(m.lyricsHeight, 124)
    }

    func testMinimumSizeDropsToFourLyricLinesAndCompactControls() {
        let m = metrics(width: 560, scale: 0.85)
        XCTAssertEqual(m.contentWidth, 498)
        XCTAssertEqual(m.bodyHeight, 100)
        XCTAssertEqual(m.density, .compact)
        XCTAssertEqual(m.lyricsVisibleLines, 4)
        XCTAssertEqual(m.lyricsHeight, 100)
        XCTAssertEqual(m.artSize, 94)
    }

    func testMaximumSizeShowsMoreLyricLinesAndABiggerCover() {
        let m = metrics(width: 900, scale: 1.30)
        XCTAssertEqual(m.density, .regular)
        XCTAssertGreaterThan(m.lyricsVisibleLines, 5)
        XCTAssertLessThanOrEqual(m.lyricsVisibleLines, 7)
        XCTAssertGreaterThan(m.artSize, 120)
        XCTAssertLessThanOrEqual(m.artSize, 144)
    }

    func testNothingOverlapsOrOverflowsAtAnySize() {
        for width in stride(from: 560.0, through: 900.0, by: 10) {
            for scale in stride(from: 0.85, through: 1.30, by: 0.05) {
                for header in [38.0, 41.0, 45.0, 60.0] {
                    for lyrics in [true, false] {
                        let m = metrics(width: width, scale: scale, header: CGFloat(header), lyrics: lyrics)
                        let tag = "w\(width) s\(scale) h\(header) lyrics=\(lyrics)"
                        // 水平：封面區塊＋控制區＋歌詞＋間距不超過內容寬。
                        XCTAssertLessThanOrEqual(m.horizontalExtent, m.contentWidth + 0.001, tag)
                        XCTAssertGreaterThanOrEqual(m.controlsWidth, NotchHomeMetrics.controlsMinimumWidth, tag)
                        // 垂直：每一塊都放得進內容區。
                        XCTAssertLessThanOrEqual(m.artSize + 2 * m.artPadding, m.bodyHeight + 0.001, tag)
                        XCTAssertLessThanOrEqual(m.lyricsHeight, m.bodyHeight + 0.001, tag)
                        XCTAssertLessThanOrEqual(m.controlsMinimumHeight, m.bodyHeight + 0.001, tag)
                        XCTAssertGreaterThanOrEqual(m.lyricsVisibleLines, 3, tag)
                        XCTAssertGreaterThanOrEqual(m.bodyHeight, NotchSizing.minimumBodyHeight, tag)
                    }
                }
            }
        }
    }

    func testControlsFillTheRemainderWhenLyricsAreHidden() {
        let withLyrics = metrics(width: 720, scale: 1.0, lyrics: true)
        let without = metrics(width: 720, scale: 1.0, lyrics: false)
        XCTAssertEqual(without.lyricsWidth, 0)
        XCTAssertGreaterThan(without.controlsWidth, withLyrics.controlsWidth)
        XCTAssertEqual(without.horizontalExtent, without.contentWidth, accuracy: 0.001)
    }

    func testLyricsWidthStaysInReadableRange() {
        for width in stride(from: 560.0, through: 900.0, by: 10) {
            let m = metrics(width: width, scale: 1.0)
            XCTAssertGreaterThanOrEqual(m.lyricsWidth, NotchHomeMetrics.lyricsMinimumWidth)
            XCTAssertLessThanOrEqual(m.lyricsWidth, NotchHomeMetrics.lyricsMaximumWidth)
        }
    }

    func testDensityThreshold() {
        // 126（預設）→ 標準；100（最小）→ 精簡。
        XCTAssertEqual(NotchHomeMetrics(contentWidth: 658, bodyHeight: 126, showsLyrics: true).density, .regular)
        XCTAssertEqual(NotchHomeMetrics(contentWidth: 658, bodyHeight: 100, showsLyrics: true).density, .compact)
        XCTAssertEqual(NotchHomeMetrics(contentWidth: 658, bodyHeight: NotchHomeMetrics.regularControlsHeight + 4, showsLyrics: true).density, .regular)
        XCTAssertEqual(NotchHomeMetrics(contentWidth: 658, bodyHeight: NotchHomeMetrics.regularControlsHeight + 3, showsLyrics: true).density, .compact)
    }
}
