import Foundation

public struct PlaybackScrubbingPolicy: Equatable, Sendable {
    public let previewSeekThrottleNanoseconds: UInt64
    public let previewSeekToleranceSeconds: TimeInterval

    public init(previewSeekThrottleNanoseconds: UInt64, previewSeekToleranceSeconds: TimeInterval) {
        self.previewSeekThrottleNanoseconds = previewSeekThrottleNanoseconds
        self.previewSeekToleranceSeconds = previewSeekToleranceSeconds
    }

    public static let current = PlaybackScrubbingPolicy(
        previewSeekThrottleNanoseconds: 75_000_000,
        previewSeekToleranceSeconds: 0.075
    )

    public static let smootherPreview = PlaybackScrubbingPolicy(
        previewSeekThrottleNanoseconds: 50_000_000,
        previewSeekToleranceSeconds: 0.05
    )

    public static let `default` = smootherPreview
}

public struct PlaybackScrubbingDiagnostics: Equatable, Sendable {
    public private(set) var rawSliderUpdates: Int = 0
    public private(set) var previewSeeksSubmitted: Int = 0
    public private(set) var coalescedSliderUpdates: Int = 0
    public private(set) var previewSeekCompletions: Int = 0
    public private(set) var stalePreviewCompletionsIgnored: Int = 0
    public private(set) var maximumPendingSeeks: Int = 0

    public init() {}

    public mutating func recordSliderUpdate(replacedPendingTarget: Bool) {
        rawSliderUpdates += 1
        if replacedPendingTarget {
            coalescedSliderUpdates += 1
        }
    }

    public mutating func recordPreviewSeekSubmitted(inFlight: Bool, hasPendingTarget: Bool) {
        previewSeeksSubmitted += 1
        recordPendingDepth(inFlight: inFlight, hasPendingTarget: hasPendingTarget)
    }

    public mutating func recordPreviewSeekCompleted(stale: Bool, inFlight: Bool, hasPendingTarget: Bool) {
        previewSeekCompletions += 1
        if stale {
            stalePreviewCompletionsIgnored += 1
        }
        recordPendingDepth(inFlight: inFlight, hasPendingTarget: hasPendingTarget)
    }

    public mutating func recordPendingDepth(inFlight: Bool, hasPendingTarget: Bool) {
        var pendingCount = 0
        if inFlight {
            pendingCount += 1
        }
        if hasPendingTarget {
            pendingCount += 1
        }
        maximumPendingSeeks = max(maximumPendingSeeks, pendingCount)
    }
}
