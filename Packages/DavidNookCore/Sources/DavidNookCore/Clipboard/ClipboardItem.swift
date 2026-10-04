import CryptoKit
import Foundation

/// 剪貼簿條目的種類。
public enum ClipboardKind: String, Codable, Sendable, CaseIterable {
    /// 純文字。
    case text
    /// 圖片（內容存在磁碟檔，條目只記檔名）。
    case image
    /// 一個或多個檔案路徑。
    case files
}

/// 內容雜湊（SHA-256，小寫十六進位）。
public enum ClipboardHash {
    /// 對任意資料計算 SHA-256。
    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// 文字：以 UTF-8 位元組計算。
    public static func text(_ string: String) -> String {
        sha256Hex(Data(string.utf8))
    }

    /// 圖片：以原始資料計算。
    public static func image(_ data: Data) -> String {
        sha256Hex(data)
    }

    /// 檔案：路徑排序後以 NUL 字元串接再計算（NUL 不會出現在路徑中，避免 ["ab","c"] 與 ["a","bc"] 撞 hash）。
    public static func files(_ paths: [String]) -> String {
        sha256Hex(Data(paths.sorted().joined(separator: "\u{0}").utf8))
    }
}

/// 一次「待記錄」的內容（policy 的輸出、store 的輸入）：內容＋雜湊＋來源 App。
public struct ClipboardCapture: Equatable, Sendable {
    /// 內容本體。
    public enum Payload: Equatable, Sendable {
        /// 文字。
        case text(String)
        /// 圖片原始資料與副檔名（png / tiff）。
        case image(Data, fileExtension: String)
        /// 檔案路徑。
        case files([String])
    }

    /// 內容本體。
    public let payload: Payload
    /// 來源 App 的 bundle id（選填）。
    public let sourceAppBundleID: String?
    /// 內容雜湊（見 ClipboardHash）。
    public let contentHash: String

    /// 以 payload 建立；圖片副檔名會被清理成只含小寫英數（防止路徑穿越）。
    public init(payload: Payload, sourceAppBundleID: String? = nil) {
        switch payload {
        case .image(let data, let fileExtension):
            self.payload = .image(data, fileExtension: Self.sanitizedExtension(fileExtension))
            self.contentHash = ClipboardHash.image(data)
        case .text(let string):
            self.payload = payload
            self.contentHash = ClipboardHash.text(string)
        case .files(let paths):
            self.payload = payload
            self.contentHash = ClipboardHash.files(paths)
        }
        self.sourceAppBundleID = sourceAppBundleID
    }

    /// 文字內容。
    public init(text: String, sourceAppBundleID: String? = nil) {
        self.init(payload: .text(text), sourceAppBundleID: sourceAppBundleID)
    }

    /// 圖片內容（預設 PNG）。
    public init(imageData: Data, fileExtension: String = "png", sourceAppBundleID: String? = nil) {
        self.init(payload: .image(imageData, fileExtension: fileExtension), sourceAppBundleID: sourceAppBundleID)
    }

    /// 檔案路徑內容。
    public init(filePaths: [String], sourceAppBundleID: String? = nil) {
        self.init(payload: .files(filePaths), sourceAppBundleID: sourceAppBundleID)
    }

    /// 內容種類。
    public var kind: ClipboardKind {
        switch payload {
        case .text: return .text
        case .image: return .image
        case .files: return .files
        }
    }

    /// 去重鍵（與 ClipboardItem.dedupKey 同格式）。
    public var dedupKey: String {
        "\(kind.rawValue):\(contentHash)"
    }

    static func sanitizedExtension(_ raw: String) -> String {
        let cleaned = raw.lowercased().filter { ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") }
        let limited = String(cleaned.prefix(8))
        return limited.isEmpty ? "bin" : limited
    }
}

/// 一筆剪貼簿歷史條目。內容欄位依 kind 擇一有值：文字 / 圖片檔名 / 檔案路徑。
/// 圖片本體不放記憶體，只記磁碟檔名（`<contentHash>.<副檔名>`）。
public struct ClipboardItem: Codable, Identifiable, Equatable, Sendable {
    /// 條目唯一識別碼。
    public let id: UUID
    /// 內容種類。
    public let kind: ClipboardKind
    /// 文字內容（kind == .text）。
    public let text: String?
    /// 圖片檔名（kind == .image）。
    public let imageFileName: String?
    /// 檔案路徑（kind == .files），保留複製時的順序。
    public let filePaths: [String]?
    /// 內容 SHA-256（小寫十六進位）。
    public let contentHash: String
    /// 首次記錄時間。
    public let createdAt: Date
    /// 最近一次使用（重新複製或點選貼回）的時間。
    public var lastUsedAt: Date
    /// 是否釘選（釘選不被上限與保留期淘汰）。
    public var isPinned: Bool
    /// 來源 App 的 bundle id（選填）。
    public var sourceAppBundleID: String?

    /// 去重鍵：同 kind 且同 contentHash 才算重複（文字 "/a/b" 與檔案 ["/a/b"] 的 hash 相同但不是同一件事）。
    public var dedupKey: String {
        "\(kind.rawValue):\(contentHash)"
    }

    /// 圖片檔的副檔名（僅 kind == .image）。
    public var imageFileExtension: String? {
        guard let imageFileName, let dot = imageFileName.lastIndex(of: ".") else { return nil }
        return String(imageFileName[imageFileName.index(after: dot)...])
    }

