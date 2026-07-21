import XCTest
@testable import FFMpegasusCore

final class PlaybackTimelineStateTests: XCTestCase {
    func testTimelineTimeFormatting() {
        XCTAssertEqual(TimeFormatting.timelineTime(0), "00:00.000")
        XCTAssertEqual(TimeFormatting.timelineTime(1.234), "00:01.234")
        XCTAssertEqual(TimeFormatting.timelineTime(72.35), "01:12.350")
        XCTAssertEqual(TimeFormatting.timelineTime(3_723.456), "01:02:03.456")
        XCTAssertEqual(TimeFormatting.timelineTime(-0.001), "00:00.000")
        XCTAssertEqual(TimeFormatting.timelineTime(.nan), "00:00.000")
        XCTAssertEqual(TimeFormatting.timelineTime(.infinity), "00:00.000")
    }

    func testPlaybackTimeClampingAndSeekAvailability() {
        XCTAssertEqual(TimeFormatting.clampedPlaybackTime(-1, duration: 10), 0)
        XCTAssertEqual(TimeFormatting.clampedPlaybackTime(12, duration: 10), 10)
        XCTAssertFalse(TimeFormatting.isSeekableDuration(0))
        XCTAssertFalse(TimeFormatting.isSeekableDuration(.nan))
        XCTAssertTrue(TimeFormatting.isSeekableDuration(0.05))

        var state = PlaybackTimelineState()
        XCTAssertFalse(state.canSeek)
        state.open(duration: 10)
        XCTAssertFalse(state.canSeek)
        state.setReadyForSeeking(true)
        XCTAssertTrue(state.canSeek)
    }

    func testObserverDoesNotOverwriteScrubValue() {
        var state = readyState(duration: 20)
        state.applyObserverTime(4)
        XCTAssertEqual(state.displayedTimeSeconds, 4)

        state.beginScrubbing()
        state.updateScrubPosition(12)
        state.applyObserverTime(5)

        XCTAssertEqual(state.displayedTimeSeconds, 12)
        XCTAssertEqual(state.committedTimeSeconds, 4)
    }

    func testLivePreviewSeekUpdatesDisplayedTimeImmediately() {
        var state = readyState(duration: 20)
        state.applyObserverTime(4)
        state.beginScrubbing()
        state.updateScrubPosition(11)

        XCTAssertEqual(state.displayedTimeSeconds, 11)
        XCTAssertFalse(state.hasPendingSeek)

        let preview = state.beginLivePreviewSeek(to: 11)
        XCTAssertEqual(preview?.target, 11)
        XCTAssertTrue(state.isLivePreviewSeeking)
        XCTAssertTrue(state.hasPendingSeek)
        XCTAssertTrue(state.isScrubbing)
        XCTAssertEqual(state.committedTimeSeconds, 4)
    }

    func testRapidLivePreviewTargetsPreferNewestPosition() {
        var state = readyState(duration: 20)
        state.beginScrubbing()

        let first = state.beginLivePreviewSeek(to: 3)!
        let second = state.beginLivePreviewSeek(to: 12)!

        XCTAssertFalse(state.completeLivePreviewSeek(generation: first.generation))
        XCTAssertTrue(state.isLivePreviewSeeking)
        XCTAssertEqual(state.displayedTimeSeconds, 12)

        XCTAssertTrue(state.completeLivePreviewSeek(generation: second.generation))
        XCTAssertFalse(state.isLivePreviewSeeking)
        XCTAssertEqual(state.displayedTimeSeconds, 12)
        XCTAssertTrue(state.isScrubbing)
    }

    func testFinalSeekInvalidatesLivePreviewSeek() {
        var state = readyState(duration: 20)
        state.beginScrubbing()
        let preview = state.beginLivePreviewSeek(to: 6)!
        state.updateScrubPosition(9)

        let final = state.beginSeekFromScrub()!

        XCTAssertFalse(state.completeLivePreviewSeek(generation: preview.generation))
        XCTAssertTrue(state.isSeeking)
        XCTAssertFalse(state.isLivePreviewSeeking)
        XCTAssertEqual(final.target, 9)
        XCTAssertTrue(state.completeSeek(generation: final.generation, actualTime: 9))
        XCTAssertFalse(state.hasPendingSeek)
    }

