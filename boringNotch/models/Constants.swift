//
//  Constants.swift
//  boringNotch
//
//  Created by Richard Kunkli on 2024. 10. 17..
//

import DavidNookCore
import DavidNookUI
import SwiftUI
import Defaults

// MARK: - File System Paths
let documentsDirectory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    ?? URL(fileURLWithPath: NSTemporaryDirectory())
let bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "io.github.davidkong3804.DavidNook"
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
            return String(
                localized: "System default",
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

    // MARK: - UI
    static let accentColorChanged = Notification.Name("AccentColorChanged")
}

// Media controller types for selection in settings
enum MediaControllerType: String, CaseIterable, Identifiable, Defaults.Serializable {
    case nowPlaying
    case appleMusic

    var id: String { self.rawValue }

    init?(rawValue: String) {
        switch rawValue {
        case "nowPlaying", "Now Playing": self = .nowPlaying
        case "appleMusic", "Apple Music": self = .appleMusic
        default: return nil
        }
    }

    init?(nowPlayingBundleIdentifier bundleIdentifier: String) {
        switch bundleIdentifier {
        case "com.apple.Music":
            self = .appleMusic
        default:
            return nil
        }
    }

    var localizedResource: LocalizedStringResource {
        switch self {
        case .nowPlaying:
            LocalizedStringResource("Now Playing")
        case .appleMusic:
            LocalizedStringResource("Apple Music")
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
    /// 歌詞（LRCLIB）預設開啟；開啟時會把曲名、歌手與長度送到 lrclib.net 查詢。
    static let enableLyrics = Key<Bool>("enableLyrics", default: true)
    /// 簡體歌詞轉繁體時是否套用台灣慣用詞（軟件→軟體…）。預設關：慣用詞層對歌詞有風險（支持→支援、打开→開啟）。
    static let lyricsTaiwanIdioms = Key<Bool>("lyricsTaiwanIdioms", default: false)
    /// 收合瀏海下方的歌詞膠囊（一句一句跑馬燈）。預設開；沒有歌詞或沒在播放時不顯示。
    static let lyricsPillEnabled = Key<Bool>("lyricsPillEnabled", default: true)
    /// 膠囊離瀏海底緣的距離（pt；−8…40，預設 6）。有實體瀏海的螢幕上膠囊會佔用一點顯示空間。
    static let lyricsPillDropDistance = Key<Double>("lyricsPillDropDistance", default: 6)
    /// 膠囊最大寬度（pt；240…520，預設 360）。
    static let lyricsPillMaxWidth = Key<Double>("lyricsPillMaxWidth", default: 360)
    /// 膠囊字級（pt；11…16，預設 12）。
    static let lyricsPillFontSize = Key<Double>("lyricsPillFontSize", default: 12)
    /// 跑馬燈速度倍率（0.5…2，預設 1）。
    static let lyricsPillSpeed = Key<Double>("lyricsPillSpeed", default: 1)
    /// 展開的播放器是否顯示右側歌詞面板（歌名旁的按鈕切換）。
    /// 影片功能（在展開瀏海顯示你挑選的單一視窗的即時畫面）。預設開；沒挑視窗時完全不擷取。
    static let videoCapsuleEnabled = Key<Bool>(VideoCapsuleSettings.enabledKey, default: VideoCapsuleSettings.defaultEnabled)
    /// 影片寬度（pt；160…480，預設 320）。
    static let videoCapsuleWidth = Key<Double>(VideoCapsuleSettings.widthKey, default: VideoCapsuleSettings.defaultWidth)
    /// 影片是否釘選（M-C 的收合膠囊才會使用；目前只存狀態）。
    static let videoCapsulePinned = Key<Bool>(VideoCapsuleSettings.pinnedKey, default: VideoCapsuleSettings.defaultPinned)
    /// 記住的影片裁切（依來源 App 的 bundle id；只含 bundle id 與正規化矩形，JSON）。
    static let videoCropMemory = Key<Data?>(VideoCropMemory.defaultsKey, default: nil)
    static let showLyricsPanel = Key<Bool>("showLyricsPanel", default: true)
    static let showRemainingTime = Key<Bool>("showRemainingTime", default: false)
    static let musicControlSlots = Key<[MusicControlButton]>(
        "musicControlSlots",
        default: MusicControlButton.defaultLayout
    )
    static let musicControlSlotLimit = Key<Int>(
        "musicControlSlotLimit",
        default: MusicControlButton.defaultLayout.count
    )

    // MARK: Clipboard
    /// 記錄剪貼簿歷史（預設開）。關閉時完全不讀剪貼簿內容，也不輪詢 changeCount。
    static let clipboardEnabled = Key<Bool>("clipboardEnabled", default: true)
    /// 暫停記錄（開著 app 但暫時不記）。暫停中仍只輪詢 changeCount（不讀內容），恢復後不會補記暫停期間複製的內容。
    static let clipboardPaused = Key<Bool>("clipboardPaused", default: false)
    /// 未釘選條目的筆數上限（釘選不計入）。
    static let clipboardMaxItems = Key<Int>("clipboardMaxItems", default: 100)
    /// 保留天數；0 = 永久。釘選項目不受影響。
    static let clipboardRetentionDays = Key<Int>("clipboardRetentionDays", default: 30)
    /// 點選歷史項目後自動送出 ⌘V（實驗性；需要「輔助使用」授權，預設關）。
    static let clipboardAutoPaste = Key<Bool>("clipboardAutoPaste", default: false)
    /// 剪貼簿分頁底部「操作提示」：已成功複製回剪貼簿的次數（只是次數，不含任何內容）；滿 3 次自動收起。
    static let clipboardHintActivations = Key<Int>("clipboardHintActivations", default: 0)
    /// 剪貼簿分頁底部「操作提示」：使用者是否按了關閉。
    static let clipboardHintDismissed = Key<Bool>("clipboardHintDismissed", default: false)

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
    /// 展開瀏海的寬度（pt）與高度係數。預設 720／1.0；範圍 560–900／0.85–1.30，
    /// 讀取端一律經 `NotchSizing` 夾限，所以手動改壞偏好值也不會讓版面失控。
    static let openNotchWidth = Key<Double>("openNotchWidth", default: Double(NotchSizing.defaultWidth))
    static let openNotchHeightScale = Key<Double>("openNotchHeightScale", default: Double(NotchSizing.defaultHeightScale))

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

}
