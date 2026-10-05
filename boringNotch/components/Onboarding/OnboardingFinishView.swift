//
//  OnboardingFinishView.swift
//  boringNotch
//
//  Created by Alexander on 2025-06-23.
//  Modified for DavidNook: 橫向完成頁（按鈕由 OnboardingView 的頁尾提供）。
//

import SwiftUI

struct OnboardingFinishPage: View {
    var body: some View {
        HStack(spacing: 32) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 88))
                .foregroundStyle(Color.effectiveAccent)
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 8) {
                Text("You're All Set!")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("You can now enjoy the app. If you want to tweak things further, you can always visit the settings.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 320, alignment: .leading)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    OnboardingView(step: .finished, onFinish: {}, onOpenSettings: {})
}
