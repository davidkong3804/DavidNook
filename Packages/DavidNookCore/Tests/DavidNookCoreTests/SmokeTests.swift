import XCTest
@testable import DavidNookCore

final class SmokeTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(DavidNookCore.version, "0.1.0")
    }
}
