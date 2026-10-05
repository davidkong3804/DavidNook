import SwiftUI

/// 讓「焦點位置」落在容器垂直中央（或 `focus` 指定比例）的直式排版：各行以容器寬度折行、依實際高度堆疊，
/// 再整體平移，使 `position`（可為小數的行索引）對應的點位於中央。
///
/// - `position` 是 `animatableData`：換行時以動畫插值，就是平滑捲動；每一幀都由排版本身算出，
///   不需要事先量測行高，所以離屏渲染（`ImageRenderer`）也是一次排版就得到正確結果。
/// - 超出 0…n−1 的位置以首行／末行的行距外推（例如「第一行之前」把焦點放在 −1，讓第一句出現在中央偏下）。
/// - 子視圖可能被排到容器外面，呼叫端負責 `.clipped()`／遮罩。
struct LyricsScrollLayout: Layout {
    var position: Double
    var spacing: CGFloat
    /// 焦點落在容器高度的哪個比例（預設 0.5＝正中央；偶數行的面板會略為上移，見 `LyricsPanelMetrics.focusFraction`）。
    var focus: CGFloat = 0.5

    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 240, height: proposal.height ?? 120)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let width = bounds.width
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        let tops = Self.tops(heights: heights, spacing: spacing, position: position, midY: bounds.height * focus)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX, y: bounds.minY + tops[index]),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: heights[index])
            )
        }
    }

    /// 各行頂端的 y 座標（相對於容器頂端），使 `position` 對應的點落在 `midY`。純函式，便於測試。
    static func tops(heights: [CGFloat], spacing: CGFloat, position: Double, midY: CGFloat) -> [CGFloat] {
        guard !heights.isEmpty else { return [] }
        var tops: [CGFloat] = []
        var y: CGFloat = 0
        for height in heights {
            tops.append(y)
            y += height + spacing
        }
        func centerY(_ index: Int) -> CGFloat { tops[index] + heights[index] / 2 }

        let last = heights.count - 1
        let focus: CGFloat
        if position <= 0 {
            focus = centerY(0) + CGFloat(position) * (heights[0] + spacing)
        } else if position >= Double(last) {
            focus = centerY(last) + CGFloat(position - Double(last)) * (heights[last] + spacing)
        } else {
            let lower = Int(position.rounded(.down))
            let fraction = CGFloat(position - Double(lower))
            focus = centerY(lower) + (centerY(lower + 1) - centerY(lower)) * fraction
        }
        let shift = midY - focus
        return tops.map { $0 + shift }
    }
}
