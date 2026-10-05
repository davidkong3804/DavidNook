import XCTest
@testable import DavidNookCore

final class LrclibCandidateDecodingTests: XCTestCase {

    private func decode(_ json: String) throws -> LrclibCandidate {
        try JSONDecoder().decode(LrclibCandidate.self, from: Data(json.utf8))
    }

    func testDecodesFullRecordIgnoringUnknownFields() throws {
        let json = jsonString(recordObject(id: 42, track: "夜行燈", artist: "阿虛", album: "某專輯", duration: 223.5,
                                           synced: "[00:01.00]x"))
        let c = try decode(json)
        XCTAssertEqual(c.id, 42)
        XCTAssertEqual(c.trackName, "夜行燈")
        XCTAssertEqual(c.artistName, "阿虛")
        XCTAssertEqual(c.albumName, "某專輯")
        XCTAssertEqual(c.duration, 223.5)
        XCTAssertFalse(c.instrumental)
        XCTAssertNil(c.plainLyrics)
        XCTAssertEqual(c.syncedLyrics, "[00:01.00]x")
    }

    func testIntegerDurationDecodes() throws {
        let c = try decode(#"{"id":1,"trackName":"a","artistName":"b","duration":233,"instrumental":false}"#)
        XCTAssertEqual(c.duration, 233)
    }

    func testNullAlbumAndNullLyricsDecode() throws {
        let c = try decode(#"{"id":1,"trackName":"a","artistName":"b","albumName":null,"duration":10,"instrumental":true,"plainLyrics":null,"syncedLyrics":null}"#)
        XCTAssertNil(c.albumName)
        XCTAssertTrue(c.instrumental)
        XCTAssertNil(c.syncedLyrics)
    }

    func testMissingOptionalFieldsGetDefaults() throws {
        let c = try decode(#"{"id":7}"#)
        XCTAssertEqual(c.id, 7)
        XCTAssertEqual(c.trackName, "")
        XCTAssertEqual(c.artistName, "")
        XCTAssertNil(c.duration)
        XCTAssertFalse(c.instrumental)
    }

    func testMissingIDFailsToDecode() {
        XCTAssertThrowsError(try decode(#"{"trackName":"a"}"#))
    }

    func testEmptyStringInput() {
        XCTAssertThrowsError(try decode(""))
    }
}

final class LyricsCandidatePickerTests: XCTestCase {

    private let query = LyricsQuery(title: "夜行燈", artist: "阿虛", album: nil, duration: 200)

    private func cand(
        _ id: Int,
        dur: Double? = 200,
        synced: String? = "[00:10.00]alpha\n[00:20.00]beta",
        instrumental: Bool = false
    ) -> LrclibCandidate {
        LrclibCandidate(id: id, trackName: "T", artistName: "A", albumName: "完全不相干的專輯名",
                        duration: dur, instrumental: instrumental, plainLyrics: nil, syncedLyrics: synced)
    }

    private func picker(_ classify: @escaping @Sendable (String) -> LyricsScript = markerClassifier) -> LyricsCandidatePicker {
        LyricsCandidatePicker(scriptClassifier: classify)
    }

    // MARK: - 過濾

    func testEmptyCandidateListYieldsNil() {
        XCTAssertNil(picker().pick(from: [], for: query))
    }

    func testInstrumentalIsFilteredOut() {
        XCTAssertNil(picker().pick(from: [cand(1, instrumental: true)], for: query))
    }

    func testMissingSyncedLyricsIsFilteredOut() {
        XCTAssertNil(picker().pick(from: [cand(1, synced: nil)], for: query))
    }

    func testBlankSyncedLyricsIsFilteredOut() {
        XCTAssertNil(picker().pick(from: [cand(1, synced: ""), cand(2, synced: "  \n ")], for: query))
    }

    func testSyncedLyricsWithoutAnyLyricLineIsFilteredOut() {
        let onlyTags = "[ti:x]\n[ar:y]\n[00:00.00]\n[03:00.00]"
        XCTAssertNil(picker().pick(from: [cand(1, synced: onlyTags)], for: query))
    }

    func testDurationDifferenceOfExactlyTwoSecondsIsKept() {
        XCTAssertEqual(picker().pick(from: [cand(1, dur: 202.0)], for: query)?.candidateID, 1)
        XCTAssertEqual(picker().pick(from: [cand(2, dur: 198.0)], for: query)?.candidateID, 2)
    }

    func testDurationDifferenceBeyondTwoSecondsIsDropped() {
        XCTAssertNil(picker().pick(from: [cand(1, dur: 202.01)], for: query))
        XCTAssertNil(picker().pick(from: [cand(2, dur: 197.9)], for: query))
    }

    func testCandidateWithoutDurationIsDroppedWhenTargetDurationIsKnown() {
        XCTAssertNil(picker().pick(from: [cand(1, dur: nil)], for: query))
    }

    func testCustomDurationTolerance() {
        let p = LyricsCandidatePicker(scriptClassifier: markerClassifier, durationTolerance: 0.5)
        XCTAssertNil(p.pick(from: [cand(1, dur: 201.0)], for: query))
        XCTAssertEqual(p.pick(from: [cand(2, dur: 200.4)], for: query)?.candidateID, 2)
    }

    func testUnknownTargetDurationDisablesDurationFiltering() {
        // duration = 0 代表播放來源沒有提供長度：不以長度過濾，也不以長度排序（改由後面的準則決定）。
        let q = LyricsQuery(title: "夜行燈", artist: "阿虛", album: nil, duration: 0)
        let picked = picker().pick(from: [cand(9, dur: 500), cand(3, dur: 10)], for: q)
        XCTAssertEqual(picked?.candidateID, 3, "長度不參與排序，兩者其餘條件相同時取 id 較小者")
    }

    func testNegativeAndNaNTargetDurationAreTreatedAsUnknown() {
        let q1 = LyricsQuery(title: "t", artist: "a", album: nil, duration: -3)
        let q2 = LyricsQuery(title: "t", artist: "a", album: nil, duration: .nan)
        XCTAssertEqual(picker().pick(from: [cand(1, dur: 99)], for: q1)?.candidateID, 1)
        XCTAssertEqual(picker().pick(from: [cand(1, dur: 99)], for: q2)?.candidateID, 1)
    }

    // MARK: - 排序：duration 差 → 原生繁體 → 首句時間 → id

    func testSmallerDurationDifferenceWinsEvenOverTraditional() {
        let exactSimplified = cand(1, dur: 200.0, synced: "[00:10.00]SIMP one")
        let farTraditional = cand(2, dur: 201.4, synced: "[00:10.00]TRAD one")   // 差 1.4s → 取整 1
        XCTAssertEqual(picker().pick(from: [farTraditional, exactSimplified], for: query)?.candidateID, 1)
    }

    func testDurationDifferenceIsComparedInWholeSeconds() {
        // 0.3s 與 0.0s 取整後同為 0，不應壓過「原生繁體」準則。
        let nearSimplified = cand(1, dur: 200.0, synced: "[00:10.00]SIMP one")
        let nearTraditional = cand(2, dur: 200.3, synced: "[00:10.00]TRAD one")
        XCTAssertEqual(picker().pick(from: [nearSimplified, nearTraditional], for: query)?.candidateID, 2)
    }

    func testNativeTraditionalBeatsSimplifiedAtEqualDuration() {
        let a = cand(1, synced: "[00:10.00]SIMP one")
        let b = cand(2, synced: "[00:10.00]TRAD one")
        XCTAssertEqual(picker().pick(from: [a, b], for: query)?.candidateID, 2)
        XCTAssertEqual(picker().pick(from: [b, a], for: query)?.candidateID, 2, "輸入順序不影響結果")
    }

    func testNativeTraditionalBeatsMixed() {
        let a = cand(1, synced: "[00:10.00]MIX one")
        let b = cand(2, synced: "[00:10.00]TRAD one")
        XCTAssertEqual(picker().pick(from: [a, b], for: query)?.candidateID, 2)
    }

    func testNeutralIsNotPenalisedComparedToTraditional() {
        let a = cand(1, synced: "[00:10.00]plain english")      // neutral
        let b = cand(2, synced: "[00:10.00]TRAD one")
        XCTAssertEqual(picker().pick(from: [b, a], for: query)?.candidateID, 1, "兩者同級，改由 id 決勝")
    }

    func testSimplifiedBeatsNothingButStillWinsWhenAlone() {
        let picked = picker().pick(from: [cand(5, synced: "[00:10.00]SIMP one")], for: query)
        XCTAssertEqual(picked?.candidateID, 5)
        XCTAssertEqual(picked?.script, .simplified)
    }

    func testFirstLineCloserToMedianWins() {
        // 首句時間：10s、14s、14.2s → 中位數 14s。10s 那筆離群。
        let outlier = cand(1, synced: "[00:10.00]one\n[00:20.00]two")
        let a = cand(2, synced: "[00:14.00]one\n[00:20.00]two")
        let b = cand(3, synced: "[00:14.20]one\n[00:20.00]two")
        let picked = picker().pick(from: [outlier, a, b], for: query)
        XCTAssertNotEqual(picked?.candidateID, 1)
    }

    func testMedianCriterionPicksTheCandidateNearestTheMedian() {
        // 首句：8s、30s、31s → 中位數 30s，8s 那筆離群，即使 id 最小也不選。
        let outlier = cand(1, synced: "[00:08.00]one")
        let a = cand(2, synced: "[00:30.00]one")
        let b = cand(3, synced: "[00:31.00]one")
        XCTAssertEqual(picker().pick(from: [outlier, b, a], for: query)?.candidateID, 2)
    }

    func testEvenSizedPoolUsesTheMeanOfTheTwoMiddleValues() {
        // 首句：10s、20s → 中位數 15s；兩者離中位數同樣遠 → id 決勝。
        let a = cand(2, synced: "[00:20.00]one")
        let b = cand(1, synced: "[00:10.00]one")
        XCTAssertEqual(picker().pick(from: [a, b], for: query)?.candidateID, 1)
    }

    func testFirstLineTimesWithinHalfASecondTieAndFallToID() {
        let a = cand(7, synced: "[00:14.00]one")
        let b = cand(4, synced: "[00:14.20]one")
        let c = cand(9, synced: "[00:14.00]one")
        XCTAssertEqual(picker().pick(from: [a, b, c], for: query)?.candidateID, 4)
    }

    func testIDIsTheFinalTieBreaker() {
        let all = [cand(30), cand(10), cand(20)]
        XCTAssertEqual(picker().pick(from: all, for: query)?.candidateID, 10)
        XCTAssertEqual(picker().pick(from: all.reversed(), for: query)?.candidateID, 10)
    }

    func testMedianIgnoresCandidatesThatWereFilteredOut() {
        // 被過濾掉的 instrumental 那筆首句 60s；若被算進中位數（變成 [10, 60, 60]→60），結果會翻成 id 3。
        // 正確：只看 [10, 60]→中位數 35，兩者等距，id 小者（2）勝。
        let junk = cand(1, synced: "[01:00.00]one", instrumental: true)
        let a = cand(2, synced: "[00:10.00]one")
        let c = cand(3, synced: "[01:00.00]one")
        XCTAssertEqual(picker().pick(from: [junk, c, a], for: query)?.candidateID, 2)
    }

    func testHeaderLinesAreStrippedBeforeComputingFirstLineTime() {
        // a：開頭有一行 0.5s 的製作資訊，真正第一句在 20s；b：第一句 20s。
        // 若沒剝除，a 的首句會被算成 0.5s 而成為離群者。
        let a = cand(1, synced: "[00:00.50]詞：甲\n[00:20.00]one\n[00:30.00]two")
        let b = cand(2, synced: "[00:20.00]one\n[00:30.00]two")
        let c = cand(3, synced: "[00:20.00]one\n[00:30.00]two")
        XCTAssertEqual(picker().pick(from: [c, b, a], for: query)?.candidateID, 1)
    }

    func testLRCOffsetTagCountsTowardEffectiveFirstLineTime() {
        // a 的檔案時間 12s、offset +2000（提早 2s）→ 有效首句 10s，與另兩筆一致；b/c 為 10s。
        let a = cand(1, synced: "[offset:+2000]\n[00:12.00]one")
        let b = cand(5, synced: "[00:10.00]one")
        let c = cand(6, synced: "[00:10.00]one")
        XCTAssertEqual(picker().pick(from: [c, b, a], for: query)?.candidateID, 1)
    }

    // MARK: - 回傳內容

    func testPickedContainsCleanedLinesScriptAndMetadata() throws {
        let synced = "[ti:歌名]\n[offset:+250]\n[00:01.00]詞：甲\n[00:02.00]夜行燈 - 阿虛\n[00:12.00]TRAD 第一句\n[00:20.00]TRAD 第二句\n[00:30.00]"
        let picked = try XCTUnwrap(picker().pick(from: [cand(77, synced: synced)], for: query))
        XCTAssertEqual(picked.candidateID, 77)
        XCTAssertEqual(picked.script, .traditional)
        XCTAssertEqual(picked.offsetMs, 250)
        XCTAssertEqual(picked.metadata["ti"], "歌名")
        XCTAssertEqual(picked.lines, [L(12_000, "TRAD 第一句"), L(20_000, "TRAD 第二句"), L(30_000, "")])
    }

    func testClassifierReceivesCleanedLyricsOnly() {
        let seen = Locked<[String]>([])
        let p = LyricsCandidatePicker(scriptClassifier: { text in
            seen.withLock { $0.append(text) }
            return .neutral
        })
        let synced = "[00:01.00]詞：甲\n[00:12.00]第一句\n[00:20.00]第二句"
        _ = p.pick(from: [cand(1, synced: synced)], for: query)
        XCTAssertEqual(seen.snapshot, ["第一句\n第二句"])
    }

    func testPickedTimelineConvenienceAppliesOffsetTag() throws {
        let synced = "[offset:+500]\n[00:10.00]a\n[00:20.00]b"
        let picked = try XCTUnwrap(picker().pick(from: [cand(1, synced: synced)], for: query))
        XCTAssertEqual(picked.timeline.currentIndex(atMs: 9_500), 0)
        XCTAssertNil(picked.timeline.currentIndex(atMs: 9_499))
    }

    func testAlbumNameIsNeverUsedForSelection() {
        // 兩筆除 albumName 與 id 外完全相同：albumName 再怎麼「像」也不能影響結果。
        let a = LrclibCandidate(id: 2, trackName: "T", artistName: "A", albumName: "夜行燈",
                                duration: 200, instrumental: false, plainLyrics: nil, syncedLyrics: "[00:10.00]x")
        let b = LrclibCandidate(id: 1, trackName: "T", artistName: "A", albumName: nil,
                                duration: 200, instrumental: false, plainLyrics: nil, syncedLyrics: "[00:10.00]x")
        XCTAssertEqual(picker().pick(from: [a, b], for: query)?.candidateID, 1)
    }

    func testPickedLyricsIsCodableRoundTrip() throws {
        let picked = try XCTUnwrap(picker().pick(from: [cand(1, synced: "[offset:+10]\n[ti:x]\n[00:10.00]TRAD a")], for: query))
        let data = try JSONEncoder().encode(picked)
        let back = try JSONDecoder().decode(PickedLyrics.self, from: data)
        XCTAssertEqual(back, picked)
    }

    func testStripperNormalizerIsUsedWhenProvided() throws {
        let fold: @Sendable (String) -> String = { $0.replacingOccurrences(of: "燈", with: "灯") }
        let p = LyricsCandidatePicker(scriptClassifier: markerClassifier,
                                      stripper: LyricsMetaStripper(normalize: fold))
        let synced = "[00:01.00]夜行灯 - 阿虛\n[00:12.00]第一句\n[00:20.00]第二句"
        let picked = try XCTUnwrap(p.pick(from: [cand(1, synced: synced)], for: query))
        XCTAssertEqual(picked.lines.first?.text, "第一句")
    }
}
