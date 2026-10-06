import AppKit
import SwiftUI

/// 對時控制的文案；預設為繁體中文，App 傳入在地化後的字串。
///
/// 帶秒數的句子用閉包（參數是已格式化的秒數，例如 "1.2"），讓各語言自己決定語序。
public struct OffsetControlStrings: Sendable {
    // 常駐的小按鈕
    public var badgeIdle: String
    public var advancedBadge: @Sendable (String) -> String
    public var delayedBadge: @Sendable (String) -> String
    public var badgeHelp: String

    // 展開後的狀態列
    public var noOffsetStatus: String
    public var advancedStatus: @Sendable (String) -> String
    public var delayedStatus: @Sendable (String) -> String
    /// 沒有偏移時，狀態列改顯示的操作提示（點歌詞對齊）。
    public var idleHint: String
    public var closeHelp: String

    // 兩顆主要按鈕
    public var advanceCaption: String
    public var advanceTitle: String
    public var advanceHelp: String
    public var delayCaption: String
    public var delayTitle: String
    public var delayHelp: String

    // 粗調／重設
    public var coarse: String
    public var coarseHelp: String
    public var reset: String
    public var resetHelp: String

    // 點歌詞對齊
    public var aligned: String
    public var alignedLimit: String
    public var lineHelp: String

    /// 目前偏移的無障礙標籤前綴。
    public var currentOffset: String

    public init(
        badgeIdle: String,
        advancedBadge: @escaping @Sendable (String) -> String,
        delayedBadge: @escaping @Sendable (String) -> String,
        badgeHelp: String,
        noOffsetStatus: String,
        advancedStatus: @escaping @Sendable (String) -> String,
        delayedStatus: @escaping @Sendable (String) -> String,
        idleHint: String,
        closeHelp: String,
        advanceCaption: String,
        advanceTitle: String,
        advanceHelp: String,
        delayCaption: String,
        delayTitle: String,
        delayHelp: String,
        coarse: String,
        coarseHelp: String,
        reset: String,
        resetHelp: String,
        aligned: String,
        alignedLimit: String,
        lineHelp: String,
        currentOffset: String
    ) {
        self.badgeIdle = badgeIdle
        self.advancedBadge = advancedBadge
        self.delayedBadge = delayedBadge
        self.badgeHelp = badgeHelp
        self.noOffsetStatus = noOffsetStatus
        self.advancedStatus = advancedStatus
        self.delayedStatus = delayedStatus
        self.idleHint = idleHint
        self.closeHelp = closeHelp
        self.advanceCaption = advanceCaption
        self.advanceTitle = advanceTitle
        self.advanceHelp = advanceHelp
        self.delayCaption = delayCaption
        self.delayTitle = delayTitle
        self.delayHelp = delayHelp
        self.coarse = coarse
        self.coarseHelp = coarseHelp
        self.reset = reset
        self.resetHelp = resetHelp
        self.aligned = aligned
        self.alignedLimit = alignedLimit
        self.lineHelp = lineHelp
        self.currentOffset = currentOffset
    }

    public static let zhHant = OffsetControlStrings(
        badgeIdle: "對時",
        advancedBadge: { "提早 \($0) 秒" },
        delayedBadge: { "延後 \($0) 秒" },
        badgeHelp: "調整歌詞對時：點開微調；點正在唱的那一句歌詞可直接對齊（連點兩下）；在這裡滾動滾輪每格 0.1 秒",
        noOffsetStatus: "目前：無偏移",
        advancedStatus: { "目前：歌詞提早 \($0) 秒" },
        delayedStatus: { "目前：歌詞延後 \($0) 秒" },
        idleHint: "點正在唱的那一句，直接對齊",
        closeHelp: "收合對時",
        advanceCaption: "歌詞太晚",
        advanceTitle: "提早",
        advanceHelp: "歌詞比聲音晚出現？按此提早（按住 Option 或 Shift：每次 0.5 秒；按住不放連續調整；滾輪向下也是提早）",
        delayCaption: "歌詞太早",
        delayTitle: "延後",
        delayHelp: "歌詞比聲音早出現？按此延後（按住 Option 或 Shift：每次 0.5 秒；按住不放連續調整；滾輪向上也是延後）",
        coarse: "粗調",
        coarseHelp: "開啟後每次調整 0.5 秒（預設 0.1 秒）",
        reset: "重設",
        resetHelp: "重設這首歌的歌詞偏移",
        aligned: "已對齊，並記住這首歌",
        alignedLimit: "偏移已達上限（±60 秒）",
        lineHelp: "點這一行：把它對齊到現在播放的位置",
        currentOffset: "目前偏移"
    )

