//
//  OnboardingOverviewView.swift
//  DavidNook
//
//  首次啟動的第二、三頁：說明 DavidNook 做什麼與唯一的對外連線，以及會用到哪些權限與原因。
//  這兩頁「只說明」：不會呼叫任何會跳系統權限提示的 API；權限只會在使用者實際用到該功能、
//  或在設定頁按下明確的按鈕時才會被要求。
//

import SwiftUI

/// 第二頁：功能與資料流向（三欄卡片）。
struct OnboardingOverviewPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingHeader(
                title: "How DavidNook works",
                subtitle: "DavidNook turns the notch into a small control center. Everything stays on this Mac; it goes online only for lyrics (lrclib.net) and when you press Check for Updates (GitHub)."
            )
            HStack(alignment: .top, spacing: 14) {
                card(
                    icon: "music.note",
                    title: "Now Playing and lyrics",
                    detail: "Shows the current track with playback controls and line-by-line synced lyrics."
                )
                card(
                    icon: "doc.on.clipboard",
                    title: "Clipboard history",
                    detail: "Remembers the text, images and files you copy so you can paste them again."
                )
                card(
                    icon: "network",
                    title: "Online only when needed",
                    detail: "Lyrics: the title, artist and duration of the current track go to lrclib.net (can be turned off in Settings → Media). Updates: only when you press Check for Updates, a plain request goes to GitHub. No telemetry, no background checks."
                )
            }
            .fixedSize(horizontal: false, vertical: true) // 三張卡片等高，高度取最高那張，不撐滿視窗
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 26)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func card(icon: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.effectiveAccent)
                .frame(width: 36, height: 36)
                .background(Color.effectiveAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// 第三頁：權限與原因。
struct OnboardingPermissionsPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            OnboardingHeader(
                title: "Permissions",
                subtitle: "Nothing here asks for a permission now. You can change everything later in Settings."
            )
            VStack(alignment: .leading, spacing: 14) {
                OnboardingItem(
                    icon: "music.quarternote.3",
                    title: "Music (Automation)",
                    detail: "Reads and controls the Music app: as a fallback when the system's Now Playing information is unavailable, and for favorites and volume when the Music app is the one playing. macOS asks the first time it is needed."
                )
                OnboardingItem(
                    icon: "rectangle.on.rectangle",
                    title: "Paste from Other Apps",
                    detail: "Needed for clipboard history. macOS asks when DavidNook first reads the clipboard (after you copy something); allow it in System Settings → Privacy & Security → Paste from Other Apps."
                )
                OnboardingItem(
                    icon: "accessibility",
                    title: "Accessibility (paste events)",
                    detail: "Only for the experimental “paste automatically after choosing” option, off by default. You grant it yourself from Settings → Clipboard."
                )
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 26)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

#Preview {
    OnboardingView(onFinish: {}, onOpenSettings: {})
}
