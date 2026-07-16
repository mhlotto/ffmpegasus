import Combine
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct EditingCommand: Equatable, Sendable {
    public let executablePath: String
    public let arguments: [String]

    public init(executablePath: String, arguments: [String]) {
        self.executablePath = executablePath
        self.arguments = arguments
    }
}

public struct RemoveAudioRequest: Equatable, Sendable {
    public let inputURL: URL
    public let outputURL: URL
    public let sourceDuration: TimeInterval
    public let hasVideoStream: Bool
    public let hasAudioStream: Bool

    public init(inputURL: URL, outputURL: URL, sourceDuration: TimeInterval, hasVideoStream: Bool, hasAudioStream: Bool) {
        self.inputURL = inputURL
        self.outputURL = outputURL
        self.sourceDuration = sourceDuration
        self.hasVideoStream = hasVideoStream
        self.hasAudioStream = hasAudioStream
    }
}

public struct EditingDiagnostics: Equatable, Sendable {
    public var ffmpegPath: String
    public var arguments: [String]
    public var stderr: String
    public var stderrTail: String
    public var processIdentifier: Int32?
    public var startedAt: Date?
    public var lastActivityAt: Date?

    public init(
        ffmpegPath: String = "",
        arguments: [String] = [],
        stderr: String = "",
        stderrTail: String = "",
        processIdentifier: Int32? = nil,
        startedAt: Date? = nil,
        lastActivityAt: Date? = nil
    ) {
        self.ffmpegPath = ffmpegPath
        self.arguments = arguments
        self.stderr = stderr
        self.stderrTail = stderrTail
        self.processIdentifier = processIdentifier
        self.startedAt = startedAt
        self.lastActivityAt = lastActivityAt
    }
}

public enum EditingOperationPhase: Equatable, Sendable {
    case idle
    case starting
    case running(progress: Double?)
    case cancelling
    case completed(outputURL: URL, byteCount: UInt64)
    case failed(summary: String)
    case cancelled

    public var isActive: Bool {
        switch self {
        case .starting, .running, .cancelling:
            true
        case .idle, .completed, .failed, .cancelled:
            false
        }
    }

    public var title: String {
        switch self {
        case .idle:
            "Idle"
        case .starting:
            "Starting FFmpeg..."
        case .running:
            "Trimming video..."
        case .cancelling:
            "Cancelling..."
        case .completed:
            "Trim complete"
        case .failed:
            "Trim failed"
        case .cancelled:
            "Cancelled"
        }
    }
}

@MainActor
public final class EditingOperationState: ObservableObject {
    @Published public var phase: EditingOperationPhase = .idle
    @Published public var message: String?
    @Published public var outputURL: URL?
    @Published public var diagnostics = EditingDiagnostics()
    @Published public var statusText: String?

    public var isRunning: Bool {
        phase.isActive
    }

    public var progress: Double? {
        switch phase {
        case .running(let progress):
            progress
        case .completed:
            1
        default:
            nil
        }
    }

    public var status: String {
        statusText ?? phase.title
    }

    public init() {}
}

public enum VideoEditingError: LocalizedError, Equatable, Sendable {
    case inputMissing(String)
    case outputMatchesInput
    case missingOutputDirectory(String)
    case outputDirectoryNotWritable(String)
    case missingFFmpegExecutable(String)
    case ffmpegNotExecutable(String)
    case ffmpegExited(code: Int32)
    case outputMissing(String)
    case outputEmpty(String)
    case launchFailed(String)
    case missingVideoStream
    case missingAudioStream

    public var errorDescription: String? {
        switch self {
        case .inputMissing(let path):
            "Input file was not found: \(path)"
        case .outputMatchesInput:
            "Output path must be different from the input path."
        case .missingOutputDirectory(let path):
            "Output directory does not exist: \(path)"
        case .outputDirectoryNotWritable(let path):
            "Output directory is not writable: \(path)"
        case .missingFFmpegExecutable(let path):
            "FFmpeg executable was not found: \(path)"
        case .ffmpegNotExecutable(let path):
            "FFmpeg path is not executable: \(path)"
        case .ffmpegExited(let code):
            "FFmpeg returned exit code \(code)."
        case .outputMissing(let path):
            "FFmpeg exited successfully, but no output file was created: \(path)"
        case .outputEmpty(let path):
            "FFmpeg exited successfully, but the output file is empty: \(path)"
        case .launchFailed(let message):
            "Could not start FFmpeg: \(message)"
        case .missingVideoStream:
            "Input contains no video stream."
        case .missingAudioStream:
            "Input contains no audio stream."
        }
    }
}

public protocol EditingProcessExecuting: Sendable {
    func run(
        command: EditingCommand,
        totalDuration: TimeInterval,
        onStarted: @escaping @Sendable () -> Void,
        onProgress: @escaping @Sendable (Double) -> Void,
        onActivity: @escaping @Sendable (ProcessActivity) -> Void
    ) async throws -> ProcessResult

    func cancel()
}

public protocol EditingFileSystemChecking: Sendable {
    func fileExists(at url: URL) -> Bool
    func directoryExists(at url: URL) -> Bool
    func isWritableDirectory(at url: URL) -> Bool
    func isExecutableFile(at url: URL) -> Bool
    func fileSize(at url: URL) -> UInt64?
    func contentsOfDirectory(at url: URL) -> [String]
    func removeFile(at url: URL)
}

public protocol CompressionOutputVerifying: Sendable {
    func verify(request: CompressionRequest, outputURL: URL) async throws
}

public protocol TrimOutputVerifying: Sendable {
    func verify(request: EditingRequest, outputURL: URL) async throws
}

public protocol VideoTransformOutputVerifying: Sendable {
    func verify(request: VideoTransformRequest, outputURL: URL) async throws
}

public protocol VideoEditPlanOutputVerifying: Sendable {
    func verify(plan: VideoEditPlan, outputURL: URL) async throws
}

public protocol VideoSpeedOutputVerifying: Sendable {
    func verify(request: VideoSpeedRequest, outputURL: URL) async throws
}

public protocol FrameExportOutputVerifying: Sendable {
    func verify(request: FrameExportRequest, outputURL: URL) async throws -> FrameImageInfo
}

public protocol IntervalFrameExportOutputVerifying: Sendable {
    func verify(request: IntervalFrameExportRequest, files: [URL]) async throws -> IntervalFrameExportResult
}

public struct FrameImageInfo: Equatable, Sendable {
    public let format: FrameImageFormat
    public let dimensions: VideoDimensions

    public init(format: FrameImageFormat, dimensions: VideoDimensions) {
        self.format = format
        self.dimensions = dimensions
    }
}

