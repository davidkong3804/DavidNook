import XCTest
@testable import DavidNookCore

final class VideoCapsuleStateMachineTests: XCTestCase {
    private var m = VideoCapsuleStateMachine()

    override func setUp() { m = VideoCapsuleStateMachine() }

    private func startStreaming(ratio: Double = 16.0 / 9.0, at t: Double = 0) {
        m.handle(.requestPicker, at: t)
        m.handle(.source(.started(aspectRatio: ratio)), at: t)
    }

    func testStartsIdle() {
        XCTAssertEqual(m.state, .idle)
        XCTAssertFalse(m.state.needsSource)
    }

    func testPickThenStartedStreams() {
        m.handle(.requestPicker, at: 0)
        XCTAssertEqual(m.state, .choosing)
        m.handle(.source(.started(aspectRatio: 1.5)), at: 1)
        XCTAssertEqual(m.state, .streaming(aspectRatio: 1.5))
        XCTAssertTrue(m.state.needsSource)
    }

    func testCancelFromIdleReturnsToIdle() {
        m.handle(.requestPicker, at: 0)
        m.handle(.source(.selectionCancelled), at: 1)
        XCTAssertEqual(m.state, .idle)
    }

    func testCancelWhileRepickingKeepsTheCurrentStream() {
        startStreaming()
        m.handle(.requestPicker, at: 5)
        XCTAssertEqual(m.state, .choosing)
        m.handle(.source(.selectionCancelled), at: 6)
        XCTAssertEqual(m.state, .streaming(aspectRatio: 16.0 / 9.0))
    }

    func testCancelAfterSourceClosedGoesBackToSourceClosed() {
        startStreaming()
        m.handle(.source(.sourceClosed), at: 2)
        m.handle(.requestPicker, at: 3)
        m.handle(.source(.selectionCancelled), at: 4)
        XCTAssertEqual(m.state, .sourceClosed)
    }

    func testSourceClosedFromStreaming() {
        startStreaming()
        m.handle(.source(.sourceClosed), at: 3)
        XCTAssertEqual(m.state, .sourceClosed)
        XCTAssertFalse(m.state.needsSource)
    }

    func testStreamErrorsCarryAReason() {
        startStreaming()
        m.handle(.source(.failed(.streamStopped(code: -3805))), at: 3)
        XCTAssertEqual(m.state, .error(.streamStopped(code: -3805)))
    }

    func testPickerFailureWhileChoosing() {
        m.handle(.requestPicker, at: 0)
        m.handle(.source(.failed(.pickerFailed)), at: 1)
        XCTAssertEqual(m.state, .error(.pickerFailed))
    }

    func testPermissionDeniedIsAnError() {
        m.handle(.requestPicker, at: 0)
        m.handle(.source(.failed(.permissionDenied)), at: 1)
        XCTAssertEqual(m.state, .error(.permissionDenied))
    }

    func testErrorRecoversByPickingAgain() {
        m.handle(.source(.failed(.unknown)), at: 0)
        XCTAssertEqual(m.state, .error(.unknown))
        m.handle(.requestPicker, at: 1)
        m.handle(.source(.started(aspectRatio: 2)), at: 2)
        XCTAssertEqual(m.state, .streaming(aspectRatio: 2))
    }

    func testCancelFromErrorReturnsToError() {
        m.handle(.source(.failed(.unknown)), at: 0)
        m.handle(.requestPicker, at: 1)
        m.handle(.source(.selectionCancelled), at: 2)
        XCTAssertEqual(m.state, .error(.unknown))
    }

    func testStopGoesIdleFromEveryState() {
        startStreaming()
        m.handle(.userStopped, at: 1)
        XCTAssertEqual(m.state, .idle)
        m.handle(.requestPicker, at: 2)
        m.handle(.userStopped, at: 3)
        XCTAssertEqual(m.state, .idle)
        m.handle(.source(.failed(.unknown)), at: 4)
        m.handle(.userStopped, at: 5)
        XCTAssertEqual(m.state, .idle)
    }

    func testSustainedBlackBecomesBlackContentAndRecovers() {
        startStreaming(at: 0)
        for t in stride(from: 1.0, through: 3.0, by: 1.0) { m.handle(.source(.brightness(0)), at: t) }
        XCTAssertEqual(m.state, .streaming(aspectRatio: 16.0 / 9.0), "黑了 2 秒（1→3）還不到 3 秒")
        m.handle(.source(.brightness(0)), at: 4)
        XCTAssertEqual(m.state, .blackContent(aspectRatio: 16.0 / 9.0))
        m.handle(.source(.brightness(60)), at: 5)
        XCTAssertEqual(m.state, .streaming(aspectRatio: 16.0 / 9.0))
    }

    func testTransitionBlackStaysStreaming() {
        startStreaming(at: 0)
        m.handle(.source(.brightness(0)), at: 1)
        m.handle(.source(.brightness(0)), at: 2)
        m.handle(.source(.brightness(50)), at: 2.5)
        XCTAssertEqual(m.state, .streaming(aspectRatio: 16.0 / 9.0))
    }

