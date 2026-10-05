import XCTest
@testable import DavidNookCore

/// 元件 6：ClipboardMonitor（以 changeCount 輪詢、處理自己寫回）。以 FakePasteboard 與手動排程器測試。
final class ClipboardMonitorTests: XCTestCase {
    private struct Rig {
        let monitor: ClipboardMonitor
        let pasteboard: FakePasteboard
        let store: ClipboardStore
        let persistence: InMemoryClipboardPersistence
        let scheduler: ManualClipboardScheduler
    }

    private func makeRig(
        policy: ClipboardPolicy = ClipboardPolicy(),
        interval: TimeInterval? = nil,
        logger: ClipboardLogging = NoOpClipboardLogger()
    ) -> Rig {
        let pasteboard = FakePasteboard()
        let persistence = InMemoryClipboardPersistence()
        let store = ClipboardStore(persistence: persistence, logger: logger)
        let scheduler = ManualClipboardScheduler()
        let monitor: ClipboardMonitor
        if let interval {
            monitor = ClipboardMonitor(reader: pasteboard, store: store, policy: policy, scheduler: scheduler, interval: interval, logger: logger)
        } else {
            monitor = ClipboardMonitor(reader: pasteboard, store: store, policy: policy, scheduler: scheduler, logger: logger)
        }
        return Rig(monitor: monitor, pasteboard: pasteboard, store: store, persistence: persistence, scheduler: scheduler)
    }

    private func texts(_ store: ClipboardStore) async -> [String] {
        await store.items.compactMap(\.text)
    }

    private func firstItem(_ store: ClipboardStore, file: StaticString = #filePath, line: UInt = #line) async throws -> ClipboardItem {
        let items = await store.items
        return try XCTUnwrap(items.first, file: file, line: line)
    }

    private func lastItem(_ store: ClipboardStore, file: StaticString = #filePath, line: UInt = #line) async throws -> ClipboardItem {
        let items = await store.items
        return try XCTUnwrap(items.last, file: file, line: line)
    }

    // MARK: changeCount 輪詢

    func testUnchangedChangeCountNeverReadsPasteboardContents() async {
        let rig = makeRig()
        rig.pasteboard.copy([PBType.utf8Text: utf8("already there")])
        await rig.monitor.start()
        for _ in 0..<10 { await rig.monitor.pollOnce(now: t(1)) }
        XCTAssertEqual(rig.pasteboard.snapshotCallCount, 0, "changeCount 沒變就不得讀取任何內容")
        XCTAssertTrue(rig.pasteboard.dataReadTypes.isEmpty)
        let items = await rig.store.items
        XCTAssertTrue(items.isEmpty, "啟動前就在剪貼簿上的內容不讀、不記")
    }

    func testChangedChangeCountReadsExactlyOnceAndRecordsText() async {
        let rig = makeRig()
        await rig.monitor.start()
        rig.pasteboard.copy([PBType.utf8Text: utf8("hello")])
        await rig.monitor.pollOnce(now: t(1))
        await rig.monitor.pollOnce(now: t(2))
        await rig.monitor.pollOnce(now: t(3))
        XCTAssertEqual(rig.pasteboard.snapshotCallCount, 1)
        let order = await texts(rig.store)
        XCTAssertEqual(order, ["hello"])
    }

    func testRapidChangesBetweenPollsRecordOnlyTheLatestContent() async {
        let rig = makeRig()
        await rig.monitor.start()
        rig.pasteboard.copy([PBType.utf8Text: utf8("A")])
        rig.pasteboard.copy([PBType.utf8Text: utf8("B")])
        rig.pasteboard.copy([PBType.utf8Text: utf8("C")])
        await rig.monitor.pollOnce(now: t(1))
        let order = await texts(rig.store)
        XCTAssertEqual(order, ["C"])
        XCTAssertEqual(rig.pasteboard.snapshotCallCount, 1)
    }

    func testCopyingTheSameTextAgainBumpsInsteadOfDuplicating() async {
        let rig = makeRig()
        await rig.monitor.start()
        for (i, s) in ["X", "Y", "X", "X"].enumerated() {
            rig.pasteboard.copy([PBType.utf8Text: utf8(s)])
            await rig.monitor.pollOnce(now: t(Double(i)))
        }
        let order = await texts(rig.store)
        XCTAssertEqual(order, ["X", "Y"])
    }

