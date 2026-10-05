import XCTest
@testable import DavidNookCore

/// 剪貼簿面板狀態模型：排序、搜尋、篩選、選取與鍵盤導覽、空狀態。
/// 所有資料皆為自編；不碰任何系統剪貼簿。
final class ClipboardPanelModelTests: XCTestCase {
    // MARK: 輔助

    private func text(_ s: String, at seconds: Double, pinned: Bool = false, source: String? = nil) -> ClipboardItem {
        ClipboardItem(text: s, now: t(seconds), isPinned: pinned, sourceAppBundleID: source)
    }

    private func image(_ seed: String, at seconds: Double, pinned: Bool = false, source: String? = nil) -> ClipboardItem {
        ClipboardItem(imageData: utf8(seed), now: t(seconds), isPinned: pinned, sourceAppBundleID: source)
    }

    private func files(_ paths: [String], at seconds: Double, pinned: Bool = false) -> ClipboardItem {
        ClipboardItem(filePaths: paths, now: t(seconds), isPinned: pinned)
    }

    /// 五筆文字，lastUsedAt 依序為 1…5 秒（"e" 最新）。
    private func fiveTexts() -> [ClipboardItem] {
        ["a", "b", "c", "d", "e"].enumerated().map { text($0.element, at: Double($0.offset + 1)) }
    }

    private func texts(_ model: ClipboardPanelModel) -> [String] {
        model.visibleItems.compactMap(\.text)
    }

    // MARK: 排序

    func testVisibleItemsPinnedFirstThenLastUsedNewestFirst() {
        let model = ClipboardPanelModel(items: [
            text("old", at: 1),
            text("pinOld", at: 2, pinned: true),
            text("new", at: 10),
            text("pinNew", at: 5, pinned: true),
            text("mid", at: 6),
        ])
        XCTAssertEqual(texts(model), ["pinNew", "pinOld", "new", "mid", "old"])
        XCTAssertEqual(model.pinnedCount, 2)
    }

    func testSortIsStableWhenLastUsedAtTies() {
        let model = ClipboardPanelModel(items: [
            text("first", at: 3), text("second", at: 3), text("third", at: 3),
        ])
        XCTAssertEqual(texts(model), ["first", "second", "third"])
    }

    func testSetItemsReplacesAndResorts() {
        var model = ClipboardPanelModel(items: [text("a", at: 1)])
        model.setItems([text("a", at: 1), text("b", at: 2)])
        XCTAssertEqual(texts(model), ["b", "a"])
        XCTAssertEqual(model.allItems.count, 2)
    }

    // MARK: 搜尋

    func testSearchTextIsCaseInsensitiveSubstring() {
        var model = ClipboardPanelModel(items: [text("Hello World", at: 1), text("goodbye", at: 2)])
        model.setQuery("hello")
        XCTAssertEqual(texts(model), ["Hello World"])
    }

    func testSearchTrimsWhitespaceAndEmptyQueryShowsAll() {
        var model = ClipboardPanelModel(items: [text("alpha", at: 1), text("beta", at: 2)])
        model.setQuery("   ")
        XCTAssertEqual(model.visibleItems.count, 2)
        model.setQuery("  alp ")
        XCTAssertEqual(texts(model), ["alpha"])
    }

    func testSearchMatchesFilePathFragmentsAndImageSourceApp() {
        var model = ClipboardPanelModel(items: [
            files(["/Users/test/Documents/report-final.pdf"], at: 1),
            image("img", at: 2, source: "com.example.Painter"),
            image("img2", at: 3),
            text("report notes", at: 4),
        ])
        model.setQuery("report")
        XCTAssertEqual(model.visibleItems.map(\.kind), [.text, .files])
        model.setQuery("painter")
        XCTAssertEqual(model.visibleItems.map(\.kind), [.image])
    }

