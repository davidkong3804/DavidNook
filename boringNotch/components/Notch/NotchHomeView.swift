//
//  NotchHomeView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-18.
//  Modified by Harsh Vardhan Goswami & Richard Kunkli & Mustafa Ramadan
//

import Combine
import DavidNookCore
import DavidNookUI
import Defaults
import SwiftUI

// MARK: - Music Player Components

struct MusicPlayerView: View {
    @EnvironmentObject var vm: BoringViewModel
    let albumArtNamespace: Namespace.ID
    let horizontalMediaGestureFeedback: CGFloat
    @Binding var isHoveringMusicArea: Bool
    /// 內容區尺寸（由 ContentView 依 NotchSizing 給定）；封面、控制區、歌詞的寬高全部由 `NotchHomeMetrics` 決定。
    let contentWidth: CGFloat
    let bodyHeight: CGFloat
    @Default(.enableLyrics) private var enableLyrics
    @Default(.showLyricsPanel) private var showLyricsPanel
    @Default(.videoCapsuleEnabled) private var videoEnabled
    @Default(.videoCapsuleWidth) private var videoWidth
    @ObservedObject private var video = VideoCapsuleController.shared

    /// 封面槽在串流中（或顯示影片說明）時加寬；寬度不超過版面容許與設定頁的影片寬度，也不擠壞控制區與歌詞（見 NotchHomeMetrics）。
    private var metrics: NotchHomeMetrics {
        NotchHomeMetrics(
            contentWidth: contentWidth,
            bodyHeight: bodyHeight,
            showsLyrics: enableLyrics && showLyricsPanel,
            artAspectRatio: videoEnabled ? video.state.slotAspectRatio : nil,
            videoMaximumWidth: videoWidth
        )
    }

    var body: some View {
        let metrics = metrics
        NotchHomeLayout(metrics: metrics) {
            AlbumArtView(vm: vm, albumArtNamespace: albumArtNamespace)
        } controls: {
            MusicControlsView(metrics: metrics, horizontalMediaGestureFeedback: horizontalMediaGestureFeedback)
                .compositingGroup()
        } lyrics: {
            LyricsSidePanel(visibleLineCount: metrics.lyricsVisibleLines)
        }
        // 沿用分頁切換的彈簧（response 0.38、dampingRatio 0.82）讓封面槽加寬／恢復；只改槽內版面，不碰視窗大小。
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: metrics.artWidth)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHoveringMusicArea = hovering
        }
        .onDisappear {
            isHoveringMusicArea = false
        }
    }
}

struct AlbumArtView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var vm: BoringViewModel
    let albumArtNamespace: Namespace.ID

    var body: some View {
        VideoArtSlotHost {
            ZStack(alignment: .bottomTrailing) {
                if Defaults[.lightingEffect] {
                    albumArtBackground
                }
                albumArtButton
            }
        }
    }

    private var albumArtBackground: some View {
        Image(nsImage: musicManager.albumArt)
            .resizable().scaledToFit()
            .clipShape(
                RoundedRectangle(
                    cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.opened)
            )
            .scaleEffect(x: 1.3, y: 1.4)
            .rotationEffect(.degrees(92))
            .blur(radius: 40)
            .opacity(musicManager.isPlaying ? 0.5 : 0)
    }

    private var albumArtButton: some View {
        ZStack {
            Button {
                musicManager.openMusicApp()
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    albumArtImage
                    appIconOverlay
                }
            }
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(musicManager.isPlaying ? 1 : 0.85)

            albumArtDarkOverlay
        }
    }

    private var albumArtDarkOverlay: some View {
        Rectangle()
            .foregroundColor(Color.black)
            .opacity(musicManager.isPlaying ? 0 : 0.8)
            .blur(radius: 50)
            .allowsHitTesting(false)
    }

    private var albumArtImage: some View {
        Image(nsImage: musicManager.albumArt)
            .interpolation(.high)
            .resizable().scaledToFit()
            .clipShape(
                RoundedRectangle(
                    cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.opened)
            )
            .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
    }

    @ViewBuilder
    private var appIconOverlay: some View {
        if vm.notchState == .open && !musicManager.usingAppIconForArtwork {
            appIcon(for: musicManager.bundleIdentifier ?? MediaAppBundleID.appleMusic)
                .resizable().scaledToFit()
                .frame(width: 30, height: 30)
                .offset(x: 10, y: 10)
                .transition(.scale.combined(with: .opacity))
                .zIndex(2)
        }
    }
}

