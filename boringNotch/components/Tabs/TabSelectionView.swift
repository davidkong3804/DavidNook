//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import DavidNookUI
import SwiftUI

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
}

/// Extension point for notch tabs: add a `NotchViews` case, a `TabModel`
/// here, and a matching `case` in `ContentView`'s `switch coordinator.currentView`.
let tabs = [
    TabModel(label: "Home", icon: "house.fill", view: .home),
    TabModel(label: String(localized: "Clipboard", comment: "Notch tab and settings tab: clipboard history."), icon: "doc.on.clipboard", view: .clipboard),
]

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Namespace var animation
    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                    TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view) {
                        // 形體在兩個分頁尺寸之間以彈簧變形（response 0.38、dampingRatio 0.82），內容交叉淡入。
                        withAnimation(NotchMotion.current.animation(.tabSwitch)) {
                            coordinator.currentView = tab.view
                        }
                    }
                    .frame(height: 26)
                    .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                    .background {
                        if tab.view == coordinator.currentView {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        } else {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                                .hidden()
                        }
                    }
            }
        }
        .clipShape(Capsule())
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
