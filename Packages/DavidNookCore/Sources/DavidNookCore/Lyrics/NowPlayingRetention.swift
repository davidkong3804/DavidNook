import Foundation

/// 「正在播放」資訊的保留規則：播放結束時來源（Now Playing adapter／Music.app）會回報「沒有曲目」，
/// 若照單全收，標題／封面／歌詞會被清空；但暫停時不會。這個型別讓「結束」的行為等同「暫停」：
/// 來源回報無曲目時，保留最後一首（`.retainLast`），只把它視為「已停止」。
///
/// 只存在記憶體裡（沒有任何序列化或寫檔）；App 結束就沒了，冷啟動時回到 `.none`。
public struct NowPlayingRetention: Equatable, Sendable {

    public enum Phase: Equatable, Sendable {
        /// 還沒有播放過任何東西（冷啟動，或換了來源後尚無資料）。
        case none
        case playing
        case paused
        /// 最後一首播完（或來源離開），畫面保留最後一首但已停止。
        case ended
    }

    public enum Decision: Equatable, Sendable {
        /// 照來源回報更新（換歌、播放、暫停、冷啟動時的空狀態）。
        case applyIncoming
        /// 忽略來源的「無曲目」：保留最後一首的標題／歌手／封面／歌詞，並視為已停止。
        case retainLast
    }

    public private(set) var phase: Phase = .none

    public init() {}

    /// 保留中的最後一首是否已「播完」。
    public var isEnded: Bool { phase == .ended }

    /// 來源回報有沒有曲目：標題或歌手任一不為空即算有。
    public static func hasTrack(title: String, artist: String) -> Bool {
        !title.isEmpty || !artist.isEmpty
    }

    /// 觀察來源的一次回報，更新階段並決定要不要套用。
    public mutating func observe(hasTrack: Bool, isPlaying: Bool) -> Decision {
        if hasTrack {
            phase = isPlaying ? .playing : .paused
            return .applyIncoming
        }
        switch phase {
        case .none:
            return .applyIncoming
        case .playing, .paused, .ended:
            phase = .ended
            return .retainLast
        }
    }

    /// 全部忘掉（切換來源時）：之後的「無曲目」就是真的沒有曲目。
    public mutating func reset() {
        phase = .none
    }
}
