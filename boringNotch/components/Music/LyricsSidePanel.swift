//
//  LyricsSidePanel.swift
//  DavidNook
//
//  展開的 Now Playing 首頁右側的歌詞面板：把 LyricsService（狀態、顯示行、偏移）與 MusicManager 的播放時鐘
//  接到 DavidNookUI 的資料驅動元件。這裡只做接線；時間軸、簡繁轉換、網路都在 DavidNookCore。
//

import DavidNookCore
import DavidNookUI
import Defaults
import SwiftUI

struct LyricsSidePanel: View {
    @ObservedObject private var service = LyricsService.shared
    @ObservedObject private var musicManager = MusicManager.shared
    /// 對時控制是否展開（點右下角的「對時」小按鈕）。換歌或歌詞消失時自動收合。
    @State private var isSyncOpen = false
    /// 點歌詞對齊後的短暫回饋文字。
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    /// 滑鼠離開面板一小段時間後自動收合對時控制。
    @State private var collapseTask: Task<Void, Never>?
    /// 瀏海正在變形（展開／收合／切分頁）：降低歌詞時間軸的更新頻率，把算力留給形體動畫。
    @Environment(\.notchIsMorphing) private var isMorphing
    /// 可見行數：預設 5 行；展開面板高度不足時由 `NotchHomeMetrics` 降為 4 行。
    var visibleLineCount: Int = LyricsPanelMetrics.defaultVisibleLines

    private let strings = LyricsPanelStrings(
        loading: String(localized: "Loading lyrics…", comment: "Lyrics panel: shown while lyrics are being looked up."),
        noLyrics: String(localized: "No lyrics for this song", comment: "Lyrics panel: no synced lyrics were found."),
        instrumental: String(localized: "Instrumental", comment: "Lyrics panel: the track is instrumental."),
        error: String(localized: "Couldn't get lyrics", comment: "Lyrics panel: the lookup failed (network or server error).")
    )

    private let offsetStrings = OffsetControlStrings(
        badgeIdle: String(localized: "Sync", comment: "Lyrics panel: small always-visible button that opens the lyrics timing controls."),
        advancedBadge: { String(localized: "\($0) s early", comment: "Lyrics panel: the badge when this song's lyrics are shown earlier. Placeholder is the seconds, e.g. 1.2.") },
        delayedBadge: { String(localized: "\($0) s late", comment: "Lyrics panel: the badge when this song's lyrics are shown later. Placeholder is the seconds, e.g. 0.4.") },
        badgeHelp: String(localized: "Adjust lyrics timing. Click to open the controls. Double-click the line being sung to sync to it. Scroll here to nudge by 0.1 s.", comment: "Tooltip of the small Sync button in the lyrics panel."),
        noOffsetStatus: String(localized: "Now: no offset", comment: "Lyrics timing controls: status line when the lyrics are not shifted."),
        advancedStatus: { String(localized: "Now: lyrics \($0) s early", comment: "Lyrics timing controls: status line when lyrics are shown earlier. Placeholder is the seconds, e.g. 1.2.") },
        delayedStatus: { String(localized: "Now: lyrics \($0) s late", comment: "Lyrics timing controls: status line when lyrics are shown later. Placeholder is the seconds, e.g. 0.4.") },
        idleHint: String(localized: "Click the line being sung to sync", comment: "Lyrics timing controls: hint shown while there is no offset. Fits one short line."),
        closeHelp: String(localized: "Close sync controls", comment: "Tooltip of the button that collapses the lyrics timing controls."),
        advanceCaption: String(localized: "Lyrics too late", comment: "Lyrics timing controls: small caption above the Earlier button (the lyrics show up after the singing)."),
        advanceTitle: String(localized: "Show earlier", comment: "Lyrics timing controls: button that shows the lyrics earlier."),
        advanceHelp: String(localized: "Lyrics show up after the singing? Show them earlier. Hold Option or Shift for 0.5 s steps; hold the button to repeat; scrolling down also shows them earlier.", comment: "Tooltip of the Earlier button."),
        delayCaption: String(localized: "Lyrics too early", comment: "Lyrics timing controls: small caption above the Later button (the lyrics show up before the singing)."),
        delayTitle: String(localized: "Show later", comment: "Lyrics timing controls: button that shows the lyrics later."),
        delayHelp: String(localized: "Lyrics show up before the singing? Show them later. Hold Option or Shift for 0.5 s steps; hold the button to repeat; scrolling up also shows them later.", comment: "Tooltip of the Later button."),
        coarse: String(localized: "Coarse", comment: "Lyrics timing controls: toggle that makes each step 0.5 s instead of 0.1 s."),
        coarseHelp: String(localized: "Each step is 0.5 s instead of 0.1 s", comment: "Tooltip of the Coarse toggle."),
        reset: String(localized: "Reset", comment: "Button that resets the per-track lyrics offset to zero."),
        resetHelp: String(localized: "Reset lyrics offset", comment: "Tooltip of the reset lyrics offset button."),
        aligned: String(localized: "Synced. Remembered for this song", comment: "Toast shown after the user clicked a lyric line to sync the timing."),
        alignedLimit: String(localized: "Offset limit reached (±60 s)", comment: "Toast shown when syncing to a lyric line would need more than ±60 seconds of offset."),
        lineHelp: String(localized: "Click this line to sync it to the current playback position", comment: "Tooltip of a lyric line while the timing controls are open."),
        currentOffset: String(localized: "Current offset", comment: "Accessibility label prefix for the current lyrics offset.")
    )

