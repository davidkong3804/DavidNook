import XCTest
@testable import DavidNookCore

/// 時間軸精準度：PlaybackClock（內插）＋ LyricsTimeline（查行）串起來的端到端驗證。
/// 20 行歌詞全為自編的測試句，行時間刻意取不規則間隔。
///
/// 偏移約定（本檔鎖定）：
/// - 正值＝歌詞提早顯示；負值＝歌詞延後顯示（LRC `[offset:]` 慣例）。
/// - LRC 檔內 `[offset:]` 與使用者偏移「相加」：查詢時間 = 播放位置 + lrcOffset + userOffset。
///   兩者相加，不分先後；解析階段不改寫行時間，所以解析結果可快取，與使用者偏移無關。
final class TimelinePrecisionTests: XCTestCase {

    private static let lines: [(ms: Int, tag: String)] = [
        (4_000, "00:04.00"), (8_500, "00:08.50"), (12_000, "00:12.00"), (15_250, "00:15.25"),
        (19_800, "00:19.80"), (24_000, "00:24.00"), (28_350, "00:28.35"), (33_000, "00:33.00"),
        (37_100, "00:37.10"), (41_500, "00:41.50"), (46_000, "00:46.00"), (50_250, "00:50.25"),
        (55_000, "00:55.00"), (59_900, "00:59.90"), (64_000, "01:04.00"), (68_400, "01:08.40"),
        (73_000, "01:13.00"), (77_750, "01:17.75"), (82_000, "01:22.00"), (86_500, "01:26.50"),
    ]

    private static func lrc(offsetTag: String? = nil) -> String {
        var out = "[ti:精準度測試用]\n[ar:自編]\n"
        if let offsetTag { out += "[offset:\(offsetTag)]\n" }
        for (i, l) in lines.enumerated() {
            let number = i + 1 < 10 ? "0\(i + 1)" : "\(i + 1)"
            out += "[\(l.tag)]測試句\(number)\n"
        }
        return out
    }

    private var clock: ManualClock!
    private var playback: PlaybackClock!

    override func setUp() {
        super.setUp()
        clock = ManualClock()
        playback = PlaybackClock(now: clock.provider)
    }

    private func timeline(offsetTag: String? = nil) -> LyricsTimeline {
        LyricsTimeline(document: LRCParser.parse(Self.lrc(offsetTag: offsetTag)))
    }

    private func update(elapsed: TimeInterval, ago: TimeInterval = 0, rate: Double = 1.0,
                        playing: Bool = true, duration: TimeInterval? = 120) {
        playback.update(PlaybackSnapshot(elapsedTime: elapsed, timestamp: clock.now().addingTimeInterval(-ago),
                                         playbackRate: rate, isPlaying: playing, duration: duration))
    }

    private func currentIndex(_ t: LyricsTimeline, userOffsetMs: Int = 0) -> Int? {
        t.currentIndex(at: playback.position()!, userOffsetMs: userOffsetMs)
    }

    // MARK: - 樣本本身

    func testFixtureParsesToTwentyLinesWithExpectedTimes() {
        let doc = LRCParser.parse(Self.lrc())
        XCTAssertEqual(doc.lines.count, 20)
        XCTAssertEqual(doc.lines.map(\.timeMs), Self.lines.map(\.ms))
        XCTAssertEqual(doc.lines[2].text, "測試句03")
        XCTAssertEqual(doc.metadata["ti"], "精準度測試用")
    }

    // MARK: - 播放速率與暫停

    func testElapsed10TimestampTwoAndHalfSecondsAgoRate1() {
        update(elapsed: 10.0, ago: 2.5, rate: 1.0)
        XCTAssertEqual(playback.position()!, 12.5, accuracy: 1e-9)
        let t = timeline()
        XCTAssertEqual(currentIndex(t), 2)
        XCTAssertEqual(t.lines[currentIndex(t)!].text, "測試句03")
        XCTAssertEqual(t.nextLineTime(at: playback.position()!)!, 15.25, accuracy: 1e-9)
    }

