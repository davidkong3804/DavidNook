//
//  ClipboardSettingsView.swift
//  DavidNook
//
//  設定 → 剪貼簿：記錄開關、暫停、筆數上限、保留時間、點選後自動貼上（實驗性）、清除未釘選／清除全部。
//  風格與 Media 分頁一致（Form＋Section＋footer 小字）。資料與行為都在 ClipboardService／Core。
//

import Defaults
import SwiftUI

struct ClipboardSettingsView: View {
    @Default(.clipboardEnabled) private var enabled
    @Default(.clipboardPaused) private var paused
    @Default(.clipboardMaxItems) private var maxItems
    @Default(.clipboardRetentionDays) private var retentionDays
    @Default(.clipboardAutoPaste) private var autoPaste

    @ObservedObject private var service = ClipboardService.shared
    @State private var unpinnedCleared = false
    @State private var confirmClearAll = false
    @State private var clearAllFailed = false
    @State private var autoPasteAuthorized = ClipboardService.shared.isAutoPasteAuthorized

    /// 筆數上限選項；若設定檔裡是別的值（手動改過），也列出來，避免 Picker 沒有對應項目。
    private var maxItemOptions: [Int] {
        let base = [20, 50, 100, 200, 500]
        return base.contains(maxItems) ? base : (base + [maxItems]).sorted()
    }

    private var retentionOptions: [Int] {
        let base = [0, 1, 7, 30]
        return base.contains(retentionDays) ? base : (base + [retentionDays]).sorted()
    }

    var body: some View {
        Form {
            recordingSection
            if service.needsPermission {
                permissionSection
            }
            pasteSection
            clearSection
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Clipboard")
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
            // 使用者在系統設定授權後回到這裡，狀態會自動更新（只是檢查，不會跳提示）。
            let current = service.isAutoPasteAuthorized
            if current != autoPasteAuthorized { autoPasteAuthorized = current }
        }
    }

    // MARK: 記錄

    private var recordingSection: some View {
        Section {
            Defaults.Toggle(key: .clipboardEnabled) {
                Text("Record clipboard history")
            }
            Defaults.Toggle(key: .clipboardPaused) {
                Text("Pause recording")
            }
            .disabled(!enabled)
            Picker("Maximum items", selection: $maxItems) {
                ForEach(maxItemOptions, id: \.self) { count in
                    Text("\(count) items").tag(count)
                }
            }
            .disabled(!enabled)
            Picker("Keep history for", selection: $retentionDays) {
                ForEach(retentionOptions, id: \.self) { days in
                    switch days {
                    case 0: Text("Forever").tag(days)
                    case 1: Text("1 day").tag(days)
                    case 7: Text("7 days").tag(days)
                    case 30: Text("30 days").tag(days)
                    default: Text("\(days) days").tag(days)
                    }
                }
            }
            .disabled(!enabled)
        } header: {
            Text("Recording")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pinned items are never removed by the item limit or the retention time.")
                Text("Text larger than 1 MB and images larger than 20 MB are not recorded.")
                Text("Clipboard data is stored only on this Mac. Items marked as passwords or one-time content are never recorded.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: 系統的「從其他 App 貼上」

    private var permissionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text("Paste permission needed")
                } icon: {
                    Image(systemName: "lock.shield.fill").foregroundStyle(.orange)
                }
                Text("In System Settings → Privacy & Security → Paste from Other Apps, set DavidNook to Allow")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open System Settings") {
                    service.openPasteboardPrivacySettings()
                }
            }
        }
    }

    // MARK: 貼上

    private var pasteSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Defaults.Toggle(key: .clipboardAutoPaste) {
                        Text("Paste automatically after choosing (requires Accessibility)")
                    }
                    customBadge(text: "Experimental")
                }
            }
            if autoPaste {
                HStack {
                    Label {
                        Text(autoPasteAuthorized ? LocalizedStringKey("Permission granted") : LocalizedStringKey("Permission not granted"))
                    } icon: {
                        Image(systemName: autoPasteAuthorized ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(autoPasteAuthorized ? Color.green : Color.orange)
                    }
                    Spacer()
                    if !autoPasteAuthorized {
                        // 只有使用者按這個按鈕才會向系統請求授權（會跳系統提示）；其他地方只做檢查。
                        Button("Request permission") {
                            service.requestAutoPasteAuthorization()
                        }
                        Button("Open Accessibility Settings") {
                            openAccessibilitySettings()
                        }
                    }
                }
            }
        } header: {
            Text("Pasting")
        } footer: {
            Text("Experimental. DavidNook runs in the App Sandbox, so whether ⌘V can be sent depends on macOS accepting it after you grant permission; this has not been verified on every macOS version. Without permission the item is only copied back to the clipboard.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func openAccessibilitySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy",
        ]
        for string in candidates {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    // MARK: 清除

    private var clearSection: some View {
        Section {
            Button {
                service.clearUnpinned()
                unpinnedCleared = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    unpinnedCleared = false
                }
            } label: {
                if unpinnedCleared {
                    Label("Unpinned items cleared", systemImage: "checkmark.circle")
                } else {
                    Text("Clear unpinned")
                }
            }
            Button("Clear all", role: .destructive) {
                confirmClearAll = true
            }
            .confirmationDialog(
                "Clear all clipboard history?",
                isPresented: $confirmClearAll,
                titleVisibility: .visible
            ) {
                Button("Clear all", role: .destructive) {
                    Task {
                        let ok = await service.clearAll()
                        ClipboardPanelController.thumbnails.removeAll()
                        clearAllFailed = !ok
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes all clipboard history (including pinned items) and cached images. This cannot be undone.")
            }
            if clearAllFailed {
                Label("Some files could not be deleted", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Clear history")
        }
    }
}