    // MARK: - 組句（純函式，有單元測試）

    /// 展開後狀態列的完整句子，例如「目前：歌詞提早 1.2 秒」。
    public func status(offsetMs: Int) -> String {
        let seconds = LyricsOffsetFormat.seconds(abs: offsetMs)
        switch LyricsOffsetFormat.direction(ofOffsetMs: offsetMs) {
        case .none: return noOffsetStatus
        case .advanced: return advancedStatus(seconds)
        case .delayed: return delayedStatus(seconds)
        }
    }

    /// 常駐小按鈕上的短字：沒有偏移顯示「對時」，有偏移顯示「提早 1.2 秒」。
    public func badge(offsetMs: Int) -> String {
        let seconds = LyricsOffsetFormat.seconds(abs: offsetMs)
        switch LyricsOffsetFormat.direction(ofOffsetMs: offsetMs) {
        case .none: return badgeIdle
        case .advanced: return advancedBadge(seconds)
        case .delayed: return delayedBadge(seconds)
        }
    }

    /// 點歌詞對齊後的回饋文字。
    public func alignedToast(isClamped: Bool) -> String {
        isClamped ? alignedLimit : aligned
    }
}

// MARK: - 展開的對時控制卡片

/// 展開後的對時控制：兩列、固定高度 `cardHeight`。只回呼，不保存狀態。
///
/// 方向約定與 Core 相同：**正值＝歌詞提早顯示**。
/// - 第一列：「目前：歌詞提早 1.2 秒」（沒有偏移時改顯示操作提示）、粗調開關、重設（有偏移才出現）、收合。
/// - 第二列：「歌詞太晚 → 提早」「歌詞太早 → 延後」兩顆大按鈕。預設每次 0.1 秒；
///   按住 Option／Shift 點按或開啟「粗調」為 0.5 秒；按住不放連續調整。
/// - 在卡片上滾動滾輪（觸控板亦可）：每格 0.1 秒，向下捲＝提早、向上捲＝延後。
public struct OffsetControlView: View {
    /// 卡片高度（歌詞面板展開時依它預留空間）。
    public static let cardHeight: CGFloat = 50

    public var offsetMs: Int
    /// 以毫秒為單位的增減量（細調 ±100、粗調 ±500；正值＝提早）。
    public var onAdjust: (Int) -> Void
    public var onReset: () -> Void
    public var onClose: () -> Void
    public var onPointerInside: (Bool) -> Void
    public var strings: OffsetControlStrings

    @State private var coarse: Bool

    public init(
        offsetMs: Int,
        strings: OffsetControlStrings = .zhHant,
        coarse: Bool = false,
        onAdjust: @escaping (Int) -> Void,
        onReset: @escaping () -> Void,
        onClose: @escaping () -> Void = {},
        onPointerInside: @escaping (Bool) -> Void = { _ in }
    ) {
        self.offsetMs = offsetMs
        self.strings = strings
        self.onAdjust = onAdjust
        self.onReset = onReset
        self.onClose = onClose
        self.onPointerInside = onPointerInside
        _coarse = State(initialValue: coarse)
    }

