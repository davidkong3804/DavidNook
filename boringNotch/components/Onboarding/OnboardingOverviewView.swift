//
//  OnboardingOverviewView.swift
//  DavidNook
//
//  首次啟動的第二頁：說明 DavidNook 做什麼、會用到哪些權限與原因、唯一的對外連線。
//  這一頁「只說明」：不會呼叫任何會跳系統權限提示的 API（沒有 AppleScript、沒有剪貼簿讀取、
//  沒有 CGRequestPostEventAccess／AXIsProcessTrusted）。權限只會在使用者實際用到該功能、
//  或在設定頁按下明確的按鈕時才會被要求。
//

import SwiftUI

struct OnboardingOverviewView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("How DavidNook works")
                            .font(.title)
                            .fontWeight(.bold)
                        Text("DavidNook turns the notch into a small control center. Everything stays on this Mac.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    group("What it does") {
                        item(
                            icon: "music.note",
                            title: "Now Playing and lyrics",
                            detail: "Shows the current track with playback controls and line-by-line synced lyrics."
                        )
                        item(
                            icon: "doc.on.clipboard",
                            title: "Clipboard history",
                            detail: "Remembers the text, images and files you copy so you can paste them again."
                        )
                    }

                    group("Permissions") {
                        item(
                            icon: "music.quarternote.3",
                            title: "Music (Automation)",
                            detail: "Reads and controls the Music app: as a fallback when the system's Now Playing information is unavailable, and for favorites and volume when the Music app is the one playing. macOS asks the first time it is needed."
                        )
                        item(
                            icon: "rectangle.on.rectangle",
                            title: "Paste from Other Apps",
                            detail: "Needed for clipboard history. macOS asks when DavidNook first reads the clipboard (after you copy something); allow it in System Settings → Privacy & Security → Paste from Other Apps."
                        )
                        item(
                            icon: "accessibility",
                            title: "Accessibility (paste events)",
                            detail: "Only for the experimental “paste automatically after choosing” option, off by default. You grant it yourself from Settings → Clipboard."
                        )
                    }

                    group("Network") {
                        item(
                            icon: "network",
                            title: "lrclib.net only",
                            detail: "The only connection: the title, artist and duration of the current track go to lrclib.net to look up lyrics (can be turned off in Settings → Media). No telemetry, no update server."
                        )
                    }

                }
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 12)
            }

            Divider()
            VStack(spacing: 12) {
                Text("Nothing here asks for a permission now. You can change everything later in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Continue", action: onContinue)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
    }

    private func group<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private func item(icon: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.effectiveAccent)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    OnboardingOverviewView(onContinue: {})
        .frame(width: 400, height: 600)
}
