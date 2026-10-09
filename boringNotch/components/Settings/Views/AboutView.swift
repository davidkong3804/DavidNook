//
//  AboutView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//  Modified for DavidNook: 版本、授權聲明、衍生關係、第三方授權入口。
//

import Defaults
import DavidNookCore
import DavidNookUI
import SwiftUI

struct AboutView: View {
    @State private var showBuildNumber: Bool = false
    @State private var presentedDocument: LegalDocument?
    @ObservedObject private var updates = UpdateController.shared

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "DavidNook")
                            .font(.title3.weight(.semibold))
                        Text("A notch utility for macOS with synced lyrics and clipboard history.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                HStack {
                    Text("Version")
                    Spacer()
                    if showBuildNumber {
                        Text(verbatim: "(\(Bundle.main.buildVersionNumber ?? ""))")
                            .foregroundStyle(.secondary)
                    }
                    Text(verbatim: Bundle.main.releaseVersionNumber ?? "—")
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation {
                        showBuildNumber.toggle()
                    }
                }
                HStack {
                    Text("Core library")
                    Spacer()
                    Text(DavidNookCore.version)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Version info")
            }

            Section {
                UpdatePanelView(state: updates.state, strings: updates.strings, callbacks: updates.callbacks)
            } header: {
                Text("Updates")
            } footer: {
                Text("DavidNook connects to GitHub only when you press “Check for Updates”: a plain GET request to api.github.com (and, if you update, to GitHub's download servers) that carries only a User-Agent with the app version, for example DavidNook/0.1.0. No account, token, identifier or usage data is sent, and nothing is checked in the background or at launch. To replace itself, DavidNook asks you to choose the folder it is in, only while updating (the sandbox “user-selected files” permission).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("DavidNook is free software released under the GNU General Public License v3.0 (GPL-3.0). It comes with no warranty of any kind.")
                Text("DavidNook is a derivative work of boring.notch (TheBoredTeam), licensed under GPL-3.0.")
                Text("DavidNook is an independent implementation and is not affiliated with NotchNook or its authors.")
            } header: {
                Text("License and credits")
            }

            Section {
                linkRow(
                    title: "Source code",
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    help: "Open the project page in your browser"
                ) {
                    if let url = URL(string: "https://github.com/davidkong3804/DavidNook") {
                        NSWorkspace.shared.open(url)
                    }
                }
                linkRow(title: "GPL-3.0 license text", systemImage: "doc.text") {
                    presentedDocument = .gpl
                }
                linkRow(title: "Third-party licenses", systemImage: "shippingbox") {
                    presentedDocument = .thirdParty
                }
            } header: {
                Text("Links")
            }
        }
        .navigationTitle("About")
        .sheet(item: $presentedDocument) { document in
            LegalDocumentSheet(document: document)
        }
    }

    @ViewBuilder
    private func linkRow(
        title: LocalizedStringKey,
        systemImage: String,
        help: LocalizedStringKey? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let row = Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                    .frame(width: 22)
                Text(title)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if let help {
            row.help(help)
        } else {
            row
        }
    }
}

// MARK: - 授權文件（隨 App 內附，離線可讀）

/// App 內顯示的授權文件。內容來自 App bundle 內的資源（建置時複製）：
/// `LICENSE`（GPL-3.0 全文）、`THIRD_PARTY_NOTICES.md` 與 `LICENSES/*.txt`（第三方授權全文）。
enum LegalDocument: String, Identifiable {
    case gpl
    case thirdParty

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .gpl: LocalizedStringKey("GPL-3.0 license text")
        case .thirdParty: LocalizedStringKey("Third-party licenses")
        }
    }

    var text: String {
        switch self {
        case .gpl:
            return Self.read("LICENSE", nil, nil) ?? Self.missing
        case .thirdParty:
            var parts: [String] = []
            if let notices = Self.read("THIRD_PARTY_NOTICES", "md", nil) { parts.append(notices) }
            let urls = (Bundle.main.urls(forResourcesWithExtension: "txt", subdirectory: "LICENSES") ?? [])
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for url in urls {
                if let body = try? String(contentsOf: url, encoding: .utf8) {
                    parts.append("\n==== \(url.deletingPathExtension().lastPathComponent) ====\n\n" + body)
                }
            }
            return parts.isEmpty ? Self.missing : parts.joined(separator: "\n\n")
        }
    }

    private static var missing: String {
        String(localized: "The license text is not bundled with this build. See the project repository.",
               comment: "Shown in the license viewer when the bundled license files are missing.")
    }

    private static func read(_ name: String, _ ext: String?, _ subdirectory: String?) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdirectory) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

struct LegalDocumentSheet: View {
    let document: LegalDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(document.title)
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
            Divider()
            LegalTextView(text: document.text)
        }
        .frame(width: 640, height: 520)
    }
}

/// 大量唯讀文字用 NSTextView（可選取、捲動順暢），不用 SwiftUI Text。
private struct LegalTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            textView.textContainerInset = NSSize(width: 10, height: 10)
            textView.string = text
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        if let textView = scrollView.documentView as? NSTextView, textView.string != text {
            textView.string = text
        }
    }
}
