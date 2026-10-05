import XCTest
@testable import DavidNookCore

final class LrclibClientTests: XCTestCase {

    private let query = LyricsQuery(title: "原樣", artist: "阿虛", album: "專輯", duration: 223.4)

    private let goodSynced = "[00:10.00]alpha\n[00:20.00]beta"

    private func good(id: Int = 1, duration: Double = 223, synced: String? = nil) -> String {
        jsonString(recordObject(id: id, duration: duration, synced: synced ?? goodSynced))
    }

    /// 以標題建立變體產生器。
    private func variants(_ titles: [String]) -> @Sendable (LyricsQuery) -> [LyricsQuery] {
        { q in titles.map { LyricsQuery(title: $0, artist: q.artist, album: q.album, duration: q.duration) } }
    }

    private func makeClient(
        _ transport: StubTransport,
        picker: LyricsCandidatePicker = neutralPicker(),
        variants: @escaping @Sendable (LyricsQuery) -> [LyricsQuery] = { _ in [] },
        sleep: SleepRecorder = SleepRecorder(),
        clock: ManualClock = ManualClock(),
        spacing: TimeInterval = 0,
        maxRetryAfter: TimeInterval = 30,
        appVersion: String = DavidNookCore.version
    ) -> LrclibClient {
        LrclibClient(transport: transport, picker: picker, variants: variants, sleeper: sleep.sleeper,
                     now: clock.provider, appVersion: appVersion, requestSpacing: spacing, maxRetryAfter: maxRetryAfter)
    }

    private func expectError(_ expected: LrclibError, file: StaticString = #filePath, line: UInt = #line,
                             _ body: () async throws -> Void) async {
        do {
            try await body()
            XCTFail("預期拋出 \(expected)，但沒有拋錯", file: file, line: line)
        } catch let e as LrclibError {
            XCTAssertEqual(e, expected, file: file, line: line)
        } catch {
            XCTFail("拋出非預期錯誤 \(error)", file: file, line: line)
        }
    }

    // MARK: - 請求格式

    func testGetRequestShape() async throws {
        let t = StubTransport(steps: [.ok(good()), .ok("[]")])
        _ = try await makeClient(t).lyrics(for: query)
        XCTAssertEqual(t.requests.count, 2, "get 命中後仍會送一次 search（共識挑選）")
        let r = t.requests[0]
        XCTAssertEqual(r.httpMethod, "GET")
        XCTAssertEqual(r.url?.scheme, "https")
        XCTAssertEqual(r.url?.host, "lrclib.net")
        XCTAssertEqual(r.url?.path, "/api/get")
        XCTAssertEqual(queryItems(r).map(\.name), ["track_name", "artist_name", "album_name", "duration"])
        XCTAssertEqual(queryDict(r), ["track_name": "原樣", "artist_name": "阿虛", "album_name": "專輯", "duration": "223"])
    }

    func testGetRequestOmitsAlbumWhenNilOrBlank() async throws {
        for album in [nil, "", "   "] as [String?] {
            let t = StubTransport(steps: [.ok(good(duration: 200)), .ok("[]")])
            let q = LyricsQuery(title: "原樣", artist: "阿虛", album: album, duration: 200)
            _ = try await makeClient(t).lyrics(for: q)
            XCTAssertNil(queryDict(t.requests[0])["album_name"], "album=\(String(describing: album))")
        }
    }

    func testDurationIsSentAsWholeSeconds() async throws {
        for (input, expected) in [(223.4, "223"), (222.6, "223"), (200.0, "200"), (3600.0, "3600")] {
            let t = StubTransport(steps: [.ok(good(duration: input)), .ok("[]")])
            let q = LyricsQuery(title: "x", artist: "y", album: nil, duration: input)
            _ = try await makeClient(t).lyrics(for: q)
            XCTAssertEqual(queryDict(t.requests[0])["duration"], expected, "duration=\(input)")
        }
    }

    func testDurationIsOmittedWhenUnknownOrOutOfRange() async throws {
        // (查詢用的長度, 假紀錄的長度)：讓 picker 一定接受該紀錄，才能只驗證請求本身。
        let cases: [(Double, Double)] = [(0.0, 100), (-1.0, 100), (0.4, 0.4), (3600.6, 3600.6), (99_999.0, 99_999.0), (.nan, 100)]
        for (input, recordDuration) in cases {
            let t = StubTransport(steps: [.ok(good(duration: recordDuration)), .ok("[]")])
            let q = LyricsQuery(title: "x", artist: "y", album: nil, duration: input)
            _ = try await makeClient(t).lyrics(for: q)
            XCTAssertNil(queryDict(t.requests[0])["duration"], "duration=\(input)")
        }
    }

