//
//  VideoCapsuleHost.swift
//  DavidNook
//
//  收合瀏海正下方的「釘選影片膠囊」（M-C）。由 ContentView 放在歌詞膠囊旁邊，畫在既有視窗範圍內（不改視窗大小）。
//
//  - 可見性：Core 的 `VideoCapsuleVisibility`（功能開＋收合＋已釘選＋串流中且非黑畫面）。展開時不顯示（影片在封面槽，不重複）。
//  - 位置：`VideoCapsulePlacement`（委託 `VideoCapsuleStack.layout`）。歌詞膠囊可見時在其下方（間距 6），不可見時上移到歌詞位置；
//    位置／尺寸變化用瀏海的 tabSwitch 彈簧動畫，只改 SwiftUI 版面，絕不對 NSWindow setFrame。
//  - 畫面：與封面槽共用 `VideoCapsuleController.display`（同一條 SCStream）。
//  - 互動（照歌詞膠囊的做法）：膠囊視覺 `allowsHitTesting(false)`；膠囊可見時另放一塊同大小的透明區域，
//    hover 轉接給瀏海的 `handleHover`、點擊轉接 `doOpen()`；所以滑鼠移到膠囊上等同移到瀏海。
//    因為視覺層不吃事件、透明區域只存在於膠囊可見期間，不會影響既有手勢。
//

import DavidNookCore
import DavidNookUI
import Defaults
import SwiftUI

struct VideoCapsuleHost: View {
    /// 瀏海目前是收合狀態，且沒有被隱藏／歡迎動畫／提示佔用。
    var isNotchClosed: Bool
    /// 瀏海底緣離視窗上緣的距離（pt）。
    var notchBottom: CGFloat
    /// 歌詞膠囊目前是否可見（決定堆疊位置）。
    var lyricsVisible: Bool
    var onHover: (Bool) -> Void
    var onTap: () -> Void

    @ObservedObject private var controller = VideoCapsuleController.shared
    @Default(.videoCapsuleEnabled) private var enabled
    @Default(.videoCapsulePinned) private var pinned
    @Default(.videoCapsuleWidth) private var width
    @Default(.lyricsPillDropDistance) private var dropDistance

    @State private var heldRect: CGRect?
    @State private var hovering = false

    var body: some View {
        let visible = VideoCapsuleVisibility.isVisible(isEnabled: enabled, isNotchClosed: isNotchClosed, isPinned: pinned, state: controller.state)
        let live = VideoCapsulePlacement.rect(
            isVisible: visible, notchBottom: notchBottom, dropDistance: CGFloat(dropDistance), lyricsVisible: lyricsVisible,
            videoWidth: width, aspectRatio: controller.state.slotAspectRatio ?? VideoCapsuleMetrics.fallbackAspectRatio
        )
        // 淡出期間沿用最後的位置與大小，膠囊原地淡出。
        let rect = live ?? heldRect
        let motion = NotchMotion.current
        ZStack(alignment: .top) {
            if let rect {
                VideoCapsuleView(
                    size: rect.size, isVisible: live != nil, isHovering: hovering,
                    display: controller.display, motion: motion
                )
                if live != nil {
                    Color.clear
                        .frame(width: rect.width, height: rect.height)
                        .contentShape(Rectangle())
                        .onHover { inside in
                            hovering = inside
                            onHover(inside)
                        }
                        .onTapGesture { onTap() }
                }
            }
        }
        .frame(width: rect?.width ?? 0, height: rect?.height ?? 0, alignment: .top)
        .offset(y: rect?.minY ?? 0)
        .animation(motion.animation(.tabSwitch), value: rect)
        .onChange(of: live, initial: true) { _, new in
            if let new { heldRect = new } else { hovering = false }
        }
    }
}
