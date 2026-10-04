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
    case accessibilityPermission
    case musicPermission
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
                        step = .accessibilityPermission
                    }
                }
                .transition(.opacity)

            case .accessibilityPermission:
                PermissionsRequestView(
                    icon: Image(systemName: AccessibilityPermission.systemImageName),
                    title: String(localized: "Enable \(AccessibilityPermission.displayName)"),
                    description: String(localized: "\(AccessibilityPermission.displayName) is only needed when using built-in macOS control sources for OSD replacement. External sources like BetterDisplay or Lunar do not require it. You can enable it later in OSD settings if needed."),
                    privacyNote: String(localized: "\(AccessibilityPermission.displayName) is used only to improve media and brightness notifications. No data is collected or shared."),
                    onAllow: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .musicPermission
                        }
                    },
                    onSkip: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .musicPermission
                        }
                    }
                )
                .transition(.opacity)

            case .musicPermission:
                MusicControllerSelectionView(
                    onContinue: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            BoringViewCoordinator.shared.firstLaunch = false
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

    // MARK: - Permission Request Logic

}
