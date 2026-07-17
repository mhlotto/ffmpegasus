import Foundation

public enum TimeFormatting {
    public static func clockTime(_ seconds: TimeInterval) -> String {
        timelineTime(seconds)
    }

    public static func timelineTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "00:00.000" }
        let clampedSeconds = max(0, seconds)
        let totalMilliseconds = Int((clampedSeconds * 1000).rounded())
        let milliseconds = totalMilliseconds % 1000
        let totalSeconds = totalMilliseconds / 1000
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secondsPart = totalSeconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d.%03d", hours, minutes, secondsPart, milliseconds)
        }
        return String(format: "%02d:%02d.%03d", minutes, secondsPart, milliseconds)
    }

    public static func ffmpegSeconds(_ seconds: TimeInterval) -> String {
        String(format: "%.6f", seconds)
    }

    public static func clampedPlaybackTime(_ seconds: TimeInterval, duration: TimeInterval) -> TimeInterval {
        guard seconds.isFinite else { return 0 }
        guard duration.isFinite, duration > 0 else { return max(0, seconds) }
        return min(max(0, seconds), duration)
    }

    public static func isSeekableDuration(_ duration: TimeInterval) -> Bool {
        duration.isFinite && duration > 0
    }
}
