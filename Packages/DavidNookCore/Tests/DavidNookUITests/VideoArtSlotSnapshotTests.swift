import AppKit
import DavidNookCore
import SwiftUI
import XCTest
@testable import DavidNookUI

/// Home 面板封面槽顯示影片的離屏渲染（PNG 輸出到 DAVIDNOOK_SNAPSHOT_DIR）。畫面是程式合成的假圖，不含任何真實視窗內容；
/// 控制區與歌詞用同尺寸的替身（真正的版面規則由 NotchHomeLayout／NotchHomeMetrics 決定，與 App 共用）。
@MainActor
final class VideoArtSlotSnapshotTests: XCTestCase {
    private let ear: CGFloat = 19

    private let strings = VideoArtSlotStrings(
        captureWindow: "擷取視窗", changeWindow: "換視窗", stop: "停止",
        pinHelp: "點一下，把影片釘到瀏海外面", unpinHelp: "點一下取消釘選", backToCover: "回到封面",
        blackTitle: "這個來源受內容保護", blackHint: "系統不允許擷取。可改用來源本身的畫中畫", closedTitle: "視窗已關閉", closedHint: "你選的視窗已經關掉了",
        permissionTitle: "需要螢幕錄製權限", permissionHint: "請到「系統設定 → 隱私權與安全性 → 螢幕與系統錄音」允許 DavidNook，再重新開啟 App",
        openSettings: "開啟系統設定", errorTitle: "無法顯示影片", pickerFailedHint: "系統挑選器沒有開啟，請再試一次",
        streamErrorHint: "擷取被系統中斷，請重新選擇視窗", unknownErrorHint: "發生未知的錯誤，請重新選擇視窗", chooseWindow: "選擇視窗"
    )
    private let noop = VideoArtSlotCallbacks(onChoose: {}, onStop: {}, onTogglePin: {}, onBackToCover: {}, onOpenSettings: {})

    private func fakeFrame(width: Int, height: Int) -> CGImage {
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: max(width, 1), height: max(height, 1), bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let gradient = CGGradient(colorsSpace: space, colors: [
            CGColor(red: 0.15, green: 0.35, blue: 0.75, alpha: 1), CGColor(red: 0.95, green: 0.6, blue: 0.25, alpha: 1),
        ] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.85))
        ctx.fillEllipse(in: CGRect(x: width / 8, y: height / 4, width: height / 2, height: height / 2))
        return ctx.makeImage()!
    }

    private func cover() -> some View {
        RoundedRectangle(cornerRadius: 13)
            .fill(LinearGradient(colors: [Color(red: 0.95, green: 0.55, blue: 0.2), Color(red: 0.85, green: 0.2, blue: 0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay { Image(systemName: "music.note").font(.system(size: 28)).foregroundStyle(Color.white.opacity(0.8)) }
    }

    /// 完整的 Home 內容區（表頭留白＋封面槽＋控制區替身＋歌詞替身），畫在黑色形體上。
    private func home(state: VideoCapsuleState, width: Double = 720, scale: Double = 1.0, pinned: Bool = false, hover: Bool = false, lyrics: Bool = true) -> some View {
        let sizing = NotchSizing(width: width, heightScale: scale)
        let size = sizing.openSize(for: .home)
        let cw = sizing.contentWidth(earInset: ear)
        let body = sizing.bodyHeight(for: .home)
        let ratio = state.slotAspectRatio
        let metrics = NotchHomeMetrics(contentWidth: cw, bodyHeight: body, showsLyrics: lyrics, artAspectRatio: ratio)
        let frame = fakeFrame(width: Int(metrics.artWidth * 2), height: Int(metrics.artSize * 2))
        return NotchBackdrop(size: CGSize(width: size.width + 20, height: size.height + 20)) {
            VStack(spacing: 0) {
                Color.clear.frame(height: NotchSizing.minimumHeaderHeight)
                NotchHomeLayout(metrics: metrics) {
                    VideoArtSlotView(state: state, isPinned: pinned, strings: self.strings, display: VideoFrameDisplay(),
                                     callbacks: self.noop, staticFrame: frame, forceHover: hover) { self.cover() }
                } controls: {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: "Midnight Train").font(.headline).foregroundStyle(Color.white).lineLimit(1)
                        Text(verbatim: "Sample Artist").font(.headline).fontWeight(.medium).foregroundStyle(Color.gray).lineLimit(1)
                        Spacer()
                        Capsule().fill(Color.gray.opacity(0.4)).frame(height: 5)
                        Spacer()
                        HStack(spacing: 8) {
                            ForEach(0..<5, id: \.self) { _ in Circle().fill(Color.white.opacity(0.2)).frame(width: 30, height: 30) }
                        }
                    }
                    .padding(.leading, NotchHomeMetrics.controlsLeadingInset)
                    .frame(width: metrics.controlsWidth, height: metrics.bodyHeight, alignment: .top)
                } lyrics: {
                    RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08))
                }
                Color.clear.frame(height: NotchSizing.bottomInset)
            }
            .frame(width: size.width, height: size.height, alignment: .top)
        }
    }

    private func render(_ name: String, _ view: some View) throws -> Pixels {
        let image = try renderImage(view)
        try writeSnapshot(image, named: "video-home-" + name)
        return Pixels(image)
    }

    func testCoverWhenNothingIsCaptured() throws {
        _ = try render("cover-idle", home(state: .idle))
        _ = try render("cover-idle-hover", home(state: .idle, hover: true))
    }

    func testStreamingWidensTheSlotAndShowsTheFrame() throws {
        let streaming = VideoCapsuleState.streaming(aspectRatio: 16.0 / 9.0)
        let normal = try render("streaming", home(state: streaming))
        _ = try render("streaming-hover", home(state: streaming, hover: true))
        _ = try render("streaming-pinned", home(state: streaming, pinned: true))
        _ = try render("streaming-pinned-hover", home(state: streaming, pinned: true, hover: true))
        _ = try render("streaming-no-lyrics", home(state: streaming, lyrics: false))
        _ = try render("streaming-min-size", home(state: streaming, width: 560, scale: 0.85))
        _ = try render("streaming-max-size", home(state: streaming, width: 900, scale: 1.3))
        _ = try render("streaming-portrait", home(state: .streaming(aspectRatio: 0.5)))
        XCTAssertGreaterThan(normal.count(rows: 0...(normal.height - 1), above: 0.45), 800, "應該看得到影片畫面")
    }

    func testBlackContentClosedAndErrorNotes() throws {
        _ = try render("black-content", home(state: .blackContent(aspectRatio: 16.0 / 9.0)))
        _ = try render("black-content-min-size", home(state: .blackContent(aspectRatio: 16.0 / 9.0), width: 560, scale: 0.85))
        _ = try render("source-closed", home(state: .sourceClosed))
        _ = try render("error-permission", home(state: .error(.permissionDenied)))
        _ = try render("error-permission-min-size", home(state: .error(.permissionDenied), width: 560, scale: 0.85))
        _ = try render("error-stream", home(state: .error(.streamStopped(code: -3811))))
        _ = try render("error-picker", home(state: .error(.pickerFailed)))
    }
}
