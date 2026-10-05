import SwiftUI

/// 內容層外觀（不透明度、模糊、縮放、位移）套用到任意視圖；縮放錨點為上緣中央。
public struct NotchContentStyleModifier: ViewModifier {
    public var style: NotchMotion.ContentStyle

    public init(style: NotchMotion.ContentStyle) {
        self.style = style
    }

    public func body(content: Content) -> some View {
        content
            .opacity(style.opacity)
            .blur(radius: style.blur)
            .scaleEffect(style.scale, anchor: .top)
            .offset(y: style.offsetY)
    }
}

extension AnyTransition {
    /// 展開面板內容層的進出場：進場延遲後淡入（去模糊、放大、上移歸位），出場無延遲快速淡出。
    /// 動畫掛在轉場本身，所以不受外層形體彈簧影響；曲線與時間全部來自 `NotchMotion`。
    public static func notchContent(_ motion: NotchMotion) -> AnyTransition {
        let hidden = NotchContentStyleModifier(style: motion.hiddenContentStyle)
        let shown = NotchContentStyleModifier(style: .shown)
        return .asymmetric(
            insertion: AnyTransition.modifier(active: hidden, identity: shown).animation(motion.contentRevealAnimation),
            removal: AnyTransition.modifier(active: hidden, identity: shown).animation(motion.contentHideAnimation)
        )
    }
}