private enum VideoArtSlotText {
    static let strings = VideoArtSlotStrings(
        captureWindow: String(localized: "Show a window as live video", comment: "Album art slot: tooltip of the small button that opens the system window picker."),
        changeWindow: String(localized: "Change Window", comment: "Video tab: toolbar button to pick a different window."),
        stop: String(localized: "Stop", comment: "Video tab: toolbar button that stops showing the window."),
        pinHelp: String(localized: "Click to pin the video as a floating window", comment: "Album art slot: tooltip on the live video; clicking pins it as a free-floating window on the desktop."),
        unpinHelp: String(localized: "Click to unpin the video", comment: "Album art slot: tooltip on the live video while it is pinned."),
        backToCover: String(localized: "Back to cover", comment: "Album art slot: button that stops the video and shows the album cover again."),
        blackTitle: String(localized: "This source is content-protected", comment: "Video tab: shown over a black picture that looks like protected (DRM) content."),
        blackHint: String(localized: "The system does not allow capturing it. Try the source's own picture-in-picture, or an unprotected source such as YouTube", comment: "Album art slot: explains protected content and what to try instead."),
        closedTitle: String(localized: "The window was closed", comment: "Video tab: shown when the picked window no longer exists."),
        closedHint: String(localized: "Choose another window, or go back to the cover", comment: "Album art slot: hint when the picked window was closed."),
        permissionTitle: String(localized: "Screen recording permission needed", comment: "Video tab: shown when macOS does not allow capturing."),
        permissionHint: String(localized: "In System Settings → Privacy & Security → Screen & System Audio Recording, allow DavidNook, then reopen the app", comment: "Video tab: what to do about the missing permission."),
        openSettings: String(localized: "Open System Settings", comment: "Clipboard panel: button that opens System Settings."),
        errorTitle: String(localized: "Couldn't show the video", comment: "Video tab: title of a generic error."),
        pickerFailedHint: String(localized: "The system picker did not open. Please try again", comment: "Video tab: error hint when the system picker failed to open."),
        streamErrorHint: String(localized: "Capture was interrupted by the system. Choose the window again", comment: "Video tab: error hint when the system stopped the capture."),
        unknownErrorHint: String(localized: "Something unexpected happened. Choose the window again", comment: "Video tab: error hint for an unknown error."),
        chooseWindow: String(localized: "Choose Window", comment: "Video tab: button that opens the system window picker."),
        crop: String(localized: "Crop", comment: "Album art slot: tooltip of the button that opens the crop window to show only part of the picked window."),
        resetCrop: String(localized: "Reset crop", comment: "Album art slot: tooltip of the button that goes back to showing the whole window.")
    )
}

