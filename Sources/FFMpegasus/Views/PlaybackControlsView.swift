import FFMpegasusCore
import SwiftUI

struct PlaybackControlsView: View {
    let hasVideo: Bool
    let isPlaying: Bool
    let currentTime: TimeInterval
    let duration: TimeInterval
    let onPlay: () -> Void
    let onPause: () -> Void
    let onStop: () -> Void
    let onSeek: (TimeInterval) -> Void

    @State private var sliderValue: Double = 0
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button(action: onPlay) {
                    Label("Play", systemImage: "play.fill")
                }
                .disabled(!hasVideo || isPlaying)

                Button(action: onPause) {
                    Label("Pause", systemImage: "pause.fill")
                }
                .disabled(!hasVideo || !isPlaying)

                Button(action: onStop) {
                    Label("Stop", systemImage: "stop.fill")
                }
                .disabled(!hasVideo)

                Text(TimeFormatting.clockTime(currentTime))
                    .monospacedDigit()
                    .frame(width: 72, alignment: .trailing)

                Slider(
                    value: Binding(
                        get: { isDragging ? sliderValue : currentTime },
                        set: { value in
                            sliderValue = value
                            isDragging = true
                        }
                    ),
                    in: 0...max(duration, 0.01),
                    onEditingChanged: { editing in
                        isDragging = editing
                        if !editing {
                            onSeek(sliderValue)
                        }
                    }
                )
                .disabled(!hasVideo)

                Text(TimeFormatting.clockTime(duration))
                    .monospacedDigit()
                    .frame(width: 72, alignment: .leading)
            }
        }
    }
}
