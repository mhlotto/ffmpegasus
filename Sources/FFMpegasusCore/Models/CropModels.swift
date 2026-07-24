import Foundation

public enum CropMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case aspectRatio
    case customRectangle

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .aspectRatio: "Aspect Ratio"
        case .customRectangle: "Custom Rectangle"
        }
    }
}

public enum CropAspectRatioPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case square
    case fourThree
    case threeFour
    case sixteenNine
    case nineSixteen
    case twentyOneNine
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .square: "1:1"
        case .fourThree: "4:3"
        case .threeFour: "3:4"
        case .sixteenNine: "16:9"
        case .nineSixteen: "9:16"
        case .twentyOneNine: "21:9"
        case .custom: "Custom Ratio"
        }
    }

    public var ratioComponents: (width: Double, height: Double)? {
        switch self {
        case .square: (1, 1)
        case .fourThree: (4, 3)
        case .threeFour: (3, 4)
        case .sixteenNine: (16, 9)
        case .nineSixteen: (9, 16)
        case .twentyOneNine: (21, 9)
        case .custom: nil
        }
    }
}

public struct CropAspectRatio: Equatable, Codable, Sendable {
    public static let validComponentRange = 0.000_001...10_000.0
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) throws {
        guard width.isFinite, height.isFinite,
              Self.validComponentRange.contains(width),
              Self.validComponentRange.contains(height) else {
            throw CropValidationError.invalidAspectRatio
        }
        self.width = width
        self.height = height
    }

    public var value: Double { width / height }

    public static func parse(width: String, height: String) -> CropAspectRatio? {
        let widthValue = Double(width.trimmingCharacters(in: .whitespacesAndNewlines))
        let heightValue = Double(height.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let widthValue, let heightValue else { return nil }
        return try? CropAspectRatio(width: widthValue, height: heightValue)
    }
}

public enum CropPositionPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case center
    case top
    case bottom
    case left
    case right
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .center: "Center"
        case .top: "Top"
        case .bottom: "Bottom"
        case .left: "Left"
        case .right: "Right"
        case .topLeft: "Top Left"
        case .topRight: "Top Right"
        case .bottomLeft: "Bottom Left"
        case .bottomRight: "Bottom Right"
        case .custom: "Custom Position"
        }
    }

    public var fractions: (x: Double, y: Double)? {
        switch self {
        case .center: (0.5, 0.5)
        case .top: (0.5, 0)
        case .bottom: (0.5, 1)
        case .left: (0, 0.5)
        case .right: (1, 0.5)
        case .topLeft: (0, 0)
        case .topRight: (1, 0)
        case .bottomLeft: (0, 1)
        case .bottomRight: (1, 1)
        case .custom: nil
        }
    }
}

public struct CropRectangle: Equatable, Codable, Sendable {
    public let width: Int
    public let height: Int
    public let x: Int
    public let y: Int

    public init(width: Int, height: Int, x: Int, y: Int, sourceDimensions: VideoDimensions) throws {
        guard width > 0, height > 0 else { throw CropValidationError.invalidDimensions }
        guard width.isMultiple(of: 2), height.isMultiple(of: 2) else { throw CropValidationError.encoderIncompatibleDimensions(VideoDimensions(width: width, height: height)) }
        guard sourceDimensions.width > 0, sourceDimensions.height > 0 else { throw CropValidationError.invalidSourceDimensions }
        guard width <= sourceDimensions.width, height <= sourceDimensions.height else { throw CropValidationError.cropExceedsSource }
        guard x >= 0, y >= 0 else { throw CropValidationError.invalidOrigin }
        guard x + width <= sourceDimensions.width, y + height <= sourceDimensions.height else { throw CropValidationError.cropOutsideSource }
        self.width = width
        self.height = height
        self.x = x
        self.y = y
    }

    public var dimensions: VideoDimensions {
        VideoDimensions(width: width, height: height)
    }

    public var filter: String {
        "crop=\(width):\(height):\(x):\(y)"
    }
}

public struct CropConfiguration: Equatable, Sendable {
    public let mode: CropMode
    public let aspectRatioPreset: CropAspectRatioPreset
    public let customAspectRatio: CropAspectRatio?
    public let position: CropPositionPreset
    public let customX: Int?
    public let customY: Int?
    public let customWidth: Int?
    public let customHeight: Int?

