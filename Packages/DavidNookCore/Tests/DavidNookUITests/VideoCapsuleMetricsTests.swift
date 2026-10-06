import CoreGraphics
import XCTest
@testable import DavidNookUI

/// 影片尺寸夾限，以及（給 M-C 用的）收合瀏海下方「影片膠囊＋歌詞膠囊」的堆疊版面。
/// 硬限制：視窗已固定（收合 640×210、展開涵蓋 948×346），膠囊只在其中畫，絕不改 NSWindow 大小。
final class VideoCapsuleMetricsTests: XCTestCase {
    private let ratios: [Double] = [.nan, -1, 0, 0.1, 0.25, 0.5, 0.75, 1, 4.0 / 3.0, 16.0 / 9.0, 2, 3, 10, .infinity]
    private let widths: [Double] = [.nan, -10, 0, 100, 159, 160, 161, 200, 320, 479, 480, 481, 1000, .infinity, -.infinity]

    func testRangeAndDefault() {
        XCTAssertEqual(VideoCapsuleMetrics.widthRange, 160...480)
        XCTAssertEqual(VideoCapsuleMetrics.defaultWidth, 320)
        XCTAssertEqual(VideoCapsuleMetrics.aspectRatioRange, 0.5...2)
        XCTAssertEqual(VideoCapsuleMetrics.fallbackAspectRatio, 16.0 / 9.0, accuracy: 1e-12)
    }

    func testAspectRatioIsSanitized() {
        XCTAssertEqual(VideoCapsuleMetrics.clampedAspectRatio(.nan), 16.0 / 9.0, accuracy: 1e-12)
        XCTAssertEqual(VideoCapsuleMetrics.clampedAspectRatio(0), 16.0 / 9.0, accuracy: 1e-12)
        XCTAssertEqual(VideoCapsuleMetrics.clampedAspectRatio(-3), 16.0 / 9.0, accuracy: 1e-12)
        XCTAssertEqual(VideoCapsuleMetrics.clampedAspectRatio(.infinity), 2)
        XCTAssertEqual(VideoCapsuleMetrics.clampedAspectRatio(0.1), 0.5)
        XCTAssertEqual(VideoCapsuleMetrics.clampedAspectRatio(10), 2)
        XCTAssertEqual(VideoCapsuleMetrics.clampedAspectRatio(1.25), 1.25)
    }

    func testDefaultWidth16by9() {
        let size = VideoCapsuleMetrics.requestedSize(width: 320, aspectRatio: 16.0 / 9.0)
        XCTAssertEqual(size.width, 320, accuracy: 1e-9)
        XCTAssertEqual(size.height, 180, accuracy: 1e-9)
    }

    func testRequestedSizeKeepsTheRatioAndStaysInRange() {
        for w in widths {
            for r in ratios {
                let size = VideoCapsuleMetrics.requestedSize(width: w, aspectRatio: r)
                XCTAssertLessThanOrEqual(size.height, VideoCapsuleMetrics.maximumHeight + 1e-9, "w\(w) r\(r)")
                XCTAssertGreaterThanOrEqual(size.width, VideoCapsuleMetrics.minimumWidth - 1e-9, "w\(w) r\(r)")
                XCTAssertEqual(size.width / size.height, VideoCapsuleMetrics.clampedAspectRatio(r), accuracy: 1e-6, "w\(w) r\(r)")
            }
        }
    }

    func testFitShrinksProportionallyAndNeverGrows() {
        let fitted = VideoCapsuleMetrics.fit(CGSize(width: 480, height: 270), into: CGSize(width: 400, height: 180))
        XCTAssertEqual(fitted.height, 180, accuracy: 1e-9)
        XCTAssertEqual(fitted.width, 320, accuracy: 1e-9)
        XCTAssertEqual(VideoCapsuleMetrics.fit(CGSize(width: 200, height: 100), into: CGSize(width: 400, height: 300)), CGSize(width: 200, height: 100))
        XCTAssertEqual(VideoCapsuleMetrics.fit(CGSize(width: 200, height: 100), into: CGSize(width: -5, height: 10)), .zero)
    }

    // MARK: - 堆疊版面（M-C 接線用）

    private let closed = NotchSizing.legacyClosedWindowSize

    func testLyricsAboveVideoWithSixPointGap() {
        let r = VideoCapsuleStack.layout(notchBottom: 32, dropDistance: 6, lyricsVisible: true, lyricsWidth: 300,
                                         videoWidth: 200, aspectRatio: 16.0 / 9.0, order: .lyricsAbove)
        let lyrics = try! XCTUnwrap(r.lyrics)
        let video = try! XCTUnwrap(r.video)
        XCTAssertEqual(lyrics.minY, 38)
        XCTAssertEqual(lyrics.height, LyricsPillMetrics.height)
        XCTAssertEqual(video.minY, lyrics.maxY + VideoCapsuleStack.gap)
        XCTAssertEqual(video.midX, closed.width / 2, accuracy: 1e-9)
        XCTAssertEqual(lyrics.midX, closed.width / 2, accuracy: 1e-9)
        XCTAssertEqual(video.width, 200, accuracy: 1e-9)
        XCTAssertEqual(video.height, 112.5, accuracy: 1e-9)
    }

