import XCTest
@testable import FFMpegasusCore

final class FakeEditingProcessExecutor: EditingProcessExecuting, @unchecked Sendable {
    var result = ProcessResult(exitCode: 0)
    var thrownError: Error?
    var progressValues: [Double] = []
    var delayNanoseconds: UInt64 = 0
    var waitForCancel = false
    private(set) var command: EditingCommand?
    private(set) var didStart = false
    private(set) var didCancel = false

    func run(
        command: EditingCommand,
        totalDuration: TimeInterval,
        onStarted: @escaping @Sendable () -> Void,
        onProgress: @escaping @Sendable (Double) -> Void,
        onActivity: @escaping @Sendable (ProcessActivity) -> Void
    ) async throws -> ProcessResult {
        self.command = command
        if let thrownError {
            throw thrownError
        }

        didStart = true
        onStarted()
        onActivity(ProcessActivity(processIdentifier: 123, stderrTail: "", lastActivityAt: Date()))
        for progress in progressValues {
            onProgress(progress)
        }

        if waitForCancel {
            while !didCancel {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
        } else if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }

        return result
    }

    func cancel() {
        didCancel = true
    }
}

final class FakeEditingFileSystem: EditingFileSystemChecking, @unchecked Sendable {
    var files = Set<String>()
    var directories = Set<String>()
    var writableDirectories = Set<String>()
    var executables = Set<String>()
    var sizes: [String: UInt64] = [:]
    private(set) var removedFiles: [String] = []

    func fileExists(at url: URL) -> Bool {
        files.contains(url.path)
    }

    func directoryExists(at url: URL) -> Bool {
        directories.contains(url.path)
    }

    func isExecutableFile(at url: URL) -> Bool {
        executables.contains(url.path)
    }

    func isWritableDirectory(at url: URL) -> Bool {
        writableDirectories.contains(url.path)
    }

    func fileSize(at url: URL) -> UInt64? {
        sizes[url.path]
    }

    func removeFile(at url: URL) {
        removedFiles.append(url.path)
        files.remove(url.path)
        sizes[url.path] = nil
    }
}

@MainActor
final class VideoEditingServiceTests: XCTestCase {
    private let ffmpegPath = "/opt/homebrew/bin/ffmpeg"

    func testOperationStateTransitionsToCompletedForSuccessfulOutput() async {
        let process = FakeEditingProcessExecutor()
        process.progressValues = [0.5]
        process.delayNanoseconds = 20_000_000
        let fileSystem = validFileSystem(outputSize: 4096)
        let state = EditingOperationState()
        let service = VideoEditingService(processExecutor: process, fileSystem: fileSystem)

        let task = Task {
            await service.run(ffmpegPath: ffmpegPath, request: request(), state: state)
        }

        try? await Task.sleep(nanoseconds: 5_000_000)
        XCTAssertTrue(state.isRunning)
        XCTAssertNotEqual(state.phase, .idle)

        await task.value

        XCTAssertEqual(state.phase, .completed(outputURL: outputURL(), byteCount: 4096))
        XCTAssertEqual(state.outputURL, outputURL())
        XCTAssertEqual(process.command?.executablePath, ffmpegPath)
    }

    func testExitZeroWithMissingOutputFails() async {
        let state = await runWith(outputExists: false, outputSize: nil, result: ProcessResult(exitCode: 0))

        guard case .failed(let summary) = state.phase else {
            return XCTFail("Expected failed state")
        }
        XCTAssertTrue(summary.contains("no output file was created"))
    }

    func testExitZeroWithZeroByteOutputFails() async {
        let state = await runWith(outputExists: true, outputSize: 0, result: ProcessResult(exitCode: 0))

        guard case .failed(let summary) = state.phase else {
            return XCTFail("Expected failed state")
        }
        XCTAssertTrue(summary.contains("output file is empty"))
    }

    func testLaunchFailureFailsVisibly() async {
        let process = FakeEditingProcessExecutor()
        process.thrownError = ProcessExecutionError.launchFailed("permission denied")
        let state = await runWith(process: process, outputExists: false, outputSize: nil)

        guard case .failed(let summary) = state.phase else {
            return XCTFail("Expected failed state")
        }
        XCTAssertTrue(summary.contains("Could not start FFmpeg"))
    }