    func testQueryValuesArePercentEncoded() async throws {
        let t = StubTransport(steps: [.ok(good(duration: 200)), .ok("[]")])
        let q = LyricsQuery(title: "A+B & C=D 夜", artist: "x/y?z#w", album: nil, duration: 200)
        _ = try await makeClient(t).lyrics(for: q)
        let raw = try XCTUnwrap(rawQuery(t.requests[0]))
        XCTAssertTrue(raw.contains("track_name=A%2BB%20%26%20C%3DD%20%E5%A4%9C"), raw)
        XCTAssertTrue(raw.contains("artist_name=x%2Fy%3Fz%23w"), raw)
        XCTAssertEqual(queryDict(t.requests[0])["track_name"], "A+B & C=D 夜")
    }

    func testSearchRequestShape() async throws {
        let t = StubTransport(steps: [.notFound, .ok("[]")])
        let result = try await makeClient(t).lyrics(for: query)
        XCTAssertNil(result)
        XCTAssertEqual(t.requests.count, 2)
        let r = t.requests[1]
        XCTAssertEqual(r.url?.path, "/api/search")
        XCTAssertEqual(r.httpMethod, "GET")
        XCTAssertEqual(queryItems(r).map(\.name), ["track_name", "artist_name"])
        XCTAssertEqual(queryDict(r), ["track_name": "原樣", "artist_name": "阿虛"])
    }

    func testUserAgentIsSentOnEveryRequestIncludingSearch() async throws {
        let t = StubTransport(steps: [.notFound, .ok("[]")])
        _ = try await makeClient(t).lyrics(for: query)
        let expected = "DavidNook/\(DavidNookCore.version) (https://github.com/davidkong3804/DavidNook)"
        XCTAssertEqual(t.requests.count, 2)
        for r in t.requests {
            XCTAssertEqual(r.value(forHTTPHeaderField: "User-Agent"), expected)
        }
    }

    func testUserAgentFormatAndInjectedVersion() async throws {
        XCTAssertEqual(LrclibClient.userAgent(appVersion: "1.2.3"),
                       "DavidNook/1.2.3 (https://github.com/davidkong3804/DavidNook)")
        let t = StubTransport(steps: [.ok(good()), .ok("[]")])
        _ = try await makeClient(t, appVersion: "9.9.9").lyrics(for: query)
        XCTAssertEqual(t.requests[0].value(forHTTPHeaderField: "User-Agent"),
                       "DavidNook/9.9.9 (https://github.com/davidkong3804/DavidNook)")
    }

    // MARK: - 查詢流程

    func testGetHitReturnsPickedLyrics() async throws {
        let t = StubTransport(steps: [.ok(good(id: 11)), .ok("[]")])
        let picked = try await makeClient(t).lyrics(for: query)
        XCTAssertEqual(picked?.candidateID, 11)
        XCTAssertEqual(picked?.lines, [L(10_000, "alpha"), L(20_000, "beta")])
        XCTAssertEqual(t.requests.map { $0.url?.path }, ["/api/get", "/api/search"])
    }

    func testNotFoundMovesToTheNextVariantInOrder() async throws {
        let t = StubTransport(steps: [.notFound, .notFound, .ok(good(id: 3)), .ok("[]")])
        let picked = try await makeClient(t, variants: variants(["t1", "t2"])).lyrics(for: query)
        XCTAssertEqual(picked?.candidateID, 3)
        XCTAssertEqual(t.requests.map { queryDict($0)["track_name"] }, ["原樣", "t1", "t2", "t2"],
                       "get 依序換變體；命中的是 t2，所以 search 也用 t2 的寫法")
        XCTAssertEqual(t.requests.map { $0.url?.path }, ["/api/get", "/api/get", "/api/get", "/api/search"])
    }

    func testStopsAtTheFirstUsableGetHitAndSearchesOnlyOnce() async throws {
        let t = StubTransport(steps: [.notFound, .ok(good(id: 2)), .ok("[]")])
        let picked = try await makeClient(t, variants: variants(["t1", "t2"])).lyrics(for: query)
        XCTAssertEqual(picked?.candidateID, 2)
        XCTAssertEqual(t.requests.map { $0.url?.path }, ["/api/get", "/api/get", "/api/search"],
                       "get 命中後不得再發後續 get 變體；search 只送一次")
    }

    func testDuplicateAndBlankVariantsAreSkipped() async throws {
        // 變體：與原樣相同、t1、t1（重複）、空標題 → 只應實際查詢 原樣、t1。
        let t = StubTransport(steps: [.notFound, .notFound, .ok("[]"), .ok("[]")])
        let result = try await makeClient(t, variants: variants(["原樣", "t1", "t1", "  "])).lyrics(for: query)
        XCTAssertNil(result)
        XCTAssertEqual(t.requests.map { $0.url?.path }, ["/api/get", "/api/get", "/api/search", "/api/search"])
        XCTAssertEqual(t.requests.map { queryDict($0)["track_name"] }, ["原樣", "t1", "原樣", "t1"])
    }

