import XCTest
@testable import DavidNookCore

/// 元件 4（並發）：ClipboardStore 是 actor，所有狀態與持久化寫入都在 actor 內串行執行。
/// 這些測試從大量並發任務同時存取，驗證不變量成立（無重複、無殘留或懸空圖片檔、記憶體與磁碟一致）。
final class ClipboardStoreConcurrencyTests: XCTestCase {
    func testConcurrentAddsOfDistinctAndDuplicateContentStayConsistent() async {
        let persistence = InMemoryClipboardPersistence()
        let store = ClipboardStore(persistence: persistence, maxItems: 1000)
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask { _ = await store.add(ClipboardCapture(text: "unique-\(i)"), now: t(Double(i))) }
                group.addTask { _ = await store.add(ClipboardCapture(text: "shared"), now: t(Double(i))) }
            }
        }
        let items = await store.items
        XCTAssertEqual(items.count, 101, "100 筆不同內容 + 1 筆被重複複製 100 次的內容")
        XCTAssertEqual(Set(items.map(\.dedupKey)).count, 101, "不得有重複內容")
        XCTAssertEqual(Set(persistence.loadItems().map(\.id)), Set(items.map(\.id)), "磁碟索引與記憶體一致")
    }

    func testConcurrentMixedOperationsKeepInvariants() async {
        let persistence = InMemoryClipboardPersistence()
        let store = ClipboardStore(persistence: persistence, maxItems: 15)
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<80 {
                group.addTask { _ = await store.add(ClipboardCapture(text: "t\(i % 25)"), now: t(Double(i))) }
                group.addTask { _ = await store.add(ClipboardCapture(imageData: Data("img\(i % 12)".utf8)), now: t(Double(i))) }
                group.addTask {
                    if let first = await store.items.first { _ = await store.togglePin(id: first.id) }
                }
                group.addTask { _ = await store.search(query: "t1") }
                group.addTask {
                    if let last = await store.items.last { _ = await store.remove(id: last.id) }
                }
                group.addTask { _ = await store.prune(now: t(10_000)) }
                if i % 20 == 0 {
                    group.addTask { await store.clearUnpinned() }
                }
            }
        }
        let items = await store.items
        XCTAssertEqual(Set(items.map(\.dedupKey)).count, items.count, "無重複內容")
        let referenced = Set(items.compactMap(\.imageFileName))
        XCTAssertEqual(Set(persistence.imageFileNames()), referenced, "磁碟上的圖片檔 == 條目所參照的圖片檔（無殘留、無懸空）")
        XCTAssertEqual(Set(persistence.loadItems().map(\.id)), Set(items.map(\.id)))
        let unpinned = items.filter { !$0.isPinned }.count
        XCTAssertLessThanOrEqual(unpinned, 15, "未釘選筆數不得超過上限")
    }

    func testConcurrentPauseAndResumeNeverCorruptsState() async {
        let store = ClipboardStore(persistence: InMemoryClipboardPersistence(), maxItems: 500)
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask { _ = await store.add(ClipboardCapture(text: "n\(i)"), now: t(Double(i))) }
                group.addTask { i.isMultiple(of: 2) ? await store.pause() : await store.resume() }
            }
        }
        await store.resume()
        let items = await store.items
        XCTAssertLessThanOrEqual(items.count, 100)
        XCTAssertEqual(Set(items.map(\.dedupKey)).count, items.count)
        _ = await store.add(ClipboardCapture(text: "after"), now: t(999))
        let after = await store.items.first?.text
        XCTAssertEqual(after, "after")
    }

    func testConcurrentClearAllWhileAddingLeavesNoDanglingImageFiles() async throws {
        let persistence = InMemoryClipboardPersistence()
        let store = ClipboardStore(persistence: persistence, maxItems: 500)
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<60 {
                group.addTask { _ = await store.add(ClipboardCapture(imageData: Data("i\(i)".utf8)), now: t(Double(i))) }
            }
            group.addTask { try? await store.clearAll() }
        }
        let items = await store.items
        XCTAssertEqual(Set(persistence.imageFileNames()), Set(items.compactMap(\.imageFileName)))
        try await store.clearAll()
        XCTAssertEqual(persistence.imageFileNames(), [])
    }
}
