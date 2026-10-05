import XCTest
@testable import DavidNookCore

final class TrackKeyTests: XCTestCase {

    func testCaseAndSurroundingWhitespaceAreIgnored() {
        XCTAssertEqual(TrackKey(title: "Song", artist: "Artist", duration: 200),
                       TrackKey(title: "  song\n", artist: " ARTIST ", duration: 200))
    }

    func testDurationIsRoundedToWholeSeconds() {
        XCTAssertEqual(TrackKey(title: "a", artist: "b", duration: 223.4).durationSeconds, 223)
        XCTAssertEqual(TrackKey(title: "a", artist: "b", duration: 222.6).durationSeconds, 223)
        XCTAssertEqual(TrackKey(title: "a", artist: "b", duration: 223.4), TrackKey(title: "a", artist: "b", duration: 222.6))
        XCTAssertNotEqual(TrackKey(title: "a", artist: "b", duration: 223.4), TrackKey(title: "a", artist: "b", duration: 223.6))
    }

    func testInvalidDurationsCollapseToZero() {
        XCTAssertEqual(TrackKey(title: "a", artist: "b", duration: -5).durationSeconds, 0)
        XCTAssertEqual(TrackKey(title: "a", artist: "b", duration: .nan).durationSeconds, 0)
        XCTAssertEqual(TrackKey(title: "a", artist: "b", duration: .infinity).durationSeconds, 0)
        XCTAssertEqual(TrackKey(title: "a", artist: "b", duration: 0).durationSeconds, 0)
    }

    func testUnicodeCanonicalEquivalenceIsNormalised() {
        // "é" 預組字 vs "e" + 組合重音符
        XCTAssertEqual(TrackKey(title: "caf\u{E9}", artist: "x", duration: 1),
                       TrackKey(title: "cafe\u{301}", artist: "x", duration: 1))
    }

    func testDifferentArtistsAreDifferentKeys() {
        XCTAssertNotEqual(TrackKey(title: "a", artist: "b", duration: 1), TrackKey(title: "a", artist: "c", duration: 1))
    }

    func testStorageStringIsStableAndUnambiguous() {
        let k1 = TrackKey(title: "a|b", artist: "c", duration: 10)
        let k2 = TrackKey(title: "a", artist: "b|c", duration: 10)
        XCTAssertNotEqual(k1.storageString, k2.storageString)
        XCTAssertEqual(TrackKey(title: "A", artist: "B", duration: 10).storageString,
                       TrackKey(title: "a", artist: "b", duration: 10).storageString)
    }

    func testCodableRoundTrip() throws {
        let key = TrackKey(title: "夜行燈", artist: "阿虛", duration: 223.4)
        let back = try JSONDecoder().decode(TrackKey.self, from: JSONEncoder().encode(key))
        XCTAssertEqual(back, key)
    }

    func testLyricsQueryProducesMatchingTrackKey() {
        let q = LyricsQuery(title: "夜行燈", artist: "阿虛", album: "任何", duration: 223.4)
        XCTAssertEqual(q.trackKey, TrackKey(title: "夜行燈", artist: "阿虛", duration: 223))
    }
}

final class MemoryTrackOffsetStoreTests: XCTestCase {

    private let key = TrackKey(title: "夜行燈", artist: "阿虛", duration: 223)

    func testUnknownTrackHasZeroOffset() {
        XCTAssertEqual(MemoryTrackOffsetStore().offsetMs(for: key), 0)
    }

    func testSetAndGetPositiveAndNegativeOffsets() {
        let store = MemoryTrackOffsetStore()
        store.setOffsetMs(350, for: key)
        XCTAssertEqual(store.offsetMs(for: key), 350)
        store.setOffsetMs(-1_200, for: key)
        XCTAssertEqual(store.offsetMs(for: key), -1_200)
    }

    func testOffsetsAreRememberedPerTrack() {
        let store = MemoryTrackOffsetStore()
        let other = TrackKey(title: "夜行燈", artist: "阿虛", duration: 260)   // 同名不同長度版本
        store.setOffsetMs(300, for: key)
        store.setOffsetMs(-100, for: other)
        XCTAssertEqual(store.offsetMs(for: key), 300)
        XCTAssertEqual(store.offsetMs(for: other), -100)
    }

    func testSameTrackWithSlightDurationJitterSharesTheOffset() {
        let store = MemoryTrackOffsetStore()
        store.setOffsetMs(300, for: TrackKey(title: "a", artist: "b", duration: 223.4))
        XCTAssertEqual(store.offsetMs(for: TrackKey(title: "A", artist: "b ", duration: 222.6)), 300)
    }

    func testSettingZeroRemovesTheEntry() {
        let store = MemoryTrackOffsetStore()
        store.setOffsetMs(300, for: key)
        store.setOffsetMs(0, for: key)
        XCTAssertEqual(store.offsetMs(for: key), 0)
        XCTAssertEqual(store.allOffsets().count, 0, "0 等於沒有偏移，不佔空間")
    }

