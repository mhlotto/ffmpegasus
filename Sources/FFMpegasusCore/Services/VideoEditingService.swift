import Combine
import Foundation

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
    case verifying
    case completed(outputURL: URL, byteCount: UInt64)
    case failed(summary: String)
    case cancelled

    public var isActive: Bool {
        switch self {
        case .starting, .running, .cancelling, .verifying:
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
            "Running FFmpeg..."
        case .cancelling:
            "Cancelling..."
        case .verifying:
            "Verifying output..."
        case .completed:
            "Operation complete"
        case .failed:
            "Operation failed"
        case .cancelled:
            "Cancelled"
        }
    }

    public var presentationKind: EditingOperationPresentationKind {
        switch self {
        case .idle:
            .neutral
        case .starting, .running, .verifying:
            .running
        case .cancelling, .cancelled:
            .cancelled
        case .completed:
            .success
        case .failed:
            .failure
        }
    }
}

public enum EditingOperationPresentationKind: Equatable, Sendable {
    case neutral
    case running
    case success
    case failure
    case cancelled
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
    case operationInProgress
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
        case .operationInProgress:
            "Another FFmpeg operation is already running."
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

public protocol CropOutputVerifying: Sendable {
    func verify(request: CropRequest, outputURL: URL) async throws
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

public protocol GIFExportOutputVerifying: Sendable {
    func verify(request: GIFExportRequest, outputURL: URL) async throws -> GIFExportResult
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

private enum EditingExecutionOutcome: Equatable, Sendable {
    case completed(byteCount: UInt64)
    case cancelled
}

public final class VideoEditingService: @unchecked Sendable {
    private let processExecutor: any EditingProcessExecuting
    private let fileSystem: any EditingFileSystemChecking
    private let cancellationFlag = CancellationFlag()
    private let encoderChecker: any CompressionEncoderChecking
    private let activeLock = NSLock()
    private var activeOperation = false

    /// This service owns one process executor and one cancellation flag, so it accepts one
    /// operation at a time. The UI also prevents overlap, but the service enforces the same
    /// rule to keep cancellation deterministic if called directly.
    public init(
        processExecutor: any EditingProcessExecuting = FFmpegEditingProcessExecutor(),
        fileSystem: any EditingFileSystemChecking = LocalEditingFileSystem(),
        encoderChecker: any CompressionEncoderChecking = FFmpegCompressionEncoderChecker()
    ) {
        self.processExecutor = processExecutor
        self.fileSystem = fileSystem
        self.encoderChecker = encoderChecker
    }

    private var preflightValidator: EditingPreflightValidator {
        EditingPreflightValidator(fileSystem: fileSystem)
    }

    private var outputValidator: EditingOutputFileValidator {
        EditingOutputFileValidator(fileSystem: fileSystem)
    }

    private func beginOperation() -> Bool {
        activeLock.lock()
        defer { activeLock.unlock() }
        guard !activeOperation else { return false }
        activeOperation = true
        cancellationFlag.set(false)
        return true
    }

    private func endOperation() {
        activeLock.lock()
        activeOperation = false
        activeLock.unlock()
    }

    public func requestCancellation(state: EditingOperationState) {
        cancellationFlag.set(true)
        Task { @MainActor in
            state.phase = .cancelling
            state.statusText = "Cancelling..."
            state.message = "Cancellation requested. Stopping FFmpeg..."
        }
        processExecutor.cancel()
    }

