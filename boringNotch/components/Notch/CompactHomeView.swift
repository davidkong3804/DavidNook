//
//  CompactHomeView.swift
//  boringNotch
//
//  A smaller open-notch layout: just the now-playing essentials — art,
//  title, scrubber, transport — with no tab bar or calendar.
//
//  Layout and proportions follow Atoll's MinimalisticMusicPlayerView
//  (https://github.com/Ebullioscopic/Atoll, GPL-3.0, itself a boring.notch
//  fork): 50pt album art, 12/10pt title and artist, a fixed-width
//  visualizer block on the right sized to match the trailing time label so
//  the bars centre over it, a progress row, and a transport row.
//
//  Transport and slider are deliberately shared with the standard layout
//  (MusicControlSlotButton / MusicSliderView) rather than ported separately,
//  so seeking and the buttons behave identically in both layouts instead of
//  drifting apart. The transport row is a fixed five here rather than the
//  musicControlSlots preference — that preference exists to configure the
//  full layout.
//

import Defaults
import SwiftUI

struct CompactHomeView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var musicManager = MusicManager.shared
    let albumArtNamespace: Namespace.ID
    let horizontalMediaGestureFeedback: CGFloat

    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast

    @Default(.coloredSpectrogram) private var coloredSpectrogram
    @Default(.musicControlSlots) private var slotConfig
    @Default(.musicControlSlotLimit) private var slotLimit
    @Default(.playerColorTinting) private var playerColorTinting
    @Default(.showRemainingTime) private var showRemainingTime

    private let albumArtWidth: CGFloat = 45
    private let headerSpacing: CGFloat = 10
    /// Matches the trailing time label's width in the row below, so the
    /// visualizer's bars sit centred over "-0:00" rather than drifting.
    private let vizBlockWidth: CGFloat = 42
    private let vizBarWidth: CGFloat = 24

    // No idle branch, deliberately. The standard layout has none either —
    // it renders whatever MusicManager last cached, so a paused or stopped
    // track keeps its art, title and scrub position. A "Nothing Playing"
    // placeholder here made compact mode lose state the full layout keeps.
    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: albumArtWidth)

            progressRow
                .padding(.top, 6)

            transport
                .padding(.top, 2)
        }
        .padding(.horizontal, 12)
        // Atoll's 15/3 formula assumes the player is the whole panel; here
        // a notch-clearance spacer sits above it, so these are trimmed to
        // land the panel at the intended overall height. The 2pt bottom pad
        // keeps the play/pause's hover fill from kissing the rounded corner
        // without adding a visible band of empty space.
        .padding(.top, 4)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity)
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Header

    private var header: some View {
        GeometryReader { geo in
            let textWidth = max(
                0,
                geo.size.width - albumArtWidth - headerSpacing - (vizBlockWidth + headerSpacing)
            )

            HStack(alignment: .center, spacing: headerSpacing) {
                compactAlbumArt

                VStack(alignment: .leading, spacing: 1) {
                    MarqueeText(
                        musicManager.songTitle,
                        font: .system(size: 12, weight: .semibold),
                        color: .white,
                        frameWidth: textWidth
                    )

                    Text(musicManager.artistName)
                        .font(.system(size: 10))
                        .foregroundStyle(
                            playerColorTinting
                                ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6)
                                : .gray
                        )
                        .lineLimit(1)
                }
                .frame(width: textWidth, alignment: .leading)

                ZStack {
                    MusicVisualizer(
                        isPlaying: musicManager.isPlaying,
                        tintColor: coloredSpectrogram
                            ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6)
                            : .gray
                    )
                    .frame(width: vizBarWidth, height: 16)
                }
                .frame(width: vizBlockWidth)
            }
        }
    }

    // MARK: - Progress

    private var progressRow: some View {
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
                onValueChange: { MusicManager.shared.seek(to: $0) },
                trailingLabel: showRemainingTime ? .remaining : .duration
            )
            .padding(.top, 5)
            .frame(height: 36)
        }
        .onAppear { sliderValue = musicManager.elapsedTime }
    }

    // MARK: - Transport

    /// The user's configured control slots, clamped like the standard
    /// layout's activeSlots, rendered through the same MusicControlSlotButton
    /// — so sizing, glyphs and the swipe-to-skip bounce match exactly.
    private var displayedSlots: [MusicControlButton] {
        let sanitizedLimit = min(
            max(slotLimit, MusicControlButton.minSlotCount),
            MusicControlButton.maxSlotCount
        )
        return slotConfig
            .padded(to: sanitizedLimit, filler: .none)
            .prefix(sanitizedLimit)
            .map { $0 }
    }

    private var transport: some View {
        HStack(spacing: 6) {
            ForEach(Array(displayedSlots.enumerated()), id: \.offset) { _, slot in
                MusicControlSlotButton(
                    slot: slot,
                    horizontalMediaGestureFeedback: horizontalMediaGestureFeedback
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var compactAlbumArt: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(nsImage: musicManager.albumArt)
                .resizable().scaledToFill()
                .frame(width: albumArtWidth, height: albumArtWidth)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            // Badge scaled to this art. AlbumArtView's is a fixed 30pt with
            // a +10/+10 offset, sized for the 120pt art in the full layout —
            // on 50pt art it spills outside the corner.
            if !musicManager.usingAppIconForArtwork {
                appIcon(for: musicManager.bundleIdentifier ?? MediaAppBundleID.appleMusic)
                    .resizable().scaledToFit()
                    .frame(width: 18, height: 18)
                    .offset(x: 5, y: 5)
            }
        }
        .frame(width: albumArtWidth, height: albumArtWidth)
    }
}
