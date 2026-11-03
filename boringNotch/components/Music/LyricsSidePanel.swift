//
//  LyricsSidePanel.swift
//  DavidNook
//
//  展開的 Now Playing 首頁右側的歌詞面板：把 LyricsService（狀態、顯示行、偏移）與 MusicManager 的播放時鐘
//  接到 DavidNookUI 的資料驅動元件。這裡只做接線；時間軸、簡繁轉換、網路都在 DavidNookCore。
//

import DavidNookCore
import DavidNookUI
import Defaults
import SwiftUI
import Translation

struct LyricsSidePanel: View {
    @ObservedObject private var service = LyricsService.shared
    /// 日文／韓文歌只顯示原文（設定頁與歌名旁的按鈕共用同一個設定）。
    @Default(.lyricsOriginalOnly) private var originalOnly
    @ObservedObject private var musicManager = MusicManager.shared
    /// 對時控制是否展開（點右下角的「對時」小按鈕）。換歌或歌詞消失時自動收合。
    @State private var isSyncOpen = false
    /// 點歌詞對齊後的短暫回饋文字。
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    /// 滑鼠離開面板一小段時間後自動收合對時控制。
    @State private var collapseTask: Task<Void, Never>?
    /// 瀏海正在變形（展開／收合／切分頁）：降低歌詞時間軸的更新頻率，把算力留給形體動畫。
    @Environment(\.notchIsMorphing) private var isMorphing
    /// 可見行數：預設 5 行；展開面板高度不足時由 `NotchHomeMetrics` 降為 4 行。
    var visibleLineCount: Int = LyricsPanelMetrics.defaultVisibleLines

    private let strings = LyricsPanelStrings(
        loading: String(localized: "Loading lyrics…", comment: "Lyrics panel: shown while lyrics are being looked up."),
        noLyrics: String(localized: "No lyrics for this song", comment: "Lyrics panel: no synced lyrics were found."),
        instrumental: String(localized: "Instrumental", comment: "Lyrics panel: the track is instrumental."),
        error: String(localized: "Couldn't get lyrics", comment: "Lyrics panel: the lookup failed (network or server error).")
    )

    private let offsetStrings = OffsetControlStrings(
        badgeIdle: String(localized: "Sync", comment: "Lyrics panel: small always-visible button that opens the lyrics timing controls."),
        advancedBadge: { String(localized: "\($0) s early", comment: "Lyrics panel: the badge when this song's lyrics are shown earlier. Placeholder is the seconds, e.g. 1.2.") },
        delayedBadge: { String(localized: "\($0) s late", comment: "Lyrics panel: the badge when this song's lyrics are shown later. Placeholder is the seconds, e.g. 0.4.") },
        badgeHelp: String(localized: "Adjust lyrics timing. Click to open the controls. Double-click the line being sung to sync to it. Scroll here to nudge by 0.1 s.", comment: "Tooltip of the small Sync button in the lyrics panel."),
        noOffsetStatus: String(localized: "Now: no offset", comment: "Lyrics timing controls: status line when the lyrics are not shifted."),
        advancedStatus: { String(localized: "Now: lyrics \($0) s early", comment: "Lyrics timing controls: status line when lyrics are shown earlier. Placeholder is the seconds, e.g. 1.2.") },
        delayedStatus: { String(localized: "Now: lyrics \($0) s late", comment: "Lyrics timing controls: status line when lyrics are shown later. Placeholder is the seconds, e.g. 0.4.") },
        idleHint: String(localized: "Click the line being sung to sync", comment: "Lyrics timing controls: hint shown while there is no offset. Fits one short line."),
        closeHelp: String(localized: "Close sync controls", comment: "Tooltip of the button that collapses the lyrics timing controls."),
        advanceCaption: String(localized: "Lyrics too late", comment: "Lyrics timing controls: small caption above the Earlier button (the lyrics show up after the singing)."),
        advanceTitle: String(localized: "Show earlier", comment: "Lyrics timing controls: button that shows the lyrics earlier."),
        advanceHelp: String(localized: "Lyrics show up after the singing? Show them earlier. Hold Option or Shift for 0.5 s steps; hold the button to repeat; scrolling down also shows them earlier.", comment: "Tooltip of the Earlier button."),
        delayCaption: String(localized: "Lyrics too early", comment: "Lyrics timing controls: small caption above the Later button (the lyrics show up before the singing)."),
        delayTitle: String(localized: "Show later", comment: "Lyrics timing controls: button that shows the lyrics later."),
        delayHelp: String(localized: "Lyrics show up before the singing? Show them later. Hold Option or Shift for 0.5 s steps; hold the button to repeat; scrolling up also shows them later.", comment: "Tooltip of the Later button."),
        coarse: String(localized: "Coarse", comment: "Lyrics timing controls: toggle that makes each step 0.5 s instead of 0.1 s."),
        coarseHelp: String(localized: "Each step is 0.5 s instead of 0.1 s", comment: "Tooltip of the Coarse toggle."),
        reset: String(localized: "Reset", comment: "Button that resets the per-track lyrics offset to zero."),
        resetHelp: String(localized: "Reset lyrics offset", comment: "Tooltip of the reset lyrics offset button."),
        aligned: String(localized: "Synced. Remembered for this song", comment: "Toast shown after the user clicked a lyric line to sync the timing."),
        alignedLimit: String(localized: "Offset limit reached (±60 s)", comment: "Toast shown when syncing to a lyric line would need more than ±60 seconds of offset."),
        lineHelp: String(localized: "Click this line to sync it to the current playback position", comment: "Tooltip of a lyric line while the timing controls are open."),
        currentOffset: String(localized: "Current offset", comment: "Accessibility label prefix for the current lyrics offset.")
    )

