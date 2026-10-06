//
//  generic.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Foundation
import Defaults

enum Style {
    case notch
    case floating
}

enum NotchState {
    case closed
    case open
}

enum NotchViews {
    case home
    case clipboard
    case video
}

enum DownloadIndicatorStyle: String, Defaults.Serializable {
    case progress = "Progress"
    case percentage = "Percentage"
}

enum DownloadIconStyle: String, Defaults.Serializable {
    case onlyAppIcon = "Only app icon"
    case onlyIcon = "Only download icon"
    case iconAndAppIcon = "Icon and app icon"
}

enum WindowHeightMode: String, Defaults.Serializable {
    case matchMenuBar = "Match menubar height"
    case matchRealNotchSize = "Match real notch height"
    case custom = "Custom height"
}

enum SliderColorEnum: String, CaseIterable, Defaults.Serializable {
    case white
    case albumArt
    case accent

    init?(rawValue: String) {
        switch rawValue {
        case "white", "White": self = .white
        case "albumArt", "Match album art": self = .albumArt
        case "accent", "Accent color": self = .accent
        default: return nil
        }
    }

    var localizedString: String {
        switch self {
        case .white:
            return String(localized: "White", comment: "Slider color option: white")
        case .albumArt:
            return String(localized: "Match album art", comment: "Slider color option: match album art")
        case .accent:
            return String(localized: "Accent color", comment: "Slider color option: accent color")
        }
    }
}