    var body: some View {
        content
            .contentShape(Rectangle())
            .onHover { hovering in
                // 對時控制展開後，滑鼠離開面板 2 秒才自動收合（中途回來就取消）。
                collapseTask?.cancel()
                guard !hovering, isSyncOpen else { return }
                collapseTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    withAnimation(.smooth(duration: 0.25)) { isSyncOpen = false }
                }
            }
            .onChange(of: service.status) { _, status in
                if status != .loaded, isSyncOpen { isSyncOpen = false }
            }
            .onDisappear {
                collapseTask?.cancel()
                toastTask?.cancel()
                LyricsSyncPointer.isOverControl = false
            }
    }

    private var syncConfiguration: LyricsSyncConfiguration? {
        guard service.status == .loaded else { return nil }
        return LyricsSyncConfiguration(
            strings: offsetStrings,
            isOpen: isSyncOpen,
            toast: toast,
            onToggle: { withAnimation(.smooth(duration: 0.25)) { isSyncOpen.toggle() } },
            onAdjust: { service.adjustOffset(byMs: $0) },
            onReset: { service.resetOffset() },
            onAlignLine: { alignLine($0) },
            onPointerInside: { LyricsSyncPointer.isOverControl = $0 }
        )
    }

    /// 點歌詞對齊：用「點擊這一刻」的播放位置，把被點的行對齊到現在，並顯示回饋。
    private func alignLine(_ index: Int) {
        let position = musicManager.estimatedPlaybackPosition(at: Date())
        guard let result = service.alignOffset(toLine: index, atPosition: position) else { return }
        showToast(offsetStrings.alignedToast(isClamped: result.isClamped))
    }

    private func showToast(_ text: String) {
        toastTask?.cancel()
        withAnimation(.smooth(duration: 0.2)) { toast = text }
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.3)) { toast = nil }
        }
    }

    @ViewBuilder
    private var content: some View {
        if service.status == .idle {
            Color.clear
        } else {
            // 10 Hz 重新取目前行（瀏海變形期間降為 2 Hz，約半秒內最多差一行）；暫停時停止更新。
            // 位置來自 PlaybackClock（elapsed + (now − timestamp) × rate）。
            TimelineView(.animation(minimumInterval: isMorphing ? 0.5 : 0.1, paused: !musicManager.isPlaying)) { context in
                let position = musicManager.estimatedPlaybackPosition(at: context.date)
                LyricsPanelView(
                    lines: LyricsPanelLine.make(from: service.lines),
                    currentIndex: service.currentIndex(at: position),
                    offsetMs: service.offsetMs,
                    status: panelStatus,
                    strings: strings,
                    visibleLineCount: visibleLineCount,
                    sync: syncConfiguration
                )
            }
        }
    }

    private var panelStatus: LyricsPanelStatus {
        switch service.status {
        case .idle, .loading: .loading
        case .loaded: .loaded
        case .notFound: .noLyrics
        case .error: .error
        }
    }
}

/// 滑鼠是否正指著歌詞面板的對時控制。
///
/// 瀏海外層（ContentView）有「上滑關閉」的捲動手勢監聽；對時控制支援滾輪微調，滾輪往上捲不能同時把瀏海關掉。
/// 對時控制在滑鼠進出時設定這個旗標，ContentView 的手勢處理在它為 true 時略過新的捲動。
@MainActor
enum LyricsSyncPointer {
    static var isOverControl = false
}

/// 歌名旁的小按鈕：切換歌詞面板的顯示。
struct LyricsToggleButton: View {
    @Binding var isShowing: Bool

    var body: some View {
        Button {
            withAnimation(.smooth(duration: 0.25)) { isShowing.toggle() }
        } label: {
            Image(systemName: "text.quote")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isShowing ? Color.white : Color.gray)
                .frame(width: 20, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(isShowing ? 0.16 : 0.06))
                )
        }
        .buttonStyle(.plain)
        .help(isShowing ? String(localized: "Hide lyrics") : String(localized: "Show lyrics"))
        .accessibilityLabel(isShowing ? String(localized: "Hide lyrics") : String(localized: "Show lyrics"))
    }
}

// MARK: - 收合瀏海下方的歌詞膠囊

