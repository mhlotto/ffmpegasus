import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ExportProfileOutputValidator {
    public static func verify(metadata: VideoMetadata, profile: ExportProfile, outputURL: URL, expectsAudio: Bool) throws {
        let actualExtension = outputURL.pathExtension.lowercased()
        guard actualExtension == profile.fileExtension else {
            throw ExportProfileValidationError.wrongExtension(expected: profile.fileExtension, actual: actualExtension)
        }
        if let formatName = metadata.formatName,
           !profile.expectedFormatNames.contains(formatName) {
            throw ExportProfileValidationError.wrongContainer(expected: profile, actual: formatName)
        }
        guard profile.expectedVideoCodecs.contains(metadata.videoCodec ?? "") else {
            throw ExportProfileValidationError.wrongVideoCodec(expected: profile, actual: metadata.videoCodec)
        }
        if expectsAudio {
            guard profile.expectedAudioCodecs.contains(metadata.audioCodec ?? "") else {
                throw ExportProfileValidationError.wrongAudioCodec(expected: profile, actual: metadata.audioCodec)
            }
        }
    }
}

public enum TrimOutputValidationError: LocalizedError, Equatable, Sendable {
    case missingVideoStream
    case wrongCodec(String?)
    case invalidDimensions
    case oddDimensions(VideoDimensions)
    case missingExpectedAudio
    case durationMismatch(expected: TimeInterval, actual: TimeInterval, tolerance: TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .missingVideoStream:
            "Trimmed output contains no video stream."
        case .wrongCodec(let codec):
            "Accurate Trim output is not H.264. Detected codec: \(codec ?? "unknown")."
        case .invalidDimensions:
            "Trimmed output dimensions are unavailable."
        case .oddDimensions(let dimensions):
            "Accurate Trim output dimensions must be even. Got \(dimensions.width)x\(dimensions.height)."
        case .missingExpectedAudio:
            "Accurate Trim output is missing expected audio."
        case .durationMismatch(let expected, let actual, let tolerance):
            String(format: "Trimmed output duration is %.3f seconds, expected %.3f seconds within %.3f seconds.", actual, expected, tolerance)
        }
    }
}

public enum TrimOutputValidator {
    public static let fastDurationTolerance: TimeInterval = 1.0
    public static let accurateDurationTolerance: TimeInterval = 0.15

    public static func verify(metadata: VideoMetadata, request: EditingRequest) throws {
        guard metadata.videoCodec != nil else {
            throw TrimOutputValidationError.missingVideoStream
        }

        let expectedDuration = try request.trimPlan().outputDuration
        let tolerance = request.effectiveTrimExecutionMode == .accurate ? accurateDurationTolerance : fastDurationTolerance
        guard abs(metadata.duration - expectedDuration) <= tolerance else {
            throw TrimOutputValidationError.durationMismatch(
                expected: expectedDuration,
                actual: metadata.duration,
                tolerance: tolerance
            )
        }

        guard request.effectiveTrimExecutionMode == .accurate else { return }

        try ExportProfileOutputValidator.verify(metadata: metadata, profile: request.exportProfile, outputURL: request.outputURL, expectsAudio: request.hasAudioStream)
        guard request.exportProfile.expectedVideoCodecs.contains(metadata.videoCodec ?? "") else {
            throw TrimOutputValidationError.wrongCodec(metadata.videoCodec)
        }
        guard let width = metadata.width, let height = metadata.height else {
            throw TrimOutputValidationError.invalidDimensions
        }
        let dimensions = VideoDimensions(width: width, height: height)
        guard width.isMultiple(of: 2), height.isMultiple(of: 2) else {
            throw TrimOutputValidationError.oddDimensions(dimensions)
        }
    }
}