/// 封面槽：沒在擷取時是專輯封面（右上有低調的「擷取視窗」入口）；擷取中改顯示選定視窗的即時畫面。
/// 點一下影片＝釘選／取消釘選；hover 時才出現「換視窗」「停止」。畫面只在記憶體，不存檔、不上傳。
struct VideoArtSlotHost<Cover: View>: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var controller = VideoCapsuleController.shared
    @Default(.videoCapsuleEnabled) private var enabled
    @Default(.videoCapsulePinned) private var pinned
    @ViewBuilder let cover: () -> Cover

    var body: some View {
        if enabled {
            VideoArtSlotView(
                state: controller.state,
                isPinned: pinned,
                hasCrop: controller.crop != nil,
                strings: VideoArtSlotText.strings,
                display: controller.display,
                callbacks: VideoArtSlotCallbacks(
                    onChoose: { controller.choose() },
                    onStop: { controller.stop() },
                    onTogglePin: { controller.togglePin() },
                    onBackToCover: { controller.stop() },
                    onOpenSettings: { controller.openSystemSettings() },
                    onCrop: { controller.openCropEditor() },
                    onResetCrop: { controller.resetCrop() }
                ),
                cover: cover
            )
            .onAppear { controller.slotDidAppear() }
            .onDisappear {
                vm.isPopoverActive = false
                controller.slotDidDisappear()
            }
            // 系統挑選器開著時，滑鼠移到挑選器上不要讓瀏海自動收合。
            .onChange(of: controller.state) { _, newState in
                vm.isPopoverActive = (newState == .choosing)
            }
        } else {
            cover()
        }
    }
}

