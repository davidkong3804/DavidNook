import XCTest
@testable import DavidNookCore

/// F2／F7(d)：暫停、恢復、權限變化的決策（ClipboardRecordingPlanner）與定期維護（ClipboardMaintenance）。
/// 全部以 FakePasteboard、手動排程器與記憶體持久化測試，不碰系統剪貼簿。
final class ClipboardRecordingPlannerTests: XCTestCase {
    private typealias Inputs = ClipboardRecordingInputs

    private let recording = Inputs(enabled: true, userPaused: false, access: .allowed)
    private let userPaused = Inputs(enabled: true, userPaused: true, access: .allowed)
    private let disabled = Inputs(enabled: false, userPaused: false, access: .allowed)
    private let denied = Inputs(enabled: true, userPaused: false, access: .denied)
    private let asking = Inputs(enabled: true, userPaused: false, access: .askEveryTime)

    // MARK: 純決策

    func testEffectivePausedIsDisabledOrUserPaused() {
        XCTAssertFalse(ClipboardRecordingPlanner.effectivePaused(recording))
        XCTAssertTrue(ClipboardRecordingPlanner.effectivePaused(userPaused))
        XCTAssertTrue(ClipboardRecordingPlanner.effectivePaused(disabled))
        XCTAssertFalse(ClipboardRecordingPlanner.effectivePaused(denied), "權限被拒不等於使用者暫停；只是不讀")
    }

    func testMonitorRunsOnlyWhenEnabledAndSystemAllowsReading() {
        XCTAssertTrue(ClipboardRecordingPlanner.shouldMonitor(recording))
        XCTAssertTrue(ClipboardRecordingPlanner.shouldMonitor(userPaused), "使用者暫停時 monitor 照跑（只消耗 changeCount）")
        XCTAssertFalse(ClipboardRecordingPlanner.shouldMonitor(disabled))
        XCTAssertFalse(ClipboardRecordingPlanner.shouldMonitor(denied))
        XCTAssertFalse(ClipboardRecordingPlanner.shouldMonitor(asking))
    }

    func testSteadyStateNeedsNoSteps() {
        XCTAssertEqual(ClipboardRecordingPlanner.steps(for: recording, storeIsPaused: false, monitorIsRunning: true), [])
        XCTAssertEqual(ClipboardRecordingPlanner.steps(for: userPaused, storeIsPaused: true, monitorIsRunning: true), [])
        XCTAssertEqual(ClipboardRecordingPlanner.steps(for: disabled, storeIsPaused: true, monitorIsRunning: false), [])
        XCTAssertEqual(ClipboardRecordingPlanner.steps(for: denied, storeIsPaused: false, monitorIsRunning: false), [])
    }

    func testPausingJustPausesTheStore() {
        XCTAssertEqual(ClipboardRecordingPlanner.steps(for: userPaused, storeIsPaused: false, monitorIsRunning: true), [.pauseStore])
    }

    func testResumeButtonPathSyncsBaselineBeforeResumingTheStore() {
        XCTAssertEqual(ClipboardRecordingPlanner.steps(for: recording, storeIsPaused: true, monitorIsRunning: true),
                       [.syncBaseline, .resumeStore], "設定開關／暫停按鈕的恢復路徑：先對齊基準，再恢復")
    }

    func testReEnablingTheFeatureSyncsBaselineBeforeResumingAndStarting() {
        XCTAssertEqual(ClipboardRecordingPlanner.steps(for: recording, storeIsPaused: true, monitorIsRunning: false),
                       [.syncBaseline, .resumeStore, .startMonitor])
    }

    func testPermissionGrantedAfterDenialSyncsBaselineBeforeStartingTheMonitor() {
        XCTAssertEqual(ClipboardRecordingPlanner.steps(for: recording, storeIsPaused: false, monitorIsRunning: false),
                       [.syncBaseline, .startMonitor], "權限由拒絕轉允許：同樣要先對齊基準")
    }

    func testDisablingPausesTheStoreAndStopsTheMonitor() {
        XCTAssertEqual(ClipboardRecordingPlanner.steps(for: disabled, storeIsPaused: false, monitorIsRunning: true),
                       [.pauseStore, .stopMonitor])
    }

