import XCTest
@testable import DavidNookCore

// 樣本皆為自編的影片標題（歌名／歌手名是公開的名稱，不含任何歌詞內容）。
// 輸入是瀏覽器「正在播放」的原樣資料：title＝影片標題、artist＝頻道名、duration＝影片長度。

final class TrackTitleExtractorTests: XCTestCase {

    private let chrome = "com.google.Chrome"

    private func extract(
        _ title: String, channel: String = "", duration: TimeInterval = 240, bundle: String? = "com.google.Chrome"
    ) -> [TrackTitleCandidate] {
        TrackTitleExtractor.candidates(title: title, artist: channel, durationSeconds: duration, sourceBundleID: bundle)
    }

    private func C(_ title: String, _ artist: String?) -> TrackTitleCandidate { TrackTitleCandidate(title, artist) }

    // MARK: - 使用者回報的實例

    func testBracketedTitleWithBilingualArtistAndLabelChannel() {
        let r = extract("周杰倫 Jay Chou【告白氣球 Balloon】Official MV", channel: "杰威爾音樂 JVR Music")
        XCTAssertEqual(r.first, C("告白氣球", "周杰倫"), "中文歌名＋中文歌手為主候選；頻道是唱片公司，不當歌手")
        XCTAssertTrue(r.contains(C("告白氣球", "Jay Chou")), "英文歌手名為次候選")
        XCTAssertTrue(r.contains(C("Balloon", "周杰倫")), "英文歌名為次候選")
        XCTAssertFalse(r.contains { $0.artist?.contains("JVR") == true }, "唱片公司頻道不可進候選")
    }

    func testLatinArtistFirstBilingualTitleInBrackets() {
        let r = extract("Jay Chou 周杰倫【晴天 Sunny Day】Official Music Video", channel: "JVR Music")
        XCTAssertEqual(r.first, C("晴天", "周杰倫"))
        XCTAssertTrue(r.contains(C("Sunny Day", "周杰倫")))
    }

    func testDashSeparatedWithParenthesizedDecoration() {
        XCTAssertEqual(extract("周杰倫 - 稻香 (官方完整版MV)", channel: "周杰倫 Jay Chou").first, C("稻香", "周杰倫"))
    }

    func testTitleMarkBracketsBeforeArtist() {
        XCTAssertEqual(extract("《七里香》 周杰倫").first, C("七里香", "周杰倫"))
    }

    // MARK: - 英文標題

    func testArtistDashTitleWithOfficialMusicVideo() {
        XCTAssertEqual(
            extract("Ed Sheeran - Shape of You (Official Music Video)", channel: "Ed Sheeran").first,
            C("Shape of You", "Ed Sheeran")
        )
    }

    func testTitleDashArtistReversedUsesChannelAsHint() {
        let r = extract("Shape of You - Ed Sheeran (Lyrics)", channel: "Ed Sheeran")
        XCTAssertEqual(r.first, C("Shape of You", "Ed Sheeran"), "頻道名吻合右側 → 右側是歌手")
    }

    func testAmbiguousOrientationEmitsBothOrders() {
        let r = extract("Shape of You - Ed Sheeran (Lyrics)", channel: "Lyric Archive Channel")
        XCTAssertTrue(r.contains(C("Shape of You", "Ed Sheeran")))
        XCTAssertTrue(r.contains(C("Ed Sheeran", "Shape of You")), "沒有線索時兩種方向都要有（由挑選器的歌名／歌手比對把關）")
    }

    func testFeaturedGuestInParenthesesIsDropped() {
        let r = extract("Dua Lipa - Levitating (feat. DaBaby) [Official Video]", channel: "Dua Lipa")
        XCTAssertEqual(r.first, C("Levitating", "Dua Lipa"))
        XCTAssertFalse(r.contains { $0.title.contains("DaBaby") || $0.artist?.contains("DaBaby") == true })
    }

    func testFtInArtistPartIsDropped() {
        XCTAssertEqual(
            extract("Artist One ft. Guest Two - Song Name (Official Audio)", channel: "").first,
            C("Song Name", "Artist One")
        )
    }

    func testAmpersandCollaborationPrefersFirstArtistThenFullName() {
        let r = extract("Ed Sheeran & Justin Bieber - I Don't Care (Official Video)", channel: "Ed Sheeran")
        XCTAssertEqual(r.first, C("I Don't Care", "Ed Sheeran"))
        XCTAssertTrue(r.contains(C("I Don't Care", "Ed Sheeran & Justin Bieber")))
    }

