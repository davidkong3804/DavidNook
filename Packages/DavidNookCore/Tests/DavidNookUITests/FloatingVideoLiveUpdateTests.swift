import AppKit
import CoreGraphics
import IOSurface
import XCTest
@testable import DavidNookUI

/// 回歸測試：浮動視窗收到「會持續變化」的 IOSurface 幀時，螢幕上真的在更新（不是投影片）。
/// 做法：把真的 FloatingVideoPanel 顯示出來，以 20 fps 餵內容不斷變化的合成幀（模擬 SCStream 輪流重用 3 張 IOSurface 並覆寫內容），
/// 用 CGWindowListCreateImage 擷取自己的視窗（自己的視窗不需要螢幕錄製權限）數張，比對像素是否改變。
@MainActor
final class FloatingVideoLiveUpdateTests: XCTestCase {
    private func makeSurfaces(_ n: Int) throws -> [IOSurface] {
        try (0..<n).map { _ in
            try XCTUnwrap(IOSurface(properties: [.width: 160, .height: 90, .bytesPerElement: 4, .pixelFormat: 0x42475241]))
        }
    }

    private func fill(_ s: IOSurface, step: Int) {
        s.lock(options: [], seed: nil)
        let p = s.baseAddress.assumingMemoryBound(to: UInt8.self)
        for y in 0..<s.height {
            for x in 0..<s.width {
                let i = y * s.bytesPerRow + x * 4
                let v = UInt8(truncatingIfNeeded: (x + step * 23) * 3)
                p[i] = v; p[i + 1] = UInt8(truncatingIfNeeded: y * 2 + step * 41); p[i + 2] = UInt8(truncatingIfNeeded: 255 - Int(v)); p[i + 3] = 255
            }
        }
        s.unlock(options: [], seed: nil)
    }

    private func grab(_ window: NSWindow) -> [UInt8]? {
        guard let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming]),
              let data = image.dataProvider?.data else { return nil }
        return Array(CFDataGetBytePtr(data).map { UnsafeBufferPointer(start: $0, count: CFDataGetLength(data)) } ?? UnsafeBufferPointer(start: nil, count: 0))
    }

    private func distinctFrames(rotating: Int) throws -> (captures: Int, distinct: Int) {
        _ = NSApplication.shared
        let display = VideoFrameDisplay()
        let panel = FloatingVideoPanel(contentRect: CGRect(x: 80, y: 80, width: 320, height: 180))
        let view = FloatingVideoView(display: display)
        panel.contentView = view
        panel.orderFrontRegardless()
        let surfaces = try makeSurfaces(rotating)
        var step = 0
        let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            step += 1
            let s = surfaces[step % surfaces.count]
            self.fill(s, step: step)
            display.present(s)
        }
        var shots: [[UInt8]] = []
        for _ in 0..<5 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            if let g = grab(panel) { shots.append(g) }
        }
        timer.invalidate()
        panel.orderOut(nil)
        var unique: [[UInt8]] = []
        for s in shots where !unique.contains(s) { unique.append(s) }
        return (shots.count, unique.count)
    }

    func testFloatingWindowUpdatesLiveWithRotatingSurfaces() throws {
        // 這個測試會在螢幕上真的顯示一個視窗（約 3 秒），會打擾正在使用電腦的人；預設略過，
        // 需要時以 DAVIDNOOK_LIVE_WINDOW_TESTS=1 swift test --filter FloatingVideoLiveUpdateTests 開啟。
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DAVIDNOOK_LIVE_WINDOW_TESTS"] == "1",
                          "預設不在螢幕上顯示測試視窗；設 DAVIDNOOK_LIVE_WINDOW_TESTS=1 才執行")
        let r = try distinctFrames(rotating: 3)
        if r.captures == 0 { throw XCTSkip("此環境無法擷取視窗") }
        print("LIVE rotating3 captures=\(r.captures) distinct=\(r.distinct)")
        XCTAssertGreaterThanOrEqual(r.distinct, 4, "浮動視窗必須即時更新（\(r.captures) 張擷取只有 \(r.distinct) 種畫面）")
    }

    func testFloatingWindowUpdatesLiveWithSingleReusedSurface() throws {
        // 這個測試會在螢幕上真的顯示一個視窗（約 3 秒），會打擾正在使用電腦的人；預設略過，
        // 需要時以 DAVIDNOOK_LIVE_WINDOW_TESTS=1 swift test --filter FloatingVideoLiveUpdateTests 開啟。
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DAVIDNOOK_LIVE_WINDOW_TESTS"] == "1",
                          "預設不在螢幕上顯示測試視窗；設 DAVIDNOOK_LIVE_WINDOW_TESTS=1 才執行")
        let r = try distinctFrames(rotating: 1)
        if r.captures == 0 { throw XCTSkip("此環境無法擷取視窗") }
        print("LIVE single captures=\(r.captures) distinct=\(r.distinct)")
        XCTAssertGreaterThanOrEqual(r.distinct, 4, "同一張 IOSurface 被覆寫時也必須更新（\(r.captures) 張只有 \(r.distinct) 種）")
    }
}