    func testSearchFollowsEveryGetVariantWhenAllAre404() async throws {
        let t = StubTransport(steps: [.notFound, .notFound, .notFound,
                                      .ok(jsonString([recordObject(id: 8, duration: 223, synced: goodSynced)]))])
        let picked = try await makeClient(t, variants: variants(["t1", "t2"])).lyrics(for: query)
        XCTAssertEqual(picked?.candidateID, 8)
        XCTAssertEqual(t.requests.map { $0.url?.path }, ["/api/get", "/api/get", "/api/get", "/api/search"])
        XCTAssertEqual(queryDict(t.requests[3])["track_name"], "原樣", "search 先用原樣查詢")
    }

    func testSearchResultsAreRankedByThePicker() async throws {
        let simp = recordObject(id: 1, duration: 223, synced: "[00:10.00]SIMP a")
        let trad = recordObject(id: 2, duration: 223, synced: "[00:10.00]TRAD a")
        let t = StubTransport(steps: [.notFound, .ok(jsonString([simp, trad]))])
        let picked = try await makeClient(t, picker: LyricsCandidatePicker(scriptClassifier: markerClassifier)).lyrics(for: query)
        XCTAssertEqual(picked?.candidateID, 2)
        XCTAssertEqual(picked?.script, .traditional)
    }

    func testSearchWithNoUsableResultTriesTheNextVariantThenReturnsNil() async throws {
        let instrumental = jsonString([recordObject(id: 1, instrumental: true, synced: nil)])
        let t = StubTransport(steps: [.notFound, .notFound, .ok(instrumental), .ok("[]")])
        let result = try await makeClient(t, variants: variants(["t1"])).lyrics(for: query)
        XCTAssertNil(result)
        XCTAssertEqual(t.requests.count, 4)
    }

    func testSearchSecondVariantCanStillSucceed() async throws {
        let t = StubTransport(steps: [.notFound, .notFound, .ok("[]"),
                                      .ok(jsonString([recordObject(id: 6, duration: 223, synced: goodSynced)]))])
        let picked = try await makeClient(t, variants: variants(["t1"])).lyrics(for: query)
        XCTAssertEqual(picked?.candidateID, 6)
        XCTAssertEqual(queryDict(t.requests[3])["track_name"], "t1")
    }

    func testSearchResultsDecodeLossily() async throws {
        let body = "[{\"foo\":1}," + jsonString(recordObject(id: 4, duration: 223, synced: goodSynced)) + "]"
        let t = StubTransport(steps: [.notFound, .ok(body)])
        let picked = try await makeClient(t).lyrics(for: query)
        XCTAssertEqual(picked?.candidateID, 4, "單筆壞資料不應拖垮整個結果")
    }

    func testSearch404IsTreatedAsNoResults() async throws {
        let t = StubTransport(steps: [.notFound, .notFound])
        let result = try await makeClient(t).lyrics(for: query)
        XCTAssertNil(result)
    }

    func testGetRecordWithoutSyncedLyricsFallsThroughToNextVariant() async throws {
        let noSync = jsonString(recordObject(id: 1, synced: nil))
        let t = StubTransport(steps: [.ok(noSync), .ok(good(id: 2)), .ok("[]")])
        let picked = try await makeClient(t, variants: variants(["t1"])).lyrics(for: query)
        XCTAssertEqual(picked?.candidateID, 2)
        XCTAssertEqual(t.requests.count, 3)
    }

    func testGetRecordWithWrongDurationIsRejectedByThePicker() async throws {
        let wrong = good(duration: 260)                      // 與目標 223.4 差 >2 秒
        let t = StubTransport(steps: [.ok(wrong), .ok("[]")])
        let result = try await makeClient(t).lyrics(for: query)
        XCTAssertNil(result)
        XCTAssertEqual(t.requests.map { $0.url?.path }, ["/api/get", "/api/search"])
    }

    func testBlankTitleReturnsNilWithoutAnyRequest() async throws {
        let t = StubTransport(steps: [])
        let q = LyricsQuery(title: "   ", artist: "阿虛", album: nil, duration: 200)
        let result = try await makeClient(t).lyrics(for: q)
        XCTAssertNil(result)
        XCTAssertTrue(t.requests.isEmpty)
    }

    func testBlankArtistSkipsGetAndSearchesByTitleOnly() async throws {
        // /api/get 要求 artist_name；沒有歌手時直接走 search（artist_name 為選填）。
        let t = StubTransport(steps: [.ok("[]")])
        let q = LyricsQuery(title: "x", artist: "  ", album: nil, duration: 200)
        let result = try await makeClient(t).lyrics(for: q)
        XCTAssertNil(result)
        XCTAssertEqual(t.requests.count, 1)
        XCTAssertEqual(t.requests[0].url?.path, "/api/search")
        XCTAssertEqual(queryDict(t.requests[0]), ["track_name": "x"])
    }

    // MARK: - 共識挑選：get 的單筆併入 search 候選池，統一交給 Picker 排序

    /// 首句在 `seconds` 秒的兩行同步歌詞（用來製造「時間軸不同的版本」）。
    private func lrc(startingAt seconds: Int) -> String {
        func tag(_ s: Int) -> String { String(format: "[%02d:%02d.00]", s / 60, s % 60) }
        return "\(tag(seconds))alpha\n\(tag(seconds + 10))beta"
    }

