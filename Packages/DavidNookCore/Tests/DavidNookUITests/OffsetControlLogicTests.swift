import XCTest
@testable import DavidNookUI

/// 對時控制的純邏輯：步進、滾輪累積、文字格式、點擊次數、面板預留空間。
/// 方向約定不變：正值＝歌詞提早顯示、負值＝延後。
final class OffsetControlLogicTests: XCTestCase {

    // MARK: - 步進（細調 0.1 秒、粗調 0.5 秒）

    func testStepSizes() {
        XCTAssertEqual(LyricsOffsetFormat.fineStepMs, 100)
        XCTAssertEqual(LyricsOffsetFormat.coarseStepMs, 500)
    }

    func testAdvanceMakesTheOffsetMorePositiveAndDelayMakesItMoreNegative() {
        XCTAssertEqual(OffsetNudge.advance.deltaMs(coarse: false), 100)
        XCTAssertEqual(OffsetNudge.advance.deltaMs(coarse: true), 500)
        XCTAssertEqual(OffsetNudge.delay.deltaMs(coarse: false), -100)
        XCTAssertEqual(OffsetNudge.delay.deltaMs(coarse: true), -500)
    }

    func testAdjustedAddsTheDeltaAndStaysInsideTheLimit() {
        XCTAssertEqual(LyricsOffsetFormat.adjusted(0, byMs: 100), 100)
        XCTAssertEqual(LyricsOffsetFormat.adjusted(1_200, byMs: -500), 700)
        XCTAssertEqual(LyricsOffsetFormat.adjusted(-300, byMs: 100), -200)
        XCTAssertEqual(LyricsOffsetFormat.adjusted(59_900, byMs: 500), 60_000)
        XCTAssertEqual(LyricsOffsetFormat.adjusted(-59_900, byMs: -500), -60_000)
        XCTAssertEqual(LyricsOffsetFormat.adjusted(Int.max, byMs: 500), 60_000)
    }

    // MARK: - 秒數文字

    func testSecondsTextUsesOneDecimalForMultiplesOfHundredMilliseconds() {
        XCTAssertEqual(LyricsOffsetFormat.seconds(abs: 1_200), "1.2")
        XCTAssertEqual(LyricsOffsetFormat.seconds(abs: 1_000), "1.0")
        XCTAssertEqual(LyricsOffsetFormat.seconds(abs: 100), "0.1")
        XCTAssertEqual(LyricsOffsetFormat.seconds(abs: 60_000), "60.0")
    }

    func testSecondsTextUsesTwoDecimalsForFinerValues() {
        XCTAssertEqual(LyricsOffsetFormat.seconds(abs: 1_240), "1.24")
        XCTAssertEqual(LyricsOffsetFormat.seconds(abs: 40), "0.04")
        XCTAssertEqual(LyricsOffsetFormat.seconds(abs: 2_010), "2.01")
    }

    func testSecondsTextIgnoresTheSign() {
        XCTAssertEqual(LyricsOffsetFormat.seconds(abs: -1_200), "1.2")
        XCTAssertEqual(LyricsOffsetFormat.seconds(abs: Int.min), LyricsOffsetFormat.seconds(abs: Int.max))
    }

    func testDirection() {
        XCTAssertEqual(LyricsOffsetFormat.direction(ofOffsetMs: 0), .none)
        XCTAssertEqual(LyricsOffsetFormat.direction(ofOffsetMs: 1), .advanced)
        XCTAssertEqual(LyricsOffsetFormat.direction(ofOffsetMs: -1), .delayed)
    }

    // MARK: - 人話狀態（繁體中文預設）

    func testStatusSentenceInTraditionalChinese() {
        let s = OffsetControlStrings.zhHant
        XCTAssertEqual(s.status(offsetMs: 1_200), "目前：歌詞提早 1.2 秒")
        XCTAssertEqual(s.status(offsetMs: -400), "目前：歌詞延後 0.4 秒")
        XCTAssertEqual(s.status(offsetMs: 0), "目前：無偏移")
    }

    func testBadgeInTraditionalChinese() {
        let s = OffsetControlStrings.zhHant
        XCTAssertEqual(s.badge(offsetMs: 0), "對時")
        XCTAssertEqual(s.badge(offsetMs: 1_200), "提早 1.2 秒")
        XCTAssertEqual(s.badge(offsetMs: -400), "延後 0.4 秒")
        XCTAssertEqual(s.badge(offsetMs: -1_240), "延後 1.24 秒")
    }

    func testToastTextDependsOnWhetherTheLimitWasHit() {
        let s = OffsetControlStrings.zhHant
        XCTAssertEqual(s.alignedToast(isClamped: false), "已對齊，並記住這首歌")
        XCTAssertNotEqual(s.alignedToast(isClamped: true), s.alignedToast(isClamped: false))
    }

    func testStringsFormatThroughInjectedClosures() {
        var s = OffsetControlStrings.zhHant
        s.advancedStatus = { "EARLY \($0)" }
        s.delayedStatus = { "LATE \($0)" }
        XCTAssertEqual(s.status(offsetMs: 300), "EARLY 0.3")
        XCTAssertEqual(s.status(offsetMs: -300), "LATE 0.3")
    }

    // MARK: - 滾輪