struct MusicControlsView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @EnvironmentObject var vm: BoringViewModel
    let metrics: NotchHomeMetrics
    let horizontalMediaGestureFeedback: CGFloat
    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast
    @Default(.musicControlSlots) private var slotConfig
    @Default(.musicControlSlotLimit) private var slotLimit
    @Default(.showRemainingTime) private var showRemainingTime
    @Default(.enableLyrics) private var enableLyrics
    @Default(.showLyricsPanel) private var showLyricsPanel

    var body: some View {
        // 三塊（歌名歌手／進度條／工具列）的高度與間距由 NotchHomeMetrics 的預算決定，
        // 最小尺寸下改用精簡密度（播放鈕 40→30、進度條 32→30），保證不重疊。
        NotchControlsLayout(metrics: metrics) {
            songInfo(width: max(metrics.controlsWidth - NotchHomeMetrics.controlsLeadingInset, 0))
        } slider: {
            musicSlider
        } toolbar: {
            slotToolbar
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func songInfo(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 歌名旁的按鈕：切換右側歌詞面板（只在歌詞功能開啟時出現）。
            HStack(spacing: 4) {
                MarqueeText(musicManager.songTitle, font: .headline, color: .white, frameWidth: enableLyrics ? max(width - 24, 0) : width)
                if enableLyrics {
                    LyricsToggleButton(isShowing: $showLyricsPanel)
                }
            }
            MarqueeText(
                musicManager.artistName,
                font: .headline,
                color: Defaults[.playerColorTinting]
                    ? Color(nsColor: musicManager.avgColor)
                        .ensureMinimumBrightness(factor: 0.6) : .gray,
                frameWidth: width
            )
            .fontWeight(.medium)
        }
    }

    private var musicSlider: some View {
        MusicPlaybackTimeline(playbackRate: musicManager.playbackRate) { date in
            MusicSliderView(
                sliderValue: $sliderValue,
                duration: $musicManager.songDuration,
                lastDragged: $lastDragged,
                color: musicManager.avgColor,
                dragging: $dragging,
                currentDate: date,
                timestampDate: musicManager.timestampDate,
                elapsedTime: musicManager.elapsedTime,
                playbackRate: musicManager.playbackRate,
                isPlaying: musicManager.isPlaying,
                onValueChange: { newValue in
                    MusicManager.shared.seek(to: newValue)
                },
                trailingLabel: showRemainingTime ? .remaining : .duration
            )
        }
    }

    private var slotToolbar: some View {
        let slots = activeSlots
        return HStack(spacing: 6) {
            ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                slotView(for: slot)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var activeSlots: [MusicControlButton] {
        let sanitizedLimit = min(
            max(slotLimit, MusicControlButton.minSlotCount),
            MusicControlButton.maxSlotCount
        )
        let padded = slotConfig.padded(to: sanitizedLimit, filler: .none)
        let result = Array(padded.prefix(sanitizedLimit))
        return result
    }

    private func slotView(for slot: MusicControlButton) -> some View {
        MusicControlSlotButton(
            slot: slot,
            horizontalMediaGestureFeedback: horizontalMediaGestureFeedback,
            compact: metrics.density == .compact
        )
    }
}

/// A single transport button, shared by the standard and compact layouts so
/// both render the exact same controls — sizing, glyphs, swipe-to-skip
/// bounce — and can't drift apart.
struct MusicControlSlotButton: View {
    @ObservedObject var musicManager = MusicManager.shared
    let slot: MusicControlButton
    let horizontalMediaGestureFeedback: CGFloat
    /// 精簡密度（最小尺寸）：播放鈕與其他按鈕同為 30pt，而不是 40pt。
    var compact: Bool = false

    var body: some View {
        Group {
            switch slot {
            case .shuffle:
                HoverButton(icon: "shuffle", iconColor: musicManager.isShuffled ? .red : .primary, scale: .medium) {
                    MusicManager.shared.toggleShuffle()
                }
            case .previous:
                HoverButton(icon: "backward.fill", scale: .medium) {
                    MusicManager.shared.previousTrack()
                }
                .scaleEffect(horizontalMediaGestureFeedback > 0 ? 1.12 : 1)
                .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.62), value: horizontalMediaGestureFeedback)
            case .playPause:
                HoverButton(icon: musicManager.isPlaying ? "pause.fill" : "play.fill", scale: compact ? .medium : .large) {
                    MusicManager.shared.togglePlay()
                }
            case .next:
                HoverButton(icon: "forward.fill", scale: .medium) {
                    MusicManager.shared.nextTrack()
                }
                .scaleEffect(horizontalMediaGestureFeedback < 0 ? 1.12 : 1)
                .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.62), value: horizontalMediaGestureFeedback)
            case .repeatMode:
                HoverButton(icon: repeatIcon, iconColor: repeatIconColor, scale: .medium) {
                    MusicManager.shared.toggleRepeat()
                }
            case .volume:
                VolumeControlView()
            case .favorite:
                FavoriteControlButton()
            case .goBackward:
                HoverButton(icon: "gobackward.15", scale: .medium) {
                    MusicManager.shared.skip(seconds: -15)
                }
            case .goForward:
                HoverButton(icon: "goforward.15", scale: .medium) {
                    MusicManager.shared.skip(seconds: 15)
                }
            case .none:
                Color.clear.frame(height: 1)
            }
        }
        .help(slot.actionLabel(isPlaying: musicManager.isPlaying, isFavorite: musicManager.isFavoriteTrack))
        .accessibilityLabel(slot.actionLabel(isPlaying: musicManager.isPlaying, isFavorite: musicManager.isFavoriteTrack))
        .accessibilityHidden(slot == .none)
    }

    private var repeatIcon: String {
        switch musicManager.repeatMode {
        case .off:
            return "repeat"
        case .all:
            return "repeat"
        case .one:
            return "repeat.1"
        }
    }

    private var repeatIconColor: Color {
        switch musicManager.repeatMode {
        case .off:
            return .primary
        case .all, .one:
            return .red
        }
    }
}

struct MusicPlaybackTimeline<Content: View>: View {
    let playbackRate: Double
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        TimelineView(.animation(minimumInterval: playbackRate > 0 ? musicPlaybackTickInterval : nil)) { context in
            content(context.date)
        }
    }
}

private let musicPlaybackTickInterval: TimeInterval = 0.2

struct FavoriteControlButton: View {
    @ObservedObject var musicManager = MusicManager.shared

    var body: some View {
        HoverButton(icon: iconName, iconColor: iconColor, scale: .medium) {
            MusicManager.shared.toggleFavoriteTrack()
        }
        .disabled(!musicManager.canFavoriteTrack)
        .opacity(musicManager.canFavoriteTrack ? 1 : 0.35)
    }

