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

    public init(inputURL: URL, outputURL: URL, sourceDuration: TimeInterval, removeStartSeconds: TimeInterval, removeEndSeconds: TimeInterval, mode: EditingMode, method: EditingMethod) {
        self.inputURL = inputURL
        self.outputURL = outputURL
        self.sourceDuration = sourceDuration
        self.removeStartSeconds = removeStartSeconds
        self.removeEndSeconds = removeEndSeconds
        self.mode = mode
        self.method = method
    }

    public func trimPlan() throws -> TrimPlan {
        try TrimPlan(
            sourceDuration: sourceDuration,
            removeStartSeconds: removeStartSeconds,
            removeEndSeconds: removeEndSeconds
        )
    }
}

public enum EditingMethod: String, CaseIterable, Identifiable, Sendable {
    case streamCopy

    public var id: String { rawValue }
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
