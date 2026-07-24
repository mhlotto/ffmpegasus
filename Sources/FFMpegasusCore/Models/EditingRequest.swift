import Foundation

public enum EditingMode: String, CaseIterable, Identifiable, Sendable {
    case trimStart
    case trimEnd
    case trimBoth

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .trimStart: "Remove first seconds"
        case .trimEnd: "Remove last seconds"
        case .trimBoth: "Remove first and last seconds"
        }
    }
}

public struct EditingRequest: Equatable, Sendable {
    public let inputURL: URL
    public let outputURL: URL
    public let sourceDuration: TimeInterval
    public let removeStartSeconds: TimeInterval
    public let removeEndSeconds: TimeInterval
    public let mode: EditingMode
    public let method: EditingMethod
    public let trimExecutionMode: TrimExecutionMode
    public let hasVideoStream: Bool
    public let hasAudioStream: Bool
    public let exportProfile: ExportProfile

    public init(
        inputURL: URL,
        outputURL: URL,
        sourceDuration: TimeInterval,
        removeStartSeconds: TimeInterval,
        removeEndSeconds: TimeInterval,
        mode: EditingMode,
        method: EditingMethod,
        trimExecutionMode: TrimExecutionMode = .fast,
        hasVideoStream: Bool = true,
        hasAudioStream: Bool = true,
        exportProfile: ExportProfile = .mp4H264
    ) {
        self.inputURL = inputURL
        self.outputURL = outputURL
        self.sourceDuration = sourceDuration
        self.removeStartSeconds = removeStartSeconds
        self.removeEndSeconds = removeEndSeconds
        self.mode = mode
        self.method = method
        self.trimExecutionMode = trimExecutionMode
        self.hasVideoStream = hasVideoStream
        self.hasAudioStream = hasAudioStream
        self.exportProfile = exportProfile
    }

    public func trimPlan() throws -> TrimPlan {
        try TrimPlan(
            sourceDuration: sourceDuration,
            removeStartSeconds: removeStartSeconds,
            removeEndSeconds: removeEndSeconds
        )
    }

    public var effectiveTrimExecutionMode: TrimExecutionMode {
        exportProfile == .mp4H264 ? trimExecutionMode : .accurate
    }
}

public enum EditingMethod: String, CaseIterable, Identifiable, Sendable {
    case streamCopy

    public var id: String { rawValue }
}

public enum TrimExecutionMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case fast
    case accurate

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fast: "Fast"
        case .accurate: "Accurate"
        }
    }

    public var description: String {
        switch self {
        case .fast:
            "Very quick and lossless, but cuts may move to nearby keyframes."
        case .accurate:
            "Re-encodes the video for more precise start and end times."
        }
    }
}

public struct TrimPlan: Equatable, Sendable {
    public let startTime: TimeInterval
    public let outputDuration: TimeInterval

    public init(sourceDuration: TimeInterval, removeStartSeconds: TimeInterval, removeEndSeconds: TimeInterval) throws {
        guard sourceDuration > 0 else {
            throw EditingValidationError.invalidSourceDuration
        }
        guard removeStartSeconds >= 0, removeEndSeconds >= 0 else {
            throw EditingValidationError.negativeTrimValue
        }

        let outputDuration = sourceDuration - removeStartSeconds - removeEndSeconds
        guard outputDuration > 0 else {
            throw EditingValidationError.emptyResult
        }

        self.startTime = removeStartSeconds
        self.outputDuration = outputDuration
    }
}

public enum EditingValidationError: LocalizedError, Equatable, Sendable {
    case invalidSourceDuration
    case negativeTrimValue
    case emptyResult

    public var errorDescription: String? {
        switch self {
        case .invalidSourceDuration:
            "The source video duration is unavailable."
        case .negativeTrimValue:
            "Trim values cannot be negative."
        case .emptyResult:
            "The resulting video duration must be greater than zero."
        }
    }
}

public enum TrimSecondsParser {
    public static func parse(_ value: String) -> TimeInterval? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let number = TimeInterval(trimmed),
              number.isFinite,
              number >= 0 else {
            return nil
        }
        return number
    }
}

public enum OutputFilename {
    public static func mutedName(for inputURL: URL) -> String {
        let base = inputURL.deletingPathExtension().lastPathComponent
        let ext = inputURL.pathExtension.isEmpty ? "mp4" : inputURL.pathExtension
        return "\(base)-muted.\(ext)"
    }

    public static func compressedName(for inputURL: URL, profile: ExportProfile = .mp4H264) -> String {
        let base = inputURL.deletingPathExtension().lastPathComponent
        return "\(base)-compressed.\(profile.fileExtension)"
    }

    public static func trimmedName(for inputURL: URL, mode: TrimExecutionMode, profile: ExportProfile = .mp4H264) -> String {
        let base = inputURL.deletingPathExtension().lastPathComponent
        if mode == .fast, profile == .mp4H264 {
            let ext = inputURL.pathExtension.isEmpty ? "mp4" : inputURL.pathExtension
            return "\(base)-trimmed.\(ext)"
        }
        return "\(base)-trimmed-accurate.\(profile.fileExtension)"
    }
}
