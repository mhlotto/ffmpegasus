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

public enum FrameIntervalPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case every1
    case every2
    case every5
    case every10
    case every30
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .every1: "Every 1 second"
        case .every2: "Every 2 seconds"
        case .every5: "Every 5 seconds"
        case .every10: "Every 10 seconds"
        case .every30: "Every 30 seconds"
        case .custom: "Custom"
        }
    }

    public var seconds: Double? {
        switch self {
        case .every1: 1
        case .every2: 2
        case .every5: 5
        case .every10: 10
        case .every30: 30
        case .custom: nil
        }
    }
}

public struct FrameInterval: Equatable, Codable, Sendable {
    public static let validRange = 0.1...3600.0
    public let seconds: Double

    public init(seconds: Double) throws {
        guard seconds.isFinite, Self.validRange.contains(seconds) else {
            throw FrameExportValidationError.invalidInterval
        }
        self.seconds = seconds
    }

    public static func parse(_ value: String) -> FrameInterval? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let seconds = Double(trimmed) else { return nil }
        return try? FrameInterval(seconds: seconds)
    }
}

public enum FrameExportRangeMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case entireVideo
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .entireVideo: "Entire Video"
        case .custom: "Custom Range"
        }
    }
}

public struct FrameExportRange: Equatable, Codable, Sendable {
    public let startSeconds: Double
    public let endSeconds: Double

    public init(startSeconds: Double, endSeconds: Double, sourceDuration: TimeInterval) throws {
        guard startSeconds.isFinite, endSeconds.isFinite else {
            throw FrameExportValidationError.invalidRange
        }
        guard sourceDuration.isFinite, sourceDuration > 0 else {
            throw FrameExportValidationError.invalidDuration
        }
        guard startSeconds >= 0 else {
            throw FrameExportValidationError.timestampBeforeZero
        }
        guard endSeconds <= sourceDuration else {
            throw FrameExportValidationError.timestampBeyondDuration
        }
        guard endSeconds > startSeconds else {
            throw FrameExportValidationError.invalidRange
        }
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
    }

    public static func entireVideo(duration: TimeInterval) throws -> FrameExportRange {
        try FrameExportRange(startSeconds: 0, endSeconds: duration, sourceDuration: duration)
    }

    public var duration: TimeInterval {
        endSeconds - startSeconds
    }