    @discardableResult
    public func run(
        ffmpegPath: String,
        ffprobePath: String? = nil,
        request: EditingRequest,
        state: EditingOperationState,
        verifier: (any TrimOutputVerifying)? = nil
    ) async -> Bool {
        guard beginOperation() else {
            return false
        }
        defer { endOperation() }

        await MainActor.run {
            state.phase = .starting
            state.statusText = "Preparing trim..."
            state.message = nil
            state.outputURL = nil
            state.diagnostics = EditingDiagnostics(ffmpegPath: ffmpegPath, startedAt: Date(), lastActivityAt: Date())
        }

        do {
            let command = try command(ffmpegPath: ffmpegPath, request: request)
            try preflightValidator.validate(ffmpegPath: ffmpegPath, request: request)
            try validateOutputExtension(outputURL: request.outputURL, profile: request.exportProfile)
            if request.effectiveTrimExecutionMode == .accurate {
                try await ensureExportProfile(ffmpegPath: ffmpegPath, profile: request.exportProfile)
            }
            let outcome = try await execute(
                command: command,
                totalDuration: try request.trimPlan().outputDuration,
                outputURL: request.outputURL,
                state: state,
                runningStatus: "Trimming video..."
            )
            guard case .completed(let byteCount) = outcome else { return true }
            let outputVerifier = verifier ?? ffprobePath.map { FFprobeTrimOutputVerifier(ffprobePath: $0) }
            await markVerifying(state: state)
            try await outputVerifier?.verify(request: request, outputURL: request.outputURL)
            await MainActor.run {
                let completedStatus = request.effectiveTrimExecutionMode == .accurate ? "Accurate trim complete" : "Fast trim complete"
                state.phase = .completed(outputURL: request.outputURL, byteCount: byteCount)
                state.statusText = completedStatus
                state.outputURL = request.outputURL
                state.message = "Saved: \(request.outputURL.path)"
                if request.effectiveTrimExecutionMode == .fast {
                    state.message = (state.message ?? "Saved: \(request.outputURL.path)") + "\n\nThe cut may align to nearby keyframes."
                }
            }
        } catch ProcessExecutionError.launchFailed(let message) {
            await fail(state: state, error: VideoEditingError.launchFailed(message))
        } catch ProcessExecutionError.cancelled {
            await markCancelled(state: state, outputURL: request.outputURL)
        } catch {
            await fail(state: state, error: error)
        }
        return true
    }

    @discardableResult
    public func runRemoveAudio(ffmpegPath: String, request: RemoveAudioRequest, state: EditingOperationState) async -> Bool {
        guard beginOperation() else {
            return false
        }
        defer { endOperation() }

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
            try preflightValidator.validate(ffmpegPath: ffmpegPath, inputURL: request.inputURL, outputURL: request.outputURL)
            let outcome = try await execute(
                command: command,
                totalDuration: request.sourceDuration,
                outputURL: request.outputURL,
                state: state,
                runningStatus: "Removing audio..."
            )
            guard case .completed(let byteCount) = outcome else { return true }
            await MainActor.run {
                state.phase = .completed(outputURL: request.outputURL, byteCount: byteCount)
                state.statusText = "Audio removed"
                state.outputURL = request.outputURL
                state.message = "Saved: \(request.outputURL.path)"
            }
        } catch ProcessExecutionError.launchFailed(let message) {
            await fail(state: state, error: VideoEditingError.launchFailed(message))
        } catch ProcessExecutionError.cancelled {
            await markCancelled(state: state, outputURL: request.outputURL)
        } catch {
            await fail(state: state, error: error)
        }
        return true
    }

    @discardableResult
    public func runCompression(
        ffmpegPath: String,
        ffprobePath: String,
        request: CompressionRequest,
        state: EditingOperationState,
        verifier: (any CompressionOutputVerifying)? = nil
    ) async -> Bool {
        guard beginOperation() else {
            return false
        }
        defer { endOperation() }

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
            try preflightValidator.validate(ffmpegPath: ffmpegPath, inputURL: request.inputURL, outputURL: request.outputURL)
            try validateOutputExtension(outputURL: request.outputURL, profile: request.exportProfile)

            await MainActor.run {
                state.statusText = "Checking encoder..."
            }
            try await ensureExportProfile(ffmpegPath: ffmpegPath, profile: request.exportProfile)

            let command = try compressionCommand(ffmpegPath: ffmpegPath, request: request)
            let outcome = try await execute(
                command: command,
                totalDuration: request.sourceDuration,
                outputURL: request.outputURL,
                state: state,
                runningStatus: "Compressing video..."
            )
            guard case .completed(let byteCount) = outcome else { return true }

            let outputVerifier = verifier ?? FFprobeCompressionOutputVerifier(ffprobePath: ffprobePath)
            await markVerifying(state: state)
            try await outputVerifier.verify(request: request, outputURL: request.outputURL)
            let inputSize = fileSystem.fileSize(at: request.inputURL)
            let outputSize = fileSystem.fileSize(at: request.outputURL)
            await MainActor.run {
                state.phase = .completed(outputURL: request.outputURL, byteCount: byteCount)
                state.statusText = "Compression complete"
                state.outputURL = request.outputURL
                state.message = EditingSuccessMessageFormatter.compressionSuccessMessage(inputURL: request.inputURL, outputURL: request.outputURL, inputSize: inputSize, outputSize: outputSize)
            }
        } catch ProcessExecutionError.launchFailed(let message) {
            await fail(state: state, error: VideoEditingError.launchFailed(message))
        } catch ProcessExecutionError.cancelled {
            await markCancelled(state: state, outputURL: request.outputURL)
        } catch {
            await fail(state: state, error: error)
        }
        return true
    }

