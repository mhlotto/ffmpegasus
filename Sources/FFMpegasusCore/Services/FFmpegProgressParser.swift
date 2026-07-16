import Foundation

public struct FFmpegProgress: Equatable, Sendable {
    public let outTime: TimeInterval?
    public let progress: String?
}

public struct FFmpegProgressParser: Sendable {
    public init() {}

    public func parse(_ text: String) -> FFmpegProgress? {
        var outTime: TimeInterval?
        var progress: String?

        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }

            switch parts[0] {
            case "out_time_ms", "out_time_us":
                if let raw = Double(parts[1]) {
                    outTime = raw / 1_000_000
                }
            case "out_time":
                outTime = parseTimestamp(parts[1])
            case "progress":
                progress = parts[1]
            default:
                continue
            }
        }

        guard outTime != nil || progress != nil else { return nil }
        return FFmpegProgress(outTime: outTime, progress: progress)
    }

    private func parseTimestamp(_ value: String) -> TimeInterval? {
        let parts = value.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 3 else { return nil }
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }
}