    func testSearchKeepsPinnedFirstOrdering() {
        var model = ClipboardPanelModel(items: [
            text("note newest", at: 9), text("note pinned", at: 1, pinned: true), text("other", at: 10),
        ])
        model.setQuery("note")
        XCTAssertEqual(texts(model), ["note pinned", "note newest"])
    }

    func testMatchesSearchQueryOnItem() {
        let item = text("Swift Package", at: 1)
        XCTAssertTrue(item.matches(searchQuery: "package"))
        XCTAssertTrue(item.matches(searchQuery: "  "))
        XCTAssertFalse(item.matches(searchQuery: "kotlin"))
    }

    // MARK: 類型篩選

    func testFilterByKind() {
        var model = ClipboardPanelModel(items: [
            text("t", at: 1), image("i", at: 2), files(["/a/b"], at: 3),
        ])
        XCTAssertEqual(model.visibleItems.count, 3)
        model.setFilter(.text)
        XCTAssertEqual(model.visibleItems.map(\.kind), [.text])
        model.setFilter(.image)
        XCTAssertEqual(model.visibleItems.map(\.kind), [.image])
        model.setFilter(.files)
        XCTAssertEqual(model.visibleItems.map(\.kind), [.files])
        model.setFilter(.all)
        XCTAssertEqual(model.visibleItems.count, 3)
    }

    func testFilterIncludesMapping() {
        XCTAssertTrue(ClipboardTypeFilter.all.includes(.text))
        XCTAssertTrue(ClipboardTypeFilter.all.includes(.image))
        XCTAssertTrue(ClipboardTypeFilter.all.includes(.files))
        XCTAssertTrue(ClipboardTypeFilter.text.includes(.text))
        XCTAssertFalse(ClipboardTypeFilter.text.includes(.image))
        XCTAssertFalse(ClipboardTypeFilter.image.includes(.files))
        XCTAssertTrue(ClipboardTypeFilter.files.includes(.files))
    }

    func testFilterCombinesWithQuery() {
        var model = ClipboardPanelModel(items: [
            text("report text", at: 1), files(["/x/report.pdf"], at: 2),
        ])
        model.setQuery("report")
        model.setFilter(.files)
        XCTAssertEqual(model.visibleItems.map(\.kind), [.files])
    }

    // MARK: 預設選取

    func testDefaultSelectionIsFirstRowWhenNotEmpty() {
        let model = ClipboardPanelModel(items: fiveTexts())
        XCTAssertEqual(model.selectedIndex, 0)
        XCTAssertEqual(model.selectedItem?.text, "e")
    }

    func testEmptyListHasNoSelection() {
        let model = ClipboardPanelModel(items: [])
        XCTAssertNil(model.selectedIndex)
        XCTAssertNil(model.selectedItem)
    }

    // MARK: 鍵盤導覽

    func testDownMovesSelectionAndClampsAtEnd() {
        var model = ClipboardPanelModel(items: fiveTexts())
        model.handle(.down)
        XCTAssertEqual(model.selectedIndex, 1)
        for _ in 0..<10 { model.handle(.down) }
        XCTAssertEqual(model.selectedIndex, 4, "不循環：停在最後一列")
    }

    func testUpMovesSelectionAndClampsAtStart() {
        var model = ClipboardPanelModel(items: fiveTexts())
        model.handle(.end)
        model.handle(.up)
        XCTAssertEqual(model.selectedIndex, 3)
        for _ in 0..<10 { model.handle(.up) }
        XCTAssertEqual(model.selectedIndex, 0, "不循環：停在第一列")
    }

    func testHomeAndEnd() {
        var model = ClipboardPanelModel(items: fiveTexts())
        model.handle(.end)
        XCTAssertEqual(model.selectedIndex, 4)
        model.handle(.home)
        XCTAssertEqual(model.selectedIndex, 0)
    }

    func testNavigationKeysOnEmptyListDoNothing() {
        var model = ClipboardPanelModel(items: [])
        for key in [ClipboardPanelKey.up, .down, .home, .end] {
            XCTAssertEqual(model.handle(key), .none)
            XCTAssertNil(model.selectedIndex)
        }
    }

