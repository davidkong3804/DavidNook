import SwiftUI
import XCTest
@testable import DavidNookUI

/// 對時介面的離屏渲染：預設（常駐小按鈕）、展開、提早／延後、點擊對齊後的回饋、最窄寬度。
/// 輸出 PNG 到 DAVIDNOOK_SNAPSHOT_DIR；歌詞皆為自編句子。
@MainActor
final class LyricsSyncSnapshotTests: XCTestCase {

    private let lines = LyricsPanelLine.make(from: [
        "測試句一，夜行的燈還亮著",
        "測試句二，我們沿著河岸走",
        "測試句三，風把名字吹遠了",
        "測試句四，後來沒有人再問",
        "測試句五，窗口亮起一盞燈",
        "測試句六，雲在遠處慢慢散",
        "測試句七，回家只剩一句話",
    ])

    private func panel(
        width: CGFloat = 240, visibleLines: Int = 5, offsetMs: Int = 0, isOpen: Bool = false, toast: String? = nil
    ) -> some View {
        LyricsPanelView(
            lines: lines, currentIndex: 3, offsetMs: offsetMs, status: .loaded, visibleLineCount: visibleLines,
            sync: LyricsSyncConfiguration(
                isOpen: isOpen, toast: toast,
                onToggle: {}, onAdjust: { _ in }, onReset: {}, onAlignLine: { _ in }
            )
        )
        .frame(width: width, height: LyricsPanelMetrics.height(forVisibleLines: visibleLines))
    }

    @discardableResult
    private func snap<V: View>(_ name: String, width: CGFloat = 240, visibleLines: Int = 5, _ view: V) throws -> Pixels {
        let canvas = CGSize(width: width + 60, height: LyricsPanelMetrics.height(forVisibleLines: visibleLines) + 46)
        let image = try renderImage(NotchBackdrop(size: canvas) { view }.environment(\.offsetWheelEnabled, false))
        let url = try writeSnapshot(image, named: name)
        XCTAssertGreaterThan((try? Data(contentsOf: url).count) ?? 0, 1_000, name)
        return Pixels(image)
    }

    func testDefaultStateShowsAQuietSyncBadgeAtTheCorner() throws {
        let px = try snap("20-sync-default", panel())
        // 右下角（面板右下，scale 2）有小按鈕的像素。
        let h = px.height
        XCTAssertGreaterThan(px.count(rows: (h - 60)...(h - 24), above: 0.2), 20)
    }

    func testExpandedControlsLeaveTheCurrentAndNextLineVisible() throws {
        let px = try snap("21-sync-expanded", panel(isOpen: true))
        XCTAssertGreaterThan(px.maxLuminance(rows: 0...(px.height - 1)), 0.9)
    }

    func testAdvancedAndDelayedOffsets() throws {
        try snap("22-sync-offset-advanced-collapsed", panel(offsetMs: 1_200))
        try snap("23-sync-offset-advanced-expanded", panel(offsetMs: 1_200, isOpen: true))
        try snap("24-sync-offset-delayed-collapsed", panel(offsetMs: -400))
        try snap("25-sync-offset-delayed-expanded", panel(offsetMs: -400, isOpen: true))
    }

    func testToastAfterAligning() throws {
        try snap("26-sync-toast-collapsed", panel(offsetMs: 1_240, toast: OffsetControlStrings.zhHant.aligned))
        try snap("27-sync-toast-expanded", panel(offsetMs: 1_240, isOpen: true, toast: OffsetControlStrings.zhHant.aligned))
    }

    func testNarrowestAndShortestLayouts() throws {
        try snap("28-sync-expanded-min-width", width: 190, panel(width: 190, offsetMs: -1_240, isOpen: true))
        try snap("29-sync-expanded-4-lines", visibleLines: 4, panel(visibleLines: 4, offsetMs: 1_200, isOpen: true))
        try snap("30-sync-collapsed-min-width", width: 190, panel(width: 190, offsetMs: 1_200))
    }
}