    private var iconName: String {
        musicManager.isFavoriteTrack ? "heart.fill" : "heart"
    }

    private var iconColor: Color {
        musicManager.isFavoriteTrack ? .red : .primary
    }
}

// Internal so the compact layout's slot row can share the padding rule.
extension Array where Element == MusicControlButton {
    func padded(to length: Int, filler: MusicControlButton) -> [MusicControlButton] {
        if count >= length { return self }
        return self + Array(repeating: filler, count: length - count)
    }
}

// MARK: - Volume Control View

struct VolumeControlView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @State private var volumeSliderValue: Double = 0.5
    @State private var dragging: Bool = false
    @State private var showVolumeSlider: Bool = false
    @State private var lastVolumeUpdateTime: Date = Date.distantPast
    private let volumeUpdateThrottle: TimeInterval = 0.1

    var body: some View {
        HStack(spacing: 4) {
            Button(action: {
                if musicManager.volumeControlSupported {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        showVolumeSlider.toggle()
                    }
                }
            }) {
                Image(systemName: volumeIcon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(musicManager.volumeControlSupported ? .white : .gray)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!musicManager.volumeControlSupported)
            .frame(width: 24)
            .help(MusicControlButton.volume.label)
            .accessibilityLabel(MusicControlButton.volume.label)

            if showVolumeSlider && musicManager.volumeControlSupported {
                CustomSlider(
                    value: $volumeSliderValue,
                    range: 0.0...1.0,
                    color: .white,
                    dragging: $dragging,
                    lastDragged: .constant(Date.distantPast),
                    onValueChange: { newValue in
                        MusicManager.shared.setVolume(to: newValue)
                    },
                    onDragChange: { newValue in
                        let now = Date()
                        if now.timeIntervalSince(lastVolumeUpdateTime) > volumeUpdateThrottle {
                            MusicManager.shared.setVolume(to: newValue)
                            lastVolumeUpdateTime = now
                        }
                    }
                )
                .frame(width: 48, height: 8)
                .accessibilityLabel(MusicControlButton.volume.label)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .clipped()
        .onReceive(musicManager.$volume) { volume in
            if !dragging {
                volumeSliderValue = volume
            }
        }
        .onReceive(musicManager.$volumeControlSupported) { supported in
            if !supported {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showVolumeSlider = false
                }
            }
        }
        .onChange(of: showVolumeSlider) { _, isShowing in
            if isShowing {
                // Sync volume from app when slider appears
                Task {
                    await MusicManager.shared.syncVolumeFromActiveApp()
                }
            }
        }
        .onDisappear {
            // volumeUpdateTask?.cancel() // No longer needed
        }
    }

    /// Level-reactive speaker waves (v2.7.3 behavior). The route-device
    /// glyphs (AirPods, headphones, …) that replaced these belong to the
    /// media-output button beside this slot — duplicating them here made
    /// volume and output indistinguishable and static while dragging.
    private var volumeIcon: String {
        if !musicManager.volumeControlSupported {
            return "speaker.slash"
        } else if volumeSliderValue == 0 {
            return "speaker.slash.fill"
        } else if volumeSliderValue < 0.33 {
            return "speaker.1.fill"
        } else if volumeSliderValue < 0.66 {
            return "speaker.2.fill"
        } else {
            return "speaker.3.fill"
        }
    }
}

// MARK: - Main View

struct NotchHomeView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    let albumArtNamespace: Namespace.ID
    let horizontalMediaGestureFeedback: CGFloat
    @Binding var isHoveringMusicArea: Bool
    let contentWidth: CGFloat
    let bodyHeight: CGFloat

    var body: some View {
        mainContent
            .transition(.opacity)
    }

    private var mainContent: some View {
        HStack(alignment: .top, spacing: 15) {
            MusicPlayerView(
                albumArtNamespace: albumArtNamespace,
                horizontalMediaGestureFeedback: horizontalMediaGestureFeedback,
                isHoveringMusicArea: $isHoveringMusicArea,
                contentWidth: contentWidth,
                bodyHeight: bodyHeight
            )

        }
        .transition(.opacity)
        .blur(radius: vm.notchState == .closed ? 30 : 0)
    }
}