    var body: some View {
        content
            .contentShape(Rectangle())
            .onHover { hovering in
                // 對時控制展開後，滑鼠離開面板 2 秒才自動收合（中途回來就取消）。
                collapseTask?.cancel()
                guard !hovering, isSyncOpen else { return }
                collapseTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    withAnimation(.smooth(duration: 0.25)) { isSyncOpen = false }
                }
            }
            .onChange(of: service.status) { _, status in
                if status != .loaded, isSyncOpen { isSyncOpen = false }
            }
            .onDisappear {
                collapseTask?.cancel()
                toastTask?.cancel()
                LyricsSyncPointer.isOverControl = false
            }
    }

    private var syncConfiguration: LyricsSyncConfiguration? {
        guard service.status == .loaded else { return nil }
        return LyricsSyncConfiguration(
            strings: offsetStrings,
            isOpen: isSyncOpen,
            toast: toast,
            onToggle: { withAnimation(.smooth(duration: 0.25)) { isSyncOpen.toggle() } },
            onAdjust: { service.adjustOffset(byMs: $0) },
            onReset: { service.resetOffset() },
            onAlignLine: { alignLine($0) },
            onPointerInside: { LyricsSyncPointer.isOverControl = $0 }
        )
    }

    /// 點歌詞對齊：用「點擊這一刻」的播放位置，把被點的行對齊到現在，並顯示回饋。
    private func alignLine(_ index: Int) {
        let position = musicManager.estimatedPlaybackPosition(at: Date())
        guard let result = service.alignOffset(toLine: index, atPosition: position) else { return }
        showToast(offsetStrings.alignedToast(isClamped: result.isClamped))
    }

    private func showToast(_ text: String) {
        toastTask?.cancel()
        withAnimation(.smooth(duration: 0.2)) { toast = text }
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.3)) { toast = nil }
        }
    }

    @ViewBuilder
    private var content: some View {
        if service.status == .idle {
            Color.clear
        } else {
            // 10 Hz 重新取目前行（瀏海變形期間降為 2 Hz，約半秒內最多差一行）；暫停時停止更新。
            // 位置來自 PlaybackClock（elapsed + (now − timestamp) × rate）。
            TimelineView(.animation(minimumInterval: isMorphing ? 0.5 : 0.1, paused: !musicManager.isPlaying)) { context in
                let position = musicManager.estimatedPlaybackPosition(at: context.date)
                LyricsPanelView(
                    lines: LyricsPanelLine.make(from: service.lines, translations: originalOnly ? nil : service.translations),
                    currentIndex: service.currentIndex(at: position),
                    offsetMs: service.offsetMs,
                    status: panelStatus,
                    strings: strings,
                    visibleLineCount: visibleLineCount,
                    sync: syncConfiguration
                )
            }
        }
    }

    private var panelStatus: LyricsPanelStatus {
        switch service.status {
        case .idle, .loading: .loading
        case .loaded: .loaded
        case .notFound: .noLyrics
        case .error: .error
        }
    }
}