    public var body: some View {
        VStack(spacing: 3) {
            statusRow
            nudgeRow
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .frame(height: Self.cardHeight)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.92))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
        )
        .modifier(OffsetWheelModifier(onDelta: onAdjust, onPointerInside: onPointerInside))
    }

    // MARK: 第一列

    private var statusRow: some View {
        HStack(spacing: 4) {
            Text(verbatim: offsetMs == 0 ? strings.idleHint : strings.status(offsetMs: offsetMs))
                .font(.system(size: 9.5, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(offsetMs == 0 ? Color.white.opacity(0.6) : Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(Text(verbatim: "\(strings.currentOffset) \(strings.status(offsetMs: offsetMs))"))
            chip(strings.coarse, help: strings.coarseHelp, isOn: coarse) { coarse.toggle() }
            if offsetMs != 0 {
                chip(strings.reset, help: strings.resetHelp, isEmphasized: true) { onReset() }
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(strings.closeHelp)
            .accessibilityLabel(strings.closeHelp)
        }
        .frame(height: 16)
    }

    private func chip(
        _ title: String, help: String, isOn: Bool = false, isEmphasized: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(isOn ? Color.black : Color.white.opacity(isEmphasized ? 1 : 0.8))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(isOn ? Color.white.opacity(0.9) : Color.white.opacity(isEmphasized ? 0.28 : 0.14)))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: 第二列

    private var nudgeRow: some View {
        HStack(spacing: 4) {
            nudgeButton(.advance, caption: strings.advanceCaption, title: strings.advanceTitle, help: strings.advanceHelp)
            nudgeButton(.delay, caption: strings.delayCaption, title: strings.delayTitle, help: strings.delayHelp)
        }
    }

    private func nudgeButton(_ nudge: OffsetNudge, caption: String, title: String, help: String) -> some View {
        let step = coarse ? LyricsOffsetFormat.coarseStepMs : LyricsOffsetFormat.fineStepMs
        return HoldRepeatButton(
            action: {
                // 修飾鍵在「這一下」才讀：Option／Shift 暫時粗調。
                let flags = NSEvent.modifierFlags
                let useCoarse = coarse || flags.contains(.option) || flags.contains(.shift)
                onAdjust(nudge.deltaMs(coarse: useCoarse))
            }
        ) { isPressed in
            VStack(spacing: 0) {
                Text(verbatim: caption)
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.55))
                HStack(spacing: 3) {
                    if nudge == .advance { Image(systemName: "chevron.left").font(.system(size: 8, weight: .bold)) }
                    Text(verbatim: title).font(.system(size: 11, weight: .semibold, design: .rounded))
                    Text(verbatim: LyricsOffsetFormat.seconds(abs: step))
                        .font(.system(size: 8.5, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.55))
                    if nudge == .delay { Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)) }
                }
                .foregroundStyle(Color.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(isPressed ? 0.30 : 0.14)))
        }
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - 按住連發的按鈕

/// 按下立刻觸發一次；按住超過 `initialDelay` 後每 `interval` 秒再觸發一次，放開即停。
/// 用 `DragGesture(minimumDistance: 0)` 偵測按下／放開（與播放進度條同一種做法，不會被外層的拖曳手勢搶走）。
struct HoldRepeatButton<Label: View>: View {
    static var initialDelay: Duration { .milliseconds(450) }
    static var interval: Duration { .milliseconds(100) }

    var action: () -> Void
    @ViewBuilder var label: (_ isPressed: Bool) -> Label

    @State private var repeatTask: Task<Void, Never>?
    @State private var isPressed = false

    var body: some View {
        label(isPressed)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard repeatTask == nil else { return }
                        isPressed = true
                        action()
                        repeatTask = Task { @MainActor in
                            try? await Task.sleep(for: Self.initialDelay)
                            while !Task.isCancelled {
                                action()
                                try? await Task.sleep(for: Self.interval)
                            }
                        }
                    }
                    .onEnded { _ in stop() }
            )
            .onDisappear { stop() }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }

    private func stop() {
        repeatTask?.cancel()
        repeatTask = nil
        isPressed = false
    }
}

// MARK: - 滾輪