public enum CompressionOutputValidator {
    public static func verify(metadata: VideoMetadata, request: CompressionRequest) throws {
        try ExportProfileOutputValidator.verify(metadata: metadata, profile: request.exportProfile, outputURL: request.outputURL, expectsAudio: request.audioMode == .keep && request.hasAudioStream)
        guard request.exportProfile.expectedVideoCodecs.contains(metadata.videoCodec ?? "") else {
            throw CompressionValidationError.wrongCodec(metadata.videoCodec)
        }
        guard let width = metadata.width, let height = metadata.height else {
            throw CompressionValidationError.invalidSourceDimensions
        }
        let actual = VideoDimensions(width: width, height: height)
        let expected = try request.outputDimensions()
        guard actual == expected else {
            throw CompressionValidationError.wrongDimensions(expected: expected, actual: actual)
        }
        guard width.isMultiple(of: 2), height.isMultiple(of: 2) else {
            throw CompressionValidationError.oddDimensions(actual)
        }
        if request.audioMode == .remove || !request.hasAudioStream {
            guard metadata.audioCodec == nil else { throw CompressionValidationError.unexpectedAudio }
        } else {
            guard metadata.audioCodec != nil else { throw CompressionValidationError.missingExpectedAudio }
        }
        guard abs(metadata.duration - request.sourceDuration) <= max(1.0, request.sourceDuration * 0.05) else {
            throw CompressionValidationError.durationMismatch
        }
    }
}

public enum VideoTransformOutputValidator {
    public static let durationTolerance: TimeInterval = 0.15

    public static func verify(metadata: VideoMetadata, request: VideoTransformRequest) throws {
        guard metadata.videoCodec != nil else {
            throw VideoTransformValidationError.missingVideoStream
        }
        try ExportProfileOutputValidator.verify(metadata: metadata, profile: request.exportProfile, outputURL: request.outputURL, expectsAudio: request.hasAudioStream)
        guard request.exportProfile.expectedVideoCodecs.contains(metadata.videoCodec ?? "") else {
            throw VideoTransformValidationError.wrongCodec(metadata.videoCodec)
        }
        guard let width = metadata.width, let height = metadata.height else {
            throw VideoTransformValidationError.invalidSourceDimensions
        }
        let actual = VideoDimensions(width: width, height: height)
        let expected = try request.outputDimensions()
        guard actual == expected else {
            throw VideoTransformValidationError.wrongDimensions(expected: expected, actual: actual)
        }
        guard width.isMultiple(of: 2), height.isMultiple(of: 2) else {
            throw VideoTransformValidationError.oddDimensions(actual)
        }
        if request.hasAudioStream {
            guard metadata.audioCodec != nil else { throw VideoTransformValidationError.missingExpectedAudio }
        } else {
            guard metadata.audioCodec == nil else { throw VideoTransformValidationError.unexpectedAudio }
        }
        guard abs(metadata.duration - request.sourceDuration) <= max(durationTolerance, request.sourceDuration * 0.01) else {
            throw VideoTransformValidationError.durationMismatch
        }
        if let rotation = metadata.rotationDegrees?.normalizedRotationDegrees, rotation != 0 {
            throw VideoTransformValidationError.staleRotationMetadata(rotation)
        }
    }
}

public enum VideoEditPlanOutputValidator {
    public static func verify(metadata: VideoMetadata, plan: VideoEditPlan) throws {
        guard metadata.videoCodec != nil else {
            throw VideoEditPlanValidationError.missingVideoStream
        }

        let strategy = try plan.executionStrategy()
        let expectedDuration = try plan.outputDuration()
        let tolerance: TimeInterval = strategy == .streamCopy ? 1.0 : 0.15
        let frameTolerance = metadata.frameRate.map { $0 > 0 ? 2.0 / $0 : 0 } ?? 0
        let effectiveTolerance = max(tolerance, frameTolerance)
        guard abs(metadata.duration - expectedDuration) <= effectiveTolerance + 0.001 else {
            throw TrimOutputValidationError.durationMismatch(expected: expectedDuration, actual: metadata.duration, tolerance: effectiveTolerance)
        }

        let expectedDimensions = try plan.outputDimensions()
        guard let width = metadata.width, let height = metadata.height else {
            throw VideoTransformValidationError.invalidSourceDimensions
        }
        let actualDimensions = VideoDimensions(width: width, height: height)
        guard actualDimensions == expectedDimensions else {
            throw VideoTransformValidationError.wrongDimensions(expected: expectedDimensions, actual: actualDimensions)
        }

        if strategy == .reencode {
            try ExportProfileOutputValidator.verify(metadata: metadata, profile: plan.exportProfile, outputURL: plan.outputURL, expectsAudio: plan.audioMode == .keep && plan.hasAudioStream)
            guard plan.exportProfile.expectedVideoCodecs.contains(metadata.videoCodec ?? "") else {
                throw VideoTransformValidationError.wrongCodec(metadata.videoCodec)
            }
            guard width.isMultiple(of: 2), height.isMultiple(of: 2) else {
                throw VideoTransformValidationError.oddDimensions(actualDimensions)
            }
        }

        if plan.audioMode == .keep, plan.hasAudioStream {
            guard metadata.audioCodec != nil else { throw VideoTransformValidationError.missingExpectedAudio }
            if plan.speed != nil, let audioDuration = metadata.audioDuration {
                guard abs(metadata.duration - audioDuration) <= max(0.15, frameTolerance) else {
                    throw VideoSpeedValidationError.audioVideoDurationMismatch(video: metadata.duration, audio: audioDuration)
                }
            }
        } else {
            guard metadata.audioCodec == nil else { throw VideoTransformValidationError.unexpectedAudio }
        }

        if let rotation = metadata.rotationDegrees?.normalizedRotationDegrees, rotation != 0 {
            throw VideoTransformValidationError.staleRotationMetadata(rotation)
        }
    }
}