    func testBrightnessIsIgnoredOutsideStreaming() {
        m.handle(.source(.brightness(0)), at: 0)
        m.handle(.source(.brightness(0)), at: 10)
        XCTAssertEqual(m.state, .idle)
    }

    func testNewStreamStartsWithAFreshBlackClock() {
        startStreaming(at: 0)
        m.handle(.source(.brightness(0)), at: 1)
        m.handle(.source(.brightness(0)), at: 2)
        startStreaming(at: 2.5)
        m.handle(.source(.brightness(0)), at: 3)
        XCTAssertEqual(m.state, .streaming(aspectRatio: 16.0 / 9.0), "換視窗後黑場計時要重來")
    }

    func testSourceClosedWhileBlack() {
        startStreaming(at: 0)
        m.handle(.source(.brightness(0)), at: 1)
        m.handle(.source(.brightness(0)), at: 5)
        m.handle(.source(.sourceClosed), at: 6)
        XCTAssertEqual(m.state, .sourceClosed)
    }

    func testFrameSizeChangeUpdatesAspectRatio() {
        startStreaming()
        m.handle(.source(.frameSize(width: 800, height: 400)), at: 1)
        XCTAssertEqual(m.state, .streaming(aspectRatio: 2))
    }

    func testDegenerateFrameSizeIsIgnored() {
        startStreaming()
        m.handle(.source(.frameSize(width: 0, height: 400)), at: 1)
        m.handle(.source(.frameSize(width: 100, height: 0)), at: 1)
        XCTAssertEqual(m.state, .streaming(aspectRatio: 16.0 / 9.0))
    }

    func testStartedWithBadRatioFallsBackTo16by9() {
        m.handle(.requestPicker, at: 0)
        m.handle(.source(.started(aspectRatio: 0)), at: 1)
        XCTAssertEqual(m.state, .streaming(aspectRatio: 16.0 / 9.0))
        m.handle(.source(.started(aspectRatio: .nan)), at: 2)
        XCTAssertEqual(m.state, .streaming(aspectRatio: 16.0 / 9.0))
    }

    func testStrayEventsInIdleAreIgnored() {
        m.handle(.source(.sourceClosed), at: 0)
        m.handle(.source(.selectionCancelled), at: 0)
        m.handle(.source(.frameSize(width: 10, height: 10)), at: 0)
        XCTAssertEqual(m.state, .idle)
    }

    func testFailureWhileIdleIsStillSurfacedAsError() {
        m.handle(.source(.failed(.permissionDenied)), at: 0)
        XCTAssertEqual(m.state, .error(.permissionDenied))
    }

    func testFailureReasonsDoNotLeakDetails() {
        // 只有狀態與錯誤碼，不含視窗標題或 App 名稱。
        XCTAssertEqual(VideoFailure.streamStopped(code: 7).logDescription, "streamStopped(7)")
        XCTAssertEqual(VideoFailure.permissionDenied.logDescription, "permissionDenied")
    }

    /// 串流中連續 4 秒全黑（每秒一個樣本，t = 1…4）→ blackContent。
    private func goBlack() {
        for t in 1...4 { m.handle(.source(.brightness(0)), at: Double(t)) }
    }

    // MARK: - 釘選（點一下影片＝把影片釘成瀏海外面的膠囊）

    func testStartsUnpinned() {
        XCTAssertFalse(m.isPinned)
    }

    func testTogglePinOnlyWhileStreaming() {
        m.handle(.togglePin, at: 0)
        XCTAssertFalse(m.isPinned, "沒有串流不能釘選")
        startStreaming()
        m.handle(.togglePin, at: 1)
        XCTAssertTrue(m.isPinned)
        m.handle(.togglePin, at: 2)
        XCTAssertFalse(m.isPinned)
    }

    func testCannotPinWhileChoosingOrBlackOrClosed() {
        m.handle(.requestPicker, at: 0)
        m.handle(.togglePin, at: 0)
        XCTAssertFalse(m.isPinned)
        m.handle(.source(.selectionCancelled), at: 0)
        startStreaming(at: 0)
        goBlack()
        XCTAssertEqual(m.state, .blackContent(aspectRatio: 16.0 / 9.0))
        m.handle(.togglePin, at: 6)
        XCTAssertFalse(m.isPinned, "黑畫面（疑似受保護）沒有東西可釘")
    }

    func testPinSurvivesRepickCancelAndWindowChange() {
        startStreaming()
        m.handle(.togglePin, at: 1)
        m.handle(.requestPicker, at: 2)
        XCTAssertTrue(m.isPinned)
        m.handle(.source(.selectionCancelled), at: 3)
        XCTAssertTrue(m.isPinned)
        m.handle(.requestPicker, at: 4)
        m.handle(.source(.started(aspectRatio: 1.5)), at: 5)
        XCTAssertEqual(m.state, .streaming(aspectRatio: 1.5))
        XCTAssertTrue(m.isPinned, "換視窗後釘選維持")
    }

