import AppKit
import DavidNookCore
import SwiftUI
import XCTest
@testable import DavidNookUI

/// 影片分頁的離屏渲染（PNG 輸出到 DAVIDNOOK_SNAPSHOT_DIR）。畫面用程式合成的假圖，不含任何真實視窗內容。
@MainActor
final class VideoPanelSnapshotTests: XCTestCase {
    private let strings = VideoPanelStrings(
        emptyTitle: "在瀏海裡看影片", emptyHint: "挑一個視窗，它的即時畫面會縮小顯示在這裡。畫面只在記憶體中，不會儲存或上傳",
        chooseWindow: "選擇視窗", choosingTitle: "請在系統挑選器選一個視窗", choosingHint: "只會顯示你選的那一個視窗；按 Esc 可取消",
        changeWindow: "換視窗", stop: "停止", pin: "釘選", unpin: "取消釘選", pinHelp: "釘選",
        widthLabel: { "寬度 \($0) pt" },
        sourceClosedTitle: "視窗已關閉", sourceClosedHint: "你選的視窗已經關掉了。重新選一個視窗就能繼續",
        blackTitle: "這個來源受內容保護", blackHint: "系統不允許擷取。可改用來源本身的畫中畫，或沒有保護的來源（例如 YouTube、本機影片）",
        permissionTitle: "需要螢幕錄製權限", permissionWhy: "系統不允許 DavidNook 擷取畫面。畫面只在你的 Mac 記憶體中縮小顯示，不會儲存或上傳",
        permissionDetail: "請到「系統設定 → 隱私權與安全性 → 螢幕與系統錄音」允許 DavidNook，然後重新開啟 App", openSettings: "開啟系統設定",
        errorTitle: "無法顯示影片", pickerFailedHint: "系統挑選器沒有開啟。請再試一次", streamErrorHint: "擷取被系統中斷。請重新選擇視窗",
        unknownErrorHint: "發生未知的錯誤。請重新選擇視窗"
    )

    private let noop = VideoPanelCallbacks(onChoose: {}, onStop: {}, onTogglePin: {}, onWidthChange: { _ in }, onWidthCommit: {}, onOpenSettings: {})

    /// 合成的「影片」畫面：漸層＋幾個色塊（亮度明顯高於黑色）。
    private func fakeFrame(width: Int, height: Int) -> CGImage {
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let gradient = CGGradient(colorsSpace: space, colors: [
            CGColor(red: 0.15, green: 0.35, blue: 0.75, alpha: 1), CGColor(red: 0.95, green: 0.6, blue: 0.25, alpha: 1),
        ] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.85))
        ctx.fillEllipse(in: CGRect(x: width / 8, y: height / 4, width: height / 2, height: height / 2))
        ctx.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.8))
        ctx.fill(CGRect(x: width / 2, y: height / 5, width: width / 3, height: height / 6))
        return ctx.makeImage()!
    }

    private func scene(state: VideoCapsuleState, width: Double, pinned: Bool = false) -> some View {
        let sizing = NotchSizing()
        let ratio: Double
        switch state {
        case .streaming(let r), .blackContent(let r): ratio = r
        default: ratio = 16.0 / 9.0
        }
        let layout = VideoCapsuleMetrics.layout(width: width, aspectRatio: ratio, sizing: sizing, headerHeight: 38, earInset: 19)
        let cw = sizing.contentWidth(earInset: 19)
        let frame = fakeFrame(width: Int(layout.videoSize.width * 2), height: Int(layout.videoSize.height * 2))
        return NotchBackdrop(size: CGSize(width: layout.panelSize.width + 20, height: layout.panelSize.height + 20)) {
            VStack(spacing: 0) {
                Color.clear.frame(height: 38)
                VideoPanelView(state: state, layout: layout, strings: self.strings, display: VideoFrameDisplay(), width: width,
                               isPinned: pinned, callbacks: self.noop, staticFrame: frame)
                    .frame(width: cw, height: layout.bodyHeight)
                Color.clear.frame(height: NotchSizing.bottomInset)
            }
            .frame(width: layout.panelSize.width, height: layout.panelSize.height, alignment: .top)
        }
    }

    private func render(_ name: String, _ view: some View) throws -> Pixels {
        let image = try renderImage(view)
        try writeSnapshot(image, named: "video-" + name)
        return Pixels(image)
    }

    func testEmptyAndChoosing() throws {
        _ = try render("empty", scene(state: .idle, width: 320))
        _ = try render("choosing", scene(state: .choosing, width: 320))
        _ = try render("source-closed", scene(state: .sourceClosed, width: 320))
    }

    func testStreamingAtThreeWidthsShowsBrightPixelsInsideThePanel() throws {
        for w in [160.0, 320.0, 480.0] {
            let pixels = try render("streaming-\(Int(w))", scene(state: .streaming(aspectRatio: 16.0 / 9.0), width: w, pinned: w == 480))
            let bright = pixels.count(rows: 0...(pixels.height - 1), above: 0.4)
            XCTAssertGreaterThan(bright, 500, "寬 \(w) 應該看得到影片畫面")
        }
    }

    func testBlackContentAndErrors() throws {
        _ = try render("black-content", scene(state: .blackContent(aspectRatio: 16.0 / 9.0), width: 320))
        _ = try render("error-permission", scene(state: .error(.permissionDenied), width: 320))
        _ = try render("error-picker", scene(state: .error(.pickerFailed), width: 320))
        _ = try render("error-stream", scene(state: .error(.streamStopped(code: -3811)), width: 320))
    }

    func testPortraitSourceStaysInsideTheBody() throws {
        _ = try render("streaming-portrait-480", scene(state: .streaming(aspectRatio: 0.5), width: 480))
    }
}
