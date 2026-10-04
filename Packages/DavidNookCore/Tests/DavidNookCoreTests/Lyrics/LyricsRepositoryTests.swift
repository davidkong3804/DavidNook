import XCTest
@testable import DavidNookCore

/// 記錄呼叫並依腳本回應的假 fetcher（不經 HTTP）。
private final class FakeFetcher: LyricsFetching, @unchecked Sendable {
    typealias Outcome = Result<PickedLyrics?, Error>
    private let state = Locked<(calls: [LyricsQuery], outcomes: [Outcome])>(([], []))
    private let fallback: Outcome

    init(_ outcomes: [Outcome], then fallback: Outcome = .success(nil)) {
        self.fallback = fallback
        state.withLock { $0.outcomes = outcomes }
    }

    var calls: [LyricsQuery] { state.snapshot.calls }

    func lyrics(for query: LyricsQuery) async throws -> PickedLyrics? {
        let outcome: Outcome = state.withLock { s in
            s.calls.append(query)
            return s.outcomes.isEmpty ? fallback : s.outcomes.removeFirst()
        }
        return try outcome.get()
    }
}

final class LyricsRepositoryTests: XCTestCase {

    private let query = LyricsQuery(title: "原樣", artist: "阿虛", album: nil, duration: 223.4)

    private func lyrics(_ id: Int) -> PickedLyrics {
        PickedLyrics(candidateID: id, trackName: "原樣", artistName: "阿虛", script: .traditional,
                     lines: [L(10_000, "第一句"), L(20_000, "第二句")], offsetMs: 0, metadata: [:])
    }

    private func makeRepo(_ fetcher: FakeFetcher, store: MemoryLyricsCacheStore = MemoryLyricsCacheStore(),
                          ttl: TimeInterval = 1_800, clock: ManualClock = ManualClock()) -> LyricsRepository {
        LyricsRepository(fetcher: fetcher, store: store, negativeTTL: ttl, now: clock.provider)
    }

    // MARK: - 命中與未命中

    func testMissFetchesThenSecondCallIsServedFromCache() async throws {
        let fetcher = FakeFetcher([.success(lyrics(1))])
        let repo = makeRepo(fetcher)
        let first = try await repo.lyrics(for: query)
        let second = try await repo.lyrics(for: query)
        XCTAssertEqual(first, lyrics(1))
        XCTAssertEqual(second, lyrics(1))
        XCTAssertEqual(fetcher.calls.count, 1)
    }

    func testCacheKeyIgnoresCaseWhitespaceAndRoundsDurationToWholeSeconds() async throws {
        let fetcher = FakeFetcher([.success(lyrics(1))])
        let repo = makeRepo(fetcher)
        _ = try await repo.lyrics(for: LyricsQuery(title: "Song", artist: "Artist", album: nil, duration: 223.4))
        let again = try await repo.lyrics(for: LyricsQuery(title: "  song ", artist: "ARTIST", album: "不同專輯", duration: 222.6))
        XCTAssertEqual(again, lyrics(1))
        XCTAssertEqual(fetcher.calls.count, 1)
    }

    func testDifferentDurationIsADifferentCacheEntry() async throws {
        let fetcher = FakeFetcher([.success(lyrics(1)), .success(lyrics(2))])
        let repo = makeRepo(fetcher)
        let a = try await repo.lyrics(for: LyricsQuery(title: "x", artist: "y", album: nil, duration: 200))
        let b = try await repo.lyrics(for: LyricsQuery(title: "x", artist: "y", album: nil, duration: 230))
        XCTAssertEqual(a?.candidateID, 1)
        XCTAssertEqual(b?.candidateID, 2)
        XCTAssertEqual(fetcher.calls.count, 2)
    }

    func testPositiveEntriesNeverExpire() async throws {
        let clock = ManualClock()
        let fetcher = FakeFetcher([.success(lyrics(1))])
        let repo = makeRepo(fetcher, clock: clock)
        _ = try await repo.lyrics(for: query)
        clock.advance(60 * 60 * 24 * 365 * 10)
        let cached = try await repo.lyrics(for: query)
        XCTAssertEqual(cached?.candidateID, 1)
        XCTAssertEqual(fetcher.calls.count, 1)
    }

    // MARK: - 負快取