    func testEndingScrubRequestsSelectedSeek() {
        var state = readyState(duration: 20)
        state.applyObserverTime(3)
        state.beginScrubbing()
        state.updateScrubPosition(9)

        let seek = state.beginSeekFromScrub()

        XCTAssertEqual(seek?.target, 9)
        XCTAssertTrue(state.isSeeking)
        XCTAssertFalse(state.canSeek)
        XCTAssertEqual(state.displayedTimeSeconds, 9)
    }

    func testPlayingAndPausedStateSurviveScrubbingStateMachine() {
        var paused = readyState(duration: 20)
        paused.setPlaying(false)
        paused.beginScrubbing()
        paused.updateScrubPosition(8)
        let pausedSeek = paused.beginSeekFromScrub()!
        paused.completeSeek(generation: pausedSeek.generation)
        XCTAssertFalse(paused.isPlaying)

        var playing = readyState(duration: 20)
        playing.setPlaying(true)
        playing.beginScrubbing()
        playing.updateScrubPosition(8)
        let playingSeek = playing.beginSeekFromScrub()!
        playing.completeSeek(generation: playingSeek.generation)
        XCTAssertTrue(playing.isPlaying)
    }

    func testStopAndCloseResetTimeline() {
        var state = readyState(duration: 20)
        state.setPlaying(true)
        state.applyObserverTime(7)
        state.beginScrubbing()
        let preview = state.beginLivePreviewSeek(to: 12)!

        let seek = state.stop()
        XCTAssertFalse(state.completeLivePreviewSeek(generation: preview.generation))
        XCTAssertEqual(seek.target, 0)
        XCTAssertEqual(state.displayedTimeSeconds, 0)
        XCTAssertFalse(state.isPlaying)
        XCTAssertFalse(state.isScrubbing)
        XCTAssertFalse(state.isLivePreviewSeeking)

        state.completeSeek(generation: seek.generation)
        state.close()
        XCTAssertFalse(state.hasVideo)
        XCTAssertEqual(state.durationSeconds, 0)
        XCTAssertEqual(state.displayedTimeSeconds, 0)
        XCTAssertFalse(state.canSeek)
    }

    func testStaleSeekCompletionCannotOverwriteNewerSeek() {
        var state = readyState(duration: 20)

        let first = state.beginSeek(to: 5)
        let second = state.beginSeek(to: 10)

        XCTAssertFalse(state.completeSeek(generation: first.generation, actualTime: 5))
        XCTAssertEqual(state.displayedTimeSeconds, 10)
        XCTAssertTrue(state.isSeeking)

        XCTAssertTrue(state.completeSeek(generation: second.generation, actualTime: 10))
        XCTAssertEqual(state.displayedTimeSeconds, 10)
        XCTAssertFalse(state.isSeeking)
    }

    func testOpeningOrClosingInvalidatesPendingSeekCallbacks() {
        var state = readyState(duration: 20)
        let oldSeek = state.beginSeek(to: 6)

        state.open(duration: 12)
        state.setReadyForSeeking(true)
        XCTAssertFalse(state.completeSeek(generation: oldSeek.generation, actualTime: 6))
        XCTAssertEqual(state.displayedTimeSeconds, 0)

        let secondSeek = state.beginSeek(to: 4)
        state.close()
        XCTAssertFalse(state.completeSeek(generation: secondSeek.generation, actualTime: 4))
        XCTAssertEqual(state.displayedTimeSeconds, 0)
        XCTAssertFalse(state.hasVideo)
    }

    func testCloseInvalidatesPendingLivePreviewCallbacks() {
        var state = readyState(duration: 20)
        state.beginScrubbing()
        let preview = state.beginLivePreviewSeek(to: 7)!

        state.close()

        XCTAssertFalse(state.completeLivePreviewSeek(generation: preview.generation))
        XCTAssertFalse(state.hasPendingSeek)
        XCTAssertFalse(state.isScrubbing)
        XCTAssertEqual(state.displayedTimeSeconds, 0)
    }