    @discardableResult
    public func runTransform(
        ffmpegPath: String,
        ffprobePath: String,
        request: VideoTransformRequest,
        state: EditingOperationState,
        verifier: (any VideoTransformOutputVerifying)? = nil
    ) async -> Bool {
        guard beginOperation() else {
            return false
        }
        defer { endOperation() }

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
            try preflightValidator.validate(ffmpegPath: ffmpegPath, inputURL: request.inputURL, outputURL: request.outputURL)
            try validateOutputExtension(outputURL: request.outputURL, profile: request.exportProfile)

            await MainActor.run {
                state.statusText = "Checking encoder..."
            }
            try await ensureExportProfile(ffmpegPath: ffmpegPath, profile: request.exportProfile)

            let command = try transformCommand(ffmpegPath: ffmpegPath, request: request)
            let outcome = try await execute(
                command: command,
                totalDuration: request.sourceDuration,
                outputURL: request.outputURL,
                state: state,
                runningStatus: "Transforming video..."
            )
            guard case .completed(let byteCount) = outcome else { return true }

            let outputVerifier = verifier ?? FFprobeVideoTransformOutputVerifier(ffprobePath: ffprobePath)
            await markVerifying(state: state)
            try await outputVerifier.verify(request: request, outputURL: request.outputURL)
            let inputSize = fileSystem.fileSize(at: request.inputURL)
            let outputSize = fileSystem.fileSize(at: request.outputURL)
            await MainActor.run {
                state.phase = .completed(outputURL: request.outputURL, byteCount: byteCount)
                state.statusText = "Transformation complete"
                state.outputURL = request.outputURL
                state.message = EditingSuccessMessageFormatter.transformSuccessMessage(request: request, inputSize: inputSize, outputSize: outputSize)
            }
        } catch ProcessExecutionError.launchFailed(let message) {
            await fail(state: state, error: VideoEditingError.launchFailed(message))
        } catch ProcessExecutionError.cancelled {
            await markCancelled(state: state, outputURL: request.outputURL)
        } catch {
            await fail(state: state, error: error)
        }
        return true
    }

    @discardableResult
    public func runCrop(
        ffmpegPath: String,
        ffprobePath: String,
        request: CropRequest,
        state: EditingOperationState,
        verifier: (any CropOutputVerifying)? = nil
    ) async -> Bool {
        guard beginOperation() else {
            return false
        }
        defer { endOperation() }

        await MainActor.run {
            state.phase = .starting
            state.statusText = "Preparing crop export..."
            state.message = nil
            state.outputURL = nil
            state.diagnostics = EditingDiagnostics(ffmpegPath: ffmpegPath, startedAt: Date(), lastActivityAt: Date())
        }

        do {
            guard request.hasVideoStream else { throw CropValidationError.missingVideoStream }
            try request.validate()
            try preflightValidator.validate(ffmpegPath: ffmpegPath, inputURL: request.inputURL, outputURL: request.outputURL)
            try validateOutputExtension(outputURL: request.outputURL, profile: request.exportProfile)
            try await ensureExportProfile(ffmpegPath: ffmpegPath, profile: request.exportProfile)
            let inputSize = fileSystem.fileSize(at: request.inputURL)
            let command = try cropCommand(ffmpegPath: ffmpegPath, request: request)
            let outcome = try await execute(
                command: command,
                totalDuration: request.sourceDuration,
                outputURL: request.outputURL,
                state: state,
                runningStatus: "Cropping video..."
            )
            guard case .completed(let outputSize) = outcome else { return true }

            let outputVerifier = verifier ?? FFprobeCropOutputVerifier(ffprobePath: ffprobePath)
            await markVerifying(state: state)
            try await outputVerifier.verify(request: request, outputURL: request.outputURL)
            await MainActor.run {
                state.phase = .completed(outputURL: request.outputURL, byteCount: outputSize)
                state.statusText = "Crop export complete"
                state.outputURL = request.outputURL
                state.message = EditingSuccessMessageFormatter.cropSuccessMessage(request: request, inputSize: inputSize, outputSize: outputSize)
            }
        } catch ProcessExecutionError.launchFailed(let message) {
            await fail(state: state, error: VideoEditingError.launchFailed(message))
        } catch ProcessExecutionError.cancelled {
            await markCancelled(state: state, outputURL: request.outputURL)
        } catch {
            await fail(state: state, error: error)
        }
        return true
    }

