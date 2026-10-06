import DavidNookCore
import SwiftUI
import XCTest
@testable import DavidNookUI

/// 離屏渲染證據（ImageRenderer，輸出到 DAVIDNOOK_SNAPSHOT_DIR，未設定則為暫存目錄）：
/// - 展開／收合影格條：以 `Spring.value` 算出各時間點的寬高、圓角、內容層外觀，渲染形體＋內容。
/// - Home／剪貼簿在預設、最小、最大尺寸下的靜態渲染。
/// - 與舊版 640×190 的並排比較。
///
/// 重要：Home 的封面／播放控制／進度條是尺寸與 App 相同的替身（App 的真實視圖依賴 MusicManager 等單例，無法離屏渲染）；
/// 版面容器（`NotchHomeLayout`／`NotchControlsLayout`）、歌詞面板、剪貼簿面板、`NotchShape` 與所有尺寸都是 App 實際使用的程式。
/// 所有文字皆為自編，沒有真實歌詞或剪貼簿內容。
@MainActor
final class NotchMotionRenderTests: XCTestCase {
    private let motion = NotchMotion()

    // 代表性的閉合形體：浮動瀏海（外接螢幕）常見尺寸；圓角依 cornerRadiusScaling 以 32/38 縮放（上 6、下 14 為基準）。
    private let closedSize = CGSize(width: 193, height: 32)
    private let closedRadii = (top: 6.0 * 32 / 38, bottom: 14.0 * 32 / 38)
    private let openRadii = (top: 19.0, bottom: 24.0)
    private let earInset: CGFloat = 19

    // MARK: - 自編資料

    private let lyricLines = LyricsPanelLine.make(from: [
        "測試句一，夜行的燈還亮著",
        "測試句二，我們沿著河岸走",
        "測試句三，風把名字吹遠了",
        "測試句四，後來沒有人再問",
        "測試句五，窗口亮起一盞燈",
        "測試句六，雲在遠處慢慢散",
        "測試句七，回家只剩一句話",
        "測試句八，故事停在這一行",
    ])

    private func t(_ seconds: Double) -> Date { Date(timeIntervalSince1970: 1_800_000_000 + seconds) }

    private func clipboardModel() -> ClipboardPanelModel {
        ClipboardPanelModel(items: [
            ClipboardItem(text: "會議紀錄範本：日期、出席者、決議事項、待辦清單", now: t(10), isPinned: true, sourceAppBundleID: "test.example.notes"),
            ClipboardItem(text: "ssh deploy@staging.example.test -p 2222", now: t(20), isPinned: true, sourceAppBundleID: "test.example.terminal"),
            ClipboardItem(filePaths: ["/Users/test/Documents/季度報告-2026Q3.pdf"], now: t(80), sourceAppBundleID: "test.example.finder"),
            ClipboardItem(text: "明天下午三點記得帶筆電和轉接頭，順便把投影片的備份放到隨身碟", now: t(70), sourceAppBundleID: "test.example.notes"),
            ClipboardItem(filePaths: ["/Users/test/Pictures/trip/IMG_0001.jpg", "/Users/test/Pictures/trip/IMG_0002.jpg"], now: t(50)),
            ClipboardItem(text: "Meeting notes\n- agenda review\n- budget\n- next steps", now: t(40), sourceAppBundleID: "test.example.notes"),
            ClipboardItem(text: "第七筆資料：用來確認列表可以捲動", now: t(30)),
        ])
    }

    private let appNames: [String: String] = [
        "test.example.notes": "備忘錄",
        "test.example.terminal": "Terminal",
        "test.example.finder": "Finder",
    ]

    // MARK: - 內容（開啟後的面板）