public enum CropOutputValidator {
    public static let durationTolerance: TimeInterval = 0.15

    public static func verify(metadata: VideoMetadata, request: CropRequest) throws {
        guard metadata.videoCodec != nil else {
            throw CropValidationError.missingVideoStream
        }
        try ExportProfileOutputValidator.verify(metadata: metadata, profile: request.exportProfile, outputURL: request.outputURL, expectsAudio: request.hasAudioStream)
        guard request.exportProfile.expectedVideoCodecs.contains(metadata.videoCodec ?? "") else {
            throw CropValidationError.wrongCodec(metadata.videoCodec)
        }
        guard let width = metadata.width, let height = metadata.height else {
            throw CropValidationError.invalidSourceDimensions
        }
        let actual = VideoDimensions(width: width, height: height)
        let expected = try request.outputDimensions()
        guard actual == expected else {
            throw CropValidationError.wrongDimensions(expected: expected, actual: actual)
        }
        if request.hasAudioStream {
            guard metadata.audioCodec != nil else { throw CropValidationError.missingExpectedAudio }
        } else {
            guard metadata.audioCodec == nil else { throw CropValidationError.unexpectedAudio }
        }
        guard abs(metadata.duration - request.sourceDuration) <= max(durationTolerance, request.sourceDuration * 0.01) else {
            throw CropValidationError.durationMismatch
        }
        if let rotation = metadata.rotationDegrees?.normalizedRotationDegrees, rotation != 0 {
            throw CropValidationError.staleRotationMetadata(rotation)
        }
    }
}

public enum VideoSpeedOutputValidator {
    public static func verify(metadata: VideoMetadata, request: VideoSpeedRequest) throws {
        try ExportProfileOutputValidator.verify(metadata: metadata, profile: request.exportProfile, outputURL: request.outputURL, expectsAudio: request.keepsAudio)
        guard request.exportProfile.expectedVideoCodecs.contains(metadata.videoCodec ?? "") else {
            throw VideoSpeedValidationError.wrongCodec(metadata.videoCodec)
        }
        guard let width = metadata.width, let height = metadata.height else {
            throw VideoSpeedValidationError.invalidSourceDimensions
        }
        let actualDimensions = VideoDimensions(width: width, height: height)
        let expectedDimensions = try request.outputDimensions()
        guard actualDimensions == expectedDimensions else {
            throw VideoSpeedValidationError.wrongDimensions(expected: expectedDimensions, actual: actualDimensions)
        }
        guard width.isMultiple(of: 2), height.isMultiple(of: 2) else {
            throw VideoSpeedValidationError.oddDimensions(actualDimensions)
        }

        let expectedDuration = try request.expectedDuration()
        let frameTolerance = metadata.frameRate.map { $0 > 0 ? 2.0 / $0 : 0 } ?? 0
        let tolerance = max(0.15, expectedDuration * 0.01, frameTolerance)
        guard abs(metadata.duration - expectedDuration) <= tolerance else {
            throw VideoSpeedValidationError.durationMismatch(expected: expectedDuration, actual: metadata.duration, tolerance: tolerance)
        }

        if request.keepsAudio {
            guard metadata.audioCodec != nil else {
                throw VideoSpeedValidationError.missingExpectedAudio
            }
            if let audioDuration = metadata.audioDuration {
                let syncTolerance = max(0.15, frameTolerance)
                guard abs(metadata.duration - audioDuration) <= syncTolerance else {
                    throw VideoSpeedValidationError.audioVideoDurationMismatch(video: metadata.duration, audio: audioDuration)
                }
            }
        } else {
            guard metadata.audioCodec == nil else {
                throw VideoSpeedValidationError.unexpectedAudio
            }
        }

        if let rotation = metadata.rotationDegrees?.normalizedRotationDegrees, rotation != 0 {
            throw VideoSpeedValidationError.staleRotationMetadata(rotation)
        }
    }
}

