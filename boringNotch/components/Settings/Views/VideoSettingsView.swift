//
//  VideoSettingsView.swift
//  DavidNook
//
//  設定 → 影片：功能開關與預設寬度。擷取只在你於「影片」分頁挑選視窗後才會開始。
//

import Defaults
import SwiftUI

struct VideoSettingsView: View {
    @Default(.videoCapsuleEnabled) private var enabled
    @Default(.videoCapsuleWidth) private var width

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .videoCapsuleEnabled) {
                    Text("Show the Video tab")
                }
                .onChange(of: enabled) { _, isOn in
                    if !isOn {
                        Task { @MainActor in
                            VideoCapsuleController.shared.stop()
                            if BoringViewCoordinator.shared.currentView == .video { BoringViewCoordinator.shared.currentView = .home }
                        }
                    }
                }
                LabeledContent("Video width") {
                    HStack {
                        Slider(
                            value: Binding(get: { width }, set: { width = $0 }),
                            in: 160...480,
                            step: 10
                        ) { editing in
                            if !editing { Task { @MainActor in VideoCapsuleController.shared.commitWidth() } }
                        }
                        .frame(width: 180)
                        Text(verbatim: "\(Int(width)) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .trailing)
                    }
                }
                .disabled(!enabled)
            } header: {
                Text("Video")
            } footer: {
                Text("Shows the live picture of one window you pick, scaled down inside the expanded notch. The picture stays in memory only: it is never saved, uploaded or recorded, and no sound is captured. Protected content (such as Netflix) cannot be captured by macOS and shows a notice instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Video")
    }
}
