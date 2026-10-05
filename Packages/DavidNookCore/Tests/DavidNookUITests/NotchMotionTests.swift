import SwiftUI
import XCTest
@testable import DavidNookUI

/// 瀏海動畫常數與曲線的數值測試：以 SwiftUI `Spring.value(target:initialVelocity:time:)`
/// （經 `NotchMotionCurve.progress(at:)`）逐毫秒掃描，量過衝與進入 ±1% 穩定帶的時間。
final class NotchMotionTests: XCTestCase {
    private let motion = NotchMotion()

    /// 掃描 0…3 秒（1 ms 間隔）：最大過衝（相對目標 1.0）與最後一次離開 ±1% 帶的時間。
    private func scan(_ curve: NotchMotionCurve) -> (overshoot: Double, settle: TimeInterval, monotonic: Bool) {
        var peak = 0.0
        var settle = 0.0
        var previous = 0.0
        var monotonic = true
        var t = 0.0
        while t <= 3.0 {
            let p = curve.progress(at: t)
            peak = max(peak, p)
            if abs(p - 1) > 0.01 { settle = t }
            if p < previous - 1e-9 { monotonic = false }
            previous = p
            t += 0.001
        }
        return (max(0, peak - 1), settle, monotonic)
    }

    private func spring(_ curve: NotchMotionCurve, file: StaticString = #filePath, line: UInt = #line) throws -> Spring {
        guard case .spring(let s) = curve else {
            XCTFail("預期為彈簧曲線：\(curve)", file: file, line: line)
            throw XCTSkip("not a spring")
        }
        return s
    }

    // MARK: - 展開

    func testOpenSpringParametersMatchTheDesign() throws {
        let s = try spring(motion.curve(.open))
        XCTAssertEqual(s.response, 0.46, accuracy: 1e-9)
        XCTAssertEqual(s.dampingRatio, 0.72, accuracy: 1e-9)
    }

    func testOpenOvershootIsBetweenThreeAndSixPercent() {
        let r = scan(motion.curve(.open))
        XCTAssertGreaterThanOrEqual(r.overshoot, 0.03, "過衝太小，看不出彈性")
        XCTAssertLessThanOrEqual(r.overshoot, 0.06, "過衝太大，會顯得誇張")
    }

    func testOpenSettlesIntoOnePercentBandWithinAboutPointSixSeconds() {
        let r = scan(motion.curve(.open))
        XCTAssertLessThanOrEqual(r.settle, 0.6)
        XCTAssertGreaterThan(r.settle, 0.3, "不應瞬間完成")
    }

    // MARK: - 收合

    func testCloseSpringParametersMatchTheDesign() throws {
        let s = try spring(motion.curve(.close))
        XCTAssertEqual(s.response, 0.34, accuracy: 1e-9)
        XCTAssertEqual(s.dampingRatio, 0.9, accuracy: 1e-9)
    }

    func testCloseHasNoVisibleOvershootAndIsFasterThanOpen() {
        let close = scan(motion.curve(.close))
        let open = scan(motion.curve(.open))
        XCTAssertLessThan(close.overshoot, 0.01)
        XCTAssertLessThan(close.settle, open.settle)
        XCTAssertLessThanOrEqual(close.settle, 0.4)
    }

    // MARK: - 分頁切換與 hover 預期動作

    func testTabSwitchSpringParametersMatchTheDesign() throws {
        let s = try spring(motion.curve(.tabSwitch))
        XCTAssertEqual(s.response, 0.38, accuracy: 1e-9)
        XCTAssertEqual(s.dampingRatio, 0.82, accuracy: 1e-9)
        XCTAssertLessThan(scan(motion.curve(.tabSwitch)).overshoot, 0.02)
    }