    private func record(_ id: Int, firstAt seconds: Int, duration: Double = 223) -> [String: Any] {
        recordObject(id: id, duration: duration, synced: lrc(startingAt: seconds))
    }

    private func paths(_ t: StubTransport) -> [String?] { t.requests.map { $0.url?.path } }

    func testGetOutlierLosesToTheSearchConsensusVersion() async throws {
        // get 回的是首句 10 秒的離群版本；search 的多數版本首句都在 30 秒附近 → 要選共識版本。
        let t = StubTransport(steps: [
            .ok(jsonString(record(1, firstAt: 10))),
            .ok(jsonString([record(2, firstAt: 30), record(3, firstAt: 30), record(4, firstAt: 31)])),
        ])
        let picked = try await makeClient(t).lyrics(for: query)
        XCTAssertEqual(picked?.candidateID, 2, "離群的 get 結果不得繞過 Picker 的共識排序")
        XCTAssertEqual(paths(t), ["/api/get", "/api/search"])
    }

    func testGetResultInAgreementWithTheConsensusIsKept() async throws {
        let t = StubTransport(steps: [
            .ok(jsonString(record(5, firstAt: 30))),
            .ok(jsonString([record(6, firstAt: 30), record(7, firstAt: 30), record(8, firstAt: 10)])),
        ])
        let picked = try await makeClient(t).lyrics(for: query)
        XCTAssertEqual(picked?.candidateID, 5, "get 的結果落在共識群內（且 id 最小）時仍會被選中")
    }

    func testTheSameRecordInGetAndSearchCountsAsOneCandidate() async throws {
        // get 與 search 都回 id 9（首句 10 秒）；search 另有 id 7（30 秒）。去重後只有兩個候選，
        // 沒有共識可言，依 id 小者優先 → 7。若沒去重，id 9 會變成兩票而贏。
        let t = StubTransport(steps: [
            .ok(jsonString(record(9, firstAt: 10))),
            .ok(jsonString([record(9, firstAt: 10), record(7, firstAt: 30)])),
        ])
        let picked = try await makeClient(t).lyrics(for: query)
        XCTAssertEqual(picked?.candidateID, 7)
    }

    func testPickDoesNotDependOnSearchResultOrder() async throws {
        let records = [record(2, firstAt: 30), record(3, firstAt: 30), record(4, firstAt: 31), record(6, firstAt: 12)]
        let orders: [[Int]] = [[0, 1, 2, 3], [3, 2, 1, 0], [1, 3, 0, 2], [2, 0, 3, 1], [3, 0, 1, 2]]
        var ids = Set<Int>()
        for order in orders {
            let t = StubTransport(steps: [
                .ok(jsonString(record(1, firstAt: 10))),
                .ok(jsonString(order.map { records[$0] })),
            ])
            ids.insert(try await makeClient(t).lyrics(for: query)?.candidateID ?? -1)
        }
        XCTAssertEqual(ids, [2], "搜尋結果的順序不得影響挑選")
    }

    func testGetHitWithUsableSearchSendsExactlyTwoRequests() async throws {
        // 請求數：get 命中、search 有可用結果 → 恰好 2 個請求，不再試其他變體。
        let t = StubTransport(steps: [
            .ok(jsonString(record(1, firstAt: 10))),
            .ok(jsonString([record(2, firstAt: 10)])),
        ])
        _ = try await makeClient(t, variants: variants(["t1", "t2"])).lyrics(for: query)
        XCTAssertEqual(paths(t), ["/api/get", "/api/search"])
        XCTAssertEqual(t.requests.last.map(queryDict)?["track_name"], "原樣", "get 在原樣就命中 → search 也用原樣")
    }

    func testSearchUsesTheSpellingThatTheGetHitCameFrom() async throws {
        let t = StubTransport(steps: [
            .notFound,
            .ok(jsonString(record(1, firstAt: 10))),
            .ok(jsonString([record(2, firstAt: 10)])),
        ])
        _ = try await makeClient(t, variants: variants(["t1", "t2"])).lyrics(for: query)
        XCTAssertEqual(paths(t), ["/api/get", "/api/get", "/api/search"])
        XCTAssertEqual(t.requests.last.map(queryDict)?["track_name"], "t1")
    }

    func testGetHitThenSearchWithNothingUsableReturnsTheGetResultWithoutMoreRequests() async throws {
        let instrumental = jsonString([recordObject(id: 5, instrumental: true, synced: nil)])
        let t = StubTransport(steps: [.ok(good(id: 11)), .ok(instrumental)])
        let outcome = try await makeClient(t, variants: variants(["t1"])).fetch(query)
        XCTAssertEqual(outcome.lyrics?.candidateID, 11, "search 沒有可用候選時，get 是唯一版本")
        XCTAssertFalse(outcome.isDegraded, "search 成功（只是沒有可用結果）不算退而求其次")
        XCTAssertEqual(paths(t), ["/api/get", "/api/search"], "已經有 get 結果就不再試其他變體的 search")
    }