    func testEnDashAndEmDash() {
        XCTAssertEqual(extract("Ed Sheeran – Perfect (Official Music Video)").first, C("Perfect", "Ed Sheeran"))
        XCTAssertEqual(extract("Ed Sheeran — Perfect [4K]").first, C("Perfect", "Ed Sheeran"))
    }

    func testSquareBracketDecorationsAreDropped() {
        XCTAssertEqual(extract("Ed Sheeran - Perfect [Official Lyric Video] [4K]").first, C("Perfect", "Ed Sheeran"))
    }

    func testQuotedTitleLosesItsQuotes() {
        XCTAssertEqual(extract("Taylor Swift - \"Anti-Hero\" (Official Music Video)").first, C("Anti-Hero", "Taylor Swift"))
    }

    func testHyphenInsideNameIsNotASeparator() {
        XCTAssertEqual(extract("Jay-Z - 99 Problems (Official Video)").first, C("99 Problems", "Jay-Z"))
    }

    func testDecorationWordsInsideARealTitleSurvive() {
        // 「Video Games」是歌名：Video 不能被當成裝飾詞吃掉。
        XCTAssertEqual(
            extract("Lana Del Rey - Video Games", channel: "Lana Del Rey").first, C("Video Games", "Lana Del Rey")
        )
    }

    // MARK: - 分隔符與括號種類

    func testFullWidthPipeSeparators() {
        let r = extract("周杰倫 Jay Chou｜告白氣球 Balloon｜Official MV")
        XCTAssertEqual(r.first, C("告白氣球", "周杰倫"))
    }

    func testAsciiPipeWithTrailingDecorationSegment() {
        XCTAssertEqual(extract("Ed Sheeran - Perfect | Official Music Video").first, C("Perfect", "Ed Sheeran"))
    }

    func testCornerBracketTitleBetweenArtistAndDecoration() {
        XCTAssertEqual(extract("周杰倫「晴天」動態歌詞 Lyrics").first, C("晴天", "周杰倫"))
    }

    func testFullWidthParenthesesDecoration() {
        XCTAssertEqual(extract("周杰倫 - 夜曲（高音質）").first, C("夜曲", "周杰倫"))
    }

    func testFullWidthColonSeparator() {
        XCTAssertEqual(extract("周杰倫：青花瓷 官方MV").first, C("青花瓷", "周杰倫"))
    }

    func testLeadingDecorationBracket() {
        XCTAssertEqual(extract("【MV】周杰倫 - 晴天").first, C("晴天", "周杰倫"))
    }

    func testMusicNoteAndEmojiNoiseIsRemoved() {
        XCTAssertEqual(extract("🎵 周杰倫 - 稻香 ♪ Official MV").first, C("稻香", "周杰倫"))
    }

    func testHyphenWithoutSpacesBetweenCJKIsASeparator() {
        XCTAssertEqual(extract("周杰倫-稻香 高清").first, C("稻香", "周杰倫"))
    }

    func testArtistSpaceTitleWithoutSeparatorUsesChannelHint() {
        XCTAssertEqual(extract("周杰倫 稻香 官方MV", channel: "周杰倫 Jay Chou").first, C("稻香", "周杰倫"))
    }

    // MARK: - 簡體、雙語

    func testSimplifiedTitleIsReturnedAsIs() {
        XCTAssertEqual(extract("周杰伦 - 晴天 【动态歌词】").first, C("晴天", "周杰伦"), "不做簡繁轉換——既有管線的查詢變體會處理")
    }

    func testBilingualPairWithDashKeepsChineseFirstAndEnglishSecond() {
        let r = extract("周杰倫 Jay Chou - 告白氣球 Balloon")
        XCTAssertEqual(r.first, C("告白氣球", "周杰倫"))
        XCTAssertTrue(r.contains(C("Balloon", "周杰倫")))
    }

    // MARK: - 頻道名雜訊

    func testTopicChannelIsStrippedToArtistName() {
        XCTAssertEqual(extract("Sunny Day", channel: "Jay Chou - Topic").first, C("Sunny Day", "Jay Chou"))
    }

    func testVevoChannelIsStrippedAndCamelCaseSplit() {
        let r = extract("Ed Sheeran - Thinking Out Loud (Official Video)", channel: "EdSheeranVEVO")
        XCTAssertEqual(r.first, C("Thinking Out Loud", "Ed Sheeran"), "標題內有歌手時，頻道只當弱提示")
    }