    func testChangeCountBumpWithIdenticalContentStillDedups() async {
        let rig = makeRig()
        await rig.monitor.start()
        rig.pasteboard.copy([PBType.utf8Text: utf8("same")])
        await rig.monitor.pollOnce(now: t(1))
        rig.pasteboard.touch()
        await rig.monitor.pollOnce(now: t(2))
        let items = await rig.store.items
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.lastUsedAt, t(2))
    }

    func testPolicyLimitsAreApplied() async {
        let rig = makeRig(policy: ClipboardPolicy(maxTextBytes: 5))
        await rig.monitor.start()
        rig.pasteboard.copy([PBType.utf8Text: utf8("123456")])
        await rig.monitor.pollOnce(now: t(1))
        rig.pasteboard.copy([PBType.utf8Text: utf8("12345")])
        await rig.monitor.pollOnce(now: t(2))
        let order = await texts(rig.store)
        XCTAssertEqual(order, ["12345"])
    }

    // MARK: 隱私與暫停

    func testConcealedCopyIsNotRecordedAndItsContentIsNeverRead() async {
        let rig = makeRig()
        await rig.monitor.start()
        rig.pasteboard.copy([PBType.utf8Text: utf8("p@ssw0rd"), PBType.concealed: Data()])
        await rig.monitor.pollOnce(now: t(1))
        let items = await rig.store.items
        XCTAssertTrue(items.isEmpty)
        XCTAssertEqual(rig.pasteboard.dataReadTypes, [], "只看型別清單，連一個 byte 的內容都不讀")
    }

    func testPausedStoreMakesMonitorSkipReadingAndAnythingCopiedWhilePausedIsNeverRecorded() async {
        let rig = makeRig()
        await rig.monitor.start()
        await rig.store.pause()
        rig.pasteboard.copy([PBType.utf8Text: utf8("copied while paused")])
        await rig.monitor.pollOnce(now: t(1))
        XCTAssertEqual(rig.pasteboard.snapshotCallCount, 0, "暫停中不碰剪貼簿內容")

        await rig.store.resume()
        await rig.monitor.pollOnce(now: t(2))
        var items = await rig.store.items
        XCTAssertTrue(items.isEmpty, "暫停期間複製的內容，恢復後也不會被補記")

        rig.pasteboard.copy([PBType.utf8Text: utf8("after resume")])
        await rig.monitor.pollOnce(now: t(3))
        items = await rig.store.items
        XCTAssertEqual(items.compactMap(\.text), ["after resume"])
    }

    func testSyncBaselineBeforeResumeStopsCopyMadeWhilePausedFromBeingBackfilled() async {
        let rig = makeRig()
        await rig.monitor.start()
        await rig.store.pause()
        rig.pasteboard.copy([PBType.utf8Text: utf8("copied while paused")])   // 還沒輪詢到
        await rig.monitor.syncBaseline()
        await rig.store.resume()
        await rig.monitor.pollOnce(now: t(1))
        let items = await rig.store.items
        XCTAssertTrue(items.isEmpty, "恢復前先對齊基準：暫停期間複製的內容不得在恢復後被補記")
        XCTAssertEqual(rig.pasteboard.snapshotCallCount, 0)
    }

    func testResumeWithoutSyncBaselineWouldBackfillWhichIsWhyTheSyncExists() async {
        let rig = makeRig()
        await rig.monitor.start()
        await rig.store.pause()
        rig.pasteboard.copy([PBType.utf8Text: utf8("copied while paused")])
        await rig.store.resume()
        await rig.monitor.pollOnce(now: t(1))
        let order = await texts(rig.store)
        XCTAssertEqual(order, ["copied while paused"], "對照組：沒有 syncBaseline 就會補記（這是 F2 的原始缺陷）")
    }

    func testSyncBaselineNeverReadsContentAndLaterCopiesAreStillRecorded() async {
        let rig = makeRig()
        await rig.monitor.start()
        rig.pasteboard.copy([PBType.utf8Text: utf8("before")])
        await rig.monitor.syncBaseline()
        XCTAssertEqual(rig.pasteboard.snapshotCallCount, 0)
        XCTAssertTrue(rig.pasteboard.dataReadTypes.isEmpty)
        await rig.monitor.pollOnce(now: t(1))
        var items = await rig.store.items
        XCTAssertTrue(items.isEmpty)
        rig.pasteboard.copy([PBType.utf8Text: utf8("after")])
        await rig.monitor.pollOnce(now: t(2))
        items = await rig.store.items
        XCTAssertEqual(items.compactMap(\.text), ["after"])
    }

    func testUnsupportedContentIsSkippedWithoutError() async {
        let rig = makeRig()
        await rig.monitor.start()
        rig.pasteboard.copy(["public.rtf": utf8("{\\rtf1 hi}")])
        await rig.monitor.pollOnce(now: t(1))
        let items = await rig.store.items
        XCTAssertTrue(items.isEmpty)
    }

    // MARK: 讀取途中剪貼簿又變了

    func testChangeDuringReadDiscardsThatReadAndRereadsOnNextTick() async {
        let rig = makeRig()
        await rig.monitor.start()
        rig.pasteboard.copy([PBType.utf8Text: utf8("first")])
        // 第一次讀資料的瞬間，另一個 App 又複製了新內容
        let pasteboard = rig.pasteboard
        pasteboard.onDataRead = { [unowned pasteboard] in
            pasteboard.onDataRead = nil
            pasteboard.copy([PBType.utf8Text: utf8("second")])
        }
        await rig.monitor.pollOnce(now: t(1))
        var order = await texts(rig.store)
        XCTAssertEqual(order, [], "讀取期間 changeCount 變了，這次結果不可信，必須丟棄")

        await rig.monitor.pollOnce(now: t(2))
        order = await texts(rig.store)
        XCTAssertEqual(order, ["second"], "下一次輪詢重新讀到最新內容")
    }

    // MARK: 寫回（writeBack）

    func testWriteBackTextWritesContentAndSelfMarkerAndReturnsNewChangeCount() async throws {
        let rig = makeRig()
        _ = await rig.store.add(ClipboardCapture(text: "history item"), now: t(1))
        let item = try await firstItem(rig.store)
        let before = rig.pasteboard.changeCount

        let new = try await rig.monitor.writeBack(item: item, to: rig.pasteboard, now: t(2))

        XCTAssertEqual(new, rig.pasteboard.changeCount)
        XCTAssertGreaterThan(new, before)
        let written = try XCTUnwrap(rig.pasteboard.currentItems.first)
        XCTAssertEqual(written[PBType.utf8Text], utf8("history item"))
        XCTAssertEqual(written[PBType.selfMarker], utf8(item.id.uuidString))
    }

    func testWriteBackIsNotRecordedAgainAndDoesNotEvenReadThePasteboard() async throws {
        let rig = makeRig()
        await rig.monitor.start()
        _ = await rig.store.add(ClipboardCapture(text: "history item"), now: t(1))
        let item = try await firstItem(rig.store)

        _ = try await rig.monitor.writeBack(item: item, to: rig.pasteboard, now: t(2))
        await rig.monitor.pollOnce(now: t(3))

        XCTAssertEqual(rig.pasteboard.snapshotCallCount, 0, "回傳的 changeCount 已被記住，輪詢不會再讀自己寫的內容")
        let items = await rig.store.items
        XCTAssertEqual(items.count, 1)
    }

    func testWriteBackBumpsTheItemToTheFrontOfTheHistory() async throws {
        let rig = makeRig()
        _ = await rig.store.add(ClipboardCapture(text: "old"), now: t(1))
        _ = await rig.store.add(ClipboardCapture(text: "newer"), now: t(2))
        let old = try await lastItem(rig.store)
        _ = try await rig.monitor.writeBack(item: old, to: rig.pasteboard, now: t(9))
        let items = await rig.store.items
        XCTAssertEqual(items.compactMap(\.text), ["old", "newer"])
        XCTAssertEqual(items.first?.lastUsedAt, t(9))
    }

    func testExternalCopyRightAfterWriteBackIsStillRecorded() async throws {
        let rig = makeRig()
        await rig.monitor.start()
        _ = await rig.store.add(ClipboardCapture(text: "mine"), now: t(1))
        let item = try await firstItem(rig.store)
        _ = try await rig.monitor.writeBack(item: item, to: rig.pasteboard, now: t(2))
        rig.pasteboard.copy([PBType.utf8Text: utf8("someone else")])
        await rig.monitor.pollOnce(now: t(3))
        let order = await texts(rig.store)
        XCTAssertEqual(order, ["someone else", "mine"])
    }

    func testOwnMarkerFoundOnPasteboardBumpsExistingItemWithoutCreatingANewOne() async throws {
        let rig = makeRig()
        await rig.monitor.start()
        _ = await rig.store.add(ClipboardCapture(text: "first"), now: t(1))
        _ = await rig.store.add(ClipboardCapture(text: "second"), now: t(2))
        let first = try await lastItem(rig.store)

        // 例如另一個執行個體／競態：剪貼簿上帶著我們的標記與條目 id
        rig.pasteboard.copy([PBType.utf8Text: utf8("first"), PBType.selfMarker: utf8(first.id.uuidString)])
        await rig.monitor.pollOnce(now: t(5))

        let items = await rig.store.items
        XCTAssertEqual(items.compactMap(\.text), ["first", "second"])
        XCTAssertEqual(items.first?.lastUsedAt, t(5))
    }

    func testOwnMarkerWithUnknownItemIDChangesNothing() async {
        let rig = makeRig()
        await rig.monitor.start()
        _ = await rig.store.add(ClipboardCapture(text: "only"), now: t(1))
        rig.pasteboard.copy([PBType.utf8Text: utf8("ghost"), PBType.selfMarker: utf8(UUID().uuidString)])
        await rig.monitor.pollOnce(now: t(2))
        let items = await rig.store.items
        XCTAssertEqual(items.compactMap(\.text), ["only"])
        XCTAssertEqual(items.first?.lastUsedAt, t(1))
    }

    func testWriteBackImageUsesDataFromTheStore() async throws {
        let rig = makeRig()
        _ = await rig.store.add(ClipboardCapture(imageData: tinyPNG, fileExtension: "png"), now: t(1))
        let item = try await firstItem(rig.store)
        _ = try await rig.monitor.writeBack(item: item, to: rig.pasteboard, now: t(2))
        let written = try XCTUnwrap(rig.pasteboard.currentItems.first)
        XCTAssertEqual(written[PBType.png], tinyPNG)
        XCTAssertNotNil(written[PBType.selfMarker])
    }

    func testWriteBackImageWhoseFileIsGoneThrowsAndLeavesPasteboardUntouched() async throws {
        let rig = makeRig()
        _ = await rig.store.add(ClipboardCapture(imageData: tinyPNG), now: t(1))
        let item = try await firstItem(rig.store)
        try rig.persistence.deleteImage(fileName: try XCTUnwrap(item.imageFileName))
        let before = rig.pasteboard.changeCount

        do {
            _ = try await rig.monitor.writeBack(item: item, to: rig.pasteboard, now: t(2))
            XCTFail("應該拋出錯誤")
        } catch let error as ClipboardMonitorError {
            XCTAssertEqual(error, .imageDataUnavailable)
        }
        XCTAssertEqual(rig.pasteboard.changeCount, before)
        XCTAssertTrue(rig.pasteboard.writtenItems.isEmpty)
    }

    func testWriteBackFilesWritesOnePasteboardItemPerPath() async throws {
        let rig = makeRig()
        _ = await rig.store.add(ClipboardCapture(filePaths: ["/Users/a/1.txt", "/Users/a/2.txt"]), now: t(1))
        let item = try await firstItem(rig.store)
        _ = try await rig.monitor.writeBack(item: item, to: rig.pasteboard, now: t(2))
        let written = rig.pasteboard.currentItems
        XCTAssertEqual(written.count, 2)
        XCTAssertEqual(written[0][PBType.fileURL], fileURLData("/Users/a/1.txt"))
        XCTAssertEqual(written[1][PBType.fileURL], fileURLData("/Users/a/2.txt"))
    }

    // MARK: 排程

    func testStartSchedulesOnceAtDefaultIntervalAndStopCancels() async {
        let rig = makeRig()
        let initiallyRunning = await rig.monitor.isRunning
        XCTAssertFalse(initiallyRunning)
        await rig.monitor.start()
        await rig.monitor.start()
        XCTAssertEqual(rig.scheduler.scheduledIntervals, [0.5], "預設間隔 0.5 秒，重複 start 不會重複排程")
        XCTAssertEqual(rig.scheduler.activeCount, 1)
        let running = await rig.monitor.isRunning
        XCTAssertTrue(running)

        await rig.monitor.stop()
        XCTAssertEqual(rig.scheduler.activeCount, 0)
        XCTAssertEqual(rig.scheduler.cancelCount, 1)
        let stopped = await rig.monitor.isRunning
        XCTAssertFalse(stopped)
        await rig.monitor.stop()   // 重複 stop 無害
    }

    func testCustomIntervalIsPassedToScheduler() async {
        let rig = makeRig(interval: 2.5)
        await rig.monitor.start()
        XCTAssertEqual(rig.scheduler.scheduledIntervals, [2.5])
    }

    func testSchedulerTicksDrivePollingAndStopSilencesThem() async {
        let rig = makeRig()
        await rig.monitor.start()
        rig.pasteboard.copy([PBType.utf8Text: utf8("tick me")])
        await rig.scheduler.fire()
        var order = await texts(rig.store)
        XCTAssertEqual(order, ["tick me"])

        await rig.monitor.stop()
        rig.pasteboard.copy([PBType.utf8Text: utf8("after stop")])
        await rig.scheduler.fire()
        order = await texts(rig.store)
        XCTAssertEqual(order, ["tick me"], "stop 之後不再輪詢")
    }

    func testRestartRebaselinesSoContentCopiedWhileStoppedIsNotRead() async {
        let rig = makeRig()
        await rig.monitor.start()
        await rig.monitor.stop()
        rig.pasteboard.copy([PBType.utf8Text: utf8("copied while stopped")])
        await rig.monitor.start()
        await rig.scheduler.fire()
        XCTAssertEqual(rig.pasteboard.snapshotCallCount, 0)
    }

    func testMonitorDoesNotLeakThroughSchedulerAndDeinitCancelsTheSchedule() async {
        let scheduler = ManualClipboardScheduler()
        weak var weakMonitor: ClipboardMonitor?
        do {
            let monitor = ClipboardMonitor(
                reader: FakePasteboard(),
                store: ClipboardStore(persistence: InMemoryClipboardPersistence()),
                scheduler: scheduler
            )
            weakMonitor = monitor
            await monitor.start()
            XCTAssertEqual(scheduler.activeCount, 1)
        }
        // actor 的釋放可能晚一拍；讓出執行權幾次
        for _ in 0..<20 where weakMonitor != nil { await Task.yield() }
        XCTAssertNil(weakMonitor, "排程器的 handler 不得強引用 monitor")
        await scheduler.fire()   // 不得崩潰
        XCTAssertEqual(scheduler.activeCount, 0, "monitor 釋放時要取消排程")
    }
}