    func testMouseWheelTickIsOneFineStepWhateverTheMagnitude() {
        var acc = OffsetWheelAccumulator()
        // 內容往下捲（滑鼠滾輪向上、未開自然捲動時 scrollingDeltaY > 0）＝延後。
        XCTAssertEqual(acc.consume(deltaY: 1, isPrecise: false, isMomentum: false), -100)
        XCTAssertEqual(acc.consume(deltaY: 7.5, isPrecise: false, isMomentum: false), -100)
        // 內容往上捲＝提早。
        XCTAssertEqual(acc.consume(deltaY: -1, isPrecise: false, isMomentum: false), 100)
        XCTAssertEqual(acc.consume(deltaY: -12, isPrecise: false, isMomentum: false), 100)
    }

    func testTrackpadAccumulatesPointsUntilTheThreshold() {
        var acc = OffsetWheelAccumulator()
        XCTAssertEqual(OffsetWheelAccumulator.pointsPerStep, 10)
        XCTAssertEqual(acc.consume(deltaY: -4, isPrecise: true, isMomentum: false), 0)
        XCTAssertEqual(acc.consume(deltaY: -4, isPrecise: true, isMomentum: false), 0)
        XCTAssertEqual(acc.consume(deltaY: -4, isPrecise: true, isMomentum: false), 100) // 累計 12
        XCTAssertEqual(acc.consume(deltaY: -8, isPrecise: true, isMomentum: false), 100) // 餘 2 + 8 = 10
        XCTAssertEqual(acc.consume(deltaY: -9, isPrecise: true, isMomentum: false), 0) // 餘 0 + 9
    }

    func testTrackpadBigSwipeGivesSeveralStepsAndKeepsTheRemainder() {
        var acc = OffsetWheelAccumulator()
        XCTAssertEqual(acc.consume(deltaY: 35, isPrecise: true, isMomentum: false), -300)
        XCTAssertEqual(acc.consume(deltaY: 5, isPrecise: true, isMomentum: false), -100) // 餘 5 + 5
    }

    func testChangingDirectionDropsThePendingRemainder() {
        var acc = OffsetWheelAccumulator()
        XCTAssertEqual(acc.consume(deltaY: 6, isPrecise: true, isMomentum: false), 0)
        XCTAssertEqual(acc.consume(deltaY: -6, isPrecise: true, isMomentum: false), 0) // 不是 0 − 6 + 6 抵銷後的結果，而是重新累計 6
        XCTAssertEqual(acc.consume(deltaY: -6, isPrecise: true, isMomentum: false), 100)
    }

    func testMomentumAndNonsenseEventsAreIgnored() {
        var acc = OffsetWheelAccumulator()
        XCTAssertEqual(acc.consume(deltaY: -50, isPrecise: true, isMomentum: true), 0)
        XCTAssertEqual(acc.consume(deltaY: -50, isPrecise: false, isMomentum: true), 0)
        XCTAssertEqual(acc.consume(deltaY: 0, isPrecise: true, isMomentum: false), 0)
        XCTAssertEqual(acc.consume(deltaY: 0, isPrecise: false, isMomentum: false), 0)
        XCTAssertEqual(acc.consume(deltaY: .nan, isPrecise: true, isMomentum: false), 0)
        XCTAssertEqual(acc.consume(deltaY: .infinity, isPrecise: false, isMomentum: false), 0)
        // 慣性事件沒有污染累計：接著 4 點仍不足一格。
        XCTAssertEqual(acc.consume(deltaY: -4, isPrecise: true, isMomentum: false), 0)
    }

    func testResetClearsTheRemainder() {
        var acc = OffsetWheelAccumulator()
        _ = acc.consume(deltaY: 9, isPrecise: true, isMomentum: false)
        acc.reset()
        XCTAssertEqual(acc.consume(deltaY: 9, isPrecise: true, isMomentum: false), 0)
    }

    // MARK: - 點歌詞：單擊還是雙擊

    func testTapCountIsOneWhileTheSyncControlsAreOpenAndTwoOtherwise() {
        XCTAssertEqual(LyricsLineAlignGesture.tapCount(syncControlsOpen: true), 1)
        XCTAssertEqual(LyricsLineAlignGesture.tapCount(syncControlsOpen: false), 2)
    }

    // MARK: - 對時控制展開時，歌詞往上讓出空間

    func testScrollRegionLosesTheReservedHeight() {
        let panel = LyricsPanelMetrics.height(forVisibleLines: 5) // 124
        XCTAssertEqual(LyricsPanelMetrics.scrollRegionHeight(panelHeight: panel, reserved: 0), panel)
        XCTAssertEqual(LyricsPanelMetrics.scrollRegionHeight(panelHeight: panel, reserved: 56), 68)
    }

    func testScrollRegionNeverShrinksBelowTwoLines() {
        let pitch = LyricsPanelMetrics.linePitch()
        XCTAssertEqual(LyricsPanelMetrics.scrollRegionHeight(panelHeight: 76, reserved: 200), 2 * pitch)
        XCTAssertEqual(LyricsPanelMetrics.scrollRegionHeight(panelHeight: 124, reserved: -10), 124)
    }

    func testReservedFocusPutsTheCurrentLineOneLineBelowTheTop() {
        let pitch = LyricsPanelMetrics.linePitch()
        let region: CGFloat = 68
        let fraction = LyricsPanelMetrics.reservedFocusFraction(regionHeight: region)
        XCTAssertEqual(fraction * region, 2 + pitch * 1.5, accuracy: 0.001) // 上一行、目前行、下一行都在範圍內
    }

    func testReservedFocusIsClampedForTinyRegions() {
        let fraction = LyricsPanelMetrics.reservedFocusFraction(regionHeight: 48)
        XCTAssertLessThanOrEqual(fraction, 0.6)
        XCTAssertGreaterThan(fraction, 0.3)
    }
}
