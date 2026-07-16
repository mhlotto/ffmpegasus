import XCTest
@testable import FFMpegasusCore

final class FakeEditingProcessExecutor: EditingProcessExecuting, @unchecked Sendable {
    var result = ProcessResult(exitCode: 0)
    var thrownError: Error?
    var progressValues: [Double] = []
    var delayNanoseconds: UInt64 = 0
    var waitForCancel = false
    var onRun: (@Sendable () -> Void)?
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
        onRun?()
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
    var directoryContents: [String: [String]] = [:]
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

    func contentsOfDirectory(at url: URL) -> [String] {
        directoryContents[url.path] ?? []
    }

    func removeFile(at url: URL) {
        removedFiles.append(url.path)
        files.remove(url.path)
        sizes[url.path] = nil
        let directory = url.deletingLastPathComponent().path
        directoryContents[directory]?.removeAll { $0 == url.lastPathComponent }
    }
}

struct FakeEncoderChecker: CompressionEncoderChecking {
    var supports = true

    func supportsLibx264(ffmpegPath: String) async throws -> Bool {
        supports
    }
}

struct FakeCompressionVerifier: CompressionOutputVerifying {
    var error: Error?

    func verify(request: CompressionRequest, outputURL: URL) async throws {
        if let error {
            throw error
        }
    }
}

struct FakeTransformVerifier: VideoTransformOutputVerifying {
    var error: Error?

    func verify(request: VideoTransformRequest, outputURL: URL) async throws {
        if let error {
            throw error
        }
    }
}

struct FakeEditPlanVerifier: VideoEditPlanOutputVerifying {
    var error: Error?

    func verify(plan: VideoEditPlan, outputURL: URL) async throws {
        if let error {
            throw error
        }
    }
}

struct FakeSpeedVerifier: VideoSpeedOutputVerifying {
    var error: Error?

    func verify(request: VideoSpeedRequest, outputURL: URL) async throws {
        if let error {
            throw error
        }
    }
}

struct FakeFrameExportVerifier: FrameExportOutputVerifying {
    var error: Error?

    func verify(request: FrameExportRequest, outputURL: URL) async throws -> FrameImageInfo {
        if let error {
            throw error
        }
        return FrameImageInfo(format: request.format, dimensions: (try? request.expectedDimensions()) ?? request.sourceDimensions)
    }
}

struct FakeIntervalFrameExportVerifier: IntervalFrameExportOutputVerifying {
    var error: Error?

