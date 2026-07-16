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
        phase.title
    }

    public init() {}
}

public enum VideoEditingError: LocalizedError, Equatable, Sendable {
    case outputMatchesInput
    case missingOutputDirectory(String)
    case outputDirectoryNotWritable(String)
    case missingFFmpegExecutable(String)
    case ffmpegNotExecutable(String)
    case ffmpegExited(code: Int32)
    case outputMissing(String)
    case outputEmpty(String)
    case launchFailed(String)

    public var errorDescription: String? {
        switch self {
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
    func removeFile(at url: URL)
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

    public init(
        processExecutor: any EditingProcessExecuting = FFmpegEditingProcessExecutor(),
        fileSystem: any EditingFileSystemChecking = LocalEditingFileSystem()
    ) {
        self.processExecutor = processExecutor
        self.fileSystem = fileSystem
    }

    public func streamCopyArguments(for request: EditingRequest) throws -> [String] {
        let plan = try request.trimPlan()
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
    }

    public func command(ffmpegPath: String, request: EditingRequest) throws -> EditingCommand {
        switch request.method {
        case .streamCopy:
            EditingCommand(executablePath: ffmpegPath, arguments: try streamCopyArguments(for: request))
        }
    }

    public func requestCancellation(state: EditingOperationState) {
        cancellationFlag.set(true)
        Task { @MainActor in
            state.phase = .cancelling
            state.message = "Stopping FFmpeg..."
        }
        processExecutor.cancel()
    }

    public func run(ffmpegPath: String, request: EditingRequest, state: EditingOperationState) async {
        cancellationFlag.set(false)

        await MainActor.run {
            state.phase = .starting
            state.message = nil
            state.outputURL = nil
            state.diagnostics = EditingDiagnostics(ffmpegPath: ffmpegPath, startedAt: Date(), lastActivityAt: Date())
        }

        do {
            let command = try command(ffmpegPath: ffmpegPath, request: request)
            try validatePreflight(ffmpegPath: ffmpegPath, request: request)

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
                totalDuration: try request.trimPlan().outputDuration,
                onStarted: { [cancellationFlag] in
                    Task { @MainActor in
                        if !cancellationFlag.isSet {
                            state.phase = .running(progress: nil)
                        }
                    }
                },
                onProgress: { [cancellationFlag] progress in
                    Task { @MainActor in
                        if !cancellationFlag.isSet {
                            state.phase = .running(progress: progress)
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
                fileSystem.removeFile(at: request.outputURL)
                await MainActor.run {
                    state.phase = .cancelled
                    state.message = "Operation cancelled."
                }
                return
            }

            guard result.exitCode == 0 else {
                throw VideoEditingError.ffmpegExited(code: result.exitCode)
            }

            let byteCount = try validateSuccessfulOutput(at: request.outputURL)

            await MainActor.run {
                state.phase = .completed(outputURL: request.outputURL, byteCount: byteCount)
                state.message = "Saved: \(request.outputURL.path)"
                state.outputURL = request.outputURL
            }
        } catch ProcessExecutionError.launchFailed(let message) {
            await fail(state: state, error: VideoEditingError.launchFailed(message))
        } catch {
            await fail(state: state, error: error)
        }
    }

    private func validatePreflight(ffmpegPath: String, request: EditingRequest) throws {
        _ = try request.trimPlan()

        if request.inputURL.standardizedFileURL == request.outputURL.standardizedFileURL {
            throw VideoEditingError.outputMatchesInput
        }

        let outputDirectory = request.outputURL.deletingLastPathComponent()
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

    private func validateSuccessfulOutput(at outputURL: URL) throws -> UInt64 {
        guard fileSystem.fileExists(at: outputURL) else {
            throw VideoEditingError.outputMissing(outputURL.path)
        }

        guard let size = fileSystem.fileSize(at: outputURL), size > 0 else {
            throw VideoEditingError.outputEmpty(outputURL.path)
        }

        return size
    }

    @MainActor
    private func fail(state: EditingOperationState, error: Error) {
        state.phase = .failed(summary: error.localizedDescription)
        state.message = error.localizedDescription
    }
}
