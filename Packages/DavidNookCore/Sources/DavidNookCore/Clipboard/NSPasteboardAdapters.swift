import AppKit

/// 讓 NSPasteboard 能被 @Sendable 閉包捕捉（NSPasteboard 可跨執行緒使用，且此處只做唯讀存取）。
private struct PasteboardBox: @unchecked Sendable {
    let pasteboard: NSPasteboard
}

/// 包裝 NSPasteboard 的讀取端。由呼叫端傳入要監看的剪貼簿（系統剪貼簿由 App 傳入；測試只能傳具名剪貼簿）。
///
/// - `changeCount` 只讀計數，不讀任何內容。
/// - `snapshot()` 只收集型別清單（跨所有 pasteboard item 的聯集）；資料與來源 App 都是用到才讀。
///
/// NSPasteboard 本身可跨執行緒存取；此類別無可變狀態，因此標為 @unchecked Sendable。
public final class NSPasteboardReader: PasteboardReading, @unchecked Sendable {
    private let pasteboard: NSPasteboard
    private let sourceAppProvider: @Sendable () -> String?
    private let dataReadObserver: (@Sendable (String) -> Void)?

    /// 建立 reader。sourceAppProvider 在剪貼簿沒有 `org.nspasteboard.source` 時作為後備（預設取最前景 App 的 bundle id）。
    /// `dataReadObserver`（測試用）：每次真的向 NSPasteboard 讀取某型別的「資料」前呼叫一次，參數為型別字串。
    /// 用來證明被略過（例如機密）的快照在 reader 層完全沒有讀取內容；正式 App 不傳。
    public init(
        pasteboard: NSPasteboard,
        sourceAppProvider: @escaping @Sendable () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier },
        dataReadObserver: (@Sendable (String) -> Void)? = nil
    ) {
        self.pasteboard = pasteboard
        self.sourceAppProvider = sourceAppProvider
        self.dataReadObserver = dataReadObserver
    }

    /// 目前的 changeCount。
    public var changeCount: Int {
        pasteboard.changeCount
    }

    /// 取得快照（不讀資料）。
    public func snapshot() -> PasteboardSnapshot {
        let count = pasteboard.changeCount
        var types: [String] = []
        func append(_ raw: String) {
            if !types.contains(raw) { types.append(raw) }
        }
        for item in pasteboard.pasteboardItems ?? [] {
            for type in item.types { append(type.rawValue) }
        }
        for type in pasteboard.types ?? [] { append(type.rawValue) }

        let box = PasteboardBox(pasteboard: pasteboard)
        let provider = sourceAppProvider
        return PasteboardSnapshot(
            changeCount: count,
            types: types,
            sourceAppBundleIDProvider: {
                let sourceType = NSPasteboard.PasteboardType(ClipboardPasteboardType.source)
                if let data = box.pasteboard.pasteboardItems?.lazy.compactMap({ $0.data(forType: sourceType) }).first,
                   let id = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !id.isEmpty {
                    return id
                }
                return provider()
            },
            dataProvider: { raw in
                let type = NSPasteboard.PasteboardType(raw)
                let fromItems = box.pasteboard.pasteboardItems?.compactMap { $0.data(forType: type) } ?? []
                if !fromItems.isEmpty { return fromItems }
                return box.pasteboard.data(forType: type).map { [$0] } ?? []
            }
        )
    }
}

/// 包裝 NSPasteboard 的寫入端：清空後寫入多個 pasteboard item。
public final class NSPasteboardWriter: PasteboardWriting, @unchecked Sendable {
    private let pasteboard: NSPasteboard

    /// 建立 writer。
    public init(pasteboard: NSPasteboard) {
        self.pasteboard = pasteboard
    }

    /// 清空並寫入；回傳寫入完成後的 changeCount。
    public func write(_ items: [[PasteboardRepresentation]]) -> Int {
        pasteboard.clearContents()
        let pasteboardItems: [NSPasteboardItem] = items.map { representations in
            let item = NSPasteboardItem()
            for representation in representations {
                item.setData(representation.data, forType: NSPasteboard.PasteboardType(representation.type))
            }
            return item
        }
        pasteboard.writeObjects(pasteboardItems)
        return pasteboard.changeCount
    }
}
