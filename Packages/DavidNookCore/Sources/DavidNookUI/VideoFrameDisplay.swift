import AppKit
import IOSurface
import SwiftUI

/// 影片畫面的顯示端：把 IOSurface 直接設成 CALayer 的 contents（零拷貝，不轉 NSImage／CGImage）。
///
/// 隱私：只持有「目前這一幀」的顯示引用，不存檔、不快取、不截圖；`clear()` 或沒有任何視圖時立刻釋放。
/// 可同時掛在多個視圖（多個螢幕的瀏海視窗各一個）；以弱引用保存圖層，視圖消失就自然脫鉤。
public final class VideoFrameDisplay: @unchecked Sendable {
    private let layers = NSHashTable<CALayer>.weakObjects()
    private let lock = NSLock()
    /// 目前這一幀（與圖層持有的是同一個物件，不是額外的拷貝）：新掛上的圖層立刻補上，
    /// 因為 SCStream 在畫面沒變時不送新幀，不補的話靜止畫面的新視窗會一直是空的。clear 時釋放。
    private var latest: IOSurface?

    public init() {}

    func attach(_ layer: CALayer) {
        lock.lock(); layers.add(layer); let current = latest; lock.unlock()
        if let current { layer.contents = current }
    }

    /// 顯示一幀（可從任何執行緒呼叫；實際設定在主執行緒）。
    public func present(_ surface: IOSurface) {
        DispatchQueue.main.async { [self] in
            lock.lock(); latest = surface; let all = layers.allObjects; lock.unlock()
            for layer in all { layer.contents = surface }
        }
    }

    /// 清掉畫面（停止、來源關閉、換視窗時）。
    public func clear() {
        DispatchQueue.main.async { [self] in
            lock.lock(); latest = nil; let all = layers.allObjects; lock.unlock()
            for layer in all { layer.contents = nil }
        }
    }
}

/// 顯示 `VideoFrameDisplay` 的 SwiftUI 視圖（AppKit layer 為底）。
public struct VideoFrameLayerView: NSViewRepresentable {
    public let display: VideoFrameDisplay

    public init(display: VideoFrameDisplay) { self.display = display }

    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.contentsGravity = .resizeAspect
        view.layer?.backgroundColor = NSColor.black.cgColor
        if let layer = view.layer { display.attach(layer) }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {}
}