    func testNotFoundIsNegativelyCachedWithinTTL() async throws {
        let clock = ManualClock()
        let fetcher = FakeFetcher([.success(nil)])
        let repo = makeRepo(fetcher, ttl: 1_800, clock: clock)
        let first = try await repo.lyrics(for: query)
        clock.advance(60)
        let second = try await repo.lyrics(for: query)
        XCTAssertNil(first)
        XCTAssertNil(second)
        XCTAssertEqual(fetcher.calls.count, 1, "TTL 內不得再打 API")
    }

    func testNegativeCacheExpiresAfterTTLAndRefetches() async throws {
        let clock = ManualClock()
        let fetcher = FakeFetcher([.success(nil), .success(lyrics(5))])
        let repo = makeRepo(fetcher, ttl: 1_800, clock: clock)
        let nilResult = try await repo.lyrics(for: query)
        XCTAssertNil(nilResult)
        clock.advance(1_800)                                    // 剛好滿 TTL 視為過期
        let refetched = try await repo.lyrics(for: query)
        XCTAssertEqual(refetched?.candidateID, 5)
        XCTAssertEqual(fetcher.calls.count, 2)
        clock.advance(3_600)
        let idResult = try await repo.lyrics(for: query)?.candidateID
        XCTAssertEqual(idResult, 5, "之後找到的結果會被正常快取")
        XCTAssertEqual(fetcher.calls.count, 2)
    }

    func testNegativeTTLIsInjectable() async throws {
        let clock = ManualClock()
        let fetcher = FakeFetcher([.success(nil), .success(nil)])
        let repo = makeRepo(fetcher, ttl: 10, clock: clock)
        _ = try await repo.lyrics(for: query)
        clock.advance(9)
        _ = try await repo.lyrics(for: query)
        XCTAssertEqual(fetcher.calls.count, 1)
        clock.advance(2)
        _ = try await repo.lyrics(for: query)
        XCTAssertEqual(fetcher.calls.count, 2)
    }

    func testZeroTTLDisablesNegativeCaching() async throws {
        let fetcher = FakeFetcher([.success(nil), .success(nil)])
        let repo = makeRepo(fetcher, ttl: 0)
        _ = try await repo.lyrics(for: query)
        _ = try await repo.lyrics(for: query)
        XCTAssertEqual(fetcher.calls.count, 2)
    }

    // MARK: - 錯誤不得被快取

    func testNetworkErrorIsRethrownAndNotCached() async throws {
        let fetcher = FakeFetcher([.failure(LrclibError.network("offline")), .success(lyrics(1))])
        let repo = makeRepo(fetcher)
        do {
            _ = try await repo.lyrics(for: query)
            XCTFail("應拋出")
        } catch LrclibError.network {
            // ok
        }
        let retry = try await repo.lyrics(for: query)
        XCTAssertEqual(retry?.candidateID, 1)
        XCTAssertEqual(fetcher.calls.count, 2)
    }

    func testRateLimitAndOverloadErrorsAreNotNegativelyCached() async throws {
        let fetcher = FakeFetcher([.failure(LrclibError.rateLimited(retryAfter: 5)),
                                   .failure(LrclibError.serverOverloaded),
                                   .success(lyrics(1))])
        let repo = makeRepo(fetcher)
        for _ in 0..<2 {
            do { _ = try await repo.lyrics(for: query); XCTFail("應拋出") } catch is LrclibError {}
        }
        let idResult = try await repo.lyrics(for: query)?.candidateID
        XCTAssertEqual(idResult, 1)
        XCTAssertEqual(fetcher.calls.count, 3)
    }

    func testCancellationIsNotCached() async throws {
        let fetcher = FakeFetcher([.failure(CancellationError()), .success(lyrics(1))])
        let repo = makeRepo(fetcher)
        do { _ = try await repo.lyrics(for: query); XCTFail("應拋出") } catch is CancellationError {}
        let idResult = try await repo.lyrics(for: query)?.candidateID
        XCTAssertEqual(idResult, 1)
    }

    // MARK: - 強制更新與無效查詢

