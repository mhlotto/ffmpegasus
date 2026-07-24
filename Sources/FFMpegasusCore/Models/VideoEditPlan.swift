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
    public let crop: CropConfiguration?
    public let resize: ResizeConfiguration?
    public let compression: CompressionConfiguration?
    public let speed: VideoSpeed?
    public let audioMode: ExportAudioMode
    public let exportProfile: ExportProfile

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
        crop: CropConfiguration? = nil,
        resize: ResizeConfiguration?,
        compression: CompressionConfiguration?,
        speed: VideoSpeed? = nil,
        audioMode: ExportAudioMode,
        exportProfile: ExportProfile = .mp4H264
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
        self.crop = crop
        self.resize = resize
        self.compression = compression
        self.speed = speed
        self.audioMode = audioMode
        self.exportProfile = exportProfile
    }

    public var hasSelectedChanges: Bool {
        trim != nil ||
            (transform?.hasTransformation == true) ||
            crop != nil ||
            resize != nil ||
            compression != nil ||
            speed != nil ||
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
        if exportProfile.forcesReencode { return .reencode }
        if trim?.executionMode == .accurate { return .reencode }
        if transform?.hasTransformation == true { return .reencode }
        if crop != nil { return .reencode }
        if resize != nil { return .reencode }
        if compression != nil { return .reencode }
        if speed != nil { return .reencode }
        return .streamCopy
    }

    public func outputDuration() throws -> TimeInterval {
        let duration = try trimPlan().outputDuration
        guard let speed else { return duration }
        return try speed.expectedDuration(sourceDuration: duration)
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

    public func dimensionsAfterCrop() throws -> VideoDimensions {
        let transformed = try dimensionsAfterTransform()
        guard let crop else { return transformed }
        return try crop.resolvedRectangle(sourceDimensions: transformed).dimensions
    }

    public func outputDimensions() throws -> VideoDimensions {
        let cropped = try dimensionsAfterCrop()
        guard let resize else { return cropped }
        guard let requestedMaxHeight = try resize.resolution.maxHeight(customHeight: resize.customHeight) else {
            return cropped
        }
        if resize.resolution == .custom, requestedMaxHeight > cropped.height {
            throw CompressionValidationError.customHeightExceedsSource
        }
        guard requestedMaxHeight < cropped.height else { return cropped }
        let outputHeight = min(requestedMaxHeight, cropped.height).makeEvenDownForTransform()
        let scaledWidth = Double(cropped.width) * Double(outputHeight) / Double(cropped.height)
        return VideoDimensions(width: Int(scaledWidth.rounded()).makeEvenNearestForScale(), height: outputHeight)
    }

    public func filterChain() throws -> String? {
        var filters = transform?.filterComponents ?? []
        if let crop {
            filters.append(try crop.resolvedRectangle(sourceDimensions: dimensionsAfterTransform()).filter)
        }
        if let scaleFilter = try scaleFilter() {
            filters.append(scaleFilter)
        }
        if let speed {
            filters.append(speed.videoFilter())
        }
        guard !filters.isEmpty else { return nil }
        return filters.joined(separator: ",")
    }

    public func scaleFilter() throws -> String? {
        guard let resize,
              let requestedMaxHeight = try resize.resolution.maxHeight(customHeight: resize.customHeight),
              requestedMaxHeight < (try dimensionsAfterCrop()).height else {
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
        if let crop {
            _ = try crop.resolvedRectangle(sourceDimensions: dimensionsAfterTransform())
        }
        if let compression {
            _ = try compression.settings()
        }
        if let speed, speed.isNoChange {
            throw VideoSpeedValidationError.noSpeedChange
        }
        _ = try outputDuration()
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
    public static func editedName(for inputURL: URL, profile: ExportProfile = .mp4H264) -> String {
        let base = inputURL.deletingPathExtension().lastPathComponent
        return "\(base)-edited.\(profile.fileExtension)"
    }
}
