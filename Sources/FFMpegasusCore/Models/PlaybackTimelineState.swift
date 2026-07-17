import Foundation

public struct PlaybackTimelineState: Equatable, Sendable {
    public private(set) var hasVideo: Bool
    public private(set) var durationSeconds: TimeInterval
    public private(set) var committedTimeSeconds: TimeInterval
    public private(set) var scrubTimeSeconds: TimeInterval
    public private(set) var isScrubbing: Bool
    public private(set) var isPlaying: Bool
    public private(set) var isSeeking: Bool
    public private(set) var isLivePreviewSeeking: Bool
    public private(set) var isReadyForSeeking: Bool
    public private(set) var seekGeneration: Int

    public init(
        hasVideo: Bool = false,
        durationSeconds: TimeInterval = 0,
        committedTimeSeconds: TimeInterval = 0,
        scrubTimeSeconds: TimeInterval = 0,
        isScrubbing: Bool = false,
        isPlaying: Bool = false,
        isSeeking: Bool = false,
        isLivePreviewSeeking: Bool = false,
        isReadyForSeeking: Bool = false,
        seekGeneration: Int = 0
    ) {
        self.hasVideo = hasVideo
        self.durationSeconds = durationSeconds.isFinite ? max(0, durationSeconds) : 0
        self.committedTimeSeconds = TimeFormatting.clampedPlaybackTime(committedTimeSeconds, duration: self.durationSeconds)
        self.scrubTimeSeconds = TimeFormatting.clampedPlaybackTime(scrubTimeSeconds, duration: self.durationSeconds)
        self.isScrubbing = isScrubbing
        self.isPlaying = isPlaying
        self.isSeeking = isSeeking
        self.isLivePreviewSeeking = isLivePreviewSeeking
        self.isReadyForSeeking = isReadyForSeeking
        self.seekGeneration = seekGeneration
    }

    public var displayedTimeSeconds: TimeInterval {
        isScrubbing ? scrubTimeSeconds : committedTimeSeconds
    }

    public var canSeek: Bool {
        hasVideo && isReadyForSeeking && TimeFormatting.isSeekableDuration(durationSeconds) && !isSeeking
    }

    public var hasPendingSeek: Bool {
        isSeeking || isLivePreviewSeeking
    }

    public mutating func open(duration: TimeInterval) {
        hasVideo = true
        durationSeconds = TimeFormatting.isSeekableDuration(duration) ? duration : 0
        committedTimeSeconds = 0
        scrubTimeSeconds = 0
        isScrubbing = false
        isPlaying = false
        isSeeking = false
        isLivePreviewSeeking = false
        isReadyForSeeking = false
        seekGeneration += 1
    }

    public mutating func close() {
        hasVideo = false
        durationSeconds = 0
        committedTimeSeconds = 0
        scrubTimeSeconds = 0
        isScrubbing = false
        isPlaying = false
        isSeeking = false
        isLivePreviewSeeking = false
        isReadyForSeeking = false
        seekGeneration += 1
    }

    public mutating func setDuration(_ duration: TimeInterval) {
        durationSeconds = TimeFormatting.isSeekableDuration(duration) ? duration : 0
        committedTimeSeconds = TimeFormatting.clampedPlaybackTime(committedTimeSeconds, duration: durationSeconds)
        scrubTimeSeconds = TimeFormatting.clampedPlaybackTime(scrubTimeSeconds, duration: durationSeconds)
    }

    public mutating func setReadyForSeeking(_ ready: Bool) {
        isReadyForSeeking = ready
    }

    public mutating func setPlaying(_ playing: Bool) {
        isPlaying = playing
    }

    public mutating func applyObserverTime(_ seconds: TimeInterval) {
        guard !isScrubbing, !isSeeking else { return }
        committedTimeSeconds = TimeFormatting.clampedPlaybackTime(seconds, duration: durationSeconds)
        scrubTimeSeconds = committedTimeSeconds
    }

    public mutating func beginScrubbing() {
        guard canSeek else { return }
        isScrubbing = true
        scrubTimeSeconds = committedTimeSeconds
    }

    public mutating func updateScrubPosition(_ seconds: TimeInterval) {
        guard isScrubbing else { return }
        scrubTimeSeconds = TimeFormatting.clampedPlaybackTime(seconds, duration: durationSeconds)
    }

    @discardableResult
    public mutating func beginSeekFromScrub() -> (generation: Int, target: TimeInterval)? {
        guard isScrubbing else { return nil }
        let target = TimeFormatting.clampedPlaybackTime(scrubTimeSeconds, duration: durationSeconds)
        scrubTimeSeconds = target
        committedTimeSeconds = target
        isLivePreviewSeeking = false
        isSeeking = true
        seekGeneration += 1
        return (seekGeneration, target)
    }

    @discardableResult
    public mutating func beginLivePreviewSeek(to seconds: TimeInterval) -> (generation: Int, target: TimeInterval)? {
        guard isScrubbing else { return nil }
        let target = TimeFormatting.clampedPlaybackTime(seconds, duration: durationSeconds)
        scrubTimeSeconds = target
        isLivePreviewSeeking = true
        seekGeneration += 1
        return (seekGeneration, target)
    }

    @discardableResult
    public mutating func beginSeek(to seconds: TimeInterval) -> (generation: Int, target: TimeInterval) {
        let target = TimeFormatting.clampedPlaybackTime(seconds, duration: durationSeconds)
        committedTimeSeconds = target
        scrubTimeSeconds = target
        isScrubbing = false
        isLivePreviewSeeking = false
        isSeeking = true
        seekGeneration += 1
        return (seekGeneration, target)
    }

    @discardableResult
    public mutating func completeSeek(generation: Int, actualTime: TimeInterval? = nil) -> Bool {
        guard generation == seekGeneration else { return false }
        if let actualTime {
            committedTimeSeconds = TimeFormatting.clampedPlaybackTime(actualTime, duration: durationSeconds)
            scrubTimeSeconds = committedTimeSeconds
        }
        isScrubbing = false
        isSeeking = false
        return true
    }

    @discardableResult
    public mutating func completeLivePreviewSeek(generation: Int) -> Bool {
        guard generation == seekGeneration, isScrubbing else { return false }
        isLivePreviewSeeking = false
        return true
    }

    public mutating func stop() -> (generation: Int, target: TimeInterval) {
        isPlaying = false
        isScrubbing = false
        isLivePreviewSeeking = false
        return beginSeek(to: 0)
    }
}