    func testWithoutAGetHitSearchStillWalksTheVariants() async throws {
        let instrumental = jsonString([recordObject(id: 5, instrumental: true, synced: nil)])
        let t = StubTransport(steps: [
            .notFound, .notFound,
            .ok(instrumental),
            .ok(jsonString([record(2, firstAt: 10)])),
        ])
        let picked = try await makeClient(t, variants: variants(["t1"])).lyrics(for: query)
        XCTAssertEqual(picked?.candidateID, 2)
        XCTAssertEqual(t.requests.map { queryDict($0)["track_name"] }, ["原樣", "t1", "原樣", "t1"])
    }

    func testSearchFailureFallsBackToTheGetResult() async throws {
        // search 503（重試用盡）：退而使用 get 的結果，標記為 degraded；請求仍遵守 503 重試規範（共 3 次）。
        let t = StubTransport(steps: [.ok(good(id: 11)), .status(503), .status(503), .status(503)])
        let outcome = try await makeClient(t).fetch(query)
        XCTAssertEqual(outcome.lyrics?.candidateID, 11)
        XCTAssertTrue(outcome.isDegraded)
        XCTAssertEqual(paths(t), ["/api/get", "/api/search", "/api/search", "/api/search"])
    }

    func testSearchNetworkErrorFallsBackToTheGetResult() async throws {
        let t = StubTransport(steps: [.ok(good(id: 12)), .failure(URLError(.notConnectedToInternet))])
        let outcome = try await makeClient(t).fetch(query)
        XCTAssertEqual(outcome.lyrics?.candidateID, 12)
        XCTAssertTrue(outcome.isDegraded)
    }

    func testSearchRateLimitFallsBackToTheGetResultAfterHonoringRetryAfter() async throws {
        let sleep = SleepRecorder()
        let t = StubTransport(steps: [
            .ok(good(id: 13)),
            .status(429, retryAfter: "2"), .status(429, retryAfter: "2"), .status(429, retryAfter: "2"),
        ])
        let picked = try await makeClient(t, sleep: sleep).lyrics(for: query)
        XCTAssertEqual(picked?.candidateID, 13)
        XCTAssertEqual(sleep.durations, [2, 2], "429 仍然睡滿 Retry-After 才重試")
        XCTAssertEqual(t.requests.count, 4)
    }

    func testSearchFailureWithoutAGetResultStillThrows() async {
        let t = StubTransport(steps: [.notFound, .failure(URLError(.timedOut))])
        let client = makeClient(t)
        do {
            _ = try await client.lyrics(for: query)
            XCTFail("沒有 get 結果可退時，search 的失敗必須拋出（不可當成找不到）")
        } catch LrclibError.network {
            // ok
        } catch {
            XCTFail("錯誤型別不對：\(error)")
        }
    }

    func testGetFailureButSearchSucceedsUsesTheSearchResult() async throws {
        // get 回非預期狀態碼（500）：不重試、不再換 get 變體，直接改試 search。
        let t = StubTransport(steps: [.status(500), .ok(jsonString([record(12, firstAt: 10)]))])
        let outcome = try await makeClient(t, variants: variants(["t1"])).fetch(query)
        XCTAssertEqual(outcome.lyrics?.candidateID, 12)
        XCTAssertFalse(outcome.isDegraded)
        XCTAssertEqual(paths(t), ["/api/get", "/api/search"])
    }

    func testGetRateLimitedOrOverloadedDoesNotTriggerASearch() async {
        // get 被限流／伺服器忙碌到重試用盡：不再多打 search（伺服器正要我們退讓）。
        let limited = StubTransport(steps: [.status(429, retryAfter: "1"), .status(429, retryAfter: "1"), .status(429, retryAfter: "1")])
        await expectError(.rateLimited(retryAfter: 1)) { _ = try await makeClient(limited).lyrics(for: query) }
        XCTAssertEqual(paths(limited), ["/api/get", "/api/get", "/api/get"])

        let overloaded = StubTransport(steps: [.status(503), .status(503), .status(503)])
        await expectError(.serverOverloaded) { _ = try await makeClient(overloaded).lyrics(for: query) }
        XCTAssertEqual(paths(overloaded), ["/api/get", "/api/get", "/api/get"])
    }

    func testBothNotFoundAndEmptySearchReturnsNil() async throws {
        let t = StubTransport(steps: [.notFound, .ok("[]")])
        let outcome = try await makeClient(t).fetch(query)
        XCTAssertNil(outcome.lyrics)
        XCTAssertFalse(outcome.isDegraded)
    }

    func testOnlyGetHasAResult() async throws {
        let t = StubTransport(steps: [.ok(good(id: 21)), .notFound])
        let outcome = try await makeClient(t).fetch(query)
        XCTAssertEqual(outcome.lyrics?.candidateID, 21)
        XCTAssertFalse(outcome.isDegraded, "search 404 是「沒有結果」而不是失敗")
    }

