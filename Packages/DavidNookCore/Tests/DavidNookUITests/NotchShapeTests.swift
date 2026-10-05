import SwiftUI
import XCTest
@testable import DavidNookUI

/// NotchShape 的圓角必須能被動畫內插（展開／收合時上下圓角隨同一條彈簧變化）。
final class NotchShapeTests: XCTestCase {
    private let rect = CGRect(x: 0, y: 0, width: 400, height: 120)

    func testAnimatableDataRoundTripsBothRadii() {
        var shape = NotchShape(topCornerRadius: 6, bottomCornerRadius: 14)
        XCTAssertEqual(shape.animatableData.first, 6)
        XCTAssertEqual(shape.animatableData.second, 14)

        shape.animatableData = .init(19, 24)
        XCTAssertEqual(shape.animatableData.first, 19)
        XCTAssertEqual(shape.animatableData.second, 24)
    }

    func testDefaultsMatchUpstream() {
        let shape = NotchShape()
        XCTAssertEqual(shape.animatableData.first, 6)
        XCTAssertEqual(shape.animatableData.second, 14)
    }

    func testPathFillsTheRectAndHonoursRadii() {
        let small = NotchShape(topCornerRadius: 6, bottomCornerRadius: 14).path(in: rect)
        let big = NotchShape(topCornerRadius: 19, bottomCornerRadius: 24).path(in: rect)
        XCTAssertEqual(small.boundingRect.width, rect.width, accuracy: 0.001)
        XCTAssertEqual(small.boundingRect.height, rect.height, accuracy: 0.001)
        XCTAssertEqual(big.boundingRect.width, rect.width, accuracy: 0.001)
        // 上緣兩個「耳朵」之間的直邊由 topCornerRadius 內縮：左側直邊位於 x = topCornerRadius。
        XCTAssertTrue(big.contains(CGPoint(x: 19 + 1, y: 60)))
        XCTAssertFalse(big.contains(CGPoint(x: 19 - 4, y: 60)))
        XCTAssertTrue(small.contains(CGPoint(x: 6 + 1, y: 60)))
        XCTAssertFalse(small.contains(CGPoint(x: 6 - 3, y: 60)))
    }

    func testInterpolatedRadiiGiveContinuousSilhouette() {
        // 以 animatableData 插值：內縮的邊界隨進度單調變化（沒有突跳）。
        var previousInset: CGFloat = -1
        for step in 0...10 {
            let p = CGFloat(step) / 10
            var shape = NotchShape(topCornerRadius: 6, bottomCornerRadius: 14)
            shape.animatableData = .init(6 + (19 - 6) * p, 14 + (24 - 14) * p)
            // 取中段水平線與路徑的左邊界：用二分找出最左內點。
            var lo: CGFloat = 0, hi: CGFloat = 60
            let path = shape.path(in: rect)
            for _ in 0..<30 {
                let mid = (lo + hi) / 2
                if path.contains(CGPoint(x: mid, y: 60)) { hi = mid } else { lo = mid }
            }
            if step > 0 {
                XCTAssertGreaterThanOrEqual(hi, previousInset - 0.01)
                XCTAssertLessThan(hi - previousInset, 2.0, "相鄰兩步內縮量不應突跳")
            }
            previousInset = hi
        }
        XCTAssertEqual(previousInset, 19, accuracy: 0.2)
    }
}
