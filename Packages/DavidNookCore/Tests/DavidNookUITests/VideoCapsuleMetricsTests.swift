import CoreGraphics
import XCTest
@testable import DavidNookCore
@testable import DavidNookUI

/// 影片區塊的尺寸與版面夾限。
/// 硬限制：視窗已固定為涵蓋尺寸，影片區塊與「影片」分頁的形體只在其中畫，絕不改 NSWindow 大小。
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

    func testRequestedHeightNeverExceedsTheMaximumAndKeepsTheRatio() {
        for w in widths {
            for r in ratios {
                let size = VideoCapsuleMetrics.requestedSize(width: w, aspectRatio: r)
                XCTAssertLessThanOrEqual(size.height, VideoCapsuleMetrics.maximumHeight + 1e-9, "w\(w) r\(r)")
                XCTAssertGreaterThanOrEqual(size.width, VideoCapsuleMetrics.minimumWidth - 1e-9, "w\(w) r\(r)")
                XCTAssertEqual(size.width / size.height, VideoCapsuleMetrics.clampedAspectRatio(r), accuracy: 1e-6, "w\(w) r\(r)")
            }
        }
    }

    func testMaximumHeightFitsTheLargestPanelBody() {
        let largest = NotchSizing.maximumOpenSize.height
        XCTAssertEqual(VideoCapsuleMetrics.maximumHeight, largest - NotchSizing.minimumHeaderHeight - NotchSizing.bottomInset)
    }

    func testFitShrinksProportionallyAndNeverGrows() {
        let fitted = VideoCapsuleMetrics.fit(CGSize(width: 480, height: 270), into: CGSize(width: 400, height: 180))
        XCTAssertEqual(fitted.height, 180, accuracy: 1e-9)
        XCTAssertEqual(fitted.width, 320, accuracy: 1e-9)
        let same = VideoCapsuleMetrics.fit(CGSize(width: 200, height: 100), into: CGSize(width: 400, height: 300))
        XCTAssertEqual(same, CGSize(width: 200, height: 100))
        XCTAssertEqual(VideoCapsuleMetrics.fit(CGSize(width: 200, height: 100), into: CGSize(width: -5, height: 10)), .zero)
    }

    // MARK: - 展開面板內的版面

    func testDefaultLayoutIn720WideDefaultPanel() {
        let layout = VideoCapsuleMetrics.layout(width: 320, aspectRatio: 16.0 / 9.0, sizing: NotchSizing(), headerHeight: 38, earInset: 19)
        XCTAssertEqual(layout.videoSize.width, 320, accuracy: 1e-9)
        XCTAssertEqual(layout.videoSize.height, 180, accuracy: 1e-9)
        XCTAssertEqual(layout.panelSize, CGSize(width: 720, height: 232), "預設寬度時面板維持剪貼簿同高")
    }

    func testPanelGrowsToHoldALargeVideoWithinTheCoveringWindow() {
        let layout = VideoCapsuleMetrics.layout(width: 400, aspectRatio: 16.0 / 9.0, sizing: NotchSizing(), headerHeight: 38, earInset: 19)
        XCTAssertEqual(layout.videoSize.height, 225, accuracy: 1e-9)
        XCTAssertEqual(layout.panelSize.height, 38 + 225 + NotchSizing.bottomInset, accuracy: 1)
        XCTAssertGreaterThan(layout.panelSize.height, 232)
        XCTAssertLessThanOrEqual(layout.panelSize.height, NotchSizing.maximumOpenSize.height)
    }

    func testWorstCaseStaysInsideTheOpenPanelAndTheCoveringWindow() {
        let window = NotchSizing.coveringWindowSize
        XCTAssertEqual(window, CGSize(width: 948, height: 346), "視窗涵蓋尺寸不得因影片分頁而改變")
        for panelWidth in stride(from: 560.0, through: 900.0, by: 20) {
            for scale in stride(from: 0.85, through: 1.30, by: 0.05) {
                for header in [38.0, 41.0, 50.0, 60.0] {
                    let sizing = NotchSizing(width: panelWidth, heightScale: scale)
                    for w in widths {
                        for r in ratios {
                            let tag = "pw\(panelWidth) s\(scale) h\(header) w\(w) r\(r)"
                            let l = VideoCapsuleMetrics.layout(width: w, aspectRatio: r, sizing: sizing, headerHeight: CGFloat(header), earInset: 19)
                            // 影片區塊在內容區之內（寬扣掉右側工具列）。
                            XCTAssertLessThanOrEqual(l.videoSize.width, l.availableWidth + 1e-9, tag)
                            XCTAssertLessThanOrEqual(l.videoSize.height, l.bodyHeight + 1e-9, tag)
                            XCTAssertGreaterThanOrEqual(l.videoSize.width, VideoCapsuleMetrics.minimumWidth - 1e-9, tag)
                            XCTAssertEqual(l.videoSize.width / l.videoSize.height, VideoCapsuleMetrics.clampedAspectRatio(r), accuracy: 1e-6, tag)
                            // 面板形體在涵蓋視窗內（含下方陰影）。
                            XCTAssertLessThanOrEqual(l.panelSize.width, window.width, tag)
                            XCTAssertLessThanOrEqual(l.panelSize.height + NotchSizing.shadowPadding, window.height, tag)
                            XCTAssertEqual(l.panelSize.height, CGFloat(header) + l.bodyHeight + NotchSizing.bottomInset, accuracy: 1e-9, tag)
                            XCTAssertGreaterThanOrEqual(l.bodyHeight, NotchSizing.minimumBodyHeight, tag)
                        }
                    }
                }
            }
        }
    }

    func testVideoPanelAddsNoNewWindowGrowth() {
        // 新增 .video 分頁後，各分頁在所有可調上限下的最大尺寸與舊值相同。
        XCTAssertEqual(NotchSizing.maximumOpenSize, CGSize(width: 900, height: 302))
        let s = NotchSizing()
        XCTAssertEqual(s.openSize(for: .video), CGSize(width: 720, height: 232))
        XCTAssertEqual(s.openSize(for: .video, videoContentHeight: 10), CGSize(width: 720, height: 232), "內容小於預設高度時不縮")
        XCTAssertEqual(s.openSize(for: .video, videoContentHeight: 1000).height, 302, "內容再大也夾在最大面板高度")
        XCTAssertEqual(s.openSize(for: .clipboard, videoContentHeight: 1000).height, 232, "videoContentHeight 只影響影片分頁")
    }
}
