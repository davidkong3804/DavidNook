import CoreGraphics
import DavidNookCore
import SwiftUI

/// 封面槽上所有文案；App 傳入在地化後的字串。
public struct VideoArtSlotStrings {
    public var captureWindow: String
    public var changeWindow: String
    public var stop: String
    public var pinHelp: String
    public var unpinHelp: String
    public var backToCover: String
    public var blackTitle: String
    public var blackHint: String
    public var closedTitle: String
    public var closedHint: String
    public var permissionTitle: String
    public var permissionHint: String
    public var openSettings: String
    public var errorTitle: String
    public var pickerFailedHint: String
    public var streamErrorHint: String
    public var unknownErrorHint: String
    public var chooseWindow: String

    public init(
        captureWindow: String, changeWindow: String, stop: String, pinHelp: String, unpinHelp: String, backToCover: String,
        blackTitle: String, blackHint: String, closedTitle: String, closedHint: String,
        permissionTitle: String, permissionHint: String, openSettings: String,
        errorTitle: String, pickerFailedHint: String, streamErrorHint: String, unknownErrorHint: String, chooseWindow: String
    ) {
        self.captureWindow = captureWindow; self.changeWindow = changeWindow; self.stop = stop
        self.pinHelp = pinHelp; self.unpinHelp = unpinHelp; self.backToCover = backToCover
        self.blackTitle = blackTitle; self.blackHint = blackHint; self.closedTitle = closedTitle; self.closedHint = closedHint
        self.permissionTitle = permissionTitle; self.permissionHint = permissionHint; self.openSettings = openSettings
        self.errorTitle = errorTitle; self.pickerFailedHint = pickerFailedHint
        self.streamErrorHint = streamErrorHint; self.unknownErrorHint = unknownErrorHint; self.chooseWindow = chooseWindow
    }
}

public struct VideoArtSlotCallbacks {
    /// 選擇／換視窗（開系統挑選器）。
    public var onChoose: () -> Void
    /// 停止擷取（回到封面）。
    public var onStop: () -> Void
    /// 點一下影片：釘選／取消釘選。
    public var onTogglePin: () -> Void
    /// 說明狀態（黑畫面、來源關閉、錯誤）上的「回到封面」。
    public var onBackToCover: () -> Void
    public var onOpenSettings: () -> Void

    public init(
        onChoose: @escaping () -> Void, onStop: @escaping () -> Void, onTogglePin: @escaping () -> Void,
        onBackToCover: @escaping () -> Void, onOpenSettings: @escaping () -> Void
    ) {
        self.onChoose = onChoose; self.onStop = onStop; self.onTogglePin = onTogglePin
        self.onBackToCover = onBackToCover; self.onOpenSettings = onOpenSettings
    }
}

/// Home 面板的封面槽：沒在擷取時顯示專輯封面（`cover`，右上有低調的「擷取視窗」入口）；
/// 串流中改顯示擷取畫面（aspect-fit）；黑畫面、來源關閉、錯誤時顯示簡短說明。
///
/// 事件分開：**點影片本身＝釘選／取消釘選**（`pinTapLayer`，只覆蓋影片）；「換視窗」「停止」「回到封面」等是疊在上面的獨立 Button，
/// 按鈕自己吃掉點擊，不會同時觸發釘選（程式結構保證：釘選手勢只掛在最底層的透明層，按鈕在它上方的 ZStack 層）。
public struct VideoArtSlotView<Cover: View>: View {
    let state: VideoCapsuleState
    let isPinned: Bool
    let strings: VideoArtSlotStrings
    let display: VideoFrameDisplay
    let callbacks: VideoArtSlotCallbacks
    let cover: Cover
    /// 測試／離屏渲染用的假畫面（ImageRenderer 無法渲染 NSViewRepresentable）；正式 App 一律 nil。
    let staticFrame: CGImage?
    /// 測試用：模擬滑鼠停留。
    let forceHover: Bool
    @State private var isHovering = false

    public init(
        state: VideoCapsuleState, isPinned: Bool, strings: VideoArtSlotStrings, display: VideoFrameDisplay,
        callbacks: VideoArtSlotCallbacks, staticFrame: CGImage? = nil, forceHover: Bool = false,
        @ViewBuilder cover: () -> Cover
    ) {
        self.state = state; self.isPinned = isPinned; self.strings = strings; self.display = display
        self.callbacks = callbacks; self.staticFrame = staticFrame; self.forceHover = forceHover; self.cover = cover()
    }

    private var hovering: Bool { isHovering || forceHover }
    private static var corner: CGFloat { 13 }

    public var body: some View {
        content
            .onHover { isHovering = $0 }
            .animation(.easeInOut(duration: 0.15), value: hovering)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .choosing:
            ZStack(alignment: .topTrailing) {
                cover
                captureEntryButton
            }
        case .streaming:
            ZStack {
                videoLayer
                pinTapLayer
                controlsOverlay
                pinBadge
            }
            .clipShape(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
        case .blackContent:
            note(symbol: "lock.shield", title: strings.blackTitle, hint: strings.blackHint, buttons: [(strings.backToCover, callbacks.onBackToCover)], warning: true)
        case .sourceClosed:
            note(symbol: "macwindow", title: strings.closedTitle, hint: strings.closedHint,
                 buttons: [(strings.chooseWindow, callbacks.onChoose), (strings.backToCover, callbacks.onBackToCover)], warning: false)
        case .error(let failure):
            errorNote(failure)
        }
    }

    // MARK: 串流

