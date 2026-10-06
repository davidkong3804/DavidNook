import DavidNookCore
import SwiftUI
import XCTest
@testable import DavidNookUI

/// 剪貼簿面板離屏渲染（ImageRenderer，scale 2）：輸出 PNG 供人工檢視，並以像素統計做基本斷言。
/// 輸出目錄：環境變數 DAVIDNOOK_SNAPSHOT_DIR（未設定則為暫存目錄）。
/// 所有文字、檔名皆為自編；圖片以 CoreGraphics 現場生成（漸層／純色），沒有任何真實剪貼簿內容，也不碰系統剪貼簿。
@MainActor
final class ClipboardPanelSnapshotTests: XCTestCase {
    // MARK: - 自編資料

    private func t(_ seconds: Double) -> Date { Date(timeIntervalSince1970: 1_800_000_000 + seconds) }

    private let appNames: [String: String] = [
        "test.example.notes": "備忘錄",
        "test.example.browser": "Browser",
        "test.example.terminal": "Terminal",
        "test.example.finder": "Finder",
    ]

    private let panelSize = CGSize(width: 578, height: 128)
    private let notchSize = CGSize(width: 640, height: 190)
    private lazy var canvas = CGSize(width: notchSize.width + 20, height: notchSize.height + 20)

    private var imageURLs: [UUID: URL] = [:]
    private let thumbnails = ClipboardThumbnailCache()

    /// 以 CoreGraphics 生成漸層 PNG（寫到暫存目錄），並建立對應的圖片條目；預先把縮圖放進快取。
    private func imageItem(
        _ index: Int, width: Int = 1600, height: Int = 900, at seconds: Double, pinned: Bool = false, source: String? = nil
    ) async throws -> ClipboardItem {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let palette: [(CGColor, CGColor)] = [
            (CGColor(red: 0.95, green: 0.55, blue: 0.2, alpha: 1), CGColor(red: 0.85, green: 0.2, blue: 0.4, alpha: 1)),
            (CGColor(red: 0.2, green: 0.7, blue: 0.9, alpha: 1), CGColor(red: 0.2, green: 0.3, blue: 0.8, alpha: 1)),
            (CGColor(red: 0.4, green: 0.8, blue: 0.4, alpha: 1), CGColor(red: 0.1, green: 0.5, blue: 0.4, alpha: 1)),
        ]
        let colors = palette[index % palette.count]
        let gradient = try XCTUnwrap(CGGradient(colorsSpace: space, colors: [colors.0, colors.1] as CFArray, locations: [0, 1]))
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
        let image = try XCTUnwrap(context.makeImage())
        let data = try pngData(image)

        // 條目本身的圖片資料只用來產生 hash／檔名；實際顯示走磁碟檔縮圖。
        let item = ClipboardItem(imageData: data, now: t(seconds), isPinned: pinned, sourceAppBundleID: source)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DavidNookClipSnap-\(UUID().uuidString).png")
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        imageURLs[item.id] = url
        _ = await thumbnails.thumbnail(for: url)
        return item
    }

    private func text(_ s: String, at seconds: Double, pinned: Bool = false, source: String? = nil) -> ClipboardItem {
        ClipboardItem(text: s, now: t(seconds), isPinned: pinned, sourceAppBundleID: source)
    }

    private func files(_ paths: [String], at seconds: Double, pinned: Bool = false, source: String? = nil) -> ClipboardItem {
        ClipboardItem(filePaths: paths, now: t(seconds), isPinned: pinned, sourceAppBundleID: source)
    }

    /// 文字、圖片、檔案混合，含釘選。
    private func mixedItems() async throws -> [ClipboardItem] {
        [
            text("會議紀錄範本：日期、出席者、決議事項、待辦清單", at: 10, pinned: true, source: "test.example.notes"),
            text("ssh deploy@staging.example.test -p 2222", at: 20, pinned: true, source: "test.example.terminal"),
            try await imageItem(0, at: 90, source: "test.example.browser"),
            files(["/Users/test/Documents/季度報告-2026Q3.pdf"], at: 80, source: "test.example.finder"),
            text("明天下午三點記得帶筆電和轉接頭，順便把投影片的備份放到隨身碟", at: 70, source: "test.example.notes"),
            try await imageItem(1, at: 60),
            files(["/Users/test/Pictures/trip/IMG_0001.jpg", "/Users/test/Pictures/trip/IMG_0002.jpg", "/Users/test/Pictures/trip/IMG_0003.jpg"], at: 50),
            text("Meeting notes\n- agenda review\n- budget\n- next steps", at: 40, source: "test.example.notes"),
        ]
    }

