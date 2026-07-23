import Foundation

public enum GIFFrameRatePreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case fps5
    case fps10
    case fps15
    case fps20
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fps5: "5 fps"
        case .fps10: "10 fps"
        case .fps15: "15 fps"
        case .fps20: "20 fps"
        case .custom: "Custom"
        }
    }

    public var framesPerSecond: Double? {
        switch self {
        case .fps5: 5
        case .fps10: 10
        case .fps15: 15
        case .fps20: 20
        case .custom: nil
        }
    }
}

public struct GIFFrameRate: Equatable, Codable, Sendable {
    public static let validRange = 1.0...30.0
    public let framesPerSecond: Double

    public init(framesPerSecond: Double) throws {
        guard framesPerSecond.isFinite, Self.validRange.contains(framesPerSecond) else {
            throw GIFExportValidationError.invalidFrameRate
        }
        self.framesPerSecond = framesPerSecond
    }

    public static func parse(_ value: String) -> GIFFrameRate? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let fps = Double(trimmed) else { return nil }
        return try? GIFFrameRate(framesPerSecond: fps)
    }
}

public enum GIFSizePreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case original
    case wide1080
    case wide720
    case wide480
    case wide320
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .original: "Original"
        case .wide1080: "1080 px wide"
        case .wide720: "720 px wide"
        case .wide480: "480 px wide"
        case .wide320: "320 px wide"
        case .custom: "Custom width"
        }
    }

    public var width: Int? {
        switch self {
        case .original, .custom: nil
        case .wide1080: 1080
        case .wide720: 720
        case .wide480: 480
        case .wide320: 320
        }
    }
}

public struct GIFWidth: Equatable, Codable, Sendable {
    public static let validRange = 64...1920
    public let pixels: Int

    public init(pixels: Int) throws {
        guard Self.validRange.contains(pixels) else {
            throw GIFExportValidationError.invalidWidth
        }
        self.pixels = pixels
    }

    public static func parse(_ value: String) -> GIFWidth? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pixels = Int(trimmed) else { return nil }
        return try? GIFWidth(pixels: pixels)
    }
}

public enum GIFQualityPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case high
    case balanced
    case smallFile

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .high: "High Quality"
        case .balanced: "Balanced"
        case .smallFile: "Small File"
        }
    }

    public var maxColors: Int {
        switch self {
        case .high: 256
        case .balanced: 192
        case .smallFile: 128
        }
    }

    public var dither: String {
        switch self {
        case .high: "sierra2_4a"
        case .balanced: "bayer:bayer_scale=3"
        case .smallFile: "bayer:bayer_scale=5"
        }
    }
}

public enum GIFLoopMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case forever
    case once

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .forever: "Loop Forever"
        case .once: "Play Once"
        }
    }

    public var ffmpegLoopValue: String {
        switch self {
        case .forever: "0"
        case .once: "-1"
        }
    }
}

public struct GIFExportRequest: Equatable, Sendable {
    public let inputURL: URL
    public let outputURL: URL
    public let sourceDuration: TimeInterval
    public let sourceDimensions: VideoDimensions
    public let sourceRotationDegrees: Int?
    public let hasVideoStream: Bool
    public let range: FrameExportRange
    public let frameRate: GIFFrameRate
    public let sizePreset: GIFSizePreset
    public let customWidth: GIFWidth?
    public let quality: GIFQualityPreset
    public let loopMode: GIFLoopMode
    public let frameCountTolerance: Int
    public let durationTolerance: TimeInterval

    public init(
        inputURL: URL,
        outputURL: URL,
        sourceDuration: TimeInterval,
        sourceDimensions: VideoDimensions,
        sourceRotationDegrees: Int?,
        hasVideoStream: Bool,
        range: FrameExportRange,
        frameRate: GIFFrameRate,
        sizePreset: GIFSizePreset,
        customWidth: GIFWidth?,
        quality: GIFQualityPreset,
        loopMode: GIFLoopMode,
        frameCountTolerance: Int = 2,
        durationTolerance: TimeInterval = 0.35
    ) {
        self.inputURL = inputURL
        self.outputURL = outputURL
        self.sourceDuration = sourceDuration
        self.sourceDimensions = sourceDimensions
        self.sourceRotationDegrees = sourceRotationDegrees
        self.hasVideoStream = hasVideoStream
        self.range = range
        self.frameRate = frameRate
        self.sizePreset = sizePreset
        self.customWidth = customWidth
        self.quality = quality
        self.loopMode = loopMode
        self.frameCountTolerance = frameCountTolerance
        self.durationTolerance = durationTolerance
    }

    public func validate() throws {
        guard hasVideoStream else { throw GIFExportValidationError.missingVideoStream }
        guard sourceDuration.isFinite, sourceDuration > 0 else { throw GIFExportValidationError.invalidDuration }
        guard sourceDimensions.width > 0, sourceDimensions.height > 0 else { throw GIFExportValidationError.invalidDimensions }
        guard outputURL.pathExtension.lowercased() == "gif" else { throw GIFExportValidationError.invalidGIF }
        if sizePreset == .custom {
            guard customWidth != nil else { throw GIFExportValidationError.invalidWidth }
        }
        guard frameCountTolerance >= 0 else { throw GIFExportValidationError.invalidRange }
        guard durationTolerance.isFinite, durationTolerance >= 0 else { throw GIFExportValidationError.invalidDuration }
        _ = try estimatedFrameCount()
        _ = try outputDimensions()
    }

    public func outputDuration() -> TimeInterval {
        range.duration
    }