/// 日文／韓文歌的現場翻譯：用系統的離線翻譯（Translation 框架，macOS 15 以上），歌詞不離開這台 Mac。
/// 系統只讓視圖取得翻譯工作階段，所以由「一直在畫面上」的 `LyricsPillHost` 接手 `LyricsService.translationJob`：
/// 歌詞一載入就開始翻，不必等你展開面板（膠囊也要用翻譯）。多個螢幕各有一份視圖時，由 `claimTranslation` 保證只翻一次。
/// 第一次翻某個語言時，系統可能會跳出下載語言包的提示。失敗就只顯示原文。
extension View {
    @ViewBuilder
    func lyricsTranslationHost(service: LyricsService) -> some View {
        if #available(macOS 15.0, *) {
            modifier(LyricsTranslationHost(service: service))
        } else {
            self
        }
    }
}

@available(macOS 15.0, *)
private struct LyricsTranslationHost: ViewModifier {
    @ObservedObject var service: LyricsService
    @State private var configuration: TranslationSession.Configuration?

    func body(content: Content) -> some View {
        content
            .translationTask(configuration) { [service] session in
                await Self.translate(with: session, service: service)
            }
            .onAppear { start(service.translationJob) }
            .onChange(of: service.translationJob) { _, job in start(job) }
    }

    /// 只在語言包**已經裝好**時才翻：沒裝的話，系統會跳出下載對話框，在這種無邊框浮動視窗上可能卡住整個螢幕的操作。
    /// 沒裝就只顯示原文（到「系統設定 → 一般 → 語言與地區 → 翻譯語言」下載日文／韓文與繁體中文後，下次播放就會翻）。
    private func start(_ job: LyricsService.TranslationJob?) {
        guard let job else {
            configuration = nil
            return
        }
        let source = Locale.Language(identifier: job.source == .japanese ? "ja" : "ko")
        let target = Locale.Language(identifier: "zh-Hant")
        Task { @MainActor in
            let status = await LanguageAvailability().status(from: source, to: target)
            guard service.translationJob == job else { return }
            guard status == .installed else {
                service.failTranslation(job)
                return
            }
            let next = TranslationSession.Configuration(source: source, target: target)
            if configuration == next { configuration?.invalidate() } else { configuration = next }
        }
    }

    nonisolated private static func translate(with session: TranslationSession, service: LyricsService) async {
        guard let job = await service.translationJob, await service.claimTranslation(job) else { return }
        do {
            let requests = job.requests.enumerated().map {
                TranslationSession.Request(sourceText: $0.element.text, clientIdentifier: String($0.offset))
            }
            let responses = try await session.translations(from: requests)
            var byID: [Int: String] = [:]
            for response in responses {
                if let id = response.clientIdentifier.flatMap(Int.init) { byID[id] = response.targetText }
            }
            await service.completeTranslation(job, translated: job.requests.indices.map { byID[$0] ?? "" })
        } catch is CancellationError {
            await service.releaseTranslationClaim(job)      // 被取消：工作留著，下次再翻
            return
        } catch {
            await service.failTranslation(job)
        }
    }
}

/// 歌名旁的第二顆小按鈕：日文／韓文歌才出現，切換「只顯示原文」。
struct LyricsTranslationToggleSlot: View {
    @ObservedObject private var service = LyricsService.shared
    @Default(.lyricsOriginalOnly) private var originalOnly

    var body: some View {
        if service.sourceLanguage != nil {
            LyricsTranslationToggleButton(isOriginalOnly: $originalOnly)
        }
    }
}

struct LyricsTranslationToggleButton: View {
    @Binding var isOriginalOnly: Bool

