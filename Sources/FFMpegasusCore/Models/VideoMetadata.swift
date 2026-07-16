import Foundation

public struct VideoMetadata: Equatable, Sendable {
    public let duration: TimeInterval
    public let width: Int?
    public let height: Int?
    public let videoCodec: String?
    public let audioCodec: String?
    public let audioDuration: TimeInterval?
    public let frameRate: Double?
    public let pixelFormat: String?
    public let rotationDegrees: Int?

    public init(duration: TimeInterval, width: Int?, height: Int?, videoCodec: String?, audioCodec: String?, audioDuration: TimeInterval? = nil, frameRate: Double?, pixelFormat: String? = nil, rotationDegrees: Int? = nil) {
        self.duration = duration
        self.width = width
        self.height = height
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.audioDuration = audioDuration
        self.frameRate = frameRate
        self.pixelFormat = pixelFormat
        self.rotationDegrees = rotationDegrees
    }

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
            audioDuration: audioStream?.durationValue ?? (audioStream == nil ? nil : format?.durationValue),
            frameRate: videoStream?.frameRateValue,
            pixelFormat: videoStream?.pixelFormat,
            rotationDegrees: videoStream?.rotationDegrees
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
    public let pixelFormat: String?
    public let tags: [String: String]?
    public let sideDataList: [FFprobeSideData]?

    enum CodingKeys: String, CodingKey {
        case codecName = "codec_name"
        case codecType = "codec_type"
        case width
        case height
        case duration
        case avgFrameRate = "avg_frame_rate"
        case rFrameRate = "r_frame_rate"
        case pixelFormat = "pix_fmt"
        case tags
        case sideDataList = "side_data_list"
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

    public var rotationDegrees: Int? {
        if let rotate = tags?["rotate"], let value = Double(rotate) {
            return Int(value.rounded()).normalizedRotationDegrees
        }
        if let sideRotation = sideDataList?.compactMap(\.rotation).first {
            return Int(sideRotation.rounded()).normalizedRotationDegrees
        }
        return nil
    }
}

public struct FFprobeSideData: Decodable, Sendable {
    public let rotation: Double?
}

public struct FFprobeFormat: Decodable, Sendable {
    public let duration: String?

    public var durationValue: TimeInterval? {
        duration.flatMap(TimeInterval.init)
    }
}
