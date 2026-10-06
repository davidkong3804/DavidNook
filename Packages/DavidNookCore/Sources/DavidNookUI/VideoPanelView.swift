import CoreGraphics
import DavidNookCore
import SwiftUI

/// 影片分頁上的所有文案；App 傳入在地化後的字串（預設值只為了預覽與測試）。
public struct VideoPanelStrings {
    public var emptyTitle: String
    public var emptyHint: String
    public var chooseWindow: String
    public var choosingTitle: String
    public var choosingHint: String
    public var changeWindow: String
    public var stop: String
    public var pin: String
    public var unpin: String
    public var pinHelp: String
    public var widthLabel: (Int) -> String
    public var sourceClosedTitle: String
    public var sourceClosedHint: String
    public var blackTitle: String
    public var blackHint: String
    public var permissionTitle: String
    public var permissionWhy: String
    public var permissionDetail: String
    public var openSettings: String
    public var errorTitle: String
    public var pickerFailedHint: String
    public var streamErrorHint: String
    public var unknownErrorHint: String

    public init(
        emptyTitle: String, emptyHint: String, chooseWindow: String, choosingTitle: String, choosingHint: String,
        changeWindow: String, stop: String, pin: String, unpin: String, pinHelp: String,
        widthLabel: @escaping (Int) -> String,
        sourceClosedTitle: String, sourceClosedHint: String, blackTitle: String, blackHint: String,
        permissionTitle: String, permissionWhy: String, permissionDetail: String, openSettings: String,
        errorTitle: String, pickerFailedHint: String, streamErrorHint: String, unknownErrorHint: String
    ) {
        self.emptyTitle = emptyTitle; self.emptyHint = emptyHint; self.chooseWindow = chooseWindow
        self.choosingTitle = choosingTitle; self.choosingHint = choosingHint
        self.changeWindow = changeWindow; self.stop = stop; self.pin = pin; self.unpin = unpin; self.pinHelp = pinHelp
        self.widthLabel = widthLabel
        self.sourceClosedTitle = sourceClosedTitle; self.sourceClosedHint = sourceClosedHint
        self.blackTitle = blackTitle; self.blackHint = blackHint
        self.permissionTitle = permissionTitle; self.permissionWhy = permissionWhy
        self.permissionDetail = permissionDetail; self.openSettings = openSettings
        self.errorTitle = errorTitle; self.pickerFailedHint = pickerFailedHint
        self.streamErrorHint = streamErrorHint; self.unknownErrorHint = unknownErrorHint
    }
}

public struct VideoPanelCallbacks {
    public var onChoose: () -> Void
    public var onStop: () -> Void
    public var onTogglePin: () -> Void
    /// 滑桿拖動中（即時改尺寸）。
    public var onWidthChange: (Double) -> Void
    /// 滑桿放開（才更新擷取解析度）。
    public var onWidthCommit: () -> Void
    public var onOpenSettings: () -> Void

    public init(
        onChoose: @escaping () -> Void, onStop: @escaping () -> Void, onTogglePin: @escaping () -> Void,
        onWidthChange: @escaping (Double) -> Void, onWidthCommit: @escaping () -> Void, onOpenSettings: @escaping () -> Void
    ) {
        self.onChoose = onChoose; self.onStop = onStop; self.onTogglePin = onTogglePin
        self.onWidthChange = onWidthChange; self.onWidthCommit = onWidthCommit; self.onOpenSettings = onOpenSettings
    }
}

/// 展開瀏海的「影片」分頁內容（資料驅動，不含擷取邏輯）。
public struct VideoPanelView: View {
    let state: VideoCapsuleState
    let layout: VideoCapsuleMetrics.Layout
    let strings: VideoPanelStrings
    let display: VideoFrameDisplay
    let width: Double
    let isPinned: Bool
    let callbacks: VideoPanelCallbacks
    /// 測試／離屏渲染用：給了就以這張圖當畫面（ImageRenderer 無法渲染 NSViewRepresentable）。正式 App 一律 nil。
    let staticFrame: CGImage?

