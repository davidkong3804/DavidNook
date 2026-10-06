//
//  MediaSettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import DavidNookUI
import Defaults
import SwiftUI

struct MediaSettingsView: View {
    @Default(.waitInterval) var waitInterval
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.hideNotchOption) var hideNotchOption
    @Default(.enableSneakPeek) private var enableSneakPeek
    @Default(.sneakPeekStyles) var sneakPeekStyles
    @Default(.sliderColor) var sliderColor

    @Default(.enableLyrics) var enableLyrics
    @Default(.lyricsPillEnabled) var lyricsPillEnabled
    @Default(.lyricsPillDropDistance) var lyricsPillDropDistance
    @Default(.lyricsPillMaxWidth) var lyricsPillMaxWidth
    @Default(.lyricsPillFontSize) var lyricsPillFontSize
    @Default(.lyricsPillSpeed) var lyricsPillSpeed
    @State private var lyricsCacheCleared = false
    @ObservedObject private var musicManager = MusicManager.shared

    var body: some View {
        Form {
            Section {
                Picker("Music Source", selection: mediaControllerSelection) {
                    ForEach(MediaControllerType.allCases) { controller in
                        Text(controller.localizedResource)
                            .tag(controller)
                            .disabled(
                                controller == .nowPlaying
                                    && !musicManager.nowPlayingAvailability.isSelectable
                            )
                    }
                }
            } header: {
                Text("Media Source")
            } footer: {
                mediaSourceFooter
            }

            Section {
                Toggle(
                    "Show music live activity",
                    isOn: $coordinator.musicLiveActivityEnabled.animation()
                )
                Toggle("Show sneak peek on playback changes", isOn: $enableSneakPeek)
                Picker("Sneak Peek Style", selection: $sneakPeekStyles) {
                    ForEach(SneakPeekStyle.allCases) { style in
                        Text(style.localizedString).tag(style)
                    }
                }
                HStack {
                    Stepper(value: $waitInterval, in: 0...10, step: 1) {
                        HStack {
                            Text("Media inactivity timeout")
                            Spacer()
                            Text(
                                Measurement(
                                    value: Defaults[.waitInterval],
                                    unit: UnitDuration.seconds
                                ),
                                format: .measurement(
                                    width: .wide,
                                    usage: .asProvided,
                                    numberFormatStyle: .number.precision(
                                        .fractionLength(0)
                                    )
                                )
                            )
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Picker(
                    selection: $hideNotchOption,
                    label:
                        HStack {
                            Text("Full screen behavior")
                            customBadge(text: "Beta")
                        }
                ) {
                    Text("Hide for all apps").tag(HideNotchOption.always)
                    Text("Hide for media app only").tag(
                        HideNotchOption.nowPlayingOnly)
                    Text("Never hide").tag(HideNotchOption.never)
                }
            } header: {
                Text("Media playback live activity")
            }

            Section {
                MusicSlotConfigurationView()
                Defaults.Toggle(key: .showRemainingTime) {
                    Text("Show remaining time instead of duration")
                }
            } header: {
                Text("Media controls")
            }  footer: {
                Text("Customize which controls appear in the music player. Volume expands when active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Defaults.Toggle(key: .enableLyrics) {
                    Text("Show lyrics")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Defaults.Toggle(key: .lyricsTaiwanIdioms) {
                        Text("Apply Taiwan-style wording conversion")
                    }
                    Text("May change the meaning of some lyrics (e.g. 支持 → 支援, 打开 → 開啟). Only affects Simplified Chinese lyrics; off by default.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(!enableLyrics)
                VStack(alignment: .leading, spacing: 4) {
                    Defaults.Toggle(key: .lyricsPillEnabled) {
                        Text("Show lyrics under the closed notch")
                    }
                    Text("A slim capsule below the notch shows the current line while music plays. It uses a little display space on Macs with a physical notch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(!enableLyrics)
                if enableLyrics && lyricsPillEnabled {
                    Slider(value: $lyricsPillDropDistance, in: Double(LyricsPillMetrics.dropDistanceRange.lowerBound)...Double(LyricsPillMetrics.dropDistanceRange.upperBound), step: 1) {
                        HStack {
                            Text("Distance below the notch")
                            Spacer()
                            Text(verbatim: "\(Int(lyricsPillDropDistance)) pt")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Slider(value: $lyricsPillMaxWidth, in: Double(LyricsPillMetrics.maxWidthRange.lowerBound)...Double(LyricsPillMetrics.maxWidthRange.upperBound), step: 10) {
                        HStack {
                            Text("Maximum width")
                            Spacer()
                            Text(verbatim: "\(Int(lyricsPillMaxWidth)) pt")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Slider(value: $lyricsPillFontSize, in: Double(LyricsPillMetrics.fontSizeRange.lowerBound)...Double(LyricsPillMetrics.fontSizeRange.upperBound), step: 1) {
                        HStack {
                            Text("Lyrics font size")
                            Spacer()
                            Text(verbatim: "\(Int(lyricsPillFontSize)) pt")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Slider(value: $lyricsPillSpeed, in: LyricsPillMetrics.speedRange, step: 0.1) {
                        HStack {
                            Text("Lyrics scroll speed")
                            Spacer()
                            Text(verbatim: String(format: "%.1fx", lyricsPillSpeed))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Button {
                    LyricsService.shared.clearCache()
                    lyricsCacheCleared = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        lyricsCacheCleared = false
                    }
                } label: {
                    if lyricsCacheCleared {
                        Label("Lyrics cache cleared", systemImage: "checkmark.circle")
                    } else {
                        Text("Clear lyrics cache")
                    }
                }
            } header: {
                Text("Lyrics")
            } footer: {
                Text("When lyrics are on, the track title, artist and duration are sent to lrclib.net to look up lyrics.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Defaults.Toggle(key: .coloredSpectrogram) {
                    Text("Colored playback bars")
                }
                Defaults.Toggle(key: .playerColorTinting) {
                    Text("Player tinting")
                }
                Defaults.Toggle(key: .lightingEffect) {
                    Text("Enable blur effect behind album art")
                }
                Picker("Slider color", selection: $sliderColor) {
                    ForEach(SliderColorEnum.allCases, id: \.self) { option in
                        Text(option.localizedString)
                    }
                }
            } header: {
                Text("Player appearance")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Media")
        .task {
            musicManager.ensureNowPlayingAvailabilityChecked()
        }
    }

    private var mediaControllerSelection: Binding<MediaControllerType> {
        Binding(
            get: { musicManager.preferredMediaController },
            set: { selectedController in
                guard selectedController != musicManager.preferredMediaController else { return }
                musicManager.selectMediaController(selectedController)
            }
        )
    }

    @ViewBuilder
    private var mediaSourceFooter: some View {
        let availability = musicManager.nowPlayingAvailability

        if availability == .checking {
            footerText("Checking Now Playing availability...")
        } else if let message = availability.settingsMessage {
            VStack(alignment: .leading, spacing: 6) {
                footerText(message)

                if musicManager.preferredMediaController == .nowPlaying,
                   let effectiveController = musicManager.effectiveMediaController,
                   effectiveController != .nowPlaying {
                    if availability.usesTemporaryFallback {
                        footerText(
                            LocalizedStringResource(
                                "Using \(effectiveController.localizedString) temporarily. Your Now Playing preference is preserved.",
                                comment: "Media settings footer for a temporary Now Playing fallback. The placeholder is the active fallback source."
                            )
                        )
                    } else {
                        footerText(
                            LocalizedStringResource(
                                "Using \(effectiveController.localizedString) instead. Your Now Playing preference is preserved.",
                                comment: "Media settings footer for a non-recoverable Now Playing setup failure. The placeholder is the active fallback source."
                            )
                        )
                    }
                }

                if availability.offersManualRetry {
                    Button("Check Again") {
                        musicManager.refreshNowPlayingAvailability()
                    }
                    .font(.caption)
                }
            }
        } else {
            footerText(
                "Now Playing works with most players. If it is unavailable, DavidNook falls back to the Music app through Apple events, and macOS asks for Automation permission the first time that is needed."
            )
        }
    }

    private func footerText(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .font(.caption)
    }
}