    func verify(request: IntervalFrameExportRequest, files: [URL]) async throws -> IntervalFrameExportResult {
        if let error {
            throw error
        }
        return IntervalFrameExportResult(
            imageCount: files.count,
            dimensions: (try? request.expectedDimensions()) ?? request.sourceDimensions,
            firstImageURL: files.first ?? request.outputURL(forSequenceNumber: 1),
            lastImageURL: files.last ?? request.outputURL(forSequenceNumber: max(1, files.count))
        )
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

    func testRemoveAudioSucceedsWithValidNonemptyOutput() async {
        let process = FakeEditingProcessExecutor()
        let fileSystem = validFileSystem(outputSize: 2048)
        let state = EditingOperationState()
        let service = VideoEditingService(processExecutor: process, fileSystem: fileSystem)

        await service.runRemoveAudio(ffmpegPath: ffmpegPath, request: removeAudioRequest(), state: state)

        XCTAssertEqual(state.phase, .completed(outputURL: outputURL(), byteCount: 2048))
        XCTAssertEqual(state.status, "Audio removed")
        XCTAssertEqual(process.command?.arguments.commandValue(after: "-map"), "0:v")
    }

    func testRemoveAudioRejectsMissingVideoStream() async {
        let state = await runRemoveAudioWith(request: removeAudioRequest(hasVideoStream: false))

        guard case .failed(let summary) = state.phase else {
            return XCTFail("Expected failed state")
        }
        XCTAssertTrue(summary.contains("no video stream"))
    }

    func testRemoveAudioRejectsMissingAudioStream() async {
        let state = await runRemoveAudioWith(request: removeAudioRequest(hasAudioStream: false))

        guard case .failed(let summary) = state.phase else {
            return XCTFail("Expected failed state")
        }
        XCTAssertTrue(summary.contains("no audio stream"))
    }

    func testRemoveAudioRejectsInputAndOutputPathsBeingIdentical() async {
        let state = await runRemoveAudioWith(request: removeAudioRequest(outputURL: inputURL()))

        guard case .failed(let summary) = state.phase else {
            return XCTFail("Expected failed state")
        }
        XCTAssertTrue(summary.contains("different from the input"))
    }

    func testRemoveAudioExitZeroWithMissingOutputFails() async {
        let state = await runRemoveAudioWith(outputExists: false, outputSize: nil)

        guard case .failed(let summary) = state.phase else {
            return XCTFail("Expected failed state")
        }
        XCTAssertTrue(summary.contains("no output file was created"))
    }

    func testRemoveAudioExitZeroWithZeroByteOutputFails() async {
        let state = await runRemoveAudioWith(outputExists: true, outputSize: 0)

        guard case .failed(let summary) = state.phase else {
            return XCTFail("Expected failed state")
        }
        XCTAssertTrue(summary.contains("output file is empty"))
    }

    func testRemoveAudioCancellationRemovesIncompleteOutput() async {
        let process = FakeEditingProcessExecutor()
        process.waitForCancel = true
        let fileSystem = validFileSystem(outputSize: 12)
        let state = EditingOperationState()
        let service = VideoEditingService(processExecutor: process, fileSystem: fileSystem)

        let task = Task {
            await service.runRemoveAudio(ffmpegPath: ffmpegPath, request: removeAudioRequest(), state: state)
        }

        try? await Task.sleep(nanoseconds: 5_000_000)
        service.requestCancellation(state: state)
        await task.value

        XCTAssertEqual(state.phase, .cancelled)
        XCTAssertEqual(fileSystem.removedFiles, [outputURL().path])
    }

    func testCompressionSucceedsWithValidOutput() async {
        let process = FakeEditingProcessExecutor()
        let fileSystem = validFileSystem(outputSize: 4096)
        fileSystem.files.insert(inputURL().path)
        fileSystem.sizes[inputURL().path] = 10_000
        let state = EditingOperationState()
        let service = VideoEditingService(processExecutor: process, fileSystem: fileSystem, encoderChecker: FakeEncoderChecker())

        await service.runCompression(
            ffmpegPath: ffmpegPath,
            ffprobePath: "/opt/homebrew/bin/ffprobe",
            request: compressionRequest(),
            state: state,
            verifier: FakeCompressionVerifier()
        )

        XCTAssertEqual(state.phase, .completed(outputURL: outputURL(), byteCount: 4096))
        XCTAssertTrue(state.message?.contains("Output size") == true)
    }

    func testCompressionMissingLibx264Fails() async {
        let state = await runCompressionWith(encoderChecker: FakeEncoderChecker(supports: false))

        guard case .failed(let summary) = state.phase else {
            return XCTFail("Expected failed state")
        }
        XCTAssertTrue(summary.contains("libx264"))
    }

    func testAccurateTrimMissingLibx264Fails() async {
        let state = EditingOperationState()
        let service = VideoEditingService(
            processExecutor: FakeEditingProcessExecutor(),
            fileSystem: validFileSystem(outputSize: 100),
            encoderChecker: FakeEncoderChecker(supports: false)
        )
        await service.run(ffmpegPath: ffmpegPath, request: request(trimExecutionMode: .accurate), state: state)

        guard case .failed(let summary) = state.phase else {
            return XCTFail("Expected failed state")
        }
        XCTAssertTrue(summary.contains("libx264"))
    }

    func testCompressionOutputVerificationFailureFails() async {
        let state = await runCompressionWith(verifier: FakeCompressionVerifier(error: CompressionValidationError.wrongCodec("hevc")))

        guard case .failed(let summary) = state.phase else {
            return XCTFail("Expected failed state")
        }
        XCTAssertTrue(summary.contains("not H.264"))
    }

    func testCompressionCancellationRemovesIncompleteOutput() async {
        let process = FakeEditingProcessExecutor()
        process.waitForCancel = true
        let fileSystem = validFileSystem(outputSize: 12)
        let state = EditingOperationState()
        let service = VideoEditingService(processExecutor: process, fileSystem: fileSystem, encoderChecker: FakeEncoderChecker())

        let task = Task {
            await service.runCompression(
                ffmpegPath: ffmpegPath,
                ffprobePath: "/opt/homebrew/bin/ffprobe",
                request: compressionRequest(),
                state: state,
                verifier: FakeCompressionVerifier()
            )
        }

        try? await Task.sleep(nanoseconds: 5_000_000)
        service.requestCancellation(state: state)
        await task.value

        XCTAssertEqual(state.phase, .cancelled)
        XCTAssertEqual(fileSystem.removedFiles, [outputURL().path])
    }

    func testTransformSucceedsWithValidOutput() async {
        let process = FakeEditingProcessExecutor()
        let fileSystem = validFileSystem(outputSize: 4096)
        fileSystem.files.insert(inputURL().path)
        fileSystem.sizes[inputURL().path] = 10_000
        let state = EditingOperationState()
        let service = VideoEditingService(processExecutor: process, fileSystem: fileSystem, encoderChecker: FakeEncoderChecker())

        await service.runTransform(
            ffmpegPath: ffmpegPath,
            ffprobePath: "/opt/homebrew/bin/ffprobe",
            request: transformRequest(),
            state: state,
            verifier: FakeTransformVerifier()
        )

        XCTAssertEqual(state.phase, .completed(outputURL: outputURL(), byteCount: 4096))
        XCTAssertEqual(state.status, "Transformation complete")
        XCTAssertEqual(process.command?.arguments.commandValue(after: "-vf"), "transpose=clock")
    }

    func testTransformMissingLibx264Fails() async {
        let state = await runTransformWith(encoderChecker: FakeEncoderChecker(supports: false))

        guard case .failed(let summary) = state.phase else {
            return XCTFail("Expected failed state")
        }
        XCTAssertTrue(summary.contains("Rotate / Flip requires"))
    }

    func testTransformOutputVerificationFailureFails() async {
        let state = await runTransformWith(verifier: FakeTransformVerifier(error: VideoTransformValidationError.wrongCodec("hevc")))

        guard case .failed(let summary) = state.phase else {
            return XCTFail("Expected failed state")
        }
        XCTAssertTrue(summary.contains("not H.264"))
    }

    func testTransformRejectsInputAndOutputPathsBeingIdentical() async {
        let state = await runTransformWith(request: transformRequest(outputURL: inputURL()))

        guard case .failed(let summary) = state.phase else {
            return XCTFail("Expected failed state")
        }
        XCTAssertTrue(summary.contains("different from the input"))
    }

    func testTransformCancellationRemovesIncompleteOutput() async {
        let process = FakeEditingProcessExecutor()
        process.waitForCancel = true
        let fileSystem = validFileSystem(outputSize: 12)
        let state = EditingOperationState()
        let service = VideoEditingService(processExecutor: process, fileSystem: fileSystem, encoderChecker: FakeEncoderChecker())

        let task = Task {
            await service.runTransform(
                ffmpegPath: ffmpegPath,
                ffprobePath: "/opt/homebrew/bin/ffprobe",
                request: transformRequest(),
                state: state,
                verifier: FakeTransformVerifier()
            )
        }

        try? await Task.sleep(nanoseconds: 5_000_000)
        service.requestCancellation(state: state)
        await task.value

        XCTAssertEqual(state.phase, .cancelled)
        XCTAssertEqual(fileSystem.removedFiles, [outputURL().path])
    }

    func testEditPlanSucceedsWithValidOutput() async {
        let process = FakeEditingProcessExecutor()
        let fileSystem = validFileSystem(outputSize: 4096)
        fileSystem.files.insert(inputURL().path)
        fileSystem.sizes[inputURL().path] = 10_000
        let state = EditingOperationState()
        let service = VideoEditingService(processExecutor: process, fileSystem: fileSystem, encoderChecker: FakeEncoderChecker())

        await service.runEditPlan(
            ffmpegPath: ffmpegPath,
            ffprobePath: "/opt/homebrew/bin/ffprobe",
            plan: editPlan(),
            state: state,
            verifier: FakeEditPlanVerifier()
        )

        XCTAssertEqual(state.phase, .completed(outputURL: outputURL(), byteCount: 4096))
        XCTAssertEqual(state.status, "Export complete")
        XCTAssertEqual(process.command?.arguments.commandValue(after: "-vf"), "transpose=clock")
    }

    func testEditPlanMissingLibx264FailsWhenReencoding() async {
        let state = await runEditPlanWith(encoderChecker: FakeEncoderChecker(supports: false))

        guard case .failed(let summary) = state.phase else {
            return XCTFail("Expected failed state")
        }
        XCTAssertTrue(summary.contains("libx264"))
    }

    func testEditPlanVerificationFailureFails() async {
        let state = await runEditPlanWith(verifier: FakeEditPlanVerifier(error: VideoTransformValidationError.wrongCodec("hevc")))

        guard case .failed(let summary) = state.phase else {
            return XCTFail("Expected failed state")
        }
        XCTAssertTrue(summary.contains("not H.264"))
    }

    func testEditPlanRejectsInputAndOutputPathsBeingIdentical() async {
        let state = await runEditPlanWith(plan: editPlan(outputURL: inputURL()))

        guard case .failed(let summary) = state.phase else {
            return XCTFail("Expected failed state")
        }
        XCTAssertTrue(summary.contains("different from the input"))
    }

    func testEditPlanCancellationRemovesIncompleteOutput() async {
        let process = FakeEditingProcessExecutor()
        process.waitForCancel = true
        let fileSystem = validFileSystem(outputSize: 12)
        let state = EditingOperationState()
        let service = VideoEditingService(processExecutor: process, fileSystem: fileSystem, encoderChecker: FakeEncoderChecker())

        let task = Task {
            await service.runEditPlan(
                ffmpegPath: ffmpegPath,
                ffprobePath: "/opt/homebrew/bin/ffprobe",
                plan: editPlan(),
                state: state,
                verifier: FakeEditPlanVerifier()
            )
        }

        try? await Task.sleep(nanoseconds: 5_000_000)
        service.requestCancellation(state: state)
        await task.value

        XCTAssertEqual(state.phase, .cancelled)
        XCTAssertEqual(fileSystem.removedFiles, [outputURL().path])
    }

    func testSpeedChangeSucceedsWithValidOutput() async throws {
        let process = FakeEditingProcessExecutor()
        let fileSystem = validFileSystem(outputSize: 4096)
        fileSystem.files.insert(inputURL().path)
        fileSystem.sizes[inputURL().path] = 10_000
        let state = EditingOperationState()
        let service = VideoEditingService(processExecutor: process, fileSystem: fileSystem, encoderChecker: FakeEncoderChecker())

        await service.runSpeedChange(
            ffmpegPath: ffmpegPath,
            ffprobePath: "/opt/homebrew/bin/ffprobe",
            request: speedRequest(speed: try VideoSpeed(multiplier: 1.5)),
            state: state,
            verifier: FakeSpeedVerifier()
        )

        XCTAssertEqual(state.phase, .completed(outputURL: outputURL(), byteCount: 4096))
        XCTAssertEqual(state.status, "Speed change complete")
        XCTAssertEqual(process.command?.arguments.commandValue(after: "-vf"), "setpts=PTS/1.5")
        XCTAssertTrue(state.message?.contains("Speed: 1_5x") == true)
    }

    func testSpeedChangeMissingLibx264Fails() async {
        let state = await runSpeedWith(encoderChecker: FakeEncoderChecker(supports: false))

        guard case .failed(let summary) = state.phase else {
            return XCTFail("Expected failed state")
        }
        XCTAssertTrue(summary.contains("Changing speed requires"))
    }

    func testSpeedChangeVerificationFailureFails() async {
        let state = await runSpeedWith(verifier: FakeSpeedVerifier(error: VideoSpeedValidationError.wrongCodec("hevc")))

        guard case .failed(let summary) = state.phase else {
            return XCTFail("Expected failed state")
        }
        XCTAssertTrue(summary.contains("not H.264"))
    }

    func testSpeedChangeExitZeroWithMissingOutputFails() async {
        let state = await runSpeedWith(outputExists: false, outputSize: nil)

        guard case .failed(let summary) = state.phase else {
            return XCTFail("Expected failed state")
        }
        XCTAssertTrue(summary.contains("no output file was created"))
    }

    func testSpeedChangeExitZeroWithZeroByteOutputFails() async {
        let state = await runSpeedWith(outputExists: true, outputSize: 0)

        guard case .failed(let summary) = state.phase else {
            return XCTFail("Expected failed state")
        }
        XCTAssertTrue(summary.contains("output file is empty"))
    }

    func testSpeedChangeCancellationRemovesIncompleteOutput() async throws {
        let process = FakeEditingProcessExecutor()
        process.waitForCancel = true
        let fileSystem = validFileSystem(outputSize: 12)
        let state = EditingOperationState()
        let service = VideoEditingService(processExecutor: process, fileSystem: fileSystem, encoderChecker: FakeEncoderChecker())

        let task = Task {
            await service.runSpeedChange(
                ffmpegPath: ffmpegPath,
                ffprobePath: "/opt/homebrew/bin/ffprobe",
                request: speedRequest(speed: try! VideoSpeed(multiplier: 0.5)),
                state: state,
                verifier: FakeSpeedVerifier()
            )
        }

        try? await Task.sleep(nanoseconds: 5_000_000)
        service.requestCancellation(state: state)
        await task.value

        XCTAssertEqual(state.phase, .cancelled)
        XCTAssertEqual(fileSystem.removedFiles, [outputURL().path])
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

    func testFrameExportSucceedsWithValidOutput() async {
        let process = FakeEditingProcessExecutor()
        let state = EditingOperationState()
        let service = VideoEditingService(processExecutor: process, fileSystem: validFileSystem(outputSize: 2048))

        await service.runFrameExport(
            ffmpegPath: ffmpegPath,
            request: frameExportRequest(),
            state: state,
            verifier: FakeFrameExportVerifier()
        )

        XCTAssertEqual(state.phase, .completed(outputURL: outputURL(), byteCount: 2048))
        XCTAssertEqual(state.status, "Frame export complete")
        XCTAssertEqual(process.command?.arguments.commandValue(after: "-frames:v"), "1")
    }

    func testFrameExportExitZeroWithMissingOutputFails() async {
        let state = await runFrameExportWith(outputExists: false, outputSize: nil)

        guard case .failed(let summary) = state.phase else {
            return XCTFail("Expected failed state")
        }
        XCTAssertTrue(summary.contains("no output file was created"))
    }

    func testFrameExportExitZeroWithZeroByteOutputFails() async {
        let state = await runFrameExportWith(outputExists: true, outputSize: 0)

        guard case .failed(let summary) = state.phase else {
            return XCTFail("Expected failed state")
        }
        XCTAssertTrue(summary.contains("output file is empty"))
    }

    func testFrameExportVerificationFailureFails() async {
        let state = await runFrameExportWith(
            verifier: FakeFrameExportVerifier(error: FrameExportValidationError.wrongFormat(expected: .png, actual: .jpeg))
        )

        guard case .failed(let summary) = state.phase else {
            return XCTFail("Expected failed state")
        }
        XCTAssertTrue(summary.contains("expected PNG"))
    }

    func testFrameExportRejectsInputAndOutputPathsBeingIdentical() async {
        let state = await runFrameExportWith(request: frameExportRequest(outputURL: inputURL()))

        guard case .failed(let summary) = state.phase else {
            return XCTFail("Expected failed state")
        }
        XCTAssertTrue(summary.contains("different from the input"))
    }

    func testFrameExportCancellationRemovesIncompleteOutput() async {
        let process = FakeEditingProcessExecutor()
        process.waitForCancel = true
        let fileSystem = validFileSystem(outputSize: 12)
        let state = EditingOperationState()
        let service = VideoEditingService(processExecutor: process, fileSystem: fileSystem)

        let task = Task {
            await service.runFrameExport(
                ffmpegPath: ffmpegPath,
                request: frameExportRequest(),
                state: state,
                verifier: FakeFrameExportVerifier()
            )
        }

        try? await Task.sleep(nanoseconds: 5_000_000)
        service.requestCancellation(state: state)
        await task.value

        XCTAssertEqual(state.phase, .cancelled)
        XCTAssertEqual(fileSystem.removedFiles, [outputURL().path])
    }

    func testIntervalFrameExportSucceedsWithCreatedImages() async {
        let process = FakeEditingProcessExecutor()
        let fileSystem = validFileSystem(outputSize: nil)
        let request = intervalFrameExportRequest()
        process.onRun = {
            fileSystem.directoryContents["/tmp"] = [
                "input-frame-000001.png",
                "input-frame-000002.png",
                "input-frame-000003.png"
            ]
            for number in 1...3 {
                let url = request.outputURL(forSequenceNumber: number)
                fileSystem.files.insert(url.path)
                fileSystem.sizes[url.path] = 256
            }
        }
        let state = EditingOperationState()
        let service = VideoEditingService(processExecutor: process, fileSystem: fileSystem)

        await service.runIntervalFrameExport(
            ffmpegPath: ffmpegPath,
            request: request,
            state: state,
            verifier: FakeIntervalFrameExportVerifier()
        )

        XCTAssertEqual(state.phase, .completed(outputURL: URL(fileURLWithPath: "/tmp"), byteCount: 0))
        XCTAssertEqual(state.status, "Frame export complete")
        XCTAssertEqual(process.command?.arguments.commandValue(after: "-vf"), "setpts=PTS-STARTPTS,fps=1/5:start_time=0")
    }

    func testIntervalFrameExportCancellationRemovesOnlyNewMatchingFiles() async {
        let process = FakeEditingProcessExecutor()
        process.waitForCancel = true
        let fileSystem = validFileSystem(outputSize: nil)
        let request = intervalFrameExportRequest()
        let newFiles = [
            request.outputURL(forSequenceNumber: 1),
            request.outputURL(forSequenceNumber: 2)
        ]
        process.onRun = {
            fileSystem.directoryContents["/tmp"] = [
                "input-frame-000001.png",
                "input-frame-000002.png",
                "unrelated.png"
            ]
            for url in newFiles {
                fileSystem.files.insert(url.path)
                fileSystem.sizes[url.path] = 256
            }
            fileSystem.files.insert("/tmp/unrelated.png")
            fileSystem.sizes["/tmp/unrelated.png"] = 12
        }
        let state = EditingOperationState()
        let service = VideoEditingService(processExecutor: process, fileSystem: fileSystem)

        let task = Task {
            await service.runIntervalFrameExport(
                ffmpegPath: ffmpegPath,
                request: request,
                state: state,
                verifier: FakeIntervalFrameExportVerifier()
            )
        }

        try? await Task.sleep(nanoseconds: 5_000_000)
        service.requestCancellation(state: state)
        await task.value

        XCTAssertEqual(state.phase, .cancelled)
        XCTAssertEqual(Set(fileSystem.removedFiles), Set(newFiles.map(\.path)))
        XCTAssertTrue(fileSystem.files.contains("/tmp/unrelated.png"))
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
        fileSystem.files = [ffmpegPath, inputURL().path]
        fileSystem.executables = [ffmpegPath]
        if outputExists {
            fileSystem.files.insert(outputURL().path)
        }
        if let outputSize {
            fileSystem.sizes[outputURL().path] = outputSize
        }
        return fileSystem
    }

    private func request(outputURL: URL? = nil, trimExecutionMode: TrimExecutionMode = .fast) -> EditingRequest {
        EditingRequest(
            inputURL: inputURL(),
            outputURL: outputURL ?? self.outputURL(),
            sourceDuration: 100,
            removeStartSeconds: 10,
            removeEndSeconds: 15,
            mode: .trimBoth,
            method: .streamCopy,
            trimExecutionMode: trimExecutionMode
        )
    }

    private func runRemoveAudioWith(
        process: FakeEditingProcessExecutor = FakeEditingProcessExecutor(),
        fileSystem: FakeEditingFileSystem? = nil,
        request: RemoveAudioRequest? = nil,
        outputExists: Bool = true,
        outputSize: UInt64? = 100
    ) async -> EditingOperationState {
        let state = EditingOperationState()
        let service = VideoEditingService(
            processExecutor: process,
            fileSystem: fileSystem ?? validFileSystem(outputExists: outputExists, outputSize: outputSize)
        )
        await service.runRemoveAudio(ffmpegPath: ffmpegPath, request: request ?? removeAudioRequest(), state: state)
        return state
    }

    private func removeAudioRequest(
        outputURL: URL? = nil,
        hasVideoStream: Bool = true,
        hasAudioStream: Bool = true
    ) -> RemoveAudioRequest {
        RemoveAudioRequest(
            inputURL: inputURL(),
            outputURL: outputURL ?? self.outputURL(),
            sourceDuration: 100,
            hasVideoStream: hasVideoStream,
            hasAudioStream: hasAudioStream
        )
    }

    private func runCompressionWith(
        encoderChecker: FakeEncoderChecker = FakeEncoderChecker(),
        verifier: FakeCompressionVerifier = FakeCompressionVerifier()
    ) async -> EditingOperationState {
        let state = EditingOperationState()
        let service = VideoEditingService(
            processExecutor: FakeEditingProcessExecutor(),
            fileSystem: validFileSystem(outputSize: 100),
            encoderChecker: encoderChecker
        )
        await service.runCompression(
            ffmpegPath: ffmpegPath,
            ffprobePath: "/opt/homebrew/bin/ffprobe",
            request: compressionRequest(),
            state: state,
            verifier: verifier
        )
        return state
    }

    private func runTransformWith(
        encoderChecker: FakeEncoderChecker = FakeEncoderChecker(),
        verifier: FakeTransformVerifier = FakeTransformVerifier(),
        request: VideoTransformRequest? = nil
    ) async -> EditingOperationState {
        let state = EditingOperationState()
        let service = VideoEditingService(
            processExecutor: FakeEditingProcessExecutor(),
            fileSystem: validFileSystem(outputSize: 100),
            encoderChecker: encoderChecker
        )
        await service.runTransform(
            ffmpegPath: ffmpegPath,
            ffprobePath: "/opt/homebrew/bin/ffprobe",
            request: request ?? transformRequest(),
            state: state,
            verifier: verifier
        )
        return state
    }

    private func runEditPlanWith(
        encoderChecker: FakeEncoderChecker = FakeEncoderChecker(),
        verifier: FakeEditPlanVerifier = FakeEditPlanVerifier(),
        plan: VideoEditPlan? = nil
    ) async -> EditingOperationState {
        let state = EditingOperationState()
        let service = VideoEditingService(
            processExecutor: FakeEditingProcessExecutor(),
            fileSystem: validFileSystem(outputSize: 100),
            encoderChecker: encoderChecker
        )
        await service.runEditPlan(
            ffmpegPath: ffmpegPath,
            ffprobePath: "/opt/homebrew/bin/ffprobe",
            plan: plan ?? editPlan(),
            state: state,
            verifier: verifier
        )
        return state
    }

    private func runSpeedWith(
        encoderChecker: FakeEncoderChecker = FakeEncoderChecker(),
        verifier: FakeSpeedVerifier = FakeSpeedVerifier(),
        outputExists: Bool = true,
        outputSize: UInt64? = 100
    ) async -> EditingOperationState {
        let state = EditingOperationState()
        let service = VideoEditingService(
            processExecutor: FakeEditingProcessExecutor(),
            fileSystem: validFileSystem(outputExists: outputExists, outputSize: outputSize),
            encoderChecker: encoderChecker
        )
        await service.runSpeedChange(
            ffmpegPath: ffmpegPath,
            ffprobePath: "/opt/homebrew/bin/ffprobe",
            request: speedRequest(speed: try! VideoSpeed(multiplier: 2.0)),
            state: state,
            verifier: verifier
        )
        return state
    }

    private func runFrameExportWith(
        verifier: FakeFrameExportVerifier = FakeFrameExportVerifier(),
        request: FrameExportRequest? = nil,
        outputExists: Bool = true,
        outputSize: UInt64? = 100
    ) async -> EditingOperationState {
        let state = EditingOperationState()
        let service = VideoEditingService(
            processExecutor: FakeEditingProcessExecutor(),
            fileSystem: validFileSystem(outputExists: outputExists, outputSize: outputSize)
        )
        await service.runFrameExport(
            ffmpegPath: ffmpegPath,
            request: request ?? frameExportRequest(),
            state: state,
            verifier: verifier
        )
        return state
    }

    private func compressionRequest() -> CompressionRequest {
        CompressionRequest(
            inputURL: inputURL(),
            outputURL: outputURL(),
            sourceDuration: 100,
            sourceDimensions: VideoDimensions(width: 1920, height: 1080),
            hasVideoStream: true,
            hasAudioStream: true,
            quality: .balanced,
            customCRF: 24,
            encoderPreset: .medium,
            resolution: .p720,
            customHeight: nil,
            audioMode: .keep
        )
    }

    private func transformRequest(outputURL: URL? = nil) -> VideoTransformRequest {
        VideoTransformRequest(
            inputURL: inputURL(),
            outputURL: outputURL ?? self.outputURL(),
            sourceDuration: 100,
            sourceDimensions: VideoDimensions(width: 1920, height: 1080),
            sourceRotationDegrees: nil,
            hasVideoStream: true,
            hasAudioStream: true,
            rotation: .clockwise90,
            flipHorizontal: false,
            flipVertical: false
        )
    }

    private func editPlan(outputURL: URL? = nil) -> VideoEditPlan {
        VideoEditPlan(
            inputURL: inputURL(),
            outputURL: outputURL ?? self.outputURL(),
            sourceDuration: 100,
            sourceDimensions: VideoDimensions(width: 1920, height: 1080),
            sourceRotationDegrees: nil,
            hasVideoStream: true,
            hasAudioStream: true,
            trim: nil,
            transform: VideoTransformConfiguration(rotation: .clockwise90, flipHorizontal: false, flipVertical: false),
            resize: nil,
            compression: nil,
            audioMode: .keep
        )
    }

    private func speedRequest(speed: VideoSpeed) -> VideoSpeedRequest {
        VideoSpeedRequest(
            inputURL: inputURL(),
            outputURL: outputURL(),
            sourceDuration: 100,
            sourceDimensions: VideoDimensions(width: 1920, height: 1080),
            sourceRotationDegrees: nil,
            hasVideoStream: true,
            hasAudioStream: true,
            speed: speed,
            audioMode: .keep
        )
    }

    private func frameExportRequest(outputURL: URL? = nil) -> FrameExportRequest {
        FrameExportRequest(
            inputURL: inputURL(),
            outputURL: outputURL ?? self.outputURL(),
            timestampSeconds: 1.25,
            sourceDuration: 100,
            sourceDimensions: VideoDimensions(width: 1920, height: 1080),
            sourceRotationDegrees: nil,
            hasVideoStream: true,
            format: .png,
            jpegQuality: nil
        )
    }

    private func intervalFrameExportRequest() -> IntervalFrameExportRequest {
        IntervalFrameExportRequest(
            inputURL: inputURL(),
            outputDirectoryURL: URL(fileURLWithPath: "/tmp"),
            sourceDuration: 10,
            sourceDimensions: VideoDimensions(width: 1920, height: 1080),
            sourceRotationDegrees: nil,
            hasVideoStream: true,
            interval: try! FrameInterval(seconds: 5),
            range: try! FrameExportRange(startSeconds: 0, endSeconds: 10, sourceDuration: 10),
            format: .png,
            jpegQuality: nil
        )
    }

    private func inputURL() -> URL {
        URL(fileURLWithPath: "/tmp/input.mov")
    }

    private func outputURL() -> URL {
        URL(fileURLWithPath: "/tmp/output.mov")
    }
}

private extension Array where Element == String {
    func commandValue(after option: String) -> String? {
        guard let index = firstIndex(of: option), indices.contains(index + 1) else { return nil }
        return self[index + 1]
    }
}
