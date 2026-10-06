import XCTest
@testable import DavidNookCore

/// 浮動視窗的幾何：縮放夾限、四角縮放（鎖長寬比）、位置恢復、透明度、記憶資料。
final class FloatingVideoGeometryTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
    private let ratio: Double = 16.0 / 9.0

    // MARK: 尺寸夾限

    func testClampedSizeKeepsRatioInsideLimits() {
        let size = FloatingVideoGeometry.clampedSize(width: 320, aspectRatio: ratio, in: screen)
        XCTAssertEqual(size.width, 320, accuracy: 0.001)
        XCTAssertEqual(size.height, 180, accuracy: 0.001)
    }

    func testMinimumWidth() {
        let size = FloatingVideoGeometry.clampedSize(width: 10, aspectRatio: ratio, in: screen)
        XCTAssertEqual(size.width, FloatingVideoGeometry.minimumWidth)
        XCTAssertEqual(FloatingVideoGeometry.minimumWidth, 160)
        XCTAssertEqual(size.width / size.height, ratio, accuracy: 0.001)
    }

    func testMaximumNeverExceedsScreen() {
        let size = FloatingVideoGeometry.clampedSize(width: 99_999, aspectRatio: ratio, in: screen)
        XCTAssertLessThanOrEqual(size.width, screen.width + 0.001)
        XCTAssertLessThanOrEqual(size.height, screen.height + 0.001)
        XCTAssertEqual(size.width, min(screen.width, screen.height * ratio), accuracy: 0.001)
        let wide = CGRect(x: 0, y: 0, width: 3000, height: 800)
        let w2 = FloatingVideoGeometry.clampedSize(width: 99_999, aspectRatio: ratio, in: wide)
        XCTAssertEqual(w2.height, 800, accuracy: 0.001, "寬螢幕受高度限制")
    }

    func testInvalidInputsFallBack() {
        let a = FloatingVideoGeometry.clampedSize(width: .nan, aspectRatio: ratio, in: screen)
        XCTAssertEqual(a.width, FloatingVideoGeometry.defaultWidth)
        let b = FloatingVideoGeometry.clampedSize(width: 320, aspectRatio: .nan, in: screen)
        XCTAssertEqual(b.width / b.height, 16.0 / 9.0, accuracy: 0.001)
        let c = FloatingVideoGeometry.clampedSize(width: 320, aspectRatio: 0, in: screen)
        XCTAssertTrue(c.height.isFinite && c.height > 0)
    }

    /// 窮舉：各種比例、寬度、螢幕大小，結果一定在螢幕內、比例（夾在 1:4…4:1 內）不變、寬不小於最小寬（除非螢幕本身更小）。
    func testExhaustiveClamp() {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 875), CGRect(x: -1920, y: 100, width: 1920, height: 1055),
                       CGRect(x: 0, y: 0, width: 800, height: 500), CGRect(x: 0, y: 0, width: 200, height: 120)]
        for s in screens {
            for r in [0.2, 0.5, 9.0 / 16.0, 1.0, 4.0 / 3.0, 16.0 / 9.0, 21.0 / 9.0, 3.0, 8.0] {
                for w in [-50.0, 0, 50, 159, 160, 320, 777, 1200, 5000, 1e9] {
                    let size = FloatingVideoGeometry.clampedSize(width: w, aspectRatio: r, in: s)
                    let eff = min(max(r, FloatingVideoGeometry.aspectRatioRange.lowerBound), FloatingVideoGeometry.aspectRatioRange.upperBound)
                    XCTAssertLessThanOrEqual(size.width, s.width + 0.001, "\(s) \(r) \(w)")
                    XCTAssertLessThanOrEqual(size.height, s.height + 0.001, "\(s) \(r) \(w)")
                    XCTAssertEqual(size.width / size.height, eff, accuracy: 0.001, "\(s) \(r) \(w)")
                    if s.width >= 1000 { XCTAssertGreaterThanOrEqual(size.width, FloatingVideoGeometry.minimumWidth - 0.001) }
                }
            }
        }
    }

    // MARK: 四角縮放

    private let frame = CGRect(x: 100, y: 100, width: 320, height: 180)   // AppKit 座標：y 向上，maxY = 280

    func testResizeFromBottomRightAnchorsTopLeft() {
        let r = FloatingVideoGeometry.resize(frame: frame, corner: .bottomRight, pointer: CGPoint(x: 520, y: 100), aspectRatio: ratio, in: screen)
        XCTAssertEqual(r.width, 420, accuracy: 0.001)
        XCTAssertEqual(r.height, 420 / ratio, accuracy: 0.001)
        XCTAssertEqual(r.minX, 100, accuracy: 0.001)
        XCTAssertEqual(r.maxY, 280, accuracy: 0.001)
    }

    func testResizeFromTopLeftAnchorsBottomRight() {
        let r = FloatingVideoGeometry.resize(frame: frame, corner: .topLeft, pointer: CGPoint(x: 20, y: 300), aspectRatio: ratio, in: screen)
        XCTAssertEqual(r.width, 400, accuracy: 0.001)
        XCTAssertEqual(r.maxX, 420, accuracy: 0.001)
        XCTAssertEqual(r.minY, 100, accuracy: 0.001)
    }

    func testResizeFromTopRightAndBottomLeft() {
        let tr = FloatingVideoGeometry.resize(frame: frame, corner: .topRight, pointer: CGPoint(x: 300, y: 330), aspectRatio: ratio, in: screen)
        XCTAssertEqual(tr.minX, 100, accuracy: 0.001)
        XCTAssertEqual(tr.minY, 100, accuracy: 0.001)
        XCTAssertEqual(tr.width / tr.height, ratio, accuracy: 0.001)
        let bl = FloatingVideoGeometry.resize(frame: frame, corner: .bottomLeft, pointer: CGPoint(x: 60, y: 40), aspectRatio: ratio, in: screen)
        XCTAssertEqual(bl.maxX, 420, accuracy: 0.001)
        XCTAssertEqual(bl.maxY, 280, accuracy: 0.001)
        XCTAssertEqual(bl.width / bl.height, ratio, accuracy: 0.001)
    }

    func testResizeUsesLargerOfBothAxes() {
        // 往下拖很多、往右拖一點：高度方向決定大小。
        let r = FloatingVideoGeometry.resize(frame: frame, corner: .bottomRight, pointer: CGPoint(x: 430, y: -100), aspectRatio: ratio, in: screen)
        XCTAssertEqual(r.height, 380, accuracy: 0.001)
        XCTAssertEqual(r.width, 380 * ratio, accuracy: 0.001)
    }

    func testResizeClampsAndNeverFlips() {
        let tiny = FloatingVideoGeometry.resize(frame: frame, corner: .bottomRight, pointer: CGPoint(x: 0, y: 500), aspectRatio: ratio, in: screen)
        XCTAssertEqual(tiny.width, 160, accuracy: 0.001, "拖過對角＝最小寬，不翻轉")
        XCTAssertEqual(tiny.minX, 100, accuracy: 0.001)
        let huge = FloatingVideoGeometry.resize(frame: frame, corner: .bottomRight, pointer: CGPoint(x: 99_999, y: -99_999), aspectRatio: ratio, in: screen)
        XCTAssertLessThanOrEqual(huge.width, screen.width + 0.001)
        XCTAssertLessThanOrEqual(huge.height, screen.height + 0.001)
    }

    // MARK: 比例改變、推回螢幕內

    func testAspectChangeKeepsWidthAndTopLeft() {
        let high = CGRect(x: 100, y: 500, width: 320, height: 180)   // maxY = 680
        let r = FloatingVideoGeometry.adjustedForAspect(frame: high, aspectRatio: 1.0, in: screen)
        XCTAssertEqual(r.width, 320, accuracy: 0.001)
        XCTAssertEqual(r.height, 320, accuracy: 0.001)
        XCTAssertEqual(r.minX, 100, accuracy: 0.001)
        XCTAssertEqual(r.maxY, 680, accuracy: 0.001)
        // 靠近螢幕下緣：長高後被推回螢幕內
        let low = FloatingVideoGeometry.adjustedForAspect(frame: frame, aspectRatio: 1.0, in: screen)
        XCTAssertTrue(screen.contains(low))
    }

    func testNudgedInside() {
        let out = CGRect(x: 1400, y: -50, width: 320, height: 180)
        let r = FloatingVideoGeometry.nudgedInside(out, in: screen)
        XCTAssertTrue(screen.contains(r))
        XCTAssertEqual(r.size, out.size)
        XCTAssertEqual(FloatingVideoGeometry.nudgedInside(frame, in: screen), frame)
    }

    // MARK: 位置恢復

    func testNoSavedPlacementGoesBottomRightOfPrimary() {
        let r = FloatingVideoGeometry.restoredFrame(saved: nil, aspectRatio: ratio, screens: [screen], primary: screen)
        XCTAssertEqual(r.width, FloatingVideoGeometry.defaultWidth, accuracy: 0.001)
        XCTAssertEqual(r.maxX, screen.maxX - FloatingVideoGeometry.cornerMargin, accuracy: 0.001)
        XCTAssertEqual(r.minY, screen.minY + FloatingVideoGeometry.cornerMargin, accuracy: 0.001)
    }

    func testSavedOnScreenIsKept() {
        let saved = FloatingVideoPlacement(x: 300, y: 400, width: 400)
        let r = FloatingVideoGeometry.restoredFrame(saved: saved, aspectRatio: ratio, screens: [screen], primary: screen)
        XCTAssertEqual(r.minX, 300, accuracy: 0.001)
        XCTAssertEqual(r.minY, 400, accuracy: 0.001)
        XCTAssertEqual(r.width, 400, accuracy: 0.001)
        XCTAssertEqual(r.height, 225, accuracy: 0.001)
    }

    func testSavedOffAllScreensFallsBackToPrimaryBottomRight() {
        // 上次在已拔掉的第二螢幕
        let saved = FloatingVideoPlacement(x: -2500, y: 200, width: 500)
        let r = FloatingVideoGeometry.restoredFrame(saved: saved, aspectRatio: ratio, screens: [screen], primary: screen)
        XCTAssertEqual(r.maxX, screen.maxX - FloatingVideoGeometry.cornerMargin, accuracy: 0.001)
        XCTAssertEqual(r.minY, screen.minY + FloatingVideoGeometry.cornerMargin, accuracy: 0.001)
        XCTAssertEqual(r.width, 500, accuracy: 0.001, "寬度仍沿用記住的")
        XCTAssertTrue(screen.contains(r))
    }

    func testSavedOnSecondScreenIsKeptWhenPresent() {
        let second = CGRect(x: 1440, y: 0, width: 1920, height: 1055)
        let saved = FloatingVideoPlacement(x: 1600, y: 300, width: 320)
        let r = FloatingVideoGeometry.restoredFrame(saved: saved, aspectRatio: ratio, screens: [screen, second], primary: screen)
        XCTAssertEqual(r.minX, 1600, accuracy: 0.001)
    }

    func testSavedPartlyOffscreenIsNudgedInsideAndOversizeClamped() {
        let partly = FloatingVideoPlacement(x: 1200, y: 700, width: 400)   // 中心在螢幕內，但右上超出
        let a = FloatingVideoGeometry.restoredFrame(saved: partly, aspectRatio: ratio, screens: [screen], primary: screen)
        XCTAssertTrue(screen.contains(a))
        let big = FloatingVideoPlacement(x: 0, y: 0, width: 9000)
        let b = FloatingVideoGeometry.restoredFrame(saved: big, aspectRatio: ratio, screens: [screen], primary: screen)
        XCTAssertTrue(screen.contains(b))
    }

    func testSavedCenterOnScreenButAspectChangedStillInside() {
        let saved = FloatingVideoPlacement(x: 1100, y: 10, width: 400)
        let r = FloatingVideoGeometry.restoredFrame(saved: saved, aspectRatio: 0.5, screens: [screen], primary: screen)
        XCTAssertTrue(screen.contains(r))
    }

    func testNoScreensAtAllStillReturnsSomething() {
        let r = FloatingVideoGeometry.restoredFrame(saved: nil, aspectRatio: ratio, screens: [], primary: screen)
        XCTAssertTrue(screen.contains(r))
    }

    // MARK: 透明度

    func testOpacityClamp() {
        XCTAssertEqual(FloatingVideoOpacity.clamped(0.1), 0.4)
        XCTAssertEqual(FloatingVideoOpacity.clamped(5), 1.0)
        XCTAssertEqual(FloatingVideoOpacity.clamped(0.7), 0.7)
        XCTAssertEqual(FloatingVideoOpacity.clamped(.nan), 1.0)
        XCTAssertEqual(FloatingVideoOpacity.clamped(-.infinity), 0.4)
        XCTAssertEqual(FloatingVideoOpacity.defaultValue, 1.0)
    }

    func testOpacityCycleVisitsAllStepsAndWraps() {
        XCTAssertEqual(FloatingVideoOpacity.steps, [1.0, 0.8, 0.6, 0.4])
        XCTAssertEqual(FloatingVideoOpacity.next(after: 1.0), 0.8)
        XCTAssertEqual(FloatingVideoOpacity.next(after: 0.8), 0.6)
        XCTAssertEqual(FloatingVideoOpacity.next(after: 0.6), 0.4)
        XCTAssertEqual(FloatingVideoOpacity.next(after: 0.4), 1.0)
        XCTAssertEqual(FloatingVideoOpacity.next(after: 0.71), 0.6, "不在刻度上＝先靠到最近刻度（0.8）再往下一格")
        XCTAssertEqual(FloatingVideoOpacity.next(after: .nan), 0.8)
        XCTAssertEqual(FloatingVideoOpacity.next(after: 99), 0.8)
    }

    // MARK: 記憶資料

    func testPlacementCodableRoundTripAndContainsNoContent() throws {
        let p = FloatingVideoPlacement(frame: CGRect(x: 12.5, y: 34, width: 400, height: 225))
        XCTAssertEqual(p.width, 400)
        let data = try JSONEncoder().encode(p)
        XCTAssertEqual(try JSONDecoder().decode(FloatingVideoPlacement.self, from: data), p)
        let keys = Set((try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]).keys)
        XCTAssertEqual(keys, ["x", "y", "width"], "只記位置與寬度，沒有任何標題或內容")
    }

    func testDefaultsKeys() {
        XCTAssertEqual(FloatingVideoPlacement.defaultsKey, "videoFloatingPlacement")
        XCTAssertEqual(FloatingVideoOpacity.defaultsKey, "videoFloatingOpacity")
    }
}