    func testLabelChannelIsNotUsedAsArtist() {
        let r = extract("Sunny Day (Official Video)", channel: "Warner Music Group")
        XCTAssertEqual(r.first, C("Sunny Day", nil))
        XCTAssertFalse(r.contains { $0.artist != nil })
    }

    func testChannelNameIsTheArtistWhenTitleHasNone() {
        XCTAssertEqual(extract("Sunny Day Official Video HD", channel: "Jay Chou").first, C("Sunny Day", "Jay Chou"))
    }

    func testOfficialSuffixOnChannelIsStripped() {
        XCTAssertEqual(extract("Sunny Day", channel: "Jay Chou Official").first, C("Sunny Day", "Jay Chou"))
    }

    // MARK: - 乾淨、空、極端輸入

    func testCleanTitleIsReturnedUntouchedAsFirstCandidate() {
        XCTAssertEqual(extract("Shape of You", channel: "Ed Sheeran").first, C("Shape of You", "Ed Sheeran"))
        XCTAssertEqual(extract("稻香", channel: "周杰倫").first, C("稻香", "周杰倫"))
        XCTAssertEqual(extract("Re:Zero 〜Starting Life〜", channel: "Someone").first, C("Re:Zero 〜Starting Life〜", "Someone"))
    }

    func testCleanTitleWithoutChannelHasNoArtist() {
        XCTAssertEqual(extract("稻香").first, C("稻香", nil))
    }

    func testEmptyInputsReturnNothing() {
        XCTAssertEqual(extract(""), [])
        XCTAssertEqual(extract("   \n "), [])
        XCTAssertEqual(extract("", channel: "Ed Sheeran"), [])
    }

    func testOnlyDecorationWordsReturnNothing() {
        XCTAssertEqual(extract("【Official MV】"), [])
        XCTAssertEqual(extract("Official Music Video (HD)"), [])
        XCTAssertEqual(extract("【官方完整版】【高音質】", channel: "周杰倫"), [])
    }

    func testVeryLongVideosAreNotSingleSongs() {
        XCTAssertEqual(extract("Ed Sheeran - Perfect (Official Video)", duration: 3 * 3600), [], "超過 15 分鐘＝合輯／直播／專輯，寧缺勿錯")
        XCTAssertFalse(extract("Ed Sheeran - Perfect (Official Video)", duration: 0).isEmpty, "長度未知不擋")
    }

    func testNonVideoSourceReturnsTheOriginalOnly() {
        let r = TrackTitleExtractor.candidates(
            title: "Song (Official Video)", artist: "Someone", durationSeconds: 200, sourceBundleID: "com.apple.Music"
        )
        XCTAssertEqual(r, [C("Song (Official Video)", "Someone")], "乾淨來源（Apple Music）完全不解析標題")
    }

    func testCandidateListIsBoundedAndDeduplicated() {
        let r = extract("周杰倫 Jay Chou【告白氣球 Balloon】Official MV - Live - Extra", channel: "周杰倫 Jay Chou")
        XCTAssertLessThanOrEqual(r.count, TrackTitleExtractor.maxCandidates)
        XCTAssertEqual(Set(r).count, r.count)
        XCTAssertFalse(r.contains { $0.title.isEmpty })
    }

    func testNoCandidateContainsDecorationJunk() {
        let inputs = [
            "周杰倫 Jay Chou【告白氣球 Balloon】Official MV", "Ed Sheeran - Shape of You (Official Music Video)",
            "周杰倫 - 稻香 (官方完整版MV)", "《七里香》 周杰倫 動態歌詞 HD", "Shape of You - Ed Sheeran (Lyrics) [4K]",
        ]
        for input in inputs {
            for c in extract(input, channel: "Ed Sheeran") {
                for junk in ["Official", "MV", "Lyrics", "歌詞", "官方", "完整版", "HD", "4K", "【", "】", "(", ")", "《", "》"] {
                    XCTAssertFalse(c.title.contains(junk), "候選歌名含雜訊 \(junk)：\(c) ← \(input)")
                    XCTAssertFalse(c.artist?.contains(junk) == true, "候選歌手含雜訊 \(junk)：\(c) ← \(input)")
                }
            }
        }
    }

    // MARK: - 來源判斷