    /// M-C 決議：已釘選時偵測到持續黑畫面（疑似受保護）→ 膠囊不顯示黑塊，改為自動取消釘選；恢復非黑後不會自己再釘。
    func testBlackContentAutoUnpinsAndDoesNotRepinOnRecovery() {
        startStreaming(at: 0)
        m.handle(.togglePin, at: 0)
        goBlack()
        XCTAssertEqual(m.state, .blackContent(aspectRatio: 16.0 / 9.0))
        XCTAssertFalse(m.isPinned)
        m.handle(.source(.brightness(80)), at: 6)
        XCTAssertEqual(m.state, .streaming(aspectRatio: 16.0 / 9.0))
        XCTAssertFalse(m.isPinned)
        m.handle(.togglePin, at: 7)
        XCTAssertTrue(m.isPinned, "恢復後可以重新釘選")
    }

    func testStopSourceClosedAndErrorsAutoUnpin() {
        // 決議：串流結束一律自動取消釘選（沒有畫面的膠囊沒有意義；重新啟動 App 也不會殘留釘選）。
        for ending in [VideoCapsuleInput.userStopped, .source(.sourceClosed), .source(.failed(.unknown)), .source(.failed(.streamStopped(code: 1)))] {
            m = VideoCapsuleStateMachine()
            startStreaming()
            m.handle(.togglePin, at: 1)
            XCTAssertTrue(m.isPinned)
            m.handle(ending, at: 2)
            XCTAssertFalse(m.isPinned, "\(ending)")
        }
    }

    func testPinnedThenBlackThenClosedUnpins() {
        startStreaming(at: 0)
        m.handle(.togglePin, at: 0)
        goBlack()
        m.handle(.source(.sourceClosed), at: 6)
        XCTAssertFalse(m.isPinned)
        XCTAssertEqual(m.state, .sourceClosed)
    }

    func testClosedWhileRepickingUnpins() {
        startStreaming()
        m.handle(.togglePin, at: 1)
        m.handle(.requestPicker, at: 2)
        m.handle(.source(.sourceClosed), at: 3)
        XCTAssertFalse(m.isPinned)
        m.handle(.source(.selectionCancelled), at: 4)
        XCTAssertEqual(m.state, .sourceClosed)
    }

    func testSlotAspectRatio() {
        XCTAssertNil(VideoCapsuleState.idle.slotAspectRatio)
        XCTAssertNil(VideoCapsuleState.choosing.slotAspectRatio)
        XCTAssertEqual(VideoCapsuleState.streaming(aspectRatio: 1.5).slotAspectRatio, 1.5)
        XCTAssertEqual(VideoCapsuleState.blackContent(aspectRatio: 2).slotAspectRatio, 2)
        XCTAssertEqual(VideoCapsuleState.sourceClosed.slotAspectRatio ?? 0, 16.0 / 9.0, accuracy: 1e-12)
        XCTAssertEqual(VideoCapsuleState.error(.unknown).slotAspectRatio ?? 0, 16.0 / 9.0, accuracy: 1e-12)
    }

    // MARK: 裁切

    func testCropChangedUpdatesTheRatioKeepsPinAndResetsTheBlackClock() {
        startStreaming(at: 0)
        m.handle(.togglePin, at: 0)
        m.handle(.source(.brightness(0)), at: 1)
        m.handle(.source(.brightness(0)), at: 2)
        m.handle(.source(.cropChanged(aspectRatio: 1.0)), at: 2.5)
        XCTAssertEqual(m.state, .streaming(aspectRatio: 1.0))
        XCTAssertTrue(m.isPinned)
        // 重新計時：裁切後要再連續黑 3 秒才判黑，不會被裁切前的黑樣本影響。
        m.handle(.source(.brightness(0)), at: 3)
        m.handle(.source(.brightness(0)), at: 4)
        m.handle(.source(.brightness(0)), at: 5)
        XCTAssertEqual(m.state, .streaming(aspectRatio: 1.0), "從 3 秒起算，到 5 秒只有 2 秒")
        m.handle(.source(.brightness(0)), at: 6)
        XCTAssertEqual(m.state, .blackContent(aspectRatio: 1.0))
    }

    func testCropChangedWhileBlackReturnsToStreamingAndInvalidRatiosFallBack() {
        startStreaming(at: 0)
        goBlack()
        XCTAssertEqual(m.state, .blackContent(aspectRatio: 16.0 / 9.0))
        m.handle(.source(.cropChanged(aspectRatio: .nan)), at: 6)
        XCTAssertEqual(m.state, .streaming(aspectRatio: 16.0 / 9.0), "異常比例退回 16:9")
    }

    func testCropChangedIsIgnoredWithoutAStream() {
        m.handle(.source(.cropChanged(aspectRatio: 1.5)), at: 0)
        XCTAssertEqual(m.state, .idle)
        m.handle(.source(.sourceClosed), at: 0)
        m.handle(.source(.cropChanged(aspectRatio: 1.5)), at: 1)
        XCTAssertEqual(m.state, .idle)
    }
}
