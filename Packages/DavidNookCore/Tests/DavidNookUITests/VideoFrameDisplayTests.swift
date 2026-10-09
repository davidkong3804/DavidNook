import AppKit
import IOSurface
import XCTest
@testable import DavidNookUI

/// 畫面顯示端：新掛上的圖層（例如剛開的浮動視窗）要立刻拿到最新一幀——SCStream 在畫面不變時不送新幀，
/// 若不補送，靜止畫面的新視窗會一直是空的（看起來「卡住」）。
@MainActor
final class VideoFrameDisplayTests: XCTestCase {
    private func makeSurface() throws -> IOSurface {
        let props: [IOSurfacePropertyKey: Any] = [.width: 16, .height: 9, .bytesPerElement: 4, .pixelFormat: 0x42475241]
        return try XCTUnwrap(IOSurface(properties: props))
    }

    private func pump() { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }

    func testPresentReachesAttachedLayers() throws {
        let display = VideoFrameDisplay()
        let layer = CALayer()
        display.attach(layer)
        display.present(try makeSurface())
        pump()
        XCTAssertNotNil(layer.contents)
        display.clear()
        pump()
        XCTAssertNil(layer.contents)
    }

    func testLateAttachedLayerGetsLatestFrameImmediately() throws {
        let display = VideoFrameDisplay()
        display.present(try makeSurface())
        pump()
        let late = CALayer()
        display.attach(late)
        XCTAssertNotNil(late.contents, "後掛上的圖層不必等下一幀")
        display.clear()
        pump()
        let afterClear = CALayer()
        display.attach(afterClear)
        XCTAssertNil(afterClear.contents, "clear 之後不可再補送舊畫面")
    }

    func testFloatingViewShowsFrameAfterOpeningOnStaticSource() throws {
        let display = VideoFrameDisplay()
        display.present(try makeSurface())
        pump()
        let view = FloatingVideoView(display: display)
        let hasContents = view.layer?.sublayers?.contains { $0.contents != nil } ?? false
        XCTAssertTrue(hasContents)
    }

    func testReleasedLayerDoesNotCrash() throws {
        let display = VideoFrameDisplay()
        autoreleasepool { display.attach(CALayer()) }
        display.present(try makeSurface())
        pump()
    }
}

/// 畫質：縮小用三線性、放大用線性、等比顯示；contentsScale 跟著視窗的 backingScaleFactor。
@MainActor
final class VideoLayerQualityTests: XCTestCase {
    func testAttachedLayerGetsQualityFilters() {
        let display = VideoFrameDisplay()
        let layer = CALayer()
        display.attach(layer)
        XCTAssertEqual(layer.contentsGravity, .resizeAspect)
        XCTAssertEqual(layer.minificationFilter, .trilinear)
        XCTAssertEqual(layer.magnificationFilter, .linear)
    }

    func testFloatingViewVideoLayerUsesQualityFiltersAndWindowScale() {
        let display = VideoFrameDisplay()
        let view = FloatingVideoView(display: display)
        XCTAssertEqual(view.videoLayer.contentsGravity, .resizeAspect)
        XCTAssertEqual(view.videoLayer.minificationFilter, .trilinear)
        XCTAssertEqual(view.videoLayer.magnificationFilter, .linear)
        let panel = FloatingVideoPanel(contentRect: CGRect(x: 0, y: 0, width: 320, height: 180))
        panel.contentView = view
        view.viewDidChangeBackingProperties()
        XCTAssertEqual(view.videoLayer.contentsScale, panel.backingScaleFactor)
    }

    func testLayerHostViewAppliesWindowScaleToItsLayer() {
        let display = VideoFrameDisplay()
        let host = VideoFrameLayerHostView(display: display)
        XCTAssertEqual(host.layer?.minificationFilter, .trilinear)
        XCTAssertEqual(host.layer?.magnificationFilter, .linear)
        XCTAssertEqual(host.layer?.contentsGravity, .resizeAspect)
        let panel = FloatingVideoPanel(contentRect: CGRect(x: 0, y: 0, width: 320, height: 180))
        panel.contentView = host
        host.viewDidChangeBackingProperties()
        XCTAssertEqual(host.layer?.contentsScale, panel.backingScaleFactor)
    }
}
