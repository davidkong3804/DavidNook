// STUB（紅燈階段）：只有 API 形狀，尚無實作。

public struct LyricsOverrides: Sendable {
    public struct Entry: Equatable, Sendable {
        public let key: String
        public let value: String
    }

    public private(set) var entries: [Entry] = []
    public private(set) var duplicateKeys: [String] = []
    public private(set) var malformedLineNumbers: [Int] = []

    public init(parsing text: String) {}

    public static let bundled = LyricsOverrides(parsing: "")

    public func apply(to text: String, convertingRest convert: (String) -> String) -> String {
        convert(text)
    }
}
