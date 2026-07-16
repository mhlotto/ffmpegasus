import Foundation

public enum FrameImageFormat: String, CaseIterable, Identifiable, Codable, Sendable {
    case png
    case jpeg

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        }
    }

    public var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        }
    }
}

public enum JPEGQualityPreset: String, CaseIterable, Identifiable, Sendable {
    case high
    case balanced
    case smallFile
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .high: "High"
        case .balanced: "Balanced"
        case .smallFile: "Small File"
        case .custom: "Custom"
        }
    }

    public var qualityValue: Int? {
        switch self {
        case .high: 2
        case .balanced: 4
        case .smallFile: 7
        case .custom: nil
        }
    }
}

public struct JPEGQuality: Equatable, Codable, Sendable {
    public static let validRange = 2...31
    public let ffmpegValue: Int

    public init(ffmpegValue: Int) throws {
        guard Self.validRange.contains(ffmpegValue) else {
            throw FrameExportValidationError.invalidJPEGQuality
        }
        self.ffmpegValue = ffmpegValue
    }
}

public struct FrameExportRequest: Equatable, Sendable {
    public let inputURL: URL
    public let outputURL: URL
    public let timestampSeconds: Double
    public let sourceDuration: TimeInterval
    public let sourceDimensions: VideoDimensions
    public let sourceRotationDegrees: Int?
    public let hasVideoStream: Bool
    public let format: FrameImageFormat
    public let jpegQuality: JPEGQuality?

    public init(
        inputURL: URL,
        outputURL: URL,
        timestampSeconds: Double,
        sourceDuration: TimeInterval,
        sourceDimensions: VideoDimensions,
        sourceRotationDegrees: Int?,
        hasVideoStream: Bool,
        format: FrameImageFormat,
        jpegQuality: JPEGQuality?
    ) {
        self.inputURL = inputURL
        self.outputURL = outputURL
        self.timestampSeconds = timestampSeconds
        self.sourceDuration = sourceDuration
        self.sourceDimensions = sourceDimensions
        self.sourceRotationDegrees = sourceRotationDegrees
        self.hasVideoStream = hasVideoStream
        self.format = format
        self.jpegQuality = jpegQuality
    }

    public func validate() throws {
        guard hasVideoStream else { throw FrameExportValidationError.missingVideoStream }
        guard timestampSeconds.isFinite else { throw FrameExportValidationError.invalidTimestamp }
        guard timestampSeconds >= 0 else { throw FrameExportValidationError.timestampBeforeZero }
        guard sourceDuration.isFinite, sourceDuration > 0 else { throw FrameExportValidationError.invalidDuration }
        guard timestampSeconds <= sourceDuration else { throw FrameExportValidationError.timestampBeyondDuration }
        guard sourceDimensions.width > 0, sourceDimensions.height > 0 else { throw FrameExportValidationError.invalidDimensions }
        if format == .jpeg {
            guard jpegQuality != nil else { throw FrameExportValidationError.invalidJPEGQuality }
        }
    }

    public func expectedDimensions() throws -> VideoDimensions {
        guard sourceDimensions.width > 0, sourceDimensions.height > 0 else {
            throw FrameExportValidationError.invalidDimensions
        }
        let normalizedRotation = (sourceRotationDegrees ?? 0).normalizedRotationDegrees
        let dimensions = normalizedRotation == 90 || normalizedRotation == 270
            ? VideoDimensions(width: sourceDimensions.height, height: sourceDimensions.width)
            : sourceDimensions
        return dimensions
    }
}

public enum FrameExportTimestamp {
    public static func clamped(_ seconds: TimeInterval, duration: TimeInterval) throws -> TimeInterval {
        guard seconds.isFinite else { throw FrameExportValidationError.invalidTimestamp }
        guard duration.isFinite, duration > 0 else { throw FrameExportValidationError.invalidDuration }
        return min(max(seconds, 0), duration)
    }

    public static func ffmpegSeconds(_ seconds: TimeInterval) -> String {
        TimeFormatting.ffmpegSeconds(seconds)
    }

    public static func displayTime(_ seconds: TimeInterval) -> String {
        let clamped = max(seconds, 0)
        let totalMilliseconds = Int((clamped * 1000).rounded())
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds % 3_600_000) / 60_000
        let secs = (totalMilliseconds % 60_000) / 1000
        let millis = totalMilliseconds % 1000
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, secs, millis)
    }

    public static func filenameLabel(_ seconds: TimeInterval) -> String {
        displayTime(seconds)
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }
}

public enum FrameExportValidationError: LocalizedError, Equatable, Sendable {
    case missingVideoStream
    case invalidTimestamp
    case timestampBeforeZero
    case timestampBeyondDuration
    case invalidDuration
    case invalidJPEGQuality
    case invalidDimensions
    case wrongFormat(expected: FrameImageFormat, actual: FrameImageFormat?)
    case wrongDimensions(expected: VideoDimensions, actual: VideoDimensions)

    public var errorDescription: String? {
        switch self {
        case .missingVideoStream:
            "Input contains no video stream."
        case .invalidTimestamp:
            "Current playback time is invalid."
        case .timestampBeforeZero:
            "Current playback time is before the start of the video."
        case .timestampBeyondDuration:
            "Current playback time is beyond the end of the video."
        case .invalidDuration:
            "The source video duration is unavailable."
        case .invalidJPEGQuality:
            "JPEG quality must be between 2 and 31."
        case .invalidDimensions:
            "Frame image dimensions are invalid."
        case .wrongFormat(let expected, let actual):
            "Exported image format is \(actual?.title ?? "unknown"), expected \(expected.title)."
        case .wrongDimensions(let expected, let actual):
            "Exported image dimensions are \(actual.width)x\(actual.height), expected \(expected.width)x\(expected.height)."
        }
    }
}

extension OutputFilename {
    public static func frameName(for inputURL: URL, timestamp: TimeInterval, format: FrameImageFormat) -> String {
        let base = safeFrameBaseName(inputURL.deletingPathExtension().lastPathComponent)
        return "\(base)-frame-\(FrameExportTimestamp.filenameLabel(timestamp)).\(format.fileExtension)"
    }

    private static func safeFrameBaseName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let replaced = name.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "-"
        }.joined()
        let collapsed = replaced.split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: ".-_"))
        return trimmed.isEmpty ? "frame" : trimmed
    }
}