    func testPermissionRevokedOnlyStopsTheMonitor() {
        XCTAssertEqual(ClipboardRecordingPlanner.steps(for: denied, storeIsPaused: false, monitorIsRunning: true), [.stopMonitor])
        XCTAssertEqual(ClipboardRecordingPlanner.steps(for: asking, storeIsPaused: false, monitorIsRunning: true), [.stopMonitor])
    }

    func testEveryResumePathPutsSyncBaselineBeforeResumeAndStart() {
        for inputs in [recording] {
            for storeIsPaused in [true, false] {
                for monitorIsRunning in [true, false] {
                    let steps = ClipboardRecordingPlanner.steps(for: inputs, storeIsPaused: storeIsPaused, monitorIsRunning: monitorIsRunning)
                    for gated in [ClipboardRecordingStep.resumeStore, .startMonitor] where steps.contains(gated) {
                        let sync = steps.firstIndex(of: .syncBaseline)
                        XCTAssertNotNil(sync, "\(steps) 缺少 syncBaseline")
                        XCTAssertLessThan(sync ?? Int.max, steps.firstIndex(of: gated) ?? 0, "\(steps)：syncBaseline 必須在 \(gated) 之前")
                    }
                }
            }
        }
    }

    // MARK: 套用到真實 store／monitor（F2：暫停期間複製的內容，恢復後不補記）

    private struct Rig {
        let monitor: ClipboardMonitor
        let pasteboard: FakePasteboard
        let store: ClipboardStore
    }

    private func makeRig() -> Rig {
        let pasteboard = FakePasteboard()
        let store = ClipboardStore(persistence: InMemoryClipboardPersistence())
        let monitor = ClipboardMonitor(reader: pasteboard, store: store, scheduler: ManualClipboardScheduler())
        return Rig(monitor: monitor, pasteboard: pasteboard, store: store)
    }

    private func texts(_ rig: Rig) async -> [String] {
        await rig.store.items.compactMap(\.text)
    }

    func testCopyWhilePausedThenResumeBeforeNextPollIsNotBackfilled() async {
        let rig = makeRig()
        await ClipboardRecordingPlanner.apply(recording, store: rig.store, monitor: rig.monitor)
        await ClipboardRecordingPlanner.apply(userPaused, store: rig.store, monitor: rig.monitor)

        rig.pasteboard.copy([PBType.utf8Text: utf8("copied while paused")])     // 暫停期間複製，monitor 還沒輪詢到
        await ClipboardRecordingPlanner.apply(recording, store: rig.store, monitor: rig.monitor)   // 恢復
        await rig.monitor.pollOnce(now: t(1))

        let recorded = await texts(rig)
        XCTAssertEqual(recorded, [], "暫停期間複製的內容，恢復後的第一次輪詢也不得補記")
        XCTAssertEqual(rig.pasteboard.snapshotCallCount, 0, "對齊基準不讀內容，之後也不該讀")

        rig.pasteboard.copy([PBType.utf8Text: utf8("after resume")])
        await rig.monitor.pollOnce(now: t(2))
        let afterResume = await texts(rig)
        XCTAssertEqual(afterResume, ["after resume"], "恢復之後的複製要正常記錄")
    }

    func testCopyWhileFeatureDisabledThenReEnabledIsNotBackfilled() async {
        let rig = makeRig()
        await ClipboardRecordingPlanner.apply(recording, store: rig.store, monitor: rig.monitor)
        await ClipboardRecordingPlanner.apply(disabled, store: rig.store, monitor: rig.monitor)
        rig.pasteboard.copy([PBType.utf8Text: utf8("copied while disabled")])
        await ClipboardRecordingPlanner.apply(recording, store: rig.store, monitor: rig.monitor)
        await rig.monitor.pollOnce(now: t(1))
        let recorded = await texts(rig)
        XCTAssertEqual(recorded, [])
    }