    public init(
        mode: CropMode,
        aspectRatioPreset: CropAspectRatioPreset,
        customAspectRatio: CropAspectRatio?,
        position: CropPositionPreset,
        customX: Int?,
        customY: Int?,
        customWidth: Int?,
        customHeight: Int?
    ) {
        self.mode = mode
        self.aspectRatioPreset = aspectRatioPreset
        self.customAspectRatio = customAspectRatio
        self.position = position
        self.customX = customX
        self.customY = customY
        self.customWidth = customWidth
        self.customHeight = customHeight
    }

    public func resolvedRectangle(sourceDimensions: VideoDimensions) throws -> CropRectangle {
        switch mode {
        case .aspectRatio:
            return try resolveAspectRatio(sourceDimensions: sourceDimensions)
        case .customRectangle:
            guard let customWidth, let customHeight else { throw CropValidationError.invalidDimensions }
            let x = customX ?? 0
            let y = customY ?? 0
            return try CropRectangle(width: customWidth, height: customHeight, x: x, y: y, sourceDimensions: sourceDimensions)
        }
    }

    private func resolveAspectRatio(sourceDimensions: VideoDimensions) throws -> CropRectangle {
        guard sourceDimensions.width > 0, sourceDimensions.height > 0 else {
            throw CropValidationError.invalidSourceDimensions
        }
        let ratio = try aspectRatio()
        let sourceRatio = Double(sourceDimensions.width) / Double(sourceDimensions.height)
        let rawWidth: Int
        let rawHeight: Int
        if sourceRatio > ratio.value {
            rawHeight = sourceDimensions.height
            rawWidth = Int((Double(rawHeight) * ratio.value).rounded(.down))
        } else {
            rawWidth = sourceDimensions.width
            rawHeight = Int((Double(rawWidth) / ratio.value).rounded(.down))
        }
        let cropWidth = rawWidth.makeEvenDownForCrop()
        let cropHeight = rawHeight.makeEvenDownForCrop()
        let origin = try origin(sourceDimensions: sourceDimensions, cropWidth: cropWidth, cropHeight: cropHeight)
        return try CropRectangle(width: cropWidth, height: cropHeight, x: origin.x, y: origin.y, sourceDimensions: sourceDimensions)
    }

    public func aspectRatio() throws -> CropAspectRatio {
        if aspectRatioPreset == .custom {
            guard let customAspectRatio else { throw CropValidationError.invalidAspectRatio }
            return customAspectRatio
        }
        guard let components = aspectRatioPreset.ratioComponents else {
            throw CropValidationError.invalidAspectRatio
        }
        return try CropAspectRatio(width: components.width, height: components.height)
    }

    private func origin(sourceDimensions: VideoDimensions, cropWidth: Int, cropHeight: Int) throws -> (x: Int, y: Int) {
        if position == .custom {
            guard let customX, let customY else { throw CropValidationError.invalidOrigin }
            return (customX, customY)
        }
        guard let fractions = position.fractions else { throw CropValidationError.invalidOrigin }
        let remainingX = sourceDimensions.width - cropWidth
        let remainingY = sourceDimensions.height - cropHeight
        return (
            Int((Double(remainingX) * fractions.x).rounded()),
            Int((Double(remainingY) * fractions.y).rounded())
        )
    }
}

public struct CropRequest: Equatable, Sendable {
    public let inputURL: URL
    public let outputURL: URL
    public let sourceDuration: TimeInterval
    public let sourceDimensions: VideoDimensions
    public let sourceRotationDegrees: Int?
    public let hasVideoStream: Bool
    public let hasAudioStream: Bool
    public let configuration: CropConfiguration
    public let exportProfile: ExportProfile

    public init(
        inputURL: URL,
        outputURL: URL,
        sourceDuration: TimeInterval,
        sourceDimensions: VideoDimensions,
        sourceRotationDegrees: Int?,
        hasVideoStream: Bool,
        hasAudioStream: Bool,
        configuration: CropConfiguration,
        exportProfile: ExportProfile = .mp4H264
    ) {
        self.inputURL = inputURL
        self.outputURL = outputURL
        self.sourceDuration = sourceDuration
        self.sourceDimensions = sourceDimensions
        self.sourceRotationDegrees = sourceRotationDegrees
        self.hasVideoStream = hasVideoStream
        self.hasAudioStream = hasAudioStream
        self.configuration = configuration
        self.exportProfile = exportProfile
    }

