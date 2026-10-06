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

    /// 任意裁切比例：釘選的浮動視窗大小仍在螢幕內、比例等於裁切比例（夾在 1:4…4:1）。
    func testCropRatioFlowsIntoFloatingWindowSize() throws {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
        var checked = 0
        for cx in stride(from: 0.0, through: 0.9, by: 0.15) {
            for w in stride(from: 0.1, through: 1.0, by: 0.15) {
                for h in stride(from: 0.1, through: 1.0, by: 0.15) {
                    let crop = NormalizedCropRect(x: cx, y: cx, width: w, height: h)
                    let ratio = try XCTUnwrap(crop.aspectRatio(windowSize: window))
                    let size = FloatingVideoGeometry.clampedSize(width: 320, aspectRatio: ratio, in: screen)
                    checked += 1
                    XCTAssertLessThanOrEqual(size.width, screen.width)
                    XCTAssertLessThanOrEqual(size.height, screen.height)
                    let eff = min(max(ratio, 0.25), 4)
                    XCTAssertEqual(size.width / size.height, eff, accuracy: 0.001)
                }
            }
        }
        XCTAssertGreaterThan(checked, 50)
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

    // MARK: 裁切後的槽與膠囊

    private func croppedFrame(_ crop: NormalizedCropRect) throws -> CGImage {
        let full = fakeBrowserFrame()
        let r = CGRect(x: crop.x * Double(full.width), y: crop.y * Double(full.height), width: crop.width * Double(full.width), height: crop.height * Double(full.height))
        return try XCTUnwrap(full.cropping(to: r))
    }

    /// 裁切後的封面槽（hover 顯示「換視窗／裁切／重設裁切／停止」）與收合膠囊（歌詞在上、影片在下）。
    func testRenderSlotAndCapsuleAfterCrop() throws {
        let crop = NormalizedCropRect(x: 60.0 / 1280, y: 50.0 / 800, width: 800.0 / 1280, height: 450.0 / 800)
        let ratio = try XCTUnwrap(crop.aspectRatio(windowSize: CGSize(width: 1280, height: 800)))
        XCTAssertEqual(ratio, 16.0 / 9.0, accuracy: 0.01)
        let frame = try croppedFrame(crop)
        let strings = VideoArtSlotStrings(
            captureWindow: "擷取視窗", changeWindow: "換視窗", stop: "停止", pinHelp: "點一下，把影片釘到瀏海外面", unpinHelp: "點一下取消釘選",
            backToCover: "回到封面", blackTitle: "", blackHint: "", closedTitle: "", closedHint: "", permissionTitle: "", permissionHint: "",
            openSettings: "", errorTitle: "", pickerFailedHint: "", streamErrorHint: "", unknownErrorHint: "", chooseWindow: "",
            crop: "裁切", resetCrop: "重設裁切")
        let slot = VideoArtSlotView(
            state: .streaming(aspectRatio: ratio), isPinned: true, hasCrop: true, strings: strings, display: VideoFrameDisplay(),
            callbacks: VideoArtSlotCallbacks(onChoose: {}, onStop: {}, onTogglePin: {}, onBackToCover: {}, onOpenSettings: {}),
            staticFrame: frame, forceHover: true
        ) { Color.gray }
            .frame(width: 288, height: 162)
            .padding(16)
            .background(Color.black)
        let img = try renderImage(slot)
        try writeSnapshot(img, named: "videocrop-slot-cropped-hover")

    }
}