    @discardableResult
    public func runEditPlan(
        ffmpegPath: String,
        ffprobePath: String,
        plan: VideoEditPlan,
        state: EditingOperationState,
        verifier: (any VideoEditPlanOutputVerifying)? = nil
    ) async -> Bool {
        guard beginOperation() else {
            return false
        }
        defer { endOperation() }

        await MainActor.run {
            state.phase = .starting
            state.statusText = "Preparing combined export..."
            state.message = nil
            state.outputURL = nil
            state.diagnostics = EditingDiagnostics(ffmpegPath: ffmpegPath, startedAt: Date(), lastActivityAt: Date())
        }

        do {
            try plan.validate()
            try preflightValidator.validate(ffmpegPath: ffmpegPath, inputURL: plan.inputURL, outputURL: plan.outputURL)
            try validateOutputExtension(outputURL: plan.outputURL, profile: plan.exportProfile)
            let strategy = try plan.executionStrategy()
            if strategy == .reencode {
                await MainActor.run {
                    state.statusText = "Checking encoder..."
                }
                try await ensureExportProfile(ffmpegPath: ffmpegPath, profile: plan.exportProfile)
            }

            let command = try editPlanCommand(ffmpegPath: ffmpegPath, plan: plan)
            let outcome = try await execute(
                command: command,
                totalDuration: try plan.outputDuration(),
                outputURL: plan.outputURL,
                state: state,
                runningStatus: "Exporting changes..."
            )
            guard case .completed(let byteCount) = outcome else { return true }

            let outputVerifier = verifier ?? FFprobeVideoEditPlanOutputVerifier(ffprobePath: ffprobePath)
            await markVerifying(state: state)
            try await outputVerifier.verify(plan: plan, outputURL: plan.outputURL)
            let inputSize = fileSystem.fileSize(at: plan.inputURL)
            let outputSize = fileSystem.fileSize(at: plan.outputURL)
            await MainActor.run {
                state.phase = .completed(outputURL: plan.outputURL, byteCount: byteCount)
                state.statusText = "Export complete"
                state.outputURL = plan.outputURL
                state.message = EditingSuccessMessageFormatter.editPlanSuccessMessage(plan: plan, inputSize: inputSize, outputSize: outputSize)
            }
        } catch ProcessExecutionError.launchFailed(let message) {
            await fail(state: state, error: VideoEditingError.launchFailed(message))
        } catch ProcessExecutionError.cancelled {
            await markCancelled(state: state, outputURL: plan.outputURL)
        } catch {
            await fail(state: state, error: error)
        }
        return true
    }

    @discardableResult
    public func runSpeedChange(
        ffmpegPath: String,
        ffprobePath: String,
        request: VideoSpeedRequest,
        state: EditingOperationState,
        verifier: (any VideoSpeedOutputVerifying)? = nil
    ) async -> Bool {
        guard beginOperation() else {
            return false
        }
        defer { endOperation() }

        await MainActor.run {
            state.phase = .starting
            state.statusText = "Preparing speed change..."
            state.message = nil
            state.outputURL = nil
            state.diagnostics = EditingDiagnostics(ffmpegPath: ffmpegPath, startedAt: Date(), lastActivityAt: Date())
        }

        do {
            try request.validateForExport()
            try preflightValidator.validate(ffmpegPath: ffmpegPath, inputURL: request.inputURL, outputURL: request.outputURL)
            try validateOutputExtension(outputURL: request.outputURL, profile: request.exportProfile)

            await MainActor.run {
                state.statusText = "Checking encoder..."
            }
            try await ensureExportProfile(ffmpegPath: ffmpegPath, profile: request.exportProfile)

            let command = try speedCommand(ffmpegPath: ffmpegPath, request: request)
            let outcome = try await execute(
                command: command,
                totalDuration: try request.expectedDuration(),
                outputURL: request.outputURL,
                state: state,
                runningStatus: "Changing video speed..."
            )
            guard case .completed(let byteCount) = outcome else { return true }

            let outputVerifier = verifier ?? FFprobeVideoSpeedOutputVerifier(ffprobePath: ffprobePath)
            await markVerifying(state: state)
            try await outputVerifier.verify(request: request, outputURL: request.outputURL)
            let inputSize = fileSystem.fileSize(at: request.inputURL)
            let outputSize = fileSystem.fileSize(at: request.outputURL)
            await MainActor.run {
                state.phase = .completed(outputURL: request.outputURL, byteCount: byteCount)
                state.statusText = "Speed change complete"
                state.outputURL = request.outputURL
                state.message = EditingSuccessMessageFormatter.speedSuccessMessage(request: request, inputSize: inputSize, outputSize: outputSize)
            }
        } catch ProcessExecutionError.launchFailed(let message) {
            await fail(state: state, error: VideoEditingError.launchFailed(message))
        } catch ProcessExecutionError.cancelled {
            await markCancelled(state: state, outputURL: request.outputURL)
        } catch {
            await fail(state: state, error: error)
        }
        return true
    }

