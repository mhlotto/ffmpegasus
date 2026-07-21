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

    private var preflightValidator: EditingPreflightValidator {
        EditingPreflightValidator(fileSystem: fileSystem)
    }

    private var outputValidator: EditingOutputFileValidator {
        EditingOutputFileValidator(fileSystem: fileSystem)
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
            try preflightValidator.validate(ffmpegPath: ffmpegPath, request: request)
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
            try preflightValidator.validate(ffmpegPath: ffmpegPath, inputURL: request.inputURL, outputURL: request.outputURL)
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
            try preflightValidator.validate(ffmpegPath: ffmpegPath, inputURL: request.inputURL, outputURL: request.outputURL)

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
                state.message = EditingSuccessMessageFormatter.compressionSuccessMessage(inputURL: request.inputURL, outputURL: request.outputURL, inputSize: inputSize, outputSize: outputSize)
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
            try preflightValidator.validate(ffmpegPath: ffmpegPath, inputURL: request.inputURL, outputURL: request.outputURL)

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
                state.message = EditingSuccessMessageFormatter.transformSuccessMessage(request: request, inputSize: inputSize, outputSize: outputSize)
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
            try preflightValidator.validate(ffmpegPath: ffmpegPath, inputURL: plan.inputURL, outputURL: plan.outputURL)
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
                state.message = EditingSuccessMessageFormatter.editPlanSuccessMessage(plan: plan, inputSize: inputSize, outputSize: outputSize)
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
            try preflightValidator.validate(ffmpegPath: ffmpegPath, inputURL: request.inputURL, outputURL: request.outputURL)

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
                state.message = EditingSuccessMessageFormatter.speedSuccessMessage(request: request, inputSize: inputSize, outputSize: outputSize)
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
            try preflightValidator.validate(ffmpegPath: ffmpegPath, inputURL: request.inputURL, outputURL: request.outputURL)
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
                state.message = EditingSuccessMessageFormatter.frameExportSuccessMessage(request: request, imageInfo: imageInfo, outputSize: outputSize)
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
                state.message = EditingSuccessMessageFormatter.intervalFrameExportSuccessMessage(request: request, result: exportResult)
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

    private func ensureLibx264(ffmpegPath: String) async throws {
        guard try await encoderChecker.supportsLibx264(ffmpegPath: ffmpegPath) else {
            throw CompressionValidationError.missingLibx264
        }
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

        let byteCount = try outputValidator.validateSuccessfulOutput(at: outputURL)

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