    func testPausedPositionDoesNotMoveEvenWhenTimePasses() {
        update(elapsed: 10.0, ago: 2.5, rate: 0, playing: false)
        let t = timeline()
        XCTAssertEqual(currentIndex(t), 1, "暫停時固定在 10.0s（8.5s 那行），不加上 2.5s")
        clock.advance(1_000)
        XCTAssertEqual(currentIndex(t), 1)
        XCTAssertEqual(playback.position()!, 10.0, accuracy: 1e-9)
    }

    func testHalfRate() {
        let t = timeline()
        update(elapsed: 10.0, ago: 2.5, rate: 0.5)             // 10 + 1.25 = 11.25
        XCTAssertEqual(playback.position()!, 11.25, accuracy: 1e-9)
        XCTAssertEqual(currentIndex(t), 1)
        update(elapsed: 10.0, ago: 5.0, rate: 0.5)             // 10 + 2.5 = 12.5，與 rate=1、2.5s 相同
        XCTAssertEqual(currentIndex(t), 2)
    }

    func testDoubleRate() {
        update(elapsed: 10.0, ago: 2.5, rate: 2.0)             // 10 + 5 = 15 → 還沒到 15.25
        XCTAssertEqual(currentIndex(timeline()), 2)
        clock.advance(0.125)                                   // 15 + 0.25 = 15.25 → 正好換行
        XCTAssertEqual(currentIndex(timeline()), 3)
    }

    // MARK: - 行邊界前後各 1 ms

    func testEveryLineBoundaryIsExactToTheMillisecond() {
        let t = timeline()
        for (i, line) in Self.lines.enumerated() {
            let sec = Double(line.ms) / 1000
            update(elapsed: 0, ago: sec - 0.001)
            XCTAssertEqual(currentIndex(t), i == 0 ? nil : i - 1, "line \(i) 前 1ms")
            update(elapsed: 0, ago: sec)
            XCTAssertEqual(currentIndex(t), i, "line \(i) 剛好")
            update(elapsed: 0, ago: sec + 0.001)
            XCTAssertEqual(currentIndex(t), i, "line \(i) 後 1ms")
        }
    }

    func testBoundaryWithFractionalElapsedAndTimestamp() {
        // elapsed 10.000 + 5.249 = 15.249（行 4 在 15.250）
        update(elapsed: 10.0, ago: 5.249)
        XCTAssertEqual(currentIndex(timeline()), 2)
        update(elapsed: 10.0, ago: 5.250)
        XCTAssertEqual(currentIndex(timeline()), 3)
        update(elapsed: 10.0, ago: 5.251)
        XCTAssertEqual(currentIndex(timeline()), 3)
    }

    func testBeforeFirstLineThenFirstLine() {
        let t = timeline()
        update(elapsed: 3.999)
        XCTAssertNil(currentIndex(t))
        update(elapsed: 4.0)
        XCTAssertEqual(currentIndex(t), 0)
    }

    func testPastTheLastLineIsClampedByDurationAndStaysOnLastLine() {
        let t = timeline()
        update(elapsed: 85, ago: 20, duration: 90)             // 105 → 夾到 90
        XCTAssertEqual(playback.position()!, 90, accuracy: 1e-9)
        XCTAssertEqual(currentIndex(t), 19)
        XCTAssertNil(t.nextLineTime(at: playback.position()!))
    }

    func testSeekJumpsStraightToTheRightLine() {
        let t = timeline()
        update(elapsed: 10.0)
        XCTAssertEqual(currentIndex(t), 1)
        update(elapsed: 50.5)                                   // 使用者拖曳
        XCTAssertEqual(currentIndex(t), 11)
        update(elapsed: 0.0)                                    // 回到開頭
        XCTAssertNil(currentIndex(t))
    }

    func testTimeUntilNextLineForSchedulingTheNextWakeUp() {
        update(elapsed: 10.0, ago: 2.5)
        XCTAssertEqual(timeline().timeUntilNextLine(at: playback.position()!)!, 2.75, accuracy: 1e-9)
    }

