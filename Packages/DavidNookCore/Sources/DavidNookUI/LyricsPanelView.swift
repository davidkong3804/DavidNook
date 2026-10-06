import SwiftUI

/// 資料驅動的歌詞面板：預設約 5 行可見（`visibleLineCount` 可調），目前行白色粗體、其餘行變暗，上下邊緣淡出，換行時平滑捲動。
///
/// 不含網路或播放邏輯——目前行索引由呼叫端依播放位置算好傳入。
///
/// - 長行自動折行；折行後各行高度不同，目前行仍固定在垂直中央。
/// - 空白行（`text` 為空）是間奏：只留白，不畫任何東西；目前行落在空白行時，所有行都維持暗色。
/// - `currentIndex == nil` 代表還沒開始：第一句以暗色出現在中央偏下。
/// - 字型見 `LyricsFont`：中文優先 PingFang TC，英文維持系統字型。
/// - `offsetMs` 非 0 時，右下角顯示小字的偏移量（正值＝歌詞提早）。
/// - 傳入 `sync`（`LyricsSyncConfiguration`）後，右下角改為常駐的「對時」小按鈕；點開展開對時控制，
///   並可點歌詞行把該行對齊到目前播放位置。沒有傳入時行為與舊版相同。
public struct LyricsPanelView: View {
    public var lines: [LyricsPanelLine]
    public var currentIndex: Int?
    public var offsetMs: Int
    public var status: LyricsPanelStatus
    public var strings: LyricsPanelStrings
    /// 目前行的字級；其餘行為 `fontSize - 1`。
    public var fontSize: CGFloat
    /// 可見行數（預設 5；高度不足時由呼叫端降為 4）。面板高度由它決定，見 `LyricsPanelMetrics`。
    public var visibleLineCount: Int
    /// 對時（偏移微調＋點歌詞對齊）。nil＝沒有對時功能，只在偏移非 0 時顯示一個靜態小標籤。
    public var sync: LyricsSyncConfiguration?

    @State private var isHovering = false
    @State private var hoveredLineID: Int?

    public init(
        lines: [LyricsPanelLine],
        currentIndex: Int?,
        offsetMs: Int = 0,
        status: LyricsPanelStatus,
        strings: LyricsPanelStrings = .zhHant,
        fontSize: CGFloat = 14,
        visibleLineCount: Int = 5,
        sync: LyricsSyncConfiguration? = nil
    ) {
        self.lines = lines
        self.currentIndex = currentIndex
        self.offsetMs = offsetMs
        self.status = status
        self.strings = strings
        self.fontSize = fontSize
        self.visibleLineCount = LyricsPanelMetrics.clampedVisibleLines(visibleLineCount)
        self.sync = sync
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
        .frame(maxWidth: .infinity)
        .frame(height: panelHeight)
        .onHover { isHovering = $0 }
    }

    /// 面板高度：由可見行數決定（5 行 = 124 pt，4 行 = 100 pt）。
    private var panelHeight: CGFloat {
        LyricsPanelMetrics.height(forVisibleLines: visibleLineCount, fontSize: fontSize)
    }

    // MARK: - 歌詞

    /// 對時控制展開時預留給卡片的高度（含底部留白）；沒展開為 0。
    private var reservedHeight: CGFloat {
        (sync?.isOpen ?? false) ? OffsetControlView.cardHeight + Self.cardBottomPadding : 0
    }

    private static let cardBottomPadding: CGFloat = 2