    func testNonzeroExitFailsWithStderrDiagnostics() async {
        let stderr = "bad input".data(using: .utf8)!
        let state = await runWith(outputExists: false, outputSize: nil, result: ProcessResult(exitCode: 1, stderr: stderr))

        guard case .failed(let summary) = state.phase else {
            return XCTFail("Expected failed state")
        }
        XCTAssertTrue(summary.contains("exit code 1"))
        XCTAssertEqual(state.diagnostics.stderr, "bad input")
    }

    func testCancellationTerminatesProcessAndRemovesIncompleteOutput() async {
        let process = FakeEditingProcessExecutor()
        process.waitForCancel = true
        let fileSystem = validFileSystem(outputSize: 12)
        let state = EditingOperationState()
        let service = VideoEditingService(processExecutor: process, fileSystem: fileSystem)

        let task = Task {
            await service.run(ffmpegPath: ffmpegPath, request: request(), state: state)
        }

        try? await Task.sleep(nanoseconds: 5_000_000)
        service.requestCancellation(state: state)
        await task.value

        XCTAssertTrue(process.didCancel)
        XCTAssertEqual(state.phase, .cancelled)
        XCTAssertEqual(fileSystem.removedFiles, [outputURL().path])
    }

    func testRejectsInputAndOutputPathsBeingIdentical() async {
        let state = await runWith(request: request(outputURL: inputURL()))

        guard case .failed(let summary) = state.phase else {
            return XCTFail("Expected failed state")
        }
        XCTAssertTrue(summary.contains("different from the input"))
    }

    func testRejectsMissingFFmpegExecutable() async {
        let fileSystem = validFileSystem(outputSize: 100)
        fileSystem.files.remove(ffmpegPath)
        let state = await runWith(fileSystem: fileSystem)

        guard case .failed(let summary) = state.phase else {
            return XCTFail("Expected failed state")
        }
        XCTAssertTrue(summary.contains("was not found"))
    }

    func testRejectsNonWritableOutputDirectory() async {
        let fileSystem = validFileSystem(outputSize: 100)
        fileSystem.writableDirectories.remove("/tmp")
        let state = await runWith(fileSystem: fileSystem)

        guard case .failed(let summary) = state.phase else {
            return XCTFail("Expected failed state")
        }
        XCTAssertTrue(summary.contains("not writable"))
    }

    func testRejectsNonExecutableFFmpegPath() async {
        let fileSystem = validFileSystem(outputSize: 100)
        fileSystem.executables.remove(ffmpegPath)
        let state = await runWith(fileSystem: fileSystem)

        guard case .failed(let summary) = state.phase else {
            return XCTFail("Expected failed state")
        }
        XCTAssertTrue(summary.contains("not executable"))
    }

    private func runWith(
        process: FakeEditingProcessExecutor = FakeEditingProcessExecutor(),
        fileSystem: FakeEditingFileSystem? = nil,
        request: EditingRequest? = nil,
        outputExists: Bool = true,
        outputSize: UInt64? = 100,
        result: ProcessResult = ProcessResult(exitCode: 0)
    ) async -> EditingOperationState {
        process.result = result
        let fileSystem = fileSystem ?? validFileSystem(outputExists: outputExists, outputSize: outputSize)
        let state = EditingOperationState()
        let service = VideoEditingService(processExecutor: process, fileSystem: fileSystem)

        await service.run(ffmpegPath: ffmpegPath, request: request ?? self.request(), state: state)
        return state
    }

    private func validFileSystem(outputExists: Bool = true, outputSize: UInt64?) -> FakeEditingFileSystem {
        let fileSystem = FakeEditingFileSystem()
        fileSystem.directories = ["/tmp", "/opt/homebrew/bin"]
        fileSystem.writableDirectories = ["/tmp"]
        fileSystem.files = [ffmpegPath]
        fileSystem.executables = [ffmpegPath]
        if outputExists {
            fileSystem.files.insert(outputURL().path)
        }
        if let outputSize {
            fileSystem.sizes[outputURL().path] = outputSize
        }
        return fileSystem
    }

    private func request(outputURL: URL? = nil) -> EditingRequest {
        EditingRequest(
            inputURL: inputURL(),
            outputURL: outputURL ?? self.outputURL(),
            sourceDuration: 100,
            removeStartSeconds: 10,
            removeEndSeconds: 15,
            mode: .trimBoth,
            method: .streamCopy
        )
    }

    private func inputURL() -> URL {
        URL(fileURLWithPath: "/tmp/input.mov")
    }

    private func outputURL() -> URL {
        URL(fileURLWithPath: "/tmp/output.mov")
    }
}