    // MARK: - 偏移（正值＝提早）

    func testNegativeUserOffsetDelaysTheLyrics() {
        let t = timeline()
        update(elapsed: 12.0)
        XCTAssertEqual(currentIndex(t, userOffsetMs: -500), 1, "12.0s 時查詢時間為 11.5s，第三行（12.0s）還沒到")
        update(elapsed: 12.499)
        XCTAssertEqual(currentIndex(t, userOffsetMs: -500), 1)
        update(elapsed: 12.5)
        XCTAssertEqual(currentIndex(t, userOffsetMs: -500), 2)
    }

    func testPositiveUserOffsetAdvancesTheLyrics() {
        let t = timeline()
        update(elapsed: 11.499)
        XCTAssertEqual(currentIndex(t, userOffsetMs: 500), 1)
        update(elapsed: 11.5)
        XCTAssertEqual(currentIndex(t, userOffsetMs: 500), 2)
    }

    func testLRCOffsetTagAdvancesTheLyricsInTheSameDirection() {
        let t = timeline(offsetTag: "+500")
        update(elapsed: 11.499)
        XCTAssertEqual(currentIndex(t), 1)
        update(elapsed: 11.5)
        XCTAssertEqual(currentIndex(t), 2)
    }

    func testNegativeLRCOffsetTagDelaysTheLyrics() {
        let t = timeline(offsetTag: "-500")
        update(elapsed: 12.499)
        XCTAssertEqual(currentIndex(t), 1)
        update(elapsed: 12.5)
        XCTAssertEqual(currentIndex(t), 2)
    }

    func testLRCOffsetTagAndUserOffsetStackByAddition() {
        // 檔內 +500、使用者 -300 → 合計 +200：第三行（12.0s）在 11.8s 切換。
        let t = timeline(offsetTag: "+500")
        update(elapsed: 11.799)
        XCTAssertEqual(currentIndex(t, userOffsetMs: -300), 1)
        update(elapsed: 11.8)
        XCTAssertEqual(currentIndex(t, userOffsetMs: -300), 2)

        // 檔內 +500、使用者 +200 → 合計 +700：11.3s 切換。
        update(elapsed: 11.299)
        XCTAssertEqual(currentIndex(t, userOffsetMs: 200), 1)
        update(elapsed: 11.3)
        XCTAssertEqual(currentIndex(t, userOffsetMs: 200), 2)
    }

    func testOrderOfApplyingTheTwoOffsetsDoesNotMatter() {
        // (檔內 +500, 使用者 -300) 與 (檔內 -300, 使用者 +500) 與 (檔內 0, 使用者 +200) 完全等價。
        let a = timeline(offsetTag: "+500")
        let b = timeline(offsetTag: "-300")
        let c = timeline()
        for ms in stride(from: 3_000, through: 90_000, by: 13) {
            update(elapsed: Double(ms) / 1000)
            let pos = playback.position()!
            XCTAssertEqual(a.currentIndex(at: pos, userOffsetMs: -300), c.currentIndex(at: pos, userOffsetMs: 200), "ms=\(ms)")
            XCTAssertEqual(b.currentIndex(at: pos, userOffsetMs: 500), c.currentIndex(at: pos, userOffsetMs: 200), "ms=\(ms)")
        }
    }

    func testRateAndNegativeOffsetTogether() {
        // rate 0.5：10 + 2.5×0.5 = 11.25；再 -250ms → 查詢 11.0s → 第二行（8.5s）。
        let t = timeline()
        update(elapsed: 10.0, ago: 2.5, rate: 0.5)
        XCTAssertEqual(currentIndex(t, userOffsetMs: -250), 1)
        // 若 +750ms → 查詢 12.0s → 剛好第三行。
        XCTAssertEqual(currentIndex(t, userOffsetMs: 750), 2)
        XCTAssertEqual(currentIndex(t, userOffsetMs: 749), 1)
    }
}
