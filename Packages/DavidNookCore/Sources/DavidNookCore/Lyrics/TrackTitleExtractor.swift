import Foundation

/// 從影片標題萃取出的一組查詢候選。`artist` 為 nil 代表歌手未知（只用歌名查）。
public struct TrackTitleCandidate: Equatable, Hashable, Sendable {
    public var title: String
    public var artist: String?

    public init(_ title: String, _ artist: String?) {
        self.title = title
        self.artist = artist
    }
}

/// （紅燈階段的骨架：行為尚未實作。）
public enum TrackTitleExtractor {
    public static let maxCandidates = 6
    public static let maxVideoDuration: TimeInterval = 900

    public static func candidates(
        title: String, artist: String, durationSeconds: TimeInterval, sourceBundleID: String?
    ) -> [TrackTitleCandidate] {
        []
    }

    public static func isVideoSource(bundleID: String?, title: String) -> Bool { false }
    public static func isBrowserBundleID(_ id: String) -> Bool { false }
    public static func looksLikeVideoTitle(_ title: String) -> Bool { false }
}
