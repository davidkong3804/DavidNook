//
//  AppIcons.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 16/08/24.
//

import SwiftUI
import AppKit

func normalizeBundleIdentifier(_ bundleID: String) -> String {
    let bundleID = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = bundleID.lowercased()

    // Handle Safari Technology Preview rendering helper processes
    if lower.hasPrefix("com.apple.safaritechnologypreview.") {
        return "com.apple.SafariTechnologyPreview"
    }

    // Handle WebKit / Safari rendering helper processes
    if lower.hasPrefix("com.apple.webkit.") || lower.hasPrefix("com.apple.safari.") {
        return "com.apple.Safari"
    }

    // General rule for Chromium/Electron helper processes
    // e.g., "com.google.Chrome.helper" -> "com.google.Chrome"
    let components = bundleID.components(separatedBy: ".")
    if let helperIndex = components.firstIndex(where: { $0.lowercased() == "helper" }) {
        return components[0..<helperIndex].joined(separator: ".")
    }

    return bundleID
}

private func applicationURL(for bundleID: String) -> URL? {
    let workspace = NSWorkspace.shared
    let normalizedID = normalizeBundleIdentifier(bundleID)

    if let appURL = workspace.urlForApplication(withBundleIdentifier: normalizedID) {
        return appURL
    }

    return workspace.runningApplications
        .filter {
            !$0.isTerminated
                && $0.bundleIdentifier.map(normalizeBundleIdentifier) == normalizedID
        }
        .sorted { lhs, rhs in
            if lhs.activationPolicy == .regular, rhs.activationPolicy != .regular {
                return true
            }
            if rhs.activationPolicy == .regular, lhs.activationPolicy != .regular {
                return false
            }
            return lhs.processIdentifier < rhs.processIdentifier
        }
        .first?.bundleURL
}

func appIcon(for bundleID: String) -> Image {
    let workspace = NSWorkspace.shared

    if let appURL = applicationURL(for: bundleID) {
        let appIcon = workspace.icon(forFile: appURL.path)
        return Image(nsImage: appIcon)
    }

    return Image(nsImage: workspace.icon(for: .applicationBundle))
}

func appIconAsNSImage(for bundleID: String) -> NSImage? {
    let workspace = NSWorkspace.shared

    if let appURL = applicationURL(for: bundleID) {
        let appIcon = workspace.icon(forFile: appURL.path)
        appIcon.size = NSSize(width: 256, height: 256)
        return appIcon
    }
    return nil
}
