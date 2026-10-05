import Foundation

/// 檔案版歌詞快取（紅燈佔位：尚未實作；`entry` 一律回傳 nil，`store` 不寫入）。
public final class FileLyricsCacheStore: LyricsCacheStore, @unchecked Sendable {
    public static let formatVersion = 1
    public let directory: URL

    public init(directory: URL) throws {
        self.directory = directory
    }

    public func entry(for key: TrackKey) -> LyricsCacheEntry? { nil }

    public func store(_ entry: LyricsCacheEntry, for key: TrackKey) {}

    @discardableResult
    public func removeAll() throws -> Int { 0 }

    static func fileName(for key: TrackKey) -> String { "placeholder.json" }
}
