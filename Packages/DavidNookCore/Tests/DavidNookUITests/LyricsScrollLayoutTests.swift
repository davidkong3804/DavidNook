import XCTest
@testable import DavidNookUI

final class LyricsScrollLayoutTests: XCTestCase {
    private let heights: [CGFloat] = [20, 20, 40, 20, 20]
    private let spacing: CGFloat = 8
    private let mid: CGFloat = 60

    private func centers(position: Double) -> [CGFloat] {
        let tops = LyricsScrollLayout.tops(heights: heights, spacing: spacing, position: position, midY: mid)
        return zip(tops, heights).map { $0 + $1 / 2 }
    }

    func testCurrentLineIsCenteredAtIntegerPositions() {
        for index in heights.indices {
            XCTAssertEqual(centers(position: Double(index))[index], mid, accuracy: 1e-9, "index \(index)")
        }
    }

    func testTallWrappedLineIsStillCentered() {
        // 第 2 行高 40（折成兩行）：它的中心落在 mid，而不是頂端。
        XCTAssertEqual(centers(position: 2)[2], mid, accuracy: 1e-9)
    }

    func testFractionalPositionInterpolatesBetweenNeighbours() {
        let a = centers(position: 1)[1]
        let b = centers(position: 2)[1]
        XCTAssertEqual(centers(position: 1.5)[1], (a + b) / 2, accuracy: 1e-9)
    }

    func testBeforeTheFirstLineTheFirstLineSitsOnePitchBelowCenter() {
        let c = centers(position: -1)
        XCTAssertEqual(c[0], mid + (heights[0] + spacing), accuracy: 1e-9)
    }

    func testPastTheLastLineExtrapolates() {
        let c = centers(position: Double(heights.count))
        XCTAssertEqual(c[heights.count - 1], mid - (heights[heights.count - 1] + spacing), accuracy: 1e-9)
    }

    func testEmptyInput() {
        XCTAssertEqual(LyricsScrollLayout.tops(heights: [], spacing: 8, position: 0, midY: 50), [])
    }
}
