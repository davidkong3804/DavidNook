//
//  Constants.swift
//  boringNotch
//
//  Created by Richard Kunkli on 2024. 10. 17..
//

import SwiftUI
import Defaults

// MARK: - File System Paths
let documentsDirectory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    ?? URL(fileURLWithPath: NSTemporaryDirectory())
let bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "theboringteam.boringnotch"
let appVersion = "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))"

let temporaryDirectory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    ?? URL(fileURLWithPath: NSTemporaryDirectory())
let spacing: CGFloat = 16

enum HideNotchOption: String, Defaults.Serializable {
    case always
    case nowPlayingOnly
    case never
}

struct AppLanguage: RawRepresentable, Hashable, Identifiable, Defaults.Serializable {
    static let system = AppLanguage(rawValue: "system")

    var id: String { rawValue }
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static var allCases: [AppLanguage] {
        let languages = Bundle.main.localizations
            .filter(isSelectableLocalization)
            .map(AppLanguage.init(rawValue:))
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }

        return [.system] + languages
    }

    var displayName: String {
        if self == .system {
            return NSLocalizedString(
                "System default",
                comment: "Language picker option: follow the system app language"
            )
        }

        let displayName = nativeLocale.localizedString(forIdentifier: rawValue) ?? rawValue
        return displayName.capitalized(with: nativeLocale)
    }

    private var nativeLocale: Locale {
        Locale(identifier: rawValue)
    }

    private static func isSelectableLocalization(_ identifier: String) -> Bool {
        guard identifier != "Base" else { return false }
        guard let url = Bundle.main.url(
            forResource: "Localizable",
            withExtension: "strings",
            subdirectory: nil,
            localization: identifier
        ) else {
            return false
        }

        guard
            let data = try? Data(contentsOf: url),
            let strings = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: String]
        else {
            return false
        }

        return strings.values.contains { !$0.isEmpty }
    }

    func applyAppleLanguagesOverride() {
        if self == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
    }
}

// Define notification names at file scope
extension Notification.Name {
    // MARK: - Display
    static let selectedScreenChanged = Notification.Name("SelectedScreenChanged")
    static let notchHeightChanged = Notification.Name("NotchHeightChanged")
    static let showOnAllDisplaysChanged = Notification.Name("showOnAllDisplaysChanged")
    static let automaticallySwitchDisplayChanged = Notification.Name("automaticallySwitchDisplayChanged")

    // MARK: - Shelf
    static let expandedDragDetectionChanged = Notification.Name("expandedDragDetectionChanged")

    // MARK: - Sharing
    static let sharingDidFinish = Notification.Name("com.boringNotch.sharingDidFinish")

    // MARK: - UI
    static let accentColorChanged = Notification.Name("AccentColorChanged")
}

// Media controller types for selection in settings
enum MediaControllerType: String, CaseIterable, Identifiable, Defaults.Serializable {
    case nowPlaying
    case appleMusic
    case spotify
    case youtubeMusic

    var id: String { self.rawValue }

    init?(rawValue: String) {
        switch rawValue {
        case "nowPlaying", "Now Playing": self = .nowPlaying
        case "appleMusic", "Apple Music": self = .appleMusic
        case "spotify", "Spotify": self = .spotify
        case "youtubeMusic", "YouTube Music": self = .youtubeMusic
        default: return nil
        }
    }

    init?(nowPlayingBundleIdentifier bundleIdentifier: String) {
        switch bundleIdentifier {
        case "com.apple.Music":
            self = .appleMusic
        case "com.spotify.client":
            self = .spotify
        case YouTubeMusicConfiguration.default.bundleIdentifier:
            self = .youtubeMusic
        default:
            return nil
        }
    }

    var localizedResource: LocalizedStringResource {
        switch self {
        case .nowPlaying:
            "Now Playing"
        case .appleMusic:
            "Apple Music"
        case .spotify:
            "Spotify"
        case .youtubeMusic:
            "YouTube Music"
        }
    }