    func testAnticipationSpringAndScale() throws {
        let s = try spring(motion.curve(.anticipate))
        XCTAssertEqual(s.response, 0.2, accuracy: 1e-9)
        XCTAssertEqual(s.dampingRatio, 0.7, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(motion.anticipationScale, 1.03)
        XCTAssertLessThanOrEqual(motion.anticipationScale, 1.05)
    }

    // MARK: - 速度倍率

    func testSpeedMultiplierScalesResponse() throws {
        let fast = NotchMotion(speed: 2)
        let slow = NotchMotion(speed: 0.5)
        for phase in NotchMotion.Phase.allCases {
            let base = try spring(motion.curve(phase))
            XCTAssertEqual(try spring(fast.curve(phase)).response, base.response / 2, accuracy: 1e-9, "\(phase)")
            XCTAssertEqual(try spring(slow.curve(phase)).response, base.response * 2, accuracy: 1e-9, "\(phase)")
            // 阻尼比不變：形狀相同，只是時間軸縮放。
            XCTAssertEqual(try spring(fast.curve(phase)).dampingRatio, base.dampingRatio, accuracy: 1e-9)
        }
    }

    func testSpeedMultiplierIsAPureTimeScaling() {
        let fast = NotchMotion(speed: 2)
        for t in stride(from: 0.0, through: 0.5, by: 0.025) {
            XCTAssertEqual(
                fast.curve(.open).progress(at: t),
                motion.curve(.open).progress(at: 2 * t),
                accuracy: 1e-6, "t=\(t)"
            )
        }
        XCTAssertEqual(scan(fast.curve(.open)).settle, scan(motion.curve(.open)).settle / 2, accuracy: 0.01)
    }

    func testSpeedMultiplierScalesContentTimingToo() {
        let fast = NotchMotion(speed: 2)
        XCTAssertEqual(fast.contentRevealDelay, motion.contentRevealDelay / 2, accuracy: 1e-9)
        XCTAssertEqual(scan(fast.contentHideCurve).settle, scan(motion.contentHideCurve).settle / 2, accuracy: 0.01)
    }

    func testSpeedIsClamped() {
        XCTAssertEqual(NotchMotion(speed: 0).speed, NotchMotion.speedRange.lowerBound)
        XCTAssertEqual(NotchMotion(speed: -3).speed, NotchMotion.speedRange.lowerBound)
        XCTAssertEqual(NotchMotion(speed: 99).speed, NotchMotion.speedRange.upperBound)
        XCTAssertEqual(NotchMotion(speed: .nan).speed, 1)
        XCTAssertEqual(NotchMotion(speed: 1.5).speed, 1.5)
    }

    // MARK: - 減少動態

    func testReduceMotionUsesTwoHundredMillisecondEaseWithoutOvershoot() {
        let reduced = NotchMotion(reduceMotion: true)
        for phase in [NotchMotion.Phase.open, .close, .tabSwitch] {
            let curve = reduced.curve(phase)
            guard case .easeInOut(let duration) = curve else {
                XCTFail("\(phase) 在減少動態下應為 easeInOut：\(curve)")
                continue
            }
            XCTAssertEqual(duration, 0.2, accuracy: 1e-9)
            let r = scan(curve)
            XCTAssertEqual(r.overshoot, 0, accuracy: 1e-9, "\(phase) 不得過衝")
            XCTAssertTrue(r.monotonic, "\(phase) 應單調")
            XCTAssertEqual(r.settle, 0.2, accuracy: 0.03)
            XCTAssertEqual(curve.progress(at: 0), 0, accuracy: 1e-9)
            XCTAssertEqual(curve.progress(at: 0.2), 1, accuracy: 1e-6)
        }
    }

    func testReduceMotionDropsBlurScaleOffsetAndAnticipation() {
        let reduced = NotchMotion(reduceMotion: true)
        XCTAssertEqual(reduced.hiddenContentStyle.blur, 0)
        XCTAssertEqual(reduced.hiddenContentStyle.scale, 1)
        XCTAssertEqual(reduced.hiddenContentStyle.offsetY, 0)
        XCTAssertEqual(reduced.hiddenContentStyle.opacity, 0)
        XCTAssertEqual(reduced.anticipationScale, 1)
        XCTAssertEqual(reduced.contentRevealDelay, 0)
        // 整段內容轉場過程中也不得出現模糊或位移。
        for t in stride(from: 0.0, through: 0.4, by: 0.02) {
            for revealing in [true, false] {
                let style = reduced.contentStyle(revealing: revealing, at: t)
                XCTAssertEqual(style.blur, 0, "t=\(t)")
                XCTAssertEqual(style.scale, 1, "t=\(t)")
                XCTAssertEqual(style.offsetY, 0, "t=\(t)")
            }
        }
    }

    func testReduceMotionStillScalesWithSpeed() throws {
        let reduced = NotchMotion(speed: 2, reduceMotion: true)
        guard case .easeInOut(let duration) = reduced.curve(.open) else { return XCTFail("應為 easeInOut") }
        XCTAssertEqual(duration, 0.1, accuracy: 1e-9)
    }

    // MARK: - 動畫關閉（設定「Notch animation」）

    func testDisabledMotionIsInstant() {
        let off = NotchMotion(isEnabled: false)
        for phase in NotchMotion.Phase.allCases {
            XCTAssertEqual(off.curve(phase), .instant, "\(phase)")
            XCTAssertEqual(off.curve(phase).progress(at: 0), 1)
        }
        XCTAssertEqual(off.anticipationScale, 1)
        XCTAssertEqual(off.contentRevealDelay, 0)
        XCTAssertEqual(off.contentStyle(revealing: true, at: 0), NotchMotion.ContentStyle(opacity: 1, blur: 0, scale: 1, offsetY: 0))
        XCTAssertEqual(off.settleTime(for: .open), 0, accuracy: 1e-9)
    }

    // MARK: - 內容層

    func testContentRevealDelaysThenFadesInWithBlurScaleAndOffset() {
        let hidden = motion.hiddenContentStyle
        XCTAssertEqual(hidden, NotchMotion.ContentStyle(opacity: 0, blur: 10, scale: 0.97, offsetY: 4))
        XCTAssertGreaterThanOrEqual(motion.contentRevealDelay, 0.08)
        XCTAssertLessThanOrEqual(motion.contentRevealDelay, 0.10)

        // 延遲期間維持完全隱藏。
        XCTAssertEqual(motion.contentStyle(revealing: true, at: 0), hidden)
        XCTAssertEqual(motion.contentStyle(revealing: true, at: motion.contentRevealDelay - 0.001), hidden)

        // 延遲之後單調地淡入、去模糊、放大到 1、位移歸零，且不過衝。
        var previous = hidden
        var t = motion.contentRevealDelay
        while t <= 0.8 {
            let s = motion.contentStyle(revealing: true, at: t)
            XCTAssertGreaterThanOrEqual(s.opacity, previous.opacity - 1e-9)
            XCTAssertLessThanOrEqual(s.blur, previous.blur + 1e-9)
            XCTAssertGreaterThanOrEqual(s.scale, previous.scale - 1e-9)
            XCTAssertLessThanOrEqual(s.offsetY, previous.offsetY + 1e-9)
            XCTAssertLessThanOrEqual(s.opacity, 1 + 1e-9)
            XCTAssertLessThanOrEqual(s.scale, 1 + 1e-6)
            XCTAssertGreaterThanOrEqual(s.blur, -1e-6)
            previous = s
            t += 0.005
        }
        let end = motion.contentStyle(revealing: true, at: 1.0)
        XCTAssertEqual(end.opacity, 1, accuracy: 0.002)
        XCTAssertEqual(end.blur, 0, accuracy: 0.02)
        XCTAssertEqual(end.scale, 1, accuracy: 0.001)
        XCTAssertEqual(end.offsetY, 0, accuracy: 0.02)
        // 中途確實在變化（不是瞬間）。
        let mid = motion.contentStyle(revealing: true, at: motion.contentRevealDelay + 0.06)
        XCTAssertGreaterThan(mid.opacity, 0.05)
        XCTAssertLessThan(mid.opacity, 0.95)
    }

    func testContentHideIsQuickAndHasNoDelay() {
        XCTAssertEqual(motion.contentStyle(revealing: false, at: 0).opacity, 1, accuracy: 1e-9)
        XCTAssertLessThan(motion.contentStyle(revealing: false, at: 0.03).opacity, 0.95, "不得有延遲，一開始就要退")
        XCTAssertEqual(motion.contentStyle(revealing: false, at: 0.12).opacity, 0, accuracy: 0.01, "約 0.12 秒內淡出")
        XCTAssertEqual(scan(motion.contentHideCurve).settle, 0.12, accuracy: 0.03)
    }

    // MARK: - 穩定時間（App 用來決定何時結束「動畫中」狀態）

    func testSettleTimesMatchMeasuredCurves() {
        for phase in NotchMotion.Phase.allCases {
            let measured = scan(motion.curve(phase)).settle
            XCTAssertEqual(motion.settleTime(for: phase), measured, accuracy: 0.02, "\(phase)")
        }
        XCTAssertGreaterThanOrEqual(motion.openSettleTime, motion.settleTime(for: .open))
        XCTAssertGreaterThanOrEqual(motion.openSettleTime, motion.contentRevealDelay)
    }

    func testAnimationsAreProvidedForEveryPhase() {
        // 只確認可取得（Animation 本身不透明）；曲線由上面的測試驗證。
        for phase in NotchMotion.Phase.allCases {
            _ = motion.animation(phase)
        }
        _ = motion.contentRevealAnimation
        _ = motion.contentHideAnimation
    }

    // MARK: - 報表（供人工檢視；不斷言）

    func testPrintMeasuredNumbers() {
        func line(_ name: String, _ curve: NotchMotionCurve) -> String {
            let r = scan(curve)
            return String(format: "NOTCHMOTION %@ overshoot=%.2f%% settle(±1%%)=%.3fs", name, r.overshoot * 100, r.settle)
        }
        print(line("open", motion.curve(.open)))
        print(line("close", motion.curve(.close)))
        print(line("tabSwitch", motion.curve(.tabSwitch)))
        print(line("anticipate", motion.curve(.anticipate)))
        print(line("contentReveal", motion.contentRevealCurve))
        print(line("contentHide", motion.contentHideCurve))
        print(line("reduceMotion.open", NotchMotion(reduceMotion: true).curve(.open)))
        print(line("speed2x.open", NotchMotion(speed: 2).curve(.open)))
        print(String(format: "NOTCHMOTION contentRevealDelay=%.3fs anticipationScale=%.2f", motion.contentRevealDelay, motion.anticipationScale))
    }
}
