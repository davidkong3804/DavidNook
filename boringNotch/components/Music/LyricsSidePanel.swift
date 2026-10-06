//
//  LyricsSidePanel.swift
//  DavidNook
//
//  展開的 Now Playing 首頁右側的歌詞面板：把 LyricsService（狀態、顯示行、偏移）與 MusicManager 的播放時鐘
//  接到 DavidNookUI 的資料驅動元件。這裡只做接線；時間軸、簡繁轉換、網路都在 DavidNookCore。
//

import DavidNookCore
import DavidNookUI
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