    func testRequestCountsForTheCommonScenarios() async throws {
        // 1) get 404（無變體）→ search 有結果：2 個請求。
        var t = StubTransport(steps: [.notFound, .ok(jsonString([record(1, firstAt: 10)]))])
        _ = try await makeClient(t).lyrics(for: query)
        XCTAssertEqual(t.requests.count, 2)
        // 2) 兩個 get 變體 404 → search 有結果：3 個請求。
        t = StubTransport(steps: [.notFound, .notFound, .ok(jsonString([record(1, firstAt: 10)]))])
        _ = try await makeClient(t, variants: variants(["t1"])).lyrics(for: query)
        XCTAssertEqual(t.requests.count, 3)
        // 3) 沒有歌手（不能 get）→ 只有 search：1 個請求。
        t = StubTransport(steps: [.ok(jsonString([record(1, firstAt: 10)]))])
        _ = try await makeClient(t).lyrics(for: LyricsQuery(title: "x", artist: " ", album: nil, duration: 223))
        XCTAssertEqual(t.requests.count, 1)
    }

    // MARK: - 429 Retry-After

    func test429HonorsRetryAfterThenSucceeds() async throws {
        let sleep = SleepRecorder()
        let t = StubTransport(steps: [.status(429, retryAfter: "3"), .ok(good()), .ok("[]")])
        let picked = try await makeClient(t, sleep: sleep).lyrics(for: query)
        XCTAssertNotNil(picked)
        XCTAssertEqual(sleep.durations, [3])
        XCTAssertEqual(t.requests.count, 3)
    }

    func test429TwiceThenSuccessSleepsEachTime() async throws {
        let sleep = SleepRecorder()
        let t = StubTransport(steps: [.status(429, retryAfter: "1"), .status(429, retryAfter: "2"), .ok(good()), .ok("[]")])
        let picked = try await makeClient(t, sleep: sleep).lyrics(for: query)
        XCTAssertNotNil(picked)
        XCTAssertEqual(sleep.durations, [1, 2])
    }

    func test429ExhaustedThrowsRateLimitedAndIsNotNotFound() async {
        let sleep = SleepRecorder()
        let t = StubTransport(steps: [.status(429, retryAfter: "4"), .status(429, retryAfter: "4"), .status(429, retryAfter: "4")])
        let client = makeClient(t, sleep: sleep)
        await expectError(.rateLimited(retryAfter: 4)) { _ = try await client.lyrics(for: query) }
        XCTAssertEqual(t.requests.count, 3, "首次請求 + 2 次重試")
        XCTAssertEqual(sleep.durations, [4, 4])
    }

    func test429WithHugeRetryAfterThrowsImmediatelyWithoutSleeping() async {
        let sleep = SleepRecorder()
        let t = StubTransport(steps: [.status(429, retryAfter: "3600")])
        let client = makeClient(t, sleep: sleep, maxRetryAfter: 30)
        await expectError(.rateLimited(retryAfter: 3600)) { _ = try await client.lyrics(for: query) }
        XCTAssertEqual(t.requests.count, 1)
        XCTAssertTrue(sleep.durations.isEmpty)
    }

    func test429WithoutRetryAfterUsesTheFallback() async throws {
        let sleep = SleepRecorder()
        let t = StubTransport(steps: [.status(429), .ok(good()), .ok("[]")])
        _ = try await makeClient(t, sleep: sleep).lyrics(for: query)
        XCTAssertEqual(sleep.durations, [LrclibClient.fallbackRetryAfter])
    }

    func testRetryAfterAcceptsDecimalAndIgnoresHTTPDateAndGarbage() async throws {
        let sleep = SleepRecorder()
        let t = StubTransport(steps: [
            .status(429, retryAfter: "1.5"),
            .status(429, retryAfter: "Wed, 21 Oct 2015 07:28:00 GMT"),
            .ok(good()),
            .ok("[]"),
        ])
        _ = try await makeClient(t, sleep: sleep).lyrics(for: query)
        XCTAssertEqual(sleep.durations, [1.5, LrclibClient.fallbackRetryAfter])
    }

    func testRetryAfterHeaderNameIsCaseInsensitive() async throws {
        let sleep = SleepRecorder()
        let lower = StubTransport.Step.response(HTTPResponse(statusCode: 429, headers: ["retry-after": "7"], body: Data()))
        let t = StubTransport(steps: [lower, .ok(good()), .ok("[]")])
        _ = try await makeClient(t, sleep: sleep).lyrics(for: query)
        XCTAssertEqual(sleep.durations, [7])
    }

