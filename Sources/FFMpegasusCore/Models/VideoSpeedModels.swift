import Foundation

public enum SpeedPreset: String, CaseIterable, Identifiable, Sendable {
    case x0_5
    case x0_75
    case x1_0
    case x1_25
    case x1_5
    case x2_0
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .x0_5: "0.5x"
        case .x0_75: "0.75x"
        case .x1_0: "1.0x"
        case .x1_25: "1.25x"
        case .x1_5: "1.5x"
        case .x2_0: "2.0x"
        case .custom: "Custom"
        }
    }

    public var multiplier: Double? {
        switch self {
        case .x0_5: 0.5
        case .x0_75: 0.75
        case .x1_0: 1.0
        case .x1_25: 1.25
        case .x1_5: 1.5
        case .x2_0: 2.0
        case .custom: nil
        }
    }
}

public enum SpeedAudioMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case keep
    case remove

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .keep: "Keep Audio"
        case .remove: "Remove Audio"
        }
    }
}

public struct VideoSpeed: Equatable, Codable, Sendable {
    public static let minimumMultiplier = 0.25
    public static let maximumMultiplier = 4.0
    public static let noChangeTolerance = 0.000_001

    public let multiplier: Double

    public init(multiplier: Double) throws {
        guard multiplier.isFinite else { throw VideoSpeedValidationError.invalidSpeed }
        guard multiplier >= Self.minimumMultiplier else { throw VideoSpeedValidationError.speedTooLow }
        guard multiplier <= Self.maximumMultiplier else { throw VideoSpeedValidationError.speedTooHigh }
        self.multiplier = multiplier
    }

    public var isNoChange: Bool {
        abs(multiplier - 1.0) <= Self.noChangeTolerance
    }

    public func expectedDuration(sourceDuration: TimeInterval) throws -> TimeInterval {
        guard sourceDuration.isFinite, sourceDuration > 0 else {
            throw VideoSpeedValidationError.invalidSourceDuration
        }
        let duration = sourceDuration / multiplier
        guard duration.isFinite, duration > 0 else {
            throw VideoSpeedValidationError.invalidExpectedDuration
        }
        return duration
    }

    public func videoFilter() -> String {
        "setpts=PTS/\(Self.format(multiplier))"
    }

    public func audioTempoFilter() throws -> String {
        try audioTempoFactors().map { "atempo=\(Self.format($0))" }.joined(separator: ",")
    }

    public func audioTempoFactors() throws -> [Double] {
        guard !isNoChange else { return [1.0] }
        if (0.5...2.0).contains(multiplier) {
            return [multiplier]
        }
        if multiplier < 0.5 {
            return [0.5, multiplier / 0.5]
        }
        return [2.0, multiplier / 2.0]
    }

    public static func parse(_ value: String) -> VideoSpeed? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let multiplier = Double(trimmed) else { return nil }
        return try? VideoSpeed(multiplier: multiplier)
    }

    public static func format(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 6
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    public var filenameLabel: String {
        var formatted = Self.format(multiplier)
        while formatted.contains(".") && formatted.last == "0" {
            formatted.removeLast()
        }
        if formatted.last == "." {
            formatted.removeLast()
        }
        return formatted.replacingOccurrences(of: ".", with: "_") + "x"
    }
}

public struct VideoSpeedRequest: Equatable, Sendable {
    public let inputURL: URL
    public let outputURL: URL
    public let sourceDuration: TimeInterval
    public let sourceDimensions: VideoDimensions
    public let sourceRotationDegrees: Int?
    public let hasVideoStream: Bool
    public let hasAudioStream: Bool
    public let speed: VideoSpeed
    public let audioMode: SpeedAudioMode

    public init(
        inputURL: URL,
        outputURL: URL,
        sourceDuration: TimeInterval,
        sourceDimensions: VideoDimensions,
        sourceRotationDegrees: Int?,
        hasVideoStream: Bool,
        hasAudioStream: Bool,
        speed: VideoSpeed,
        audioMode: SpeedAudioMode
    ) {
        self.inputURL = inputURL
        self.outputURL = outputURL
        self.sourceDuration = sourceDuration
        self.sourceDimensions = sourceDimensions
        self.sourceRotationDegrees = sourceRotationDegrees
        self.hasVideoStream = hasVideoStream
        self.hasAudioStream = hasAudioStream
        self.speed = speed
        self.audioMode = audioMode
    }

