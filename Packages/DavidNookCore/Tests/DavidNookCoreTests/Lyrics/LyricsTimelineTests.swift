import XCTest
@testable import DavidNookCore

final class LyricsTimelineTests: XCTestCase {

    private let three = [L(10_000, "a"), L(20_000, "b"), L(30_000, "c")]

    // MARK: - 基本查詢

    func testEmptyTimelineHasNoCurrentLineAndNoNext() {
        let t = LyricsTimeline(lines: [])
        XCTAssertNil(t.currentIndex(atMs: 0))
        XCTAssertNil(t.currentIndex(at: 123.4))
        XCTAssertNil(t.nextLineTime(at: 0))
    }

    func testPositionBeforeFirstLineIsNil() {
        let t = LyricsTimeline(lines: three)
        XCTAssertNil(t.currentIndex(atMs: 9_999))
        XCTAssertNil(t.currentIndex(atMs: 0))
        XCTAssertNil(t.currentIndex(atMs: -5_000))
    }

    func testPositionExactlyAtFirstLineIsIndexZero() {
        XCTAssertEqual(LyricsTimeline(lines: three).currentIndex(atMs: 10_000), 0)
    }

    func testOneMillisecondAroundMiddleBoundary() {
        let t = LyricsTimeline(lines: three)
        XCTAssertEqual(t.currentIndex(atMs: 19_999), 0)
        XCTAssertEqual(t.currentIndex(atMs: 20_000), 1)
        XCTAssertEqual(t.currentIndex(atMs: 20_001), 1)
    }

    func testPositionAfterLastLineIsLastIndex() {
        XCTAssertEqual(LyricsTimeline(lines: three).currentIndex(atMs: 9_999_999), 2)
    }

    func testSingleLineTimeline() {
        let t = LyricsTimeline(lines: [L(5_000, "only")])
        XCTAssertNil(t.currentIndex(atMs: 4_999))
        XCTAssertEqual(t.currentIndex(atMs: 5_000), 0)
        XCTAssertNil(t.nextLineTime(at: 6))
    }

    func testEqualTimestampsResolveToTheLastLineAtThatTime() {
        let t = LyricsTimeline(lines: [L(10_000, "a1"), L(10_000, "a2"), L(20_000, "b")])
        XCTAssertEqual(t.currentIndex(atMs: 10_000), 1)
        XCTAssertEqual(t.currentIndex(atMs: 15_000), 1)
    }

    func testBlankMarkerLineIsAValidCurrentLine() {
        let t = LyricsTimeline(lines: [L(10_000, "a"), L(20_000, ""), L(40_000, "b")])
        XCTAssertEqual(t.currentIndex(atMs: 25_000), 1)
        XCTAssertEqual(t.lines[1].text, "")
    }

    func testUnsortedInputIsSortedStablyOnInit() {
        let t = LyricsTimeline(lines: [L(20_000, "b"), L(10_000, "a1"), L(10_000, "a2")])
        XCTAssertEqual(t.lines.map(\.text), ["a1", "a2", "b"])
    }

    // MARK: - 秒數 API（四捨五入到毫秒）

    func testSecondsAPIRoundsToNearestMillisecond() {
        let t = LyricsTimeline(lines: three)
        XCTAssertEqual(t.currentIndex(at: 9.9996), 0, "9.9996s 四捨五入為 10000ms，應已進入第一行")
        XCTAssertNil(t.currentIndex(at: 9.9994), "9.9994s 四捨五入為 9999ms，尚未到第一行")
    }

    func testSecondsAPIMatchesMillisecondAPI() {
        let t = LyricsTimeline(lines: three)
        XCTAssertEqual(t.currentIndex(at: 20.0), t.currentIndex(atMs: 20_000))
        XCTAssertEqual(t.currentIndex(at: 19.999), t.currentIndex(atMs: 19_999))
    }

    func testNonFinitePositions() {
        let t = LyricsTimeline(lines: three)
        XCTAssertNil(t.currentIndex(at: .nan))
        XCTAssertNil(t.currentIndex(at: -.infinity))
        XCTAssertEqual(t.currentIndex(at: .infinity), 2)
    }

    // MARK: - 下一行時間（播放時間軸上的絕對秒數）

    func testNextLineTimeBeforeFirstLineIsFirstLine() {
        XCTAssertEqual(LyricsTimeline(lines: three).nextLineTime(at: 3.0)!, 10.0, accuracy: 1e-9)
    }

    func testNextLineTimeInTheMiddle() {
        XCTAssertEqual(LyricsTimeline(lines: three).nextLineTime(at: 12.0)!, 20.0, accuracy: 1e-9)
    }

    func testNextLineTimeExactlyAtLineStartIsTheFollowingLine() {
        XCTAssertEqual(LyricsTimeline(lines: three).nextLineTime(at: 20.0)!, 30.0, accuracy: 1e-9)
    }