    private func tabHeader(selected: NotchSizing.Panel) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                Image(systemName: "house.fill")
                    .padding(.horizontal, 15).frame(height: 26)
                    .background(Capsule().fill(selected == .home ? Color.white.opacity(0.18) : Color.clear))
                    .foregroundStyle(selected == .home ? Color.white : Color.gray)
                Image(systemName: "doc.on.clipboard")
                    .padding(.horizontal, 15).frame(height: 26)
                    .background(Capsule().fill(selected == .clipboard ? Color.white.opacity(0.18) : Color.clear))
                    .foregroundStyle(selected == .clipboard ? Color.white : Color.gray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Capsule().fill(Color.black).frame(width: 30, height: 30)
                .overlay { Image(systemName: "gear").foregroundStyle(Color.white).imageScale(.medium) }
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func toolbarButton(_ symbol: String, size: CGFloat, symbolSize: CGFloat) -> some View {
        Circle().fill(Color.clear).frame(width: size, height: size)
            .overlay { Image(systemName: symbol).font(.system(size: symbolSize)).foregroundStyle(Color.white) }
    }

    @ViewBuilder
    private func homeBody(_ metrics: NotchHomeMetrics, bounds: Bool = false) -> some View {
        NotchHomeLayout(metrics: metrics) {
            RoundedRectangle(cornerRadius: 13)
                .fill(LinearGradient(colors: [Color(red: 0.95, green: 0.55, blue: 0.2), Color(red: 0.85, green: 0.2, blue: 0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay { Image(systemName: "music.note").font(.system(size: 28)).foregroundStyle(Color.white.opacity(0.8)) }
                .debugBox(bounds, .red)
        } controls: {
            NotchControlsLayout(metrics: metrics) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Text(verbatim: "Midnight Train").font(.headline).foregroundStyle(Color.white).lineLimit(1)
                        RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.16)).frame(width: 20, height: 18)
                    }
                    Text(verbatim: "Sample Artist").font(.headline).fontWeight(.medium).foregroundStyle(Color.gray).lineLimit(1)
                }
                .debugBox(bounds, .green)
            } slider: {
                VStack(spacing: 4) {
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.gray.opacity(0.3)).frame(height: 5)
                        Capsule().fill(Color.white).frame(width: 60, height: 5)
                    }
                    .frame(height: 10)
                    HStack {
                        Text(verbatim: "1:12"); Spacer(); Text(verbatim: "-2:48")
                    }
                    .font(.caption).fontWeight(.medium).foregroundStyle(Color.gray)
                }
                .debugBox(bounds, .blue)
            } toolbar: {
                HStack(spacing: 6) {
                    toolbarButton("shuffle", size: 30, symbolSize: 13)
                    toolbarButton("backward.fill", size: 30, symbolSize: 13)
                    toolbarButton(metrics.density == .regular ? "pause.fill" : "pause.fill", size: metrics.primaryButtonSize,
                                  symbolSize: metrics.density == .regular ? 28 : 13)
                    toolbarButton("forward.fill", size: 30, symbolSize: 13)
                    toolbarButton("repeat", size: 30, symbolSize: 13)
                }
                .debugBox(bounds, .orange)
            }
            .debugBox(bounds, .yellow)
        } lyrics: {
            LyricsPanelView(lines: lyricLines, currentIndex: 3, status: .loaded, visibleLineCount: metrics.lyricsVisibleLines)
                .debugBox(bounds, .purple)
        }
    }

    private func clipboardBody(width: CGFloat, height: CGFloat) -> some View {
        ClipboardPanelView(
            model: clipboardModel(),
            strings: .zhHant,
            thumbnails: ClipboardThumbnailCache(),
            imageURL: { _ in nil },
            appName: { [appNames] in $0.flatMap { appNames[$0] } },
            autoFocusSearch: false
        )
        .environment(\.clipboardStaticRender, true)
        .frame(width: width, height: height)
    }

    /// 開啟後內容層（表頭＋內容區），以「最終尺寸」排版。
    @ViewBuilder
    private func openContent(_ panel: NotchSizing.Panel, sizing: NotchSizing, bounds: Bool = false) -> some View {
        let header = NotchSizing.minimumHeaderHeight
        let cw = sizing.contentWidth(earInset: earInset)
        let body = sizing.bodyHeight(for: panel, headerHeight: header)
        VStack(spacing: 0) {
            tabHeader(selected: panel).frame(width: cw, height: header)
            switch panel {
            case .home:
                homeBody(NotchHomeMetrics(contentWidth: cw, bodyHeight: body, showsLyrics: true), bounds: bounds)
                    .frame(width: cw, height: body, alignment: .top)
            case .clipboard:
                clipboardBody(width: cw, height: body)
            case .video:
                Color.clear.frame(width: cw, height: body)
            }
        }
        .frame(width: cw, alignment: .top)
    }

    /// 一個完整的展開形體（外框＝尺寸模型的 openSize）。
    private func openNotch(_ panel: NotchSizing.Panel, sizing: NotchSizing, bounds: Bool = false) -> some View {
        let size = sizing.openSize(for: panel)
        return ZStack(alignment: .top) {
            NotchShape(topCornerRadius: openRadii.top, bottomCornerRadius: openRadii.bottom).fill(Color.black)
            openContent(panel, sizing: sizing, bounds: bounds)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    // MARK: - 影格

    private struct FrameState {
        var progress: Double
        var content: NotchMotion.ContentStyle
        var label: String
    }

    private func interpolatedSize(from: CGSize, to: CGSize, _ p: Double) -> CGSize {
        CGSize(width: from.width + (to.width - from.width) * p, height: from.height + (to.height - from.height) * p)
    }

    private func interpolatedRadii(from: (top: Double, bottom: Double), to: (top: Double, bottom: Double), _ p: Double) -> (top: Double, bottom: Double) {
        (from.top + (to.top - from.top) * p, from.bottom + (to.bottom - from.bottom) * p)
    }

    private let canvasSize = CGSize(width: 800, height: 236)

    /// 變形中的一格：形體尺寸／圓角隨進度，內容層固定最終尺寸、被形體裁切，外觀依內容層樣式。
    private func morphFrame(
        progress p: Double, content style: NotchMotion.ContentStyle?, panel: NotchSizing.Panel = .home,
        sizing: NotchSizing = NotchSizing(), from: CGSize, to: CGSize,
        fromRadii: (top: Double, bottom: Double), toRadii: (top: Double, bottom: Double)
    ) -> some View {
        let size = interpolatedSize(from: from, to: to, p)
        let radii = interpolatedRadii(from: fromRadii, to: toRadii, p)
        return ZStack(alignment: .top) {
            Color(white: 0.82)
            ZStack(alignment: .top) {
                Color.black
                if let style {
                    openContent(panel, sizing: sizing)
                        .modifier(NotchContentStyleModifier(style: style))
                        .padding(.top, 0)
                }
            }
            .frame(width: max(size.width, 1), height: max(size.height, 1), alignment: .top)
            .clipShape(NotchShape(topCornerRadius: radii.top, bottomCornerRadius: radii.bottom))
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .top)
    }

    private let sampleTimesMs = [0, 40, 80, 120, 160, 200, 260, 320, 400, 500, 600]

    private func filmstrip(opening: Bool) -> some View {
        let sizing = NotchSizing()
        let open = sizing.openSize(for: .home)
        let curve = motion.curve(opening ? .open : .close)
        let cells: [AnyView] = sampleTimesMs.map { ms in
            let time = Double(ms) / 1000
            let p = curve.progress(at: time)
            let style = motion.contentStyle(revealing: opening, at: time)
            let from = opening ? closedSize : open
            let to = opening ? open : closedSize
            let fromRadii = opening ? closedRadii : openRadii
            let toRadii = opening ? openRadii : closedRadii
            let size = interpolatedSize(from: from, to: to, p)
            let label = String(
                format: "t=%3dms  p=%.3f  %.0f×%.0f  content α=%.2f blur=%.1f s=%.3f dy=%.1f",
                ms, p, size.width, size.height, style.opacity, style.blur, style.scale, style.offsetY
            )
            return AnyView(
                VStack(spacing: 2) {
                    morphFrame(progress: p, content: style, from: from, to: to, fromRadii: fromRadii, toRadii: toRadii)
                        .scaleEffect(0.5)
                        .frame(width: canvasSize.width / 2, height: canvasSize.height / 2)
                    Text(verbatim: label).font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.black)
                }
            )
        }
        let cell = CGSize(width: canvasSize.width / 2, height: canvasSize.height / 2)
        let title = opening ? "展開（open spring response 0.46 / ζ 0.72；內容層延遲 0.09s）" : "收合（close spring response 0.34 / ζ 0.90；內容層 0.12s 淡出）"
        return VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.black)
            ForEach(0..<4) { row in
                HStack(spacing: 6) {
                    ForEach(0..<3) { col in
                        let index = row * 3 + col
                        if index < cells.count { cells[index] } else { Color.clear.frame(width: cell.width, height: cell.height + 14) }
                    }
                }
            }
        }
        .padding(10)
        .background(Color.white)
    }

    @discardableResult
    private func write(_ view: some View, named name: String, scale: CGFloat = 2) throws -> CGImage {
        let image = try renderImage(view, scale: scale)
        let url = try writeSnapshot(image, named: name)
        XCTAssertGreaterThan((try? Data(contentsOf: url).count) ?? 0, 5_000, "PNG 太小：\(name)")
        return image
    }

    func testOpenFilmstrip() throws {
        try write(filmstrip(opening: true), named: "motion-open-filmstrip", scale: 1.5)
    }

    func testCloseFilmstrip() throws {
        try write(filmstrip(opening: false), named: "motion-close-filmstrip", scale: 1.5)
    }

    // MARK: - 數值表

    func testWriteMotionCurvesTable() throws {
        let sizing = NotchSizing()
        let open = sizing.openSize(for: .home)
        var out = ""
        out += "DavidNook 瀏海動畫數值表（NotchMotion 預設：速度 1.0、未開啟減少動態）\n"
        out += "閉合形體 \(Int(closedSize.width))×\(Int(closedSize.height))，圓角 上 \(String(format: "%.2f", closedRadii.top)) / 下 \(String(format: "%.2f", closedRadii.bottom))；"
        out += "展開形體 Home \(Int(open.width))×\(Int(open.height))，圓角 上 \(openRadii.top) / 下 \(openRadii.bottom)\n"
        out += "進度 p = Spring.value(target: 1, time: t)；尺寸／圓角 = 起點 + (終點 − 起點) × p；內容層樣式見 NotchMotion.contentStyle。\n\n"

        func section(_ title: String, opening: Bool) {
            let curve = motion.curve(opening ? .open : .close)
            let from = opening ? closedSize : open
            let to = opening ? open : closedSize
            let fromRadii = opening ? closedRadii : openRadii
            let toRadii = opening ? openRadii : closedRadii
            out += "== \(title) ==\n"
            out += "t(ms)    p        width    height   topR    botR    | content: alpha  blur   scale   offsetY\n"
            for ms in sampleTimesMs {
                let time = Double(ms) / 1000
                let p = curve.progress(at: time)
                let size = interpolatedSize(from: from, to: to, p)
                let radii = interpolatedRadii(from: fromRadii, to: toRadii, p)
                let style = motion.contentStyle(revealing: opening, at: time)
                out += String(format: "%-8d %-8.4f %-8.1f %-8.1f %-7.2f %-7.2f |          %-6.3f %-6.2f %-7.4f %.2f\n",
                              ms, p, size.width, size.height, radii.top, radii.bottom, style.opacity, style.blur, style.scale, style.offsetY)
            }
            out += "\n"
        }
        section("展開（closed → open）", opening: true)
        section("收合（open → closed）", opening: false)

        func scan(_ curve: NotchMotionCurve) -> (overshoot: Double, settle: Double) {
            var peak = 0.0, settle = 0.0, time = 0.0
            while time <= 3 {
                let p = curve.progress(at: time)
                peak = max(peak, p)
                if abs(p - 1) > 0.01 { settle = time }
                time += 0.001
            }
            return (max(0, peak - 1), settle)
        }
        out += "== 實測過衝與穩定時間（逐毫秒掃描）==\n"
        for (name, curve) in [
            ("open", motion.curve(.open)), ("close", motion.curve(.close)), ("tabSwitch", motion.curve(.tabSwitch)),
            ("anticipate", motion.curve(.anticipate)), ("contentReveal", motion.contentRevealCurve), ("contentHide", motion.contentHideCurve),
            ("reduceMotion.open", NotchMotion(reduceMotion: true).curve(.open)), ("speed 2x open", NotchMotion(speed: 2).curve(.open)),
        ] {
            let r = scan(curve)
            out += String(format: "%-18@ overshoot %5.2f%%  settle(±1%%) %.3fs\n", name as NSString, r.overshoot * 100, r.settle)
        }
        let openOvershootPx = (open.width - closedSize.width) * scan(motion.curve(.open)).overshoot
        out += String(format: "\nHome 展開寬度過衝 ≈ %.1f pt（%.0f → 峰值 %.1f）；高度過衝 ≈ %.1f pt\n",
                      openOvershootPx, open.width, open.width + openOvershootPx,
                      (open.height - closedSize.height) * scan(motion.curve(.open)).overshoot)
        let url = try snapshotDirectory().appendingPathComponent("motion-curves.txt")
        try out.write(to: url, atomically: true, encoding: .utf8)
        XCTAssertTrue(out.contains("展開（closed → open）"))
        print(out)
    }

    // MARK: - 過衝在渲染中確實出現（像素量測）

    /// 形體（純黑）在畫面中的外框寬度（像素，scale 2）。
    private func blackWidth(progress p: Double) throws -> Int {
        let open = NotchSizing().openSize(for: .home)
        let view = morphFrame(progress: p, content: nil, from: closedSize, to: open, fromRadii: closedRadii, toRadii: openRadii)
        let px = Pixels(try renderImage(view))
        let row = Int(16 * 2) // 兩側直邊所在的高度（耳朵與下緣圓角之間）；可見黑色寬度 = 外框寬 − 2 × 上緣圓角
        var minX = Int.max, maxX = -1
        for x in 0..<px.width where px.luminance(x: x, y: row) < 0.1 {
            minX = min(minX, x); maxX = max(maxX, x)
        }
        return maxX >= minX ? maxX - minX + 1 : 0
    }

    func testRenderedShapeOvershootsThenSettlesAtTheOpenWidth() throws {
        let curve = motion.curve(.open)
        // 找峰值時間。
        var peakTime = 0.0, peak = 0.0, time = 0.0
        while time <= 1 { let p = curve.progress(at: time); if p > peak { peak = p; peakTime = time }; time += 0.001 }
        let peakWidth = try blackWidth(progress: peak)
        let finalWidth = try blackWidth(progress: curve.progress(at: 0.6))
        let closedWidth = try blackWidth(progress: 0)
        // 可見黑色寬度 = 外框寬 − 2 × 上緣圓角（耳朵）。
        XCTAssertEqual(Double(closedWidth) / 2, Double(closedSize.width) - 2 * closedRadii.top, accuracy: 2, "t=0 應為閉合寬度")
        XCTAssertEqual(Double(finalWidth) / 2, 720 - 2 * 19, accuracy: 4, "t=0.6s 應已回到 720（±1% 內）")
        XCTAssertGreaterThan(Double(peakWidth) / 2, Double(finalWidth) / 2 + 12, "峰值（t=\(String(format: "%.3f", peakTime))s）應比最終寬度多出至少 12 pt")
        print(String(format: "NOTCHRENDER black width: closed=%.1f peak(%.3fs)=%.1f final(0.6s)=%.1f", Double(closedWidth) / 2, peakTime, Double(peakWidth) / 2, Double(finalWidth) / 2))
    }

    // MARK: - 6 張靜態圖（Home／剪貼簿 × 預設／最小／最大）

    private let sizeCases: [(name: String, sizing: NotchSizing)] = [
        ("default-720x100", NotchSizing()),
        ("min-560x85", NotchSizing(width: 560, heightScale: 0.85)),
        ("max-900x130", NotchSizing(width: 900, heightScale: 1.30)),
    ]

    private func staticCanvas(_ panel: NotchSizing.Panel, sizing: NotchSizing, bounds: Bool = false) -> some View {
        let size = sizing.openSize(for: panel)
        let label = String(format: "%@  %.0f×%.0f  內容區 %.0f×%.0f", panel == .home ? "Home" : "Clipboard", size.width, size.height,
                           sizing.contentWidth(earInset: earInset), sizing.bodyHeight(for: panel))
        return VStack(spacing: 6) {
            Text(verbatim: label).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.black)
            openNotch(panel, sizing: sizing, bounds: bounds)
        }
        .padding(16)
        .background(Color(white: 0.82))
    }

    func testStaticRendersHomeAndClipboardAtThreeSizes() throws {
        for (name, sizing) in sizeCases {
            for panel in NotchSizing.Panel.allCases {
                let prefix = panel == .home ? "static-home" : "static-clipboard"
                let image = try write(staticCanvas(panel, sizing: sizing), named: "\(prefix)-\(name)")
                let size = sizing.openSize(for: panel)
                XCTAssertGreaterThanOrEqual(image.width, Int(size.width * 2), "\(prefix)-\(name)")
                XCTAssertGreaterThanOrEqual(image.height, Int(size.height * 2), "\(prefix)-\(name)")
            }
        }
        // 最小尺寸、各區塊外框（紅＝封面、綠＝歌名歌手、藍＝進度條、橘＝工具列、紫＝歌詞、黃＝控制區）。
        try write(staticCanvas(.home, sizing: NotchSizing(width: 560, heightScale: 0.85), bounds: true), named: "static-home-min-560x85-bounds")
        try write(staticCanvas(.home, sizing: NotchSizing(), bounds: true), named: "static-home-default-720x100-bounds")
    }

    // MARK: - 與舊版 640×190 並排

    func testComparisonWithTheOldSize() throws {
        let old = CGSize(width: 640, height: 190)
        let new = NotchSizing()
        // 舊版 Home：內容區 578×130（形體 640 − 2×31；高 190 − 38 − 8 − 12 − …），歌詞固定 215×124。
        let oldMetrics = NotchHomeMetrics(contentWidth: 578, bodyHeight: 130, showsLyrics: true)
        let oldNotch = ZStack(alignment: .top) {
            NotchShape(topCornerRadius: 19, bottomCornerRadius: 24).fill(Color.black)
            VStack(spacing: 0) {
                tabHeader(selected: .home).frame(width: 578, height: 38)
                homeBody(oldMetrics).frame(width: 578, height: 130, alignment: .top)
            }
            .frame(width: 578, alignment: .top)
            .padding(.top, 8) // 舊版表頭與內容之間的預設間距
        }
        .frame(width: old.width, height: old.height, alignment: .top)

        func caption(_ text: String) -> some View {
            Text(verbatim: text).font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.black)
        }
        let view = VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    caption("舊版 640×190（內容近似：以相同元件排版）")
                    oldNotch
                }
                VStack(alignment: .leading, spacing: 4) {
                    caption("新版 Home 預設 720×176")
                    openNotch(.home, sizing: new)
                }
            }
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    caption("新版 Clipboard 預設 720×232")
                    openNotch(.clipboard, sizing: new)
                }
            }
        }
        .padding(20)
        .background(Color(white: 0.82))
        _ = try write(view, named: "compare-old-640x190-vs-new")
    }
}

private extension View {
    /// 除錯用外框（僅 `enabled` 時繪製），用來在渲染圖上看出各區塊的實際範圍。
    @ViewBuilder
    func debugBox(_ enabled: Bool, _ color: Color) -> some View {
        if enabled { overlay(Rectangle().stroke(color, lineWidth: 1)) } else { self }
    }
}
