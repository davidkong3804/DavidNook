import XCTest
@testable import DavidNookUI

/// 歌詞膠囊：同一句、同一樣式的文字寬只量測一次（每個 tick 只算捲動位移）。
final class LyricsTextWidthCacheTests: XCTestCase {
    func testSameLineMeasuredOnce() {
        var measured = 0
        let cache = LyricsTextWidthCache { text, size in measured += 1; return CGFloat(text.count) * size }
        for _ in 0..<100 { XCTAssertEqual(cache.width(text: "夜風輕輕吹過窗台", fontSize: 12), 96) }
        XCTAssertEqual(measured, 1)
    }

    func testNewLineOrSizeMeasuresAgain() {
        var measured = 0
        let cache = LyricsTextWidthCache { text, size in measured += 1; return CGFloat(text.count) * size }
        _ = cache.width(text: "a", fontSize: 12); _ = cache.width(text: "b", fontSize: 12); _ = cache.width(text: "a", fontSize: 13)
        _ = cache.width(text: "a", fontSize: 12)
        XCTAssertEqual(measured, 3)
    }

    func testCacheIsBounded() {
        var measured = 0
        let cache = LyricsTextWidthCache(capacity: 4) { _, _ in measured += 1; return 1 }
        for i in 0..<20 { _ = cache.width(text: "line \(i)", fontSize: 12) }
        XCTAssertLessThanOrEqual(cache.count, 4)
    }

    func testLayoutUsesSharedCache() {
        let style = LyricsPillStyle()
        let before = LyricsTextWidthCache.shared.measureCount
        for _ in 0..<50 { _ = LyricsPillLayout(text: "同一句連續取樣", lineDuration: 5, style: style) }
        XCTAssertLessThanOrEqual(LyricsTextWidthCache.shared.measureCount - before, 1)
    }
}
