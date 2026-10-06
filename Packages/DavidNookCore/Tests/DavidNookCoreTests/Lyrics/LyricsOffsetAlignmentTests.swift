import XCTest
@testable import DavidNookCore

/// 「點歌詞對齊」：使用者點某一行時，算出讓該行「剛好是目前行」的逐曲偏移。
/// 偏移語意不變：正值＝歌詞提早顯示、負值＝延後（見 LyricsTimeline）。
final class LyricsOffsetAlignmentTests: XCTestCase {

    // MARK: - 基本方向

    func testLineLaterThanPositionNeedsPositiveOffset() {
        // 聽到的是 12 秒那行，但播放位置才 10 秒（歌詞出現得太晚）→ 提早 2 秒。
        let r = LyricsOffsetAlignment.aligned(positionMs: 10_000, lineTimeMs: 12_000)
        XCTAssertEqual(r, .init(offsetMs: 2_000, isClamped: false))
    }

    func testLineEarlierThanPositionNeedsNegativeOffset() {
        // 聽到的是 12 秒那行，但播放位置已經 15 秒（歌詞出現得太早）→ 延後 3 秒。
        let r = LyricsOffsetAlignment.aligned(positionMs: 15_000, lineTimeMs: 12_000)
        XCTAssertEqual(r.offsetMs, -3_000)
        XCTAssertFalse(r.isClamped)
    }

    func testLineAtPositionNeedsNoOffset() {
        XCTAssertEqual(LyricsOffsetAlignment.aligned(positionMs: 12_000, lineTimeMs: 12_000).offsetMs, 0)
    }

    func testPlaybackAdvancingBetweenHearingAndClickingLowersTheOffset() {
        // 位置每多走 500 ms，同一行需要的偏移就少 500 ms。
        let early = LyricsOffsetAlignment.aligned(positionMs: 10_000, lineTimeMs: 12_000).offsetMs
        let later = LyricsOffsetAlignment.aligned(positionMs: 10_500, lineTimeMs: 12_000).offsetMs
        XCTAssertEqual(early - later, 500)
    }

    // MARK: - 檔內 [offset:]

    func testLrcOffsetIsSubtractedBecauseTheTimelineAddsItAgain() {
        // 查詢時間 = 位置 + lrcOffset + userOffset；要讓它等於行時間：userOffset = 行時間 − lrcOffset − 位置。
        let r = LyricsOffsetAlignment.aligned(positionMs: 10_000, lineTimeMs: 12_000, lrcOffsetMs: 500)
        XCTAssertEqual(r.offsetMs, 1_500)
    }

    func testResultDoesNotDependOnTheOffsetThatIsCurrentlyApplied() {
        // 計算只看原始行時間（LRCLine.timeMs 不含任何偏移），所以「現有偏移」不影響結果：
        // 不論先前調過多少，點同一行都得到同一個偏移（函式簽章裡本來就沒有「現有偏移」）。
        let lines = [LRCLine(timeMs: 10_000, text: "a"), LRCLine(timeMs: 20_000, text: "b"), LRCLine(timeMs: 30_000, text: "c")]
        let timeline = LyricsTimeline(lines: lines, lrcOffsetMs: 300)
        let position = 17_700
        let r = LyricsOffsetAlignment.aligned(positionMs: position, lineTimeMs: lines[2].timeMs, lrcOffsetMs: timeline.lrcOffsetMs)
        XCTAssertEqual(timeline.currentIndex(atMs: position, userOffsetMs: r.offsetMs), 2)
    }

    // MARK: - 套用後被點的那行真的會變成目前行

    func testClickedLineBecomesTheCurrentLineAtOnce() {
        let lines = (0..<12).map { LRCLine(timeMs: 8_000 + $0 * 4_370, text: "line \($0)") }
        for lrc in [0, 500, -700] {
            let timeline = LyricsTimeline(lines: lines, lrcOffsetMs: lrc)
            for position in stride(from: 3_000, through: 70_000, by: 2_137) {
                for target in lines.indices {
                    let r = LyricsOffsetAlignment.aligned(positionMs: position, lineTimeMs: lines[target].timeMs, lrcOffsetMs: lrc)
                    guard !r.isClamped else { continue }
                    XCTAssertEqual(
                        timeline.currentIndex(atMs: position, userOffsetMs: r.offsetMs), target,
                        "lrc=\(lrc) position=\(position) target=\(target)"
                    )
                }
            }
        }
    }

    // MARK: - 進位（10 ms，往「提早」方向）