    var localizedString: String {
        String(localized: localizedResource)
    }
}

// Sneak peek styles for selection in settings
enum SneakPeekStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case standard
    case inline

    var id: String { self.rawValue }

    init?(rawValue: String) {
        switch rawValue {
        case "standard", "Default": self = .standard
        case "inline", "Inline": self = .inline
        default: return nil
        }
    }

    var localizedString: String {
        switch self {
        case .standard:
            return String(localized: "Default", comment: "Sneak Peek style: Default")
        case .inline:
            return String(localized: "Inline", comment: "Sneak Peek style: Inline")
        }
    }
}

extension Defaults.Keys {
    // MARK: General
    static let appLanguage = Key<AppLanguage>("appLanguage", default: .system)
    static let menubarIcon = Key<Bool>("menubarIcon", default: true)
    static let showOnAllDisplays = Key<Bool>("showOnAllDisplays", default: false)
    static let automaticallySwitchDisplay = Key<Bool>("automaticallySwitchDisplay", default: true)
    static let releaseName = Key<String>("releaseName", default: "Dapper Crab 🎩🦀")

    // MARK: Behavior
    static let minimumHoverDuration = Key<TimeInterval>("minimumHoverDuration", default: 0.3)
    static let enableOpeningAnimation = Key<Bool>("enableOpeningAnimation", default: true)
    static let animationSpeedMultiplier = Key<Double>("animationSpeedMultiplier", default: 1.0)
    static let enableHaptics = Key<Bool>("enableHaptics", default: true)
    static let openNotchOnHover = Key<Bool>("openNotchOnHover", default: true)
    static let extendHoverArea = Key<Bool>("extendHoverArea", default: false)
    static let notchHeightMode = Key<WindowHeightMode>(
        "notchHeightMode",
        default: WindowHeightMode.matchRealNotchSize
    )
    static let nonNotchHeightMode = Key<WindowHeightMode>(
        "nonNotchHeightMode",
        default: WindowHeightMode.matchMenuBar
    )
    static let nonNotchHeight = Key<CGFloat>("nonNotchHeight", default: 32)
    static let notchHeight = Key<CGFloat>("notchHeight", default: 32)
    // static let openLastTabByDefault = Key<Bool>("openLastTabByDefault", default: false)
    static let showOnLockScreen = Key<Bool>("showOnLockScreen", default: false)
    static let hideFromScreenRecording = Key<Bool>("hideFromScreenRecording", default: false)

    // MARK: Appearance
    // static let alwaysShowTabs = Key<Bool>("alwaysShowTabs", default: true)
    static let settingsIconInNotch = Key<Bool>("settingsIconInNotch", default: true)
    static let lightingEffect = Key<Bool>("lightingEffect", default: true)
    static let enableShadow = Key<Bool>("enableShadow", default: true)
    static let cornerRadiusScaling = Key<Bool>("cornerRadiusScaling", default: true)

    static let showNotHumanFace = Key<Bool>("showNotHumanFace", default: false)
    static let sliderColor = Key<SliderColorEnum>(
        "sliderUseAlbumArtColor",
        default: SliderColorEnum.white
    )
    static let playerColorTinting = Key<Bool>("playerColorTinting", default: true)

    // MARK: Gestures
    static let enableGestures = Key<Bool>("enableGestures", default: true)
    static let enableHorizontalMediaGestures = Key<Bool>("enableHorizontalMediaGestures", default: false)
    static let closeGestureEnabled = Key<Bool>("closeGestureEnabled", default: true)
    static let gestureSensitivity = Key<CGFloat>("gestureSensitivity", default: 200.0)

