//
//  SettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import SwiftUI

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case notch
    case appearance
    case media
    case clipboard
    case shortcuts
    case about

    enum Icon {
        case system(String)
        case custom(String)
    }

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .general: LocalizedStringKey("General")
        case .notch: LocalizedStringKey("Notch")
        case .appearance: LocalizedStringKey("Appearance")
        case .media: LocalizedStringKey("Media")
        case .clipboard: LocalizedStringKey("Clipboard")
        case .shortcuts: LocalizedStringKey("Shortcuts")
        case .about: LocalizedStringKey("About")
        }
    }

    var icon: Icon {
        switch self {
        case .general: .system("gear")
        case .notch: .custom("notch")
        case .appearance: .system("paintbrush")
        case .media: .system("play.rectangle")
        case .clipboard: .system("doc.on.clipboard")
        case .shortcuts: .system("keyboard")
        case .about: .system("info.circle")
        }
    }
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general
    @State private var accentColorUpdateTrigger = UUID()

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    tabItem(tab)
                }
            }
            .listStyle(SidebarListStyle())
            .tint(.effectiveAccent)
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(200)
        } detail: {
            Group {
                switch selectedTab {
                case .general:
                    GeneralSettings()
                case .notch:
                    NotchSettingsView()
                case .appearance:
                    AppearanceSettingsView()
                case .media:
                    MediaSettingsView()
                case .clipboard:
                    ClipboardSettingsView()
                case .shortcuts:
                    ShortcutsSettingsView()
                case .about:
                    AboutView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(verbatim: "")
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 700)
        .background(Color(NSColor.windowBackgroundColor))
        .tint(.effectiveAccent)
        .id(accentColorUpdateTrigger)
        .onReceive(NotificationCenter.default.publisher(for: .accentColorChanged)) { _ in
            accentColorUpdateTrigger = UUID()
        }
    }

    private func tabItem(_ tab: SettingsTab) -> some View {
        Label {
            Text(tab.title)
        } icon: {
            switch tab.icon {
            case .system(let imageName):
                Image(systemName: imageName)

            case .custom(let imageName):
                Image(imageName)
            }
        }
        .tag(tab)
    }
}
