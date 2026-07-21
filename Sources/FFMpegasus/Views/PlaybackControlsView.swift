import FFMpegasusCore
import SwiftUI

struct PlaybackControlsView: View {
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
                    value: Binding(
                        get: { TimeFormatting.clampedPlaybackTime(currentTime, duration: duration) },
                        set: { value in
                            if !isScrubbing {
                                onBeginScrubbing()
                            }
                            onScrubChanged(value)
                        }
                    ),
                    in: 0...max(duration, 0.001),
                    onEditingChanged: { editing in
                        if !editing {
                            onEndScrubbing()
                        } else if !isScrubbing {
                            onBeginScrubbing()
                        }
                    }
                )
                .disabled(!canSeek)
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
        }
    }
}
