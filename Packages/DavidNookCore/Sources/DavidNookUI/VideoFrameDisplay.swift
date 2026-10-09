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

    /// 畫質設定：等比顯示；縮小、放大都用線性。不用 trilinear：它會替 IOSurface 產生並快取 mipmap，SCStream 重用同一張 surface 覆寫內容時會顯示舊畫面（實測 FloatingVideoLiveUpdateTests 單張重用 surface 只剩 1 種畫面）。擷取尺寸已跟著顯示大小走，縮小幅度本來就小。
    static func applyQuality(to layer: CALayer) {
        layer.contentsGravity = .resizeAspect
        layer.minificationFilter = .linear
        layer.magnificationFilter = .linear
    }

    func attach(_ layer: CALayer) {
        Self.applyQuality(to: layer)
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

/// 掛著影片圖層的 AppKit 視圖：contentsScale 跟著所在視窗的 backingScaleFactor（換螢幕時也更新）。
final class VideoFrameLayerHostView: NSView {
    init(display: VideoFrameDisplay) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        if let layer { display.attach(layer) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let scale = window?.backingScaleFactor { layer?.contentsScale = scale }
    }
}

/// 顯示 `VideoFrameDisplay` 的 SwiftUI 視圖（AppKit layer 為底）。
public struct VideoFrameLayerView: NSViewRepresentable {
    public let display: VideoFrameDisplay

    public init(display: VideoFrameDisplay) { self.display = display }

    public func makeNSView(context: Context) -> NSView { VideoFrameLayerHostView(display: display) }

    public func updateNSView(_ nsView: NSView, context: Context) {}
}