    func testRateLimitCooldownDelaysTheNextCallMadeBeforeItExpires() async throws {
        let sleep = SleepRecorder()
        let clock = ManualClock()
        let t = StubTransport(steps: [.status(429, retryAfter: "5"), .status(429, retryAfter: "5"), .status(429, retryAfter: "5"), .ok(good()), .ok("[]")])
        let client = makeClient(t, sleep: sleep, clock: clock)
        await expectError(.rateLimited(retryAfter: 5)) { _ = try await client.lyrics(for: query) }
        XCTAssertEqual(sleep.durations, [5, 5])
        // 鐘面時間沒動 → 冷卻仍有效 → 下一次呼叫必須先等。
        let picked = try await client.lyrics(for: query)
        XCTAssertNotNil(picked)
        XCTAssertEqual(sleep.durations, [5, 5, 5])
    }

    func testRateLimitCooldownExpiresWithTime() async throws {
        let sleep = SleepRecorder()
        let clock = ManualClock()
        let t = StubTransport(steps: [.status(429, retryAfter: "5"), .status(429, retryAfter: "5"), .status(429, retryAfter: "5"), .ok(good()), .ok("[]")])
        let client = makeClient(t, sleep: sleep, clock: clock)
        await expectError(.rateLimited(retryAfter: 5)) { _ = try await client.lyrics(for: query) }
        clock.advance(10)
        let picked = try await client.lyrics(for: query)
        XCTAssertNotNil(picked)
        XCTAssertEqual(sleep.durations, [5, 5], "冷卻已過，不需再等")
    }

    // MARK: - 503 重試

    func test503RetriesUpToTwiceThenSucceeds() async throws {
        let sleep = SleepRecorder()
        let t = StubTransport(steps: [.status(503), .status(503), .ok(good()), .ok("[]")])
        let picked = try await makeClient(t, sleep: sleep).lyrics(for: query)
        XCTAssertNotNil(picked)
        XCTAssertEqual(t.requests.count, 4)
        XCTAssertEqual(sleep.durations, [LrclibClient.fallbackServerRetryAfter, LrclibClient.fallbackServerRetryAfter])
    }

    func test503HonorsRetryAfter() async throws {
        let sleep = SleepRecorder()
        let t = StubTransport(steps: [.status(503, retryAfter: "2"), .ok(good()), .ok("[]")])
        _ = try await makeClient(t, sleep: sleep).lyrics(for: query)
        XCTAssertEqual(sleep.durations, [2])
    }

    func test503ExhaustedThrowsAfterExactlyThreeRequests() async {
        let t = StubTransport(steps: [.status(503), .status(503), .status(503)])
        let client = makeClient(t)
        await expectError(.serverOverloaded) { _ = try await client.lyrics(for: query) }
        XCTAssertEqual(t.requests.count, 3)
    }

    func test503ExhaustionDoesNotFallThroughToSearchOrNextVariant() async {
        let t = StubTransport(steps: [.status(503), .status(503), .status(503)])
        let client = makeClient(t, variants: variants(["t1"]))
        await expectError(.serverOverloaded) { _ = try await client.lyrics(for: query) }
        XCTAssertEqual(t.requests.count, 3)
    }

    func test503RetryResetsPerRequest() async throws {
        // 第一個 get 503→404（換變體）；第二個 get 有自己的 2 次重試額度。
        let t = StubTransport(steps: [.status(503), .notFound, .status(503), .status(503), .ok(good()), .ok("[]")])
        let picked = try await makeClient(t, variants: variants(["t1"])).lyrics(for: query)
        XCTAssertNotNil(picked)
        XCTAssertEqual(t.requests.count, 6)
    }

    // MARK: - 其他狀態碼與網路錯誤（必須與「找不到」區分）

    func test500IsNotRetriedAndThrowsWhenSearchFailsToo() async {
        // get 回 500 不重試；仍試一次 search（另一個端點），兩邊都失敗才拋錯。
        let t = StubTransport(steps: [.status(500), .status(500)])
        let client = makeClient(t)
        await expectError(.unexpectedStatus(500)) { _ = try await client.lyrics(for: query) }
        XCTAssertEqual(t.requests.map { $0.url?.path }, ["/api/get", "/api/search"])
    }

    func test400Throws() async {
        let body = #"{"name":"ValidationError","statusCode":400}"#
        let t = StubTransport(steps: [.status(400, body: body), .status(400, body: body)])
        let client = makeClient(t)
        await expectError(.unexpectedStatus(400)) { _ = try await client.lyrics(for: query) }
    }

    func testTransportErrorThrowsNetworkErrorInsteadOfReturningNil() async {
        let t = StubTransport(steps: [.failure(URLError(.notConnectedToInternet))])
        let client = makeClient(t)
        do {
            _ = try await client.lyrics(for: query)
            XCTFail("網路錯誤必須拋出，不可回 nil（那代表找不到）")
        } catch LrclibError.network {
            // ok
        } catch {
            XCTFail("錯誤型別不對：\(error)")
        }
    }