/// 收合瀏海下方的歌詞膠囊（一句一句跑馬燈）：由 ContentView 放在瀏海正下方，位置＝瀏海底緣＋「下拉距離」。
///
/// - 資料沿用 `LyricsService`（目前行、偏移、簡轉繁）與 `MusicManager` 的播放時鐘；不新增網路請求、不寫 log。
/// - 可見性走 Core 的 `LyricsPillVisibility`（收合＋播放中＋歌詞已載入＋當前句非空＋功能開啟；暫停延遲 1.5 秒才收起）。
/// - 效能：10 Hz 的 `TimelineView` 只在「功能開啟＋收合＋播放中＋歌詞已載入」時跑；其餘時間暫停（零逐幀成本）。
///   逐幀（`.animation`）更新只發生在 `LyricsPillView` 內「這一句放不下、正在捲動」的那幾秒。
/// - 互動：膠囊本身不接收點擊（`allowsHitTesting(false)`）；膠囊可見時，另放一塊與膠囊同寬同高的透明區域，
///   hover 與點擊轉接給瀏海的 `handleHover` 與開啟動作，所以滑鼠移到膠囊上等同移到瀏海。
struct LyricsPillHost: View {
    /// 瀏海目前是收合狀態，且沒有被隱藏／歡迎動畫／提示佔用。
    var isNotchClosed: Bool
    /// 瀏海底緣離視窗上緣的距離（pt）。
    var notchBottom: CGFloat
    var onHover: (Bool) -> Void
    var onTap: () -> Void
    /// 膠囊實際可見（含淡出前）時回報給 ContentView，讓影片膠囊知道要不要讓位（垂直堆疊）。
    var onVisibleChange: (Bool) -> Void = { _ in }

    @ObservedObject private var service = LyricsService.shared
    @ObservedObject private var musicManager = MusicManager.shared
    @Default(.enableLyrics) private var enableLyrics
    @Default(.lyricsPillEnabled) private var pillEnabled
    @Default(.lyricsPillDropDistance) private var dropDistance
    @Default(.lyricsPillMaxWidth) private var maxWidth
    @Default(.lyricsPillFontSize) private var fontSize
    @Default(.lyricsPillSpeed) private var speed

    @State private var visibility = LyricsPillVisibility()
    @State private var graceTask: Task<Void, Never>?
    @State private var heldText = ""

    private var style: LyricsPillStyle {
        LyricsPillStyle(
            fontSize: CGFloat(fontSize), maxWidth: CGFloat(maxWidth), speedMultiplier: speed,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
    }

    var body: some View {
        let enabled = enableLyrics && pillEnabled
        let eligible = enabled && isNotchClosed && service.status == .loaded
        let style = style
        let width = heldText.isEmpty ? 0 : LyricsPillSizing.pillWidth(text: heldText, style: style)
        ZStack(alignment: .top) {
            TimelineView(.animation(minimumInterval: 0.1, paused: !(eligible && musicManager.isPlaying))) { context in
                let sample = eligible ? service.pillSample(at: musicManager.estimatedPlaybackPosition(at: context.date)) : nil
                LyricsPillGate(
                    input: LyricsPillVisibility.Input(
                        isEnabled: enabled, isNotchClosed: isNotchClosed, isPlaying: musicManager.isPlaying,
                        hasLyrics: service.status == .loaded, hasCurrentText: sample != nil
                    ),
                    heldText: sample?.line.text,
                    apply: apply
                ) {
                    LyricsPillView(
                        sample: sample, isVisible: visibility.isVisible, isTicking: eligible && musicManager.isPlaying,
                        style: style, motion: NotchMotion.current,
                        positionAt: { musicManager.estimatedPlaybackPosition(at: $0) }
                    )
                }
            }
            .frame(width: CGFloat(maxWidth), height: LyricsPillMetrics.height)

            if visibility.isVisible, isNotchClosed, width > 0 {
                Color.clear
                    .frame(width: width, height: LyricsPillMetrics.height)
                    .contentShape(Rectangle())
                    .onHover { onHover($0) }
                    .onTapGesture { onTap() }
            }
        }
        .frame(width: CGFloat(maxWidth), height: LyricsPillMetrics.height, alignment: .top)
        .offset(y: LyricsPillMetrics.topOffset(notchBottom: notchBottom, dropDistance: CGFloat(dropDistance)))
        .onChange(of: visibility.isVisible) { _, visible in onVisibleChange(visible) }
    }

    private func apply(_ input: LyricsPillVisibility.Input, text: String?) {
        if let text { heldText = text }
        let now = Date.timeIntervalSinceReferenceDate
        visibility.update(input, at: now)
        graceTask?.cancel()
        graceTask = nil
        if let deadline = visibility.hideDeadline {
            graceTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(max(deadline - Date.timeIntervalSinceReferenceDate, 0)))
                guard !Task.isCancelled else { return }
                visibility.tick(at: Date.timeIntervalSinceReferenceDate)
            }
        }
    }
}

/// 把「輸入變了」從 TimelineView 的內容閉包轉成狀態更新（body 裡不能直接改 @State）。
private struct LyricsPillGate<Content: View>: View {
    var input: LyricsPillVisibility.Input
    var heldText: String?
    var apply: (LyricsPillVisibility.Input, String?) -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .onChange(of: input, initial: true) { _, new in apply(new, heldText) }
            .onChange(of: heldText) { _, new in if let new { apply(input, new) } }
    }
}
