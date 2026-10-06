//
//  ContentView.swift
//  boringNotchApp
//
//  Created by Harsh Vardhan Goswami  on 02/08/24
//  Modified by Richard Kunkli on 24/08/2024.
//

import AVFoundation
import Combine
import DavidNookUI
import Defaults
import KeyboardShortcuts
import SwiftUI

@MainActor
struct ContentView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    /// Which entry of the closed-notch activity stack is on top.
    @State private var activityIndex: Int = 0
    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering: Bool = false

    @State private var gestureProgress: CGFloat = .zero
    @State private var horizontalMediaGestureTriggered = false
    @State private var horizontalMediaGestureFeedback: CGFloat = .zero
    @State private var isHoveringMusicArea = false

    @State private var haptics: Bool = false

    /// Hover 預期動作：游標在觸發區內、尚未達到停留時間時，閉合瀏海輕微鼓起。
    @State private var isAnticipating = false
    /// 形體正在變形（展開／收合／切分頁／調整尺寸）。歌詞面板據此降低更新頻率，避免跟變形搶資源。
    @State private var isMorphing = false
    @State private var morphTask: Task<Void, Never>?

    @Namespace var albumArtNamespace

    @Default(.showNotHumanFace) var showNotHumanFace
    // 設定頁的展開寬度／高度：改變時重新排版（即時生效）。實際數值一律經 NotchSizing 夾限。
    @Default(.openNotchWidth) private var openNotchWidth
    @Default(.openNotchHeightScale) private var openNotchHeightScale
    @Default(.videoCapsuleWidth) private var videoCapsuleWidth
    @ObservedObject private var video = VideoCapsuleController.shared

    // Use standardized animations from StandardAnimations enum
    private let animationSpring = StandardAnimations.interactive

    /// 所有展開／收合／分頁／hover 動畫的參數都來自 NotchMotion（含速度倍率、減少動態、動畫開關）。
    private var motion: NotchMotion { NotchMotion.current }

    private let extendedHoverPadding: CGFloat = 30
    private let zeroHeightHoverPadding: CGFloat = 10
    private let nowPlayingFallbackNoticeWidth: CGFloat = 330
    /// Matches the popovers' dismiss delay; long enough to reach a control
    /// inside the panel without closing under the pointer.
    private let hoverExitDelayMilliseconds = 350

    // MARK: - Corner Radius Scaling
    private var cornerRadiusScaleFactor: CGFloat? {
        guard Defaults[.cornerRadiusScaling] else { return nil }
        let effectiveHeight = displayClosedNotchHeight
        guard effectiveHeight > 0 else { return nil }
        return effectiveHeight / 38.0
    }

    /// Compact mode gets a rounder opened shape (35 vs 19) — at its smaller
    /// size the standard radius reads square rather than pill-like.
    private var openedInsets: (top: CGFloat, bottom: CGFloat) {
        Defaults[.compactMode] ? compactCornerRadiusInsets.opened : cornerRadiusInsets.opened
    }

    private var topCornerRadius: CGFloat {
        // If the notch is open, return the opened radius.
        if vm.notchState == .open {
            return openedInsets.top
        }

        // For the closed notch, scale if enabled
        let baseClosedTop = cornerRadiusInsets.closed.top
        guard let scaleFactor = cornerRadiusScaleFactor else {
            return displayClosedNotchHeight > 0 ? baseClosedTop : 0
        }
        return max(0, baseClosedTop * scaleFactor)
    }

    private var currentNotchShape: NotchShape {
        // Scale bottom corner radius for closed notch shape when scaling is enabled.
        let baseClosedBottom = cornerRadiusInsets.closed.bottom
        let bottomCorner: CGFloat

        if vm.notchState == .open {
            bottomCorner = openedInsets.bottom
        } else if let scaleFactor = cornerRadiusScaleFactor {
            bottomCorner = max(0, baseClosedBottom * scaleFactor)
        } else {
            bottomCorner = displayClosedNotchHeight > 0 ? baseClosedBottom : 0
        }

        return NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCorner
        )
    }

    /// Closed-notch activities, newest first.
    private var liveActivities: [LiveActivityItem] {
        var items: [LiveActivityItem] = []

        let musicIsShowing = (!coordinator.expandingView.show || coordinator.expandingView.type == .music)
            && (musicManager.isPlaying || !musicManager.isPlayerIdle)
            && coordinator.musicLiveActivityEnabled
        if musicIsShowing {
            items.append(.music)
        }

        return items
    }

    // MARK: - Open size (NotchSizing)

    private var sizing: NotchSizing {
        NotchSizing(width: openNotchWidth, heightScale: openNotchHeightScale)
    }

    /// 表頭（分頁列＋瀏海缺口）高度：與 BoringHeader 的 frame 相同。
    private var openHeaderHeight: CGFloat {
        max(NotchSizing.minimumHeaderHeight, displayClosedNotchHeight)
    }

    /// 展開內容寬：形體寬扣掉兩側的耳朵（上緣圓角）與內縮。
    private var openContentWidth: CGFloat {
        sizing.contentWidth(earInset: openedInsets.top)
    }

    private func openBodyHeight(for panel: NotchSizing.Panel) -> CGFloat {
        if panel == .video { return videoLayout.bodyHeight }
        return sizing.bodyHeight(for: panel, headerHeight: openHeaderHeight)
    }

    /// 影片分頁的版面（依使用者寬度與來源長寬比；面板會加高但不超過涵蓋視窗，不改視窗大小）。
    private var videoLayout: VideoCapsuleMetrics.Layout {
        VideoCapsuleMetrics.layout(
            width: videoCapsuleWidth, aspectRatio: video.aspectRatio,
            sizing: sizing, headerHeight: openHeaderHeight, earInset: openedInsets.top
        )
    }

    /// Compact mode drops the tab bar along with the tabs it switches
    /// between — there's only the player to show, so a switcher would have
    /// nothing to switch to. Also what keeps the panel narrow, since the
    /// header spans the full notch width.
    private var showsHeader: Bool {
        vm.notchState == .open
            && !Defaults[.compactMode]
    }

    /// The activity currently on top of the stack — what the chin has to be
    /// sized for.
    private var selectedActivity: LiveActivityItem? {
        let items = liveActivities
        guard !items.isEmpty else { return nil }
        return items[min(max(activityIndex, 0), items.count - 1)]
    }

    private enum ClosedNotchContent: Equatable {
        case hello
        case nowPlayingFallback
        case sneakPeek(SneakContentType)
        case activities([LiveActivityItem])
        case face
        case idle
    }

    private var closedNotchContent: ClosedNotchContent {
        if coordinator.helloAnimationRunning { return .hello }
        if nowPlayingFallbackNoticeActive { return .nowPlayingFallback }
        if coordinator.shouldShowSneakPeek(on: vm.screenUUID) {
            return .sneakPeek(coordinator.sneakPeekState(for: vm.screenUUID).type)
        }
        if !liveActivities.isEmpty, !vm.hideOnClosed {
            return .activities(liveActivities)
        }
        if !coordinator.expandingView.show,
           !musicManager.isPlaying,
           musicManager.isPlayerIdle,
           Defaults[.showNotHumanFace],
           !vm.hideOnClosed {
            return .face
        }
        return .idle
    }

    private var computedChinWidth: CGFloat {
        var chinWidth: CGFloat = vm.closedNotchSize.width

        if shouldDisplayNowPlayingFallbackNotice {
            chinWidth = nowPlayingFallbackNoticeWidth
        } else if vm.notchState == .closed, !vm.hideOnClosed, let activity = selectedActivity {
            // Sized for whichever activity is actually on top.
            switch activity {
            case .music:
                chinWidth += (2 * max(0, displayClosedNotchHeight - 12) + 20 + 2 * liveActivityEdgeMargin + 2)
                // The inline song-change peek widens the pill itself, so the
                // chin has to grow with it — otherwise the hover region is
                // narrower than what's on screen.
                if showingInlineMusicPeek {
                    chinWidth += 2 * inlineMusicPeekLabelWidth
                }
            }
        } else if !coordinator.expandingView.show && vm.notchState == .closed
            && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace]
            && !vm.hideOnClosed {
            chinWidth += (2 * max(0, displayClosedNotchHeight - 12) + 20)
        }

        return chinWidth
    }

    private var shouldDisplayNowPlayingFallbackNotice: Bool {
        vm.notchState == .closed && nowPlayingFallbackNoticeActive
    }

    private var nowPlayingFallbackNoticeActive: Bool {
        guard musicManager.nowPlayingNotice != nil else { return false }

        let selectedScreen = NSScreen.screen(withUUID: coordinator.selectedScreenUUID)
        let targetScreenUUID = selectedScreen?.displayUUID ?? NSScreen.main?.displayUUID
        let currentScreen = vm.screenUUID.flatMap { NSScreen.screen(withUUID: $0) }
        let isConnected = vm.screenUUID == nil || currentScreen != nil
        let isTargetDisplay = vm.screenUUID == nil || vm.screenUUID == targetScreenUUID

        return isConnected
            && isTargetDisplay
            && !isNotchHeightZero
    }

    // If the closed notch height is 0 (any display/setting), display a 10pt nearly-invisible notch
    // instead of fully hiding it. This preserves layout while avoiding visual artifacts.
    private var isNotchHeightZero: Bool { vm.effectiveClosedNotchHeight == 0 }

    private var displayClosedNotchHeight: CGFloat { isNotchHeightZero ? 10 : vm.effectiveClosedNotchHeight }

    private var lyricsPill: some View {
        LyricsPillHost(
            isNotchClosed: vm.notchState == .closed && !vm.hideOnClosed
                && !coordinator.helloAnimationRunning && !shouldDisplayNowPlayingFallbackNotice,
            notchBottom: displayClosedNotchHeight,
            onHover: { handleHover($0) },
            onTap: { if vm.notchState == .closed && !shouldDisplayNowPlayingFallbackNotice { doOpen() } }
        )
    }

    var body: some View {
        // Calculate scale based on gesture progress only
        let gestureScale: CGFloat = {
            guard gestureProgress != 0 else { return 1.0 }
            let scaleFactor = 1.0 + gestureProgress * 0.01
            return max(0.6, scaleFactor)
        }()

        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                let mainLayout = NotchLayout()
                    .frame(alignment: .top)
                    .padding(
                        .horizontal,
                        vm.notchState == .open ? openedInsets.top : cornerRadiusInsets.closed.bottom
                    )
                    .padding([.horizontal, .bottom], vm.notchState == .open ? 12 : 0)
                    .background(.black)
                    .clipShape(currentNotchShape)
                          .overlay(alignment: .top) {
                              displayClosedNotchHeight.isZero && vm.notchState == .closed ? nil
                        : Rectangle()
                            .fill(.black)
                            .frame(height: 1)
                            .padding(.horizontal, topCornerRadius)
                    }
                    .shadow(
                        color: ((vm.notchState == .open || isHovering) && Defaults[.enableShadow])
                            ? .black.opacity(0.7) : .clear, radius: 6
                    )
                    // Removed conditional bottom padding when using custom 0 notch to keep layout stable
                    .opacity((isNotchHeightZero && vm.notchState == .closed) ? 0.01 : 1)
                    // Hover 預期動作：鼓起的是「畫面」（錨點上緣中央），不改版面，也不改 hover 觸發區，所以不會因鼓起而抖動。
                    // 這個 animation 最靠近 isAnticipating，所以展開瞬間「復原」用預期彈簧接手速度，與展開彈簧銜接不跳動。
                    .scaleEffect(isAnticipating ? motion.anticipationScale : 1, anchor: .top)
                    .animation(motion.animation(.anticipate), value: isAnticipating)

                mainLayout
                    .conditionalModifier(true) { view in
                        return view
                            .animation(motion.animation(vm.notchState == .open ? .open : .close), value: vm.notchState)
                            // 設定頁拖動展開寬度／高度滑桿時，形體用分頁切換的彈簧跟著變形。
                            .animation(motion.animation(.tabSwitch), value: sizing)
                            .animation(.smooth, value: gestureProgress)
                            // Outermost on purpose: it only fires when the
                            // closed-state content changes (the key is stable
                            // across open/close), and when several keys change
                            // at once the innermost animation wins, so the
                            // open/close springs below keep precedence.
                            .animation(.smooth(duration: 0.3), value: closedNotchContent)
                    }
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        handleHover(hovering)
                    }
                    .onTapGesture {
                        if vm.notchState == .closed && !shouldDisplayNowPlayingFallbackNotice {
                            doOpen()
                        }
                    }
                    .conditionalModifier(Defaults[.enableGestures] && !shouldDisplayNowPlayingFallbackNotice) { view in
                        view
                            .panGesture(direction: .down) { translation, phase in
                                handleDownGesture(translation: translation, phase: phase)
                            }
                    }
                    .conditionalModifier(Defaults[.closeGestureEnabled] && Defaults[.enableGestures] && !shouldDisplayNowPlayingFallbackNotice) { view in
                        view
                            .panGesture(direction: .up) { translation, phase in
                                handleUpGesture(translation: translation, phase: phase)
                            }
                    }
                    .conditionalModifier(Defaults[.enableHorizontalMediaGestures] && Defaults[.enableGestures] && !shouldDisplayNowPlayingFallbackNotice) { view in
                        view
                            .panGesture(direction: .left) { translation, phase in
                                handleNextTrackGesture(translation: translation, phase: phase)
                            }
                            .panGesture(direction: .right) { translation, phase in
                                handlePreviousTrackGesture(translation: translation, phase: phase)
                            }
                    }
                    // Activities disappear on their own (music stops). Keep
                    // the selection in range so the stack falls back to
                    // whatever is left instead of pointing past the end.
                    .onChange(of: liveActivities.count) { _, count in
                        if activityIndex >= count { activityIndex = max(count - 1, 0) }
                    }
                    .onChange(of: vm.isPopoverActive) { _, _ in
                        scheduleCloseIfNotHovering(overNotch: vm)
                    }
                    .onChange(of: vm.notchState) { _, state in
                        // 真正展開／收合後預期動作就結束了（鼓起的比例隨展開彈簧回到 1）。
                        isAnticipating = false
                        beginMorph(for: state == .open ? motion.openSettleTime : motion.closeSettleTime)
                    }
                    .onChange(of: coordinator.currentView) { _, _ in
                        beginMorph(for: motion.settleTime(for: .tabSwitch))
                    }
                    .onChange(of: sizing) { _, _ in
                        beginMorph(for: motion.settleTime(for: .tabSwitch))
                    }
                    .sensoryFeedback(.alignment, trigger: haptics)
                    .contextMenu {
                        Button("Settings") {
                            DispatchQueue.main.async {
                                SettingsWindowController.shared.showWindow()
                            }
                        }
                        .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
                        //                    Button("Edit") { // Doesnt work....
                        //                        let dn = DynamicNotch(content: EditPanelView())
                        //                        dn.toggle()
                        //                    }
                        //                    .keyboardShortcut("E", modifiers: .command)
                    }
                if vm.chinHeight > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.01))
                        .frame(width: computedChinWidth, height: vm.chinHeight)
                }
            }
        }
        // 收合瀏海下方的歌詞膠囊：畫在既有視窗範圍內（不改視窗大小）；hover／點擊轉接給瀏海。
        .overlay(alignment: .top) { lyricsPill }
        .padding(.bottom, 8)
        .frame(
            maxWidth: NotchSizing.coveringWindowSize.width,
            maxHeight: NotchSizing.coveringWindowSize.height,
            alignment: .top
        )
        .ignoresSafeArea(.all)
        .compositingGroup()
        .scaleEffect(
            x: gestureScale,
            y: gestureScale,
            anchor: .top
        )
        .animation(.smooth, value: gestureProgress)
        .preferredColorScheme(.dark)
        .environment(\.notchIsMorphing, isMorphing)
        .environmentObject(vm)
    }

    @ViewBuilder
    func NotchLayout() -> some View {
        // spacing: 0 —— 展開時表頭與內容區之間的距離由 NotchSizing 的高度預算決定（閉合時只有一個子視圖，不受影響）。
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading) {
                if coordinator.helloAnimationRunning {
                    Spacer()
                    HelloAnimation(onFinish: {
                        vm.closeHello()
                    }).frame(
                        width: getClosedNotchSize().width,
                        height: 80
                    )
                    .padding(.top, 40)
                    Spacer()
                } else {
                    if shouldDisplayNowPlayingFallbackNotice,
                       let notice = musicManager.nowPlayingNotice {
                        nowPlayingFallbackNotice(notice)
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                      } else if !liveActivities.isEmpty && vm.notchState == .closed && !vm.hideOnClosed {
                          LiveActivityStack(items: liveActivities, index: $activityIndex) { item in
                              switch item {
                              case .music:
                                  MusicLiveActivity()
                                      .frame(alignment: .center)
                              }
                          }
                      } else if !coordinator.expandingView.show && vm.notchState == .closed && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace] && !vm.hideOnClosed {
                          BoringFaceAnimation()
                       } else if showsHeader {
                           BoringHeader()
                               .frame(width: openContentWidth, height: openHeaderHeight)
                               .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
                               .transition(.notchContent(motion))
                       }
                        // New case to enable compact notch on external displays
                        else if !vm.hasNotch {
                           Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: 11) // idle notch height is halved on non notch display
                       } else {
                           Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: displayClosedNotchHeight)
                       }

                        if coordinator.shouldShowSneakPeek(on: vm.screenUUID) {
                           // Old sneak peek music
                           if coordinator.sneakPeekState(for: vm.screenUUID).type == .music {
                               if vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard {
                                   HStack(alignment: .center) {
                                       Image(systemName: "music.note")
                                       GeometryReader { geo in
                                           MarqueeText(musicManager.songTitle + " - " + musicManager.artistName, color: Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray, delayDuration: 1.0, frameWidth: geo.size.width)
                                       }
                                   }
                                   .foregroundStyle(.gray)
                                   .padding(.bottom, 10)
                               }
                           }
                       }
                        }
                      }
                      .conditionalModifier(coordinator.shouldShowSneakPeek(on: vm.screenUUID) && (coordinator.sneakPeekState(for: vm.screenUUID).type == .music) && vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard) { view in
                          view
                              .fixedSize()
                      }
                      .zIndex(1)
            if vm.notchState == .open {
                VStack {
                    if Defaults[.compactMode] {
                        // Player only — no tab switching, so currentView is
                        // ignored here (the compact layout has no room for
                        // a tab bar).
                        // 336 = Atoll's 420 base less 20%, which also lands
                        // within a few points of their Dynamic Island width
                        // (340) — the tighter of their two compact sizes.
                        CompactHomeView(
                            albumArtNamespace: albumArtNamespace,
                            horizontalMediaGestureFeedback: horizontalMediaGestureFeedback
                        )
                        .frame(width: 336)
                        .onHover { hovering in
                            isHoveringMusicArea = hovering
                        }
                        .onDisappear {
                            isHoveringMusicArea = false
                        }
                    } else {
                        // 內容以「最終尺寸」固定排版，外層形體的彈簧變形只負責揭露它（不會在展開途中重新折行）。
                        ZStack(alignment: .top) {
                            switch coordinator.currentView {
                            case .home:
                                NotchHomeView(
                                    albumArtNamespace: albumArtNamespace,
                                    horizontalMediaGestureFeedback: horizontalMediaGestureFeedback,
                                    isHoveringMusicArea: $isHoveringMusicArea,
                                    contentWidth: openContentWidth,
                                    bodyHeight: openBodyHeight(for: .home)
                                )
                                .frame(width: openContentWidth, height: openBodyHeight(for: .home), alignment: .top)
                                .transition(.opacity)
                            case .clipboard:
                                ClipboardTabView()
                                    .frame(width: openContentWidth, height: openBodyHeight(for: .clipboard), alignment: .top)
                                    .transition(.opacity)
                            case .video:
                                VideoTabView(layout: videoLayout)
                                    .frame(width: openContentWidth, height: openBodyHeight(for: .video), alignment: .top)
                                    .transition(.opacity)
                            }
                        }
                        .frame(
                            width: openContentWidth,
                            height: openBodyHeight(for: coordinator.currentView.sizingPanel),
                            alignment: .top
                        )
                    }
                }
                // 內容層：展開時延遲約 0.09 秒才淡入（blur 10→0、scale 0.97→1、下移 4pt→0），
                // 收合時立刻快速淡出——形體先長出來，內容再浮現。數值全部在 NotchMotion。
                .transition(.notchContent(motion))
                .zIndex(1)
                .allowsHitTesting(vm.notchState == .open)
                .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
            }
        }
    }

    private func nowPlayingFallbackNotice(_ notice: NowPlayingFallbackNotice) -> some View {
        HStack(spacing: 11) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.orange)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Text(notice.subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
            }
            .lineLimit(2)

            Spacer(minLength: 5)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(width: nowPlayingFallbackNoticeWidth)
        .frame(minHeight: 58)
        .accessibilityElement(children: .combine)
        .onAppear {
            if musicManager.markNowPlayingNoticePresented(notice.id) {
                announceNowPlayingFallbackNotice(notice)
            }
        }
    }

    private func announceNowPlayingFallbackNotice(_ notice: NowPlayingFallbackNotice) {
        let announcement = "\(String(localized: notice.title)). \(String(localized: notice.subtitle))."
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: announcement,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }

    @ViewBuilder
    func BoringFaceAnimation() -> some View {
        HStack {
            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 20)
            let faceScale = min(1.0, displayClosedNotchHeight / 30.0)
            AnimatedFace(height: 24.0 * faceScale, width: 30.0 * faceScale)
        }.frame(
            height: displayClosedNotchHeight,
            alignment: .center
        )
    }

    /// True while the song-change peek is expanding the closed pill inline.
    private var showingInlineMusicPeek: Bool {
        coordinator.expandingView.show
            && coordinator.expandingView.type == .music
            && Defaults[.sneakPeekStyles] == .inline
    }

    /// Width of the black centre section of the closed music pill.
    ///
    /// Derived from the real notch width rather than the previous hard-coded
    /// 380. That constant assumed a particular notch size: the title sits
    /// left of the cutout and the artist right of it, separated by a spacer
    /// as wide as the notch itself, so on a wider notch there was no room
    /// left for the artist and the labels collided. Sizing from
    /// closedNotchSize keeps a fixed label budget either side whatever the
    /// hardware is, and keeps liveActivityEdgeMargin in play so content
    /// clears the bezel — the inline path had dropped it entirely.
    private var musicActivityCenterWidth: CGFloat {
        let margin = vm.closedNotchSize.width - 4 + (2 * liveActivityEdgeMargin)
        guard showingInlineMusicPeek else { return margin }
        return margin + (2 * inlineMusicPeekLabelWidth)
    }

    /// Space reserved for the title (left of the cutout) and artist (right).
    private let inlineMusicPeekLabelWidth: CGFloat = 110

    @ViewBuilder
    func MusicLiveActivity() -> some View {
        HStack(spacing: 0) {
            // Closed-mode album art: scale padding and corner radius according to cornerRadiusScaleFactor
            let baseArtSize = displayClosedNotchHeight - 12
            let scaledArtSize: CGFloat = {
                if let scale = cornerRadiusScaleFactor {
                    return displayClosedNotchHeight - 12 * scale
                }
                return baseArtSize
            }()
            // The art's top/bottom gap to the pill; the leading offset below
            // trims the row's edge slack down to this same inset.
            let artVerticalInset = (displayClosedNotchHeight - scaledArtSize) / 2

            let closedCornerRadius: CGFloat = {
                let base = MusicPlayerImageSizes.cornerRadiusInset.closed
                if let scale = cornerRadiusScaleFactor {
                    return max(0, base * scale)
                }
                return base
            }()

            Image(nsImage: musicManager.albumArt)
                .resizable().scaledToFit()
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: closedCornerRadius)
                )
                .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                .frame(
                    width: scaledArtSize,
                    height: scaledArtSize
                )
                .offset(x: artVerticalInset - liveActivityEdgeMargin)

            Rectangle()
                .fill(.black)
                .overlay(
                    // .center, not .top: the album art beside this is
                    // vertically centered, so top-aligned labels sat visibly
                    // high against it.
                    HStack(alignment: .center) {
                        if coordinator.expandingView.show
                            && coordinator.expandingView.type == .music {
                            MarqueeText(
                                musicManager.songTitle,
                                color: Defaults[.coloredSpectrogram]
                                    ? Color(nsColor: musicManager.avgColor) : Color.gray,
                                delayDuration: 0.4,
                                frameWidth: inlineMusicPeekLabelWidth
                            )
                            .opacity(
                                (coordinator.expandingView.show
                                    && Defaults[.sneakPeekStyles] == .inline)
                                    ? 1 : 0
                            )
                            Spacer(minLength: vm.closedNotchSize.width)
                            // Song Artist
                            Text(musicManager.artistName)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(width: inlineMusicPeekLabelWidth, alignment: .trailing)
                                .foregroundStyle(
                                    Defaults[.coloredSpectrogram]
                                        ? Color(nsColor: musicManager.avgColor)
                                        : Color.gray
                                )
                                .opacity(
                                    (coordinator.expandingView.show
                                        && coordinator.expandingView.type == .music
                                        && Defaults[.sneakPeekStyles] == .inline)
                                        ? 1 : 0
                                )
                        }
                    }
                    .padding(.horizontal, 8)
                )
                .frame(width: musicActivityCenterWidth)

            HStack {
                MusicVisualizer(
                    isPlaying: musicManager.isPlaying,
                    tintColor: Defaults[.coloredSpectrogram]
                    ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.5)
                    : Color.gray
                )
                .frame(width: 18, height: 12)
            }
            .frame(
                width: max(
                    0,
                    displayClosedNotchHeight - 12
                        + gestureProgress / 2
                ),
                height: max(
                    0,
                    displayClosedNotchHeight - 12
                ),
                alignment: .center
            )
        }
        .frame(
            height: displayClosedNotchHeight,
            alignment: .center
        )
    }

}
// MARK: - Gesture & Hover Handling

