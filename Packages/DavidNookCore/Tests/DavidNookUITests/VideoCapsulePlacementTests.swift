import CoreGraphics
import DavidNookCore
import XCTest
@testable import DavidNookUI

/// M-C：釘選影片膠囊在收合視窗內的位置（單獨／與歌詞膠囊並存）、尺寸夾限、圓角。
final class VideoCapsulePlacementTests: XCTestCase {
    private let closed = NotchSizing.legacyClosedWindowSize
    private let covering = NotchSizing.coveringWindowSize

    private func rect(visible: Bool = true, notchBottom: CGFloat = 32, drop: CGFloat = 6, lyrics: Bool,
                      width: Double = 320, ratio: Double = 16.0 / 9.0) -> CGRect? {
        VideoCapsulePlacement.rect(isVisible: visible, notchBottom: notchBottom, dropDistance: drop, lyricsVisible: lyrics,
                                   videoWidth: width, aspectRatio: ratio)
    }

    func testHiddenHasNoRect() {
        XCTAssertNil(rect(visible: false, lyrics: false))
        XCTAssertNil(rect(visible: false, lyrics: true))
    }

    func testAloneSitsWhereTheLyricsPillWould() {
        let r = try! XCTUnwrap(rect(lyrics: false))
        XCTAssertEqual(r.minY, LyricsPillMetrics.topOffset(notchBottom: 32, dropDistance: 6), accuracy: 0.001)
        // 收合視窗 210 − 底部 8 − 上緣 38 = 164 高放不下 320×180，等比縮成 291.6×164。
        XCTAssertEqual(r.size.height, 164, accuracy: 0.001)
        XCTAssertEqual(r.size.width, 164 * 16.0 / 9.0, accuracy: 0.001)
        XCTAssertEqual(r.midX, closed.width / 2, accuracy: 0.001)
    }

    func testWithLyricsItSitsBelowWithTheStackGap() {
        let top = LyricsPillMetrics.topOffset(notchBottom: 32, dropDistance: 6)
        let r = try! XCTUnwrap(rect(lyrics: true, width: 200))
        XCTAssertEqual(r.minY, top + LyricsPillMetrics.height + VideoCapsuleStack.gap, accuracy: 0.001)
    }

    func testLyricsAppearingMovesItDownByExactlyOneLyricsBlock() {
        let alone = try! XCTUnwrap(rect(lyrics: false, width: 200))
        let with = try! XCTUnwrap(rect(lyrics: true, width: 200))
        XCTAssertEqual(with.minY - alone.minY, LyricsPillMetrics.height + VideoCapsuleStack.gap, accuracy: 0.001)
        XCTAssertEqual(with.size, alone.size)
    }

    func testSizeFollowsTheSliderAndAspectRatio() {
        let minR = try! XCTUnwrap(rect(lyrics: false, width: 160))
        let midR = try! XCTUnwrap(rect(lyrics: false, width: 240))
        XCTAssertEqual(minR.width, 160, accuracy: 0.001)
        XCTAssertGreaterThan(midR.width, minR.width)
        // 超出可用高度的設定一律縮成同一個最大尺寸（不溢出）。
        let big1 = try! XCTUnwrap(rect(lyrics: false, width: 400))
        let big2 = try! XCTUnwrap(rect(lyrics: false, width: 480))
        XCTAssertEqual(big1.size.width, big2.size.width, accuracy: 0.001)
        let tall = try! XCTUnwrap(rect(lyrics: false, width: 320, ratio: 0.75))
        XCTAssertLessThan(tall.width, tall.height)
        // 很窄的直向影片縮到寬 < 96 就不顯示（絕不溢出）。
        XCTAssertNil(rect(lyrics: false, width: 320, ratio: 0.5))
    }

    func testOutOfRangeSettingsAreClamped() {
        for width in [-5.0, 0, 1, 159, 481, 5000, .nan, .infinity] {
            for ratio in [Double.nan, 0, -1, 0.01, 100, .infinity] {
                for lyrics in [false, true] {
                    guard let r = rect(lyrics: lyrics, width: width, ratio: ratio) else { continue }
                    XCTAssertTrue(r.width.isFinite && r.height.isFinite && r.minY.isFinite, "\(width) \(ratio)")
                    XCTAssertGreaterThanOrEqual(r.width, VideoCapsuleMetrics.minimumWidth - 0.001)
                    XCTAssertLessThanOrEqual(r.width, 480 + 0.001)
                }
            }
        }
    }

    /// 窮舉：不論歌詞有無、下拉距離、瀏海底緣、滑桿與長寬比，膠囊必在收合視窗（扣底部 8）與涵蓋視窗內，且與歌詞膠囊不重疊。
    func testWorstCaseStaysInsideTheClosedAndCoveringWindows() {
        var checked = 0
        for notchBottom in stride(from: CGFloat(0), through: 60, by: 6) {
            for drop in stride(from: CGFloat(-8), through: 40, by: 4) {
                for lyrics in [false, true] {
                    for width in stride(from: 160.0, through: 480.0, by: 40) {
                        for ratio in [0.5, 0.75, 1, 4.0 / 3, 16.0 / 9, 2] {
                            guard let r = rect(notchBottom: notchBottom, drop: drop, lyrics: lyrics, width: width, ratio: ratio) else { continue }
                            checked += 1
                            let inner = CGRect(x: 0, y: 0, width: closed.width, height: closed.height - LyricsPillMetrics.windowBottomPadding)
                            XCTAssertTrue(inner.insetBy(dx: -0.001, dy: -0.001).contains(r), "closed \(r) nb=\(notchBottom) d=\(drop) l=\(lyrics)")
                            XCTAssertTrue(CGRect(origin: .zero, size: covering).contains(r), "covering \(r)")
                            if lyrics {
                                let lyricsBottom = LyricsPillMetrics.topOffset(notchBottom: notchBottom, dropDistance: drop) + LyricsPillMetrics.height
                                XCTAssertGreaterThanOrEqual(r.minY, lyricsBottom + VideoCapsuleStack.gap - 0.001, "overlaps lyrics")
                            }
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 1000)
    }

    func testCornerRadiusIsClampedAndFitsTheShortSide() {
        for size in [CGSize(width: 96, height: 54), CGSize(width: 480, height: 270), CGSize(width: 135, height: 270), CGSize(width: 270, height: 135)] {
            let c = VideoCapsuleMetrics.cornerRadius(for: size)
            XCTAssertGreaterThanOrEqual(c, 8)
            XCTAssertLessThanOrEqual(c, 16)
            XCTAssertLessThanOrEqual(c * 2, min(size.width, size.height))
        }
        XCTAssertEqual(VideoCapsuleMetrics.cornerRadius(for: .zero), 8)
    }
}
