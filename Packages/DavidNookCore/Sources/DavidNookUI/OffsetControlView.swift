import SwiftUI

/// 偏移控制的文案；預設為繁體中文，App 可傳入在地化後的字串。
public struct OffsetControlStrings: Equatable, Sendable {
    public var delayHelp: String
    public var advanceHelp: String
    public var reset: String
    public var resetHelp: String
    /// 目前偏移的無障礙標籤前綴（後面接偏移量，例如「目前偏移 +0.5s」）。
    public var currentOffset: String

    public init(delayHelp: String, advanceHelp: String, reset: String, resetHelp: String, currentOffset: String) {
        self.delayHelp = delayHelp
        self.advanceHelp = advanceHelp
        self.reset = reset
        self.resetHelp = resetHelp
        self.currentOffset = currentOffset
    }

    public static let zhHant = OffsetControlStrings(
        delayHelp: "歌詞延後 0.5 秒",
        advanceHelp: "歌詞提早 0.5 秒",
        reset: "重設",
        resetHelp: "重設歌詞偏移",
        currentOffset: "目前偏移"
    )
}

/// 歌詞偏移控制：「−0.5s」「+0.5s」「重設」，中間顯示目前偏移秒數。只回呼，不保存狀態。
///
/// 方向約定與 Core 相同：**正值＝歌詞提早顯示**。歌詞比聲音慢（句子出現得太晚）就按 +；太早就按 −。
public struct OffsetControlView: View {
    public var offsetMs: Int
    /// 以毫秒為單位的增減量（−500 或 +500）。
    public var onAdjust: (Int) -> Void
    public var onReset: () -> Void
    public var strings: OffsetControlStrings

    public init(
        offsetMs: Int,
        strings: OffsetControlStrings = .zhHant,
        onAdjust: @escaping (Int) -> Void,
        onReset: @escaping () -> Void
    ) {
        self.offsetMs = offsetMs
        self.strings = strings
        self.onAdjust = onAdjust
        self.onReset = onReset
    }

    public var body: some View {
        HStack(spacing: 4) {
            chip("\u{2212}0.5s", help: strings.delayHelp) { onAdjust(-LyricsOffsetFormat.stepMs) }
            Text(verbatim: LyricsOffsetFormat.label(offsetMs: offsetMs))
                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(offsetMs == 0 ? Color.white.opacity(0.55) : Color.white)
                .frame(minWidth: 38)
                .accessibilityLabel(Text(verbatim: "\(strings.currentOffset) \(LyricsOffsetFormat.label(offsetMs: offsetMs))"))
            chip("+0.5s", help: strings.advanceHelp) { onAdjust(LyricsOffsetFormat.stepMs) }
            chip(strings.reset, help: strings.resetHelp) { onReset() }
                .disabled(offsetMs == 0)
                .opacity(offsetMs == 0 ? 0.4 : 1)
        }
    }

    private func chip(_ title: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.9))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.16)))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
