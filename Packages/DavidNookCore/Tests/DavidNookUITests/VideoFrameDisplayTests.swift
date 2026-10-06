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
