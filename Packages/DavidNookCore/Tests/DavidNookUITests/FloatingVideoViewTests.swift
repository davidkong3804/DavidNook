import AppKit
import DavidNookCore
import XCTest
@testable import DavidNookUI

/// 浮動視窗：面板設定、純 AppKit 內容（沒有 NSHostingView）、控制列／右鍵選單、離屏渲染（PNG）。
/// 畫面是程式合成的假圖，不含任何真實視窗內容。
@MainActor
final class FloatingVideoViewTests: XCTestCase {
    private func makeView(width: CGFloat = 320, ratio: Double = 16.0 / 9.0) -> FloatingVideoView {
        let view = FloatingVideoView(display: VideoFrameDisplay())
        view.frame = CGRect(x: 0, y: 0, width: width, height: (width / ratio).rounded())
        view.aspectRatio = ratio
        view.layoutSubtreeIfNeeded()
        return view
    }

    private func fakeFrame(width: Int, height: Int) -> CGImage {
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let gradient = CGGradient(colorsSpace: space, colors: [
            CGColor(red: 0.12, green: 0.45, blue: 0.55, alpha: 1), CGColor(red: 0.9, green: 0.45, blue: 0.3, alpha: 1),
        ] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.85))
        ctx.fillEllipse(in: CGRect(x: width / 8, y: height / 4, width: height / 2, height: height / 2))
        return ctx.makeImage()!
    }

    /// 把 view 畫在一張淺灰底上（模擬桌面）；`alpha` 模擬視窗透明度。
    private func snapshot(_ view: FloatingVideoView, alpha: CGFloat = 1, name: String) throws {
        view.layoutSubtreeIfNeeded()
        let scale = 2
        let pad = 24
        let w = Int(view.bounds.width), h = Int(view.bounds.height)
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw XCTSkip("無法建立離屏位圖") }
        view.cacheDisplay(in: view.bounds, to: rep)
        let viewImage = try XCTUnwrap(rep.cgImage)
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = try XCTUnwrap(CGContext(
            data: nil, width: (w + pad * 2) * scale, height: (h + pad * 2) * scale, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // 桌面底：棋盤格淺灰＋一條假文字，才看得出半透明
        ctx.setFillColor(CGColor(gray: 0.85, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
        ctx.setFillColor(CGColor(gray: 0.45, alpha: 1))
        for i in 0..<8 { ctx.fill(CGRect(x: 20 + i * 6, y: ctx.height / 2 - 4 + (i % 2) * 120, width: ctx.width - 40 - i * 12, height: 10)) }
        ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 14, color: CGColor(gray: 0, alpha: 0.35))
        ctx.setAlpha(alpha)
        ctx.draw(viewImage, in: CGRect(x: pad * scale, y: pad * scale, width: w * scale, height: h * scale))
        let image = try XCTUnwrap(ctx.makeImage())
        try writeSnapshot(image, named: "floating-" + name)
    }

    // MARK: 面板設定

    func testPanelConfiguration() {
        let panel = FloatingVideoPanel(contentRect: CGRect(x: 0, y: 0, width: 320, height: 180))
        XCTAssertEqual(panel.level, .floating)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.styleMask.contains(.borderless))
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertFalse(panel.isOpaque)
        XCTAssertTrue(panel.hasShadow)
    }

    func testContentIsPureAppKitNoHostingView() {
        let panel = FloatingVideoPanel(contentRect: CGRect(x: 0, y: 0, width: 320, height: 180))
        let view = makeView()
        panel.contentView = view
        func walk(_ v: NSView, _ visit: (NSView) -> Void) { visit(v); v.subviews.forEach { walk($0, visit) } }
        var names: [String] = []
        walk(view) { names.append(String(describing: type(of: $0))) }
        XCTAssertFalse(names.contains { $0.contains("Hosting") }, "浮動視窗內不可有 SwiftUI NSHostingView：\(names)")
    }

    func testSymbolsExist() {
        for name in ["pip.enter", "pip.exit", "pin", "xmark", "circle.lefthalf.filled"] {
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil), name)
        }
    }

    // MARK: 互動

    func testCornerZones() {
        let view = makeView()
        XCTAssertEqual(view.corner(at: CGPoint(x: 2, y: 2)), .bottomLeft)
        XCTAssertEqual(view.corner(at: CGPoint(x: view.bounds.width - 2, y: 2)), .bottomRight)
        XCTAssertEqual(view.corner(at: CGPoint(x: 2, y: view.bounds.height - 2)), .topLeft)
        XCTAssertEqual(view.corner(at: CGPoint(x: view.bounds.width - 2, y: view.bounds.height - 2)), .topRight)
        XCTAssertNil(view.corner(at: CGPoint(x: view.bounds.midX, y: view.bounds.midY)))
        XCTAssertNil(view.corner(at: CGPoint(x: view.bounds.midX, y: 2)), "邊中間是移動，不是縮放")
    }

    func testControlBarFollowsHoverAndStaysForProtectedNotice() {
        let view = makeView()
        XCTAssertFalse(view.controlsAreVisible)
        XCTAssertEqual(view.controlBarForTesting.alphaValue, 0)
        view.setHoverForTesting(true)
        XCTAssertTrue(view.controlsAreVisible)
        XCTAssertEqual(view.controlBarForTesting.alphaValue, 1)
        view.setHoverForTesting(false)
        XCTAssertEqual(view.controlBarForTesting.alphaValue, 0)
        view.content = .protectedNotice
        XCTAssertTrue(view.controlsAreVisible, "黑畫面說明時控制列一直顯示（要能關閉）")
        XCTAssertEqual(view.controlBarForTesting.alphaValue, 1)
    }

    func testButtonsFireCallbacks() {
        let view = makeView()
        var log: [String] = []
        view.onUnpin = { log.append("unpin") }
        view.onOpacityChange = { log.append("opacity \($0)") }
        view.setOpacity(1.0)
        view.buttonsForTesting.forEach { $0.performClick(nil) }
        XCTAssertEqual(log, ["unpin", "opacity 0.8"])
    }

    func testContextMenuOpacitySubmenu() {
        let view = makeView()
        view.setOpacity(0.6)
        let sub = view.makeMenu().items.first { $0.title == "Opacity" }?.submenu
        XCTAssertEqual(sub?.items.map(\.title), ["100%", "80%", "60%", "40%"])
        XCTAssertEqual(sub?.items.map(\.state), [.off, .off, .on, .off])
        var chosen: Double?
        view.onOpacityChange = { chosen = $0 }
        let item = sub!.items[3]
        _ = item.target?.perform(item.action, with: item)
        XCTAssertEqual(chosen, 0.4)
    }

    // MARK: 離屏渲染（PNG）

    func testSnapshotNormal() throws {
        let view = makeView(width: 320)
        view.setStaticFrame(fakeFrame(width: 640, height: 360))
        try snapshot(view, name: "normal")
    }

    func testSnapshotHoverControls() throws {
        let view = makeView(width: 320)
        view.setStaticFrame(fakeFrame(width: 640, height: 360))
        view.setHoverForTesting(true)
        try snapshot(view, name: "hover-controls")
    }

    func testSnapshotMinimumSize() throws {
        let view = makeView(width: FloatingVideoGeometry.minimumWidth)
        view.setStaticFrame(fakeFrame(width: 320, height: 180))
        view.setHoverForTesting(true)
        try snapshot(view, name: "min-size-hover")
    }

    func testSnapshotTranslucent() throws {
        let view = makeView(width: 320)
        view.setStaticFrame(fakeFrame(width: 640, height: 360))
        try snapshot(view, alpha: 0.5, name: "translucent-0.5")
    }

    func testSnapshotProtectedNotice() throws {
        let view = makeView(width: 320)
        view.content = .protectedNotice
        try snapshot(view, name: "protected-notice")
        let small = makeView(width: 160)
        small.content = .protectedNotice
        try snapshot(small, name: "protected-notice-min")
    }

    func testSnapshotReconnecting() throws {
        let view = makeView(width: 320)
        view.setStaticFrame(fakeFrame(width: 640, height: 360))
        view.content = .reconnecting
        try snapshot(view, name: "reconnecting")
    }

    func testSnapshotStalled() throws {
        let view = makeView(width: 320)
        view.content = .stalledNotice
        try snapshot(view, name: "stalled")
    }

    func testSnapshotPortrait() throws {
        let view = makeView(width: 200, ratio: 9.0 / 16.0)
        view.setStaticFrame(fakeFrame(width: 360, height: 640))
        view.setHoverForTesting(true)
        try snapshot(view, name: "portrait-hover")
    }
}