    func testBrowserBundleIDsAreVideoSources() {
        let browsers = [
            "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.google.Chrome", "com.google.Chrome.canary",
            "org.mozilla.firefox", "company.thebrowser.Browser", "com.microsoft.edgemac", "com.brave.Browser",
            "com.operasoftware.Opera", "com.vivaldi.Vivaldi", "org.chromium.Chromium", "com.apple.WebKit.GPU",
        ]
        for id in browsers {
            XCTAssertTrue(TrackTitleExtractor.isVideoSource(bundleID: id, title: "Clean Title"), id)
        }
    }

    func testBrowserHelpersAndWebAppsMatchByPrefix() {
        XCTAssertTrue(TrackTitleExtractor.isBrowserBundleID("com.google.Chrome.helper"))
        XCTAssertTrue(TrackTitleExtractor.isBrowserBundleID("com.google.Chrome.app.abcdef"))
        XCTAssertTrue(TrackTitleExtractor.isBrowserBundleID("com.apple.Safari.WebApp.1234"))
        XCTAssertFalse(TrackTitleExtractor.isBrowserBundleID("com.google.ChromeFake"), "要在 '.' 邊界比對，不能只比字串前綴")
    }

    func testCleanSourcesAreNeverVideoSourcesEvenWithVideoLikeTitles() {
        for id in ["com.apple.Music", "com.spotify.client", "com.netease.163music"] {
            XCTAssertFalse(TrackTitleExtractor.isVideoSource(bundleID: id, title: "周杰倫【告白氣球】Official MV"), id)
        }
    }

    func testMissingBundleIDFallsBackToTitleHeuristics() {
        XCTAssertTrue(TrackTitleExtractor.isVideoSource(bundleID: nil, title: "周杰倫 Jay Chou【告白氣球 Balloon】Official MV"))
        XCTAssertTrue(TrackTitleExtractor.isVideoSource(bundleID: "", title: "Ed Sheeran - Perfect | Official Video"))
        XCTAssertTrue(TrackTitleExtractor.isVideoSource(bundleID: nil, title: "周杰倫｜稻香"))
        XCTAssertFalse(TrackTitleExtractor.isVideoSource(bundleID: nil, title: "稻香"))
        XCTAssertFalse(TrackTitleExtractor.isVideoSource(bundleID: nil, title: "Video Games"))
        XCTAssertFalse(TrackTitleExtractor.isVideoSource(bundleID: "", title: "Shape of You"))
    }

    // MARK: - 實測回報：Comet（ai.perplexity.comet）播 YouTube 找不到歌詞

    func testCometIsABrowser() {
        XCTAssertTrue(TrackTitleExtractor.isBrowserBundleID("ai.perplexity.comet"))
        XCTAssertTrue(TrackTitleExtractor.isBrowserBundleID("ai.perplexity.comet.helper"))
        XCTAssertTrue(TrackTitleExtractor.isVideoSource(bundleID: "ai.perplexity.comet", title: "Clean Title"))
    }

    func testUnknownBundleIDWithVideoLikeTitleIsAVideoSource() {
        // 清單外的瀏覽器／網頁 App：bundle id 不認得時，不能一律當成乾淨來源。
        XCTAssertTrue(TrackTitleExtractor.isVideoSource(
            bundleID: "com.example.newbrowser", title: "陳綺貞 Cheer Chen - 旅行的意義 Travel is Meaningful (Official Music Video)"))
        XCTAssertFalse(TrackTitleExtractor.isVideoSource(bundleID: "com.example.newbrowser", title: "旅行的意義"))
    }

    func testUnknownBundleIDWithVideoTitleStillExtractsCandidates() {
        let c = TrackTitleExtractor.candidates(
            title: "周杰倫 Jay Chou【妳聽得到 You Hear Me】Official MV [ 4K ]", artist: "杰威爾音樂 JVR Music",
            durationSeconds: 240, sourceBundleID: "com.example.newbrowser")
        XCTAssertEqual(c.first, TrackTitleCandidate("妳聽得到", "周杰倫"))
    }

    func testKnownMusicAppsStayCleanEvenWithVideoLikeTitles() {
        for id in ["com.apple.Music", "com.apple.iTunes", "com.spotify.client", "com.netease.163music"] {
            let c = TrackTitleExtractor.candidates(
                title: "周杰倫【告白氣球】Official MV", artist: "周杰倫", durationSeconds: 215, sourceBundleID: id)
            XCTAssertEqual(c, [TrackTitleCandidate("周杰倫【告白氣球】Official MV", "周杰倫")], id)
        }
    }
}