    func testOldLivePreviewCompletionDoesNotAffectNewScrubSession() {
        var state = readyState(duration: 20)
        state.beginScrubbing()
        let oldPreview = state.beginLivePreviewSeek(to: 4)!

        let stopSeek = state.stop()
        XCTAssertFalse(state.completeLivePreviewSeek(generation: oldPreview.generation))
        XCTAssertTrue(state.completeSeek(generation: stopSeek.generation, actualTime: 0))

        state.beginScrubbing()
        let newPreview = state.beginLivePreviewSeek(to: 11)!

        XCTAssertFalse(state.completeLivePreviewSeek(generation: oldPreview.generation))
        XCTAssertTrue(state.isLivePreviewSeeking)
        XCTAssertEqual(state.displayedTimeSeconds, 11)

        XCTAssertTrue(state.completeLivePreviewSeek(generation: newPreview.generation))
        XCTAssertFalse(state.isLivePreviewSeeking)
    }

    func testInvalidatingLivePreviewPreventsOldCompletionFromClearingNewSession() {
        var state = readyState(duration: 20)
        state.beginScrubbing()
        let oldPreview = state.beginLivePreviewSeek(to: 5)!

        state.invalidateLivePreviewSeek()
        XCTAssertFalse(state.isLivePreviewSeeking)
        XCTAssertFalse(state.completeLivePreviewSeek(generation: oldPreview.generation))

        state.updateScrubPosition(12)
        let newPreview = state.beginLivePreviewSeek(to: 12)!

        XCTAssertFalse(state.completeLivePreviewSeek(generation: oldPreview.generation))
        XCTAssertTrue(state.isLivePreviewSeeking)
        XCTAssertTrue(state.completeLivePreviewSeek(generation: newPreview.generation))
        XCTAssertFalse(state.isLivePreviewSeeking)
        XCTAssertEqual(state.displayedTimeSeconds, 12)
    }

    func testSelectedLiveScrubbingPolicyUsesSmootherCandidate() {
        XCTAssertEqual(PlaybackScrubbingPolicy.current.previewSeekThrottleNanoseconds, 75_000_000)
        XCTAssertEqual(PlaybackScrubbingPolicy.current.previewSeekToleranceSeconds, 0.075)
        XCTAssertEqual(PlaybackScrubbingPolicy.default.previewSeekThrottleNanoseconds, 50_000_000)
        XCTAssertEqual(PlaybackScrubbingPolicy.default.previewSeekToleranceSeconds, 0.05)
    }

    func testPrecisionRangeCentersAroundCurrentPosition() {
        let range = PlaybackPrecisionTimelineRange.centered(
            around: 120,
            durationSeconds: 3_600,
            windowSeconds: 10
        )

        XCTAssertEqual(range.startSeconds, 115, accuracy: 0.000_001)
        XCTAssertEqual(range.endSeconds, 125, accuracy: 0.000_001)
        XCTAssertEqual(range.durationSeconds, 10, accuracy: 0.000_001)
    }

    func testPrecisionRangeClampsNearZeroAndEnd() {
        let nearZero = PlaybackPrecisionTimelineRange.centered(
            around: 2,
            durationSeconds: 3_600,
            windowSeconds: 10
        )
        XCTAssertEqual(nearZero.startSeconds, 0, accuracy: 0.000_001)
        XCTAssertEqual(nearZero.endSeconds, 10, accuracy: 0.000_001)

        let nearEnd = PlaybackPrecisionTimelineRange.centered(
            around: 3_598,
            durationSeconds: 3_600,
            windowSeconds: 10
        )
        XCTAssertEqual(nearEnd.startSeconds, 3_590, accuracy: 0.000_001)
        XCTAssertEqual(nearEnd.endSeconds, 3_600, accuracy: 0.000_001)
    }

    func testPrecisionRangeUsesFullDurationForVeryShortMedia() {
        let range = PlaybackPrecisionTimelineRange.centered(
            around: 1.5,
            durationSeconds: 3,
            windowSeconds: 10
        )

        XCTAssertEqual(range.startSeconds, 0, accuracy: 0.000_001)
        XCTAssertEqual(range.endSeconds, 3, accuracy: 0.000_001)
    }

