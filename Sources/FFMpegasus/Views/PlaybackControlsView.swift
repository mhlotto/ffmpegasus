import FFMpegasusCore
import SwiftUI

struct PlaybackControlsView: View {
    private enum ActiveScrubber {
        case primary
        case precision
    }

    let hasVideo: Bool
    let isPlaying: Bool
    let currentTime: TimeInterval
    let duration: TimeInterval
    let canSeek: Bool
    let isScrubbing: Bool
    let isSeeking: Bool
    let onPlay: () -> Void
    let onPause: () -> Void
    let onStop: () -> Void
    let onBeginScrubbing: () -> Void
    let onScrubChanged: (TimeInterval) -> Void
    let onEndScrubbing: () -> Void
    let onSeek: (TimeInterval) -> Void

    @State private var activeScrubber: ActiveScrubber?
    @State private var precisionRangeAnchor: PlaybackPrecisionTimelineRange?

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button(action: onPlay) {
                    Label("Play", systemImage: "play.fill")
                }
                .disabled(!hasVideo || isPlaying)
                .accessibilityIdentifier("playback.play")

                Button(action: onPause) {
                    Label("Pause", systemImage: "pause.fill")
                }
                .disabled(!hasVideo || !isPlaying)
                .accessibilityIdentifier("playback.pause")

                Button(action: onStop) {
                    Label("Stop", systemImage: "stop.fill")
                }
                .disabled(!hasVideo)
                .accessibilityIdentifier("playback.stop")

                Text(TimeFormatting.timelineTime(currentTime))
                    .monospacedDigit()
                    .frame(width: duration >= 3600 ? 96 : 76, alignment: .trailing)
                    .accessibilityIdentifier("playback.currentTime")

                Slider(
                    value: primarySliderBinding,
                    in: 0...max(duration, 0.001),
                    onEditingChanged: { editing in
                        if editing {
                            beginPrimaryScrubbing()
                        } else {
                            endScrubbing(for: .primary)
                        }
                    }
                )
                .disabled(!canSeek || activeScrubber == .precision)
                .accessibilityLabel("Video timeline")
                .accessibilityIdentifier("playback.timeline")
                .accessibilityValue("\(TimeFormatting.timelineTime(currentTime)) of \(TimeFormatting.timelineTime(duration))")

                Text(TimeFormatting.timelineTime(duration))
                    .monospacedDigit()
                    .frame(width: duration >= 3600 ? 96 : 76, alignment: .leading)
                    .accessibilityIdentifier("playback.duration")
            }
            if isSeeking {
                Text("Seeking...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            precisionTimeline
        }
        .onChange(of: hasVideo) { _, hasVideo in
            if !hasVideo {
                activeScrubber = nil
                precisionRangeAnchor = nil
            }
        }
        .onChange(of: duration) { _, _ in
            precisionRangeAnchor = nil
        }
        .onChange(of: isScrubbing) { _, isScrubbing in
            if !isScrubbing {
                activeScrubber = nil
                precisionRangeAnchor = nil
            }
        }
    }

    private var primarySliderBinding: Binding<TimeInterval> {
        Binding(
            get: { TimeFormatting.clampedPlaybackTime(currentTime, duration: duration) },
            set: { value in
                beginPrimaryScrubbing()
                onScrubChanged(value)
            }
        )
    }

    private var precisionTimeline: some View {
        let range = currentPrecisionRange
        let sliderRange = range.startSeconds...max(range.endSeconds, range.startSeconds + 0.001)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Fine tune")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("playback.precisionLabel")

                Button {
                    stepPrecision(by: -PlaybackPrecisionTimelineRange.smallStepSeconds)
                } label: {
                    Label("Back 0.1 seconds", systemImage: "gobackward")
                        .labelStyle(.iconOnly)
                }
                .disabled(!canUsePrecisionStep)
                .help("Back 0.1 seconds")
                .accessibilityIdentifier("playback.precisionStepBackward")

                Text(TimeFormatting.timelineTime(range.startSeconds))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: duration >= 3600 ? 96 : 76, alignment: .trailing)
                    .accessibilityIdentifier("playback.precisionRangeStart")

                Slider(
                    value: precisionSliderBinding,
                    in: sliderRange,
                    onEditingChanged: { editing in
                        if editing {
                            beginPrecisionScrubbing()
                        } else {
                            endScrubbing(for: .precision)
                        }
                    }
                )
                .disabled(!canSeek || activeScrubber == .primary)
                .accessibilityLabel("Precision timeline")
                .accessibilityIdentifier("playback.precisionTimeline")
                .accessibilityValue(
                    "\(TimeFormatting.timelineTime(currentTime)) in \(TimeFormatting.timelineTime(range.startSeconds)) to \(TimeFormatting.timelineTime(range.endSeconds))"
                )

                Text(TimeFormatting.timelineTime(range.endSeconds))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: duration >= 3600 ? 96 : 76, alignment: .leading)
                    .accessibilityIdentifier("playback.precisionRangeEnd")

                Button {
                    stepPrecision(by: PlaybackPrecisionTimelineRange.smallStepSeconds)
                } label: {
                    Label("Forward 0.1 seconds", systemImage: "goforward")
                        .labelStyle(.iconOnly)
                }
                .disabled(!canUsePrecisionStep)
                .help("Forward 0.1 seconds")
                .accessibilityIdentifier("playback.precisionStepForward")
            }

            Text("Local range: \(TimeFormatting.timelineTime(range.startSeconds)) to \(TimeFormatting.timelineTime(range.endSeconds))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("playback.precisionRangeSummary")
        }
    }

    private var precisionSliderBinding: Binding<TimeInterval> {
        Binding(
            get: { currentPrecisionRange.clamped(currentTime) },
            set: { value in
                beginPrecisionScrubbing()
                onScrubChanged(currentPrecisionRange.clamped(value))
            }
        )
    }

    private var currentPrecisionRange: PlaybackPrecisionTimelineRange {
        if let precisionRangeAnchor {
            return precisionRangeAnchor
        }
        return PlaybackPrecisionTimelineRange.centered(around: currentTime, durationSeconds: duration)
    }

    private var canUsePrecisionStep: Bool {
        canSeek && !isScrubbing && !isSeeking && activeScrubber == nil
    }

    private func beginPrimaryScrubbing() {
        guard activeScrubber != .precision else { return }
        if activeScrubber == nil {
            activeScrubber = .primary
            precisionRangeAnchor = nil
            onBeginScrubbing()
        }
    }

    private func beginPrecisionScrubbing() {
        guard activeScrubber != .primary else { return }
        if activeScrubber == nil {
            activeScrubber = .precision
            precisionRangeAnchor = PlaybackPrecisionTimelineRange.centered(around: currentTime, durationSeconds: duration)
            onBeginScrubbing()
        }
    }

    private func endScrubbing(for scrubber: ActiveScrubber) {
        guard activeScrubber == scrubber else { return }
        activeScrubber = nil
        precisionRangeAnchor = nil
        onEndScrubbing()
    }

    private func stepPrecision(by offset: TimeInterval) {
        guard canUsePrecisionStep else { return }
        onSeek(TimeFormatting.clampedPlaybackTime(currentTime + offset, duration: duration))
    }
}
