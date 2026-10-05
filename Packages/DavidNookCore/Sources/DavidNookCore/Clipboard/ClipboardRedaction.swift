import Foundation

// 隱私：持有剪貼簿內容的型別，被 print／字串內插／String(describing:)／String(reflecting:)／dump 時，
// 一律只輸出「種類與位元組數（或筆數）」加 `<redacted>`。
//   - CustomStringConvertible／CustomDebugStringConvertible 管 print、內插、describing、reflecting；
//   - CustomReflectable 管 dump 與 Mirror（dump 只看反射，不看 description）。
// 即使某天有人在除錯時隨手 print 了一個條目、快照或整個模型，也不會把使用者複製的內容寫進 console 或 log。

/// 遮蔽用的共用輔助。
enum ClipboardRedaction {
    /// `Name(<redacted> detail)`。
    static func describe(_ name: String, _ detail: String) -> String {
        detail.isEmpty ? "\(name)(<redacted>)" : "\(name)(<redacted> \(detail))"
    }

    /// 只暴露一個 `redacted` 子項的反射，讓 dump／Mirror 看不到真正的欄位。
    static func mirror(_ subject: Any, _ summary: String) -> Mirror {
        Mirror(subject, children: ["redacted": summary], displayStyle: .struct)
    }
}

extension ClipboardItem: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// 只含種類與位元組數（文字）／筆數（檔案）。
    public var description: String {
        switch kind {
        case .text: return ClipboardRedaction.describe("ClipboardItem", "kind=text, bytes=\(text?.utf8.count ?? 0)")
        case .image: return ClipboardRedaction.describe("ClipboardItem", "kind=image")
        case .files: return ClipboardRedaction.describe("ClipboardItem", "kind=files, count=\(filePaths?.count ?? 0)")
        }
    }
    /// 同 `description`。
    public var debugDescription: String { description }
    /// dump／Mirror 只看得到遮蔽後的摘要。
    public var customMirror: Mirror { ClipboardRedaction.mirror(self, description) }
}

extension ClipboardCapture.Payload: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// 只含種類與位元組數／筆數。
    public var description: String {
        switch self {
        case .text(let string): return ClipboardRedaction.describe("Payload", "kind=text, bytes=\(string.utf8.count)")
        case .image(let data, _): return ClipboardRedaction.describe("Payload", "kind=image, bytes=\(data.count)")
        case .files(let paths): return ClipboardRedaction.describe("Payload", "kind=files, count=\(paths.count)")
        }
    }
    /// 同 `description`。
    public var debugDescription: String { description }
    /// dump／Mirror 只看得到遮蔽後的摘要。
    public var customMirror: Mirror { ClipboardRedaction.mirror(self, description) }
}

extension ClipboardCapture: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// 只含種類與位元組數／筆數（不含來源 App、雜湊）。
    public var description: String {
        switch payload {
        case .text(let string): return ClipboardRedaction.describe("ClipboardCapture", "kind=text, bytes=\(string.utf8.count)")
        case .image(let data, _): return ClipboardRedaction.describe("ClipboardCapture", "kind=image, bytes=\(data.count)")
        case .files(let paths): return ClipboardRedaction.describe("ClipboardCapture", "kind=files, count=\(paths.count)")
        }
    }
    /// 同 `description`。
    public var debugDescription: String { description }
    /// dump／Mirror 只看得到遮蔽後的摘要。
    public var customMirror: Mirror { ClipboardRedaction.mirror(self, description) }
}

extension PasteboardSnapshot: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// 只含 changeCount 與型別數量；不會呼叫資料或來源 App 的讀取閉包（字串化不得觸發任何剪貼簿讀取）。
    public var description: String {
        ClipboardRedaction.describe("PasteboardSnapshot", "changeCount=\(changeCount), types=\(types.count)")
    }
    /// 同 `description`。
    public var debugDescription: String { description }
    /// dump／Mirror 只看得到遮蔽後的摘要。
    public var customMirror: Mirror { ClipboardRedaction.mirror(self, description) }
}

extension PasteboardRepresentation: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// 只含型別字串與位元組數。
    public var description: String {
        ClipboardRedaction.describe("PasteboardRepresentation", "type=\(type), bytes=\(data.count)")
    }
    /// 同 `description`。
    public var debugDescription: String { description }
    /// dump／Mirror 只看得到遮蔽後的摘要。
    public var customMirror: Mirror { ClipboardRedaction.mirror(self, description) }
}

extension ClipboardPanelModel: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// 只含筆數（模型持有全部條目與使用者輸入的搜尋字串）。
    public var description: String {
        ClipboardRedaction.describe("ClipboardPanelModel", "items=\(allItems.count), visible=\(visibleItems.count)")
    }
    /// 同 `description`。
    public var debugDescription: String { description }
    /// dump／Mirror 只看得到遮蔽後的摘要。
    public var customMirror: Mirror { ClipboardRedaction.mirror(self, description) }
}
