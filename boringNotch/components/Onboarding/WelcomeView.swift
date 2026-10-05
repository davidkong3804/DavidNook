//
//  WelcomeView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 2024. 09. 26..
//  Modified for DavidNook: upstream logo/branding artwork removed；改為橫向歡迎頁（按鈕由 OnboardingView 的頁尾提供）。
//

import SwiftUI

struct WelcomePage: View {
    var body: some View {
        HStack(spacing: 36) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 136, height: 136)
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "DavidNook")
                    .font(.system(size: 40, weight: .bold))
                Text("Welcome")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("A notch utility for macOS with synced lyrics and clipboard history.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
            .frame(maxWidth: 300, alignment: .leading)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    OnboardingView(onFinish: {}, onOpenSettings: {})
}