    private var lyricsBody: some View {
        let reserved = reservedHeight
        let region = LyricsPanelMetrics.scrollRegionHeight(panelHeight: panelHeight, reserved: reserved, fontSize: fontSize)
        let focus = reserved > 0
            ? LyricsPanelMetrics.reservedFocusFraction(regionHeight: region, fontSize: fontSize)
            : LyricsPanelMetrics.focusFraction(forVisibleLines: visibleLineCount, fontSize: fontSize)
        return LyricsScrollLayout(
            position: scrollPosition,
            spacing: LyricsPanelMetrics.lineSpacing,
            focus: focus
        ) {
            ForEach(lines) { line in
                lineView(line)
            }
        }
        .animation(.smooth(duration: 0.5), value: scrollPosition)
        .frame(height: region)
        .clipped()
        .mask(edgeFade(height: region, fadesBottom: reserved == 0))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.smooth(duration: 0.3), value: reserved)
        .overlay(alignment: .bottom) { syncCard }
        .overlay(alignment: .bottomTrailing) { cornerBadge }
        .overlay(alignment: .top) { toast }
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
                .modifier(AlignTapModifier(
                    sync: sync, lineID: line.id, hoveredLineID: $hoveredLineID, hoverID: hoveredLineID
                ))
        }
    }

    /// 離目前行越遠越暗（0.5 → 0.18）。
    static func dimOpacity(distance: Int) -> Double {
        max(0.18, 0.52 - 0.12 * Double(max(distance, 1) - 1))
    }

    /// 上下緣各淡出一行節距（5 行時約 19%，與舊版的 20% 相同）。對時卡片展開時下緣不淡出（由卡片的上緣收邊）。
    private func edgeFade(height: CGFloat, fadesBottom: Bool) -> some View {
        let fade = min(0.35, LyricsPanelMetrics.linePitch(fontSize: fontSize) / height)
        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: fade),
                .init(color: .black, location: fadesBottom ? 1 - fade : 1),
                .init(color: fadesBottom ? .clear : .black, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// 右下角：有對時功能時是常駐的「對時」小按鈕（展開時隱藏）；沒有時只在偏移非 0 顯示靜態標籤。
    @ViewBuilder
    private var cornerBadge: some View {
        if let sync {
            if !sync.isOpen {
                OffsetBadgeButton(
                    offsetMs: offsetMs,
                    strings: sync.strings,
                    isProminent: isHovering,
                    onTap: sync.onToggle,
                    onAdjust: sync.onAdjust,
                    onPointerInside: sync.onPointerInside
                )
                .padding(2)
                .transition(.opacity)
            }
        } else if offsetMs != 0 {
            Text(verbatim: LyricsOffsetFormat.label(offsetMs: offsetMs))
                .font(.system(size: 9, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.55))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.12)))
                .padding(2)
        }
    }

    @ViewBuilder
    private var syncCard: some View {
        if let sync, sync.isOpen {
            OffsetControlView(
                offsetMs: offsetMs,
                strings: sync.strings,
                onAdjust: sync.onAdjust,
                onReset: sync.onReset,
                onClose: sync.onToggle,
                onPointerInside: sync.onPointerInside
            )
            .padding(.horizontal, 2)
            .padding(.bottom, Self.cardBottomPadding)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    @ViewBuilder
    private var toast: some View {
        if let text = sync?.toast {
            LyricsSyncToast(text: text)
                .padding(.top, 3)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
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

// MARK: - 對時設定

/// 歌詞面板的對時功能：常駐小按鈕、展開的控制、點歌詞對齊、回饋。全部是資料與回呼，不含狀態保存。
public struct LyricsSyncConfiguration {
    public var strings: OffsetControlStrings
    /// 對時控制是否展開。展開時單擊歌詞行即對齊；未展開時要雙擊（見 `LyricsLineAlignGesture`）。
    public var isOpen: Bool
    /// 點歌詞對齊後的短暫回饋文字；nil＝不顯示。
    public var toast: String?
    /// 展開／收合。
    public var onToggle: () -> Void
    /// 偏移變化量（毫秒；正值＝提早）。
    public var onAdjust: (Int) -> Void
    public var onReset: () -> Void
    /// 使用者點了第 n 行歌詞（索引對應 `lines`）。
    public var onAlignLine: (Int) -> Void
    /// 滑鼠進出對時控制（App 用來在滾輪調整時暫停外層「上滑關閉」手勢）。
    public var onPointerInside: (Bool) -> Void

    public init(
        strings: OffsetControlStrings = .zhHant,
        isOpen: Bool,
        toast: String? = nil,
        onToggle: @escaping () -> Void,
        onAdjust: @escaping (Int) -> Void,
        onReset: @escaping () -> Void,
        onAlignLine: @escaping (Int) -> Void,
        onPointerInside: @escaping (Bool) -> Void = { _ in }
    ) {
        self.strings = strings
        self.isOpen = isOpen
        self.toast = toast
        self.onToggle = onToggle
        self.onAdjust = onAdjust
        self.onReset = onReset
        self.onAlignLine = onAlignLine
        self.onPointerInside = onPointerInside
    }
}

/// 歌詞行的點擊對齊：單擊（對時展開時）或雙擊（平常）。
///
/// 用 `simultaneousGesture`：點擊只是「附加」在歌詞行上，不會吃掉外層瀏海的拖曳／捲動手勢（上滑關閉、換歌），
/// 也不影響歌詞自動捲動。對時展開時滑鼠移到行上會出現淡淡的底色，提示這一行可以點。
private struct AlignTapModifier: ViewModifier {
    var sync: LyricsSyncConfiguration?
    var lineID: Int
    @Binding var hoveredLineID: Int?
    var hoverID: Int?

    func body(content: Content) -> some View {
        if let sync {
            let count = LyricsLineAlignGesture.tapCount(syncControlsOpen: sync.isOpen)
            content
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.white.opacity(sync.isOpen && hoverID == lineID ? 0.12 : 0))
                        .padding(.horizontal, -3)
                        .padding(.vertical, -1)
                )
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { hoveredLineID = lineID } else if hoveredLineID == lineID { hoveredLineID = nil }
                }
                .help(sync.isOpen ? sync.strings.lineHelp : "")
                .simultaneousGesture(TapGesture(count: count).onEnded { sync.onAlignLine(lineID) })
        } else {
            content
        }
    }
}