    func testOffsetIsRoundedUpToTenMilliseconds() {
        // 往上進位而不是四捨五入：偏移只會「多提早一點點」，被點的那行一定立刻成為目前行。
        XCTAssertEqual(LyricsOffsetAlignment.aligned(positionMs: 10_003, lineTimeMs: 12_000).offsetMs, 2_000) // 1997 → 2000
        XCTAssertEqual(LyricsOffsetAlignment.aligned(positionMs: 10_000, lineTimeMs: 12_001).offsetMs, 2_010) // 2001 → 2010
        XCTAssertEqual(LyricsOffsetAlignment.aligned(positionMs: 10_000, lineTimeMs: 12_010).offsetMs, 2_010) // 已是 10 的倍數
    }

    func testNegativeOffsetsRoundTowardZeroWhichIsUpwards() {
        XCTAssertEqual(LyricsOffsetAlignment.aligned(positionMs: 13_239, lineTimeMs: 12_000).offsetMs, -1_230) // −1239 → −1230
        XCTAssertEqual(LyricsOffsetAlignment.aligned(positionMs: 13_240, lineTimeMs: 12_000).offsetMs, -1_240)
    }

    // MARK: - 以秒計的播放位置

    func testSecondsPositionIsRoundedToTheNearestMillisecond() {
        // 10.0004 s → 10000 ms；10.0006 s → 10001 ms（再進位到 10 ms）。
        XCTAssertEqual(LyricsOffsetAlignment.aligned(position: 10.0004, lineTimeMs: 12_000)?.offsetMs, 2_000)
        XCTAssertEqual(LyricsOffsetAlignment.aligned(position: 10.0006, lineTimeMs: 12_000)?.offsetMs, 2_000) // 1999 → 2000
        XCTAssertEqual(LyricsOffsetAlignment.aligned(position: 10.0016, lineTimeMs: 12_000)?.offsetMs, 2_000) // 10002 → 1998 → 2000
        XCTAssertEqual(LyricsOffsetAlignment.aligned(position: 10.0126, lineTimeMs: 12_000)?.offsetMs, 1_990) // 10013 → 1987 → 1990
    }

    func testNonFinitePositionGivesNoResult() {
        XCTAssertNil(LyricsOffsetAlignment.aligned(position: .nan, lineTimeMs: 12_000))
        XCTAssertNil(LyricsOffsetAlignment.aligned(position: .infinity, lineTimeMs: 12_000))
        XCTAssertNil(LyricsOffsetAlignment.aligned(position: -.infinity, lineTimeMs: 12_000))
    }

    // MARK: - 上下限

    func testLimitIsSixtySeconds() {
        XCTAssertEqual(LyricsOffsetAlignment.limitMs, 60_000)
    }

    func testClampKeepsValuesInsideTheLimit() {
        XCTAssertEqual(LyricsOffsetAlignment.clamp(0), 0)
        XCTAssertEqual(LyricsOffsetAlignment.clamp(60_000), 60_000)
        XCTAssertEqual(LyricsOffsetAlignment.clamp(60_001), 60_000)
        XCTAssertEqual(LyricsOffsetAlignment.clamp(-60_001), -60_000)
        XCTAssertEqual(LyricsOffsetAlignment.clamp(Int.max), 60_000)
        XCTAssertEqual(LyricsOffsetAlignment.clamp(Int.min), -60_000)
    }

    func testResultBeyondTheLimitIsClampedAndFlagged() {
        let tooLate = LyricsOffsetAlignment.aligned(positionMs: 0, lineTimeMs: 200_000)
        XCTAssertEqual(tooLate, .init(offsetMs: 60_000, isClamped: true))
        let tooEarly = LyricsOffsetAlignment.aligned(positionMs: 200_000, lineTimeMs: 0)
        XCTAssertEqual(tooEarly, .init(offsetMs: -60_000, isClamped: true))
    }

    func testExactlyAtTheLimitIsNotFlagged() {
        XCTAssertEqual(LyricsOffsetAlignment.aligned(positionMs: 0, lineTimeMs: 60_000), .init(offsetMs: 60_000, isClamped: false))
        XCTAssertEqual(LyricsOffsetAlignment.aligned(positionMs: 60_000, lineTimeMs: 0), .init(offsetMs: -60_000, isClamped: false))
    }

    func testExtremeInputsDoNotOverflow() {
        XCTAssertEqual(LyricsOffsetAlignment.aligned(positionMs: Int.min, lineTimeMs: Int.max).offsetMs, 60_000)
        XCTAssertEqual(LyricsOffsetAlignment.aligned(positionMs: Int.max, lineTimeMs: Int.min, lrcOffsetMs: Int.max).offsetMs, -60_000)
    }
}
