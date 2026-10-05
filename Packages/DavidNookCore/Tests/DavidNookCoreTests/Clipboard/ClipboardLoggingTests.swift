import XCTest
@testable import DavidNookCore

/// 元件 5（隱私）：任何 log 都不得含有剪貼簿內容。
/// logger 事件是只帶「操作類型與數量」的列舉；這裡用 spy 在各種操作中收集事件，掃描有無任何內容洩漏。
final class ClipboardLoggingTests: XCTestCase {
    private let secretText = "TOPSECRET-TEXT-9f3a"
    private let secretPath = "/Users/secret-user/private-plans.txt"
    private let secretQuery = "TOPSECRET-QUERY"
    private let secretImage = "IMAGE-SECRET-BYTES"
    private let secretApp = "com.secret.app"

    private var allSecrets: [String] {
        [secretText, secretPath, secretQuery, secretImage, secretApp, "secret-user", "private-plans"]
    }

    func testStoreLogsNeverContainContentAcrossEveryKindOfOperation() async throws {
        let spy = SpyClipboardLogger()
        let persistence = InMemoryClipboardPersistence()
        let store = ClipboardStore(persistence: persistence, maxItems: 2, retention: 5, logger: spy)

        let text = await store.add(ClipboardCapture(text: secretText, sourceAppBundleID: secretApp), now: t(1))      // 新增
        _ = await store.add(ClipboardCapture(text: secretText, sourceAppBundleID: secretApp), now: t(2))              // 去重
        _ = await store.add(ClipboardCapture(filePaths: [secretPath]), now: t(3))                                      // 檔案
        _ = await store.add(ClipboardCapture(imageData: Data(secretImage.utf8)), now: t(4))                            // 圖片＋淘汰
        _ = await store.search(query: secretQuery)                                                                     // 搜尋
        guard case .inserted(let item) = text else { return XCTFail("預期 inserted") }
        _ = await store.togglePin(id: item.id)
        _ = await store.togglePin(id: item.id)
        _ = await store.bump(id: item.id, now: t(5))
        _ = await store.prune(now: t(1000))                                                                            // 過期
        await store.setMaxItems(1)
        await store.setRetention(1)
        _ = await store.remove(id: item.id)
        await store.pause()
        _ = await store.add(ClipboardCapture(text: secretText), now: t(6))                                             // 暫停中
        await store.resume()
        _ = await store.add(ClipboardCapture(text: secretText), now: t(7))
        await store.clearUnpinned()
        try await store.clearAll()

        XCTAssertFalse(spy.events.isEmpty, "至少要有操作類型的紀錄，否則這個測試沒有意義")
        spy.assertNoneContain(allSecrets)
    }

    func testEventsCarryOnlyOperationTypesAndCounts() async throws {
        let spy = SpyClipboardLogger()
        let store = ClipboardStore(persistence: InMemoryClipboardPersistence(), maxItems: 2, logger: spy)
        let first = await store.add(ClipboardCapture(text: "a"), now: t(1))
        _ = await store.add(ClipboardCapture(text: "a"), now: t(2))
        _ = await store.add(ClipboardCapture(text: "b"), now: t(3))
        guard case .inserted(let a) = first else { return XCTFail("預期 inserted") }
        _ = await store.togglePin(id: a.id)
        _ = await store.add(ClipboardCapture(text: "c"), now: t(4))
        _ = await store.add(ClipboardCapture(text: "d"), now: t(5))   // 未釘選 b、c、d 超出上限 2 → 淘汰 b
        _ = await store.remove(id: a.id)
        try await store.clearAll()

        XCTAssertEqual(spy.events, [
            .loaded(count: 0),
            .itemAdded(kind: .text),
            .itemDeduplicated(kind: .text),
            .itemAdded(kind: .text),
            .pinChanged(isPinned: true),
            .itemAdded(kind: .text),
            .itemAdded(kind: .text),
            .itemsEvicted(count: 1),
            .itemRemoved,
            .cleared(count: 2, includingPinned: true),
        ])
    }

    func testPersistenceFailureIsLoggedByOperationNameOnly() async {
        let spy = SpyClipboardLogger()
        let store = ClipboardStore(persistence: FailingImagePersistence(), logger: spy)
        _ = await store.add(ClipboardCapture(imageData: Data(secretImage.utf8)), now: t(1))
        XCTAssertTrue(spy.events.contains(.persistenceFailed(operation: .saveImage)))
        spy.assertNoneContain(allSecrets + ["Failure"])
    }