extension ContentView {
    @discardableResult
    private func doOpen() -> Bool {
        var didOpen = false
        withAnimation(motion.animation(.open)) {
            didOpen = vm.open()
            // 預期鼓起與展開同一個 transaction 結束：比例從 1.04 隨彈簧回到 1，與形體展開銜接。
            isAnticipating = false
        }
        return didOpen
    }

    /// 標記「形體正在變形」，`settle` 秒後（再多留一點餘裕）解除。連續觸發時以最後一次為準。
    private func beginMorph(for settle: TimeInterval) {
        morphTask?.cancel()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { isMorphing = true }
        morphTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(settle + 0.1))
            guard !Task.isCancelled else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { isMorphing = false }
        }
    }

    // MARK: - Hover Management

    /// Closes the open notch after the hover grace period unless a popover
    /// still owns the pointer.
    private func scheduleCloseIfNotHovering(overNotch notchViewModel: BoringViewModel) {
        guard notchViewModel.notchState == .open,
              !isHovering,
              !notchViewModel.isPopoverActive else { return }
        hoverTask?.cancel()
        hoverTask = Task {
            try? await Task.sleep(for: .milliseconds(hoverExitDelayMilliseconds))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if self.vm.notchState == .open,
                   !self.isHovering,
                   !self.vm.isPopoverActive {
                    self.vm.close()
                }
            }
        }
    }

    private func handleHover(_ hovering: Bool) {
        if coordinator.firstLaunch { return }
        hoverTask?.cancel()

        if hovering {
            withAnimation(animationSpring) {
                isHovering = true
            }

            if vm.notchState == .closed && Defaults[.enableHaptics] {
                haptics.toggle()
            }

            guard vm.notchState == .closed,
                  !shouldDisplayNowPlayingFallbackNotice,
                  !coordinator.shouldShowSneakPeek(on: vm.screenUUID),
                  Defaults[.openNotchOnHover] else { return }

            // 預期動作：停留時間幾乎為 0 時直接展開，不先鼓一下。
            if Defaults[.minimumHoverDuration] > 0.05 {
                isAnticipating = true
            }

            hoverTask = Task {
                try? await Task.sleep(for: .seconds(Defaults[.minimumHoverDuration]))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard self.vm.notchState == .closed,
                          self.isHovering,
                          !self.shouldDisplayNowPlayingFallbackNotice,
                          !self.coordinator.shouldShowSneakPeek(on: self.vm.screenUUID) else { return }

                    self.doOpen()
                }
            }
        } else {
            // 游標離開：預期鼓起立即回彈復原（收合的延遲只針對「已展開」的瀏海）。
            isAnticipating = false

            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(hoverExitDelayMilliseconds))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    withAnimation(animationSpring) {
                        self.isHovering = false
                    }

                    if self.vm.notchState == .open,
                       !self.vm.isPopoverActive {
                        self.vm.close()
                    }
                }
            }
        }
    }

    // MARK: - Gesture Handling

    private func handleDownGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .closed else { return }
        // 滑鼠在歌詞對時控制上：滾輪是拿來微調偏移的，不當成手勢（結束事件照常處理，避免進度卡住）。
        guard phase == .ended || !LyricsSyncPointer.isOverControl else { return }

        if phase == .ended {
            withAnimation(animationSpring) { gestureProgress = .zero }
            return
        }

        withAnimation(animationSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * 20
        }

        if translation > Defaults[.gestureSensitivity] {
            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
            doOpen()
        }
    }

    private func handleUpGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .open else { return }
        // 滑鼠在歌詞對時控制上：滾輪往上捲是微調偏移，不能把瀏海關掉。
        guard phase == .ended || !LyricsSyncPointer.isOverControl else { return }

        withAnimation(animationSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * -20
        }

        if phase == .ended {
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
        }

        if translation > Defaults[.gestureSensitivity] {
            withAnimation(animationSpring) {
                isHovering = false
            }
            gestureProgress = .zero
            vm.close()

            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
        }
    }

    private func handleNextTrackGesture(translation: CGFloat, phase: NSEvent.Phase) {
        handleHorizontalMediaGesture(translation: translation, phase: phase, feedback: -1) {
            musicManager.nextTrack()
        }
    }

    private func handlePreviousTrackGesture(translation: CGFloat, phase: NSEvent.Phase) {
        handleHorizontalMediaGesture(translation: translation, phase: phase, feedback: 1) {
            musicManager.previousTrack()
        }
    }

    private func handleHorizontalMediaGesture(
        translation: CGFloat,
        phase: NSEvent.Phase,
        feedback: CGFloat,
        action: () -> Void
    ) {
        guard isHorizontalMediaGestureContext, phase == .ended || !LyricsSyncPointer.isOverControl else {
            resetHorizontalMediaGesture()
            return
        }
        guard phase != .ended else {
            resetHorizontalMediaGesture()
            return
        }
        guard !horizontalMediaGestureTriggered else { return }
        guard translation > Defaults[.gestureSensitivity] else { return }

        horizontalMediaGestureTriggered = true
        triggerHorizontalMediaFeedback(feedback)
        action()

        if Defaults[.enableHaptics] {
            haptics.toggle()
        }
    }

    private func resetHorizontalMediaGesture() {
        horizontalMediaGestureTriggered = false
    }

    private func triggerHorizontalMediaFeedback(_ feedback: CGFloat) {
        withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.62)) {
            horizontalMediaGestureFeedback = feedback
            if vm.notchState == .closed {
                gestureProgress = 2
            }
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            withAnimation(animationSpring) {
                horizontalMediaGestureFeedback = .zero
                if vm.notchState == .closed {
                    gestureProgress = .zero
                }
            }
        }
    }

    private var isHorizontalMediaGestureContext: Bool {
        switch vm.notchState {
        case .closed:
            guard !vm.hideOnClosed else { return false }

            if coordinator.shouldShowSneakPeek(on: vm.screenUUID) {
                return coordinator.sneakPeekState(for: vm.screenUUID).type == .music
            }

            guard !coordinator.expandingView.show || coordinator.expandingView.type == .music else {
                return false
            }

            return coordinator.musicLiveActivityEnabled && (musicManager.isPlaying || !musicManager.isPlayerIdle)

        case .open:
            if Defaults[.compactMode] {
                return !musicManager.isPlayerIdle && isHoveringMusicArea
            }
            return coordinator.currentView == .home && !musicManager.isPlayerIdle && isHoveringMusicArea
        }
    }
}

#Preview {
    let vm = BoringViewModel()
    vm.open()
    return ContentView()
        .environmentObject(vm)
        .frame(
            width: NotchSizing().openSize(for: .home).width,
            height: NotchSizing().openSize(for: .home).height
        )
}
