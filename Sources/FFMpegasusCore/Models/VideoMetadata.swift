import Foundation

public struct VideoMetadata: Equatable, Sendable {
    public let duration: TimeInterval
    public let width: Int?
    public let height: Int?
    public let videoCodec: String?
    public let audioCodec: String?
    public let frameRate: Double?

    public var dimensionsText: String {
        guard let width, let height else { return "Unknown" }
        return "\(width)x\(height)"
    }
}

public struct FFprobeResponse: Decodable, Sendable {
    public let streams: [FFprobeStream]
    public let format: FFprobeFormat?

    public func videoMetadata() -> VideoMetadata {
        let videoStream = streams.first { $0.codecType == "video" }
        let audioStream = streams.first { $0.codecType == "audio" }
        let duration = format?.durationValue ?? videoStream?.durationValue ?? 0

        return VideoMetadata(
            duration: duration,
            width: videoStream?.width,
            height: videoStream?.height,
            videoCodec: videoStream?.codecName,
            audioCodec: audioStream?.codecName,
            frameRate: videoStream?.frameRateValue
        )
    }
}

public struct FFprobeStream: Decodable, Sendable {
    public let codecName: String?
    public let codecType: String?
    public let width: Int?
    public let height: Int?
    public let duration: String?
    public let avgFrameRate: String?
    public let rFrameRate: String?

    enum CodingKeys: String, CodingKey {
        case codecName = "codec_name"
        case codecType = "codec_type"
        case width
        case height
        case duration
        case avgFrameRate = "avg_frame_rate"
        case rFrameRate = "r_frame_rate"
    }

    public var durationValue: TimeInterval? {
        duration.flatMap(TimeInterval.init)
    }

    public var frameRateValue: Double? {
        parseRate(avgFrameRate) ?? parseRate(rFrameRate)
    }

    private func parseRate(_ value: String?) -> Double? {
        guard let value, value != "0/0" else { return nil }
        let parts = value.split(separator: "/")
        if parts.count == 2,
           let numerator = Double(parts[0]),
           let denominator = Double(parts[1]),
           denominator != 0 {
            return numerator / denominator
        }
        return Double(value)
    }
}

public struct FFprobeFormat: Decodable, Sendable {
    public let duration: String?

    public var durationValue: TimeInterval? {
        duration.flatMap(TimeInterval.init)
    }
}