    public var keepsAudio: Bool {
        audioMode == .keep && hasAudioStream
    }

    public func expectedDuration() throws -> TimeInterval {
        try speed.expectedDuration(sourceDuration: sourceDuration)
    }

    public func outputDimensions() throws -> VideoDimensions {
        guard hasVideoStream else { throw VideoSpeedValidationError.missingVideoStream }
        guard sourceDimensions.width > 0, sourceDimensions.height > 0 else {
            throw VideoSpeedValidationError.invalidSourceDimensions
        }
        let normalizedRotation = (sourceRotationDegrees ?? 0).normalizedRotationDegrees
        let dimensions = normalizedRotation == 90 || normalizedRotation == 270
            ? VideoDimensions(width: sourceDimensions.height, height: sourceDimensions.width)
            : sourceDimensions
        return VideoDimensions(width: dimensions.width.makeEvenDownForTransform(), height: dimensions.height.makeEvenDownForTransform())
    }

    public func validateForExport() throws {
        guard hasVideoStream else { throw VideoSpeedValidationError.missingVideoStream }
        guard !speed.isNoChange else { throw VideoSpeedValidationError.noSpeedChange }
        _ = try expectedDuration()
        _ = try outputDimensions()
    }
}

public enum VideoSpeedValidationError: LocalizedError, Equatable, Sendable {
    case invalidSpeed
    case speedTooLow
    case speedTooHigh
    case noSpeedChange
    case invalidSourceDuration
    case invalidExpectedDuration
    case missingVideoStream
    case missingLibx264
    case invalidSourceDimensions
    case wrongCodec(String?)
    case wrongDimensions(expected: VideoDimensions, actual: VideoDimensions)
    case oddDimensions(VideoDimensions)
    case durationMismatch(expected: TimeInterval, actual: TimeInterval, tolerance: TimeInterval)
    case unexpectedAudio
    case missingExpectedAudio
    case audioVideoDurationMismatch(video: TimeInterval, audio: TimeInterval)
    case staleRotationMetadata(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidSpeed:
            "Speed must be a finite number."
        case .speedTooLow:
            "Speed must be at least 0.25x."
        case .speedTooHigh:
            "Speed must be at most 4.0x."
        case .noSpeedChange:
            "Choose a speed other than 1.0x before exporting."
        case .invalidSourceDuration:
            "The source video duration is unavailable."
        case .invalidExpectedDuration:
            "The expected output duration is invalid."
        case .missingVideoStream:
            "Input contains no video stream."
        case .missingLibx264:
            "Changing speed requires an FFmpeg build with the libx264 encoder."
        case .invalidSourceDimensions:
            "Source video dimensions are unavailable."
        case .wrongCodec(let codec):
            "Speed output is not H.264. Detected codec: \(codec ?? "unknown")."
        case .wrongDimensions(let expected, let actual):
            "Speed output dimensions are \(actual.width)x\(actual.height), expected \(expected.width)x\(expected.height)."
        case .oddDimensions(let dimensions):
            "Speed output dimensions must be even. Got \(dimensions.width)x\(dimensions.height)."
        case .durationMismatch(let expected, let actual, let tolerance):
            String(format: "Speed output duration is %.3f seconds, expected %.3f seconds within %.3f seconds.", actual, expected, tolerance)
        case .unexpectedAudio:
            "Speed output contains audio, but audio removal was requested."
        case .missingExpectedAudio:
            "Speed output is missing expected audio."
        case .audioVideoDurationMismatch(let video, let audio):
            String(format: "Audio duration %.3f seconds differs from video duration %.3f seconds.", audio, video)
        case .staleRotationMetadata(let rotation):
            "Speed output still has rotation metadata: \(rotation) degrees."
        }
    }
}

extension OutputFilename {
    public static func speedName(for inputURL: URL, speed: VideoSpeed) -> String {
        let base = inputURL.deletingPathExtension().lastPathComponent
        return "\(base)-speed-\(speed.filenameLabel).mp4"
    }
}