struct MusicSliderView: View {
    @Binding var sliderValue: Double
    @Binding var duration: Double
    @Binding var lastDragged: Date
    var color: NSColor
    @Binding var dragging: Bool
    let currentDate: Date
    let timestampDate: Date
    let elapsedTime: Double
    let playbackRate: Double
    let isPlaying: Bool
    var onValueChange: (Double) -> Void

    // Ported from Atoll (GPL-3.0, itself a boring.notch fork) so the
    // trailing timestamp can count down instead of showing the duration.
    var trailingLabel: TrailingLabel = .duration

    enum TrailingLabel {
        case duration
        /// Counts down: "-2:56".
        case remaining
    }

    var body: some View {
        VStack {
            sliderCore
                .frame(height: sliderFrameHeight, alignment: .center)

            HStack {
                Text(timeString(from: sliderValue))
                Spacer()
                Text(trailingTimeText)
            }
            .fontWeight(.medium)
            .foregroundColor(timeLabelColor)
            .font(.caption)
        }
        .onChange(of: currentDate) {
           guard !dragging, timestampDate.timeIntervalSince(lastDragged) > -1 else { return }
            sliderValue = MusicManager.shared.estimatedPlaybackPosition(at: currentDate)
        }
    }

    private var sliderCore: some View {
        CustomSlider(
            value: $sliderValue,
            range: 0...duration,
            color: Defaults[.sliderColor] == SliderColorEnum.albumArt
                ? Color(nsColor: color).ensureMinimumBrightness(factor: 0.8)
                : Defaults[.sliderColor] == SliderColorEnum.accent ? .effectiveAccent : .white,
            dragging: $dragging,
            lastDragged: $lastDragged,
            onValueChange: onValueChange
        )
    }

    private var timeLabelColor: Color {
        Defaults[.playerColorTinting]
            ? Color(nsColor: color).ensureMinimumBrightness(factor: 0.6) : .gray
    }

    private var trailingTimeText: String {
        switch trailingLabel {
        case .duration:
            return timeString(from: duration)
        case .remaining:
            return "-" + timeString(from: max(duration - sliderValue, 0))
        }
    }

    private var sliderFrameHeight: CGFloat {
        10
    }

    func timeString(from seconds: Double) -> String {
        guard seconds.isFinite else { return "--:--" }
        let totalMinutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        } else {
            return String(format: "%d:%02d", minutes, remainingSeconds)
        }
    }
}

struct CustomSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var color: Color = .white
    @Binding var dragging: Bool
    @Binding var lastDragged: Date
    var onValueChange: ((Double) -> Void)?
    var onDragChange: ((Double) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = CGFloat(dragging ? 9 : 5)
            let rangeSpan = range.upperBound - range.lowerBound

            let progress = rangeSpan == .zero ? 0 : (value - range.lowerBound) / rangeSpan
            let filledTrackWidth = min(max(progress, 0), 1) * width

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.gray.opacity(0.3))
                    .frame(height: height)

                Rectangle()
                    .fill(color)
                    .frame(width: filledTrackWidth, height: height)
            }
            .cornerRadius(height / 2)
            .frame(height: 10)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        withAnimation {
                            dragging = true
                        }
                        let newValue = range.lowerBound + Double(gesture.location.x / width) * rangeSpan
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                        onDragChange?(value)
                    }
                    .onEnded { _ in
                        onValueChange?(value)
                        dragging = false
                        lastDragged = Date()
                    }
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: dragging)
        }
    }
}
