import Foundation

/// 依來源 App 的 bundle id 記住上次的裁切矩形。**只存 bundle id 與矩形**——不存視窗標題或任何畫面內容。
/// 取不到 bundle id（macOS 15.2 以下）時不存（只套用於本次串流）。純值型別，App 端以 Defaults 序列化（Codable）。
public struct VideoCropMemory: Codable, Equatable, Sendable {
    public static let maximumEntries = 64
    public static let defaultsKey = "videoCropMemory"

    public struct Entry: Codable, Equatable, Sendable {
        public var bundleID: String
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        var rect: NormalizedCropRect { NormalizedCropRect(x: x, y: y, width: width, height: height) }
    }

    /// 最近使用的在後面。
    public private(set) var entries: [Entry] = []

    public init() {}

    private static func isValid(_ bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        return !id.isEmpty && id.count <= 256
    }

    public func rect(for bundleID: String?) -> NormalizedCropRect? {
        guard Self.isValid(bundleID), let entry = entries.last(where: { $0.bundleID == bundleID }) else { return nil }
        return entry.rect.sanitized
    }

    /// 記住（`nil` 或整個視窗＝移除）。bundle id 空白／nil 不存。
    public mutating func set(_ rect: NormalizedCropRect?, for bundleID: String?) {
        guard Self.isValid(bundleID), let bundleID else { return }
        entries.removeAll { $0.bundleID == bundleID }
        guard let rect, !rect.isFullWindow else { return }
        let s = rect.sanitized
        entries.append(Entry(bundleID: bundleID, x: s.x, y: s.y, width: s.width, height: s.height))
        if entries.count > Self.maximumEntries { entries.removeFirst(entries.count - Self.maximumEntries) }
    }

    public mutating func remove(_ bundleID: String?) { set(nil, for: bundleID) }

    // 讀回時丟掉無效項目並夾限（儲存內容可能被手動改過）。
    private enum CodingKeys: String, CodingKey { case entries }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode([Entry].self, forKey: .entries)
        var result = VideoCropMemory()
        for entry in raw { result.set(entry.rect, for: entry.bundleID) }
        self = result
    }
}