    var body: some View {
        Button {
            withAnimation(.smooth(duration: 0.25)) { isOriginalOnly.toggle() }
        } label: {
            Image(systemName: "character.bubble")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isOriginalOnly ? Color.gray : Color.white)
                .frame(width: 20, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(isOriginalOnly ? 0.06 : 0.16))
                )
        }
        .buttonStyle(.plain)
        .help(isOriginalOnly ? String(localized: "Show Chinese translation") : String(localized: "Show original lyrics only"))
        .accessibilityLabel(isOriginalOnly ? String(localized: "Show Chinese translation") : String(localized: "Show original lyrics only"))
    }
}

/// 滑鼠是否正指著歌詞面板的對時控制。
///
/// 瀏海外層（ContentView）有「上滑關閉」的捲動手勢監聽；對時控制支援滾輪微調，滾輪往上捲不能同時把瀏海關掉。
/// 對時控制在滑鼠進出時設定這個旗標，ContentView 的手勢處理在它為 true 時略過新的捲動。
@MainActor
enum LyricsSyncPointer {
    static var isOverControl = false
}

/// 歌名旁的小按鈕：切換歌詞面板的顯示。
struct LyricsToggleButton: View {
    @Binding var isShowing: Bool

    var body: some View {
        Button {
            withAnimation(.smooth(duration: 0.25)) { isShowing.toggle() }
        } label: {
            Image(systemName: "text.quote")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isShowing ? Color.white : Color.gray)
                .frame(width: 20, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(isShowing ? 0.16 : 0.06))
                )
        }
        .buttonStyle(.plain)
        .help(isShowing ? String(localized: "Hide lyrics") : String(localized: "Show lyrics"))
        .accessibilityLabel(isShowing ? String(localized: "Hide lyrics") : String(localized: "Show lyrics"))
    }
}

// MARK: - 收合瀏海下方的歌詞膠囊

/// 收合瀏海下方的歌詞膠囊（一句一句跑馬燈）：由 ContentView 放在瀏海正下方，位置＝瀏海底緣＋「下拉距離」。
///
/// - 資料沿用 `LyricsService`（目前行、偏移、簡轉繁）與 `MusicManager` 的播放時鐘；不新增網路請求、不寫 log。
/// - 可見性走 Core 的 `LyricsPillVisibility`（收合＋播放中＋歌詞已載入＋當前句非空＋功能開啟；暫停延遲 1.5 秒才收起）。
/// - 效能：10 Hz 的 `TimelineView` 只在「功能開啟＋收合＋播放中＋歌詞已載入」時跑；其餘時間暫停（零逐幀成本）。
///   逐幀（`.animation`）更新只發生在 `LyricsPillView` 內「這一句放不下、正在捲動」的那幾秒。
/// - 雙語：日文／韓文歌有中文翻譯（且沒開「只顯示原文」）時，膠囊變兩行（原文＋較小、較淡的翻譯）。
/// - 互動：膠囊本身不接收點擊（`allowsHitTesting(false)`）。預設（「滑鼠移到膠囊上時透過去」開）：游標在膠囊上停留一下，
///   膠囊就變淡、視窗暫時不接收滑鼠事件（`ignoresMouseEvents`），點擊直接落到底下的視窗（例如瀏覽器分頁）；
///   已不接收事件就沒有 hover 可用，所以靠定時取樣游標座標（見 Core 的 `LyricsPillPassThrough`）。
///   關閉該設定時維持舊行為：另放一塊與膠囊同大的透明區域，hover 與點擊轉接給瀏海，滑鼠移到膠囊上等同移到瀏海。
struct LyricsPillHost: View {
    /// 瀏海目前是收合狀態，且沒有被隱藏／歡迎動畫／提示佔用。
    var isNotchClosed: Bool
    /// 瀏海底緣離視窗上緣的距離（pt）。
    var notchBottom: CGFloat
    var onHover: (Bool) -> Void
    var onTap: () -> Void
    /// 膠囊實際可見（含淡出前）時回報給 ContentView，讓影片膠囊知道要不要讓位（垂直堆疊）。
    var onVisibleChange: (Bool) -> Void = { _ in }