public enum FrameExportOutputValidator {
    public static func verify(imageURL: URL, request: FrameExportRequest) throws -> FrameImageInfo {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil) else {
            throw FrameExportValidationError.wrongFormat(expected: request.format, actual: nil)
        }
        guard CGImageSourceGetCount(source) == 1 else {
            throw FrameExportValidationError.wrongFormat(expected: request.format, actual: nil)
        }
        let actualFormat = frameFormat(for: CGImageSourceGetType(source))
        guard actualFormat == request.format else {
            throw FrameExportValidationError.wrongFormat(expected: request.format, actual: actualFormat)
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0,
              height > 0 else {
            throw FrameExportValidationError.invalidDimensions
        }
        let actualDimensions = VideoDimensions(width: width, height: height)
        let expectedDimensions = try request.expectedDimensions()
        guard actualDimensions == expectedDimensions else {
            throw FrameExportValidationError.wrongDimensions(expected: expectedDimensions, actual: actualDimensions)
        }
        guard imageURL.pathExtension.lowercased() == request.format.fileExtension else {
            throw FrameExportValidationError.wrongFormat(expected: request.format, actual: actualFormat)
        }
        return FrameImageInfo(format: request.format, dimensions: actualDimensions)
    }

    private static func frameFormat(for type: CFString?) -> FrameImageFormat? {
        guard let type else { return nil }
        let identifier = type as String
        if identifier == UTType.png.identifier {
            return .png
        }
        if identifier == UTType.jpeg.identifier {
            return .jpeg
        }
        return nil
    }
}

public enum IntervalFrameExportOutputValidator {
    public static let fullDecodeThreshold = 50

    public static func matchingFiles(in directory: URL, request: IntervalFrameExportRequest, fileSystem: EditingFileSystemChecking) -> [URL] {
        fileSystem.contentsOfDirectory(at: directory)
            .filter { request.matchesGeneratedFrameName($0) }
            .sorted()
            .map { directory.appendingPathComponent($0) }
    }

    public static func verify(
        request: IntervalFrameExportRequest,
        files: [URL],
        fileSystem: EditingFileSystemChecking = LocalEditingFileSystem()
    ) throws -> IntervalFrameExportResult {
        let files = files.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard let first = files.first, let last = files.last else {
            throw FrameExportValidationError.noImagesCreated
        }

        let expectedCount = request.expectedImageCount
        guard abs(files.count - expectedCount) <= request.countTolerance else {
            throw FrameExportValidationError.imageCountMismatch(
                expected: expectedCount,
                actual: files.count,
                tolerance: request.countTolerance
            )
        }

        for (index, file) in files.enumerated() {
            let expected = request.outputURL(forSequenceNumber: index + 1).lastPathComponent
            guard file.lastPathComponent == expected else {
                throw FrameExportValidationError.missingSequenceNumber(index + 1)
            }
            guard let size = fileSystem.fileSize(at: file), size > 0 else {
                throw FrameExportValidationError.emptyImageFile(file.path)
            }
        }

        let sampleFiles = verificationSample(from: files)
        var dimensions: VideoDimensions?
        for file in sampleFiles {
            let frameRequest = FrameExportRequest(
                inputURL: request.inputURL,
                outputURL: file,
                timestampSeconds: request.range.startSeconds,
                sourceDuration: request.sourceDuration,
                sourceDimensions: request.sourceDimensions,
                sourceRotationDegrees: request.sourceRotationDegrees,
                hasVideoStream: request.hasVideoStream,
                format: request.format,
                jpegQuality: request.jpegQuality
            )
            let info = try FrameExportOutputValidator.verify(imageURL: file, request: frameRequest)
            dimensions = info.dimensions
        }

        let finalDimensions = try dimensions ?? request.expectedDimensions()
        return IntervalFrameExportResult(
            imageCount: files.count,
            dimensions: finalDimensions,
            firstImageURL: first,
            lastImageURL: last
        )
    }

