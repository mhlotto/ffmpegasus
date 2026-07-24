import Foundation

public enum EncoderPreset: String, CaseIterable, Sendable {
    case ultrafast
    case veryfast
    case fast
    case medium
    case slow
    case slower
}

public enum CompressionQuality: String, CaseIterable, Identifiable, Sendable {
    case highQuality
    case balanced
    case smallFile
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .highQuality: "High Quality"
        case .balanced: "Balanced"
        case .smallFile: "Small File"
        case .custom: "Custom"
        }
    }

    public func settings(customCRF: Int, customPreset: EncoderPreset) throws -> CompressionQualitySettings {
        switch self {
        case .highQuality:
            try CompressionQualitySettings(crf: 20, preset: .medium)
        case .balanced:
            try CompressionQualitySettings(crf: 24, preset: .medium)
        case .smallFile:
            try CompressionQualitySettings(crf: 28, preset: .slow)
        case .custom:
            try CompressionQualitySettings(crf: customCRF, preset: customPreset)
        }
    }
}

public struct CompressionQualitySettings: Equatable, Sendable {
    public let crf: Int
    public let preset: EncoderPreset

    public init(crf: Int, preset: EncoderPreset) throws {
        guard (16...35).contains(crf) else {
            throw CompressionValidationError.invalidCRF
        }
        self.crf = crf
        self.preset = preset
    }
}

public enum OutputResolution: String, CaseIterable, Identifiable, Sendable {
    case original
    case p1080
    case p720
    case p480
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .original: "Original"
        case .p1080: "1080p"
        case .p720: "720p"
        case .p480: "480p"
        case .custom: "Custom"
        }
    }

    public func maxHeight(customHeight: Int?) throws -> Int? {
        switch self {
        case .original:
            return nil
        case .p1080:
            return 1080
        case .p720:
            return 720
        case .p480:
            return 480
        case .custom:
            guard let customHeight else { throw CompressionValidationError.invalidCustomHeight }
            guard customHeight >= 144 else { throw CompressionValidationError.invalidCustomHeight }
            return customHeight
        }
    }
}

public enum CompressionAudioMode: String, CaseIterable, Identifiable, Sendable {
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

public struct VideoDimensions: Equatable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct CompressionRequest: Equatable, Sendable {
    public let inputURL: URL
    public let outputURL: URL
    public let sourceDuration: TimeInterval
    public let sourceDimensions: VideoDimensions
    public let hasVideoStream: Bool
    public let hasAudioStream: Bool
    public let quality: CompressionQuality
    public let customCRF: Int
    public let encoderPreset: EncoderPreset
    public let resolution: OutputResolution
    public let customHeight: Int?
    public let audioMode: CompressionAudioMode
    public let exportProfile: ExportProfile

    public init(
        inputURL: URL,
        outputURL: URL,
        sourceDuration: TimeInterval,
        sourceDimensions: VideoDimensions,
        hasVideoStream: Bool,
        hasAudioStream: Bool,
        quality: CompressionQuality,
        customCRF: Int,
        encoderPreset: EncoderPreset,
        resolution: OutputResolution,
        customHeight: Int?,
        audioMode: CompressionAudioMode,
        exportProfile: ExportProfile = .mp4H264
    ) {
        self.inputURL = inputURL
        self.outputURL = outputURL
        self.sourceDuration = sourceDuration
        self.sourceDimensions = sourceDimensions
        self.hasVideoStream = hasVideoStream
        self.hasAudioStream = hasAudioStream
        self.quality = quality
        self.customCRF = customCRF
        self.encoderPreset = encoderPreset
        self.resolution = resolution
        self.customHeight = customHeight
        self.audioMode = audioMode
        self.exportProfile = exportProfile
    }

    public func qualitySettings() throws -> CompressionQualitySettings {
        try quality.settings(customCRF: customCRF, customPreset: encoderPreset)
    }

    public func outputDimensions() throws -> VideoDimensions {
        guard hasVideoStream else { throw CompressionValidationError.missingVideoStream }
        guard sourceDimensions.width > 0, sourceDimensions.height > 0 else {
            throw CompressionValidationError.invalidSourceDimensions
        }

        guard let requestedMaxHeight = try resolution.maxHeight(customHeight: customHeight) else {
            return VideoDimensions(width: sourceDimensions.width.makeEvenDown(), height: sourceDimensions.height.makeEvenDown())
        }

        if resolution == .custom, requestedMaxHeight > sourceDimensions.height {
            throw CompressionValidationError.customHeightExceedsSource
        }

        let outputHeight = min(requestedMaxHeight, sourceDimensions.height).makeEvenDown()
        let scaledWidth = Double(sourceDimensions.width) * Double(outputHeight) / Double(sourceDimensions.height)
        return VideoDimensions(width: Int(scaledWidth.rounded()).makeEvenDown(), height: outputHeight)
    }

    public func scaleFilter() throws -> String? {
        guard let requestedMaxHeight = try resolution.maxHeight(customHeight: customHeight),
              requestedMaxHeight < sourceDimensions.height else {
            return nil
        }
        return "scale=-2:min(\(requestedMaxHeight)\\,ih)"
    }
}

public enum CompressionValidationError: LocalizedError, Equatable, Sendable {
    case invalidCRF
    case invalidCustomHeight
    case customHeightExceedsSource
    case invalidSourceDimensions
    case missingVideoStream
    case missingLibx264
    case wrongCodec(String?)
    case wrongDimensions(expected: VideoDimensions, actual: VideoDimensions)
    case oddDimensions(VideoDimensions)
    case unexpectedAudio
    case missingExpectedAudio
    case durationMismatch

    public var errorDescription: String? {
        switch self {
        case .invalidCRF:
            "CRF must be between 16 and 35."
        case .invalidCustomHeight:
            "Custom height must be an integer of at least 144 pixels."
        case .customHeightExceedsSource:
            "Custom height cannot exceed the source height."
        case .invalidSourceDimensions:
            "Source video dimensions are unavailable."
        case .missingVideoStream:
            "Input contains no video stream."
        case .missingLibx264:
            "This FFmpeg installation does not include the libx264 encoder."
        case .wrongCodec(let codec):
            "Compressed output is not H.264. Detected codec: \(codec ?? "unknown")."
        case .wrongDimensions(let expected, let actual):
            "Compressed output dimensions are \(actual.width)x\(actual.height), expected \(expected.width)x\(expected.height)."
        case .oddDimensions(let dimensions):
            "Compressed output dimensions must be even. Got \(dimensions.width)x\(dimensions.height)."
        case .unexpectedAudio:
            "Compressed output contains audio, but audio removal was requested."
        case .missingExpectedAudio:
            "Compressed output is missing expected audio."
        case .durationMismatch:
            "Compressed output duration differs too much from the source."
        }
    }
}

private extension Int {
    func makeEvenDown() -> Int {
        let even = self - (self % 2)
        return Swift.max(even, 2)
    }
}