    func testFilePersistenceLogsNeverContainContentOrPaths() throws {
        let spy = SpyClipboardLogger()
        let root = try makeTempDirectory(for: self)
        let directory = root.appendingPathComponent("Clipboard")
        let persistence = try FileClipboardPersistence(directory: directory, logger: spy)
        let secretItem = ClipboardItem(text: secretText)
        let missingImage = ClipboardItem(imageData: Data(secretImage.utf8))
        try persistence.saveItems([secretItem, missingImage])
        XCTAssertEqual(persistence.loadItems().count, 1)                         // 圖片遺失被丟棄
        try Data("{broken \(secretText)".utf8).write(to: directory.appendingPathComponent("index.json"))
        XCTAssertEqual(persistence.loadItems(), [])                              // 損毀
        try persistence.deleteAll()

        XCTAssertTrue(spy.events.contains(.indexCorrupted))
        spy.assertNoneContain(allSecrets + [directory.path, root.path])
    }

    func testMonitorLogsNeverContainContent() async throws {
        let spy = SpyClipboardLogger()
        let pasteboard = FakePasteboard()
        let persistence = InMemoryClipboardPersistence()
        let store = ClipboardStore(persistence: persistence, logger: spy)
        let monitor = ClipboardMonitor(reader: pasteboard, store: store, scheduler: ManualClipboardScheduler(), logger: spy)
        await monitor.start()

        pasteboard.copy([PBType.utf8Text: Data(secretText.utf8)])                                       // 記錄
        await monitor.pollOnce(now: t(1))
        pasteboard.copy([PBType.utf8Text: Data(secretText.utf8), PBType.concealed: Data()])             // 隱私型別
        await monitor.pollOnce(now: t(2))
        pasteboard.copy(["public.rtf": Data(secretText.utf8)])                                          // 不支援
        await monitor.pollOnce(now: t(3))
        pasteboard.copy([PBType.fileURL: fileURLData(secretPath)])
        await monitor.pollOnce(now: t(4))
        pasteboard.copy([PBType.png: Data(secretImage.utf8)])
        await monitor.pollOnce(now: t(5))
        let items = await store.items
        for item in items { _ = try await monitor.writeBack(item: item, to: pasteboard, now: t(6)) }   // 寫回
        pasteboard.copy([PBType.utf8Text: Data(secretText.utf8), PBType.selfMarker: Data(UUID().uuidString.utf8)])
        await monitor.pollOnce(now: t(7))                                                               // 自己的標記
        await store.pause()
        pasteboard.copy([PBType.utf8Text: Data(secretText.utf8)])
        await monitor.pollOnce(now: t(8))                                                               // 暫停

        XCTAssertTrue(spy.events.contains(.snapshotSkipped(reason: .sensitiveType)))
        XCTAssertTrue(spy.events.contains(.ownWriteDetected))
        XCTAssertTrue(spy.events.contains(.writtenBack(kind: .image)))
        spy.assertNoneContain(allSecrets)
    }

    /// 靜態把關：所有 Clipboard 相關原始碼（Core、UI 套件、App 端）不得出現任何直接輸出。
    func testClipboardRelatedSourcesContainNoDirectOutputCalls() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Clipboard
            .deletingLastPathComponent()   // DavidNookCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // package root
        let repoRoot = packageRoot.deletingLastPathComponent().deletingLastPathComponent()

        let core = try swiftFiles(under: packageRoot.appendingPathComponent("Sources/DavidNookCore/Clipboard"))
        let ui = try swiftFiles(under: packageRoot.appendingPathComponent("Sources/DavidNookUI")).filter { $0.lastPathComponent.hasPrefix("Clipboard") }
        let app = try swiftFiles(under: repoRoot.appendingPathComponent("boringNotch")).filter { $0.lastPathComponent.hasPrefix("Clipboard") }
        XCTAssertGreaterThanOrEqual(core.count, 8, "Core Clipboard 掃描到的檔案數太少，檢查路徑")
        XCTAssertGreaterThanOrEqual(ui.count, 5, "DavidNookUI Clipboard* 掃描到的檔案數太少，檢查路徑")
        XCTAssertGreaterThanOrEqual(app.count, 3, "App 端 Clipboard* 掃描到的檔案數太少（ClipboardService／TabView／SettingsView），檢查路徑")