    private var videoLayer: some View {
        ZStack {
            Color.black
            if let staticFrame {
                Image(decorative: staticFrame, scale: 1).resizable().aspectRatio(contentMode: .fit)
            } else {
                VideoFrameLayerView(display: display)
            }
        }
        .accessibilityHidden(true)
    }

    /// 點一下影片＝釘選／取消釘選。只有這一層掛釘選手勢。
    private var pinTapLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { callbacks.onTogglePin() }
            .help(isPinned ? strings.unpinHelp : strings.pinHelp)
            .accessibilityLabel(isPinned ? strings.unpinHelp : strings.pinHelp)
            .accessibilityAddTraits(.isButton)
    }

    /// 圖釘：已釘選時一直顯示（實心）；未釘選只在 hover 時顯示（空心）。不攔截點擊（點擊交給 pinTapLayer）。
    @ViewBuilder
    private var pinBadge: some View {
        if isPinned || hovering {
            VStack {
                HStack {
                    Spacer()
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.black.opacity(0.55)))
                }
                Spacer()
            }
            .padding(5)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    /// hover 才出現的「換視窗」「停止」：獨立 Button，疊在釘選手勢層上方。
    @ViewBuilder
    private var controlsOverlay: some View {
        if hovering {
            VStack {
                Spacer()
                HStack(spacing: 6) {
                    iconButton("rectangle.on.rectangle", help: strings.changeWindow, action: callbacks.onChoose)
                    iconButton("stop.fill", help: strings.stop, action: callbacks.onStop)
                }
                .padding(.bottom, 5)
            }
            .transition(.opacity)
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 26, height: 22)
                .background(Capsule().fill(Color.black.opacity(0.6)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    // MARK: 封面上的入口

    private var captureEntryButton: some View {
        Button(action: callbacks.onChoose) {
            Image(systemName: "macwindow.badge.plus")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.black.opacity(0.55)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(hovering ? 1 : 0.28)
        .padding(5)
        .help(strings.captureWindow)
        .accessibilityLabel(strings.captureWindow)
    }

    // MARK: 說明

    private func errorNote(_ failure: VideoFailure) -> some View {
        switch failure {
        case .permissionDenied:
            return AnyView(note(symbol: "lock.shield", title: strings.permissionTitle, hint: strings.permissionHint,
                                buttons: [(strings.openSettings, callbacks.onOpenSettings), (strings.backToCover, callbacks.onBackToCover)], warning: true))
        case .pickerFailed:
            return AnyView(note(symbol: "exclamationmark.triangle", title: strings.errorTitle, hint: strings.pickerFailedHint,
                                buttons: [(strings.chooseWindow, callbacks.onChoose), (strings.backToCover, callbacks.onBackToCover)], warning: true))
        case .streamStopped:
            return AnyView(note(symbol: "exclamationmark.triangle", title: strings.errorTitle, hint: strings.streamErrorHint,
                                buttons: [(strings.chooseWindow, callbacks.onChoose), (strings.backToCover, callbacks.onBackToCover)], warning: true))
        case .unknown:
            return AnyView(note(symbol: "exclamationmark.triangle", title: strings.errorTitle, hint: strings.unknownErrorHint,
                                buttons: [(strings.chooseWindow, callbacks.onChoose), (strings.backToCover, callbacks.onBackToCover)], warning: true))
        }
    }

    private func note(symbol: String, title: String, hint: String, buttons: [(String, () -> Void)], warning: Bool) -> some View {
        // 空間不夠時逐級精簡：圖示＋標題＋說明＋按鈕列 → 標題＋說明＋按鈕列 → 標題＋按鈕直排（說明改放 tooltip）。
        GeometryReader { proxy in
            if proxy.size.width < 130 {
                // 窄槽（最小面板的方形封面槽）：只留標題與直排按鈕，說明放 tooltip。
                noteBody(symbol: nil, title: title, hint: nil, buttons: buttons, warning: warning, axis: .vertical)
            } else {
                ViewThatFits(in: .vertical) {
                    noteBody(symbol: symbol, title: title, hint: hint, buttons: buttons, warning: warning, axis: .horizontal)
                    noteBody(symbol: nil, title: title, hint: hint, buttons: buttons, warning: warning, axis: .horizontal)
                    noteBody(symbol: nil, title: title, hint: nil, buttons: buttons, warning: warning, axis: .vertical)
                }
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: Self.corner, style: .continuous).fill(Color.black.opacity(0.85)))
        .overlay(RoundedRectangle(cornerRadius: Self.corner, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
        .help(hint)
        .accessibilityElement(children: .contain)
    }

    private func noteBody(symbol: String?, title: String, hint: String?, buttons: [(String, () -> Void)], warning: Bool, axis: Axis) -> some View {
        VStack(spacing: 3) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(warning ? Color.orange : Color.white.opacity(0.5))
            }
            Text(verbatim: title)
                .font(LyricsFont.font(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.8))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
            if let hint {
                Text(verbatim: hint)
                    .font(LyricsFont.font(size: 9, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
            }
            let row = ForEach(Array(buttons.enumerated()), id: \.offset) { index, button in
                noteButton(button.0, prominent: index == 0, warning: warning, action: button.1)
            }
            if axis == .horizontal { HStack(spacing: 4) { row } } else { VStack(spacing: 3) { row } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func noteButton(_ title: String, prominent: Bool, warning: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(LyricsFont.font(size: 9.5, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 7)
                .frame(height: 18)
                .background(Capsule().fill(prominent ? (warning ? Color.orange.opacity(0.55) : Color.white.opacity(0.22)) : Color.white.opacity(0.1)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
