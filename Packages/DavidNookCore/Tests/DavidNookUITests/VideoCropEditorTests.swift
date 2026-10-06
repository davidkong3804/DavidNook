import CoreGraphics
import DavidNookCore
import SwiftUI
import XCTest
@testable import DavidNookUI

/// 裁切：長寬比跟著裁切區域（走既有夾限）、裁切視窗版面、離屏渲染（PNG 輸出到 DAVIDNOOK_SNAPSHOT_DIR）。畫面皆為合成假圖。
@MainActor
final class VideoCropEditorTests: XCTestCase {
    private let window = CGSize(width: 1440, height: 900)
    private let closed = NotchSizing.legacyClosedWindowSize

    // MARK: 長寬比跟著裁切區域

    func testCropRatioFlowsIntoCapsulePlacementAndStaysInsideTheWindow() throws {
        var checked = 0
        for cx in stride(from: 0.0, through: 0.9, by: 0.15) {
            for w in stride(from: 0.1, through: 1.0, by: 0.15) {
                for h in stride(from: 0.1, through: 1.0, by: 0.15) {
                    let crop = NormalizedCropRect(x: cx, y: cx, width: w, height: h)
                    let ratio = try XCTUnwrap(crop.aspectRatio(windowSize: window))
                    for lyrics in [false, true] {
                        guard let r = VideoCapsulePlacement.rect(isVisible: true, notchBottom: 32, dropDistance: 6, lyricsVisible: lyrics,
                                                                 videoWidth: 320, aspectRatio: ratio) else { continue }
                        checked += 1
                        XCTAssertTrue(CGRect(x: 0, y: 0, width: closed.width, height: closed.height - 8).contains(r.insetBy(dx: 0.001, dy: 0.001)), "\(crop) \(r)")
                        // 夾限後的比例仍在 1:2…2:1
                        let shown = r.width / r.height
                        XCTAssertTrue(shown >= 0.5 - 0.001 && shown <= 2 + 0.001, "\(shown)")
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 50)
    }

    func testCroppedRatioChangesTheCapsuleShape() throws {
        let sixteenNine = try XCTUnwrap(NormalizedCropRect.full.aspectRatio(windowSize: window))   // 1.6
        let squareCrop = try XCTUnwrap(NormalizedCropRect(x: 0.2, y: 0.1, width: 0.4, height: 0.64).aspectRatio(windowSize: window))   // 1.0
        let a = try XCTUnwrap(VideoCapsulePlacement.rect(isVisible: true, notchBottom: 32, dropDistance: 6, lyricsVisible: false, videoWidth: 240, aspectRatio: sixteenNine))
        let b = try XCTUnwrap(VideoCapsulePlacement.rect(isVisible: true, notchBottom: 32, dropDistance: 6, lyricsVisible: false, videoWidth: 240, aspectRatio: squareCrop))
        XCTAssertEqual(a.width / a.height, 1.6, accuracy: 0.01)
        XCTAssertEqual(b.width / b.height, 1.0, accuracy: 0.01)
    }

    func testVeryNarrowCropIsClampedByTheMetrics() {
        XCTAssertEqual(VideoCapsuleMetrics.clampedAspectRatio(0.1), 0.5)
        XCTAssertEqual(VideoCapsuleMetrics.clampedAspectRatio(9), 2)
    }

    // MARK: 裁切視窗版面

    func testEditorWindowSizeIsBoundedAndFollowsTheAspectRatio() {
        for ratio in [0.5, 0.75, 1, 4.0 / 3, 16.0 / 9, 2, .nan, 0, 50] {
            let s = VideoCropEditorLayout.windowContentSize(windowAspectRatio: ratio)
            XCTAssertTrue(s.width.isFinite && s.height.isFinite)
            XCTAssertLessThanOrEqual(s.width, 720 + 28 + 240, "\(ratio)")
            XCTAssertLessThanOrEqual(s.height, 460 + VideoCropEditorLayout.chromeHeight + 0.001, "\(ratio)")
            XCTAssertGreaterThanOrEqual(s.width, 460 + 28 - 0.001)
        }
        let wide = VideoCropEditorLayout.windowContentSize(windowAspectRatio: 2)
        let tall = VideoCropEditorLayout.windowContentSize(windowAspectRatio: 0.5)
        XCTAssertGreaterThan(wide.width / (wide.height - 96), tall.width / (tall.height - 96))
    }

    func testModelResetClearsSelectionAndFailureNote() {
        let m = VideoCropEditorModel(selection: NormalizedCropRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5))
        m.detectionFailed = true
        m.resetToFullWindow()
        XCTAssertNil(m.selection)
        XCTAssertFalse(m.detectionFailed)
    }

    // MARK: 離屏渲染

    private let strings = VideoCropEditorStrings(
        hint: "拖曳框選要保留的區域；可拖邊角微調", autoDetect: "自動偵測", detecting: "偵測中…（約 3 秒）",
        notFound: "找不到明顯的影片區域，請手動框選", resetToFullWindow: "重設為整個視窗", confirm: "確定", cancel: "取消"
    )

    /// 假的瀏覽器視窗：網址列、分頁、中央 16:9 播放器、下方留言列表。
    private func fakeBrowserFrame(width: Int = 1280, height: Int = 800) -> CGImage {
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 0.96, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(gray: 0.82, alpha: 1)); ctx.fill(CGRect(x: 0, y: height - 90, width: width, height: 90))   // 分頁＋網址列（上方；CG 原點在左下）
        let player = CGRect(x: 60, y: 300, width: 800, height: 450)
        let gradient = CGGradient(colorsSpace: space, colors: [
            CGColor(red: 0.1, green: 0.35, blue: 0.6, alpha: 1), CGColor(red: 0.9, green: 0.5, blue: 0.25, alpha: 1)] as CFArray, locations: [0, 1])!
        ctx.saveGState(); ctx.clip(to: player)
        ctx.drawLinearGradient(gradient, start: player.origin, end: CGPoint(x: player.maxX, y: player.maxY), options: [])
        ctx.restoreGState()
        ctx.setFillColor(CGColor(gray: 0.78, alpha: 1))
        for i in 0..<5 { ctx.fill(CGRect(x: 60, y: 240 - i * 50, width: 800, height: 30)) }   // 留言
        ctx.setFillColor(CGColor(gray: 0.85, alpha: 1)); ctx.fill(CGRect(x: 900, y: 120, width: 340, height: 630))   // 推薦
        return ctx.makeImage()!
    }

    private func renderEditor(_ name: String, selection: NormalizedCropRect?, detecting: Bool = false, failed: Bool = false) throws {
        let model = VideoCropEditorModel(selection: selection)
        model.isDetecting = detecting; model.detectionFailed = failed
        let ratio = 1280.0 / 800.0
        let size = VideoCropEditorLayout.windowContentSize(windowAspectRatio: ratio)
        let view = VideoCropEditorView(model: model, display: VideoFrameDisplay(), strings: strings, windowAspectRatio: ratio, staticFrame: fakeBrowserFrame())
            .frame(width: size.width, height: size.height)
            .background(Color(white: 0.2))
            .environment(\.colorScheme, .dark)
        let image = try renderImage(view)
        try writeSnapshot(image, named: "videocrop-editor-" + name)
        XCTAssertEqual(image.width, Int(size.width) * 2)
    }

    func testRenderEditorWithoutSelection() throws { try renderEditor("none", selection: nil) }
    func testRenderEditorWithSelection() throws { try renderEditor("selected", selection: NormalizedCropRect(x: 60.0 / 1280, y: 50.0 / 800, width: 800.0 / 1280, height: 450.0 / 800)) }
    func testRenderEditorDetecting() throws { try renderEditor("detecting", selection: nil, detecting: true) }
    func testRenderEditorNotFound() throws { try renderEditor("not-found", selection: nil, failed: true) }
}
