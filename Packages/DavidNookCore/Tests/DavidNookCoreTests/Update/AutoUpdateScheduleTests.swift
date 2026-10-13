import XCTest
@testable import DavidNookCore

final class AutoUpdateScheduleTests: XCTestCase {
    private let schedule = AutoUpdateSchedule()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let hour: TimeInterval = 3_600

    private func decide(
        lastSuccess: Date? = nil,
        lastAttempt: Date? = nil,
        retried: Bool = false,
        enabled: Bool = true,
        busy: Bool = false,
        available: Bool = false
    ) -> AutoUpdateSchedule.Decision {
        schedule.decision(now: now, lastSuccessfulCheck: lastSuccess, lastAttempt: lastAttempt, retriedThisLaunch: retried,
                          enabled: enabled, isBusy: busy, alreadyAvailable: available)
    }

    // MARK: 開關與前置條件

    func testDisabledNeverChecks() {
        XCTAssertEqual(decide(enabled: false), .skip)
        XCTAssertEqual(decide(lastSuccess: now - 10 * 24 * hour, enabled: false), .skip)
        XCTAssertEqual(decide(lastSuccess: now - 10 * 24 * hour, lastAttempt: now - 2 * hour, enabled: false), .skip)
    }

    func testBusySkips() {
        XCTAssertEqual(decide(busy: true), .skip)
        XCTAssertEqual(decide(lastSuccess: now - 48 * hour, busy: true), .skip)
    }

    func testAlreadyAvailableSkips() {
        XCTAssertEqual(decide(available: true), .skip)
        XCTAssertEqual(decide(lastSuccess: now - 48 * hour, available: true), .skip)
    }

    // MARK: 每日一次

    func testFirstEverCheckRunsNow() {
        XCTAssertEqual(decide(), .checkNow)
    }

    func testWithin24HoursWaitsUntilTheDayIsUp() {
        let last = now - 23 * hour
        XCTAssertEqual(decide(lastSuccess: last), .wait(until: last + 24 * hour))
    }

    func testJustChecked() {
        XCTAssertEqual(decide(lastSuccess: now), .wait(until: now + 24 * hour))
    }

    func testExactly24HoursRunsNow() {
        XCTAssertEqual(decide(lastSuccess: now - 24 * hour), .checkNow)
    }

    func testMoreThan24HoursRunsNow() {
        XCTAssertEqual(decide(lastSuccess: now - 25 * hour), .checkNow)
        XCTAssertEqual(decide(lastSuccess: now - 30 * 24 * hour), .checkNow)
    }

    // MARK: 失敗後的重試

    func testFailedAttemptWithinAnHourWaitsForRetryWindow() {
        let attempt = now - 30 * 60
        XCTAssertEqual(decide(lastSuccess: now - 48 * hour, lastAttempt: attempt), .wait(until: attempt + hour))
    }

    func testFailedAttemptWithNoSuccessEverAlsoWaits() {
        let attempt = now - 10 * 60
        XCTAssertEqual(decide(lastAttempt: attempt), .wait(until: attempt + hour))
    }

    func testFailedAttemptOlderThanAnHourRetriesOnce() {
        XCTAssertEqual(decide(lastSuccess: now - 48 * hour, lastAttempt: now - 61 * 60), .checkNow)
        XCTAssertEqual(decide(lastSuccess: now - 48 * hour, lastAttempt: now - hour), .checkNow)
    }

    func testAfterTheRetryAlsoFailedNoMoreRetriesThisLaunch() {
        XCTAssertEqual(decide(lastSuccess: now - 48 * hour, lastAttempt: now - 5 * 60, retried: true), .skip)
        XCTAssertEqual(decide(lastSuccess: now - 48 * hour, lastAttempt: now - 10 * hour, retried: true), .skip)
        XCTAssertEqual(decide(lastAttempt: now - 100 * hour, retried: true), .skip)
    }

    func testSuccessAfterTheFailedAttemptCountsAsNormal() {
        // 失敗之後使用者手動檢查成功：回到每日一次，而且不再算「待重試」。
        let attempt = now - 3 * hour
        let success = now - 2 * hour
        XCTAssertEqual(decide(lastSuccess: success, lastAttempt: attempt), .wait(until: success + 24 * hour))
        XCTAssertEqual(decide(lastSuccess: success, lastAttempt: attempt, retried: true), .wait(until: success + 24 * hour))
    }

    // MARK: 系統時鐘被調回過去

    func testClockSetBackBeforeLastSuccessRunsNow() {
        XCTAssertEqual(decide(lastSuccess: now + 5 * 24 * hour), .checkNow)
        XCTAssertEqual(decide(lastSuccess: now + 1), .checkNow)
    }

    func testClockSetBackBeforeFailedAttemptRunsNow() {
        XCTAssertEqual(decide(lastSuccess: now - 48 * hour, lastAttempt: now + 3 * hour), .checkNow)
    }

    func testClockSetBackStillRespectsDisabledBusyAndRetryCap() {
        XCTAssertEqual(decide(lastSuccess: now + 5 * 24 * hour, enabled: false), .skip)
        XCTAssertEqual(decide(lastSuccess: now + 5 * 24 * hour, busy: true), .skip)
        XCTAssertEqual(decide(lastSuccess: now + 5 * 24 * hour, available: true), .skip)
        XCTAssertEqual(decide(lastSuccess: now - 48 * hour, lastAttempt: now + 3 * hour, retried: true), .skip)
    }

    // MARK: 常數

    func testDefaultIntervals() {
        XCTAssertEqual(AutoUpdateSchedule.checkInterval, 24 * 3_600)
        XCTAssertEqual(AutoUpdateSchedule.retryInterval, 3_600)
        XCTAssertEqual(AutoUpdateSchedule.initialDelay, 30)
    }
}
