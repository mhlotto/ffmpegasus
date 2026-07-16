import Foundation

public enum ExportExecutionStrategy: String, Sendable {
    case streamCopy
    case reencode

    public var title: String {
        switch self {
        case .streamCopy: "Stream copy"
        case .reencode: "Re-encode"
        }
    }
}

public enum ExportAudioMode: String, CaseIterable, Identifiable, Sendable {
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

public struct TrimConfiguration: Equatable, Sendable {
    public let mode: EditingMode
    public let removeStartSeconds: TimeInterval
    public let removeEndSeconds: TimeInterval
    public let executionMode: TrimExecutionMode

    public init(mode: EditingMode, removeStartSeconds: TimeInterval, removeEndSeconds: TimeInterval, executionMode: TrimExecutionMode) {
        self.mode = mode
        self.removeStartSeconds = removeStartSeconds
        self.removeEndSeconds = removeEndSeconds
        self.executionMode = executionMode
    }
}

public struct VideoTransformConfiguration: Equatable, Sendable {
    public let rotation: VideoRotation
    public let flipHorizontal: Bool
    public let flipVertical: Bool

    public init(rotation: VideoRotation, flipHorizontal: Bool, flipVertical: Bool) {
        self.rotation = rotation
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
    }

    public var hasTransformation: Bool {
        rotation != .none || flipHorizontal || flipVertical
    }

    public var filterComponents: [String] {
        var filters = rotation.filterComponents
        if flipHorizontal {
            filters.append("hflip")
        }
        if flipVertical {
            filters.append("vflip")
        }
        return filters
    }
}

public struct ResizeConfiguration: Equatable, Sendable {
    public let resolution: OutputResolution
    public let customHeight: Int?

    public init(resolution: OutputResolution, customHeight: Int?) {
        self.resolution = resolution
        self.customHeight = customHeight
    }
}

public struct CompressionConfiguration: Equatable, Sendable {
    public let quality: CompressionQuality
    public let customCRF: Int
    public let encoderPreset: EncoderPreset

    public init(quality: CompressionQuality, customCRF: Int, encoderPreset: EncoderPreset) {
        self.quality = quality
        self.customCRF = customCRF
        self.encoderPreset = encoderPreset
    }

    public func settings() throws -> CompressionQualitySettings {
        try quality.settings(customCRF: customCRF, customPreset: encoderPreset)
    }
}

public struct VideoEditPlan: Equatable, Sendable {
    public let inputURL: URL
    public let outputURL: URL
    public let sourceDuration: TimeInterval
    public let sourceDimensions: VideoDimensions
    public let sourceRotationDegrees: Int?
    public let hasVideoStream: Bool
    public let hasAudioStream: Bool
    public let trim: TrimConfiguration?
    public let transform: VideoTransformConfiguration?
    public let resize: ResizeConfiguration?
    public let compression: CompressionConfiguration?
    public let audioMode: ExportAudioMode

    public init(
        inputURL: URL,
        outputURL: URL,
        sourceDuration: TimeInterval,
        sourceDimensions: VideoDimensions,
        sourceRotationDegrees: Int?,
        hasVideoStream: Bool,
        hasAudioStream: Bool,
        trim: TrimConfiguration?,
        transform: VideoTransformConfiguration?,
        resize: ResizeConfiguration?,
        compression: CompressionConfiguration?,
        audioMode: ExportAudioMode
    ) {
        self.inputURL = inputURL
        self.outputURL = outputURL
        self.sourceDuration = sourceDuration
        self.sourceDimensions = sourceDimensions
        self.sourceRotationDegrees = sourceRotationDegrees
        self.hasVideoStream = hasVideoStream
        self.hasAudioStream = hasAudioStream
        self.trim = trim
        self.transform = transform
        self.resize = resize
        self.compression = compression
        self.audioMode = audioMode
    }

    public var hasSelectedChanges: Bool {
        trim != nil ||
            (transform?.hasTransformation == true) ||
            resize != nil ||
            compression != nil ||
            audioMode == .remove
    }

    public func trimPlan() throws -> TrimPlan {
        guard let trim else {
            return try TrimPlan(sourceDuration: sourceDuration, removeStartSeconds: 0, removeEndSeconds: 0)
        }
        return try TrimPlan(
            sourceDuration: sourceDuration,
            removeStartSeconds: trim.removeStartSeconds,
            removeEndSeconds: trim.removeEndSeconds
        )
    }