    // MARK: Media playback
    static let coloredSpectrogram = Key<Bool>("coloredSpectrogram", default: true)
    static let enableSneakPeek = Key<Bool>("enableSneakPeek", default: false)
    static let sneakPeekStyles = Key<SneakPeekStyle>("sneakPeekStyles", default: .standard)
    static let waitInterval = Key<Double>("waitInterval", default: 3)
    static let showShuffleAndRepeat = Key<Bool>("showShuffleAndRepeat", default: false)
    static let enableLyrics = Key<Bool>("enableLyrics", default: false)
    static let showRemainingTime = Key<Bool>("showRemainingTime", default: false)
    static let musicControlSlots = Key<[MusicControlButton]>(
        "musicControlSlots",
        default: MusicControlButton.defaultLayout
    )
    static let musicControlSlotLimit = Key<Int>(
        "musicControlSlotLimit",
        default: MusicControlButton.defaultLayout.count
    )

    // MARK: Downloads
    static let enableDownloadListener = Key<Bool>("enableDownloadListener", default: true)
    static let enableSafariDownloads = Key<Bool>("enableSafariDownloads", default: true)
    static let selectedDownloadIndicatorStyle = Key<DownloadIndicatorStyle>("selectedDownloadIndicatorStyle", default: DownloadIndicatorStyle.progress)
    static let selectedDownloadIconStyle = Key<DownloadIconStyle>("selectedDownloadIconStyle", default: DownloadIconStyle.onlyAppIcon)

    // MARK: Layout
    /// Swaps the opened notch for a smaller, player-only layout: no tab
    /// bar or calendar. Off by default so existing users keep the
    /// layout they already have.
    static let compactMode = Key<Bool>("compactMode", default: false)

    // MARK: Shelf
    static let boringShelf = Key<Bool>("boringShelf", default: true)
    static let openShelfByDefault = Key<Bool>("openShelfByDefault", default: true)
    static let shelfTapToOpen = Key<Bool>("shelfTapToOpen", default: true)
    static let quickShareProvider = Key<String>("quickShareProvider", default: QuickShareProvider.defaultProvider.id)
    static let copyOnDrag = Key<Bool>("copyOnDrag", default: false)
    static let autoRemoveShelfItems = Key<Bool>("autoRemoveShelfItems", default: false)
    static let expandedDragDetection = Key<Bool>("expandedDragDetection", default: true)
    static let reverseShelfOrdering = Key<Bool>("reverseShelfOrdering", default: false)

    // MARK: Fullscreen Media Detection
    static let hideNotchOption = Key<HideNotchOption>("hideNotchOption", default: .nowPlayingOnly)

    // MARK: Media Controller
    static let mediaController = Key<MediaControllerType>("mediaController", default: defaultMediaController)
    static let didChooseMediaController = Key<Bool>("didChooseMediaController", default: false)
    static let didMigrateMediaControllerChoice = Key<Bool>("didMigrateMediaControllerChoice", default: false)
    static let lastSupportedNowPlayingBundleIdentifier = Key<String?>(
        "lastSupportedNowPlayingBundleIdentifier",
        default: nil
    )

    // MARK: Advanced Settings
    static let useCustomAccentColor = Key<Bool>("useCustomAccentColor", default: false)
    static let customAccentColorData = Key<Data?>("customAccentColorData", default: nil)
    // Show or hide the title bar
    static let hideTitleBar = Key<Bool>("hideTitleBar", default: true)
    static let hideNonNotchedFromMissionControl = Key<Bool>("hideNonNotchedFromMissionControl", default: true)
    // Normalize scroll/gesture direction so when macOS "Natural scrolling" is disabled, it doesn't invert gestures
    static let normalizeGestureDirection = Key<Bool>("normalizeGestureDirection", default: true)

    // Keep the default stable. Runtime availability is handled by MusicManager.
    static var defaultMediaController: MediaControllerType {
        .nowPlaying
    }

    static let didClearLegacyURLCacheV1 = Key<Bool>("didClearLegacyURLCache_v1", default: false)
}