        for url in core + ui + app {
            let text = try String(contentsOf: url, encoding: .utf8)
            for violation in ClipboardSourceLogScan.violations(in: text) {
                XCTFail("\(url.lastPathComponent):\(violation.line) 含有直接輸出／系統 log 呼叫：\(violation.content)")
            }
        }
    }

    private func swiftFiles(under directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: directory.path])
        }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    /// 掃描器本身也要被測：每一種禁止的寫法都必須被抓到，合法寫法不可誤判。
    func testLogScannerFlagsEveryForbiddenOutputFormAndOnlyThose() {
        let forbidden = [
            #"print("x")"#,
            #"debugPrint(item)"#,
            #"Swift.print(item)"#,
            #"dump(item)"#,
            #"NSLog("%@", text)"#,
            #"os_log("x")"#,
            #"let logger = Logger(subsystem: "s", category: "c")"#,
            #"Logger(subsystem: "s", category: "c").info("\(secret)")"#,
            #"fputs("x", stderr)"#,
            #"fprintf(stderr, "x")"#,
            #"FileHandle.standardError.write(Data())"#,
            #"try? FileHandle.standardError.write(contentsOf: data)"#,
            #"FileHandle.standardOutput.write(data)"#,
            #"text.write(to: &FileHandle.standardError)"#,
            #"data.write(to: FileHandle.standardError)"#,
            "import os",
            "import OSLog",
        ]
        for line in forbidden {
            XCTAssertFalse(ClipboardSourceLogScan.violations(in: line).isEmpty, "漏抓：\(line)")
        }
        let allowed = [
            "let logger: ClipboardLogging = NoOpClipboardLogger()",
            "logger.log(.itemAdded(kind: .text))",
            "// print(\"commented out\")",
            "/// 不會 print 任何內容",
            "let blueprint = makeBlueprint()",
            "let handle = FileHandle(forReadingAtPath: path)",
            "try data.write(to: url)",
            "import Foundation",
        ]
        for line in allowed {
            XCTAssertTrue(ClipboardSourceLogScan.violations(in: line).isEmpty, "誤判：\(line)")
        }
    }

    func testDefaultLoggerIsANoOp() async {
        let logger: ClipboardLogging = NoOpClipboardLogger()
        logger.log(.itemAdded(kind: .text))
        logger.log(.indexCorrupted)
        // 預設建構 store 不傳 logger 也能正常運作
        let store = ClipboardStore(persistence: InMemoryClipboardPersistence())
        _ = await store.add(ClipboardCapture(text: "x"), now: t(1))
        let count = await store.items.count
        XCTAssertEqual(count, 1)
    }
}

/// 靜態掃描：找出直接輸出到 console／檔案／系統 log 的寫法。
enum ClipboardSourceLogScan {
    /// 前面不能緊接識別字字元，避免誤判 NoOpClipboardLogger() 這類名稱。
    /// print／debugPrint／dump、NSLog／os_log／`Logger(`（不論有沒有內插一律禁止）、fputs／fprintf。
    private static let call = try! NSRegularExpression(pattern: "(?<![A-Za-z0-9_])(print|debugPrint|NSLog|os_log|Logger|dump|fputs|fprintf|vfprintf)\\(")
    /// `FileHandle.standardError`／`standardOutput`，以及 C 的 `stderr`／`stdout`。
    private static let handles = try! NSRegularExpression(pattern: "(?<![A-Za-z0-9_])(FileHandle\\s*\\.\\s*(standardError|standardOutput)|stderr|stdout)(?![A-Za-z0-9_])")
    /// `x.write(to: FileHandle…)`／`x.write(to: &FileHandle…)`。
    private static let writeToHandle = try! NSRegularExpression(pattern: "\\.write\\(to:\\s*&?\\s*FileHandle\\b")
    private static let imp = try! NSRegularExpression(pattern: "^\\s*import\\s+(os|OSLog)\\b")

    static func violations(in text: String) -> [(line: Int, content: String)] {
        var result: [(Int, String)] = []
        for (index, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let content = String(raw)
            if content.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
            let range = NSRange(content.startIndex..., in: content)
            if [call, handles, writeToHandle, imp].contains(where: { $0.firstMatch(in: content, range: range) != nil }) {
                result.append((index + 1, content))
            }
        }
        return result
    }
}