    private init(
        id: UUID, kind: ClipboardKind, text: String?, imageFileName: String?, filePaths: [String]?,
        contentHash: String, createdAt: Date, lastUsedAt: Date, isPinned: Bool, sourceAppBundleID: String?
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imageFileName = imageFileName
        self.filePaths = filePaths
        self.contentHash = contentHash
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.isPinned = isPinned
        self.sourceAppBundleID = sourceAppBundleID
    }

    /// 由待記錄內容建立條目。
    public init(capture: ClipboardCapture, id: UUID = UUID(), now: Date = Date(), isPinned: Bool = false) {
        switch capture.payload {
        case .text(let string):
            self.init(id: id, kind: .text, text: string, imageFileName: nil, filePaths: nil,
                      contentHash: capture.contentHash, createdAt: now, lastUsedAt: now,
                      isPinned: isPinned, sourceAppBundleID: capture.sourceAppBundleID)
        case .image(_, let fileExtension):
            self.init(id: id, kind: .image, text: nil, imageFileName: "\(capture.contentHash).\(fileExtension)", filePaths: nil,
                      contentHash: capture.contentHash, createdAt: now, lastUsedAt: now,
                      isPinned: isPinned, sourceAppBundleID: capture.sourceAppBundleID)
        case .files(let paths):
            self.init(id: id, kind: .files, text: nil, imageFileName: nil, filePaths: paths,
                      contentHash: capture.contentHash, createdAt: now, lastUsedAt: now,
                      isPinned: isPinned, sourceAppBundleID: capture.sourceAppBundleID)
        }
    }

    /// 建立文字條目。
    public init(id: UUID = UUID(), text: String, now: Date = Date(), isPinned: Bool = false, sourceAppBundleID: String? = nil) {
        self.init(capture: ClipboardCapture(text: text, sourceAppBundleID: sourceAppBundleID), id: id, now: now, isPinned: isPinned)
    }

    /// 建立圖片條目（只記檔名，不保留 imageData）。
    public init(
        id: UUID = UUID(), imageData: Data, fileExtension: String = "png",
        now: Date = Date(), isPinned: Bool = false, sourceAppBundleID: String? = nil
    ) {
        self.init(capture: ClipboardCapture(imageData: imageData, fileExtension: fileExtension, sourceAppBundleID: sourceAppBundleID),
                  id: id, now: now, isPinned: isPinned)
    }

    /// 建立檔案條目。
    public init(id: UUID = UUID(), filePaths: [String], now: Date = Date(), isPinned: Bool = false, sourceAppBundleID: String? = nil) {
        self.init(capture: ClipboardCapture(filePaths: filePaths, sourceAppBundleID: sourceAppBundleID),
                  id: id, now: now, isPinned: isPinned)
    }

    // MARK: Codable（解碼時驗證 kind 與內容欄位一致，不一致視為損毀）

    private enum CodingKeys: String, CodingKey {
        case id, kind, text, imageFileName, filePaths, contentHash, createdAt, lastUsedAt, isPinned, sourceAppBundleID
    }

    /// 解碼；kind 與內容欄位不一致時拋出 DecodingError。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(ClipboardKind.self, forKey: .kind)
        let text = try c.decodeIfPresent(String.self, forKey: .text)
        let imageFileName = try c.decodeIfPresent(String.self, forKey: .imageFileName)
        let filePaths = try c.decodeIfPresent([String].self, forKey: .filePaths)
        switch kind {
        case .text where text == nil,
             .image where imageFileName == nil,
             .files where filePaths == nil:
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "kind 與內容欄位不一致"))
        default:
            break
        }
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            kind: kind,
            text: kind == .text ? text : nil,
            imageFileName: kind == .image ? imageFileName : nil,
            filePaths: kind == .files ? filePaths : nil,
            contentHash: try c.decode(String.self, forKey: .contentHash),
            createdAt: try c.decode(Date.self, forKey: .createdAt),
            lastUsedAt: try c.decode(Date.self, forKey: .lastUsedAt),
            isPinned: try c.decode(Bool.self, forKey: .isPinned),
            sourceAppBundleID: try c.decodeIfPresent(String.self, forKey: .sourceAppBundleID)
        )
    }

    // MARK: 寫回剪貼簿

    /// 產生「點選後寫回剪貼簿」所需的表示法：每個元素是一個 pasteboard item，並都附上本 app 的標記型別
    /// （資料為本條目的 UUID），讓 monitor 認得這是自己寫的。
    /// 圖片條目需要呼叫端提供圖片資料；缺資料或副檔名不支援時回傳 nil。
    public func pasteboardRepresentations(imageData: Data? = nil) -> [[PasteboardRepresentation]]? {
        let marker = PasteboardRepresentation(type: ClipboardPasteboardType.selfMarker, data: Data(id.uuidString.utf8))
        switch kind {
        case .text:
            guard let text else { return nil }
            return [[PasteboardRepresentation(type: ClipboardPasteboardType.utf8Text, data: Data(text.utf8)), marker]]
        case .image:
            guard let imageData, let ext = imageFileExtension else { return nil }
            let type: String
            switch ext {
            case "png": type = ClipboardPasteboardType.png
            case "tiff", "tif": type = ClipboardPasteboardType.tiff
            default: return nil
            }
            return [[PasteboardRepresentation(type: type, data: imageData), marker]]
        case .files:
            guard let filePaths, !filePaths.isEmpty else { return nil }
            return filePaths.map { path in
                [PasteboardRepresentation(type: ClipboardPasteboardType.fileURL,
                                          data: Data(URL(fileURLWithPath: path).absoluteString.utf8)), marker]
            }
        }
    }
}