    @ObservedObject private var service = LyricsService.shared
    @ObservedObject private var musicManager = MusicManager.shared
    @Default(.enableLyrics) private var enableLyrics
    @Default(.lyricsPillEnabled) private var pillEnabled
    @Default(.lyricsPillDropDistance) private var dropDistance
    @Default(.lyricsPillMaxWidth) private var maxWidth
    @Default(.lyricsPillFontSize) private var fontSize
    @Default(.lyricsPillSpeed) private var speed
    @Default(.lyricsPillTintFromCover) private var tintFromCover
    @Default(.lyricsPillPassThrough) private var passThroughEnabled
    @Default(.lyricsOriginalOnly) private var originalOnly

    @State private var visibility = LyricsPillVisibility()
    @State private var graceTask: Task<Void, Never>?
    /// 最後一句非空的歌詞（含翻譯）：膠囊淡出期間仍用它算尺寸。
    @State private var heldLine: LyricsPillLine?
    @State private var passThrough = LyricsPillPassThrough()
    @State private var isPassingThrough = false
    @State private var windowBox = PillWindowBox()

    private var style: LyricsPillStyle {
        LyricsPillStyle(
            fontSize: CGFloat(fontSize), maxWidth: CGFloat(maxWidth), speedMultiplier: speed,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            textColor: tintFromCover ? coverTint : nil
        )
    }

    /// 專輯封面平均色染出來的淡彩色；封面沒有顏色或還沒取到時為 nil（維持白字）。
    private var coverTint: Color? {
        guard let cover = musicManager.avgColor.usingColorSpace(.sRGB),
              let tint = LyricsPillTint.textColor(
                  red: Double(cover.redComponent), green: Double(cover.greenComponent), blue: Double(cover.blueComponent)
              ) else { return nil }
        return Color(red: tint.red, green: tint.green, blue: tint.blue)
    }

    var body: some View {
        let enabled = enableLyrics && pillEnabled
        let eligible = enabled && isNotchClosed && service.status == .loaded
        let style = style
        let size = pillSize(style: style)
        ZStack(alignment: .top) {
            TimelineView(.animation(minimumInterval: 0.1, paused: !(eligible && musicManager.isPlaying))) { context in
                let sample = eligible
                    ? service.pillSample(at: musicManager.estimatedPlaybackPosition(at: context.date), includeTranslation: !originalOnly)
                    : nil
                LyricsPillGate(
                    input: LyricsPillVisibility.Input(
                        isEnabled: enabled, isNotchClosed: isNotchClosed, isPlaying: musicManager.isPlaying,
                        hasLyrics: service.status == .loaded, hasCurrentText: sample != nil
                    ),
                    heldLine: sample?.line,
                    apply: apply
                ) {
                    LyricsPillView(
                        sample: sample, isVisible: visibility.isVisible, isTicking: eligible && musicManager.isPlaying,
                        style: style, motion: NotchMotion.current,
                        passThroughOpacity: isPassingThrough ? Self.passThroughOpacity : 1,
                        positionAt: { musicManager.estimatedPlaybackPosition(at: $0) }
                    )
                }
            }
            .frame(width: CGFloat(maxWidth), height: LyricsPillMetrics.twoLineHeight, alignment: .top)

            if !passThroughEnabled, visibility.isVisible, isNotchClosed, size.width > 0 {
                Color.clear
                    .frame(width: size.width, height: size.height)
                    .contentShape(Rectangle())
                    .onHover { onHover($0) }
                    .onTapGesture { onTap() }
            }
        }
        .frame(width: CGFloat(maxWidth), height: LyricsPillMetrics.twoLineHeight, alignment: .top)
        .offset(y: LyricsPillMetrics.topOffset(notchBottom: notchBottom, dropDistance: CGFloat(dropDistance)))
        .background(PillWindowReader(box: windowBox))
        .lyricsTranslationHost(service: service)
        .onChange(of: visibility.isVisible) { _, visible in onVisibleChange(visible) }
        .task(id: passThroughActive) { await runPassThroughPolling() }
        .onDisappear {
            passThrough.reset()
            setPassingThrough(false)
        }
    }

    /// 透過去時膠囊的不透明度：淡到幾乎看不見，底下的分頁才看得到。
    private static let passThroughOpacity = 0.15