/// TaskClipboardScheduler：真實計時器（間隔很短，逾時寬鬆）。
final class TaskClipboardSchedulerTests: XCTestCase {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        var value: Int { lock.withLock { n } }
        func increment() { lock.withLock { n += 1 } }
    }

    func testFiresRepeatedlyAndStopsAfterCancel() async throws {
        let counter = Counter()
        let expectation = expectation(description: "at least 3 ticks")
        expectation.expectedFulfillmentCount = 3
        expectation.assertForOverFulfill = false
        let token = TaskClipboardScheduler().scheduleRepeating(interval: 0.01) {
            counter.increment()
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 5)
        token.cancel()
        try await Task.sleep(nanoseconds: 100_000_000)
        let settled = counter.value
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(counter.value, settled, "cancel 之後不得再觸發")
        XCTAssertGreaterThanOrEqual(settled, 3)
    }

    func testCancelBeforeFirstTickPreventsAnyCall() async throws {
        let counter = Counter()
        let token = TaskClipboardScheduler().scheduleRepeating(interval: 0.2) { counter.increment() }
        token.cancel()
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(counter.value, 0)
    }

    func testCancelIsIdempotent() {
        let token = TaskClipboardScheduler().scheduleRepeating(interval: 10) {}
        token.cancel()
        token.cancel()
    }
}
