import SwiftUI

/// 資料驅動的歌詞面板：約 5 行可見，目前行白色粗體、其餘行變暗，上下邊緣淡出，換行時平滑捲動。
///
/// 不含網路或播放邏輯——目前行索引由呼叫端依播放位置算好傳入。
///
/// - 長行自動折行；折行後各行高度不同，目前行仍固定在垂直中央。
/// - 空白行（`text` 為空）是間奏：只留白，不畫任何東西；目前行落在空白行時，所有行都維持暗色。
/// - `currentIndex == nil` 代表還沒開始：第一句以暗色出現在中央偏下。
/// - 字型見 `LyricsFont`：中文優先 PingFang TC，英文維持系統字型。
/// - `offsetMs` 非 0 時，右下角顯示小字的偏移量（正值＝歌詞提早）。
public struct LyricsPanelView: View {
    public var lines: [LyricsPanelLine]
    public var currentIndex: Int?
    public var offsetMs: Int
    public var status: LyricsPanelStatus
    public var strings: LyricsPanelStrings
    /// 目前行的字級；其餘行為 `fontSize - 1`。
    public var fontSize: CGFloat
    /// 可見行數（骨架：尚未影響版面）。
    public var visibleLineCount: Int

    public init(
        lines: [LyricsPanelLine],
        currentIndex: Int?,
        offsetMs: Int = 0,
        status: LyricsPanelStatus,
        strings: LyricsPanelStrings = .zhHant,
        fontSize: CGFloat = 14,
        visibleLineCount: Int = 5
    ) {
        self.lines = lines
        self.currentIndex = currentIndex
        self.offsetMs = offsetMs
        self.status = status
        self.strings = strings
        self.fontSize = fontSize
        self.visibleLineCount = visibleLineCount
    }

    /// 目前行是空白行（間奏／結束）時，視為沒有高亮。
    private var highlightedIndex: Int? {
        guard let index = currentIndex, lines.indices.contains(index), !lines[index].isBlank else { return nil }
        return index
    }

    /// 捲動焦點：目前行；尚未開始為 −1（第一句在中央偏下）；超出範圍時夾回。
    private var scrollPosition: Double {
        guard !lines.isEmpty else { return 0 }
        guard let index = currentIndex else { return -1 }
        return Double(min(max(index, 0), lines.count - 1))
    }

    public var body: some View {
        ZStack {
            switch status {
            case .loaded where !lines.isEmpty:
                lyricsBody
            case .loaded:
                message(strings.noLyrics)
            case .loading:
                message(strings.loading)
            case .noLyrics:
                message(strings.noLyrics)
            case .instrumental:
                message(strings.instrumental)
            case .error:
                message(strings.error)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 歌詞

    private var lyricsBody: some View {
        LyricsScrollLayout(position: scrollPosition, spacing: 7) {
            ForEach(lines) { line in
                lineView(line)
            }
        }
        .animation(.smooth(duration: 0.5), value: scrollPosition)
        .clipped()
        .mask(edgeFade)
        .overlay(alignment: .bottomTrailing) { offsetBadge }
    }

    @ViewBuilder
    private func lineView(_ line: LyricsPanelLine) -> some View {
        if line.isBlank {
            // 間奏：只留白（高度約半行）。
            Color.clear.frame(height: fontSize * 0.9)
        } else {
            let isCurrent = highlightedIndex == line.id
            // 離「目前位置」幾行（尚未開始視為在第 −1 行；目前行是空白行時以該空白行為準）。
            let distance = abs(line.id - (currentIndex ?? -1))
            // 用粗體量測所有行，目前行切成粗體時折行與高度不會跳動。
            Text(verbatim: line.text)
                .font(LyricsFont.font(size: fontSize, weight: .bold))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hidden()
                .overlay(alignment: .topLeading) {
                    Text(verbatim: line.text)
                        .font(isCurrent
                              ? LyricsFont.font(size: fontSize, weight: .bold)
                              : LyricsFont.font(size: fontSize - 1, weight: .regular))
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(isCurrent ? Color.white : Color.white.opacity(Self.dimOpacity(distance: distance)))
                }
                .animation(.smooth(duration: 0.35), value: isCurrent)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(line.text)
        }
    }

    /// 離目前行越遠越暗（0.5 → 0.18）。
    static func dimOpacity(distance: Int) -> Double {
        max(0.18, 0.52 - 0.12 * Double(max(distance, 1) - 1))
    }

    private var edgeFade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.2),
                .init(color: .black, location: 0.8),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    @ViewBuilder
    private var offsetBadge: some View {
        if offsetMs != 0 {
            Text(verbatim: LyricsOffsetFormat.label(offsetMs: offsetMs))
                .font(.system(size: 9, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.55))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.12)))
                .padding(2)
        }
    }

    // MARK: - 狀態文案

    private func message(_ text: String) -> some View {
        Text(verbatim: text)
            .font(LyricsFont.font(size: fontSize - 1, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.5))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
    }
}