    func testNavigationKeysReturnNoAction() {
        var model = ClipboardPanelModel(items: fiveTexts())
        for key in [ClipboardPanelKey.up, .down, .home, .end] {
            XCTAssertEqual(model.handle(key), .none)
        }
    }

    func testSelectByIndexIgnoresOutOfRange() {
        var model = ClipboardPanelModel(items: fiveTexts())
        model.select(index: 3)
        XCTAssertEqual(model.selectedIndex, 3)
        model.select(index: 99)
        XCTAssertEqual(model.selectedIndex, 3)
        model.select(index: -1)
        XCTAssertEqual(model.selectedIndex, 3)
    }

    func testSelectByID() {
        let items = fiveTexts()
        var model = ClipboardPanelModel(items: items)
        let target = items[1]  // "b"
        model.select(id: target.id)
        XCTAssertEqual(model.selectedItem?.text, "b")
        model.select(id: UUID())
        XCTAssertEqual(model.selectedItem?.text, "b", "不存在的 id 不改變選取")
    }

    // MARK: Enter / ⌘⌫ / ⌘P / Esc

    func testEnterPastesSelectedItem() throws {
        var model = ClipboardPanelModel(items: fiveTexts())
        model.handle(.down)
        let expected = try XCTUnwrap(model.selectedItem).id
        XCTAssertEqual(model.handle(.enter), .paste(expected))
    }

    func testCommandDeleteReturnsDeleteForSelected() throws {
        var model = ClipboardPanelModel(items: fiveTexts())
        model.handle(.end)
        let expected = try XCTUnwrap(model.selectedItem).id
        XCTAssertEqual(model.handle(.commandDelete), .delete(expected))
    }

    func testCommandPReturnsTogglePinForSelected() throws {
        var model = ClipboardPanelModel(items: fiveTexts())
        let expected = try XCTUnwrap(model.selectedItem).id
        XCTAssertEqual(model.handle(.commandP), .togglePin(expected))
    }

    func testActionKeysWithoutSelectionDoNothing() {
        var model = ClipboardPanelModel(items: [])
        XCTAssertEqual(model.handle(.enter), .none)
        XCTAssertEqual(model.handle(.commandDelete), .none)
        XCTAssertEqual(model.handle(.commandP), .none)
    }

    func testEscapeClearsQueryFirstThenCollapses() {
        var model = ClipboardPanelModel(items: fiveTexts())
        model.setQuery("c")
        XCTAssertEqual(model.handle(.escape), .none)
        XCTAssertEqual(model.query, "")
        XCTAssertEqual(model.visibleItems.count, 5)
        XCTAssertEqual(model.handle(.escape), .collapse)
    }

    func testEscapeClearsWhitespaceOnlyQuery() {
        var model = ClipboardPanelModel(items: fiveTexts())
        model.setQuery("  ")
        XCTAssertEqual(model.handle(.escape), .none)
        XCTAssertEqual(model.query, "")
    }

    func testEscapeOnEmptyListStillCollapses() {
        var model = ClipboardPanelModel(items: [])
        XCTAssertEqual(model.handle(.escape), .collapse)
    }

    // MARK: 邊界：選取夾限／重設

    func testSearchNarrowingClampsSelectionIndex() {
        var model = ClipboardPanelModel(items: fiveTexts())  // e d c b a
        model.handle(.end)  // index 4 ("a")
        model.setQuery("e")  // 只剩 "e"
        XCTAssertEqual(model.visibleItems.count, 1)
        XCTAssertEqual(model.selectedIndex, 0, "搜尋把列表縮短：選取索引夾到最後一列")
    }

