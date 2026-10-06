import AppKit
import SwiftUI

/// 收合瀏海外面的「釘選影片膠囊」畫面（只負責外觀；位置由 `VideoCapsulePlacement` 算、可見性由 `VideoCapsuleVisibility` 判斷）。
///
/// - 畫面：與 Home 封面槽共用同一個 `VideoFrameDisplay`（同一條串流、同一個 IOSurface，不開第二條 SCStream）。
/// - 外觀：圓角（`VideoCapsuleMetrics.cornerRadius`）、黑底、極細描邊；hover 時右上角出現小圖釘（只是提示：點一下展開瀏海，
///   取消釘選在展開後的封面槽裡做；這裡**不新增第二種點擊語意**）。
/// - 顯示／收起：淡入淡出＋輕微縮放（沿用 `NotchMotion` 的內容淡入／淡出曲線；「減少動態」只淡入淡出）。
/// - 互動：整個視圖 `allowsHitTesting(false)`；點擊與 hover 由呼叫端另放的同大小透明區域轉接給瀏海（照歌詞膠囊的做法）。
public struct VideoCapsuleView: View {
    var size: CGSize
    var isVisible: Bool
    var isHovering: Bool
    var display: VideoFrameDisplay
    var motion: NotchMotion
    /// 測試／離屏渲染用的假畫面（ImageRenderer 無法渲染 NSViewRepresentable）；正式 App 一律 nil。
    var staticFrame: CGImage?

    public init(
        size: CGSize, isVisible: Bool, isHovering: Bool, display: VideoFrameDisplay, motion: NotchMotion,
        staticFrame: CGImage? = nil
    ) {
        self.size = size; self.isVisible = isVisible; self.isHovering = isHovering
        self.display = display; self.motion = motion; self.staticFrame = staticFrame
    }

    public var body: some View {
        let corner = VideoCapsuleMetrics.cornerRadius(for: size)
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        ZStack(alignment: .topTrailing) {
            ZStack {
                Color.black
                if let staticFrame {
                    Image(decorative: staticFrame, scale: 1).resizable().aspectRatio(contentMode: .fit)
                } else {
                    VideoFrameLayerView(display: display)
                }
            }
            pinBadge
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible || motion.reduceMotion ? 1 : NotchMotion.Constants.hiddenScale, anchor: .top)
        .animation(isVisible ? motion.contentRevealAnimation : motion.contentHideAnimation, value: isVisible)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var pinBadge: some View {
        Image(systemName: "pin.fill")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: 20, height: 20)
            .background(Circle().fill(Color.black.opacity(0.6)))
            .padding(6)
            .opacity(isHovering && isVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: isHovering)
    }
}