    public func estimatedImageCount(interval: FrameInterval) throws -> Int {
        guard duration.isFinite, interval.seconds.isFinite, duration >= 0, interval.seconds > 0 else {
            throw FrameExportValidationError.invalidRange
        }
        let epsilon = 1e-9
        let intervals = floor((duration + epsilon) / interval.seconds)
        let count = Int(intervals) + 1
        guard count > 0 else {
            throw FrameExportValidationError.noScheduledFrames
        }
        return count
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

public struct IntervalFrameExportRequest: Equatable, Sendable {
    public let inputURL: URL
    public let outputDirectoryURL: URL
    public let sourceDuration: TimeInterval
    public let sourceDimensions: VideoDimensions
    public let sourceRotationDegrees: Int?
    public let hasVideoStream: Bool
    public let interval: FrameInterval
    public let range: FrameExportRange
    public let format: FrameImageFormat
    public let jpegQuality: JPEGQuality?
    public let replaceExisting: Bool
    public let countTolerance: Int

    public init(
        inputURL: URL,
        outputDirectoryURL: URL,
        sourceDuration: TimeInterval,
        sourceDimensions: VideoDimensions,
        sourceRotationDegrees: Int?,
        hasVideoStream: Bool,
        interval: FrameInterval,
        range: FrameExportRange,
        format: FrameImageFormat,
        jpegQuality: JPEGQuality?,
        replaceExisting: Bool = false,
        countTolerance: Int = 1
    ) {
        self.inputURL = inputURL
        self.outputDirectoryURL = outputDirectoryURL
        self.sourceDuration = sourceDuration
        self.sourceDimensions = sourceDimensions
        self.sourceRotationDegrees = sourceRotationDegrees
        self.hasVideoStream = hasVideoStream
        self.interval = interval
        self.range = range
        self.format = format
        self.jpegQuality = jpegQuality
        self.replaceExisting = replaceExisting
        self.countTolerance = countTolerance
    }

    public func validate() throws {
        guard hasVideoStream else { throw FrameExportValidationError.missingVideoStream }
        guard sourceDuration.isFinite, sourceDuration > 0 else { throw FrameExportValidationError.invalidDuration }
        guard sourceDimensions.width > 0, sourceDimensions.height > 0 else { throw FrameExportValidationError.invalidDimensions }
        _ = try range.estimatedImageCount(interval: interval)
        guard countTolerance >= 0 else { throw FrameExportValidationError.invalidRange }
        if format == .jpeg {
            guard jpegQuality != nil else { throw FrameExportValidationError.invalidJPEGQuality }
        }
    }

    public func expectedDimensions() throws -> VideoDimensions {
        try FrameExportRequest(
            inputURL: inputURL,
            outputURL: outputDirectoryURL.appendingPathComponent("frame.\(format.fileExtension)"),
            timestampSeconds: range.startSeconds,
            sourceDuration: sourceDuration,
            sourceDimensions: sourceDimensions,
            sourceRotationDegrees: sourceRotationDegrees,
            hasVideoStream: hasVideoStream,
            format: format,
            jpegQuality: jpegQuality
        ).expectedDimensions()
    }

    public var expectedImageCount: Int {
        (try? range.estimatedImageCount(interval: interval)) ?? 0
    }

    public var outputPrefix: String {
        "\(OutputFilename.safeFrameBaseName(inputURL.deletingPathExtension().lastPathComponent))-frame-"
    }

    public var outputPattern: URL {
        outputDirectoryURL.appendingPathComponent("\(outputPrefix)%06d.\(format.fileExtension)")
    }

    public func outputURL(forSequenceNumber number: Int) -> URL {
        outputDirectoryURL.appendingPathComponent("\(outputPrefix)\(String(format: "%06d", number)).\(format.fileExtension)")
    }

    public func matchesGeneratedFrameName(_ filename: String) -> Bool {
        guard filename.hasPrefix(outputPrefix),
              filename.hasSuffix(".\(format.fileExtension)") else {
            return false
        }
        let start = filename.index(filename.startIndex, offsetBy: outputPrefix.count)
        let end = filename.index(filename.endIndex, offsetBy: -format.fileExtension.count - 1)
        let digits = filename[start..<end]
        return digits.count == 6 && digits.allSatisfy(\.isNumber)
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

    public static func compactSeconds(_ seconds: TimeInterval) -> String {
        let formatted = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), seconds)
        let trimmedZeros = formatted.replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
        let trimmedDot = trimmedZeros.replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
        return trimmedDot.isEmpty ? "0" : trimmedDot
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
    case invalidInterval
    case invalidRange
    case noScheduledFrames
    case matchingFilesExist(Int)
    case noImagesCreated
    case missingSequenceNumber(Int)
    case emptyImageFile(String)
    case imageCountMismatch(expected: Int, actual: Int, tolerance: Int)
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
        case .invalidInterval:
            "Frame interval must be between 0.1 and 3600 seconds."
        case .invalidRange:
            "Frame export range is invalid."
        case .noScheduledFrames:
            "The selected range contains no frame export timestamp."
        case .matchingFilesExist(let count):
            "\(count) matching frame files already exist in the selected folder."
        case .noImagesCreated:
            "No frame images were created."
        case .missingSequenceNumber(let number):
            "Frame export is missing sequence number \(number)."
        case .emptyImageFile(let path):
            "Exported frame image is empty: \(path)"
        case .imageCountMismatch(let expected, let actual, let tolerance):
            "Exported \(actual) images, expected about \(expected) images with tolerance \(tolerance)."
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

    public static func intervalFramePattern(for inputURL: URL, format: FrameImageFormat) -> String {
        "\(safeFrameBaseName(inputURL.deletingPathExtension().lastPathComponent))-frame-%06d.\(format.fileExtension)"
    }

    public static func safeFrameBaseName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let replaced = name.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "-"
        }.joined()
        let collapsed = replaced.split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: ".-_"))
        return trimmed.isEmpty ? "frame" : trimmed
    }
}
