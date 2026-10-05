import Foundation

/// 歌詞時間軸：給定播放位置，以二分搜尋找出「目前行」與「下一行何時開始」。
///
/// ## 偏移（單位：毫秒，可為負）
/// 約定：**正值＝歌詞提早顯示，負值＝歌詞延後顯示**（與 LRC `[offset:]` 慣例相同）。
///
///     查詢時間 = 播放位置 + lrcOffsetMs + userOffsetMs
///     目前行   = 「行時間 ≤ 查詢時間」的最後一行
///
/// 檔內 `[offset:]`（`lrcOffsetMs`）與使用者的逐曲偏移（`userOffsetMs`）**相加**，不分先後；
/// 解析階段不改寫行時間，所以同一份解析結果可以快取，使用者偏移只在查詢時帶入。
public struct LyricsTimeline: Sendable {

    /// 已依時間排序（穩定）的歌詞行。
    public let lines: [LRCLine]
    /// 檔內 `[offset:]` 的值（毫秒，正值＝提早）。
    public let lrcOffsetMs: Int

    /// - Parameters:
    ///   - lines: 歌詞行；預期已排序。若未排序會以穩定排序整理（時間相同者維持原順序）。
    ///   - lrcOffsetMs: 檔內 `[offset:]`（毫秒，正值＝提早）。
    public init(lines: [LRCLine], lrcOffsetMs: Int = 0) {
        var isSorted = true
        var previous = Int.min
        for line in lines {
            if line.timeMs < previous { isSorted = false; break }
            previous = line.timeMs
        }
        if isSorted {
            self.lines = lines
        } else {
            self.lines = lines.enumerated()
                .sorted { a, b in
                    a.element.timeMs != b.element.timeMs ? a.element.timeMs < b.element.timeMs : a.offset < b.offset
                }
                .map(\.element)
        }
        self.lrcOffsetMs = lrcOffsetMs
    }

    /// 由 `LRCParser` 的解析結果建立（帶入 `[offset:]`）。
    public init(document: LRCDocument) {
        self.init(lines: document.lines, lrcOffsetMs: document.offsetMs)
    }

    // MARK: - 目前行

    /// 目前行索引。
    /// - Parameters:
    ///   - positionMs: 播放位置，單位：毫秒。
    ///   - userOffsetMs: 使用者的逐曲偏移（毫秒，正值＝歌詞提早）。
    /// - Returns: 位置早於第一行回傳 nil；時間戳相同的多行取最後一行；過了最後一行仍回傳最後一行
    ///   （若最後一行是空白標記，顯示端應視為「歌詞已結束」）。
    public func currentIndex(atMs positionMs: Int, userOffsetMs: Int = 0) -> Int? {
        let upper = upperBound(lookupMs(positionMs, userOffsetMs))
        return upper == 0 ? nil : upper - 1
    }

    /// 同上，播放位置以秒為單位（先四捨五入到最接近的毫秒）。NaN 回傳 nil。
    public func currentIndex(at position: TimeInterval, userOffsetMs: Int = 0) -> Int? {
        guard let ms = Self.milliseconds(from: position) else { return nil }
        return currentIndex(atMs: ms, userOffsetMs: userOffsetMs)
    }

    // MARK: - 下一行

    /// 下一行開始的「播放時間」，單位：毫秒（已扣除偏移，可直接與播放位置比較）。
    /// 沒有下一行（已在最後一行之後）回傳 nil。
    public func nextLineStartMs(atMs positionMs: Int, userOffsetMs: Int = 0) -> Int? {
        let upper = upperBound(lookupMs(positionMs, userOffsetMs))
        guard upper < lines.count else { return nil }
        return Self.saturatedSubtract(Self.saturatedSubtract(lines[upper].timeMs, lrcOffsetMs), userOffsetMs)
    }

    /// 下一行開始的播放時間，單位：秒。沒有下一行或位置為 NaN 回傳 nil。
    public func nextLineTime(at position: TimeInterval, userOffsetMs: Int = 0) -> TimeInterval? {
        guard let ms = Self.milliseconds(from: position),
              let next = nextLineStartMs(atMs: ms, userOffsetMs: userOffsetMs)
        else { return nil }
        return Double(next) / 1000
    }

    /// 距離下一行開始還有多少秒（可用來排程下一次喚醒）。沒有下一行回傳 nil。
    public func timeUntilNextLine(at position: TimeInterval, userOffsetMs: Int = 0) -> TimeInterval? {
        nextLineTime(at: position, userOffsetMs: userOffsetMs).map { $0 - position }
    }

    // MARK: - 內部

    private func lookupMs(_ positionMs: Int, _ userOffsetMs: Int) -> Int {
        Self.saturatedAdd(Self.saturatedAdd(positionMs, lrcOffsetMs), userOffsetMs)
    }

    /// 第一個「行時間 > lookup」的索引（二分搜尋，O(log n)）。
    private func upperBound(_ lookup: Int) -> Int {
        var low = 0
        var high = lines.count
        while low < high {
            let mid = (low + high) / 2
            if lines[mid].timeMs <= lookup { low = mid + 1 } else { high = mid }
        }
        return low
    }

    private static func milliseconds(from seconds: TimeInterval) -> Int? {
        if seconds.isNaN { return nil }
        let ms = (seconds * 1000).rounded()
        let limit = 1e15
        if ms >= limit { return Int(limit) }
        if ms <= -limit { return Int(-limit) }
        return Int(ms)
    }

    private static func saturatedAdd(_ a: Int, _ b: Int) -> Int {
        let (sum, overflow) = a.addingReportingOverflow(b)
        return overflow ? (b > 0 ? Int.max : Int.min) : sum
    }

    private static func saturatedSubtract(_ a: Int, _ b: Int) -> Int {
        let (diff, overflow) = a.subtractingReportingOverflow(b)
        return overflow ? (b < 0 ? Int.max : Int.min) : diff
    }
}
