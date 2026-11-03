import Foundation

extension LyricsQuery {
    /// 歌名只有 ASCII（羅馬拼音／英文）而歌手含非 ASCII 字元（漢字、假名、諺文…）：
    /// Apple Music 在繁中地區常把日韓歌顯示成「Shinunoga E-Wa／藤井風」。
    var looksRomanizedAgainstNativeArtist: Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.allSatisfy(\.isASCII) && artist.contains { !$0.isASCII }
    }
}

/// 把羅馬拼音歌名換回原文歌名（例如 `Shinunoga E-Wa` → `死ぬのがいいわ`）。
public protocol NativeTitleResolving: Sendable {
    /// - Returns: 原文歌名；不適用、查不到或有歧義時為 nil。**盡力而為**：失敗一律當作 nil，不影響後續的歌詞查詢。
    func nativeTitle(for query: LyricsQuery) async -> String?
}

/// 用 Apple 的 iTunes Search API（日本區）以「歌手＋長度」找回原文歌名。
///
/// 播放器給的長度與目錄裡同一首歌的 `trackTimeMillis` 幾乎一致，所以只收長度差 `durationTolerance`（預設 0.3 秒）以內的結果，
/// 且結果的歌名必須含非 ASCII 字元；符合的歌名不只一種（歧義）就放棄。**只送出歌手名**（搜尋詞），不含歌名、長度或任何識別資料。
public struct ITunesNativeTitleResolver: NativeTitleResolving {
    private let transport: any HTTPTransport
    private let durationTolerance: TimeInterval
    private let isEnabled: @Sendable () -> Bool
    private let baseURL: URL

    public init(
        transport: any HTTPTransport,
        durationTolerance: TimeInterval = 0.3,
        isEnabled: @escaping @Sendable () -> Bool = { true },
        baseURL: URL = URL(string: "https://itunes.apple.com")!
    ) {
        self.transport = transport
        self.durationTolerance = durationTolerance
        self.isEnabled = isEnabled
        self.baseURL = baseURL
    }

    public func nativeTitle(for query: LyricsQuery) async -> String? {
        guard isEnabled(), !query.isVideoDerived, query.looksRomanizedAgainstNativeArtist,
              query.duration.isFinite, query.duration > 0 else { return nil }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        components.path = "/search"
        components.queryItems = [
            URLQueryItem(name: "term", value: query.artist.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "country", value: "JP"),
            URLQueryItem(name: "limit", value: "200"),
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        guard let response = try? await transport.send(request), response.statusCode == 200,
              let decoded = try? JSONDecoder().decode(Response.self, from: response.body) else { return nil }

        var names: [String] = []
        for result in decoded.results {
            guard let name = result.trackName, let millis = result.trackTimeMillis,
                  abs(millis / 1000 - query.duration) <= durationTolerance,
                  name.contains(where: { !$0.isASCII }) else { continue }
            if !names.contains(name) { names.append(name) }
        }
        return names.count == 1 ? names[0] : nil
    }

    private struct Response: Decodable {
        var results: [Result]
        struct Result: Decodable {
            var trackName: String?
            var trackTimeMillis: Double?
        }
    }
}

/// 包在 `LrclibClient` 外面：羅馬拼音歌名＋原文歌手時，先換回原文歌名再查（LRCLIB 的日文／韓文歌詞登記在原文歌名下）；
/// 換了查不到才退回原樣查詢。其他查詢原樣直通。
public struct NativeTitleLyricsFetcher: LyricsFetching {
    private let base: any LyricsFetching
    private let resolver: any NativeTitleResolving

    public init(base: any LyricsFetching, resolver: any NativeTitleResolving) {
        self.base = base
        self.resolver = resolver
    }

    public func lyrics(for query: LyricsQuery) async throws -> PickedLyrics? {
        try await fetch(query).lyrics
    }

    public func fetch(_ query: LyricsQuery) async throws -> LyricsFetchOutcome {
        if query.looksRomanizedAgainstNativeArtist, let native = await resolver.nativeTitle(for: query) {
            try Task.checkCancellation()
            var rewritten = query
            rewritten.title = native
            let outcome = try await base.fetch(rewritten)
            if outcome.lyrics != nil { return outcome }
        }
        return try await base.fetch(query)
    }
}
