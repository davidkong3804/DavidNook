import CoreGraphics
import XCTest
@testable import DavidNookCore

/// 相對視窗的正規化裁切矩形（0…1、原點左上、y 向下）。
final class NormalizedCropRectTests: XCTestCase {
    func testFullWindow() {
        XCTAssertTrue(NormalizedCropRect.full.isFullWindow)
        XCTAssertTrue(NormalizedCropRect(x: 0.002, y: 0, width: 0.995, height: 1).isFullWindow, "幾乎整個視窗視為沒裁切")
        XCTAssertFalse(NormalizedCropRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8).isFullWindow)
    }

    func testSanitizedClampsIntoTheUnitSquare() {
        let r = NormalizedCropRect(x: -0.5, y: 0.9, width: 2, height: 0.5).sanitized
        XCTAssertEqual(r.width, 1, accuracy: 1e-9)
        XCTAssertEqual(r.x, 0, accuracy: 1e-9)
        XCTAssertEqual(r.height, 0.5, accuracy: 1e-9)
        XCTAssertEqual(r.y, 0.5, accuracy: 1e-9, "y + height 不得超出 1")
        let tiny = NormalizedCropRect(x: 0.5, y: 0.5, width: 0, height: -3).sanitized
        XCTAssertEqual(tiny.width, NormalizedCropRect.minimumSide, accuracy: 1e-9)
        XCTAssertEqual(tiny.height, NormalizedCropRect.minimumSide, accuracy: 1e-9)
    }

    func testSanitizedHandlesNonFiniteAsFull() {
        for bad in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(NormalizedCropRect(x: bad, y: 0, width: 0.5, height: 0.5).sanitized, .full)
            XCTAssertEqual(NormalizedCropRect(x: 0, y: 0, width: bad, height: 0.5).sanitized, .full)
        }
    }

    func testSanitizedStaysInsideForManyInputs() {
        for x in stride(from: -1.0, through: 2.0, by: 0.25) {
            for w in stride(from: -1.0, through: 2.0, by: 0.25) {
                let r = NormalizedCropRect(x: x, y: x, width: w, height: w).sanitized
                XCTAssertGreaterThanOrEqual(r.x, 0); XCTAssertGreaterThanOrEqual(r.y, 0)
                XCTAssertLessThanOrEqual(r.x + r.width, 1 + 1e-9); XCTAssertLessThanOrEqual(r.y + r.height, 1 + 1e-9)
                XCTAssertGreaterThanOrEqual(r.width, NormalizedCropRect.minimumSide - 1e-9)
            }
        }
    }

    func testAspectRatioUsesTheWindowShape() throws {
        let r = NormalizedCropRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
        XCTAssertEqual(try XCTUnwrap(r.aspectRatio(windowSize: CGSize(width: 1600, height: 900))), 1600.0 / 900.0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(r.aspectRatio(windowSize: CGSize(width: 800, height: 800))), 1, accuracy: 1e-9)
        let wide = NormalizedCropRect(x: 0, y: 0.2, width: 1, height: 0.5)
        XCTAssertEqual(try XCTUnwrap(wide.aspectRatio(windowSize: CGSize(width: 1000, height: 1000))), 2, accuracy: 1e-9)
        XCTAssertNil(r.aspectRatio(windowSize: .zero))
        XCTAssertNil(r.aspectRatio(windowSize: CGSize(width: .nan, height: 10)))
    }

    /// SCStreamConfiguration.sourceRect：單位 pt、視窗擷取時相對視窗（左上為原點、y 向下；標頭未明說原點，見設計文件，需真機驗證）。
    func testSourceRectIsInWindowPoints() {
        let r = NormalizedCropRect(x: 0.25, y: 0.1, width: 0.5, height: 0.6)
        XCTAssertEqual(r.sourceRect(in: CGSize(width: 1000, height: 500)), CGRect(x: 250, y: 50, width: 500, height: 300))
    }

    func testStorageRoundTrip() throws {
        let r = NormalizedCropRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        XCTAssertEqual(NormalizedCropRect(array: r.asArray), r)
        XCTAssertNil(NormalizedCropRect(array: [0.1, 0.2]))
        XCTAssertNil(NormalizedCropRect(array: [0, 0, .nan, 1]))
    }
}