    private func pillSize(style: LyricsPillStyle) -> CGSize {
        guard let heldLine else { return .zero }
        return LyricsPillSizing.pillSize(text: heldLine.text, translation: heldLine.translation, style: style)
    }

    // MARK: 滑鼠透過去

    /// 膠囊看得到、瀏海收合、功能開著時才需要定時取樣游標。
    private var passThroughActive: Bool {
        passThroughEnabled && visibility.isVisible && isNotchClosed && heldLine != nil
    }

    /// 約 20 Hz 取樣游標；不需要時（任務被取消或條件不成立）立刻恢復接收滑鼠事件。
    private func runPassThroughPolling() async {
        passThrough.reset()
        guard passThroughActive else {
            setPassingThrough(false)
            return
        }
        while !Task.isCancelled {
            samplePointer()
            try? await Task.sleep(for: .milliseconds(50))
        }
        passThrough.reset()
        setPassingThrough(false)
    }

    private func samplePointer() {
        guard let window = windowBox.window, heldLine != nil else {
            passThrough.reset()
            setPassingThrough(false)
            return
        }
        let rect = LyricsPillPassThrough.pillRect(
            windowFrame: window.frame,
            topOffset: LyricsPillMetrics.topOffset(notchBottom: notchBottom, dropDistance: CGFloat(dropDistance)),
            size: pillSize(style: style)
        )
        let engaged = passThrough.update(
            now: ProcessInfo.processInfo.systemUptime, pointer: NSEvent.mouseLocation,
            pillRect: rect, mouseButtonDown: NSEvent.pressedMouseButtons != 0
        )
        setPassingThrough(engaged)
    }

    /// 只切換「視窗是否接收滑鼠事件」與膠囊淡化；**不能**在這裡重設 `passThrough`，否則每次取樣都會把停留計時歸零。
    private func setPassingThrough(_ engaged: Bool) {
        if isPassingThrough != engaged { isPassingThrough = engaged }
        // 每次都對齊視窗的實際狀態（不只在狀態改變時）：視圖被重建、狀態歸零時，視窗也不會卡在「不接收滑鼠」。
        if let window = windowBox.window, window.ignoresMouseEvents != engaged { window.ignoresMouseEvents = engaged }
    }

    private func apply(_ input: LyricsPillVisibility.Input, line: LyricsPillLine?) {
        if let line { heldLine = line }
        let now = Date.timeIntervalSinceReferenceDate
        visibility.update(input, at: now)
        graceTask?.cancel()
        graceTask = nil
        if let deadline = visibility.hideDeadline {
            graceTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(max(deadline - Date.timeIntervalSinceReferenceDate, 0)))
                guard !Task.isCancelled else { return }
                visibility.tick(at: Date.timeIntervalSinceReferenceDate)
            }
        }
    }
}

/// 把「輸入變了」從 TimelineView 的內容閉包轉成狀態更新（body 裡不能直接改 @State）。
private struct LyricsPillGate<Content: View>: View {
    var input: LyricsPillVisibility.Input
    var heldLine: LyricsPillLine?
    var apply: (LyricsPillVisibility.Input, LyricsPillLine?) -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .onChange(of: input, initial: true) { _, new in apply(new, heldLine) }
            .onChange(of: heldLine) { _, new in if let new { apply(input, new) } }
    }
}

/// 膠囊所在視窗的弱參照（穿透時要設這個視窗的 `ignoresMouseEvents`）。
private final class PillWindowBox {
    weak var window: NSWindow?
}

/// 取得 SwiftUI 視圖所在的 NSWindow（視圖搬進視窗時回報）。
private struct PillWindowReader: NSViewRepresentable {
    var box: PillWindowBox

    func makeNSView(context: Context) -> NSView {
        let view = Reader()
        view.box = box
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? Reader)?.box = box
        box.window = nsView.window
    }

    private final class Reader: NSView {
        var box: PillWindowBox?
        /// 只是用來取得視窗的隱形視圖：不攔截任何滑鼠事件，hover／點擊照常落到它下面的畫面。
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            box?.window = window
        }
    }
}
