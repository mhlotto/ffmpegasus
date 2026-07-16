import Foundation

public enum VideoRotation: String, CaseIterable, Identifiable, Codable, Sendable {
    case none
    case clockwise90
    case counterclockwise90
    case rotate180

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: "None"
        case .clockwise90: "90 degrees clockwise"
        case .counterclockwise90: "90 degrees counterclockwise"
        case .rotate180: "180 degrees"
        }
    }

    var filterComponents: [String] {
        switch self {
        case .none: []
        case .clockwise90: ["transpose=clock"]
        case .counterclockwise90: ["transpose=cclock"]
        case .rotate180: ["hflip", "vflip"]
        }
    }

    var swapsDimensions: Bool {
        self == .clockwise90 || self == .counterclockwise90
    }
}

public struct VideoTransformRequest: Equatable, Sendable {
    public let inputURL: URL
    public let outputURL: URL
    public let sourceDuration: TimeInterval
    public let sourceDimensions: VideoDimensions
    public let sourceRotationDegrees: Int?
    public let hasVideoStream: Bool
    public let hasAudioStream: Bool
    public let rotation: VideoRotation
    public let flipHorizontal: Bool
    public let flipVertical: Bool

    public init(
        inputURL: URL,
        outputURL: URL,
        sourceDuration: TimeInterval,
        sourceDimensions: VideoDimensions,
        sourceRotationDegrees: Int?,
        hasVideoStream: Bool,
        hasAudioStream: Bool,
        rotation: VideoRotation,
        flipHorizontal: Bool,
        flipVertical: Bool
    ) {
        self.inputURL = inputURL
        self.outputURL = outputURL
        self.sourceDuration = sourceDuration
        self.sourceDimensions = sourceDimensions
        self.sourceRotationDegrees = sourceRotationDegrees
        self.hasVideoStream = hasVideoStream
        self.hasAudioStream = hasAudioStream
        self.rotation = rotation
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
    }

    public var hasTransformation: Bool {
        rotation != .none || flipHorizontal || flipVertical
    }

    public func filterChain() throws -> String {
        guard hasTransformation else {
            throw VideoTransformValidationError.noTransformationSelected
        }

        var filters = rotation.filterComponents
        if flipHorizontal {
            filters.append("hflip")
        }
        if flipVertical {
            filters.append("vflip")
        }
        return filters.joined(separator: ",")
    }

    public func normalizedSourceDimensions() throws -> VideoDimensions {
        guard hasVideoStream else { throw VideoTransformValidationError.missingVideoStream }
        guard sourceDimensions.width > 0, sourceDimensions.height > 0 else {
            throw VideoTransformValidationError.invalidSourceDimensions
        }
        let normalizedRotation = (sourceRotationDegrees ?? 0).normalizedRotationDegrees
        let dimensions = normalizedRotation == 90 || normalizedRotation == 270
            ? VideoDimensions(width: sourceDimensions.height, height: sourceDimensions.width)
            : sourceDimensions
        return VideoDimensions(width: dimensions.width.makeEvenDownForTransform(), height: dimensions.height.makeEvenDownForTransform())
    }

    public func outputDimensions() throws -> VideoDimensions {
        let normalized = try normalizedSourceDimensions()
        if rotation.swapsDimensions {
            return VideoDimensions(width: normalized.height, height: normalized.width)
        }
        return normalized
    }
}

public enum VideoTransformValidationError: LocalizedError, Equatable, Sendable {
    case noTransformationSelected
    case missingVideoStream
    case invalidSourceDimensions
    case invalidFilterChain
    case missingLibx264
    case wrongCodec(String?)
    case wrongDimensions(expected: VideoDimensions, actual: VideoDimensions)
    case oddDimensions(VideoDimensions)
    case unexpectedAudio
    case missingExpectedAudio
    case durationMismatch
    case staleRotationMetadata(Int)

    public var errorDescription: String? {
        switch self {
        case .noTransformationSelected:
            "Select a rotation or flip before exporting."
        case .missingVideoStream:
            "Input contains no video stream."
        case .invalidSourceDimensions:
            "Source video dimensions are unavailable."
        case .invalidFilterChain:
            "The video transformation filter chain is invalid."
        case .missingLibx264:
            "Rotate / Flip requires an FFmpeg build with the libx264 encoder."
        case .wrongCodec(let codec):
            "Transformed output is not H.264. Detected codec: \(codec ?? "unknown")."
        case .wrongDimensions(let expected, let actual):
            "Transformed output dimensions are \(actual.width)x\(actual.height), expected \(expected.width)x\(expected.height)."
        case .oddDimensions(let dimensions):
            "Transformed output dimensions must be even. Got \(dimensions.width)x\(dimensions.height)."
        case .unexpectedAudio:
            "Transformed output contains audio, but the source had no audio."
        case .missingExpectedAudio:
            "Transformed output is missing expected audio."
        case .durationMismatch:
            "Transformed output duration differs too much from the source."
        case .staleRotationMetadata(let rotation):
            "Transformed output still has rotation metadata: \(rotation) degrees."
        }
    }
}

extension OutputFilename {
    public static func transformedName(for inputURL: URL, rotation: VideoRotation, flipHorizontal: Bool, flipVertical: Bool) -> String {
        let base = inputURL.deletingPathExtension().lastPathComponent
        if rotation != .none, flipHorizontal || flipVertical {
            return "\(base)-transformed.mp4"
        }
        if rotation != .none {
            return "\(base)-rotated.mp4"
        }
        return "\(base)-flipped.mp4"
    }
}

extension Int {
    var normalizedRotationDegrees: Int {
        let value = self % 360
        return value >= 0 ? value : value + 360
    }

    func makeEvenDownForTransform() -> Int {
        let even = self - (self % 2)
        return Swift.max(even, 2)
    }
}