/// 在視圖範圍內接收滾輪／觸控板捲動並換算成偏移變化量；同時回報滑鼠是否在範圍內。
///
/// 為什麼要回報「滑鼠在範圍內」：瀏海外層有「上滑關閉」的捲動手勢監聽，滾輪往上捲會被當成關閉。
/// App 端在 `onPointerInside(true)` 期間暫停那個手勢，滾輪才能專心調整偏移。
struct OffsetWheelModifier: ViewModifier {
    var onDelta: (Int) -> Void
    var onPointerInside: (Bool) -> Void

    func body(content: Content) -> some View {
        content
            .background(OffsetWheelCatcher(onDelta: onDelta))
            .onHover { onPointerInside($0) }
            .onDisappear { onPointerInside(false) }
    }
}

private struct OffsetWheelCatcher: NSViewRepresentable {
    var onDelta: (Int) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(on: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onDelta = onDelta
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.remove() }

    func makeCoordinator() -> Coordinator { Coordinator(onDelta: onDelta) }

    @MainActor final class Coordinator {
        var onDelta: (Int) -> Void
        private var monitor: Any?
        private var accumulator = OffsetWheelAccumulator()

        init(onDelta: @escaping (Int) -> Void) { self.onDelta = onDelta }

        func install(on view: NSView) {
            remove()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self, weak view] event in
                guard let self, let view, let window = view.window, event.window === window else { return event }
                let point = view.convert(event.locationInWindow, from: nil)
                guard view.bounds.contains(point) else { return event }
                if event.phase == .began || event.phase == .mayBegin { self.accumulator.reset() }
                let delta = self.accumulator.consume(
                    deltaY: Double(event.scrollingDeltaY),
                    isPrecise: event.hasPreciseScrollingDeltas,
                    isMomentum: !event.momentumPhase.isEmpty
                )
                if delta != 0 { self.onDelta(delta) }
                return event
            }
        }

        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}

// MARK: - 常駐的小按鈕

/// 歌詞面板角落常駐的低調小按鈕：沒有偏移顯示「對時」，有偏移顯示「提早 1.2 秒」。點一下展開對時控制。
/// 在上面滾動滾輪也能直接微調。
public struct OffsetBadgeButton: View {
    public var offsetMs: Int
    public var strings: OffsetControlStrings
    /// 面板被滑鼠指著時更醒目；平常很淡。
    public var isProminent: Bool
    public var onTap: () -> Void
    public var onAdjust: (Int) -> Void
    public var onPointerInside: (Bool) -> Void

    public init(
        offsetMs: Int,
        strings: OffsetControlStrings = .zhHant,
        isProminent: Bool = false,
        onTap: @escaping () -> Void,
        onAdjust: @escaping (Int) -> Void = { _ in },
        onPointerInside: @escaping (Bool) -> Void = { _ in }
    ) {
        self.offsetMs = offsetMs
        self.strings = strings
        self.isProminent = isProminent
        self.onTap = onTap
        self.onAdjust = onAdjust
        self.onPointerInside = onPointerInside
    }

    public var body: some View {
        let hasOffset = offsetMs != 0
        Button(action: onTap) {
            HStack(spacing: 3) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 8.5, weight: .semibold))
                Text(verbatim: strings.badge(offsetMs: offsetMs))
                    .font(.system(size: 9.5, weight: .medium, design: .rounded).monospacedDigit())
            }
            .foregroundStyle(Color.white.opacity(hasOffset ? 0.95 : (isProminent ? 0.8 : 0.45)))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(hasOffset ? 0.2 : (isProminent ? 0.14 : 0.07))))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(strings.badgeHelp)
        .accessibilityLabel(Text(verbatim: "\(strings.badgeIdle)，\(strings.status(offsetMs: offsetMs))"))
        .modifier(OffsetWheelModifier(onDelta: onAdjust, onPointerInside: onPointerInside))
    }
}

// MARK: - 回饋

/// 點歌詞對齊後的短暫回饋。
public struct LyricsSyncToast: View {
    public var text: String
    public init(text: String) { self.text = text }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 9, weight: .semibold))
            Text(verbatim: text).font(.system(size: 10, weight: .medium, design: .rounded))
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.black.opacity(0.88)).overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)))
        .accessibilityElement(children: .combine)
    }
}
