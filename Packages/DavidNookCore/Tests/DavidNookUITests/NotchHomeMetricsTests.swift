import SwiftUI
import XCTest
@testable import DavidNookCore
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

    // MARK: - 封面槽顯示影片時加寬

    func testNoVideoKeepsTheSquareCoverSlot() {
        let m = NotchHomeMetrics(contentWidth: 658, bodyHeight: 126, showsLyrics: true)
        XCTAssertEqual(m.artWidth, m.artSize)
        XCTAssertEqual(m.artBlockWidth, m.artBlockSize)
    }

    func testLandscapeVideoWidensTheSlotWithoutSqueezingControlsOrLyrics() {
        let m = NotchHomeMetrics(contentWidth: 658, bodyHeight: 126, showsLyrics: true, artAspectRatio: 16.0 / 9.0)
        XCTAssertEqual(m.artSize, 120)
        XCTAssertEqual(m.artWidth, 213)
        XCTAssertGreaterThanOrEqual(m.controlsWidth, NotchHomeMetrics.controlsMinimumWidth)
        XCTAssertGreaterThanOrEqual(m.lyricsWidth, NotchHomeMetrics.lyricsMinimumWidth)
        XCTAssertLessThanOrEqual(m.horizontalExtent, m.contentWidth + 0.001)
    }

    func testPortraitOrSquareVideoKeepsTheSquareSlot() {
        for ratio in [0.5, 0.75, 1.0] {
            let m = NotchHomeMetrics(contentWidth: 658, bodyHeight: 126, showsLyrics: true, artAspectRatio: ratio)
            XCTAssertEqual(m.artWidth, m.artSize, "ratio \(ratio)")
        }
    }

    func testSettingsWidthCapsTheSlot() {
        let narrow = NotchHomeMetrics(contentWidth: 658, bodyHeight: 126, showsLyrics: true, artAspectRatio: 16.0 / 9.0, videoMaximumWidth: 160)
        XCTAssertEqual(narrow.artWidth, 160)
        let tiny = NotchHomeMetrics(contentWidth: 658, bodyHeight: 126, showsLyrics: true, artAspectRatio: 16.0 / 9.0, videoMaximumWidth: 10)
        XCTAssertEqual(tiny.artWidth, 160, "設定值先夾到 160…480")
        XCTAssertGreaterThanOrEqual(tiny.artWidth, tiny.artSize)
    }

    func testWideningNeverBreaksTheLayoutAtAnySizeRatioOrCap() {
        let ratios: [Double?] = [nil, .nan, -1, 0, 0.5, 1, 4.0 / 3.0, 16.0 / 9.0, 2, 3, 10, .infinity]
        let caps: [Double] = [.nan, -5, 0, 160, 240, 320, 480, 1000, .infinity]
        for width in stride(from: 560.0, through: 900.0, by: 10) {
            for scale in stride(from: 0.85, through: 1.30, by: 0.05) {
                for header in [38.0, 60.0] {
                    for lyrics in [true, false] {
                        let sizing = NotchSizing(width: width, heightScale: scale)
                        let cw = sizing.contentWidth(earInset: ear)
                        let bh = sizing.bodyHeight(for: .home, headerHeight: CGFloat(header))
                        for ratio in ratios {
                            for cap in caps {
                                let tag = "w\(width) s\(scale) h\(header) l\(lyrics) r\(String(describing: ratio)) c\(cap)"
                                let m = NotchHomeMetrics(contentWidth: cw, bodyHeight: bh, showsLyrics: lyrics, artAspectRatio: ratio, videoMaximumWidth: cap)
                                XCTAssertLessThanOrEqual(m.horizontalExtent, cw + 0.001, tag)
                                XCTAssertGreaterThanOrEqual(m.controlsWidth, NotchHomeMetrics.controlsMinimumWidth - 0.001, tag)
                                if lyrics { XCTAssertGreaterThanOrEqual(m.lyricsWidth, NotchHomeMetrics.lyricsMinimumWidth - 0.001, tag) }
                                XCTAssertLessThanOrEqual(m.artSize + 2 * m.artPadding, bh + 0.001, tag)
                                XCTAssertGreaterThanOrEqual(m.artWidth, m.artSize, tag)
                                XCTAssertLessThanOrEqual(m.artWidth, max(m.artSize, CGFloat(VideoCapsuleSettings.clampedWidth(cap))) + 0.001, tag)
                                if ratio == nil { XCTAssertEqual(m.artWidth, m.artSize, tag) }
                            }
                        }
                    }
                }
            }
        }
    }
}

