//
//  WelcomeView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 2024. 09. 26..
//  Modified for DavidNook: upstream logo/branding artwork removed.
//

import SwiftUI

struct WelcomeView: View {
    var onGetStarted: (() -> Void)?
    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().scaledToFit()
                .frame(width: 100, height: 100)
                .padding(.bottom, 8)
            Text("DavidNook")
                .font(.system(.largeTitle, design: .default))
                .fontWeight(.semibold)
            Text("Welcome")
                .font(.title)
                .foregroundStyle(.secondary)
                .padding(.bottom, 30)

            Button {
                onGetStarted?()
            } label: {
                Text("Get started")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
            }
            .buttonStyle(BorderedProminentButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
        }
    }
}

#Preview {
    WelcomeView()
}
