//
//  NowPlayingController.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import AppKit
import Combine
import DavidNookCore
import Foundation

@MainActor
final class NowPlayingController: NowPlayingRuntimeControlling {
    func updatePlaybackInfo() async {
        await fetchFavoriteStateIfSupported()
    }

    // MARK: - Properties
    @Published private(set) var playbackState: PlaybackState = .init(
        bundleIdentifier: MediaAppBundleID.appleMusic
    )

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var supportsVolumeControl: Bool {
        playbackState.bundleIdentifier == MediaAppBundleID.appleMusic
    }

    var supportsFavorite: Bool {
        let bundleID = playbackState.bundleIdentifier
        return bundleID == MediaAppBundleID.appleMusic
    }

    func setFavorite(_ favorite: Bool) async {
        let bundleID = playbackState.bundleIdentifier

        if bundleID == MediaAppBundleID.appleMusic {
            let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: MediaAppBundleID.appleMusic)
            if !runningApps.isEmpty {
                let script = """
                tell application "Music"
                    try
                        set favorited of current track to \(favorite ? "true" : "false")
                    end try
                end tell
                """
                try? await AppleScriptHelper.executeVoid(script)
            }
        }

        // Update the favorite state locally and fetch updated info
        try? await Task.sleep(for: .milliseconds(150))
        await updatePlaybackInfo()
    }

    // MARK: - Media Remote Functions
    private let mediaRemoteBundle: CFBundle
    private let MRMediaRemoteSendCommandFunction: @convention(c) (Int, AnyObject?) -> Void
    private let MRMediaRemoteSetElapsedTimeFunction: @convention(c) (Double) -> Void
    private let MRMediaRemoteSetShuffleModeFunction: @convention(c) (Int) -> Void
    private let MRMediaRemoteSetRepeatModeFunction: @convention(c) (Int) -> Void
    private let adapterScriptURL: URL
    private let adapterFrameworkPath: String

    let runtimeFailures: AsyncStream<Void>
    private let runtimeFailureContinuation: AsyncStream<Void>.Continuation

    private var streamSession: NowPlayingStreamSession?

    // MARK: - Initialization
    init() throws {
        let resources = try NowPlayingResources.load()

        guard
            let bundle = CFBundleCreate(
                kCFAllocatorDefault,
                NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")),
            let MRMediaRemoteSendCommandPointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSendCommand" as CFString),
            let MRMediaRemoteSetElapsedTimePointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSetElapsedTime" as CFString),
            let MRMediaRemoteSetShuffleModePointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSetShuffleMode" as CFString),
            let MRMediaRemoteSetRepeatModePointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSetRepeatMode" as CFString)
        else {
            throw NowPlayingError.unavailable
        }

        mediaRemoteBundle = bundle
        MRMediaRemoteSendCommandFunction = unsafeBitCast(
            MRMediaRemoteSendCommandPointer, to: (@convention(c) (Int, AnyObject?) -> Void).self)
        MRMediaRemoteSetElapsedTimeFunction = unsafeBitCast(
            MRMediaRemoteSetElapsedTimePointer, to: (@convention(c) (Double) -> Void).self)
        MRMediaRemoteSetShuffleModeFunction = unsafeBitCast(
            MRMediaRemoteSetShuffleModePointer, to: (@convention(c) (Int) -> Void).self)
        MRMediaRemoteSetRepeatModeFunction = unsafeBitCast(
            MRMediaRemoteSetRepeatModePointer, to: (@convention(c) (Int) -> Void).self)
        adapterScriptURL = resources.adapterScriptURL
        adapterFrameworkPath = resources.adapterFrameworkPath

        let runtimeFailureChannel = AsyncStream.makeStream(of: Void.self)
        runtimeFailures = runtimeFailureChannel.stream
        runtimeFailureContinuation = runtimeFailureChannel.continuation
    }

    deinit {
        if let streamSession {
            Task { @MainActor in
                streamSession.stop()
            }
        }
        runtimeFailureContinuation.finish()
    }

    // MARK: - Protocol Implementation
    func play() async {
        MRMediaRemoteSendCommandFunction(0, nil)
    }

    func pause() async {
        MRMediaRemoteSendCommandFunction(1, nil)
    }

    func togglePlay() async {
        MRMediaRemoteSendCommandFunction(2, nil)
    }

    func nextTrack() async {
        MRMediaRemoteSendCommandFunction(4, nil)
    }

    func previousTrack() async {
        MRMediaRemoteSendCommandFunction(5, nil)
    }

    func seek(to time: Double) async {
        MRMediaRemoteSetElapsedTimeFunction(time)
    }

    func isActive() -> Bool {
        return true
    }

    func toggleShuffle() async {
        // MRMediaRemoteSendCommandFunction(6, nil)
        MRMediaRemoteSetShuffleModeFunction(playbackState.isShuffled ? 1 : 3)
        playbackState.isShuffled.toggle()
    }

    func toggleRepeat() async {
        // MRMediaRemoteSendCommandFunction(7, nil)
        let newRepeatMode = (playbackState.repeatMode == .off) ? 3 : (playbackState.repeatMode.rawValue - 1)
        playbackState.repeatMode = RepeatMode(rawValue: newRepeatMode) ?? .off
        MRMediaRemoteSetRepeatModeFunction(newRepeatMode)
    }

    func setVolume(_ level: Double) async {
        // MediaRemote framework doesn't provide direct volume control for the active audio session
        // As a workaround, try to control the currently active music app directly
        let clampedLevel = max(0.0, min(1.0, level))
        let volumePercentage = Int(clampedLevel * 100)

        let bundleID = playbackState.bundleIdentifier
        if !bundleID.isEmpty {
            if bundleID == MediaAppBundleID.appleMusic {
                let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: MediaAppBundleID.appleMusic)
                if !runningApps.isEmpty {
                    let script = "tell application \"Music\" to set sound volume to \(volumePercentage)"
                    try? await AppleScriptHelper.executeVoid(script)
                }
            }
        }

        playbackState.volume = clampedLevel
    }

    // MARK: - Runtime Stream Lifecycle
    func startRuntimeStream() {
        guard streamSession == nil else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        // --micros：時間欄位改為微秒（預設的 timestamp 只有秒級解析度，會讓歌詞同步最多差 1 秒）。
        process.arguments = [adapterScriptURL.path, adapterFrameworkPath, "stream", "--micros"]

        let session = NowPlayingStreamSession(
            process: process,
            onUpdate: { [weak self] update in
                await self?.handleAdapterUpdate(update)
            },
            onFailure: { [weak self] in
                guard let self else { return }
                self.streamSession = nil
                self.runtimeFailureContinuation.yield()
            }
        )
        streamSession = session
        session.start()
    }

    func stopRuntimeStream() {
        let session = streamSession
        streamSession = nil
        session?.stop()
    }

    // MARK: - Update Methods
    private func handleAdapterUpdate(_ update: NowPlayingUpdate) async {
        let payload = update.payload
        let diff = update.diff ?? false

        var newPlaybackState = PlaybackState(bundleIdentifier: playbackState.bundleIdentifier)
        let resolvedBundleIdentifier = (
            payload.parentApplicationBundleIdentifier ??
            payload.bundleIdentifier ??
            (diff ? self.playbackState.bundleIdentifier : "")
        )
        newPlaybackState.title = payload.title ?? (diff ? self.playbackState.title : "")
        newPlaybackState.artist = payload.artist ?? (diff ? self.playbackState.artist : "")
        newPlaybackState.album = payload.album ?? (diff ? self.playbackState.album : "")
        newPlaybackState.duration = AdapterTime.seconds(micros: payload.durationMicros, seconds: payload.duration)
            ?? (diff ? self.playbackState.duration : 0)

        // 播放位置錨點（elapsed, timestamp）：位置 = elapsed + (now − timestamp) × rate，不靠輪詢。
        // 只有「同一則更新同時帶了 elapsed」時，timestamp 才可信；否則沿用舊錨點。
        let receivedAt = Date()
        let newPlaying = payload.playing ?? (diff ? self.playbackState.isPlaying : false)
        let newRate = payload.playbackRate ?? (diff ? self.playbackState.playbackRate : 1.0)
        if let elapsedTime = AdapterTime.seconds(micros: payload.elapsedTimeMicros, seconds: payload.elapsedTime) {
            // seek、換歌、暫停/恢復時 adapter 會給新的 elapsed + timestamp：整個取代舊錨點。
            newPlaybackState.currentTime = elapsedTime
            newPlaybackState.lastUpdated = AdapterTime.date(
                epochMicros: payload.timestampEpochMicros, iso8601: payload.timestamp
            ) ?? receivedAt
        } else if diff, self.playbackState.lastUpdated != .distantPast {
            if newPlaying != self.playbackState.isPlaying || newRate != self.playbackState.playbackRate {
                // 播放狀態或速率變了，但沒有新錨點：先在舊狀態下固定當下位置，再換成新狀態，
                // 否則暫停→恢復時會多算暫停的那段時間。
                let rebased = PlaybackSnapshot(
                    elapsedTime: self.playbackState.currentTime,
                    timestamp: self.playbackState.lastUpdated,
                    playbackRate: self.playbackState.playbackRate,
                    isPlaying: self.playbackState.isPlaying,
                    duration: newPlaybackState.duration
                ).rebased(at: receivedAt)
                newPlaybackState.currentTime = rebased.elapsedTime
                newPlaybackState.lastUpdated = rebased.timestamp
            } else {
                newPlaybackState.currentTime = self.playbackState.currentTime
                newPlaybackState.lastUpdated = self.playbackState.lastUpdated
            }
        } else {
            newPlaybackState.currentTime = 0
            newPlaybackState.lastUpdated = receivedAt
        }

        if let shuffleMode = payload.shuffleMode {
            newPlaybackState.isShuffled = shuffleMode != 1
        } else if !diff {
            newPlaybackState.isShuffled = false
        } else {
            newPlaybackState.isShuffled = self.playbackState.isShuffled
        }
        if let repeatModeValue = payload.repeatMode {
            newPlaybackState.repeatMode = RepeatMode(rawValue: repeatModeValue) ?? .off
        } else if !diff {
            newPlaybackState.repeatMode = .off
        } else {
            newPlaybackState.repeatMode = self.playbackState.repeatMode
        }

        if let artworkDataString = payload.artworkData {
            newPlaybackState.artwork = Data(
                base64Encoded: artworkDataString.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } else if !diff {
            newPlaybackState.artwork = nil
        } else {
            newPlaybackState.artwork = self.playbackState.artwork
        }

        newPlaybackState.playbackRate = newRate
        newPlaybackState.isPlaying = newPlaying
        newPlaybackState.bundleIdentifier = resolvedBundleIdentifier

        newPlaybackState.volume = payload.volume ?? (diff ? self.playbackState.volume : 0.5)

        self.playbackState = newPlaybackState
    }

    private func fetchFavoriteStateIfSupported() async {
        guard playbackState.bundleIdentifier == MediaAppBundleID.appleMusic else { return }

        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: MediaAppBundleID.appleMusic)
        guard !runningApps.isEmpty else { return }

        let script = """
        tell application "Music"
            try
                return favorited of current track
            on error
                return false
            end try
        end tell
        """
        if let result = try? await AppleScriptHelper.execute(script) {
            var updated = playbackState
            updated.isFavorite = result.booleanValue
            playbackState = updated
        }
    }
}