// MARK: 滑鼠事件（取代 NSEvent.mouseLocation：用事件本身的視窗座標，才能在測試與實機都正確）

@MainActor
final class FloatingVideoInteractionTests: XCTestCase {
    private func setUp(_ ratio: Double = 16.0 / 9.0) -> (FloatingVideoPanel, FloatingVideoView) {
        let panel = FloatingVideoPanel(contentRect: CGRect(x: 400, y: 400, width: 320, height: 180))
        let view = FloatingVideoView(display: VideoFrameDisplay())
        view.aspectRatio = ratio
        view.visibleFrameProvider = { CGRect(x: 0, y: 0, width: 1440, height: 875) }
        panel.contentView = view
        view.layoutSubtreeIfNeeded()
        return (panel, view)
    }

    private func event(_ type: NSEvent.EventType, at p: CGPoint, in panel: NSWindow, clickCount: Int = 1) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                           eventNumber: 0, clickCount: clickCount, pressure: 1)!
    }

    func testDragMovesWindow() {
        let (panel, view) = setUp()
        view.mouseDown(with: event(.leftMouseDown, at: CGPoint(x: 160, y: 90), in: panel))
        view.mouseDragged(with: event(.leftMouseDragged, at: CGPoint(x: 210, y: 70), in: panel))
        XCTAssertEqual(panel.frame.minX, 450, accuracy: 0.5)
        XCTAssertEqual(panel.frame.minY, 380, accuracy: 0.5)
        var ended: CGRect?
        view.onInteractionEnd = { ended = $0 }
        view.mouseUp(with: event(.leftMouseUp, at: CGPoint(x: 210, y: 70), in: panel))
        XCTAssertEqual(ended, panel.frame)
    }

    func testCornerDragResizesKeepingRatio() {
        let (panel, view) = setUp()
        let start = panel.frame
        view.mouseDown(with: event(.leftMouseDown, at: CGPoint(x: 318, y: 2), in: panel))   // 右下角
        view.mouseDragged(with: event(.leftMouseDragged, at: CGPoint(x: 418, y: 2), in: panel))
        XCTAssertEqual(panel.frame.width, 420, accuracy: 1)
        XCTAssertEqual(panel.frame.width / panel.frame.height, 16.0 / 9.0, accuracy: 0.01)
        XCTAssertEqual(panel.frame.minX, start.minX, accuracy: 0.5)
        XCTAssertEqual(panel.frame.maxY, start.maxY, accuracy: 0.5)
    }

    func testDoubleClickUnpins() {
        let (panel, view) = setUp()
        var count = 0
        view.onUnpin = { count += 1 }
        view.mouseDown(with: event(.leftMouseDown, at: CGPoint(x: 160, y: 90), in: panel, clickCount: 2))
        XCTAssertEqual(count, 1)
    }

    func testHiddenControlBarDoesNotStealClicks() {
        let (_, view) = setUp()
        let spot = CGPoint(x: view.bounds.midX - 20, y: view.bounds.height - 18)   // 控制列所在位置
        XCTAssertTrue(view.hitTest(spot) === view, "沒 hover 時（透明）控制列不可攔截點擊")
        view.setHoverForTesting(true)
        XCTAssertTrue(view.hitTest(spot) is NSButton || view.hitTest(spot)?.superview is NSView)
    }

    func testControlBarNeverOverlapsCornerZones() {
        for width in [FloatingVideoGeometry.minimumWidth, 200, 320] {
            let view = FloatingVideoView(display: VideoFrameDisplay())
            view.frame = CGRect(x: 0, y: 0, width: width, height: (width * 9 / 16).rounded())
            view.layoutSubtreeIfNeeded()
            let bar = view.controlBarForTesting.frame
            XCTAssertGreaterThan(bar.minX, FloatingVideoView.cornerZone, "\(width)")
            XCTAssertLessThan(bar.maxX, width - FloatingVideoView.cornerZone, "\(width)")
        }
    }

    func testMenuHasUnpinAndOpacityOnly() {
        let (_, view) = setUp()
        let titles = view.makeMenu().items.filter { !$0.isSeparatorItem }.map(\.title)
        XCTAssertEqual(titles, ["Unpin", "Opacity"])
    }

    func testStatusNotices() {
        let (_, view) = setUp()
        view.content = .reconnecting
        XCTAssertTrue(view.controlsAreVisible)
        view.content = .stalledNotice
        XCTAssertTrue(view.controlsAreVisible, "錯誤說明時一定要能關閉")
    }
}
