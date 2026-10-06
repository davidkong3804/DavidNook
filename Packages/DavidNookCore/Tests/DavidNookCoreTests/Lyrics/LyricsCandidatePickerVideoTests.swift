import XCTest
@testable import DavidNookCore

// 影片來源（isVideoDerived）的挑選規則：長度不對稱放寬、歌名／歌手必須相符；非影片查詢完全不變。

final class LyricsCandidatePickerVideoTests: XCTestCase {

    private let lrc = "[00:10.00]alpha line\n[00:20.00]beta line"

    private func cand(
        _ id: Int, track: String = "告白氣球", artist: String = "周杰倫", dur: Double? = 215
    ) -> LrclibCandidate {
        LrclibCandidate(id: id, trackName: track, artistName: artist, albumName: nil, duration: dur,
                        instrumental: false, plainLyrics: nil, syncedLyrics: lrc)
    }

    private func video(
        _ title: String = "告白氣球", _ artist: String = "周杰倫", duration: TimeInterval = 215
    ) -> LyricsQuery {
        LyricsQuery(title: title, artist: artist, duration: duration, isVideoDerived: true)
    }

    private func picker() -> LyricsCandidatePicker { LyricsPipeline.makePicker() }

    // MARK: - 長度

    func testDefaultPolicyValues() {
        let p = VideoDurationPolicy()
        XCTAssertEqual(p.maxLonger, 60)
        XCTAssertEqual(p.maxShorter, 5)
        XCTAssertEqual(p.titleOnlyMaxLonger, 20)
    }

    func testVideoLongerThanSongWithinAllowanceIsAccepted() {
        XCTAssertEqual(picker().pick(from: [cand(1)], for: video(duration: 215 + 40))?.candidateID, 1)
        XCTAssertEqual(picker().pick(from: [cand(1)], for: video(duration: 215 + 60))?.candidateID, 1, "剛好 60 秒仍接受")
    }

    func testVideoMuchLongerThanSongIsRejected() {
        XCTAssertNil(picker().pick(from: [cand(1)], for: video(duration: 215 + 61)), "超過 60 秒：寧缺勿錯")
        XCTAssertNil(picker().pick(from: [cand(1)], for: video(duration: 600)), "10 分鐘的影片不是這首歌")
    }

    func testVideoShorterThanSongOnlyTolerancesAFewSeconds() {
        XCTAssertEqual(picker().pick(from: [cand(1)], for: video(duration: 215 - 5))?.candidateID, 1)
        XCTAssertNil(picker().pick(from: [cand(1)], for: video(duration: 215 - 6)))
    }

    func testNonVideoQueryKeepsTheStrictTwoSecondRule() {
        let plain = LyricsQuery(title: "告白氣球", artist: "周杰倫", duration: 215 + 40)
        XCTAssertNil(picker().pick(from: [cand(1)], for: plain), "非影片來源的規則完全不變")
        XCTAssertEqual(picker().pick(from: [cand(1)], for: LyricsQuery(title: "告白氣球", artist: "周杰倫", duration: 217))?.candidateID, 1)
    }

    func testUnknownVideoDurationDoesNotFilterByLength() {
        XCTAssertEqual(picker().pick(from: [cand(1)], for: video(duration: 0))?.candidateID, 1)
    }

    func testTitleOnlyQueriesUseTheTighterAllowance() {
        let titleOnly = { (d: TimeInterval) in self.video("告白氣球", "", duration: d) }
        XCTAssertEqual(picker().pick(from: [cand(1)], for: titleOnly(215 + 20))?.candidateID, 1)
        XCTAssertNil(picker().pick(from: [cand(1)], for: titleOnly(215 + 21)))
    }

    func testClosestDurationStillWinsAmongAcceptableVideoCandidates() {
        let picked = picker().pick(from: [cand(5, dur: 200), cand(6, dur: 212)], for: video(duration: 215))
        XCTAssertEqual(picked?.candidateID, 6)
    }

    // MARK: - 歌名／歌手相符

    func testTitleMismatchIsRejectedForVideoQueries() {
        XCTAssertNil(picker().pick(from: [cand(1, track: "晴天")], for: video()))
    }

    func testArtistMismatchIsRejectedForVideoQueries() {
        XCTAssertNil(picker().pick(from: [cand(1, artist: "某某翻唱")], for: video()), "同名歌曲、不同歌手＝放錯歌")
    }

    func testTitleMatchIgnoresCaseSpacesPunctuationAndScript() {
        let q = video("Shape of You", "Ed Sheeran", duration: 233)
        XCTAssertNotNil(picker().pick(from: [cand(1, track: "shape  of you!", artist: "ED SHEERAN", dur: 233)], for: q))
        // 簡繁不敏感
        XCTAssertNotNil(picker().pick(from: [cand(2, track: "告白气球", artist: "周杰伦")], for: video("告白氣球", "周杰倫")))
    }

    func testLongerRecordingTitlesContainingTheQueryTitleMatch() {
        let q = video("Shape of You", "Ed Sheeran", duration: 233)
        XCTAssertNotNil(picker().pick(from: [cand(1, track: "Shape of You (Acoustic)", artist: "Ed Sheeran", dur: 233)], for: q))
    }

    func testShortTitlesNeedAnExactMatch() {
        // 「晴天」不能因為被「雨過天晴天」包含就算相符。
        XCTAssertNil(picker().pick(from: [cand(1, track: "晴天氣球歌", artist: "周杰倫")], for: video("晴天", "周杰倫")))
        XCTAssertNotNil(picker().pick(from: [cand(2, track: "晴天", artist: "周杰倫")], for: video("晴天", "周杰倫")))
    }

    func testArtistContainmentMatchesCollaborations() {
        let q = video("Perfect", "Ed Sheeran", duration: 263)
        XCTAssertNotNil(picker().pick(from: [cand(1, track: "Perfect", artist: "Ed Sheeran, Beyoncé", dur: 263)], for: q))
    }

    func testTitleOnlyQueryRequiresExactTitleAndAcceptsAnyArtist() {
        let q = video("告白氣球", "")
        XCTAssertNotNil(picker().pick(from: [cand(1, artist: "任何歌手")], for: q))
        XCTAssertNil(picker().pick(from: [cand(2, track: "告白氣球 (Live)")], for: q), "只靠歌名時要求歌名完全相同")
    }

    func testNonVideoQueriesIgnoreTitleAndArtistMismatch() {
        // 非影片來源：沿用既有行為（長度與歌詞內容把關，LRCLIB 的搜尋結果自己負責相關性）。
        let plain = LyricsQuery(title: "告白氣球", artist: "周杰倫", duration: 215)
        XCTAssertNotNil(picker().pick(from: [cand(1, track: "晴天", artist: "別人")], for: plain))
    }
}
