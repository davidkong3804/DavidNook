//
//  AboutView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import Defaults
import DavidNookCore
import SwiftUI

struct AboutView: View {
    @State private var showBuildNumber: Bool = false
    @Environment(\.openWindow) var openWindow

    var body: some View {
        VStack {
            Form {
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        if showBuildNumber {
                            Text(verbatim: "(\(Bundle.main.buildVersionNumber ?? ""))")
                                .foregroundStyle(.secondary)
                        }
                        Text(verbatim: Bundle.main.releaseVersionNumber ?? "—")
                            .foregroundStyle(.secondary)
                    }
                    .onTapGesture {
                        withAnimation {
                            showBuildNumber.toggle()
                        }
                    }
                    HStack {
                        Text("Core library")
                        Spacer()
                        Text(DavidNookCore.version)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Version info")
                }

                HStack(spacing: 30) {
                    Spacer(minLength: 0)
                    Button {
                        if let url = URL(string: "https://github.com/davidkong3804/DavidNook") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .font(.system(size: 15, weight: .medium))
                                .frame(height: 18)
                            Text("Source code")
                        }
                        .contentShape(Rectangle())
                    }
                    .help("Open the project page in your browser")
                    Spacer(minLength: 0)
                }
                .buttonStyle(PlainButtonStyle())
            }
            VStack(spacing: 0) {
                Divider()
                Text("DavidNook is a GPL-3.0 fork of boring.notch by The Bored Team and contributors.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 5)
                    .padding(.bottom, 7)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("About")
    }
}
