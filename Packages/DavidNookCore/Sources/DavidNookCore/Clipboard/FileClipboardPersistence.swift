import Foundation

/// 檔案版持久化：索引為 `index.json`，圖片為 `<hash>.<副檔名>`，全部放在可注入的目錄內。
///
/// - 目錄權限 0700、檔案權限 0600；目錄標為「排除備份」（Time Machine 不會備份明文歷史，新建與既有目錄都會補設）。
/// - 寫入採「同目錄暫存檔（建立時就是 0600）→ fsync → rename」的原子寫入；寫入失敗不會破壞既有檔案。
/// - 載入時容忍損毀：整份索引壞掉 → 回傳空並把壞檔改名為 `index.json.corrupt`；個別條目壞掉或圖片檔遺失 → 只丟棄該條目。
/// - 圖片檔名嚴格驗證（`<64 位小寫 hex>.<1–8 位小寫英數>`），不可能穿越到目錄之外。
/// - 不輸出任何內容到 log；logger 只收到事件類型與數量。
public final class FileClipboardPersistence: ClipboardPersistence, @unchecked Sendable {
    /// 索引檔名。
    public static let indexFileName = "index.json"
    /// 損毀索引的備份副檔名後綴。
    public static let corruptSuffix = ".corrupt"
    /// 目前索引格式版本。
    static let indexVersion = 1
    private static let tempMarker = ".tmp-"

    /// 存放目錄。
    public let directory: URL
    private let logger: ClipboardLogging
    private let lock = NSLock()