    func testForceRefreshBypassesAndReplacesCache() async throws {
        let fetcher = FakeFetcher([.success(lyrics(1)), .success(lyrics(2))])
        let repo = makeRepo(fetcher)
        _ = try await repo.lyrics(for: query)
        let refreshed = try await repo.lyrics(for: query, forceRefresh: true)
        XCTAssertEqual(refreshed?.candidateID, 2)
        let idResult = try await repo.lyrics(for: query)?.candidateID
        XCTAssertEqual(idResult, 2)
        XCTAssertEqual(fetcher.calls.count, 2)
    }

    func testForceRefreshIgnoresNegativeEntry() async throws {
        let fetcher = FakeFetcher([.success(nil), .success(lyrics(3))])
        let repo = makeRepo(fetcher)
        let nilResult = try await repo.lyrics(for: query)
        XCTAssertNil(nilResult)
        let idResult = try await repo.lyrics(for: query, forceRefresh: true)?.candidateID
        XCTAssertEqual(idResult, 3)
    }

    func testBlankTitleReturnsNilWithoutFetchingOrCaching() async throws {
        let store = MemoryLyricsCacheStore()
        let fetcher = FakeFetcher([.success(lyrics(1))])
        let repo = makeRepo(fetcher, store: store)
        let q = LyricsQuery(title: "  ", artist: "阿虛", album: nil, duration: 200)
        let nilResult = try await repo.lyrics(for: q)
        XCTAssertNil(nilResult)
        XCTAssertTrue(fetcher.calls.isEmpty)
        XCTAssertNil(store.entry(for: q.trackKey))
    }

    func testTheOriginalQueryIsPassedToTheFetcherUntouched() async throws {
        let fetcher = FakeFetcher([.success(nil)])
        _ = try await makeRepo(fetcher).lyrics(for: query)
        XCTAssertEqual(fetcher.calls, [query])
    }
}

final class MemoryLyricsCacheStoreTests: XCTestCase {

    private let key = TrackKey(title: "a", artist: "b", duration: 200)

    func testEmptyStoreReturnsNil() {
        XCTAssertNil(MemoryLyricsCacheStore().entry(for: key))
    }

    func testStoreAndReadBack() {
        let store = MemoryLyricsCacheStore()
        let entry = LyricsCacheEntry(lyrics: nil, storedAt: Date(timeIntervalSinceReferenceDate: 1))
        store.store(entry, for: key)
        XCTAssertEqual(store.entry(for: key), entry)
    }

    func testOverwriteReplacesEntry() {
        let store = MemoryLyricsCacheStore()
        store.store(LyricsCacheEntry(lyrics: nil, storedAt: Date(timeIntervalSinceReferenceDate: 1)), for: key)
        let newer = LyricsCacheEntry(lyrics: nil, storedAt: Date(timeIntervalSinceReferenceDate: 2))
        store.store(newer, for: key)
        XCTAssertEqual(store.entry(for: key), newer)
    }

    func testKeysAreIndependent() {
        let store = MemoryLyricsCacheStore()
        let other = TrackKey(title: "a", artist: "b", duration: 201)
        store.store(LyricsCacheEntry(lyrics: nil, storedAt: Date(timeIntervalSinceReferenceDate: 1)), for: key)
        XCTAssertNil(store.entry(for: other))
    }

    func testCacheEntryIsCodableForFuturePersistentStores() throws {
        let picked = PickedLyrics(candidateID: 9, trackName: "t", artistName: "a", script: .simplified,
                                  lines: [L(1_000, "x")], offsetMs: -20, metadata: ["ti": "t"])
        for entry in [LyricsCacheEntry(lyrics: picked, storedAt: Date(timeIntervalSinceReferenceDate: 5)),
                      LyricsCacheEntry(lyrics: nil, storedAt: Date(timeIntervalSinceReferenceDate: 6))] {
            let data = try JSONEncoder().encode(entry)
            XCTAssertEqual(try JSONDecoder().decode(LyricsCacheEntry.self, from: data), entry)
        }
    }

    func testConcurrentAccessIsSafe() async {
        let store = MemoryLyricsCacheStore()
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<200 {
                group.addTask {
                    let k = TrackKey(title: "t\(i % 10)", artist: "a", duration: 100)
                    store.store(LyricsCacheEntry(lyrics: nil, storedAt: Date()), for: k)
                    _ = store.entry(for: k)
                }
            }
        }
        XCTAssertNotNil(store.entry(for: TrackKey(title: "t3", artist: "a", duration: 100)))
    }
}
