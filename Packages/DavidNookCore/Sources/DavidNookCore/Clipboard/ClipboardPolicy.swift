import Foundation

/// 為什麼略過一個快照（只用於 log 與回傳，不含任何內容）。
public enum ClipboardSkipReason: Equatable, Sendable {
    /// 暫停記錄中。
    case paused
    /// 含密碼管理員等的隱私標記型別。
    case sensitiveType
    /// 空字串、純空白或空資料。
    case empty
    /// 超過大小上限。
    case tooLarge
    /// 沒有支援的型別，或資料無法解讀。
    case unsupported
}

/// policy 對一個快照的決定。
public enum ClipboardDecision: Equatable, Sendable {
    /// 應該記錄這份內容。
    case record(ClipboardCapture)
    /// 這是本 app 自己寫回的內容：不新增條目；itemID 為標記中帶的條目 id（若有），呼叫端應 bump 該條目。
    case ownWrite(itemID: UUID?)
    /// 不記錄。
    case skip(ClipboardSkipReason)
}

/// 決定一個剪貼簿快照是否該記錄、記成哪一種。純函式，無副作用。
public struct ClipboardPolicy: Sendable, Equatable {
    /// 文字上限（UTF-8 位元組），預設 1MB。
    public var maxTextBytes: Int
    /// 圖片上限（位元組），預設 20MB。
    public var maxImageBytes: Int
    /// 出現任一型別就整份略過（隱私標記）。比對不分大小寫。
    public var ignoredTypes: Set<String>

    /// 建立 policy；未指定的欄位用預設值。
    public init(
        maxTextBytes: Int = 1_048_576,
        maxImageBytes: Int = 20 * 1_048_576,
        ignoredTypes: Set<String> = ClipboardPasteboardType.defaultIgnored
    ) {
        self.maxTextBytes = maxTextBytes
        self.maxImageBytes = maxImageBytes
        self.ignoredTypes = ignoredTypes
    }

    /// 評估快照。順序：暫停 → 隱私標記型別（只看型別清單，不讀資料）→ 自己寫的（只讀標記）→ 內容。
    ///
    /// 內容種類優先序：files > image > text。
    /// 原因：從 Finder 複製檔案時，剪貼簿會同時帶有「檔名文字」與「檔案圖示圖片」；
    /// 若 text/image 優先，就會把檔案誤記成一段檔名或一張圖示。
    /// image 排在 text 之前，是因為從瀏覽器複製圖片等情境常同時帶有網址文字，使用者要的是圖片。
    public func evaluate(_ snapshot: PasteboardSnapshot, isPaused: Bool = false) -> ClipboardDecision {
        if isPaused { return .skip(.paused) }

        let ignored = Set(ignoredTypes.map { $0.lowercased() })
        if snapshot.types.contains(where: { ignored.contains($0.lowercased()) }) {
            return .skip(.sensitiveType)
        }

        if snapshot.hasType(ClipboardPasteboardType.selfMarker) {
            let id = snapshot.data(forType: ClipboardPasteboardType.selfMarker)
                .flatMap { String(data: $0, encoding: .utf8) }
                .flatMap { UUID(uuidString: $0) }
            return .ownWrite(itemID: id)
        }

        // 1) 檔案
        if snapshot.hasType(ClipboardPasteboardType.fileURL) {
            let paths = snapshot.allData(forType: ClipboardPasteboardType.fileURL).compactMap(Self.path(fromFileURLData:))
            if !paths.isEmpty {
                return .record(ClipboardCapture(filePaths: paths, sourceAppBundleID: snapshot.sourceAppBundleID))
            }
        }

        // 2) 圖片（PNG 優先於 TIFF）
        let imageChoice: (type: String, ext: String)?
        if snapshot.hasType(ClipboardPasteboardType.png) {
            imageChoice = (ClipboardPasteboardType.png, "png")
        } else if snapshot.hasType(ClipboardPasteboardType.tiff) {
            imageChoice = (ClipboardPasteboardType.tiff, "tiff")
        } else {
            imageChoice = nil
        }
        if let imageChoice, let data = snapshot.data(forType: imageChoice.type) {
            if data.isEmpty { return .skip(.empty) }
            if data.count > maxImageBytes { return .skip(.tooLarge) }
            return .record(ClipboardCapture(imageData: data, fileExtension: imageChoice.ext, sourceAppBundleID: snapshot.sourceAppBundleID))
        }

        // 3) 文字
        if snapshot.hasType(ClipboardPasteboardType.utf8Text) {
            guard let data = snapshot.data(forType: ClipboardPasteboardType.utf8Text) else { return .skip(.unsupported) }
            if data.count > maxTextBytes { return .skip(.tooLarge) }
            guard let string = String(data: data, encoding: .utf8) else { return .skip(.unsupported) }
            if string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .skip(.empty) }
            return .record(ClipboardCapture(text: string, sourceAppBundleID: snapshot.sourceAppBundleID))
        }

        return .skip(.unsupported)
    }

    /// 把 public.file-url 的資料（"file:///..." 字串）轉成檔案系統路徑；非 file URL 回傳 nil。
    static func path(fromFileURLData data: Data) -> String? {
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{0}")))
        guard !trimmed.isEmpty, let url = URL(string: trimmed), url.isFileURL else { return nil }
        // 檔案參照 URL（file:///.file/id=...）會被解析為實際路徑
        let resolved = (url as NSURL).filePathURL ?? url
        let path = resolved.path
        return path.isEmpty ? nil : path
    }
}
