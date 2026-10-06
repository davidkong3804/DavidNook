import Foundation

/// （紅燈階段的骨架：目前只是直通。）
public struct VideoAwareLyricsFetcher: LyricsFetching {
    private let base: any LyricsFetching

    public init(base: any LyricsFetching) { self.base = base }

    public func lyrics(for query: LyricsQuery) async throws -> PickedLyrics? { try await base.lyrics(for: query) }
    public func fetch(_ query: LyricsQuery) async throws -> LyricsFetchOutcome { try await base.fetch(query) }
}