    // MARK: - 渲染

    private func panel(
        _ model: ClipboardPanelModel, height: CGFloat? = nil,
        showsHints: Bool = false, autoPasteMode: ClipboardAutoPasteMode = .off,
        feedback: ClipboardCopyFeedback = ClipboardCopyFeedback(), hoverIndex: Int? = nil
    ) -> some View {
        ClipboardPanelView(
            model: model,
            strings: .zhHant,
            thumbnails: thumbnails,
            imageURL: { [imageURLs] in imageURLs[$0.id] },
            appName: { [appNames] in $0.flatMap { appNames[$0] } },
            autoFocusSearch: false,
            showsHints: showsHints,
            autoPasteMode: autoPasteMode,
            feedback: feedback
        )
        .environment(\.clipboardStaticRender, true)
        .environment(\.clipboardPreviewHoverIndex, hoverIndex)
        .frame(width: panelSize.width, height: height ?? panelSize.height)
    }

    /// 模擬展開瀏海：黑色圓角底＋頂端分頁列（Home／剪貼簿）＋面板。panelHeight 比預設高時，整個瀏海一起加高。
    private func notch<V: View>(_ content: V, panelHeight: CGFloat? = nil) -> some View {
        let extra = (panelHeight ?? panelSize.height) - panelSize.height
        let canvasSize = CGSize(width: canvas.width, height: canvas.height + extra)
        let inner = CGSize(width: notchSize.width - 24, height: notchSize.height + extra - 10)
        return NotchBackdrop(size: canvasSize) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Image(systemName: "house.fill").padding(.horizontal, 15).foregroundStyle(Color.gray)
                        Image(systemName: "doc.on.clipboard")
                            .padding(.horizontal, 15).frame(height: 26)
                            .background(Capsule().fill(Color.white.opacity(0.18)))
                            .foregroundStyle(Color.white)
                    }
                    Spacer()
                    Image(systemName: "gear").foregroundStyle(Color.white).padding(.trailing, 6)
                }
                .frame(height: 38)
                .padding(.horizontal, 12)
                content
                Spacer(minLength: 0)
            }
            .frame(width: inner.width, height: inner.height, alignment: .top)
        }
    }

    @discardableResult
    private func snapshot(
        _ name: String, _ model: ClipboardPanelModel, height: CGFloat? = nil,
        showsHints: Bool = false, autoPasteMode: ClipboardAutoPasteMode = .off,
        feedback: ClipboardCopyFeedback = ClipboardCopyFeedback(), hoverIndex: Int? = nil
    ) throws -> CGImage {
        let view = notch(
            panel(model, height: height, showsHints: showsHints, autoPasteMode: autoPasteMode, feedback: feedback, hoverIndex: hoverIndex),
            panelHeight: height
        )
        let image = try renderImage(view)
        let url = try writeSnapshot(image, named: name)
        XCTAssertGreaterThan((try? Data(contentsOf: url).count) ?? 0, 5_000, "PNG 太小：\(name)")
        return image
    }

    /// 純黑底、只有面板（像素斷言用）。
    private func plain(_ model: ClipboardPanelModel) throws -> Pixels {
        Pixels(try renderImage(panel(model).background(Color.black)))
    }

    /// 橘色（橫幅、釘選圖示）像素數。
    private func orangeCount(_ px: Pixels, rows: ClosedRange<Int>) -> Int {
        var n = 0
        for y in max(rows.lowerBound, 0)...min(rows.upperBound, px.height - 1) {
            for x in 0..<px.width {
                let c = px.rgb(x: x, y: y)
                if c.r > 0.55, c.g > 0.25, c.g < 0.7, c.b < 0.3, c.r - c.b > 0.35 { n += 1 }
            }
        }
        return n
    }

    private var fullRows: ClosedRange<Int> { 0...(Int(panelSize.height * 2) - 1) }
    /// 面板內「橫幅」所在的水平帶（頂端列之下）。
    private var bannerRows: ClosedRange<Int> { Int(32 * 2)...Int(66 * 2) }

    // MARK: - 8 張要求的快照＋補充

    func testMixedListWithPinnedItems() async throws {
        let model = ClipboardPanelModel(items: try await mixedItems())
        try snapshot("clipboard-01-mixed-pinned", model)
        // 同一份資料以較高的面板渲染，才看得到全部列型別（真實面板可捲動）。
        try snapshot("clipboard-01b-mixed-pinned-tall", model, height: 330)

        XCTAssertEqual(model.pinnedCount, 2)
        XCTAssertEqual(model.visibleItems.prefix(2).map(\.isPinned), [true, true])
        let px = try plain(model)
        XCTAssertGreaterThan(orangeCount(px, rows: fullRows), 20, "釘選圖示應為橘色且常駐可見")
    }

    func testSearchFilteredResults() async throws {
        var model = ClipboardPanelModel(items: try await mixedItems())
        model.setQuery("notes")
        XCTAssertEqual(model.visibleItems.count, 1)
        try snapshot("clipboard-02-search-filtered", model)

        var wide = ClipboardPanelModel(items: try await mixedItems())
        wide.setQuery("a")  // 命中多筆文字／檔案
        try snapshot("clipboard-02b-search-filtered-multiple", wide, height: 200)
        XCTAssertGreaterThan(wide.visibleItems.count, 1)
    }

    func testEmptyHistory() throws {
        let model = ClipboardPanelModel(items: [])
        XCTAssertEqual(model.emptyState, .noHistory)
        try snapshot("clipboard-03-empty", model)
        let px = try plain(model)
        XCTAssertGreaterThan(px.count(rows: Int(60 * 2)...Int(110 * 2), above: 0.2), 50, "應顯示『剪貼簿是空的』")
        XCTAssertEqual(orangeCount(px, rows: fullRows), 0)
    }

    func testNoSearchResults() async throws {
        var model = ClipboardPanelModel(items: try await mixedItems())
        model.setQuery("找不到的字串")
        XCTAssertEqual(model.emptyState, .noResults)
        try snapshot("clipboard-04-no-results", model)
        let px = try plain(model)
        XCTAssertGreaterThan(px.count(rows: Int(60 * 2)...Int(110 * 2), above: 0.2), 50)
    }

    func testPausedBanner() async throws {
        let model = ClipboardPanelModel(items: try await mixedItems(), isPaused: true)
        XCTAssertEqual(model.banner, .paused)
        try snapshot("clipboard-05-paused-banner", model)
        let px = try plain(model)
        XCTAssertGreaterThan(orangeCount(px, rows: bannerRows), 200, "橫幅應為橘色調")

        let empty = ClipboardPanelModel(items: [], isPaused: true)
        XCTAssertEqual(empty.emptyState, .paused)
        try snapshot("clipboard-05b-paused-empty", empty)
    }

    func testPermissionBanner() async throws {
        let model = ClipboardPanelModel(items: try await mixedItems(), needsPermission: true)
        XCTAssertEqual(model.banner, .needsPermission)
        try snapshot("clipboard-06-permission-banner", model)
        let px = try plain(model)
        XCTAssertGreaterThan(orangeCount(px, rows: bannerRows), 200)

        let empty = ClipboardPanelModel(items: [], needsPermission: true)
        XCTAssertEqual(empty.emptyState, .needsPermission)
        try snapshot("clipboard-06b-permission-empty", empty)
    }

    func testSelectedRowHighlight() async throws {
        var model = ClipboardPanelModel(items: try await mixedItems())
        model.handle(.down)
        model.handle(.down)  // 第 3 列（釘選區之後的第一列）
        XCTAssertEqual(model.selectedIndex, 2)
        try snapshot("clipboard-07-selected-row", model)
        try snapshot("clipboard-07b-selected-row-tall", model, height: 230)

        // 以較高的面板取樣（列表頂端 26+6，列高 36＋間距 2，釘選區與其餘之間多一條分隔線 1＋2×1 的邊距）：
        // 選取列（index 2）最左側 padding 處的底色應比第一列亮。
        let px = Pixels(try renderImage(panel(model, height: 230).background(Color.black)))
        func rowLuminance(top: Int) -> Double {
            var sum = 0.0, n = 0.0
            for y in ((top + 2) * 2)..<((top + 34) * 2) { for x in 2..<8 { sum += px.luminance(x: x, y: y); n += 1 } }
            return sum / n
        }
        let listTop = 26 + 6
        let selectedTop = listTop + 2 * 38 + 3
        XCTAssertGreaterThan(rowLuminance(top: selectedTop), rowLuminance(top: listTop) + 0.05, "選取列的底色應較亮")
    }

    func testLongAndMultilineTextPreviews() throws {
        let long = String(repeating: "這是一段很長很長的測試文字，用來確認預覽只會顯示前兩行並在行尾截斷。", count: 12)
        let model = ClipboardPanelModel(items: [
            text(long, at: 50, source: "test.example.notes"),
            text("第一行\n第二行\n第三行（不應該顯示）\n第四行", at: 40),
            text("A deliberately long made-up English sentence that keeps going and going to check how the preview wraps and truncates after exactly two lines of text in the narrow notch panel.", at: 30, source: "test.example.browser"),
            text("\n\n   前面有空行與縮排的文字\n下一行", at: 20),
        ])
        try snapshot("clipboard-08-long-multiline-text", model, height: 230)
        // 預覽不得超出面板右緣（右側 6 像素欄不應有亮點）。
        let px = try plain(model)
        var lit = 0
        for y in 0..<px.height { for x in (px.width - 6)..<px.width where px.luminance(x: x, y: y) > 0.3 { lit += 1 } }
        XCTAssertEqual(lit, 0)
    }

    func testLongFileNames() throws {
        let model = ClipboardPanelModel(items: [
            files(["/Users/test/Documents/這是一個名稱非常非常長的檔案-2026年第三季度財務報告與預算分析草稿-最終版-請勿外流.pdf"], at: 50, source: "test.example.finder"),
            files(["/Users/test/Downloads/a-very-long-file-name-that-should-be-truncated-in-the-middle-so-the-extension-stays-visible.tar.gz",
                   "/Users/test/Downloads/second.txt"], at: 40),
            files(["/Users/test/Desktop/資料夾", "/Users/test/Desktop/notes.md", "/Users/test/Desktop/a.png", "/Users/test/Desktop/b.mov"], at: 30),
        ])
        try snapshot("clipboard-09-long-file-names", model, height: 180)
        let px = try plain(model)
        var lit = 0
        for y in 0..<px.height { for x in (px.width - 6)..<px.width where px.luminance(x: x, y: y) > 0.3 { lit += 1 } }
        XCTAssertEqual(lit, 0, "長檔名要在中間截斷，不得超出面板")
    }

    func testImageThumbnailsAndFilters() async throws {
        let items = [
            try await imageItem(0, width: 1920, height: 1080, at: 50, source: "test.example.browser"),
            try await imageItem(1, width: 600, height: 1200, at: 40),
            try await imageItem(2, width: 3000, height: 3000, at: 30, pinned: true),
            text("only text", at: 20),
        ]
        var model = ClipboardPanelModel(items: items)
        model.setFilter(.image)
        XCTAssertEqual(model.visibleItems.count, 3)
        try snapshot("clipboard-10-images-filter", model, height: 190)
        // 縮圖快取內只有縮圖（最長邊 ≤ 96 像素）。
        for item in model.visibleItems {
            let thumb = try XCTUnwrap(thumbnails.cachedThumbnail(for: try XCTUnwrap(imageURLs[item.id])))
            XCTAssertLessThanOrEqual(max(thumb.size.width, thumb.size.height) * 2, 96)
        }

        var files = ClipboardPanelModel(items: try await mixedItems())
        files.setFilter(.files)
        XCTAssertEqual(files.visibleItems.count, 2)
        try snapshot("clipboard-10b-files-filter", files)
    }

    // MARK: - 可發現性（提示、hover 動作、點擊回饋、狀態文案）

    /// 真實展開瀏海的內容區高度（clipboardBaseHeight 232 − 表頭 38 − 底部 12）。
    private let realHeight: CGFloat = 182

    private func lit(_ px: Pixels, rows: ClosedRange<Int>, xs: Range<Int>? = nil, above: Double = 0.25) -> Int {
        var n = 0
        for y in max(rows.lowerBound, 0)...min(rows.upperBound, px.height - 1) {
            for x in (xs ?? 0..<px.width) where px.luminance(x: x, y: y) > above { n += 1 }
        }
        return n
    }

    private func greenCount(_ px: Pixels, rows: ClosedRange<Int>) -> Int {
        var n = 0
        for y in max(rows.lowerBound, 0)...min(rows.upperBound, px.height - 1) {
            for x in 0..<px.width {
                let c = px.rgb(x: x, y: y)
                if c.g > 0.5, c.g - c.r > 0.2, c.g - c.b > 0.15 { n += 1 }
            }
        }
        return n
    }

    private func redCount(_ px: Pixels, rows: ClosedRange<Int>) -> Int {
        var n = 0
        for y in max(rows.lowerBound, 0)...min(rows.upperBound, px.height - 1) {
            for x in 0..<px.width {
                let c = px.rgb(x: x, y: y)
                if c.r > 0.6, c.r - c.g > 0.3, c.r - c.b > 0.25, c.g < 0.55 { n += 1 }
            }
        }
        return n
    }

    func testHintFooterShowsAndHides() async throws {
        let one = ClipboardPanelModel(items: [text("只有一筆的測試文字", at: 10)])
        for (name, mode) in [("off", ClipboardAutoPasteMode.off), ("on", .on), ("needs-permission", .needsPermission)] {
            try snapshot("clipboard-11-hint-footer-\(name)", one, height: realHeight, showsHints: true, autoPasteMode: mode)
        }
        try snapshot("clipboard-11b-hint-footer-mixed", ClipboardPanelModel(items: try await mixedItems()), height: realHeight, showsHints: true)

        // 底部 16pt 的帶子：有提示就有字，收起後是空的（只有一列資料，底部不會有列內容）。
        func bottomBand(_ showsHints: Bool) throws -> Int {
            let px = Pixels(try renderImage(panel(one, height: realHeight, showsHints: showsHints).background(Color.black)))
            return lit(px, rows: Int((realHeight - 16) * 2)...Int(realHeight * 2 - 1))
        }
        XCTAssertGreaterThan(try bottomBand(true), 150, "提示列應該有字")
        XCTAssertEqual(try bottomBand(false), 0, "收起後底部不留白字")
    }

    func testHintFooterIsHiddenWhenListIsEmptyOrBannerShows() throws {
        // 空狀態用空狀態文案教學；橫幅出現時不再疊一條提示（面板高度有限）。
        let empty = ClipboardPanelModel(items: [])
        let px = Pixels(try renderImage(panel(empty, height: realHeight, showsHints: true).background(Color.black)))
        XCTAssertEqual(lit(px, rows: Int((realHeight - 16) * 2)...Int(realHeight * 2 - 1)), 0, "空狀態不重複顯示底部提示")
    }

    func testHoveredRowRevealsCopyPinDeleteActions() async throws {
        let model = ClipboardPanelModel(items: [
            text("第一列（預設被選取）", at: 30),
            text("第二列（滑鼠停在這一列）", at: 20),
            text("第三列", at: 10),
        ])
        try snapshot("clipboard-12-hover-row", model, height: realHeight, hoverIndex: 1)
        try snapshot("clipboard-12b-no-hover", model, height: realHeight, hoverIndex: nil)

        // 第二列（index 1）：頂端列 26＋6，列高 36＋間距 2 → top = 32 + 38 = 70。取右側 100pt 內的亮點。
        func actionPixels(_ hover: Int?) throws -> Int {
            let px = Pixels(try renderImage(panel(model, height: realHeight, hoverIndex: hover).background(Color.black)))
            return lit(px, rows: (70 + 4) * 2...(70 + 32) * 2, xs: (px.width - 100 * 2)..<px.width, above: 0.4)
        }
        let hovered = try actionPixels(1)
        let plain = try actionPixels(nil)
        XCTAssertGreaterThan(hovered, plain + 60, "hover 時右側應出現複製／釘選／刪除三個圖示")
    }

    func testCopiedFeedbackShowsCheckmarkOnThatRowOnly() throws {
        let items = [text("要複製的這一列", at: 30), text("旁邊的另一列", at: 20)]
        let model = ClipboardPanelModel(items: items)
        var feedback = ClipboardCopyFeedback()
        _ = feedback.begin(.copied, for: model.visibleItems[0].id)
        try snapshot("clipboard-13-copied-feedback", model, height: realHeight, feedback: feedback)

        func green(_ fb: ClipboardCopyFeedback) throws -> (first: Int, second: Int) {
            let px = Pixels(try renderImage(panel(model, height: realHeight, feedback: fb).background(Color.black)))
            return (greenCount(px, rows: 32 * 2...(32 + 36) * 2), greenCount(px, rows: (32 + 38) * 2...(32 + 74) * 2))
        }
        let with = try green(feedback)
        let without = try green(ClipboardCopyFeedback())
        XCTAssertGreaterThan(with.first, 40, "被點的列要有綠色勾勾與『已複製』")
        XCTAssertEqual(with.second, 0, "其他列不受影響")
        XCTAssertEqual(without.first, 0)
    }

    func testFailedFeedbackShowsRedNotice() throws {
        let model = ClipboardPanelModel(items: [text("複製會失敗的一列", at: 30), text("另一列", at: 20)])
        var feedback = ClipboardCopyFeedback()
        _ = feedback.begin(.failed, for: model.visibleItems[0].id)
        try snapshot("clipboard-14-failed-feedback", model, height: realHeight, feedback: feedback)
        let px = Pixels(try renderImage(panel(model, height: realHeight, feedback: feedback).background(Color.black)))
        XCTAssertGreaterThan(redCount(px, rows: 32 * 2...(32 + 36) * 2), 30, "失敗要有紅色提示")
    }

    func testStateScreensAtRealHeight() async throws {
        let items = try await mixedItems()
        try snapshot("clipboard-15-empty-real", ClipboardPanelModel(items: []), height: realHeight)
        try snapshot("clipboard-15b-paused-empty-real", ClipboardPanelModel(items: [], isPaused: true), height: realHeight)
        try snapshot("clipboard-15c-permission-empty-real", ClipboardPanelModel(items: [], needsPermission: true), height: realHeight)
        try snapshot("clipboard-15d-paused-list-real", ClipboardPanelModel(items: items, isPaused: true), height: realHeight)
        try snapshot("clipboard-15e-permission-list-real", ClipboardPanelModel(items: items, needsPermission: true), height: realHeight)
        var none = ClipboardPanelModel(items: items)
        none.setQuery("找不到的字串")
        try snapshot("clipboard-15f-no-results-real", none, height: realHeight)
        try snapshot("clipboard-15g-list-with-hints-real", ClipboardPanelModel(items: items), height: realHeight, showsHints: true)

        // 橘色狀態畫面在真實高度下不能把內容擠出面板：最下方 4pt 不應有橘色按鈕像素被切到。
        for model in [ClipboardPanelModel(items: [], isPaused: true), ClipboardPanelModel(items: [], needsPermission: true)] {
            let px = Pixels(try renderImage(panel(model, height: realHeight).background(Color.black)))
            XCTAssertGreaterThan(orangeCount(px, rows: 0...(Int(realHeight * 2) - 1)), 200, "要有橘色圖示與按鈕")
            XCTAssertEqual(orangeCount(px, rows: Int((realHeight - 4) * 2)...(Int(realHeight * 2) - 1)), 0, "按鈕不得被面板底緣切掉")
        }
    }

    // MARK: - 純邏輯

    func testDefaultStringsAreTraditionalChinese() {
        let s = ClipboardPanelStrings.zhHant
        XCTAssertEqual(s.emptyHistory, "剪貼簿是空的")
        XCTAssertEqual(s.noResults, "找不到符合的項目")
        XCTAssertEqual(s.pausedTitle, "已暫停記錄")
        XCTAssertEqual(s.permissionTitle, "需要允許貼上權限")
        XCTAssertEqual(s.itemCount(3), "3 個項目")
    }
}