    @discardableResult
    public func runFrameExport(
        ffmpegPath: String,
        request: FrameExportRequest,
        state: EditingOperationState,
        verifier: (any FrameExportOutputVerifying)? = nil
    ) async -> Bool {
        guard beginOperation() else {
            return false
        }
        defer { endOperation() }

        await MainActor.run {
            state.phase = .starting
            state.statusText = "Preparing frame export..."
            state.message = nil
            state.outputURL = nil
            state.diagnostics = EditingDiagnostics(ffmpegPath: ffmpegPath, startedAt: Date(), lastActivityAt: Date())
        }

        do {
            try request.validate()
            try preflightValidator.validate(ffmpegPath: ffmpegPath, inputURL: request.inputURL, outputURL: request.outputURL)
            let command = try frameExportCommand(ffmpegPath: ffmpegPath, request: request)
            let outcome = try await execute(
                command: command,
                totalDuration: 1,
                outputURL: request.outputURL,
                state: state,
                runningStatus: "Exporting frame..."
            )
            guard case .completed(let byteCount) = outcome else { return true }

            let outputVerifier = verifier ?? NativeFrameExportOutputVerifier()
            await markVerifying(state: state)
            let imageInfo = try await outputVerifier.verify(request: request, outputURL: request.outputURL)
            let outputSize = fileSystem.fileSize(at: request.outputURL)
            await MainActor.run {
                state.phase = .completed(outputURL: request.outputURL, byteCount: byteCount)
                state.statusText = "Frame export complete"
                state.outputURL = request.outputURL
                state.message = EditingSuccessMessageFormatter.frameExportSuccessMessage(request: request, imageInfo: imageInfo, outputSize: outputSize)
            }
        } catch ProcessExecutionError.launchFailed(let message) {
            await fail(state: state, error: VideoEditingError.launchFailed(message))
        } catch ProcessExecutionError.cancelled {
            await markCancelled(state: state, outputURL: request.outputURL)
        } catch {
            await fail(state: state, error: error)
        }
        return true
    }