    private static func verificationSample(from files: [URL]) -> [URL] {
        guard files.count > fullDecodeThreshold else {
            return files
        }
        let middle = files.count / 2
        return [files[0], files[middle], files[files.count - 1]]
    }
}

public struct FFprobeCompressionOutputVerifier: CompressionOutputVerifying {
    private let ffprobePath: String

    public init(ffprobePath: String) {
        self.ffprobePath = ffprobePath
    }

    public func verify(request: CompressionRequest, outputURL: URL) async throws {
        let metadata = try await FFprobeRunner().loadMetadata(ffprobePath: ffprobePath, inputURL: outputURL)
        try CompressionOutputValidator.verify(metadata: metadata, request: request)
    }
}

public struct FFprobeTrimOutputVerifier: TrimOutputVerifying {
    private let ffprobePath: String

    public init(ffprobePath: String) {
        self.ffprobePath = ffprobePath
    }

    public func verify(request: EditingRequest, outputURL: URL) async throws {
        let metadata = try await FFprobeRunner().loadMetadata(ffprobePath: ffprobePath, inputURL: outputURL)
        try TrimOutputValidator.verify(metadata: metadata, request: request)
    }
}

public struct FFprobeVideoTransformOutputVerifier: VideoTransformOutputVerifying {
    private let ffprobePath: String

    public init(ffprobePath: String) {
        self.ffprobePath = ffprobePath
    }

    public func verify(request: VideoTransformRequest, outputURL: URL) async throws {
        let metadata = try await FFprobeRunner().loadMetadata(ffprobePath: ffprobePath, inputURL: outputURL)
        try VideoTransformOutputValidator.verify(metadata: metadata, request: request)
    }
}

public struct FFprobeCropOutputVerifier: CropOutputVerifying {
    private let ffprobePath: String

    public init(ffprobePath: String) {
        self.ffprobePath = ffprobePath
    }

    public func verify(request: CropRequest, outputURL: URL) async throws {
        let metadata = try await FFprobeRunner().loadMetadata(ffprobePath: ffprobePath, inputURL: outputURL)
        try CropOutputValidator.verify(metadata: metadata, request: request)
    }
}

public struct FFprobeVideoEditPlanOutputVerifier: VideoEditPlanOutputVerifying {
    private let ffprobePath: String

    public init(ffprobePath: String) {
        self.ffprobePath = ffprobePath
    }

    public func verify(plan: VideoEditPlan, outputURL: URL) async throws {
        let metadata = try await FFprobeRunner().loadMetadata(ffprobePath: ffprobePath, inputURL: outputURL)
        try VideoEditPlanOutputValidator.verify(metadata: metadata, plan: plan)
    }
}

public struct FFprobeVideoSpeedOutputVerifier: VideoSpeedOutputVerifying {
    private let ffprobePath: String

    public init(ffprobePath: String) {
        self.ffprobePath = ffprobePath
    }

    public func verify(request: VideoSpeedRequest, outputURL: URL) async throws {
        let metadata = try await FFprobeRunner().loadMetadata(ffprobePath: ffprobePath, inputURL: outputURL)
        try VideoSpeedOutputValidator.verify(metadata: metadata, request: request)
    }
}

public struct NativeFrameExportOutputVerifier: FrameExportOutputVerifying {
    public init() {}

    public func verify(request: FrameExportRequest, outputURL: URL) async throws -> FrameImageInfo {
        try FrameExportOutputValidator.verify(imageURL: outputURL, request: request)
    }
}

public struct NativeIntervalFrameExportOutputVerifier: IntervalFrameExportOutputVerifying {
    private let fileSystem: EditingFileSystemChecking

    public init(fileSystem: EditingFileSystemChecking = LocalEditingFileSystem()) {
        self.fileSystem = fileSystem
    }

    public func verify(request: IntervalFrameExportRequest, files: [URL]) async throws -> IntervalFrameExportResult {
        try IntervalFrameExportOutputValidator.verify(request: request, files: files, fileSystem: fileSystem)
    }
}

