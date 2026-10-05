import AppKit
import XCTest
@testable import DavidNookCore

/// 需要真實 NSPasteboard 的測試基底：只使用 NSPasteboard(name:) 建立的「測試專用具名剪貼簿」，
/// 每個測試一個獨立名稱，tearDown 時 releaseGlobally 釋放。絕不碰使用者的系統剪貼簿。
class NamedPasteboardTestCase: XCTestCase {
    var pasteboard: NSPasteboard!

    override func setUp() {
        super.setUp()
        let name = NSPasteboard.Name("io.github.davidkong3804.DavidNook.tests.\(UUID().uuidString)")
        pasteboard = NSPasteboard(name: name)
        pasteboard.clearContents()
    }

    override func tearDown() {
        pasteboard?.releaseGlobally()
        pasteboard = nil
        super.tearDown()
    }

    /// 以「另一個 App 複製」的方式寫入單一 pasteboard item。
    @discardableResult
    func externalCopy(_ entries: [(String, Data)]) -> Int {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        for (type, data) in entries {
            item.setData(data, forType: NSPasteboard.PasteboardType(type))
        }
        pasteboard.writeObjects([item])
        return pasteboard.changeCount
    }
}