    func testCopyWhilePermissionDeniedThenGrantedIsNotBackfilled() async {
        let rig = makeRig()
        await ClipboardRecordingPlanner.apply(recording, store: rig.store, monitor: rig.monitor)
        await ClipboardRecordingPlanner.apply(denied, store: rig.store, monitor: rig.monitor)
        let running = await rig.monitor.isRunning
        XCTAssertFalse(running, "權限被拒時 monitor 必須停止，完全不讀")
        rig.pasteboard.copy([PBType.utf8Text: utf8("copied while denied")])
        await ClipboardRecordingPlanner.apply(recording, store: rig.store, monitor: rig.monitor)
        await rig.monitor.pollOnce(now: t(1))
        let recorded = await texts(rig)
        XCTAssertEqual(recorded, [])
        XCTAssertEqual(rig.pasteboard.snapshotCallCount, 0)
    }

    func testApplyingTheSameInputsTwiceIsHarmless() async {
        let rig = makeRig()
        await ClipboardRecordingPlanner.apply(recording, store: rig.store, monitor: rig.monitor)
        rig.pasteboard.copy([PBType.utf8Text: utf8("normal copy")])
        await ClipboardRecordingPlanner.apply(recording, store: rig.store, monitor: rig.monitor)   // 沒有狀態變化：不得重設基準
        await rig.monitor.pollOnce(now: t(1))
        let recorded = await texts(rig)
        XCTAssertEqual(recorded, ["normal copy"], "穩定狀態下重複套用不得吃掉正常的複製")
    }
}

final class ClipboardMaintenanceTests: XCTestCase {
    func testDefaultPruneIntervalIsAtMostFiveMinutes() {
        XCTAssertLessThanOrEqual(ClipboardMaintenance.pruneInterval, 300, "保留期「1 天」不應實際 25 小時才清")
        XCTAssertGreaterThan(ClipboardMaintenance.pruneInterval, 0)
    }

    func testStartSchedulesOnceAtTheDefaultIntervalAndStopCancels() throws {
        let scheduler = ManualClipboardScheduler()
        let maintenance = ClipboardMaintenance(store: ClipboardStore(persistence: InMemoryClipboardPersistence()), scheduler: scheduler)
        maintenance.start()
        maintenance.start()
        XCTAssertEqual(scheduler.scheduledIntervals, [ClipboardMaintenance.pruneInterval])
        XCTAssertLessThanOrEqual(try XCTUnwrap(scheduler.scheduledIntervals.first), 300)
        XCTAssertTrue(maintenance.isRunning)
        maintenance.stop()
        XCTAssertEqual(scheduler.activeCount, 0)
        XCTAssertFalse(maintenance.isRunning)
    }

    func testEachTickPrunesExpiredItemsAndNotifies() async {
        let scheduler = ManualClipboardScheduler()
        let store = ClipboardStore(persistence: InMemoryClipboardPersistence(), retention: 60)
        _ = await store.add(ClipboardCapture(text: "ancient"), now: t(1))    // 2023 年：相對於現在早已過期
        let pinned = await store.add(ClipboardCapture(text: "pinned ancient"), now: t(2))
        if case .inserted(let item) = pinned { _ = await store.togglePin(id: item.id) }

        let ticks = TickCounter()
        let maintenance = ClipboardMaintenance(store: store, scheduler: scheduler) { ticks.increment() }
        maintenance.start()
        await scheduler.fire()

        let remaining = await store.items.compactMap(\.text)
        XCTAssertEqual(remaining, ["pinned ancient"], "tick 要 prune 過期且未釘選的條目")
        XCTAssertEqual(ticks.value, 1)
    }

    func testStopSilencesFurtherTicks() async {
        let scheduler = ManualClipboardScheduler()
        let store = ClipboardStore(persistence: InMemoryClipboardPersistence(), retention: 60)
        let maintenance = ClipboardMaintenance(store: store, scheduler: scheduler)
        maintenance.start()
        maintenance.stop()
        _ = await store.add(ClipboardCapture(text: "ancient"), now: t(1))
        await scheduler.fire()
        let count = await store.items.count
        XCTAssertEqual(count, 1)
    }
}

private final class TickCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    var value: Int { lock.withLock { n } }
    func increment() { lock.withLock { n += 1 } }
}