public enum GIFExportOutputValidator {
    public static let fullDelayDecodeThreshold = 120

    public static func verify(
        gifURL: URL,
        request: GIFExportRequest,
        fileSystem: EditingFileSystemChecking = LocalEditingFileSystem()
    ) throws -> GIFExportResult {
        guard fileSystem.fileExists(at: gifURL),
              let byteCount = fileSystem.fileSize(at: gifURL),
              byteCount > 0 else {
            throw GIFExportValidationError.invalidGIF
        }
        guard gifURL.pathExtension.lowercased() == "gif" else {
            throw GIFExportValidationError.invalidGIF
        }
        guard let source = CGImageSourceCreateWithURL(gifURL as CFURL, nil) else {
            throw GIFExportValidationError.invalidGIF
        }
        guard let imageType = CGImageSourceGetType(source),
              (imageType as String) == UTType.gif.identifier else {
            throw GIFExportValidationError.invalidGIF
        }

        let frameCount = CGImageSourceGetCount(source)
        let expectedFrames = try request.estimatedFrameCount()
        guard frameCount > 1 || expectedFrames <= 1 else {
            throw GIFExportValidationError.singleFrameOutput
        }
        guard abs(frameCount - expectedFrames) <= request.frameCountTolerance else {
            throw GIFExportValidationError.frameCountMismatch(
                expected: expectedFrames,
                actual: frameCount,
                tolerance: request.frameCountTolerance
            )
        }

        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0,
              height > 0 else {
            throw GIFExportValidationError.invalidDimensions
        }
        let actualDimensions = VideoDimensions(width: width, height: height)
        let expectedDimensions = try request.outputDimensions()
        guard actualDimensions == expectedDimensions else {
            throw GIFExportValidationError.wrongDimensions(expected: expectedDimensions, actual: actualDimensions)
        }

        let duration = gifDuration(source: source, frameCount: frameCount)
        if let duration {
            let expected = request.outputDuration()
            guard abs(duration - expected) <= request.durationTolerance else {
                throw GIFExportValidationError.durationMismatch(expected: expected, actual: duration, tolerance: request.durationTolerance)
            }
        }

        let loopMode = gifLoopMode(source: source)
        if let loopMode, loopMode != request.loopMode {
            throw GIFExportValidationError.loopMismatch(expected: request.loopMode, actual: loopMode)
        }

        return GIFExportResult(
            frameCount: frameCount,
            dimensions: actualDimensions,
            duration: duration,
            loopMode: loopMode,
            byteCount: byteCount
        )
    }

    private static func gifDuration(source: CGImageSource, frameCount: Int) -> TimeInterval? {
        let sampleAll = frameCount <= fullDelayDecodeThreshold
        let indices: [Int]
        if sampleAll {
            indices = Array(0..<frameCount)
        } else {
            indices = [0, frameCount / 2, frameCount - 1]
        }
        let delays = indices.compactMap { gifDelay(source: source, index: $0) }
        guard !delays.isEmpty else { return nil }
        let average = delays.reduce(0, +) / Double(delays.count)
        return sampleAll ? delays.reduce(0, +) : average * Double(frameCount)
    }

    private static func gifDelay(source: CGImageSource, index: Int) -> TimeInterval? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return nil
        }
        if let unclamped = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber, unclamped.doubleValue > 0 {
            return unclamped.doubleValue
        }
        if let delay = gifProperties[kCGImagePropertyGIFDelayTime] as? NSNumber, delay.doubleValue > 0 {
            return delay.doubleValue
        }
        return nil
    }

    private static func gifLoopMode(source: CGImageSource) -> GIFLoopMode? {
        guard let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any],
              let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any],
              let loopCount = gifProperties[kCGImagePropertyGIFLoopCount] as? NSNumber else {
            return nil
        }
        return loopCount.intValue == 0 ? .forever : .once
    }
}

public struct NativeGIFExportOutputVerifier: GIFExportOutputVerifying {
    private let fileSystem: EditingFileSystemChecking

    public init(fileSystem: EditingFileSystemChecking = LocalEditingFileSystem()) {
        self.fileSystem = fileSystem
    }

    public func verify(request: GIFExportRequest, outputURL: URL) async throws -> GIFExportResult {
        try GIFExportOutputValidator.verify(gifURL: outputURL, request: request, fileSystem: fileSystem)
    }
}
