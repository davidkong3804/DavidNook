import CryptoKit
import Foundation

/// 檔案版歌詞快取：每首歌一個 JSON 檔，放在可注入的目錄內（App 會傳 Application Support/DavidNook/Lyrics）。
///
/// - **檔名**：`<TrackKey.storageString 的 SHA-256（64 位小寫 hex）>.json`——列目錄看不出聽過哪些歌；
///   檔案內嵌 `TrackKey`，讀取時必須與要查的 key 相同（防雜湊碰撞、檔案被改名／複製）。
/// - **權限**：目錄 0700、檔案 0600。寫入採「同目錄暫存檔（建立時就是 0600）→ fsync → rename」的原子寫入，
///   寫到一半當掉或寫入失敗都不會破壞既有檔案；寫入失敗一律靜默（快取只是加速，不影響功能）。
/// - **損毀容忍**：讀不出來（亂碼、截斷、結構錯誤、內嵌 key 不符）視為未命中並刪掉該檔；未知的格式版本視為未命中
///   但保留檔案。絕不崩潰。
/// - **負快取**（`lyrics == nil`）同樣存檔，TTL 由 `LyricsRepository` 依 `storedAt` 判斷，本類別不做時效處理。
/// - **隱私**：不輸出任何內容到 log（本檔沒有任何 log 呼叫，測試以來源掃描把關）。
///
/// 執行緒安全（內部以鎖保護）。
public final class FileLyricsCacheStore: LyricsCacheStore, @unchecked Sendable {

    /// 檔案格式版本；不相容的改動請遞增。
    public static let formatVersion = 1
    /// 快取檔副檔名。
    static let fileExtension = "json"
    private static let tempMarker = ".tmp-"
    /// 讀取時的檔案大小上限（避免被塞入巨大檔案）。
    private static let maxFileBytes = 8 * 1024 * 1024

    /// 存放目錄。
    public let directory: URL
    private let lock = NSLock()

    /// 建立快取並確保目錄存在、權限為 0700，且已排除備份。
    /// - Throws: 目錄無法建立、無法設定權限或無法排除備份。
    public init(directory: URL) throws {
        self.directory = directory
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        // 快取內容反映聽歌紀錄：新建與既有目錄都標為「排除備份」，「清除快取」才不會漏掉備份快照裡的舊副本。
        try BackupExclusion.exclude(directory)
    }

    // MARK: - LyricsCacheStore

    public func entry(for key: TrackKey) -> LyricsCacheEntry? {
        lock.withLock {
            let url = fileURL(for: key)
            let fm = FileManager.default
            guard fm.fileExists(atPath: url.path) else { return nil }

            guard let attributes = try? fm.attributesOfItem(atPath: url.path),
                  let size = (attributes[.size] as? NSNumber)?.intValue,
                  size <= Self.maxFileBytes,
                  let data = try? Data(contentsOf: url)
            else {
                try? fm.removeItem(at: url)
                return nil
            }

            // 先只看版本：未知版本（例如日後的新格式）視為未命中，但不刪檔。
            guard let header = try? JSONDecoder().decode(Header.self, from: data) else {
                try? fm.removeItem(at: url)
                return nil
            }
            guard header.version == Self.formatVersion else { return nil }

            guard let file = try? JSONDecoder().decode(CacheFile.self, from: data), file.key == key else {
                try? fm.removeItem(at: url)
                return nil
            }
            return file.entry
        }
    }

    public func store(_ entry: LyricsCacheEntry, for key: TrackKey) {
        lock.withLock {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            guard let data = try? encoder.encode(CacheFile(version: Self.formatVersion, key: key, entry: entry)) else { return }
            try? atomicWrite(data, to: fileURL(for: key))
        }
    }

    // MARK: - 清除

    /// 刪除本類別產生的全部檔案（快取檔與殘留的暫存檔）；不是我們產生的檔案（檔名不符）不會被碰。
    /// - Returns: 實際刪除的檔案數。
    /// - Throws: 有檔案刪不掉時（其餘仍會嘗試刪除）。
    @discardableResult
    public func removeAll() throws -> Int {
        try lock.withLock {
            let fm = FileManager.default
            let names = (try? fm.contentsOfDirectory(atPath: directory.path)) ?? []
            var removed = 0
            var failed = false
            for name in names where Self.isManagedFile(name) {
                do {
                    try fm.removeItem(at: directory.appendingPathComponent(name))
                    removed += 1
                } catch {
                    failed = true
                }
            }
            if failed { throw CocoaError(.fileWriteUnknown) }
            return removed
        }
    }

    // MARK: - 內部

    private struct Header: Decodable {
        let version: Int
    }

    private struct CacheFile: Codable {
        let version: Int
        let key: TrackKey
        let entry: LyricsCacheEntry
    }

    /// 檔名：`TrackKey.storageString` 的 SHA-256（hex）＋ `.json`。
    static func fileName(for key: TrackKey) -> String {
        let digest = SHA256.hash(data: Data(key.storageString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + "." + fileExtension
    }

    private func fileURL(for key: TrackKey) -> URL {
        directory.appendingPathComponent(Self.fileName(for: key))
    }

    /// 是否為本類別產生的檔案：`<64 位小寫 hex>.json`，以及殘留的 `.tmp-` 暫存檔。
    static func isManagedFile(_ name: String) -> Bool {
        var base = name
        if let range = base.range(of: tempMarker) { base = String(base[..<range.lowerBound]) }
        guard base.hasSuffix("." + fileExtension) else { return false }
        let stem = base.dropLast(fileExtension.count + 1)
        return stem.utf8.count == 64 && stem.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66) }
    }

    /// 原子寫入：同目錄暫存檔（建立時即為 0600，無權限空窗）→ fsync → rename。
    private func atomicWrite(_ data: Data, to destination: URL) throws {
        let temp = directory.appendingPathComponent(destination.lastPathComponent + Self.tempMarker + UUID().uuidString)
        let fd = open(temp.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
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
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
