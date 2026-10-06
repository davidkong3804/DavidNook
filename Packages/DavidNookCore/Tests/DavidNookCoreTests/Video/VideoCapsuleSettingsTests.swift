import XCTest
@testable import DavidNookCore

final class VideoCapsuleSettingsTests: XCTestCase {
    func testKeysAndDefaults() {
        XCTAssertEqual(VideoCapsuleSettings.enabledKey, "videoCapsuleEnabled")
        XCTAssertEqual(VideoCapsuleSettings.widthKey, "videoCapsuleWidth")
        XCTAssertEqual(VideoCapsuleSettings.pinnedKey, "videoCapsulePinned")
        XCTAssertTrue(VideoCapsuleSettings.defaultEnabled)
        XCTAssertFalse(VideoCapsuleSettings.defaultPinned)
        XCTAssertEqual(VideoCapsuleSettings.defaultWidth, 320)
        XCTAssertEqual(VideoCapsuleSettings.widthRange, 160...480)
    }

    func testWidthClamp() {
        XCTAssertEqual(VideoCapsuleSettings.clampedWidth(0), 160)
        XCTAssertEqual(VideoCapsuleSettings.clampedWidth(-50), 160)
        XCTAssertEqual(VideoCapsuleSettings.clampedWidth(160), 160)
        XCTAssertEqual(VideoCapsuleSettings.clampedWidth(300), 300)
        XCTAssertEqual(VideoCapsuleSettings.clampedWidth(480), 480)
        XCTAssertEqual(VideoCapsuleSettings.clampedWidth(9999), 480)
        XCTAssertEqual(VideoCapsuleSettings.clampedWidth(.nan), 320)
        XCTAssertEqual(VideoCapsuleSettings.clampedWidth(.infinity), 480)
        XCTAssertEqual(VideoCapsuleSettings.clampedWidth(-.infinity), 160)
    }
}
