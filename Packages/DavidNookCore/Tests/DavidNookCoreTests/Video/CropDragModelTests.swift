import XCTest
@testable import DavidNookCore

/// 裁切視窗的拖曳邏輯（純函式）：點在邊角＝縮放、點在框內＝移動、點在框外＝新框。
final class CropDragModelTests: XCTestCase {
    private let box = NormalizedCropRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)

    private func p(_ x: Double, _ y: Double) -> CropPoint { CropPoint(x: x, y: y) }

    func testHitTest() {
        XCTAssertEqual(CropDragModel.begin(at: p(0.2, 0.2), current: box).kind, .resize(.topLeft))
        XCTAssertEqual(CropDragModel.begin(at: p(0.6, 0.6), current: box).kind, .resize(.bottomRight))
        XCTAssertEqual(CropDragModel.begin(at: p(0.4, 0.2), current: box).kind, .resize(.top))
        XCTAssertEqual(CropDragModel.begin(at: p(0.6, 0.4), current: box).kind, .resize(.right))
        XCTAssertEqual(CropDragModel.begin(at: p(0.4, 0.4), current: box).kind, .move)
        XCTAssertEqual(CropDragModel.begin(at: p(0.9, 0.9), current: box).kind, .create)
        XCTAssertEqual(CropDragModel.begin(at: p(0.4, 0.4), current: nil).kind, .create)
    }

    func testCreateDragsBetweenTwoPointsInAnyDirection() {
        let s = CropDragModel.begin(at: p(0.7, 0.8), current: box)
        let r = CropDragModel.update(s, to: p(0.3, 0.5))
        XCTAssertEqual(r.x, 0.3, accuracy: 1e-9); XCTAssertEqual(r.y, 0.5, accuracy: 1e-9)
        XCTAssertEqual(r.width, 0.4, accuracy: 1e-9); XCTAssertEqual(r.height, 0.3, accuracy: 1e-9)
    }

    func testCreateClampsToTheWindowAndEnforcesMinimumSize() {
        let s = CropDragModel.begin(at: p(0.9, 0.9), current: box)
        let out = CropDragModel.update(s, to: p(1.7, -2))
        XCTAssertGreaterThanOrEqual(out.x, 0); XCTAssertLessThanOrEqual(out.x + out.width, 1 + 1e-9)
        XCTAssertGreaterThanOrEqual(out.y, 0); XCTAssertLessThanOrEqual(out.y + out.height, 1 + 1e-9)
        let tiny = CropDragModel.update(s, to: p(0.9, 0.9))
        XCTAssertGreaterThanOrEqual(tiny.width, NormalizedCropRect.minimumSide - 1e-9)
    }

    func testMoveKeepsSizeAndStaysInside() {
        let s = CropDragModel.begin(at: p(0.4, 0.4), current: box)
        let r = CropDragModel.update(s, to: p(0.5, 0.45))
        XCTAssertEqual(r.x, 0.3, accuracy: 1e-9); XCTAssertEqual(r.y, 0.25, accuracy: 1e-9)
        XCTAssertEqual(r.width, 0.4, accuracy: 1e-9)
        let far = CropDragModel.update(s, to: p(5, 5))
        XCTAssertEqual(far.x + far.width, 1, accuracy: 1e-9); XCTAssertEqual(far.y + far.height, 1, accuracy: 1e-9)
        XCTAssertEqual(far.width, 0.4, accuracy: 1e-9)
    }

    func testResizeCornerMovesOnlyThatCorner() {
        let s = CropDragModel.begin(at: p(0.2, 0.2), current: box)
        let r = CropDragModel.update(s, to: p(0.1, 0.15))
        XCTAssertEqual(r.x, 0.1, accuracy: 1e-9); XCTAssertEqual(r.y, 0.15, accuracy: 1e-9)
        XCTAssertEqual(r.x + r.width, 0.6, accuracy: 1e-9); XCTAssertEqual(r.y + r.height, 0.6, accuracy: 1e-9)
    }

    func testResizeEdgeMovesOnlyThatEdge() {
        let s = CropDragModel.begin(at: p(0.6, 0.4), current: box)
        let r = CropDragModel.update(s, to: p(0.8, 0.9))
        XCTAssertEqual(r.x, 0.2, accuracy: 1e-9); XCTAssertEqual(r.y, 0.2, accuracy: 1e-9)
        XCTAssertEqual(r.width, 0.6, accuracy: 1e-9); XCTAssertEqual(r.height, 0.4, accuracy: 1e-9)
    }

    func testResizeCannotFlipOrShrinkBelowMinimum() {
        let s = CropDragModel.begin(at: p(0.6, 0.6), current: box)
        let r = CropDragModel.update(s, to: p(0.0, 0.0))
        XCTAssertEqual(r.x, 0.2, accuracy: 1e-9)
        XCTAssertEqual(r.width, NormalizedCropRect.minimumSide, accuracy: 1e-9)
        XCTAssertEqual(r.height, NormalizedCropRect.minimumSide, accuracy: 1e-9)
    }

    func testNonFinitePointsAreIgnored() {
        let s = CropDragModel.begin(at: p(0.4, 0.4), current: box)
        XCTAssertEqual(CropDragModel.update(s, to: p(.nan, 0.5)), box)
    }
}
