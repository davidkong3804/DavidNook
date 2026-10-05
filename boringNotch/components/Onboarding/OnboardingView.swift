//
//  OnboardingView.swift
//  boringNotch
//
//  Created by Alexander on 2025-06-23.
//  Modified for DavidNook: 橫向、較寬較矮的多頁版面，彈性進場與頁面轉場（尊重「減少動態」）。
//
//  這個視窗只「說明」：不會呼叫任何會跳系統權限提示的 API（沒有 AppleScript、沒有剪貼簿讀取、
//  沒有 CGRequestPostEventAccess／AXIsProcessTrusted）。
//

import AppKit
import Defaults
import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome
    /// 功能與資料流向（含唯一的對外連線）。
    case overview
    /// 權限與原因（只說明，不會觸發任何系統權限提示）。
    case permissions
    case finished
}

/// 離屏快照專用：ImageRenderer 畫不出 AppKit 支撐的 VisualEffectView（會變成佔位圖示），
/// 為 true 時背景改用純色。正式 App 不會設定它。
private struct OnboardingStaticRenderKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var onboardingStaticRender: Bool {
        get { self[OnboardingStaticRenderKey.self] }
        set { self[OnboardingStaticRenderKey.self] = newValue }
    }
}

struct OnboardingView: View {
    @Environment(\.onboardingStaticRender) private var staticRender

    /// 視窗內容尺寸（橫向；boringNotchApp 以此建立視窗）。
    static let windowSize = CGSize(width: 600, height: 400)

    @State var step: OnboardingStep
    let onFinish: () -> Void
    let onOpenSettings: () -> Void

    @State private var appeared: Bool
    /// 轉場方向：true＝往前（新頁由右側進來）。
    @State private var goingForward = true
    private let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    /// - Parameter animatesEntry: false 時直接以最終狀態顯示（離屏快照用）。
    init(
        step: OnboardingStep = .welcome,
        animatesEntry: Bool = true,
        onFinish: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        _step = State(initialValue: step)
        _appeared = State(initialValue: !animatesEntry)
        self.onFinish = onFinish
        self.onOpenSettings = onOpenSettings
    }

    var body: some View {
        ZStack {
            // 背景不跟著縮放，避免進場時視窗邊緣露出底色；只有內容做 scale／淡入。
            if staticRender {
                Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            } else {
                VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                ZStack {
                    page
                        .id(step)
                        .transition(pageTransition)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                Divider()
                footer
            }
            .scaleEffect(entryScale)
            .offset(y: entryOffset)
            .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.58), value: appeared)
            .opacity(appeared ? 1 : 0)
            .animation(.easeOut(duration: reduceMotion ? 0.2 : 0.25), value: appeared)
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .onAppear {
            // 彈性進場：scale 0.96→1＋輕微位移＋淡入；減少動態時只淡入。
            // 第一個畫格已用 appeared=false 渲染過，這裡改成 true 才會有動畫。
            appeared = true
        }
    }

    // MARK: - 進場與轉場

    private var entryScale: CGFloat { (appeared || reduceMotion) ? 1 : 0.96 }
    private var entryOffset: CGFloat { (appeared || reduceMotion) ? 0 : 10 }

    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        let enter: Edge = goingForward ? .trailing : .leading
        let leave: Edge = goingForward ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: enter).combined(with: .opacity),
            removal: .move(edge: leave).combined(with: .opacity)
        )
    }

    private var pageAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.86)
    }

    private func go(to next: OnboardingStep) {
        guard next != step else { return }
        // 先設定方向、下一個 run loop 再換頁：移除中的舊頁會沿用「上一次渲染」的轉場，方向才不會反。
        goingForward = next.rawValue > step.rawValue
        DispatchQueue.main.async {
            withAnimation(pageAnimation) { step = next }
        }
    }

    // MARK: - 頁面

    @ViewBuilder
    private var page: some View {
        switch step {
        case .welcome: WelcomePage()
        case .overview: OnboardingOverviewPage()
        case .permissions: OnboardingPermissionsPage()
        case .finished: OnboardingFinishPage()
        }
    }

    // MARK: - 頁尾（步驟點與按鈕）

    private var footer: some View {
        HStack(spacing: 12) {
            stepDots
            Spacer()
            switch step {
            case .welcome:
                Button("Get started") { go(to: .overview) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            case .overview:
                Button("Back") { go(to: .welcome) }
                Button("Continue") { go(to: .permissions) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            case .permissions:
                Button("Back") { go(to: .overview) }
                Button("Continue") {
                    BoringViewCoordinator.shared.firstLaunch = false
                    // 預設的「正在播放」來源視為使用者已確認：之後若改用備援，才會顯示備援提示。
                    Defaults[.didChooseMediaController] = true
                    go(to: .finished)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            case .finished:
                Button(action: onOpenSettings) {
                    Label("Customize in Settings", systemImage: "gear")
                }
                Button("Finish", action: onFinish)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 24)
        .frame(height: 64)
    }

    private var stepDots: some View {
        HStack(spacing: 7) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { item in
                Capsule()
                    .fill(item == step ? Color.effectiveAccent : Color.secondary.opacity(0.3))
                    .frame(width: item == step ? 18 : 7, height: 7)
                    .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: step)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
    }
}

// MARK: - 共用的頁面元件

/// 頁面標題（大標＋副標）。
struct OnboardingHeader: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title)
                .fontWeight(.bold)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 帶圖示的說明條目。
struct OnboardingItem: View {
    let icon: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.effectiveAccent)
                .frame(width: 28, height: 28)
                .background(Color.effectiveAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
