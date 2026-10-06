import AppKit
import DavidNookCore
import SwiftUI

/// 裁切視窗上的所有文案；App 傳入在地化後的字串。
public struct VideoCropEditorStrings {
    public var hint: String
    public var autoDetect: String
    public var detecting: String
    public var notFound: String
    public var resetToFullWindow: String
    public var confirm: String
    public var cancel: String

    public init(hint: String, autoDetect: String, detecting: String, notFound: String, resetToFullWindow: String, confirm: String, cancel: String) {
        self.hint = hint; self.autoDetect = autoDetect; self.detecting = detecting; self.notFound = notFound
        self.resetToFullWindow = resetToFullWindow; self.confirm = confirm; self.cancel = cancel
    }
}

/// 裁切視窗的狀態與動作（由 App 端的視窗控制器持有；視圖只讀寫這裡）。
@MainActor
public final class VideoCropEditorModel: ObservableObject {
    /// 目前選取的區域（正規化）；nil＝整個視窗（沒有裁切）。
    @Published public var selection: NormalizedCropRect?
    @Published public var isDetecting = false
    /// 自動偵測找不到時顯示說明。
    @Published public var detectionFailed = false

    public var onAutoDetect: @MainActor () -> Void = {}
    public var onConfirm: @MainActor () -> Void = {}
    public var onCancel: @MainActor () -> Void = {}

    public init(selection: NormalizedCropRect? = nil) { self.selection = selection }

    public func resetToFullWindow() {
        selection = nil
        detectionFailed = false
    }
}

/// 裁切視窗的內容：視窗目前的即時畫面（與封面槽同一條串流的最新幀）＋可拖曳框選的區域＋按鈕。
/// 拖曳邏輯在 Core 的 `CropDragModel`（純函式、有測試）；這裡只把滑鼠座標換成 0…1。
public struct VideoCropEditorView: View {
    @ObservedObject var model: VideoCropEditorModel
    let display: VideoFrameDisplay
    let strings: VideoCropEditorStrings
    /// 來源視窗的長寬比（畫面顯示區域依此決定形狀）。
    let windowAspectRatio: Double
    /// 測試／離屏渲染用的假畫面（ImageRenderer 無法渲染 NSViewRepresentable）；正式 App 一律 nil。
    let staticFrame: CGImage?
    @State private var session: CropDragSession?

    public init(model: VideoCropEditorModel, display: VideoFrameDisplay, strings: VideoCropEditorStrings, windowAspectRatio: Double, staticFrame: CGImage? = nil) {
        self.model = model; self.display = display; self.strings = strings
        self.windowAspectRatio = VideoCapsuleMetrics.clampedAspectRatio(windowAspectRatio); self.staticFrame = staticFrame
    }

    public var body: some View {
        VStack(spacing: 10) {
            canvas
            Text(strings.hint).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Button(strings.autoDetect) { model.onAutoDetect() }.disabled(model.isDetecting)
                Button(strings.resetToFullWindow) { model.resetToFullWindow() }
                if model.isDetecting {
                    ProgressView().controlSize(.small)
                    Text(strings.detecting).font(.caption).foregroundStyle(.secondary)
                } else if model.detectionFailed {
                    Text(strings.notFound).font(.caption).foregroundStyle(.orange).lineLimit(2)
                }
                Spacer()
                Button(strings.cancel) { model.onCancel() }.keyboardShortcut(.cancelAction)
                Button(strings.confirm) { model.onConfirm() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
    }

    private var canvas: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Color.black
                if let staticFrame {
                    Image(decorative: staticFrame, scale: 1).resizable().aspectRatio(contentMode: .fit)
                } else {
                    VideoFrameLayerView(display: display)
                }
                selectionOverlay(in: size)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if session == nil {
                            session = CropDragModel.begin(at: normalized(value.startLocation, in: size), current: model.selection)
                        }
                        if let session {
                            model.selection = CropDragModel.update(session, to: normalized(value.location, in: size))
                            model.detectionFailed = false
                        }
                    }
                    .onEnded { _ in session = nil }
            )
        }
        .aspectRatio(windowAspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func normalized(_ p: CGPoint, in size: CGSize) -> CropPoint {
        CropPoint(x: size.width > 0 ? Double(p.x / size.width) : 0, y: size.height > 0 ? Double(p.y / size.height) : 0)
    }

    @ViewBuilder
    private func selectionOverlay(in size: CGSize) -> some View {
        if let sel = model.selection?.sanitized, !sel.isFullWindow {
            let rect = CGRect(x: sel.x * size.width, y: sel.y * size.height, width: sel.width * size.width, height: sel.height * size.height)
            // 框外壓暗
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                path.addRect(rect)
            }
            .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)
            Rectangle().strokeBorder(Color.white, lineWidth: 1.5).frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY).allowsHitTesting(false)
            ForEach(Array(handlePoints(rect).enumerated()), id: \.offset) { _, point in
                Circle().fill(Color.white).overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 0.5))
                    .frame(width: 9, height: 9).position(point).allowsHitTesting(false)
            }
        }
    }

    private func handlePoints(_ r: CGRect) -> [CGPoint] {
        [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
         CGPoint(x: r.maxX, y: r.midY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.midX, y: r.maxY),
         CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.minX, y: r.midY)]
    }
}

/// 裁切視窗內容區的大小（pt）：畫面區依來源長寬比放大到不超過 `maximum`，再加上下方按鈕列與邊距。
public enum VideoCropEditorLayout {
    public static let canvasMaximum = CGSize(width: 720, height: 460)
    public static let canvasMinimum = CGSize(width: 320, height: 200)
    /// 畫面區之外的固定高度（提示文字＋按鈕列＋邊距）。
    public static let chromeHeight: CGFloat = 96
    public static let horizontalChrome: CGFloat = 28

    public static func windowContentSize(windowAspectRatio: Double) -> CGSize {
        let ratio = CGFloat(VideoCapsuleMetrics.clampedAspectRatio(windowAspectRatio))
        var w = canvasMaximum.width
        var h = w / ratio
        if h > canvasMaximum.height { h = canvasMaximum.height; w = h * ratio }
        w = max(w, canvasMinimum.width)
        h = max(h, canvasMinimum.height)
        // 按鈕列需要的最小寬度
        w = max(w, 460)
        return CGSize(width: w + horizontalChrome, height: h + chromeHeight)
    }
}