    public init(
        state: VideoCapsuleState, layout: VideoCapsuleMetrics.Layout, strings: VideoPanelStrings,
        display: VideoFrameDisplay, width: Double, isPinned: Bool, callbacks: VideoPanelCallbacks,
        staticFrame: CGImage? = nil
    ) {
        self.state = state; self.layout = layout; self.strings = strings; self.display = display
        self.width = width; self.isPinned = isPinned; self.callbacks = callbacks; self.staticFrame = staticFrame
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle:
            message(symbol: "play.rectangle", title: strings.emptyTitle, hints: [strings.emptyHint], button: (strings.chooseWindow, callbacks.onChoose))
        case .choosing:
            message(symbol: "macwindow.badge.plus", title: strings.choosingTitle, hints: [strings.choosingHint], button: nil)
        case .streaming, .blackContent:
            HStack(spacing: VideoCapsuleMetrics.controlsSpacing) {
                videoBox
                controls
            }
        case .sourceClosed:
            message(symbol: "macwindow", title: strings.sourceClosedTitle, hints: [strings.sourceClosedHint], button: (strings.chooseWindow, callbacks.onChoose))
        case .error(let failure):
            errorView(failure)
        }
    }

    // MARK: 影片區塊

    private var videoBox: some View {
        ZStack {
            Color.black
            if case .blackContent = state {
                VStack(spacing: 3) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(Color.orange)
                    Text(verbatim: strings.blackTitle)
                        .font(LyricsFont.font(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.75))
                    Text(verbatim: strings.blackHint)
                        .font(LyricsFont.font(size: 9.5, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .lineLimit(5)
                        .minimumScaleFactor(0.8)
                }
                .padding(8)
            } else if let staticFrame {
                Image(decorative: staticFrame, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                VideoFrameLayerView(display: display)
            }
        }
        .frame(width: layout.videoSize.width, height: layout.videoSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
        .accessibilityHidden(true)
    }

    // MARK: 工具列

    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            controlButton(symbol: "rectangle.on.rectangle", title: strings.changeWindow, action: callbacks.onChoose)
            controlButton(symbol: "stop.fill", title: strings.stop, action: callbacks.onStop)
            controlButton(symbol: isPinned ? "pin.fill" : "pin", title: isPinned ? strings.unpin : strings.pin, action: callbacks.onTogglePin)
                .help(strings.pinHelp)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: strings.widthLabel(Int(VideoCapsuleSettings.clampedWidth(width).rounded())))
                    .font(LyricsFont.font(size: 10, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.55))
                Slider(
                    value: Binding(get: { VideoCapsuleSettings.clampedWidth(width) }, set: { callbacks.onWidthChange($0) }),
                    in: VideoCapsuleSettings.widthRange,
                    onEditingChanged: { editing in if !editing { callbacks.onWidthCommit() } }
                )
                .controlSize(.mini)
                .tint(Color.white.opacity(0.7))
            }
            .padding(.top, 2)
        }
        .frame(width: VideoCapsuleMetrics.controlsWidth, alignment: .leading)
    }

    private func controlButton(symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 10.5, weight: .medium))
                    .frame(width: 14)
                Text(verbatim: title)
                    .font(LyricsFont.font(size: 11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.white.opacity(0.85))
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Capsule().fill(Color.white.opacity(0.1)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: 說明與錯誤

    private func errorView(_ failure: VideoFailure) -> some View {
        switch failure {
        case .permissionDenied:
            return AnyView(message(
                symbol: "lock.shield", title: strings.permissionTitle,
                hints: [strings.permissionWhy, strings.permissionDetail],
                button: (strings.openSettings, callbacks.onOpenSettings), secondary: (strings.chooseWindow, callbacks.onChoose), warning: true
            ))
        case .pickerFailed:
            return AnyView(message(symbol: "exclamationmark.triangle", title: strings.errorTitle, hints: [strings.pickerFailedHint], button: (strings.chooseWindow, callbacks.onChoose), warning: true))
        case .streamStopped:
            return AnyView(message(symbol: "exclamationmark.triangle", title: strings.errorTitle, hints: [strings.streamErrorHint], button: (strings.chooseWindow, callbacks.onChoose), warning: true))
        case .unknown:
            return AnyView(message(symbol: "exclamationmark.triangle", title: strings.errorTitle, hints: [strings.unknownErrorHint], button: (strings.chooseWindow, callbacks.onChoose), warning: true))
        }
    }

    private func message(
        symbol: String, title: String, hints: [String],
        button: (String, () -> Void)?, secondary: (String, () -> Void)? = nil, warning: Bool = false
    ) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(warning ? Color.orange : Color.white.opacity(0.4))
            Text(verbatim: title)
                .font(LyricsFont.font(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.75))
            ForEach(Array(hints.enumerated()), id: \.offset) { _, hint in
                Text(verbatim: hint)
                    .font(LyricsFont.font(size: 10, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            HStack(spacing: 6) {
                if let button { actionButton(button.0, prominent: true, warning: warning, action: button.1) }
                if let secondary { actionButton(secondary.0, prominent: false, warning: warning, action: secondary.1) }
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func actionButton(_ title: String, prominent: Bool, warning: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(LyricsFont.font(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 10)
                .frame(height: 20)
                .background(Capsule().fill(prominent ? (warning ? Color.orange.opacity(0.55) : Color.white.opacity(0.22)) : Color.white.opacity(0.1)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