    public func estimatedFrameCount() throws -> Int {
        guard range.duration.isFinite, range.duration > 0 else {
            throw GIFExportValidationError.invalidRange
        }
        let count = Int((range.duration * frameRate.framesPerSecond).rounded())
        guard count > 0 else {
            throw GIFExportValidationError.singleFrameOutput
        }
        return count
    }

    public func sourceDisplayDimensions() throws -> VideoDimensions {
        guard sourceDimensions.width > 0, sourceDimensions.height > 0 else {
            throw GIFExportValidationError.invalidDimensions
        }
        let rotation = (sourceRotationDegrees ?? 0).normalizedRotationDegrees
        return rotation == 90 || rotation == 270
            ? VideoDimensions(width: sourceDimensions.height, height: sourceDimensions.width)
            : sourceDimensions
    }

    public func selectedWidth() throws -> Int {
        let display = try sourceDisplayDimensions()
        let requested: Int
        switch sizePreset {
        case .original:
            requested = display.width
        case .wide1080, .wide720, .wide480, .wide320:
            requested = sizePreset.width ?? display.width
        case .custom:
            guard let customWidth else { throw GIFExportValidationError.invalidWidth }
            requested = customWidth.pixels
        }
        return min(requested, display.width)
    }

    public func outputDimensions() throws -> VideoDimensions {
        let display = try sourceDisplayDimensions()
        let width = try selectedWidth()
        let exactHeight = Double(display.height) * (Double(width) / Double(display.width))
        let roundedHeight = max(1, Int(exactHeight.rounded()))
        return VideoDimensions(width: width, height: roundedHeight)
    }

    public func scaleFilter() throws -> String {
        let width = try selectedWidth()
        return "scale=\(width):-1:flags=lanczos"
    }

    public func filterComplex() throws -> String {
        let fps = FrameExportTimestamp.compactSeconds(frameRate.framesPerSecond)
        let scale = try scaleFilter()
        return "[0:v]setpts=PTS-STARTPTS,fps=\(fps),\(scale),split[s0][s1];[s0]palettegen=max_colors=\(quality.maxColors)[p];[s1][p]paletteuse=dither=\(quality.dither)"
    }

    public var likelyLargeOutput: Bool {
        (Double((try? outputDimensions().width) ?? 0) * Double((try? outputDimensions().height) ?? 0) * Double((try? estimatedFrameCount()) ?? 0)) > 120_000_000
    }
}

public struct GIFExportResult: Equatable, Sendable {
    public let frameCount: Int
    public let dimensions: VideoDimensions
    public let duration: TimeInterval?
    public let loopMode: GIFLoopMode?
    public let byteCount: UInt64?

    public init(frameCount: Int, dimensions: VideoDimensions, duration: TimeInterval?, loopMode: GIFLoopMode?, byteCount: UInt64?) {
        self.frameCount = frameCount
        self.dimensions = dimensions
        self.duration = duration
        self.loopMode = loopMode
        self.byteCount = byteCount
    }
}

public enum GIFExportValidationError: LocalizedError, Equatable, Sendable {
    case missingVideoStream
    case invalidDuration
    case invalidFrameRate
    case invalidWidth
    case invalidDimensions
    case invalidRange
    case invalidGIF
    case singleFrameOutput
    case frameCountMismatch(expected: Int, actual: Int, tolerance: Int)
    case wrongDimensions(expected: VideoDimensions, actual: VideoDimensions)
    case durationMismatch(expected: TimeInterval, actual: TimeInterval, tolerance: TimeInterval)
    case loopMismatch(expected: GIFLoopMode, actual: GIFLoopMode?)

    public var errorDescription: String? {
        switch self {
        case .missingVideoStream:
            "Input contains no video stream."
        case .invalidDuration:
            "GIF export duration is invalid."
        case .invalidFrameRate:
            "GIF frame rate must be between 1 and 30 fps."
        case .invalidWidth:
            "GIF width must be between 64 and 1920 pixels."
        case .invalidDimensions:
            "GIF dimensions are invalid."
        case .invalidRange:
            "GIF export range is invalid."
        case .invalidGIF:
            "The exported file is not a valid GIF."
        case .singleFrameOutput:
            "The selected GIF settings would not produce an animation."
        case .frameCountMismatch(let expected, let actual, let tolerance):
            "GIF contains \(actual) frames, expected about \(expected) frames with tolerance \(tolerance)."
        case .wrongDimensions(let expected, let actual):
            "GIF dimensions are \(actual.width)x\(actual.height), expected \(expected.width)x\(expected.height)."
        case .durationMismatch(let expected, let actual, let tolerance):
            String(format: "GIF duration is %.3f seconds, expected %.3f seconds within %.3f seconds.", actual, expected, tolerance)
        case .loopMismatch(let expected, let actual):
            "GIF loop mode is \(actual?.title ?? "unknown"), expected \(expected.title)."
        }
    }
}

extension OutputFilename {
    public static func gifName(for inputURL: URL, range: FrameExportRange, sourceDuration: TimeInterval) -> String {
        let base = safeFrameBaseName(inputURL.deletingPathExtension().lastPathComponent)
        let isEntire = abs(range.startSeconds) < 0.000_001 && abs(range.endSeconds - sourceDuration) < 0.000_001
        if isEntire {
            return "\(base).gif"
        }
        return "\(base)-\(FrameExportTimestamp.filenameLabel(range.startSeconds))-to-\(FrameExportTimestamp.filenameLabel(range.endSeconds)).gif"
    }
}
