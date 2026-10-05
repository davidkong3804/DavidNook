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
    @State private var isHovering = false
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
        delayHelp: String(localized: "Delay lyrics by 0.5 s", comment: "Tooltip of the −0.5s lyrics offset button."),
        advanceHelp: String(localized: "Advance lyrics by 0.5 s", comment: "Tooltip of the +0.5s lyrics offset button."),
        reset: String(localized: "Reset", comment: "Button that resets the per-track lyrics offset to zero."),
        resetHelp: String(localized: "Reset lyrics offset", comment: "Tooltip of the reset lyrics offset button."),
        currentOffset: String(localized: "Current offset", comment: "Accessibility label prefix for the current lyrics offset.")
    )

    var body: some View {
        content
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) { isHovering = hovering }
            }
            .overlay(alignment: .bottom) {
                if isHovering && service.status == .loaded {
                    OffsetControlView(
                        offsetMs: service.offsetMs,
                        strings: offsetStrings,
                        onAdjust: { service.adjustOffset(steps: $0 / LyricsOffsetFormat.stepMs) },
                        onReset: { service.resetOffset() }
                    )
                    .padding(.bottom, 1)
                    .transition(.opacity)
                }
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
                    visibleLineCount: visibleLineCount
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
