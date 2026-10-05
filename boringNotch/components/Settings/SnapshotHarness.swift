//
//  SnapshotHarness.swift
//  DavidNook
//
//  僅 Debug 建置：以 `-davidnookSnapshot YES` 啟動時，把設定分頁離屏渲染成 PNG 後結束，
//  用來在不同語言下（例如 `-AppleLanguages (zh-Hant)`）檢查文案有沒有被截斷或溢出。Release 建置不含這段程式。
//
//  為什麼不用 ImageRenderer：它不會畫出 AppKit 支撐的控制項（Form、Toggle、Picker 會變成佔位圖示），
//  所以改用 NSHostingView.cacheDisplay 取真實控制項。
//  隱私／安全：只渲染本 App 自己的畫面；不碰剪貼簿（呼叫端必須再加 `-clipboardPaused YES`，
//  而且這裡在 ClipboardService.start() 之前就結束，不會開始監看）、不連網。App 是沙盒的，PNG 寫在容器的
//  暫存目錄（路徑會印在 stdout），由呼叫端自行複製出來。
//

#if DEBUG
import AppKit
import SwiftUI

private final class SnapshotWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor
enum SnapshotHarness {
    static var isRequested: Bool { UserDefaults.standard.bool(forKey: "davidnookSnapshot") }

    /// 沙盒容器內的暫存目錄（App 唯一可寫的位置）。
    static var outputDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("DavidNookSnapshots", isDirectory: true)
    }

    /// 渲染所有畫面並結束 App。
    static func runAndTerminate(into directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        print("SNAPSHOT_DIR=\(directory.path)")
        let suffix = UserDefaults.standard.string(forKey: "davidnookSnapshotSuffix") ?? ""

        let settingsWidth: CGFloat = 500
        let pages: [(String, AnyView, CGSize)] = [
            ("settings-general", AnyView(GeneralSettings()), CGSize(width: settingsWidth, height: 520)),
            ("settings-notch", AnyView(NotchSettingsView()), CGSize(width: settingsWidth, height: 1150)),
            ("settings-appearance", AnyView(AppearanceSettingsView()), CGSize(width: settingsWidth, height: 620)),
            ("settings-media", AnyView(MediaSettingsView()), CGSize(width: settingsWidth, height: 1350)),
            ("settings-clipboard", AnyView(ClipboardSettingsView()), CGSize(width: settingsWidth, height: 760)),
            ("settings-shortcuts", AnyView(ShortcutsSettingsView()), CGSize(width: settingsWidth, height: 480)),
            ("settings-about", AnyView(AboutView()), CGSize(width: settingsWidth, height: 620)),
            ("legal-third-party", AnyView(LegalDocumentSheet(document: .thirdParty)), CGSize(width: 640, height: 520)),
            ("legal-gpl", AnyView(LegalDocumentSheet(document: .gpl)), CGSize(width: 640, height: 520)),
        ]
        for (name, view, size) in pages {
            let content = view
                .formStyle(.grouped)
                .frame(width: size.width, height: size.height)
                .background(Color(nsColor: .windowBackgroundColor))
            render(AnyView(content), size: size, to: directory.appendingPathComponent("\(name)\(suffix).png"))
        }

        // 首次啟動視窗：每一步各一張。cacheDisplay 版（真實 AppKit 背景與按鈕、含彈性進場跑完後的最終畫面）
        // 與 ImageRenderer 版（SwiftUI 純軟體渲染；VisualEffectView 等 AppKit 元件不會被畫出，僅供對照版面）。
        for step in OnboardingStep.allCases {
            let name = "onboarding-\(step.rawValue + 1)-\(String(describing: step))"
            // 進場動畫跑完後的最終畫面（等 1.5 秒）；另存一份不跑動畫（animatesEntry: false）的對照。
            render(
                AnyView(OnboardingView(step: step, onFinish: {}, onOpenSettings: {})),
                size: OnboardingView.windowSize,
                to: directory.appendingPathComponent("\(name)\(suffix).png"),
                appLikeWindow: true,
                settle: 1.5
            )
            render(
                AnyView(OnboardingView(step: step, animatesEntry: false, onFinish: {}, onOpenSettings: {})),
                size: OnboardingView.windowSize,
                to: directory.appendingPathComponent("\(name)-static\(suffix).png"),
                appLikeWindow: true
            )
            renderWithImageRenderer(
                AnyView(
                    OnboardingView(step: step, animatesEntry: false, onFinish: {}, onOpenSettings: {})
                        .environment(\.onboardingStaticRender, true)
                ),
                size: OnboardingView.windowSize,
                to: directory.appendingPathComponent("\(name)-imagerenderer\(suffix).png")
            )
        }
        // 進場動畫的早期畫格（約 40 ms）：確認一開始內容是縮小且半透明，不是直接出現。
        render(
            AnyView(OnboardingView(step: .welcome, onFinish: {}, onOpenSettings: {})),
            size: OnboardingView.windowSize,
            to: directory.appendingPathComponent("onboarding-entry-early\(suffix).png"),
            appLikeWindow: true,
            settle: 0.04
        )
        NSApp.terminate(nil)
    }

    private static func renderWithImageRenderer(_ view: AnyView, size: CGSize, to url: URL) {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 2
        guard let image = renderer.cgImage else {
            print("SNAPSHOT_IMAGERENDERER_FAILED \(url.lastPathComponent)")
            return
        }
        let rep = NSBitmapImageRep(cgImage: image)
        if let data = rep.representation(using: .png, properties: [:]) {
            do { try data.write(to: url, options: .atomic) } catch { print("SNAPSHOT_WRITE_FAILED \(url.lastPathComponent): \(error)") }
        }
    }

    /// - Parameters:
    ///   - appLikeWindow: true 時用與首次啟動視窗相同的視窗設定（titled＋fullSizeContentView＋透明標題列），
    ///     讓 safe area 與實際一致。
    ///   - settle: 顯示後等多久才擷取（預設 0.8 秒，讓版面與動畫跑完）。
    private static func render(
        _ view: AnyView, size: CGSize, to url: URL, appLikeWindow: Bool = false, settle: TimeInterval = 0.8
    ) {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = SnapshotWindow(
            contentRect: NSRect(origin: NSPoint(x: 80, y: 80), size: size),
            styleMask: appLikeWindow ? [.titled, .fullSizeContentView] : [.borderless],
            backing: .buffered,
            defer: false
        )
        if appLikeWindow {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
        }
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        // 一般頁面用近乎透明的視窗；onboarding 要跑 SwiftUI 動畫，視窗太透明時 display link 不會推進，改成不透明。
        window.alphaValue = appLikeWindow ? 1 : 0.01
        window.makeKeyAndOrderFront(nil)
        // 讓 SwiftUI 完成版面與 .task／.onAppear。
        RunLoop.main.run(until: Date(timeIntervalSinceNow: settle))
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            window.orderOut(nil)
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            do { try data.write(to: url, options: .atomic) } catch { print("SNAPSHOT_WRITE_FAILED \(url.lastPathComponent): \(error)") }
        } else {
            print("SNAPSHOT_ENCODE_FAILED \(url.lastPathComponent)")
        }
        window.orderOut(nil)
    }
}
#endif