    func testSearchKeepsSameItemSelectedWhenStillVisible() {
        let items = [
            text("apple 1", at: 1), text("banana", at: 2), text("apple 2", at: 3), text("cherry", at: 4),
        ]
        var model = ClipboardPanelModel(items: items)  // cherry, apple 2, banana, apple 1
        model.select(id: items[0].id)  // apple 1（index 3）
        model.setQuery("apple")
        XCTAssertEqual(model.selectedItem?.text, "apple 1")
        XCTAssertEqual(model.selectedIndex, 1)
    }

    func testSearchWithNoMatchesClearsSelectionAndRestoringSelectsFirst() {
        var model = ClipboardPanelModel(items: fiveTexts())
        model.setQuery("zzz")
        XCTAssertNil(model.selectedIndex)
        XCTAssertNil(model.selectedItem)
        XCTAssertEqual(model.handle(.enter), .none)
        model.setQuery("")
        XCTAssertEqual(model.selectedIndex, 0)
    }

    func testImplicitSelectionFollowsFirstRowWhenQueryChanges() {
        var model = ClipboardPanelModel(items: fiveTexts())  // e d c b a
        model.setQuery("c")
        XCTAssertEqual(model.selectedItem?.text, "c")
        XCTAssertEqual(model.selectedIndex, 0)
    }

    func testShrinkingItemsNeverLeavesSelectionOutOfBounds() {
        var model = ClipboardPanelModel(items: fiveTexts())
        model.handle(.end)
        XCTAssertEqual(model.selectedIndex, 4)
        model.setItems(Array(fiveTexts().prefix(2)))
        XCTAssertEqual(model.visibleItems.count, 2)
        XCTAssertEqual(model.selectedIndex, 1)
        model.setItems([])
        XCTAssertNil(model.selectedIndex)
    }

    func testDeletingSelectedMiddleItemSelectsNeighbourAtSameIndex() {
        let items = fiveTexts()  // e d c b a
        var model = ClipboardPanelModel(items: items)
        model.handle(.down)
        model.handle(.down)  // "c"（index 2）
        XCTAssertEqual(model.selectedItem?.text, "c")
        model.setItems(items.filter { $0.text != "c" })
        XCTAssertEqual(model.selectedIndex, 2)
        XCTAssertEqual(model.selectedItem?.text, "b", "被刪掉後，同一索引上的下一筆被選取")
    }

    func testDeletingLastRowSelectsNewLastRow() {
        let items = fiveTexts()
        var model = ClipboardPanelModel(items: items)
        model.handle(.end)
        model.setItems(items.filter { $0.text != "a" })
        XCTAssertEqual(model.selectedIndex, 3)
        XCTAssertEqual(model.selectedItem?.text, "b")
    }

    func testExplicitSelectionFollowsItemWhenNewItemArrivesAtTop() {
        let items = fiveTexts()
        var model = ClipboardPanelModel(items: items)
        model.handle(.down)
        model.handle(.down)  // "c"
        model.setItems(items + [text("fresh", at: 100)])
        XCTAssertEqual(model.selectedItem?.text, "c", "使用者明確選過的列，不會因為新項目擠進來而跳走")
        XCTAssertEqual(model.selectedIndex, 3)
    }

    func testImplicitSelectionStaysOnTopRowWhenNewItemArrives() {
        let items = fiveTexts()
        var model = ClipboardPanelModel(items: items)
        model.setItems(items + [text("fresh", at: 100)])
        XCTAssertEqual(model.selectedItem?.text, "fresh")
        XCTAssertEqual(model.selectedIndex, 0)
    }

    func testTogglePinMakesSelectionFollowTheItem() {
        let items = fiveTexts()  // e d c b a
        var model = ClipboardPanelModel(items: items)
        model.handle(.end)  // "a"
        var pinned = items
        pinned[0].isPinned = true  // "a" 被釘選：移到最前
        model.setItems(pinned)
        XCTAssertEqual(model.selectedItem?.text, "a")
        XCTAssertEqual(model.selectedIndex, 0)
    }

