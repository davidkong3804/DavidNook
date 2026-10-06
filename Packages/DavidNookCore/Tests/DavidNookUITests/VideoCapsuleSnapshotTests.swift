import AppKit
import DavidNookCore
import SwiftUI
import XCTest
@testable import DavidNookUI

/// 收合瀏海外面釘選影片膠囊的離屏渲染（PNG 輸出到 DAVIDNOOK_SNAPSHOT_DIR）。畫面是程式合成的假圖，不含任何真實視窗內容。
/// 版面（位置、尺寸）直接用 App 用的 `VideoCapsulePlacement`／`VideoCapsuleStack`，歌詞膠囊用真正的 `LyricsPillContent`（自編句子）。
@MainActor
final class VideoCapsuleSnapshotTests: XCTestCase {
    private let window = NotchSizing.legacyClosedWindowSize
    private let notchBottom: CGFloat = 32
    private let drop: CGFloat = 6

    private func fakeFrame(width: Int, height: Int) -> CGImage {
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: max(width, 1), height: max(height, 1), bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let gradient = CGGradient(colorsSpace: space, colors: [
            CGColor(red: 0.12, green: 0.45, blue: 0.55, alpha: 1), CGColor(red: 0.9, green: 0.45, blue: 0.3, alpha: 1),
        ] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.85))
        ctx.fillEllipse(in: CGRect(x: width / 8, y: height / 4, width: height / 2, height: height / 2))
        return ctx.makeImage()!
    }

    private struct Scene: View {
        var caption: String
        var video: CGRect?
        var lyrics: CGRect?
        var hover: Bool
        var frame: CGImage?
        let window: CGSize
        let notchBottom: CGFloat

        var body: some View {
            ZStack(alignment: .topLeading) {
                Color(white: 0.78)
                UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14)
                    .fill(Color.black)
                    .frame(width: 200, height: notchBottom)
                    .position(x: window.width / 2, y: notchBottom / 2)
                if let lyrics {
                    LyricsPillContent(text: "夜風輕輕吹過窗台", elapsed: 0, lineDuration: 5)
                        .position(x: lyrics.midX, y: lyrics.midY)
                }
                if let video, let frame {
                    VideoCapsuleView(size: video.size, isVisible: true, isHovering: hover, display: VideoFrameDisplay(),
                                     motion: NotchMotion(), staticFrame: frame)
                        .position(x: video.midX, y: video.midY)
                }
                VStack {
                    Spacer()
                    Text(caption).font(.system(size: 10)).foregroundStyle(Color.black.opacity(0.6)).padding(2)
                }
                .frame(width: window.width, height: window.height)
            }
            .frame(width: window.width, height: window.height)
        }
    }

    @discardableResult
    private func render(_ name: String, visible: Bool = true, lyrics: Bool, width: Double = 320, ratio: Double = 16.0 / 9.0,
                        hover: Bool = false, caption: String? = nil) throws -> CGRect? {
        let layout = VideoCapsuleStack.layout(
            notchBottom: notchBottom, dropDistance: drop, lyricsVisible: lyrics, lyricsWidth: 140, videoWidth: width, aspectRatio: ratio
        )
        let placed = VideoCapsulePlacement.rect(
            isVisible: visible, notchBottom: notchBottom, dropDistance: drop, lyricsVisible: lyrics, videoWidth: width, aspectRatio: ratio
        )
        XCTAssertEqual(placed, visible ? layout.video : nil)
        var lyricsRect = layout.lyrics
        if let r = lyricsRect {   // 歌詞膠囊的真實寬度由文字決定；這裡只取位置
            lyricsRect = CGRect(x: window.width / 2, y: r.minY, width: 0, height: r.height)
        }
        let frame = placed.map { fakeFrame(width: Int($0.width * 2), height: Int($0.height * 2)) }
        let scene = Scene(caption: caption ?? name, video: placed, lyrics: lyricsRect, hover: hover, frame: frame,
                          window: window, notchBottom: notchBottom)
        let image = try renderImage(scene)
        try writeSnapshot(image, named: "videocap-" + name)
        XCTAssertEqual(image.width, Int(window.width) * 2)
        return placed
    }

    func testAloneDefaultSize() throws {
        let r = try XCTUnwrap(render("alone-default", lyrics: false, caption: "alone (no lyrics), width 320 → fitted"))
        XCTAssertEqual(r.minY, 38, accuracy: 0.01)
    }

    func testStackedWithLyrics() throws {
        let r = try XCTUnwrap(render("stacked-with-lyrics", lyrics: true, width: 240, caption: "lyrics above, video below (gap 6)"))
        XCTAssertEqual(r.minY, 38 + 22 + 6, accuracy: 0.01)
    }

    func testMinimumSize() throws {
        let r = try XCTUnwrap(render("min-size", lyrics: false, width: 160, caption: "slider min 160"))
        XCTAssertEqual(r.width, 160, accuracy: 0.01)
    }

    func testMaximumSizeIsClampedInsideTheWindow() throws {
        let r = try XCTUnwrap(render("max-size", lyrics: false, width: 480, caption: "slider max 480 → clamped to fit 640×210"))
        XCTAssertLessThanOrEqual(r.maxY, window.height - 8 + 0.01)
        let s = try XCTUnwrap(render("max-size-with-lyrics", lyrics: true, width: 480, caption: "max + lyrics → clamped"))
        XCTAssertLessThanOrEqual(s.maxY, window.height - 8 + 0.01)
    }

    func testHoverShowsPinHint() throws {
        try render("hover-pin", lyrics: false, width: 240, hover: true, caption: "hover: small pin")
    }

    func testPortraitAndSquare() throws {
        try render("portrait-0.75", lyrics: false, ratio: 0.75, caption: "ratio 3:4")
    }

    /// 黑畫面（疑似受保護）：不顯示黑塊——狀態機同時自動取消釘選，所以可見性為 false、沒有膠囊矩形。
    func testBlackContentShowsNoCapsule() throws {
        var m = VideoCapsuleStateMachine()
        m.handle(.source(.started(aspectRatio: 16.0 / 9.0)), at: 0)
        m.handle(.togglePin, at: 0)
        for t in 1...4 { m.handle(.source(.brightness(0)), at: Double(t)) }
        let visible = VideoCapsuleVisibility.isVisible(isEnabled: true, isNotchClosed: true, isPinned: m.isPinned, state: m.state)
        XCTAssertFalse(visible)
        let r = try render("black-content-hidden", visible: visible, lyrics: true, caption: "DRM/black: capsule hidden + auto-unpinned")
        XCTAssertNil(r)
    }

    func testLyricsOnlyForComparison() throws {
        try render("lyrics-only", visible: false, lyrics: true, caption: "lyrics only (video not pinned)")
    }
}