    @discardableResult
    public func runIntervalFrameExport(
        ffmpegPath: String,
        request: IntervalFrameExportRequest,
        state: EditingOperationState,
        verifier: (any IntervalFrameExportOutputVerifying)? = nil
    ) async -> Bool {
        guard beginOperation() else {
            return false
        }
        defer { endOperation() }

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
            try preflightValidator.validateDirectory(ffmpegPath: ffmpegPath, inputURL: request.inputURL, outputDirectoryURL: request.outputDirectoryURL)
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
                    state.outputURL = nil
                }
                return true
            }
            guard result.exitCode == 0 else {
                throw VideoEditingError.ffmpegExited(code: result.exitCode)
            }

            await MainActor.run {
                state.phase = .verifying
                state.statusText = "Verifying images..."
            }
            let outputVerifier = verifier ?? NativeIntervalFrameExportOutputVerifier(fileSystem: fileSystem)
            let exportResult = try await outputVerifier.verify(request: request, files: createdFiles)
            await MainActor.run {
                state.phase = .completed(outputURL: request.outputDirectoryURL, byteCount: 0)
                state.statusText = "Frame export complete"
                state.outputURL = request.outputDirectoryURL
                state.message = EditingSuccessMessageFormatter.intervalFrameExportSuccessMessage(request: request, result: exportResult)
            }
        } catch ProcessExecutionError.launchFailed(let message) {
            await fail(state: state, error: VideoEditingError.launchFailed(message))
        } catch ProcessExecutionError.cancelled {
            let matchingAfter = IntervalFrameExportOutputValidator.matchingFiles(
                in: request.outputDirectoryURL,
                request: request,
                fileSystem: fileSystem
            )
            matchingAfter
                .filter { !preexistingMatchingFiles.contains($0.path) }
                .forEach { fileSystem.removeFile(at: $0) }
            await markCancelled(state: state)
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
        return true
    }

    @discardableResult
    public func runGIFExport(
        ffmpegPath: String,
        request: GIFExportRequest,
        state: EditingOperationState,
        verifier: (any GIFExportOutputVerifying)? = nil
    ) async -> Bool {
        guard beginOperation() else {
            return false
        }
        defer { endOperation() }

        await MainActor.run {
            state.phase = .starting
            state.statusText = "Preparing GIF export..."
            state.message = nil
            state.outputURL = nil
            state.diagnostics = EditingDiagnostics(ffmpegPath: ffmpegPath, startedAt: Date(), lastActivityAt: Date())
        }

        do {
            try request.validate()
            try preflightValidator.validate(ffmpegPath: ffmpegPath, inputURL: request.inputURL, outputURL: request.outputURL)
            let command = try gifExportCommand(ffmpegPath: ffmpegPath, request: request)
            let outcome = try await execute(
                command: command,
                totalDuration: request.outputDuration(),
                outputURL: request.outputURL,
                state: state,
                runningStatus: "Exporting GIF..."
            )
            guard case .completed = outcome else { return true }

            let outputVerifier = verifier ?? NativeGIFExportOutputVerifier(fileSystem: fileSystem)
            await markVerifying(state: state)
            let result = try await outputVerifier.verify(request: request, outputURL: request.outputURL)
            await MainActor.run {
                state.phase = .completed(outputURL: request.outputURL, byteCount: result.byteCount ?? 0)
                state.statusText = "GIF export complete"
                state.outputURL = request.outputURL
                state.message = EditingSuccessMessageFormatter.gifExportSuccessMessage(request: request, result: result)
            }
        } catch ProcessExecutionError.launchFailed(let message) {
            await fail(state: state, error: VideoEditingError.launchFailed(message))
        } catch ProcessExecutionError.cancelled {
            await markCancelled(state: state, outputURL: request.outputURL)
        } catch {
            await fail(state: state, error: error)
        }
        return true
    }

    private func ensureLibx264(ffmpegPath: String) async throws {
        guard try await encoderChecker.supportsLibx264(ffmpegPath: ffmpegPath) else {
            throw CompressionValidationError.missingLibx264
        }
    }

    private func ensureExportProfile(ffmpegPath: String, profile: ExportProfile) async throws {
        let support = try await encoderChecker.capabilities(ffmpegPath: ffmpegPath).support(for: profile)
        guard support.isSupported else {
            throw ExportProfileValidationError.missingEncoder(profile: profile, encoder: support.missingEncoders.first ?? profile.requiredVideoEncoder)
        }
    }

    private func validateOutputExtension(outputURL: URL, profile: ExportProfile) throws {
        let actual = outputURL.pathExtension.lowercased()
        guard actual == profile.fileExtension else {
            throw ExportProfileValidationError.wrongExtension(expected: profile.fileExtension, actual: actual)
        }
    }


    private func execute(
        command: EditingCommand,
        totalDuration: TimeInterval,
        outputURL: URL,
        state: EditingOperationState,
        runningStatus: String
    ) async throws -> EditingExecutionOutcome {
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
            await markCancelled(state: state)
            return .cancelled
        }

        guard result.exitCode == 0 else {
            throw VideoEditingError.ffmpegExited(code: result.exitCode)
        }

        let byteCount = try outputValidator.validateSuccessfulOutput(at: outputURL)
        await MainActor.run {
            state.phase = .verifying
            state.statusText = "Verifying output..."
        }
        return .completed(byteCount: byteCount)
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
    private func markVerifying(state: EditingOperationState) {
        state.phase = .verifying
        state.statusText = "Verifying output..."
    }

    private func markCancelled(state: EditingOperationState, outputURL: URL? = nil) async {
        if let outputURL {
            fileSystem.removeFile(at: outputURL)
        }
        await MainActor.run {
            state.phase = .cancelled
            state.statusText = "Cancelled"
            state.message = "Operation cancelled."
            state.outputURL = nil
        }
    }

    @MainActor
    private func fail(state: EditingOperationState, error: Error) {
        if case .cancelled = state.phase {
            return
        }
        state.phase = .failed(summary: error.localizedDescription)
        state.statusText = nil
        state.message = error.localizedDescription
        state.outputURL = nil
    }
}