    public func executionStrategy() throws -> ExportExecutionStrategy {
        try validate()
        if trim?.executionMode == .accurate { return .reencode }
        if transform?.hasTransformation == true { return .reencode }
        if resize != nil { return .reencode }
        if compression != nil { return .reencode }
        return .streamCopy
    }

    public func qualitySettings() throws -> CompressionQualitySettings {
        if let compression {
            return try compression.settings()
        }
        return try CompressionQualitySettings(crf: 20, preset: .medium)
    }

    public func normalizedSourceDimensions() throws -> VideoDimensions {
        guard hasVideoStream else { throw VideoEditPlanValidationError.missingVideoStream }
        guard sourceDimensions.width > 0, sourceDimensions.height > 0 else {
            throw VideoEditPlanValidationError.invalidSourceDimensions
        }
        let normalizedRotation = (sourceRotationDegrees ?? 0).normalizedRotationDegrees
        let dimensions = normalizedRotation == 90 || normalizedRotation == 270
            ? VideoDimensions(width: sourceDimensions.height, height: sourceDimensions.width)
            : sourceDimensions
        return VideoDimensions(width: dimensions.width.makeEvenDownForTransform(), height: dimensions.height.makeEvenDownForTransform())
    }

    public func dimensionsAfterTransform() throws -> VideoDimensions {
        let normalized = try normalizedSourceDimensions()
        guard let transform, transform.rotation.swapsDimensions else {
            return normalized
        }
        return VideoDimensions(width: normalized.height, height: normalized.width)
    }

    public func outputDimensions() throws -> VideoDimensions {
        let transformed = try dimensionsAfterTransform()
        guard let resize else { return transformed }
        guard let requestedMaxHeight = try resize.resolution.maxHeight(customHeight: resize.customHeight) else {
            return transformed
        }
        if resize.resolution == .custom, requestedMaxHeight > transformed.height {
            throw CompressionValidationError.customHeightExceedsSource
        }
        guard requestedMaxHeight < transformed.height else { return transformed }
        let outputHeight = min(requestedMaxHeight, transformed.height).makeEvenDownForTransform()
        let scaledWidth = Double(transformed.width) * Double(outputHeight) / Double(transformed.height)
        return VideoDimensions(width: Int(scaledWidth.rounded()).makeEvenNearestForScale(), height: outputHeight)
    }

    public func filterChain() throws -> String? {
        var filters = transform?.filterComponents ?? []
        if let scaleFilter = try scaleFilter() {
            filters.append(scaleFilter)
        }
        guard !filters.isEmpty else { return nil }
        return filters.joined(separator: ",")
    }

    public func scaleFilter() throws -> String? {
        guard let resize,
              let requestedMaxHeight = try resize.resolution.maxHeight(customHeight: resize.customHeight),
              requestedMaxHeight < (try dimensionsAfterTransform()).height else {
            return nil
        }
        return "scale=-2:min(\(requestedMaxHeight)\\,ih)"
    }

    public func validate() throws {
        guard hasSelectedChanges else {
            throw VideoEditPlanValidationError.noChangesSelected
        }
        guard hasVideoStream else {
            throw VideoEditPlanValidationError.missingVideoStream
        }
        _ = try trimPlan()
        _ = try outputDimensions()
        if let compression {
            _ = try compression.settings()
        }
    }
}

private extension Int {
    func makeEvenNearestForScale() -> Int {
        if isMultiple(of: 2) {
            return Swift.max(self, 2)
        }
        return Swift.max(self + 1, 2)
    }
}

public enum VideoEditPlanValidationError: LocalizedError, Equatable, Sendable {
    case noChangesSelected
    case missingVideoStream
    case invalidSourceDimensions

    public var errorDescription: String? {
        switch self {
        case .noChangesSelected:
            "Select at least one change."
        case .missingVideoStream:
            "Input contains no video stream."
        case .invalidSourceDimensions:
            "Source video dimensions are unavailable."
        }
    }
}

extension OutputFilename {
    public static func editedName(for inputURL: URL) -> String {
        let base = inputURL.deletingPathExtension().lastPathComponent
        return "\(base)-edited.mp4"
    }
}