public struct IntervalFrameExportResult: Equatable, Sendable {
    public let imageCount: Int
    public let dimensions: VideoDimensions
    public let firstImageURL: URL
    public let lastImageURL: URL

    public init(imageCount: Int, dimensions: VideoDimensions, firstImageURL: URL, lastImageURL: URL) {
        self.imageCount = imageCount
        self.dimensions = dimensions
        self.firstImageURL = firstImageURL
        self.lastImageURL = lastImageURL
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
        let tolerance = request.trimExecutionMode == .accurate ? accurateDurationTolerance : fastDurationTolerance
        guard abs(metadata.duration - expectedDuration) <= tolerance else {
            throw TrimOutputValidationError.durationMismatch(
                expected: expectedDuration,
                actual: metadata.duration,
                tolerance: tolerance
            )
        }

        guard request.trimExecutionMode == .accurate else { return }

        guard metadata.videoCodec == "h264" else {
            throw TrimOutputValidationError.wrongCodec(metadata.videoCodec)
        }
        guard let width = metadata.width, let height = metadata.height else {
            throw TrimOutputValidationError.invalidDimensions
        }
        let dimensions = VideoDimensions(width: width, height: height)
        guard width.isMultiple(of: 2), height.isMultiple(of: 2) else {
            throw TrimOutputValidationError.oddDimensions(dimensions)
        }
        if request.hasAudioStream {
            guard metadata.audioCodec != nil else {
                throw TrimOutputValidationError.missingExpectedAudio
            }
        }
    }
}

