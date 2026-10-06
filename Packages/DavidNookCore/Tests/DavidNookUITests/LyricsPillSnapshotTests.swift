import SwiftUI
import XCTest
@testable import DavidNookUI

/// 離屏渲染歌詞膠囊（所有句子皆為自編）。PNG 寫到 DAVIDNOOK_SNAPSHOT_DIR（沒設就用暫存目錄）。
@MainActor
final class LyricsPillSnapshotTests: XCTestCase {
    private let zhShort = "夜風輕輕吹過窗台"
    private let zhLong = "走過一條很長很長的街，只為了把沒說完的那句話慢慢說給你聽，直到天亮"
    private let enShort = "Hold on to the quiet evening light"
    private let enLong = "Walking down the long road home, I finally learned to say what I never could"

    /// 瀏海（200×32）＋下方 `drop` pt 處的膠囊，放在淺灰「桌面」上；底部小字標註參數。
    private struct Scene: View {
        var caption: String
        var drop: CGFloat
        var text: String
        var elapsed: TimeInterval
        var duration: TimeInterval?
        var style: LyricsPillStyle
        let notchHeight: CGFloat = 32

        var body: some View {
            ZStack(alignment: .top) {
                Color(white: 0.78)
                UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14)
                    .fill(Color.black)
                    .frame(width: 200, height: notchHeight)
                LyricsPillContent(text: text, elapsed: elapsed, lineDuration: duration, style: style)
                    .offset(y: LyricsPillMetrics.topOffset(notchBottom: notchHeight, dropDistance: drop))
                VStack {
                    Spacer()
                    Text(caption).font(.system(size: 10)).foregroundStyle(Color.black.opacity(0.6)).padding(4)
                }
            }
            .frame(width: 640, height: 110)
        }
    }

    private func render(_ name: String, caption: String? = nil, drop: CGFloat = 6, text: String, elapsed: TimeInterval = 0,
                        duration: TimeInterval? = 5, style: LyricsPillStyle = LyricsPillStyle()) throws -> Data {
        let scene = Scene(caption: caption ?? name, drop: drop, text: text, elapsed: elapsed, duration: duration, style: style)
        let image = try renderImage(scene)
        try writeSnapshot(image, named: "pill-" + name)
        XCTAssertEqual(image.width, 1280)
        return try pngData(image)
    }

    func testStaticShortLines() throws {
        let zh = try render("short-zh", text: zhShort)
        let en = try render("short-en", text: enShort)
        XCTAssertNotEqual(zh, en)
        // 放得下：不論經過多久都靜止。
        XCTAssertEqual(zh, try render("short-zh-later", caption: "short-zh", text: zhShort, elapsed: 3))
    }

    func testLongLineScrollsAtThreeMoments() throws {
        let pause = try render("long-zh-t0-pause", caption: "long zh t=0.2s (start pause)", text: zhLong, elapsed: 0.2)
        let mid = try render("long-zh-t1-mid", caption: "long zh t=1.5s", text: zhLong, elapsed: 1.5)
        let end = try render("long-zh-t2-end", caption: "long zh t=4.4s (end)", text: zhLong, elapsed: 4.4)
        XCTAssertNotEqual(pause, mid)
        XCTAssertNotEqual(mid, end)
        XCTAssertEqual(end, try render("long-zh-t3-held", caption: "long zh t=4.4s (end)", text: zhLong, elapsed: 9))
        _ = try render("long-en-t0", caption: "long en t=0.2s", text: enLong, elapsed: 0.2)
        _ = try render("long-en-t1", caption: "long en t=1.8s", text: enLong, elapsed: 1.8)
        _ = try render("long-en-t2", caption: "long en t=4.4s", text: enLong, elapsed: 4.4)
    }

    func testDropDistances() throws {
        let a = try render("drop-0", caption: "drop 0", drop: 0, text: zhShort)
        let b = try render("drop-6", caption: "drop 6", drop: 6, text: zhShort)
        let c = try render("drop-30", caption: "drop 30", drop: 30, text: zhShort)
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(b, c)
        _ = try render("drop-minus8", caption: "drop -8", drop: -8, text: zhShort)
    }

    func testWidthExtremes() throws {
        let narrow = try render("width-240", caption: "max width 240", text: zhLong, elapsed: 1.5, style: LyricsPillStyle(maxWidth: 240))
        let wide = try render("width-520", caption: "max width 520", text: zhLong, elapsed: 1.5, style: LyricsPillStyle(maxWidth: 520))
        XCTAssertNotEqual(narrow, wide)
    }

    func testFontSizes() throws {
        let small = try render("font-11", caption: "font 11", text: enShort, style: LyricsPillStyle(fontSize: 11))
        let big = try render("font-16", caption: "font 16", text: enShort, style: LyricsPillStyle(fontSize: 16))
        XCTAssertNotEqual(small, big)
    }

    func testReducedMotionTruncatesInsteadOfScrolling() throws {
        let style = LyricsPillStyle(reduceMotion: true)
        let early = try render("reduce-motion-zh", caption: "reduce motion zh (no scroll)", text: zhLong, elapsed: 0.2, style: style)
        let later = try render("reduce-motion-zh-later", caption: "reduce motion zh (no scroll)", text: zhLong, elapsed: 3, style: style)
        XCTAssertEqual(early, later)
        _ = try render("reduce-motion-en", caption: "reduce motion en (no scroll)", text: enLong, elapsed: 3, style: style)
    }
}
