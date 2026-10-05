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
            ("onboarding-welcome", AnyView(WelcomeView()), CGSize(width: 400, height: 600)),
            ("onboarding-overview", AnyView(OnboardingOverviewView(onContinue: {})), CGSize(width: 400, height: 600)),
            ("onboarding-finish", AnyView(OnboardingFinishView(onFinish: {}, onOpenSettings: {})), CGSize(width: 400, height: 600)),
        ]
        for (name, view, size) in pages {
            let content = view
                .formStyle(.grouped)
                .frame(width: size.width, height: size.height)
                .background(Color(nsColor: .windowBackgroundColor))
            render(AnyView(content), size: size, to: directory.appendingPathComponent("\(name)\(suffix).png"))
        }
        NSApp.terminate(nil)
    }

    private static func render(_ view: AnyView, size: CGSize, to url: URL) {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = SnapshotWindow(
            contentRect: NSRect(origin: NSPoint(x: 80, y: 80), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.alphaValue = 0.01
        window.makeKeyAndOrderFront(nil)
        // 讓 SwiftUI 完成版面與 .task／.onAppear。
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.8))
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
