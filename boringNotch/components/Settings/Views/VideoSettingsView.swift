//
//  VideoSettingsView.swift
//  DavidNook
//
//  設定 → 影片：功能開關與影片寬度。擷取只在你於「正在播放」面板的封面槽挑選視窗後才會開始。
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
                    Text("Show a picked window in the Home panel")
                }
                .onChange(of: enabled) { _, isOn in
                    if !isOn {
                        Task { @MainActor in VideoCapsuleController.shared.stop() }
                    }
                }
                LabeledContent("Video size") {
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
                Text("Pick one window with the small button on the album cover and its live picture replaces the cover; click the video to pin it as a capsule outside the notch. The video size sets how wide the video can grow in the Home panel and how big the pinned capsule is. The picture stays in memory only: it is never saved, uploaded or recorded, and no sound is captured. Protected content (such as Netflix) cannot be captured by macOS and shows a notice instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Video")
    }
}