    func testNetworkErrorAfter404StillThrows() async {
        let t = StubTransport(steps: [.notFound, .failure(URLError(.timedOut))])
        let client = makeClient(t, variants: variants(["t1"]))
        do {
            _ = try await client.lyrics(for: query)
            XCTFail("不能把網路錯誤當成找不到")
        } catch LrclibError.network {
            XCTAssertEqual(t.requests.count, 2)
        } catch {
            XCTFail("錯誤型別不對：\(error)")
        }
    }

    func testCancellationErrorPropagatesUntouched() async {
        let t = StubTransport(steps: [.failure(CancellationError())])
        let client = makeClient(t)
        do {
            _ = try await client.lyrics(for: query)
            XCTFail("應拋出 CancellationError")
        } catch is CancellationError {
            // ok
        } catch {
            XCTFail("錯誤型別不對：\(error)")
        }
    }

    func testURLErrorCancelledIsMappedToCancellationError() async {
        let t = StubTransport(steps: [.failure(URLError(.cancelled))])
        let client = makeClient(t)
        do {
            _ = try await client.lyrics(for: query)
            XCTFail("應拋出 CancellationError")
        } catch is CancellationError {
            // ok
        } catch {
            XCTFail("錯誤型別不對：\(error)")
        }
    }

    func testInvalidJSONOn200ThrowsInvalidResponseWhenSearchFindsNothingEither() async {
        // get 的內容壞掉：改試 search；search 也沒有可用結果時不能宣稱「找不到」，要拋出 get 的錯誤。
        let t = StubTransport(steps: [.ok("not json at all"), .ok("[]")])
        let client = makeClient(t)
        await expectError(.invalidResponse) { _ = try await client.lyrics(for: query) }
        XCTAssertEqual(t.requests.map { $0.url?.path }, ["/api/get", "/api/search"])
    }

    func testSearchBodyThatIsNotAnArrayThrowsInvalidResponse() async {
        let t = StubTransport(steps: [.notFound, .ok(#"{"message":"oops"}"#)])
        let client = makeClient(t)
        await expectError(.invalidResponse) { _ = try await client.lyrics(for: query) }
    }

    // MARK: - 請求間隔（禮貌性節流）

    func testRequestSpacingIsAppliedBetweenConsecutiveRequestsOnly() async throws {
        let sleep = SleepRecorder()
        let t = StubTransport(steps: [.notFound, .notFound, .ok(good()), .ok("[]")])
        _ = try await makeClient(t, variants: variants(["t1", "t2"]), sleep: sleep, spacing: 0.25).lyrics(for: query)
        XCTAssertEqual(sleep.durations, [0.25, 0.25, 0.25], "四個請求之間睡三次，第一個請求前不睡")
    }

    func testNoSpacingBeforeTheFirstRequest() async throws {
        let sleep = SleepRecorder()
        let t = StubTransport(steps: [.ok(good()), .ok("[]")])
        _ = try await makeClient(t, sleep: sleep, spacing: 0.25).lyrics(for: query)
        XCTAssertEqual(sleep.durations, [0.25], "get 與 search 之間睡一次，第一個請求前不睡")
    }
}

// MARK: - URLSessionTransport（以 URLProtocol 攔截，仍不會連外網）

private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

final class URLSessionTransportTests: XCTestCase {

    private func makeTransport() -> URLSessionTransport {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSessionTransport(session: URLSession(configuration: config))
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func testMapsStatusHeadersAndBody() async throws {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: "HTTP/1.1",
                                           headerFields: ["Retry-After": "7", "Content-Type": "text/plain"])!
            return (response, Data("slow down".utf8))
        }
        let response = try await makeTransport().send(URLRequest(url: URL(string: "https://lrclib.net/api/get?x=1")!))
        XCTAssertEqual(response.statusCode, 429)
        XCTAssertEqual(response.header("retry-after"), "7")
        XCTAssertEqual(response.header("RETRY-AFTER"), "7")
        XCTAssertEqual(String(data: response.body, encoding: .utf8), "slow down")
    }

    func testPassesRequestHeadersThrough() async throws {
        let seen = Locked<String?>(nil)
        StubURLProtocol.handler = { request in
            seen.withLock { $0 = request.value(forHTTPHeaderField: "User-Agent") }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!, Data("{}".utf8))
        }
        var request = URLRequest(url: URL(string: "https://lrclib.net/api/get")!)
        request.setValue("DavidNook/test", forHTTPHeaderField: "User-Agent")
        _ = try await makeTransport().send(request)
        XCTAssertEqual(seen.snapshot, "DavidNook/test")
    }

    func testTransportFailureIsPropagated() async {
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await makeTransport().send(URLRequest(url: URL(string: "https://lrclib.net/api/get")!))
            XCTFail("應該拋出")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .notConnectedToInternet)
        } catch {
            XCTFail("錯誤型別不對：\(error)")
        }
    }

    func testHTTPResponseHeaderLookupIsCaseInsensitive() {
        let r = HTTPResponse(statusCode: 200, headers: ["Retry-After": "3"], body: Data())
        XCTAssertEqual(r.header("retry-after"), "3")
        XCTAssertNil(r.header("x-missing"))
    }
}
