//
//  OnboardingView.swift
//  boringNotch
//
//  Created by Alexander on 2025-06-23.
//

import SwiftUI
import Defaults

enum OnboardingStep {
    case welcome
    /// 權限與資料流向的說明頁（只說明，不會觸發任何系統權限提示）。
    case overview
    case finished
}

struct OnboardingView: View {
    @State var step: OnboardingStep = .welcome
    let onFinish: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        ZStack {
            switch step {
            case .welcome:
                WelcomeView {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        step = .overview
                    }
                }
                .transition(.opacity)

            case .overview:
                OnboardingOverviewView(
                    onContinue: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            BoringViewCoordinator.shared.firstLaunch = false
                            // 預設的「正在播放」來源視為使用者已確認：之後若改用備援，才會顯示備援提示。
                            Defaults[.didChooseMediaController] = true
                            step = .finished
                        }
                    }
                )
                .transition(.opacity)

            case .finished:
                OnboardingFinishView(onFinish: onFinish, onOpenSettings: onOpenSettings)
            }
        }
        .frame(width: 400, height: 600)
    }
}