public enum CompressionOutputValidator {
    public static func verify(metadata: VideoMetadata, request: CompressionRequest) throws {
        guard metadata.videoCodec == "h264" else {
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
        guard metadata.videoCodec == "h264" else {
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
            guard metadata.videoCodec == "h264" else {
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

public enum VideoSpeedOutputValidator {
    public static func verify(metadata: VideoMetadata, request: VideoSpeedRequest) throws {
        guard metadata.videoCodec == "h264" else {
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

public protocol CompressionEncoderChecking: Sendable {
    func supportsLibx264(ffmpegPath: String) async throws -> Bool
}

public final class FFmpegCompressionEncoderChecker: CompressionEncoderChecking, @unchecked Sendable {
    private let libx264Support = LockedValue<[String: Bool]>([:])

    public init() {}

    public func supportsLibx264(ffmpegPath: String) async throws -> Bool {
        if libx264Support.value[ffmpegPath] == true {
            return true
        }
        let encoders = try await FFmpegRunner().encoders(ffmpegPath: ffmpegPath)
        let supported = encoders.contains("libx264")
        libx264Support.update { $0[ffmpegPath] = supported }
        return supported
    }
}

public struct LocalEditingFileSystem: EditingFileSystemChecking {
    public init() {}

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    public func isExecutableFile(at url: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: url.path)
    }

    public func isWritableDirectory(at url: URL) -> Bool {
        FileManager.default.isWritableFile(atPath: url.path)
    }

    public func fileSize(at url: URL) -> UInt64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return nil
        }
        return size.uint64Value
    }

    public func contentsOfDirectory(at url: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
    }

    public func removeFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set(_ newValue: Bool) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    var isSet: Bool {
        lock.lock()
        let current = value
        lock.unlock()
        return current
    }
}

public final class FFmpegEditingProcessExecutor: EditingProcessExecuting, @unchecked Sendable {
    private let activeProcess = ActiveProcess()
    private let parser = FFmpegProgressParser()
    private let processRunner = ProcessRunner()

    public init() {}

    public func cancel() {
        activeProcess.terminate()
    }

    public func run(
        command: EditingCommand,
        totalDuration: TimeInterval,
        onStarted: @escaping @Sendable () -> Void,
        onProgress: @escaping @Sendable (Double) -> Void,
        onActivity: @escaping @Sendable (ProcessActivity) -> Void
    ) async throws -> ProcessResult {
        let parser = parser
        let didStart = LockedValue(false)
        return try await processRunner.run(
            executablePath: command.executablePath,
            arguments: command.arguments,
            activeProcess: activeProcess,
            stdoutLineHandler: { line in
                guard let parsed = parser.parse(line), let outTime = parsed.outTime, totalDuration > 0 else { return }
                onProgress(min(max(outTime / totalDuration, 0), 1))
            },
            activityHandler: { activity in
                if activity.processIdentifier != nil, !didStart.value {
                    didStart.set(true)
                    onStarted()
                }
                onActivity(activity)
            }
        )
    }
}

public final class VideoEditingService: @unchecked Sendable {
    private let processExecutor: any EditingProcessExecuting
    private let fileSystem: any EditingFileSystemChecking
    private let cancellationFlag = CancellationFlag()
    private let encoderChecker: any CompressionEncoderChecking

    public init(
        processExecutor: any EditingProcessExecuting = FFmpegEditingProcessExecutor(),
        fileSystem: any EditingFileSystemChecking = LocalEditingFileSystem(),
        encoderChecker: any CompressionEncoderChecking = FFmpegCompressionEncoderChecker()
    ) {
        self.processExecutor = processExecutor
        self.fileSystem = fileSystem
        self.encoderChecker = encoderChecker
    }

    public func streamCopyArguments(for request: EditingRequest) throws -> [String] {
        let plan = try request.trimPlan()
        switch request.trimExecutionMode {
        case .fast:
            return [
                "-y",
                "-nostdin",
                "-ss", TimeFormatting.ffmpegSeconds(plan.startTime),
                "-i", request.inputURL.path,
                "-t", TimeFormatting.ffmpegSeconds(plan.outputDuration),
                "-map", "0",
                "-c", "copy",
                "-progress", "pipe:1",
                "-nostats",
                request.outputURL.path
            ]
        case .accurate:
            guard request.hasVideoStream else { throw CompressionValidationError.missingVideoStream }
            var arguments = [
                "-y",
                "-nostdin",
                "-ss", TimeFormatting.ffmpegSeconds(plan.startTime),
                "-i", request.inputURL.path,
                "-t", TimeFormatting.ffmpegSeconds(plan.outputDuration),
                "-map", "0:v:0"
            ]
            if request.hasAudioStream {
                arguments += ["-map", "0:a:0?"]
            }
            arguments += [
                "-c:v", "libx264",
                "-preset", "medium",
                "-crf", "20",
                "-pix_fmt", "yuv420p"
            ]
            if request.hasAudioStream {
                arguments += ["-c:a", "aac", "-b:a", "128k"]
            }
            arguments += [
                "-movflags", "+faststart",
                "-progress", "pipe:1",
                "-nostats",
                request.outputURL.path
            ]
            return arguments
        }
    }

    public func removeAudioArguments(for request: RemoveAudioRequest) -> [String] {
        [
            "-y",
            "-nostdin",
            "-i", request.inputURL.path,
            "-map", "0:v",
            "-c:v", "copy",
            "-an",
            "-progress", "pipe:1",
            "-nostats",
            request.outputURL.path
        ]
    }

    public func command(ffmpegPath: String, request: EditingRequest) throws -> EditingCommand {
        switch request.method {
        case .streamCopy:
            EditingCommand(executablePath: ffmpegPath, arguments: try streamCopyArguments(for: request))
        }
    }

    public func removeAudioCommand(ffmpegPath: String, request: RemoveAudioRequest) -> EditingCommand {
        EditingCommand(executablePath: ffmpegPath, arguments: removeAudioArguments(for: request))
    }

    public func compressionArguments(for request: CompressionRequest) throws -> [String] {
        let quality = try request.qualitySettings()
        var arguments = [
            "-y",
            "-nostdin",
            "-i", request.inputURL.path,
            "-map", "0:v:0"
        ]

        if request.audioMode == .keep, request.hasAudioStream {
            arguments += ["-map", "0:a:0?"]
        }

        if let scaleFilter = try request.scaleFilter() {
            arguments += ["-vf", scaleFilter]
        }

        arguments += [
            "-c:v", "libx264",
            "-preset", quality.preset.rawValue,
            "-crf", String(quality.crf),
            "-pix_fmt", "yuv420p"
        ]

        if request.audioMode == .keep, request.hasAudioStream {
            arguments += ["-c:a", "aac", "-b:a", "128k"]
        } else {
            arguments += ["-an"]
        }

        arguments += [
            "-movflags", "+faststart",
            "-progress", "pipe:1",
            "-nostats",
            request.outputURL.path
        ]
        return arguments
    }

    public func compressionCommand(ffmpegPath: String, request: CompressionRequest) throws -> EditingCommand {
        EditingCommand(executablePath: ffmpegPath, arguments: try compressionArguments(for: request))
    }

    public func transformArguments(for request: VideoTransformRequest) throws -> [String] {
        guard request.hasVideoStream else { throw VideoTransformValidationError.missingVideoStream }
        let filterChain = try request.filterChain()
        guard !filterChain.contains("\""), !filterChain.contains("'") else {
            throw VideoTransformValidationError.invalidFilterChain
        }

        var arguments = [
            "-y",
            "-nostdin",
            "-i", request.inputURL.path,
            "-map", "0:v:0"
        ]

        if request.hasAudioStream {
            arguments += ["-map", "0:a:0?"]
        }

        arguments += [
            "-vf", filterChain,
            "-c:v", "libx264",
            "-preset", "medium",
            "-crf", "20",
            "-pix_fmt", "yuv420p"
        ]

        if request.hasAudioStream {
            arguments += ["-c:a", "aac", "-b:a", "128k"]
        } else {
            arguments += ["-an"]
        }

        arguments += [
            "-metadata:s:v:0", "rotate=0",
            "-movflags", "+faststart",
            "-progress", "pipe:1",
            "-nostats",
            request.outputURL.path
        ]

        return arguments
    }

    public func transformCommand(ffmpegPath: String, request: VideoTransformRequest) throws -> EditingCommand {
        EditingCommand(executablePath: ffmpegPath, arguments: try transformArguments(for: request))
    }

    public func editPlanArguments(for plan: VideoEditPlan) throws -> [String] {
        try plan.validate()
        let trimPlan = try plan.trimPlan()
        let strategy = try plan.executionStrategy()
        var arguments = ["-y", "-nostdin"]

        if plan.trim != nil {
            arguments += ["-ss", TimeFormatting.ffmpegSeconds(trimPlan.startTime)]
        }

        arguments += ["-i", plan.inputURL.path]

        if plan.trim != nil {
            arguments += ["-t", TimeFormatting.ffmpegSeconds(trimPlan.outputDuration)]
        }

        switch strategy {
        case .streamCopy:
            arguments += ["-map", "0:v:0"]
            if plan.audioMode == .keep, plan.hasAudioStream {
                arguments += ["-map", "0:a:0?"]
                arguments += ["-c", "copy"]
            } else {
                arguments += ["-c:v", "copy", "-an"]
            }

        case .reencode:
            let quality = try plan.qualitySettings()
            arguments += ["-map", "0:v:0"]
            if plan.audioMode == .keep, plan.hasAudioStream {
                arguments += ["-map", "0:a:0?"]
            }
            if let filterChain = try plan.filterChain() {
                guard !filterChain.contains("\""), !filterChain.contains("'") else {
                    throw VideoTransformValidationError.invalidFilterChain
                }
                arguments += ["-vf", filterChain]
            }
            if let speed = plan.speed, plan.audioMode == .keep, plan.hasAudioStream {
                let audioFilter = try speed.audioTempoFilter()
                guard !audioFilter.contains("\""), !audioFilter.contains("'") else {
                    throw VideoSpeedValidationError.invalidSpeed
                }
                arguments += ["-af", audioFilter]
            }
            arguments += [
                "-c:v", "libx264",
                "-preset", quality.preset.rawValue,
                "-crf", String(quality.crf),
                "-pix_fmt", "yuv420p"
            ]
            if plan.audioMode == .keep, plan.hasAudioStream {
                arguments += ["-c:a", "aac", "-b:a", "128k"]
            } else {
                arguments += ["-an"]
            }
            arguments += ["-metadata:s:v:0", "rotate=0", "-movflags", "+faststart"]
        }

        arguments += [
            "-progress", "pipe:1",
            "-nostats",
            plan.outputURL.path
        ]
        return arguments
    }

    public func editPlanCommand(ffmpegPath: String, plan: VideoEditPlan) throws -> EditingCommand {
        EditingCommand(executablePath: ffmpegPath, arguments: try editPlanArguments(for: plan))
    }

    public func speedArguments(for request: VideoSpeedRequest) throws -> [String] {
        try request.validateForExport()
        let videoFilter = request.speed.videoFilter()
        guard !videoFilter.contains("\""), !videoFilter.contains("'") else {
            throw VideoSpeedValidationError.invalidSpeed
        }

        var arguments = [
            "-y",
            "-nostdin",
            "-i", request.inputURL.path,
            "-map", "0:v:0"
        ]

        if request.keepsAudio {
            let audioFilter = try request.speed.audioTempoFilter()
            guard !audioFilter.contains("\""), !audioFilter.contains("'") else {
                throw VideoSpeedValidationError.invalidSpeed
            }
            arguments += ["-map", "0:a:0?"]
            arguments += ["-vf", videoFilter, "-af", audioFilter]
        } else {
            arguments += ["-vf", videoFilter]
        }

        arguments += [
            "-c:v", "libx264",
            "-preset", "medium",
            "-crf", "20",
            "-pix_fmt", "yuv420p"
        ]

        if request.keepsAudio {
            arguments += ["-c:a", "aac", "-b:a", "128k"]
        } else {
            arguments += ["-an"]
        }

        arguments += [
            "-metadata:s:v:0", "rotate=0",
            "-movflags", "+faststart",
            "-progress", "pipe:1",
            "-nostats",
            request.outputURL.path
        ]
        return arguments
    }

    public func speedCommand(ffmpegPath: String, request: VideoSpeedRequest) throws -> EditingCommand {
        EditingCommand(executablePath: ffmpegPath, arguments: try speedArguments(for: request))
    }

    public func frameExportArguments(for request: FrameExportRequest) throws -> [String] {
        try request.validate()
        var arguments = [
            "-y",
            "-nostdin",
            "-i", request.inputURL.path,
            "-ss", FrameExportTimestamp.ffmpegSeconds(request.timestampSeconds),
            "-map", "0:v:0",
            "-frames:v", "1"
        ]
        if request.format == .jpeg {
            guard let jpegQuality = request.jpegQuality else {
                throw FrameExportValidationError.invalidJPEGQuality
            }
            arguments += ["-q:v", String(jpegQuality.ffmpegValue)]
        }
        arguments += [
            "-an",
            "-sn",
            "-dn",
            request.outputURL.path
        ]
        return arguments
    }

    public func frameExportCommand(ffmpegPath: String, request: FrameExportRequest) throws -> EditingCommand {
        EditingCommand(executablePath: ffmpegPath, arguments: try frameExportArguments(for: request))
    }

    public func intervalFrameExportArguments(for request: IntervalFrameExportRequest) throws -> [String] {
        try request.validate()
        let interval = FrameExportTimestamp.compactSeconds(request.interval.seconds)
        let filter = "setpts=PTS-STARTPTS,fps=1/\(interval):start_time=0"
        var arguments = [
            "-y",
            "-nostdin",
            "-ss", FrameExportTimestamp.ffmpegSeconds(request.range.startSeconds),
            "-i", request.inputURL.path,
            "-t", FrameExportTimestamp.ffmpegSeconds(request.range.duration),
            "-map", "0:v:0",
            "-vf", filter,
            "-start_number", "1"
        ]
        if request.format == .jpeg {
            guard let jpegQuality = request.jpegQuality else {
                throw FrameExportValidationError.invalidJPEGQuality
            }
            arguments += ["-q:v", String(jpegQuality.ffmpegValue)]
        }
        arguments += [
            "-an",
            "-sn",
            "-dn",
            "-progress", "pipe:1",
            "-nostats",
            request.outputPattern.path
        ]
        return arguments
    }

    public func intervalFrameExportCommand(ffmpegPath: String, request: IntervalFrameExportRequest) throws -> EditingCommand {
        EditingCommand(executablePath: ffmpegPath, arguments: try intervalFrameExportArguments(for: request))
    }

    public func requestCancellation(state: EditingOperationState) {
        cancellationFlag.set(true)
        Task { @MainActor in
            state.phase = .cancelling
            state.message = "Stopping FFmpeg..."
        }
        processExecutor.cancel()
    }

    public func run(
        ffmpegPath: String,
        ffprobePath: String? = nil,
        request: EditingRequest,
        state: EditingOperationState,
        verifier: (any TrimOutputVerifying)? = nil
    ) async {
        cancellationFlag.set(false)

        await MainActor.run {
            state.phase = .starting
            state.statusText = "Preparing trim..."
            state.message = nil
            state.outputURL = nil
            state.diagnostics = EditingDiagnostics(ffmpegPath: ffmpegPath, startedAt: Date(), lastActivityAt: Date())
        }

        do {
            let command = try command(ffmpegPath: ffmpegPath, request: request)
            try validatePreflight(ffmpegPath: ffmpegPath, request: request)
            if request.trimExecutionMode == .accurate {
                guard try await encoderChecker.supportsLibx264(ffmpegPath: ffmpegPath) else {
                    throw CompressionValidationError.missingLibx264
                }
            }
            try await execute(
                command: command,
                totalDuration: try request.trimPlan().outputDuration,
                outputURL: request.outputURL,
                state: state,
                runningStatus: "Trimming video...",
                completedStatus: request.trimExecutionMode == .accurate ? "Accurate trim complete" : "Fast trim complete"
            )
            let outputVerifier = verifier ?? ffprobePath.map { FFprobeTrimOutputVerifier(ffprobePath: $0) }
            try await outputVerifier?.verify(request: request, outputURL: request.outputURL)
            await MainActor.run {
                if request.trimExecutionMode == .fast {
                    state.message = (state.message ?? "Saved: \(request.outputURL.path)") + "\n\nThe cut may align to nearby keyframes."
                }
            }
        } catch ProcessExecutionError.launchFailed(let message) {
            await fail(state: state, error: VideoEditingError.launchFailed(message))
        } catch {
            await fail(state: state, error: error)
        }
    }

    public func runRemoveAudio(ffmpegPath: String, request: RemoveAudioRequest, state: EditingOperationState) async {
        cancellationFlag.set(false)

        await MainActor.run {
            state.phase = .starting
            state.statusText = "Preparing audio removal..."
            state.message = nil
            state.outputURL = nil
            state.diagnostics = EditingDiagnostics(ffmpegPath: ffmpegPath, startedAt: Date(), lastActivityAt: Date())
        }

        do {
            guard request.hasVideoStream else { throw VideoEditingError.missingVideoStream }
            guard request.hasAudioStream else { throw VideoEditingError.missingAudioStream }
            let command = removeAudioCommand(ffmpegPath: ffmpegPath, request: request)
            try validatePreflight(ffmpegPath: ffmpegPath, inputURL: request.inputURL, outputURL: request.outputURL)
            try await execute(
                command: command,
                totalDuration: request.sourceDuration,
                outputURL: request.outputURL,
                state: state,
                runningStatus: "Removing audio...",
                completedStatus: "Audio removed"
            )
        } catch ProcessExecutionError.launchFailed(let message) {
            await fail(state: state, error: VideoEditingError.launchFailed(message))
        } catch {
            await fail(state: state, error: error)
        }
    }

    public func runCompression(
        ffmpegPath: String,
        ffprobePath: String,
        request: CompressionRequest,
        state: EditingOperationState,
        verifier: (any CompressionOutputVerifying)? = nil
    ) async {
        cancellationFlag.set(false)

        await MainActor.run {
            state.phase = .starting
            state.statusText = "Preparing compression..."
            state.message = nil
            state.outputURL = nil
            state.diagnostics = EditingDiagnostics(ffmpegPath: ffmpegPath, startedAt: Date(), lastActivityAt: Date())
        }

        do {
            guard request.hasVideoStream else { throw CompressionValidationError.missingVideoStream }
            _ = try request.qualitySettings()
            _ = try request.outputDimensions()
            try validatePreflight(ffmpegPath: ffmpegPath, inputURL: request.inputURL, outputURL: request.outputURL)

            await MainActor.run {
                state.statusText = "Checking encoder..."
            }
            try await ensureLibx264(ffmpegPath: ffmpegPath)

            let command = try compressionCommand(ffmpegPath: ffmpegPath, request: request)
            try await execute(
                command: command,
                totalDuration: request.sourceDuration,
                outputURL: request.outputURL,
                state: state,
                runningStatus: "Compressing video...",
                completedStatus: "Compression complete"
            )

            let outputVerifier = verifier ?? FFprobeCompressionOutputVerifier(ffprobePath: ffprobePath)
            try await outputVerifier.verify(request: request, outputURL: request.outputURL)
            let inputSize = fileSystem.fileSize(at: request.inputURL)
            let outputSize = fileSystem.fileSize(at: request.outputURL)
            await MainActor.run {
                state.statusText = "Compression complete"
                state.message = compressionSuccessMessage(inputURL: request.inputURL, outputURL: request.outputURL, inputSize: inputSize, outputSize: outputSize)
            }
        } catch ProcessExecutionError.launchFailed(let message) {
            await fail(state: state, error: VideoEditingError.launchFailed(message))
        } catch {
            await fail(state: state, error: error)
        }
    }

    public func runTransform(
        ffmpegPath: String,
        ffprobePath: String,
        request: VideoTransformRequest,
        state: EditingOperationState,
        verifier: (any VideoTransformOutputVerifying)? = nil
    ) async {
        cancellationFlag.set(false)

        await MainActor.run {
            state.phase = .starting
            state.statusText = "Preparing transformation..."
            state.message = nil
            state.outputURL = nil
            state.diagnostics = EditingDiagnostics(ffmpegPath: ffmpegPath, startedAt: Date(), lastActivityAt: Date())
        }

        do {
            guard request.hasVideoStream else { throw VideoTransformValidationError.missingVideoStream }
            _ = try request.filterChain()
            _ = try request.outputDimensions()
            try validatePreflight(ffmpegPath: ffmpegPath, inputURL: request.inputURL, outputURL: request.outputURL)

            await MainActor.run {
                state.statusText = "Checking encoder..."
            }
            guard try await encoderChecker.supportsLibx264(ffmpegPath: ffmpegPath) else {
                throw VideoTransformValidationError.missingLibx264
            }

            let command = try transformCommand(ffmpegPath: ffmpegPath, request: request)
            try await execute(
                command: command,
                totalDuration: request.sourceDuration,
                outputURL: request.outputURL,
                state: state,
                runningStatus: "Transforming video...",
                completedStatus: "Transformation complete"
            )

            let outputVerifier = verifier ?? FFprobeVideoTransformOutputVerifier(ffprobePath: ffprobePath)
            try await outputVerifier.verify(request: request, outputURL: request.outputURL)
            let inputSize = fileSystem.fileSize(at: request.inputURL)
            let outputSize = fileSystem.fileSize(at: request.outputURL)
            await MainActor.run {
                state.statusText = "Transformation complete"
                state.message = transformSuccessMessage(request: request, inputSize: inputSize, outputSize: outputSize)
            }
        } catch ProcessExecutionError.launchFailed(let message) {
            await fail(state: state, error: VideoEditingError.launchFailed(message))
        } catch {
            await fail(state: state, error: error)
        }
    }

    public func runEditPlan(
        ffmpegPath: String,
        ffprobePath: String,
        plan: VideoEditPlan,
        state: EditingOperationState,
        verifier: (any VideoEditPlanOutputVerifying)? = nil
    ) async {
        cancellationFlag.set(false)

        await MainActor.run {
            state.phase = .starting
            state.statusText = "Preparing combined export..."
            state.message = nil
            state.outputURL = nil
            state.diagnostics = EditingDiagnostics(ffmpegPath: ffmpegPath, startedAt: Date(), lastActivityAt: Date())
        }

        do {
            try plan.validate()
            try validatePreflight(ffmpegPath: ffmpegPath, inputURL: plan.inputURL, outputURL: plan.outputURL)
            let strategy = try plan.executionStrategy()
            if strategy == .reencode {
                await MainActor.run {
                    state.statusText = "Checking encoder..."
                }
                guard try await encoderChecker.supportsLibx264(ffmpegPath: ffmpegPath) else {
                    throw CompressionValidationError.missingLibx264
                }
            }

            let command = try editPlanCommand(ffmpegPath: ffmpegPath, plan: plan)
            try await execute(
                command: command,
                totalDuration: try plan.outputDuration(),
                outputURL: plan.outputURL,
                state: state,
                runningStatus: "Exporting changes...",
                completedStatus: "Export complete"
            )

            let outputVerifier = verifier ?? FFprobeVideoEditPlanOutputVerifier(ffprobePath: ffprobePath)
            try await outputVerifier.verify(plan: plan, outputURL: plan.outputURL)
            let inputSize = fileSystem.fileSize(at: plan.inputURL)
            let outputSize = fileSystem.fileSize(at: plan.outputURL)
            await MainActor.run {
                state.statusText = "Export complete"
                state.message = editPlanSuccessMessage(plan: plan, inputSize: inputSize, outputSize: outputSize)
            }
        } catch ProcessExecutionError.launchFailed(let message) {
            await fail(state: state, error: VideoEditingError.launchFailed(message))
        } catch {
            await fail(state: state, error: error)
        }
    }

    public func runSpeedChange(
        ffmpegPath: String,
        ffprobePath: String,
        request: VideoSpeedRequest,
        state: EditingOperationState,
        verifier: (any VideoSpeedOutputVerifying)? = nil
    ) async {
        cancellationFlag.set(false)

        await MainActor.run {
            state.phase = .starting
            state.statusText = "Preparing speed change..."
            state.message = nil
            state.outputURL = nil
            state.diagnostics = EditingDiagnostics(ffmpegPath: ffmpegPath, startedAt: Date(), lastActivityAt: Date())
        }

        do {
            try request.validateForExport()
            try validatePreflight(ffmpegPath: ffmpegPath, inputURL: request.inputURL, outputURL: request.outputURL)

            await MainActor.run {
                state.statusText = "Checking encoder..."
            }
            guard try await encoderChecker.supportsLibx264(ffmpegPath: ffmpegPath) else {
                throw VideoSpeedValidationError.missingLibx264
            }

            let command = try speedCommand(ffmpegPath: ffmpegPath, request: request)
            try await execute(
                command: command,
                totalDuration: try request.expectedDuration(),
                outputURL: request.outputURL,
                state: state,
                runningStatus: "Changing video speed...",
                completedStatus: "Speed change complete"
            )

            let outputVerifier = verifier ?? FFprobeVideoSpeedOutputVerifier(ffprobePath: ffprobePath)
            try await outputVerifier.verify(request: request, outputURL: request.outputURL)
            let inputSize = fileSystem.fileSize(at: request.inputURL)
            let outputSize = fileSystem.fileSize(at: request.outputURL)
            await MainActor.run {
                state.statusText = "Speed change complete"
                state.message = speedSuccessMessage(request: request, inputSize: inputSize, outputSize: outputSize)
            }
        } catch ProcessExecutionError.launchFailed(let message) {
            await fail(state: state, error: VideoEditingError.launchFailed(message))
        } catch {
            await fail(state: state, error: error)
        }
    }

    public func runFrameExport(
        ffmpegPath: String,
        request: FrameExportRequest,
        state: EditingOperationState,
        verifier: (any FrameExportOutputVerifying)? = nil
    ) async {
        cancellationFlag.set(false)

        await MainActor.run {
            state.phase = .starting
            state.statusText = "Preparing frame export..."
            state.message = nil
            state.outputURL = nil
            state.diagnostics = EditingDiagnostics(ffmpegPath: ffmpegPath, startedAt: Date(), lastActivityAt: Date())
        }

        do {
            try request.validate()
            try validatePreflight(ffmpegPath: ffmpegPath, inputURL: request.inputURL, outputURL: request.outputURL)
            let command = try frameExportCommand(ffmpegPath: ffmpegPath, request: request)
            try await execute(
                command: command,
                totalDuration: 1,
                outputURL: request.outputURL,
                state: state,
                runningStatus: "Exporting frame...",
                completedStatus: "Frame export complete"
            )

            let outputVerifier = verifier ?? NativeFrameExportOutputVerifier()
            let imageInfo = try await outputVerifier.verify(request: request, outputURL: request.outputURL)
            let outputSize = fileSystem.fileSize(at: request.outputURL)
            await MainActor.run {
                state.statusText = "Frame export complete"
                state.message = frameExportSuccessMessage(request: request, imageInfo: imageInfo, outputSize: outputSize)
            }
        } catch ProcessExecutionError.launchFailed(let message) {
            await fail(state: state, error: VideoEditingError.launchFailed(message))
        } catch {
            await fail(state: state, error: error)
        }
    }

    public func runIntervalFrameExport(
        ffmpegPath: String,
        request: IntervalFrameExportRequest,
        state: EditingOperationState,
        verifier: (any IntervalFrameExportOutputVerifying)? = nil
    ) async {
        cancellationFlag.set(false)

        await MainActor.run {
            state.phase = .starting
            state.statusText = "Preparing frame export..."
            state.message = nil
            state.outputURL = nil
            state.diagnostics = EditingDiagnostics(ffmpegPath: ffmpegPath, startedAt: Date(), lastActivityAt: Date())
        }

        var preexistingMatchingFiles: Set<String> = []
        do {
            try request.validate()
            try validateDirectoryPreflight(ffmpegPath: ffmpegPath, inputURL: request.inputURL, outputDirectoryURL: request.outputDirectoryURL)
            let matchingBefore = IntervalFrameExportOutputValidator.matchingFiles(
                in: request.outputDirectoryURL,
                request: request,
                fileSystem: fileSystem
            )
            preexistingMatchingFiles = Set(matchingBefore.map(\.path))
            if !matchingBefore.isEmpty {
                guard request.replaceExisting else {
                    throw FrameExportValidationError.matchingFilesExist(matchingBefore.count)
                }
                matchingBefore.forEach { fileSystem.removeFile(at: $0) }
                preexistingMatchingFiles = []
            }

            let command = try intervalFrameExportCommand(ffmpegPath: ffmpegPath, request: request)
            let result = try await executeSequence(
                command: command,
                totalDuration: request.range.duration,
                outputDirectoryURL: request.outputDirectoryURL,
                state: state,
                runningStatus: "Exporting frames..."
            )

            let matchingAfter = IntervalFrameExportOutputValidator.matchingFiles(
                in: request.outputDirectoryURL,
                request: request,
                fileSystem: fileSystem
            )
            let createdFiles = matchingAfter.filter { !preexistingMatchingFiles.contains($0.path) }
            if cancellationFlag.isSet {
                createdFiles.forEach { fileSystem.removeFile(at: $0) }
                await MainActor.run {
                    state.phase = .cancelled
                    state.statusText = nil
                    state.message = "Operation cancelled."
                }
                return
            }
            guard result.exitCode == 0 else {
                throw VideoEditingError.ffmpegExited(code: result.exitCode)
            }

            await MainActor.run {
                state.statusText = "Verifying images..."
            }
            let outputVerifier = verifier ?? NativeIntervalFrameExportOutputVerifier(fileSystem: fileSystem)
            let exportResult = try await outputVerifier.verify(request: request, files: createdFiles)
            await MainActor.run {
                state.phase = .completed(outputURL: request.outputDirectoryURL, byteCount: 0)
                state.statusText = "Frame export complete"
                state.outputURL = request.outputDirectoryURL
                state.message = intervalFrameExportSuccessMessage(request: request, result: exportResult)
            }
        } catch ProcessExecutionError.launchFailed(let message) {
            await fail(state: state, error: VideoEditingError.launchFailed(message))
        } catch {
            let matchingAfter = IntervalFrameExportOutputValidator.matchingFiles(
                in: request.outputDirectoryURL,
                request: request,
                fileSystem: fileSystem
            )
            matchingAfter
                .filter { !preexistingMatchingFiles.contains($0.path) }
                .forEach { fileSystem.removeFile(at: $0) }
            await fail(state: state, error: error)
        }
    }

    private func validatePreflight(ffmpegPath: String, request: EditingRequest) throws {
        _ = try request.trimPlan()
        try validatePreflight(ffmpegPath: ffmpegPath, inputURL: request.inputURL, outputURL: request.outputURL)
    }

    private func validatePreflight(ffmpegPath: String, inputURL: URL, outputURL: URL) throws {
        if inputURL.standardizedFileURL == outputURL.standardizedFileURL {
            throw VideoEditingError.outputMatchesInput
        }

        let outputDirectory = outputURL.deletingLastPathComponent()
        guard fileSystem.directoryExists(at: outputDirectory) else {
            throw VideoEditingError.missingOutputDirectory(outputDirectory.path)
        }

        guard fileSystem.isWritableDirectory(at: outputDirectory) else {
            throw VideoEditingError.outputDirectoryNotWritable(outputDirectory.path)
        }

        let ffmpegURL = URL(fileURLWithPath: ffmpegPath)
        guard fileSystem.fileExists(at: ffmpegURL) else {
            throw VideoEditingError.missingFFmpegExecutable(ffmpegPath)
        }

        guard fileSystem.isExecutableFile(at: ffmpegURL) else {
            throw VideoEditingError.ffmpegNotExecutable(ffmpegPath)
        }
    }

    private func validateDirectoryPreflight(ffmpegPath: String, inputURL: URL, outputDirectoryURL: URL) throws {
        guard fileSystem.fileExists(at: inputURL) else {
            throw VideoEditingError.inputMissing(inputURL.path)
        }
        guard fileSystem.directoryExists(at: outputDirectoryURL) else {
            throw VideoEditingError.missingOutputDirectory(outputDirectoryURL.path)
        }
        guard fileSystem.isWritableDirectory(at: outputDirectoryURL) else {
            throw VideoEditingError.outputDirectoryNotWritable(outputDirectoryURL.path)
        }
        let ffmpegURL = URL(fileURLWithPath: ffmpegPath)
        guard fileSystem.fileExists(at: ffmpegURL) else {
            throw VideoEditingError.missingFFmpegExecutable(ffmpegPath)
        }
        guard fileSystem.isExecutableFile(at: ffmpegURL) else {
            throw VideoEditingError.ffmpegNotExecutable(ffmpegPath)
        }
    }

    private func validateSuccessfulOutput(at outputURL: URL) throws -> UInt64 {
        guard fileSystem.fileExists(at: outputURL) else {
            throw VideoEditingError.outputMissing(outputURL.path)
        }

        guard let size = fileSystem.fileSize(at: outputURL), size > 0 else {
            throw VideoEditingError.outputEmpty(outputURL.path)
        }

        return size
    }

    private func ensureLibx264(ffmpegPath: String) async throws {
        guard try await encoderChecker.supportsLibx264(ffmpegPath: ffmpegPath) else {
            throw CompressionValidationError.missingLibx264
        }
    }

    private func compressionSuccessMessage(inputURL: URL, outputURL: URL, inputSize: UInt64?, outputSize: UInt64?) -> String {
        var lines: [String] = []
        if let inputSize, let outputSize, inputSize > 0 {
            lines.append("Original size: \(ByteCountFormatter.string(fromByteCount: Int64(inputSize), countStyle: .file))")
            lines.append("Output size: \(ByteCountFormatter.string(fromByteCount: Int64(outputSize), countStyle: .file))")
            let delta = (Double(inputSize) - Double(outputSize)) / Double(inputSize) * 100
            if delta >= 0 {
                lines.append(String(format: "Reduced by: %.1f%%", delta))
            } else {
                lines.append(String(format: "Output is %.1f%% larger than the original.", abs(delta)))
            }
        }
        lines.append("Saved: \(outputURL.path)")
        return lines.joined(separator: "\n")
    }

    private func transformSuccessMessage(request: VideoTransformRequest, inputSize: UInt64?, outputSize: UInt64?) -> String {
        var lines = [
            "Rotation: \(request.rotation.title)",
            "Horizontal flip: \(request.flipHorizontal ? "Yes" : "No")",
            "Vertical flip: \(request.flipVertical ? "Yes" : "No")"
        ]
        if let dimensions = try? request.outputDimensions() {
            lines.append("Output: \(dimensions.width)x\(dimensions.height)")
        }
        if let inputSize, let outputSize, inputSize > 0 {
            lines.append("Original size: \(ByteCountFormatter.string(fromByteCount: Int64(inputSize), countStyle: .file))")
            lines.append("Output size: \(ByteCountFormatter.string(fromByteCount: Int64(outputSize), countStyle: .file))")
        }
        lines.append("Saved: \(request.outputURL.path)")
        return lines.joined(separator: "\n")
    }

    private func editPlanSuccessMessage(plan: VideoEditPlan, inputSize: UInt64?, outputSize: UInt64?) -> String {
        var lines = ["Applied:"]
        lines += editPlanAppliedLines(plan: plan).map { "- \($0)" }
        if let dimensions = try? plan.outputDimensions() {
            lines.append("")
            lines.append("Output:")
            lines.append("\(dimensions.width)x\(dimensions.height)")
        }
        if (try? plan.executionStrategy()) == .reencode {
            lines.append("H.264")
        }
        if let duration = try? plan.outputDuration() {
            lines.append(String(format: "Duration: %.1f seconds", duration))
        }
        if let inputSize, let outputSize, inputSize > 0 {
            lines.append("Original size: \(ByteCountFormatter.string(fromByteCount: Int64(inputSize), countStyle: .file))")
            lines.append("Output size: \(ByteCountFormatter.string(fromByteCount: Int64(outputSize), countStyle: .file))")
        }
        lines.append("")
        lines.append("Saved:")
        lines.append(plan.outputURL.path)
        return lines.joined(separator: "\n")
    }

    private func speedSuccessMessage(request: VideoSpeedRequest, inputSize: UInt64?, outputSize: UInt64?) -> String {
        var lines = [
            "Speed: \(request.speed.filenameLabel)",
            String(format: "Original duration: %.1f seconds", request.sourceDuration)
        ]
        if let expected = try? request.expectedDuration() {
            lines.append(String(format: "Output duration: %.1f seconds", expected))
        }
        lines.append("Video: H.264")
        lines.append("Audio: \(request.keepsAudio ? "AAC" : "Removed")")
        if let inputSize, let outputSize, inputSize > 0 {
            lines.append("Original size: \(ByteCountFormatter.string(fromByteCount: Int64(inputSize), countStyle: .file))")
            lines.append("Output size: \(ByteCountFormatter.string(fromByteCount: Int64(outputSize), countStyle: .file))")
        }
        lines.append("Saved: \(request.outputURL.path)")
        return lines.joined(separator: "\n")
    }

    private func frameExportSuccessMessage(request: FrameExportRequest, imageInfo: FrameImageInfo, outputSize: UInt64?) -> String {
        var lines = [
            "Time: \(FrameExportTimestamp.displayTime(request.timestampSeconds))",
            "Format: \(request.format.title)",
            "Dimensions: \(imageInfo.dimensions.width)x\(imageInfo.dimensions.height)"
        ]
        if let outputSize {
            lines.append("Size: \(ByteCountFormatter.string(fromByteCount: Int64(outputSize), countStyle: .file))")
        }
        lines.append("")
        lines.append("Saved:")
        lines.append(request.outputURL.path)
        return lines.joined(separator: "\n")
    }

    private func intervalFrameExportSuccessMessage(request: IntervalFrameExportRequest, result: IntervalFrameExportResult) -> String {
        [
            "Format: \(request.format.title)",
            "Interval: \(FrameExportTimestamp.compactSeconds(request.interval.seconds)) seconds",
            "Range: \(FrameExportTimestamp.displayTime(request.range.startSeconds)) to \(FrameExportTimestamp.displayTime(request.range.endSeconds))",
            "Images created: \(result.imageCount)",
            "Dimensions: \(result.dimensions.width)x\(result.dimensions.height)",
            "",
            "Saved to:",
            request.outputDirectoryURL.path
        ].joined(separator: "\n")
    }

    private func editPlanAppliedLines(plan: VideoEditPlan) -> [String] {
        var lines: [String] = []
        if let trim = plan.trim {
            if trim.removeStartSeconds > 0 {
                lines.append(String(format: "Removed first %.3g seconds", trim.removeStartSeconds))
            }
            if trim.removeEndSeconds > 0 {
                lines.append(String(format: "Removed last %.3g seconds", trim.removeEndSeconds))
            }
        }
        if let transform = plan.transform {
            if transform.rotation != .none {
                lines.append("Rotated \(transform.rotation.title)")
            }
            if transform.flipHorizontal {
                lines.append("Flipped horizontally")
            }
            if transform.flipVertical {
                lines.append("Flipped vertically")
            }
        }
        if let resize = plan.resize {
            lines.append("Resized to \(resize.resolution.title)")
        }
        if let compression = plan.compression {
            lines.append("Compressed with \(compression.quality.title)")
        }
        if let speed = plan.speed {
            lines.append("Changed speed to \(speed.filenameLabel)")
        }
        if plan.audioMode == .remove {
            lines.append("Removed audio")
        }
        return lines.isEmpty ? ["No changes"] : lines
    }

    private func execute(
        command: EditingCommand,
        totalDuration: TimeInterval,
        outputURL: URL,
        state: EditingOperationState,
        runningStatus: String,
        completedStatus: String
    ) async throws {
        await MainActor.run {
            state.diagnostics = EditingDiagnostics(
                ffmpegPath: command.executablePath,
                arguments: command.arguments,
                startedAt: Date(),
                lastActivityAt: Date()
            )
            state.message = "Overwrite is enabled for existing output files."
        }

        let result = try await processExecutor.run(
            command: command,
            totalDuration: totalDuration,
            onStarted: { [cancellationFlag] in
                Task { @MainActor in
                    if !cancellationFlag.isSet {
                        state.phase = .running(progress: nil)
                        state.statusText = runningStatus
                    }
                }
            },
            onProgress: { [cancellationFlag] progress in
                Task { @MainActor in
                    if !cancellationFlag.isSet {
                        state.phase = .running(progress: progress)
                        state.statusText = runningStatus
                    }
                }
            },
            onActivity: { activity in
                Task { @MainActor in
                    state.diagnostics.processIdentifier = activity.processIdentifier
                    state.diagnostics.lastActivityAt = activity.lastActivityAt
                    if !activity.stderrTail.isEmpty {
                        state.diagnostics.stderrTail = activity.stderrTail
                    }
                }
            }
        )

        await MainActor.run {
            state.diagnostics.stderr = result.stderrText
            state.diagnostics.stderrTail = result.stderrText.isEmpty ? state.diagnostics.stderrTail : result.stderrText
        }

        if cancellationFlag.isSet {
            fileSystem.removeFile(at: outputURL)
            await MainActor.run {
                state.phase = .cancelled
                state.statusText = nil
                state.message = "Operation cancelled."
            }
            return
        }

        guard result.exitCode == 0 else {
            throw VideoEditingError.ffmpegExited(code: result.exitCode)
        }

        let byteCount = try validateSuccessfulOutput(at: outputURL)

        await MainActor.run {
            state.phase = .completed(outputURL: outputURL, byteCount: byteCount)
            state.statusText = completedStatus
            state.message = "Saved: \(outputURL.path)"
            state.outputURL = outputURL
        }
    }

    private func executeSequence(
        command: EditingCommand,
        totalDuration: TimeInterval,
        outputDirectoryURL: URL,
        state: EditingOperationState,
        runningStatus: String
    ) async throws -> ProcessResult {
        await MainActor.run {
            state.diagnostics = EditingDiagnostics(
                ffmpegPath: command.executablePath,
                arguments: command.arguments,
                startedAt: Date(),
                lastActivityAt: Date()
            )
            state.message = "Frames will be written to \(outputDirectoryURL.path). Matching files are replaced only after confirmation."
        }

        let result = try await processExecutor.run(
            command: command,
            totalDuration: totalDuration,
            onStarted: { [cancellationFlag] in
                Task { @MainActor in
                    if !cancellationFlag.isSet {
                        state.phase = .running(progress: nil)
                        state.statusText = runningStatus
                    }
                }
            },
            onProgress: { [cancellationFlag] progress in
                Task { @MainActor in
                    if !cancellationFlag.isSet {
                        state.phase = .running(progress: progress)
                        state.statusText = runningStatus
                    }
                }
            },
            onActivity: { activity in
                Task { @MainActor in
                    state.diagnostics.processIdentifier = activity.processIdentifier
                    state.diagnostics.lastActivityAt = activity.lastActivityAt
                    if !activity.stderrTail.isEmpty {
                        state.diagnostics.stderrTail = activity.stderrTail
                    }
                }
            }
        )

        await MainActor.run {
            state.diagnostics.stderr = result.stderrText
            state.diagnostics.stderrTail = result.stderrText.isEmpty ? state.diagnostics.stderrTail : result.stderrText
        }
        return result
    }

    @MainActor
    private func fail(state: EditingOperationState, error: Error) {
        state.phase = .failed(summary: error.localizedDescription)
        state.statusText = nil
        state.message = error.localizedDescription
    }
}
