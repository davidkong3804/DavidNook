import XCTest
@testable import DavidNookCore

final class MusicControlLayoutMigrationTests: XCTestCase {
    private let legacy = ["shuffle", "previous", "playPause", "next", "repeatMode"]

    func testNewDefaultIsThreeTransportButtonsWithoutShuffleOrRepeat() {
        XCTAssertEqual(MusicControlLayoutMigration.newDefault, ["previous", "playPause", "next"])
        XCTAssertFalse(MusicControlLayoutMigration.newDefault.contains("repeatMode"))
        XCTAssertFalse(MusicControlLayoutMigration.newDefault.contains("shuffle"))
    }

    func testUntouchedLegacyDefaultIsReplaced() {
        let result = MusicControlLayoutMigration.migrate(saved: legacy, savedVersion: 0)
        XCTAssertEqual(result, ["previous", "playPause", "next"])
    }

    func testLegacyDefaultPaddedWithEmptySlotsIsStillReplaced() {
        // 設定頁會把版面補到 5 格（空格存成 "none"）。
        let result = MusicControlLayoutMigration.migrate(saved: legacy + ["none"], savedVersion: 0)
        XCTAssertEqual(result, ["previous", "playPause", "next"])
    }

    func testCustomizedLayoutIsLeftAlone() {
        XCTAssertNil(MusicControlLayoutMigration.migrate(saved: ["previous", "playPause", "next", "volume", "none"], savedVersion: 0))
        XCTAssertNil(MusicControlLayoutMigration.migrate(saved: ["shuffle", "previous", "playPause", "next", "favorite"], savedVersion: 0))
        XCTAssertNil(MusicControlLayoutMigration.migrate(saved: ["repeatMode", "previous", "playPause", "next", "shuffle"], savedVersion: 0))
    }

    func testAlreadyMigratedVersionIsNeverTouchedAgain() {
        // 使用者之後自己把 shuffle／repeat 加回去：不能再被改掉。
        XCTAssertNil(MusicControlLayoutMigration.migrate(saved: legacy, savedVersion: MusicControlLayoutMigration.currentVersion))
        XCTAssertNil(MusicControlLayoutMigration.migrate(saved: legacy, savedVersion: MusicControlLayoutMigration.currentVersion + 1))
    }

    func testUnknownOrEmptySavedLayoutIsLeftAlone() {
        XCTAssertNil(MusicControlLayoutMigration.migrate(saved: [], savedVersion: 0))
        XCTAssertNil(MusicControlLayoutMigration.migrate(saved: ["bogus"], savedVersion: 0))
    }

    func testTrailingEmptySlotsAreDropped() {
        XCTAssertEqual(MusicControlLayoutMigration.trimmingTrailingEmptySlots(["previous", "playPause", "next", "none", "none"]), ["previous", "playPause", "next"])
        XCTAssertEqual(MusicControlLayoutMigration.trimmingTrailingEmptySlots(["previous", "none", "next", "none"]), ["previous", "none", "next"])
        XCTAssertEqual(MusicControlLayoutMigration.trimmingTrailingEmptySlots(["none", "none"]), [])
    }
}