    func testPrecisionRangeMakesSubsecondAdjustmentPracticalForLongDurationMedia() {
        var state = readyState(duration: 3_600)
        _ = state.beginSeek(to: 1_800)
        _ = state.completeSeek(generation: state.seekGeneration, actualTime: 1_800)

        let range = state.precisionRange()
        XCTAssertEqual(range.durationSeconds, PlaybackPrecisionTimelineRange.defaultWindowSeconds, accuracy: 0.000_001)
        XCTAssertEqual(state.precisionStepTarget(by: PlaybackPrecisionTimelineRange.smallStepSeconds), 1_800.1, accuracy: 0.000_001)
        XCTAssertEqual(state.precisionStepTarget(by: -PlaybackPrecisionTimelineRange.smallStepSeconds), 1_799.9, accuracy: 0.000_001)
    }

    func testCoarseSeekFollowedByFineScrubUsesLocalPrecisionRange() {
        var state = readyState(duration: 3_600)
        let coarseSeek = state.beginSeek(to: 2_400)
        XCTAssertTrue(state.completeSeek(generation: coarseSeek.generation, actualTime: coarseSeek.target))

        let range = state.precisionRange()
        XCTAssertEqual(range.startSeconds, 2_395, accuracy: 0.000_001)
        XCTAssertEqual(range.endSeconds, 2_405, accuracy: 0.000_001)

        state.beginScrubbing()
        state.updateScrubPosition(2_400.4)
        XCTAssertEqual(state.displayedTimeSeconds, 2_400.4, accuracy: 0.000_001)

        let final = state.beginSeekFromScrub()!
        XCTAssertEqual(final.target, 2_400.4, accuracy: 0.000_001)
    }

    func testPrecisionStepClampsAtMediaBoundaries() {
        var state = readyState(duration: 20)
        state.applyObserverTime(0.04)
        XCTAssertEqual(state.precisionStepTarget(by: -PlaybackPrecisionTimelineRange.smallStepSeconds), 0, accuracy: 0.000_001)

        state.applyObserverTime(19.96)
        XCTAssertEqual(state.precisionStepTarget(by: PlaybackPrecisionTimelineRange.smallStepSeconds), 20, accuracy: 0.000_001)
    }

    func testScrubbingDiagnosticsTrackCoalescedInputAndBoundedPendingDepth() {
        var diagnostics = PlaybackScrubbingDiagnostics()

        diagnostics.recordSliderUpdate(replacedPendingTarget: false)
        diagnostics.recordPendingDepth(inFlight: false, hasPendingTarget: true)
        diagnostics.recordSliderUpdate(replacedPendingTarget: true)
        diagnostics.recordSliderUpdate(replacedPendingTarget: true)
        diagnostics.recordPreviewSeekSubmitted(inFlight: true, hasPendingTarget: false)
        diagnostics.recordPendingDepth(inFlight: true, hasPendingTarget: true)
        diagnostics.recordPreviewSeekCompleted(stale: false, inFlight: false, hasPendingTarget: true)

        XCTAssertEqual(diagnostics.rawSliderUpdates, 3)
        XCTAssertEqual(diagnostics.coalescedSliderUpdates, 2)
        XCTAssertEqual(diagnostics.previewSeeksSubmitted, 1)
        XCTAssertEqual(diagnostics.previewSeekCompletions, 1)
        XCTAssertEqual(diagnostics.stalePreviewCompletionsIgnored, 0)
        XCTAssertLessThanOrEqual(diagnostics.maximumPendingSeeks, 2)
    }

    func testScrubbingDiagnosticsCountStalePreviewCompletions() {
        var diagnostics = PlaybackScrubbingDiagnostics()

        diagnostics.recordPreviewSeekSubmitted(inFlight: true, hasPendingTarget: false)
        diagnostics.recordPreviewSeekCompleted(stale: true, inFlight: false, hasPendingTarget: false)

        XCTAssertEqual(diagnostics.previewSeeksSubmitted, 1)
        XCTAssertEqual(diagnostics.previewSeekCompletions, 1)
        XCTAssertEqual(diagnostics.stalePreviewCompletionsIgnored, 1)
    }

    private func readyState(duration: TimeInterval) -> PlaybackTimelineState {
        var state = PlaybackTimelineState()
        state.open(duration: duration)
        state.setReadyForSeeking(true)
        return state
    }
}