    func testNextLineTimeAfterLastLineIsNil() {
        XCTAssertNil(LyricsTimeline(lines: three).nextLineTime(at: 31.0))
    }

    func testNextLineSkipsLinesSharingTheCurrentTimestamp() {
        let t = LyricsTimeline(lines: [L(10_000, "a1"), L(10_000, "a2"), L(20_000, "b")])
        XCTAssertEqual(t.nextLineTime(at: 10.0)!, 20.0, accuracy: 1e-9)
    }

    func testTimeUntilNextLine() {
        XCTAssertEqual(LyricsTimeline(lines: three).timeUntilNextLine(at: 12.5)!, 7.5, accuracy: 1e-9)
        XCTAssertNil(LyricsTimeline(lines: three).timeUntilNextLine(at: 40))
    }

    // MARK: - 偏移（正值＝歌詞提早顯示）

    func testPositiveUserOffsetMakesLyricsAppearEarlier() {
        let t = LyricsTimeline(lines: three)
        XCTAssertNil(t.currentIndex(atMs: 9_499, userOffsetMs: 500))
        XCTAssertEqual(t.currentIndex(atMs: 9_500, userOffsetMs: 500), 0)
    }

    func testNegativeUserOffsetMakesLyricsAppearLater() {
        let t = LyricsTimeline(lines: three)
        XCTAssertNil(t.currentIndex(atMs: 10_499, userOffsetMs: -500))
        XCTAssertEqual(t.currentIndex(atMs: 10_500, userOffsetMs: -500), 0)
    }

    func testLRCOffsetTagFollowsTheSameDirectionAsUserOffset() {
        let t = LyricsTimeline(lines: three, lrcOffsetMs: 500)
        XCTAssertNil(t.currentIndex(atMs: 9_499))
        XCTAssertEqual(t.currentIndex(atMs: 9_500), 0)
    }

    func testInitFromDocumentCarriesOffsetTag() {
        let doc = LRCParser.parse("[offset:+500]\n[00:10.00]a\n[00:20.00]b")
        let t = LyricsTimeline(document: doc)
        XCTAssertEqual(t.lrcOffsetMs, 500)
        XCTAssertEqual(t.currentIndex(atMs: 9_500), 0)
        XCTAssertNil(t.currentIndex(atMs: 9_499))
    }

    func testLRCOffsetAndUserOffsetAreAdditive() {
        // [offset:+500]（提早 500ms）再加使用者 -300（延後 300ms）＝ 合計提早 200ms。
        let stacked = LyricsTimeline(lines: three, lrcOffsetMs: 500)
        let direct = LyricsTimeline(lines: three, lrcOffsetMs: 0)
        for p in stride(from: 9_000, through: 31_000, by: 37) {
            XCTAssertEqual(stacked.currentIndex(atMs: p, userOffsetMs: -300),
                           direct.currentIndex(atMs: p, userOffsetMs: 200), "p=\(p)")
        }
        XCTAssertEqual(stacked.currentIndex(atMs: 9_800, userOffsetMs: -300), 0)
        XCTAssertNil(stacked.currentIndex(atMs: 9_799, userOffsetMs: -300))
    }

    func testNextLineTimeSubtractsTheTotalOffset() {
        let t = LyricsTimeline(lines: three, lrcOffsetMs: 500)
        // 下一行 20.000s，合計提早 700ms（500 + 200）→ 播放時間 19.300s 切換。
        XCTAssertEqual(t.nextLineTime(at: 12.0, userOffsetMs: 200)!, 19.3, accuracy: 1e-9)
    }

    func testNextLineTimeWithNegativeUserOffset() {
        let t = LyricsTimeline(lines: three)
        XCTAssertEqual(t.nextLineTime(at: 12.0, userOffsetMs: -1_000)!, 21.0, accuracy: 1e-9)
    }

    // MARK: - 與線性掃描比對（二分搜尋正確性）

    func testBinarySearchMatchesLinearScanOnLargeInput() {
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> UInt64 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return seed >> 33
        }
        var time = 0
        var lines: [LRCLine] = []
        for i in 0..<3_000 {
            time += Int(next() % 4) == 0 ? 0 : Int(next() % 5_000)   // 含重複時間戳
            lines.append(L(time, "l\(i)"))
        }
        let t = LyricsTimeline(lines: lines, lrcOffsetMs: 120)
        let maxTime = time + 5_000
        for _ in 0..<5_000 {
            let p = Int(next() % UInt64(maxTime)) - 2_000
            let userOffset = Int(next() % 2_001) - 1_000
            let lookup = p + 120 + userOffset
            let expected = lines.lastIndex { $0.timeMs <= lookup }
            XCTAssertEqual(t.currentIndex(atMs: p, userOffsetMs: userOffset), expected, "p=\(p) off=\(userOffset)")
        }
    }
}