    func testRemoveOffset() {
        let store = MemoryTrackOffsetStore()
        store.setOffsetMs(300, for: key)
        store.removeOffset(for: key)
        XCTAssertEqual(store.offsetMs(for: key), 0)
        store.removeOffset(for: key)                      // 重複移除不應出錯
    }

    func testExtremeValuesRoundTrip() {
        let store = MemoryTrackOffsetStore()
        store.setOffsetMs(Int.max, for: key)
        XCTAssertEqual(store.offsetMs(for: key), Int.max)
        store.setOffsetMs(Int.min, for: key)
        XCTAssertEqual(store.offsetMs(for: key), Int.min)
    }

    func testConcurrentWritesAreSafe() async {
        let store = MemoryTrackOffsetStore()
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<200 {
                group.addTask {
                    let k = TrackKey(title: "t\(i % 7)", artist: "a", duration: 100)
                    store.setOffsetMs(i + 1, for: k)
                    _ = store.offsetMs(for: k)
                }
            }
        }
        XCTAssertEqual(store.allOffsets().count, 7)
    }
}

final class UserDefaultsTrackOffsetStoreTests: XCTestCase {

    private let key = TrackKey(title: "夜行燈", artist: "阿虛", duration: 223)

    /// 每個測試用獨立的 suite，結束後清掉，不污染使用者的偏好設定。
    private func makeSuiteName() -> String {
        let name = "DavidNookTests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return name
    }

    func testUnknownTrackHasZeroOffset() throws {
        let store = try XCTUnwrap(UserDefaultsTrackOffsetStore(suiteName: makeSuiteName()))
        XCTAssertEqual(store.offsetMs(for: key), 0)
    }

    func testSetAndGet() throws {
        let store = try XCTUnwrap(UserDefaultsTrackOffsetStore(suiteName: makeSuiteName()))
        store.setOffsetMs(-450, for: key)
        XCTAssertEqual(store.offsetMs(for: key), -450)
    }

    func testPersistsAcrossInstancesWithTheSameSuite() throws {
        let suite = makeSuiteName()
        let a = try XCTUnwrap(UserDefaultsTrackOffsetStore(suiteName: suite))
        a.setOffsetMs(800, for: key)
        let b = try XCTUnwrap(UserDefaultsTrackOffsetStore(suiteName: suite))
        XCTAssertEqual(b.offsetMs(for: key), 800)
    }

    func testDifferentSuitesAreIsolated() throws {
        let a = try XCTUnwrap(UserDefaultsTrackOffsetStore(suiteName: makeSuiteName()))
        let b = try XCTUnwrap(UserDefaultsTrackOffsetStore(suiteName: makeSuiteName()))
        a.setOffsetMs(800, for: key)
        XCTAssertEqual(b.offsetMs(for: key), 0)
    }

    func testKeyingMatchesTheMemoryStoreSemantics() throws {
        let store = try XCTUnwrap(UserDefaultsTrackOffsetStore(suiteName: makeSuiteName()))
        store.setOffsetMs(300, for: TrackKey(title: "Song", artist: "X", duration: 223.4))
        XCTAssertEqual(store.offsetMs(for: TrackKey(title: " song", artist: "x", duration: 222.6)), 300)
        XCTAssertEqual(store.offsetMs(for: TrackKey(title: "song", artist: "x", duration: 230)), 0)
    }

    func testSettingZeroAndRemoveClearTheEntry() throws {
        let store = try XCTUnwrap(UserDefaultsTrackOffsetStore(suiteName: makeSuiteName()))
        store.setOffsetMs(300, for: key)
        store.setOffsetMs(0, for: key)
        XCTAssertEqual(store.offsetMs(for: key), 0)
        store.setOffsetMs(300, for: key)
        store.removeOffset(for: key)
        XCTAssertEqual(store.offsetMs(for: key), 0)
    }

    func testCorruptStoredValueIsTreatedAsZero() throws {
        let suite = makeSuiteName()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set("garbage", forKey: UserDefaultsTrackOffsetStore.storageKey)
        let store = try XCTUnwrap(UserDefaultsTrackOffsetStore(suiteName: suite))
        XCTAssertEqual(store.offsetMs(for: key), 0)
        store.setOffsetMs(120, for: key)                    // 壞資料被覆蓋後可正常寫入
        XCTAssertEqual(store.offsetMs(for: key), 120)
    }

    func testNilSuiteNameUsesStandardDefaultsWithoutCrashing() {
        // 只驗證可建立；不寫入，避免污染測試機的偏好設定。
        XCTAssertNotNil(UserDefaultsTrackOffsetStore(suiteName: nil))
    }
}