    func testFilterChangeResetsSelectionToFirstRow() {
        var model = ClipboardPanelModel(items: [
            text("t1", at: 1), text("t2", at: 2), text("t3", at: 3), image("i", at: 4),
        ])
        model.handle(.end)
        XCTAssertEqual(model.selectedIndex, 3)
        model.setFilter(.text)
        XCTAssertEqual(model.selectedIndex, 0)
        model.handle(.down)
        model.setFilter(.all)
        XCTAssertEqual(model.selectedIndex, 0, "每次切換篩選都重設到第一列")
    }

    func testFilterWithNoItemsOfThatKindClearsSelection() {
        var model = ClipboardPanelModel(items: fiveTexts())
        model.setFilter(.image)
        XCTAssertTrue(model.visibleItems.isEmpty)
        XCTAssertNil(model.selectedIndex)
    }

    func testSettingSameFilterAgainDoesNotResetSelection() {
        var model = ClipboardPanelModel(items: fiveTexts())
        model.handle(.end)
        model.setFilter(.all)
        XCTAssertEqual(model.selectedIndex, 4)
    }

    // MARK: 空狀態與橫幅

    func testNoHistoryEmptyState() {
        let model = ClipboardPanelModel(items: [])
        XCTAssertEqual(model.emptyState, .noHistory)
        XCTAssertNil(model.banner)
    }

    func testNoResultsWhenQueryExcludesEverything() {
        var model = ClipboardPanelModel(items: fiveTexts())
        XCTAssertNil(model.emptyState)
        model.setQuery("zzz")
        XCTAssertEqual(model.emptyState, .noResults)
    }

    func testNoResultsWhenFilterExcludesEverything() {
        var model = ClipboardPanelModel(items: fiveTexts())
        model.setFilter(.files)
        XCTAssertEqual(model.emptyState, .noResults)
    }

    func testPausedEmptyStateOnlyWhenThereIsNoHistory() {
        var model = ClipboardPanelModel(items: [])
        model.setPaused(true)
        XCTAssertEqual(model.emptyState, .paused)
        model.setItems(fiveTexts())
        XCTAssertNil(model.emptyState)
        model.setQuery("zzz")
        XCTAssertEqual(model.emptyState, .noResults, "有歷史但搜尋不到：顯示找不到，暫停狀態改由橫幅表達")
    }

    func testNeedsPermissionTakesPrecedenceOverPausedAndNoHistory() {
        var model = ClipboardPanelModel(items: [], isPaused: true, needsPermission: true)
        XCTAssertEqual(model.emptyState, .needsPermission)
        model.setNeedsPermission(false)
        XCTAssertEqual(model.emptyState, .paused)
        model.setPaused(false)
        XCTAssertEqual(model.emptyState, .noHistory)
    }

    func testBannerPrecedenceAndVisibilityWithItems() {
        var model = ClipboardPanelModel(items: fiveTexts())
        XCTAssertNil(model.banner)
        model.setPaused(true)
        XCTAssertEqual(model.banner, .paused)
        model.setNeedsPermission(true)
        XCTAssertEqual(model.banner, .needsPermission, "權限問題比暫停更要緊")
        model.setNeedsPermission(false)
        model.setPaused(false)
        XCTAssertNil(model.banner)
    }

    func testEmptyStateIsNilWhenListHasRows() {
        let model = ClipboardPanelModel(items: fiveTexts(), isPaused: true, needsPermission: true)
        XCTAssertNil(model.emptyState)
        XCTAssertEqual(model.visibleItems.count, 5)
    }

    func testInitialParametersAreApplied() {
        let model = ClipboardPanelModel(
            items: [text("alpha", at: 1), image("x", at: 2)], query: "alp", filter: .text, isPaused: true, needsPermission: false
        )
        XCTAssertEqual(texts(model), ["alpha"])
        XCTAssertEqual(model.query, "alp")
        XCTAssertEqual(model.filter, .text)
        XCTAssertTrue(model.isPaused)
        XCTAssertFalse(model.needsPermission)
    }
}
