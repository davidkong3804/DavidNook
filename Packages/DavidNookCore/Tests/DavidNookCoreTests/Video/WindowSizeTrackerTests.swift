import CoreGraphics
import XCTest
@testable import DavidNookCore

/// 來源視窗大小（點）的追蹤：幀的 contentRect 單位與視窗大小不同（輸出像素／點），第一個樣本用來校準，
/// 之後只有真的縮放才更新——避免把像素值（480、1200）當成視窗點數汙染裁切的 sourceRect。
final class WindowSizeTrackerTests: XCTestCase {
    func testFirstSampleCalibratesAndDoesNotChangeSize() {
        var t = WindowSizeTracker(initial: CGSize(width: 800, height: 450))
        XCTAssertFalse(t.ingest(rawSize: CGSize(width: 480, height: 270)), "像素單位的第一個樣本只用來校準")
        XCTAssertEqual(t.size, CGSize(width: 800, height: 450))
    }

    func testPixelSizedSamplesNeverPolluteTheWindowSize() {
        var t = WindowSizeTracker(initial: CGSize(width: 800, height: 450))
        _ = t.ingest(rawSize: CGSize(width: 480, height: 270))
        // 編輯裁切時輸出 1200 px 寬：校準後仍換算回 800 pt。
        XCTAssertFalse(t.ingest(rawSize: CGSize(width: 480, height: 270)))
        let crop = NormalizedCropRect(x: 0, y: 0, width: 0.5, height: 0.5).sourceRect(in: t.size)
        XCTAssertEqual(crop.width, 400, accuracy: 0.001)
        XCTAssertEqual(crop.height, 225, accuracy: 0.001)
    }

    func testSamplesInPointsAreAcceptedAsIs() {
        var t = WindowSizeTracker(initial: CGSize(width: 800, height: 450))
        XCTAssertFalse(t.ingest(rawSize: CGSize(width: 800, height: 450)))
        XCTAssertFalse(t.ingest(rawSize: CGSize(width: 800.4, height: 450.3)), "1 pt 以內的抖動不算改變")
        XCTAssertTrue(t.ingest(rawSize: CGSize(width: 640, height: 360)))
        XCTAssertEqual(t.size, CGSize(width: 640, height: 360))
    }

    func testRealResizeIsTrackedAfterCalibration() {
        var t = WindowSizeTracker(initial: CGSize(width: 800, height: 450))
        _ = t.ingest(rawSize: CGSize(width: 400, height: 225))   // 校準：k = 2
        XCTAssertTrue(t.ingest(rawSize: CGSize(width: 300, height: 225)))
        XCTAssertEqual(t.size.width, 600, accuracy: 0.001)
        XCTAssertEqual(t.size.height, 450, accuracy: 0.001)
    }

    func testResetStartsOverWithNewKnownSize() {
        var t = WindowSizeTracker(initial: CGSize(width: 800, height: 450))
        _ = t.ingest(rawSize: CGSize(width: 480, height: 270))
        t.reset(to: CGSize(width: 1920, height: 1050))
        XCTAssertEqual(t.size, CGSize(width: 1920, height: 1050))
        XCTAssertFalse(t.ingest(rawSize: CGSize(width: 480, height: 262.5)), "重新校準")
        XCTAssertEqual(t.size, CGSize(width: 1920, height: 1050))
    }

    func testUnknownInitialSizeAdoptsFirstSample() {
        var t = WindowSizeTracker(initial: .zero)
        XCTAssertTrue(t.ingest(rawSize: CGSize(width: 640, height: 360)))
        XCTAssertEqual(t.size, CGSize(width: 640, height: 360))
    }

    func testInvalidSamplesAreIgnored() {
        var t = WindowSizeTracker(initial: CGSize(width: 800, height: 450))
        for bad in [CGSize.zero, CGSize(width: -1, height: 5), CGSize(width: CGFloat.nan, height: 5), CGSize(width: 5, height: CGFloat.infinity)] {
            XCTAssertFalse(t.ingest(rawSize: bad))
        }
        XCTAssertEqual(t.size, CGSize(width: 800, height: 450))
    }
}

extension WindowSizeTrackerTests {
    func testFirstSampleWithDifferentShapeIsARealResize() {
        var t = WindowSizeTracker(initial: CGSize(width: 800, height: 450))
        XCTAssertTrue(t.ingest(rawSize: CGSize(width: 600, height: 450)), "長寬比不同＝視窗被縮放，不是單位差異")
        XCTAssertEqual(t.size, CGSize(width: 600, height: 450))
    }
}
