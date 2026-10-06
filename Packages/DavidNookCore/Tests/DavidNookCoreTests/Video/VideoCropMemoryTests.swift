import XCTest
@testable import DavidNookCore

/// 依來源 App 的 bundle id 記住裁切矩形（只存 bundle id 與矩形；不存視窗標題）。
final class VideoCropMemoryTests: XCTestCase {
    private let r1 = NormalizedCropRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
    private let r2 = NormalizedCropRect(x: 0.2, y: 0.3, width: 0.4, height: 0.4)

    func testSetAndGet() {
        var m = VideoCropMemory()
        XCTAssertNil(m.rect(for: "com.apple.Safari"))
        m.set(r1, for: "com.apple.Safari")
        XCTAssertEqual(m.rect(for: "com.apple.Safari"), r1)
        XCTAssertNil(m.rect(for: "org.mozilla.firefox"))
        m.set(r2, for: "com.apple.Safari")
        XCTAssertEqual(m.rect(for: "com.apple.Safari"), r2)
        XCTAssertEqual(m.entries.count, 1)
    }

    func testFullWindowOrNilRemovesTheEntry() {
        var m = VideoCropMemory()
        m.set(r1, for: "a")
        m.set(.full, for: "a")
        XCTAssertNil(m.rect(for: "a"))
        m.set(r1, for: "a")
        m.set(nil, for: "a")
        XCTAssertNil(m.rect(for: "a"))
        m.set(r1, for: "a")
        m.remove("a")
        XCTAssertTrue(m.entries.isEmpty)
    }

    func testNilOrEmptyBundleIDIsNeverStored() {
        var m = VideoCropMemory()
        m.set(r1, for: nil)
        m.set(r1, for: "")
        XCTAssertTrue(m.entries.isEmpty)
        XCTAssertNil(m.rect(for: nil))
    }

    func testCapDropsTheOldest() {
        var m = VideoCropMemory()
        for i in 0..<(VideoCropMemory.maximumEntries + 5) { m.set(r1, for: "app.\(i)") }
        XCTAssertEqual(m.entries.count, VideoCropMemory.maximumEntries)
        XCTAssertNil(m.rect(for: "app.0"))
        XCTAssertNotNil(m.rect(for: "app.\(VideoCropMemory.maximumEntries + 4)"))
    }

    func testCodableRoundTripSanitizesOnLoad() throws {
        var m = VideoCropMemory()
        m.set(r1, for: "a")
        m.set(r2, for: "b")
        let data = try JSONEncoder().encode(m)
        XCTAssertEqual(try JSONDecoder().decode(VideoCropMemory.self, from: data), m)
        let bad = #"{"entries":[{"bundleID":"x","x":-3,"y":0.5,"width":9,"height":0.5},{"bundleID":"","x":0,"y":0,"width":0.5,"height":0.5}]}"#
        let loaded = try JSONDecoder().decode(VideoCropMemory.self, from: Data(bad.utf8))
        XCTAssertEqual(loaded.entries.count, 1, "空 bundle id 的項目被丟掉")
        let r = try XCTUnwrap(loaded.rect(for: "x"))
        XCTAssertTrue(r.x >= 0 && r.x + r.width <= 1 + 1e-9)
    }

    func testStoredFormContainsOnlyBundleIDAndRect() throws {
        var m = VideoCropMemory()
        m.set(r1, for: "com.example.Player")
        let json = String(decoding: try JSONEncoder().encode(m), as: UTF8.self)
        XCTAssertFalse(json.lowercased().contains("title"))
        XCTAssertTrue(json.contains("com.example.Player"))
    }
}