    func testVideoMovesUpToTheLyricsSpotWhenLyricsAreHidden() {
        let r = VideoCapsuleStack.layout(notchBottom: 32, dropDistance: 6, lyricsVisible: false, lyricsWidth: 300,
                                         videoWidth: 200, aspectRatio: 16.0 / 9.0, order: .lyricsAbove)
        XCTAssertNil(r.lyrics)
        XCTAssertEqual(r.video?.minY, 38)
    }

    func testVideoAboveLyrics() {
        let r = VideoCapsuleStack.layout(notchBottom: 32, dropDistance: 6, lyricsVisible: true, lyricsWidth: 300,
                                         videoWidth: 200, aspectRatio: 16.0 / 9.0, order: .videoAbove)
        let video = try! XCTUnwrap(r.video)
        let lyrics = try! XCTUnwrap(r.lyrics)
        XCTAssertEqual(video.minY, 38)
        XCTAssertEqual(lyrics.minY, video.maxY + VideoCapsuleStack.gap)
    }

    func testTooLargeVideoIsScaledDownProportionally() {
        let r = VideoCapsuleStack.layout(notchBottom: 32, dropDistance: 6, lyricsVisible: true, lyricsWidth: 300,
                                         videoWidth: 480, aspectRatio: 16.0 / 9.0, order: .lyricsAbove)
        let video = try! XCTUnwrap(r.video)
        XCTAssertLessThan(video.width, 480)
        XCTAssertEqual(video.width / video.height, 16.0 / 9.0, accuracy: 1e-6)
    }

    func testNotDisplayedWhenTheScaledWidthFallsBelowTheMinimum() {
        // 最壞情況：瀏海底緣 60、下拉 40、歌詞膠囊在上 → 可用高度很小，16:9 會縮到寬 < 96。
        let r = VideoCapsuleStack.layout(notchBottom: 60, dropDistance: 40, lyricsVisible: true, lyricsWidth: 300,
                                         videoWidth: 320, aspectRatio: 16.0 / 9.0, order: .lyricsAbove)
        XCTAssertNotNil(r.lyrics)
        if let video = r.video { XCTAssertGreaterThanOrEqual(video.width, VideoCapsuleMetrics.minimumWidth) }
    }

    func testWorstCaseStaysInsideTheClosedAndCoveringWindows() {
        let covering = NotchSizing.coveringWindowSize
        XCTAssertEqual(covering, CGSize(width: 948, height: 346))
        let bottom = LyricsPillMetrics.windowBottomPadding
        var checked = 0
        for notchBottom in stride(from: 0.0, through: 60.0, by: 6) {
            for drop in stride(from: -8.0, through: 40.0, by: 6) {
                for lyricsVisible in [true, false] {
                    for order in [VideoCapsuleStack.Order.lyricsAbove, .videoAbove] {
                        for w in widths {
                            for ratio in ratios {
                                let tag = "nb\(notchBottom) d\(drop) l\(lyricsVisible) \(order) w\(w) r\(ratio)"
                                let r = VideoCapsuleStack.layout(
                                    notchBottom: CGFloat(notchBottom), dropDistance: CGFloat(drop), lyricsVisible: lyricsVisible,
                                    lyricsWidth: 360, videoWidth: w, aspectRatio: ratio, order: order
                                )
                                let rects = [r.video, r.lyrics].compactMap { $0 }
                                for rect in rects {
                                    XCTAssertGreaterThanOrEqual(rect.minX, 0, tag)
                                    XCTAssertGreaterThanOrEqual(rect.minY, 0, tag)
                                    XCTAssertLessThanOrEqual(rect.maxX, closed.width, tag)
                                    XCTAssertLessThanOrEqual(rect.maxY, closed.height - bottom + 1e-9, tag)
                                    XCTAssertLessThanOrEqual(rect.maxX, covering.width, tag)
                                    XCTAssertLessThanOrEqual(rect.maxY, covering.height, tag)
                                }
                                if let v = r.video, let l = r.lyrics {
                                    XCTAssertFalse(v.intersects(l), "重疊 \(tag)")
                                    let gap = order == .lyricsAbove ? v.minY - l.maxY : l.minY - v.maxY
                                    XCTAssertEqual(gap, VideoCapsuleStack.gap, accuracy: 1e-9, tag)
                                }
                                if let v = r.video {
                                    XCTAssertGreaterThanOrEqual(v.width, VideoCapsuleMetrics.minimumWidth - 1e-9, tag)
                                    XCTAssertEqual(v.width / v.height, VideoCapsuleMetrics.clampedAspectRatio(ratio), accuracy: 1e-6, tag)
                                }
                                checked += 1
                            }
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 10_000)
    }
}
