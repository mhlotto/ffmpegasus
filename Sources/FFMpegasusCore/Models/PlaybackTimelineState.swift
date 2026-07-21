import Foundation

public struct PlaybackPrecisionTimelineRange: Equatable, Sendable {
    public static let defaultWindowSeconds: TimeInterval = 10
    public static let smallStepSeconds: TimeInterval = 0.1

    public let startSeconds: TimeInterval
    public let endSeconds: TimeInterval

    public init(startSeconds: TimeInterval, endSeconds: TimeInterval) {
        let safeStart = startSeconds.isFinite ? max(0, startSeconds) : 0
        let safeEnd = endSeconds.isFinite ? max(safeStart, endSeconds) : safeStart
        self.startSeconds = safeStart
        self.endSeconds = safeEnd
    }

    public var durationSeconds: TimeInterval {
        max(0, endSeconds - startSeconds)
    }

    public static func centered(
        around centerSeconds: TimeInterval,
        durationSeconds: TimeInterval,
        windowSeconds: TimeInterval = defaultWindowSeconds
    ) -> PlaybackPrecisionTimelineRange {
        guard TimeFormatting.isSeekableDuration(durationSeconds) else {
            return PlaybackPrecisionTimelineRange(startSeconds: 0, endSeconds: 0)
        }

        let duration = max(0, durationSeconds)
        let window = max(0.001, min(windowSeconds.isFinite ? windowSeconds : defaultWindowSeconds, duration))
        let center = TimeFormatting.clampedPlaybackTime(centerSeconds, duration: duration)
        var start = center - (window / 2)
        var end = start + window

        if start < 0 {
            start = 0
            end = window
        }
        if end > duration {
            end = duration
            start = max(0, end - window)
        }

        return PlaybackPrecisionTimelineRange(startSeconds: start, endSeconds: end)
    }

    public func clamped(_ seconds: TimeInterval) -> TimeInterval {
        guard seconds.isFinite else { return startSeconds }
        return min(max(seconds, startSeconds), endSeconds)
    }
}

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

    public func precisionRange(windowSeconds: TimeInterval = PlaybackPrecisionTimelineRange.defaultWindowSeconds) -> PlaybackPrecisionTimelineRange {
        PlaybackPrecisionTimelineRange.centered(
            around: displayedTimeSeconds,
            durationSeconds: durationSeconds,
            windowSeconds: windowSeconds
        )
    }

    public func precisionStepTarget(by offsetSeconds: TimeInterval) -> TimeInterval {
        TimeFormatting.clampedPlaybackTime(displayedTimeSeconds + offsetSeconds, duration: durationSeconds)
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

    public mutating func invalidateLivePreviewSeek() {
        guard isLivePreviewSeeking else { return }
        isLivePreviewSeeking = false
        seekGeneration += 1
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