    public func displayDimensions() throws -> VideoDimensions {
        try CropGeometry.displayDimensions(sourceDimensions: sourceDimensions, rotationDegrees: sourceRotationDegrees)
    }

    public func resolvedRectangle() throws -> CropRectangle {
        try configuration.resolvedRectangle(sourceDimensions: displayDimensions())
    }

    public func outputDimensions() throws -> VideoDimensions {
        try resolvedRectangle().dimensions
    }

    public func filterChain() throws -> String {
        try resolvedRectangle().filter
    }

    public func validate() throws {
        guard hasVideoStream else { throw CropValidationError.missingVideoStream }
        guard sourceDuration.isFinite, sourceDuration > 0 else { throw CropValidationError.invalidDuration }
        _ = try resolvedRectangle()
    }
}

public enum CropGeometry {
    public static func displayDimensions(sourceDimensions: VideoDimensions, rotationDegrees: Int?) throws -> VideoDimensions {
        guard sourceDimensions.width > 0, sourceDimensions.height > 0 else {
            throw CropValidationError.invalidSourceDimensions
        }
        let normalizedRotation = (rotationDegrees ?? 0).normalizedRotationDegrees
        let display = normalizedRotation == 90 || normalizedRotation == 270
            ? VideoDimensions(width: sourceDimensions.height, height: sourceDimensions.width)
            : sourceDimensions
        return VideoDimensions(width: display.width.makeEvenDownForCrop(), height: display.height.makeEvenDownForCrop())
    }
}

public enum CropValidationError: LocalizedError, Equatable, Sendable {
    case missingVideoStream
    case invalidDuration
    case invalidSourceDimensions
    case invalidDimensions
    case invalidAspectRatio
    case invalidOrigin
    case cropExceedsSource
    case cropOutsideSource
    case encoderIncompatibleDimensions(VideoDimensions)
    case wrongDimensions(expected: VideoDimensions, actual: VideoDimensions)
    case wrongCodec(String?)
    case unexpectedAudio
    case missingExpectedAudio
    case durationMismatch
    case staleRotationMetadata(Int)

    public var errorDescription: String? {
        switch self {
        case .missingVideoStream:
            "Input contains no video stream."
        case .invalidDuration:
            "Crop source duration is invalid."
        case .invalidSourceDimensions:
            "Source video dimensions are unavailable."
        case .invalidDimensions:
            "Crop width and height must be positive even pixel values."
        case .invalidAspectRatio:
            "Crop aspect ratio must use positive finite values."
        case .invalidOrigin:
            "Crop X and Y must be valid nonnegative pixel offsets."
        case .cropExceedsSource:
            "Crop dimensions exceed the displayed source dimensions."
        case .cropOutsideSource:
            "Crop rectangle extends outside the source video."
        case .encoderIncompatibleDimensions(let dimensions):
            "Crop dimensions must be even for H.264 output. Got \(dimensions.width)x\(dimensions.height)."
        case .wrongDimensions(let expected, let actual):
            "Cropped output dimensions are \(actual.width)x\(actual.height), expected \(expected.width)x\(expected.height)."
        case .wrongCodec(let codec):
            "Cropped output is not H.264. Detected codec: \(codec ?? "unknown")."
        case .unexpectedAudio:
            "Cropped output contains audio, but the source had no audio."
        case .missingExpectedAudio:
            "Cropped output is missing expected audio."
        case .durationMismatch:
            "Cropped output duration differs too much from the source."
        case .staleRotationMetadata(let rotation):
            "Cropped output still has rotation metadata: \(rotation) degrees."
        }
    }
}

extension OutputFilename {
    public static func croppedName(for inputURL: URL, rectangle: CropRectangle? = nil, profile: ExportProfile = .mp4H264) -> String {
        let base = inputURL.deletingPathExtension().lastPathComponent
        if let rectangle {
            return "\(base)-crop-\(rectangle.width)x\(rectangle.height).\(profile.fileExtension)"
        }
        return "\(base)-cropped.\(profile.fileExtension)"
    }
}

private extension Int {
    func makeEvenDownForCrop() -> Int {
        let value = isMultiple(of: 2) ? self : self - 1
        return Swift.max(value, 2)
    }
}