    /// 建立持久化並確保目錄存在且權限為 0700（App 會傳 Application Support/DavidNook/Clipboard）。
    public init(directory: URL, logger: ClipboardLogging = NoOpClipboardLogger()) throws {
        self.directory = directory
        self.logger = logger
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            // 新建或既有（舊版建立、尚未標記）的目錄一律排除備份；失敗就視為目錄不可用，不在可能被備份的地方存明文。
            try BackupExclusion.exclude(directory)
        } catch {
            throw ClipboardPersistenceError.directoryUnavailable
        }
    }

    private var indexURL: URL { directory.appendingPathComponent(Self.indexFileName) }

    // MARK: 索引

    /// 載入索引；損毀不崩潰。
    public func loadItems() -> [ClipboardItem] {
        lock.withLock {
            let fm = FileManager.default
            guard fm.fileExists(atPath: indexURL.path) else { return [] }
            guard let data = try? Data(contentsOf: indexURL),
                  let index = try? JSONDecoder().decode(LossyIndex.self, from: data) else {
                quarantineIndex()
                return []
            }
            var kept: [ClipboardItem] = []
            var dropped = 0
            for entry in index.items {
                guard let item = entry.item else { dropped += 1; continue }
                if item.kind == .image {
                    guard let name = item.imageFileName, imageExistsUnlocked(name) else { dropped += 1; continue }
                }
                kept.append(item)
            }
            if dropped > 0 { logger.log(.itemsDropped(count: dropped)) }
            return kept
        }
    }

    /// 原子寫入整份索引。
    public func saveItems(_ items: [ClipboardItem]) throws {
        try lock.withLock {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(IndexFile(version: Self.indexVersion, items: items))
            try atomicWrite(data, to: indexURL)
        }
    }

    // MARK: 圖片

    /// 寫入圖片檔。
    public func saveImage(_ data: Data, fileName: String) throws {
        guard Self.isValidImageFileName(fileName) else { throw ClipboardPersistenceError.invalidFileName }
        try lock.withLock {
            try atomicWrite(data, to: directory.appendingPathComponent(fileName))
        }
    }

    /// 讀取圖片檔。
    public func loadImage(fileName: String) -> Data? {
        guard Self.isValidImageFileName(fileName) else { return nil }
        return lock.withLock { try? Data(contentsOf: directory.appendingPathComponent(fileName)) }
    }

    /// 圖片檔是否存在。
    public func imageExists(fileName: String) -> Bool {
        lock.withLock { imageExistsUnlocked(fileName) }
    }

    /// 刪除圖片檔（不存在不算錯誤）。
    public func deleteImage(fileName: String) throws {
        guard Self.isValidImageFileName(fileName) else { throw ClipboardPersistenceError.invalidFileName }
        try lock.withLock {
            let url = directory.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: url.path) {
                do { try FileManager.default.removeItem(at: url) } catch { throw ClipboardPersistenceError.deleteFailed }
            }
        }
    }

    /// 目前所有圖片檔名（已排序）。
    public func imageFileNames() -> [String] {
        lock.withLock {
            ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
                .filter(Self.isValidImageFileName)
                .sorted()
        }
    }

    // MARK: 清除

    /// 刪除本 app 產生的全部檔案；不是我們產生的檔案（檔名不符）不會被碰。
    public func deleteAll() throws {
        try lock.withLock {
            let fm = FileManager.default
            let names = (try? fm.contentsOfDirectory(atPath: directory.path)) ?? []
            var failed = false
            for name in names where Self.isManagedFile(name) {
                do { try fm.removeItem(at: directory.appendingPathComponent(name)) } catch { failed = true }
            }
            if failed { throw ClipboardPersistenceError.deleteFailed }
        }
    }

    // MARK: 內部

    private struct IndexFile: Encodable {
        let version: Int
        let items: [ClipboardItem]
    }

    /// 整份索引的外層結構必須合法；個別條目解不開就略過（item 為 nil）。
    private struct LossyIndex: Decodable {
        struct Entry: Decodable {
            let item: ClipboardItem?
            init(from decoder: Decoder) throws {
                item = try? ClipboardItem(from: decoder)
            }
        }
        let items: [Entry]
    }

    private func imageExistsUnlocked(_ fileName: String) -> Bool {
        guard Self.isValidImageFileName(fileName) else { return false }
        return FileManager.default.fileExists(atPath: directory.appendingPathComponent(fileName).path)
    }

    /// 損毀的索引：改名為 index.json.corrupt 保留（覆蓋舊的備份），並記錄事件。
    private func quarantineIndex() {
        let fm = FileManager.default
        let corrupt = directory.appendingPathComponent(Self.indexFileName + Self.corruptSuffix)
        try? fm.removeItem(at: corrupt)
        if (try? fm.moveItem(at: indexURL, to: corrupt)) != nil {
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: corrupt.path)
        }
        logger.log(.indexCorrupted)
    }

    /// 原子寫入：同目錄暫存檔（建立時即為 0600，無權限空窗）→ fsync → rename。
    private func atomicWrite(_ data: Data, to destination: URL) throws {
        let temp = directory.appendingPathComponent(destination.lastPathComponent + Self.tempMarker + UUID().uuidString)
        let fd = open(temp.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw ClipboardPersistenceError.writeFailed }
        var succeeded = fchmod(fd, 0o600) == 0
        if succeeded {
            succeeded = data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Bool in
                guard let base = buffer.baseAddress else { return true }
                var offset = 0
                while offset < buffer.count {
                    let written = write(fd, base + offset, buffer.count - offset)
                    if written < 0 {
                        if errno == EINTR { continue }
                        return false
                    }
                    offset += written
                }
                return true
            }
        }
        if succeeded { succeeded = fsync(fd) == 0 }
        let closed = close(fd) == 0
        if !(succeeded && closed) || rename(temp.path, destination.path) != 0 {
            unlink(temp.path)
            throw ClipboardPersistenceError.writeFailed
        }
    }

    /// 圖片檔名格式：`<64 位小寫十六進位>.<1–8 位小寫英數>`。
    static func isValidImageFileName(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let hash = parts[0], ext = parts[1]
        guard hash.utf8.count == 64, hash.utf8.allSatisfy({ ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66) }) else { return false }
        guard (1...8).contains(ext.utf8.count), ext.utf8.allSatisfy({ ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x7A) }) else { return false }
        return true
    }

    /// 是否為本 app 產生的檔案：索引、圖片，以及它們的 .corrupt 備份與 .tmp- 暫存檔。
    static func isManagedFile(_ name: String) -> Bool {
        var base = name
        if base.hasSuffix(corruptSuffix) { base.removeLast(corruptSuffix.count) }
        if let range = base.range(of: tempMarker) { base = String(base[..<range.lowerBound]) }
        return base == indexFileName || isValidImageFileName(base)
    }
}
