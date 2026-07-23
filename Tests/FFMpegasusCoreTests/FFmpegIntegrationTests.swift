import XCTest
@testable import FFMpegasusCore

final class FFmpegIntegrationTests: XCTestCase {
    func testOptionalFFmpegSyntheticStreamCopyTrim() async throws {
        let tools = try MediaFixtures.requireTools()
        try await MediaFixtures.ensureGenerated()
        let standard = try MediaFixtures.fixture(id: "standardLandscape")
        let input = MediaFixtures.url(for: standard)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appendingPathComponent("output.mp4")

        let request = EditingRequest(
            inputURL: input,
            outputURL: output,
            sourceDuration: standard.durationSeconds,
            removeStartSeconds: 0.5,
            removeEndSeconds: 0,
            mode: .trimStart,
            method: .streamCopy
        )
        let command = try VideoEditingService().command(ffmpegPath: tools.ffmpeg, request: request)
        let trim = try await ProcessRunner().run(executablePath: command.executablePath, arguments: command.arguments)

        XCTAssertEqual(trim.exitCode, 0, trim.stderrText)
        let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
        let size = try XCTUnwrap(attributes[.size] as? NSNumber)
        XCTAssertGreaterThan(size.uint64Value, 0)
    }

    func testOptionalFFmpegSyntheticFastAndAccurateTrimModes() async throws {
        let ffmpegPath = "/opt/homebrew/bin/ffmpeg"
        let ffprobePath = "/opt/homebrew/bin/ffprobe"
        guard FileManager.default.isExecutableFile(atPath: ffmpegPath),
              FileManager.default.isExecutableFile(atPath: ffprobePath) else {
            throw XCTSkip("FFmpeg or FFprobe is not available at the default Homebrew paths")
        }
        let encoders = try await FFmpegRunner().encoders(ffmpegPath: ffmpegPath)
        guard encoders.contains("libx264") else {
            throw XCTSkip("FFmpeg does not include libx264")
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let input = directory.appendingPathComponent("input.mp4")
        let fastOutput = directory.appendingPathComponent("input-trimmed.mp4")
        let accurateOutput = directory.appendingPathComponent("input-trimmed-accurate.mp4")
        let accurateNoAudioOutput = directory.appendingPathComponent("input-no-audio-trimmed-accurate.mp4")

        let generate = try await ProcessRunner().run(
            executablePath: ffmpegPath,
            arguments: [
                "-y", "-nostdin",
                "-f", "lavfi",
                "-i", "testsrc=size=320x240:rate=30:duration=8",
                "-f", "lavfi",
                "-i", "sine=frequency=1000:duration=8",
                "-shortest",
                "-c:v", "libx264",
                "-g", "90",
                "-keyint_min", "90",
                "-sc_threshold", "0",
                "-pix_fmt", "yuv420p",
                "-c:a", "aac",
                "-b:a", "96k",
                input.path
            ]
        )
        XCTAssertEqual(generate.exitCode, 0, generate.stderrText)

        let sourceMetadata = try await FFprobeRunner().loadMetadata(ffprobePath: ffprobePath, inputURL: input)
        let fastRequest = EditingRequest(
            inputURL: input,
            outputURL: fastOutput,
            sourceDuration: sourceMetadata.duration,
            removeStartSeconds: 2.3,
            removeEndSeconds: 1.7,
            mode: .trimBoth,
            method: .streamCopy,
            trimExecutionMode: .fast,
            hasVideoStream: true,
            hasAudioStream: true
        )
        let fastCommand = try VideoEditingService().command(ffmpegPath: ffmpegPath, request: fastRequest)
        let fast = try await ProcessRunner().run(executablePath: fastCommand.executablePath, arguments: fastCommand.arguments)
        XCTAssertEqual(fast.exitCode, 0, fast.stderrText)
        let fastMetadata = try await FFprobeRunner().loadMetadata(ffprobePath: ffprobePath, inputURL: fastOutput)
        XCTAssertNoThrow(try TrimOutputValidator.verify(metadata: fastMetadata, request: fastRequest))

        let accurateRequest = EditingRequest(
            inputURL: input,
            outputURL: accurateOutput,
            sourceDuration: sourceMetadata.duration,
            removeStartSeconds: 2.3,
            removeEndSeconds: 1.7,
            mode: .trimBoth,
            method: .streamCopy,
            trimExecutionMode: .accurate,
            hasVideoStream: true,
            hasAudioStream: true
        )
        let accurateCommand = try VideoEditingService().command(ffmpegPath: ffmpegPath, request: accurateRequest)
        let accurate = try await ProcessRunner().run(executablePath: accurateCommand.executablePath, arguments: accurateCommand.arguments)
        XCTAssertEqual(accurate.exitCode, 0, accurate.stderrText)
        let accurateMetadata = try await FFprobeRunner().loadMetadata(ffprobePath: ffprobePath, inputURL: accurateOutput)
        XCTAssertNoThrow(try TrimOutputValidator.verify(metadata: accurateMetadata, request: accurateRequest))
        XCTAssertEqual(accurateMetadata.videoCodec, "h264")
        XCTAssertNotNil(accurateMetadata.audioCodec)

        let noAudioRequest = EditingRequest(
            inputURL: input,
            outputURL: accurateNoAudioOutput,
            sourceDuration: sourceMetadata.duration,
            removeStartSeconds: 1,
            removeEndSeconds: 1,
            mode: .trimBoth,
            method: .streamCopy,
            trimExecutionMode: .accurate,
            hasVideoStream: true,
            hasAudioStream: false
        )
        let noAudioCommand = try VideoEditingService().command(ffmpegPath: ffmpegPath, request: noAudioRequest)
        XCTAssertFalse(noAudioCommand.arguments.contains("0:a:0?"))
        XCTAssertFalse(noAudioCommand.arguments.contains("aac"))
        let noAudio = try await ProcessRunner().run(executablePath: noAudioCommand.executablePath, arguments: noAudioCommand.arguments)
        XCTAssertEqual(noAudio.exitCode, 0, noAudio.stderrText)
        let noAudioMetadata = try await FFprobeRunner().loadMetadata(ffprobePath: ffprobePath, inputURL: accurateNoAudioOutput)
        XCTAssertNoThrow(try TrimOutputValidator.verify(metadata: noAudioMetadata, request: noAudioRequest))
        XCTAssertNil(noAudioMetadata.audioCodec)
    }

    func testOptionalFFmpegSyntheticRemoveAudio() async throws {
        let tools = try MediaFixtures.requireTools()
        try await MediaFixtures.ensureGenerated()
        let standard = try MediaFixtures.fixture(id: "standardLandscape")
        let input = MediaFixtures.url(for: standard)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appendingPathComponent("output.mp4")

        let request = RemoveAudioRequest(
            inputURL: input,
            outputURL: output,
            sourceDuration: standard.durationSeconds,
            hasVideoStream: true,
            hasAudioStream: true
        )
        let command = VideoEditingService().removeAudioCommand(ffmpegPath: tools.ffmpeg, request: request)
        let removeAudio = try await ProcessRunner().run(executablePath: command.executablePath, arguments: command.arguments)
        XCTAssertEqual(removeAudio.exitCode, 0, removeAudio.stderrText)

        let metadata = try await FFprobeRunner().loadMetadata(ffprobePath: tools.ffprobe, inputURL: output)
        XCTAssertNotNil(metadata.videoCodec)
        XCTAssertNil(metadata.audioCodec)
    }

    func testOptionalFFmpegSyntheticCompressionBalanced720p() async throws {
        let ffmpegPath = "/opt/homebrew/bin/ffmpeg"
        let ffprobePath = "/opt/homebrew/bin/ffprobe"
        guard FileManager.default.isExecutableFile(atPath: ffmpegPath),
              FileManager.default.isExecutableFile(atPath: ffprobePath) else {
            throw XCTSkip("FFmpeg or FFprobe is not available at the default Homebrew paths")
        }
        let encoders = try await FFmpegRunner().encoders(ffmpegPath: ffmpegPath)
        guard encoders.contains("libx264") else {
            throw XCTSkip("FFmpeg does not include libx264")
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let input = directory.appendingPathComponent("input.mp4")
        let output = directory.appendingPathComponent("output.mp4")
        let mutedOutput = directory.appendingPathComponent("output-muted.mp4")

        let generate = try await ProcessRunner().run(
            executablePath: ffmpegPath,
            arguments: [
                "-y", "-nostdin",
                "-f", "lavfi",
                "-i", "testsrc=size=1920x1080:rate=10:duration=1",
                "-f", "lavfi",
                "-i", "sine=frequency=1000:duration=1",
                "-shortest",
                "-pix_fmt", "yuv420p",
                input.path
            ]
        )
        XCTAssertEqual(generate.exitCode, 0, generate.stderrText)

        let keepAudio = CompressionRequest(
            inputURL: input,
            outputURL: output,
            sourceDuration: 1,
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
        let keepCommand = try VideoEditingService().compressionCommand(ffmpegPath: ffmpegPath, request: keepAudio)
        let keepResult = try await ProcessRunner().run(executablePath: keepCommand.executablePath, arguments: keepCommand.arguments)
        XCTAssertEqual(keepResult.exitCode, 0, keepResult.stderrText)

        let keepMetadata = try await FFprobeRunner().loadMetadata(ffprobePath: ffprobePath, inputURL: output)
        XCTAssertEqual(keepMetadata.videoCodec, "h264")
        XCTAssertEqual(keepMetadata.width, 1280)
        XCTAssertEqual(keepMetadata.height, 720)
        XCTAssertNotNil(keepMetadata.audioCodec)

        let removeAudio = CompressionRequest(
            inputURL: input,
            outputURL: mutedOutput,
            sourceDuration: 1,
            sourceDimensions: VideoDimensions(width: 1920, height: 1080),
            hasVideoStream: true,
            hasAudioStream: true,
            quality: .balanced,
            customCRF: 24,
            encoderPreset: .medium,
            resolution: .p720,
            customHeight: nil,
            audioMode: .remove
        )
        let removeCommand = try VideoEditingService().compressionCommand(ffmpegPath: ffmpegPath, request: removeAudio)
        let removeResult = try await ProcessRunner().run(executablePath: removeCommand.executablePath, arguments: removeCommand.arguments)
        XCTAssertEqual(removeResult.exitCode, 0, removeResult.stderrText)

        let removeMetadata = try await FFprobeRunner().loadMetadata(ffprobePath: ffprobePath, inputURL: mutedOutput)
        XCTAssertEqual(removeMetadata.videoCodec, "h264")
        XCTAssertEqual(removeMetadata.width, 1280)
        XCTAssertEqual(removeMetadata.height, 720)
        XCTAssertNil(removeMetadata.audioCodec)
    }

    func testOptionalFFmpegSyntheticRotateFlipTransforms() async throws {
        let ffmpegPath = "/opt/homebrew/bin/ffmpeg"
        let ffprobePath = "/opt/homebrew/bin/ffprobe"
        guard FileManager.default.isExecutableFile(atPath: ffmpegPath),
              FileManager.default.isExecutableFile(atPath: ffprobePath) else {
            throw XCTSkip("FFmpeg or FFprobe is not available at the default Homebrew paths")
        }
        let encoders = try await FFmpegRunner().encoders(ffmpegPath: ffmpegPath)
        guard encoders.contains("libx264") else {
            throw XCTSkip("FFmpeg does not include libx264")
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let input = directory.appendingPathComponent("input.mp4")
        let clockwise = directory.appendingPathComponent("clockwise.mp4")
        let counterclockwise = directory.appendingPathComponent("counterclockwise.mp4")
        let rotate180 = directory.appendingPathComponent("rotate180.mp4")
        let horizontal = directory.appendingPathComponent("horizontal.mp4")
        let vertical = directory.appendingPathComponent("vertical.mp4")
        let combined = directory.appendingPathComponent("combined.mp4")
        let noAudio = directory.appendingPathComponent("no-audio.mp4")
        let tagged = directory.appendingPathComponent("tagged-rotate90.mp4")
        let taggedOutput = directory.appendingPathComponent("tagged-output.mp4")

        let generate = try await ProcessRunner().run(
            executablePath: ffmpegPath,
            arguments: [
                "-y", "-nostdin",
                "-f", "lavfi",
                "-i", "testsrc=size=320x180:rate=10:duration=2",
                "-f", "lavfi",
                "-i", "sine=frequency=1000:duration=2",
                "-shortest",
                "-c:v", "libx264",
                "-pix_fmt", "yuv420p",
                "-c:a", "aac",
                "-b:a", "96k",
                input.path
            ]
        )
        XCTAssertEqual(generate.exitCode, 0, generate.stderrText)

        let service = VideoEditingService()
        try await runTransform(
            service: service,
            ffmpegPath: ffmpegPath,
            ffprobePath: ffprobePath,
            request: transformRequest(input: input, output: clockwise, rotation: .clockwise90),
            expectedDimensions: VideoDimensions(width: 180, height: 320),
            expectedAudio: true
        )
        try await runTransform(
            service: service,
            ffmpegPath: ffmpegPath,
            ffprobePath: ffprobePath,
            request: transformRequest(input: input, output: counterclockwise, rotation: .counterclockwise90),
            expectedDimensions: VideoDimensions(width: 180, height: 320),
            expectedAudio: true
        )
        try await runTransform(
            service: service,
            ffmpegPath: ffmpegPath,
            ffprobePath: ffprobePath,
            request: transformRequest(input: input, output: rotate180, rotation: .rotate180),
            expectedDimensions: VideoDimensions(width: 320, height: 180),
            expectedAudio: true
        )
        try await runTransform(
            service: service,
            ffmpegPath: ffmpegPath,
            ffprobePath: ffprobePath,
            request: transformRequest(input: input, output: horizontal, flipHorizontal: true),
            expectedDimensions: VideoDimensions(width: 320, height: 180),
            expectedAudio: true
        )
        try await runTransform(
            service: service,
            ffmpegPath: ffmpegPath,
            ffprobePath: ffprobePath,
            request: transformRequest(input: input, output: vertical, flipVertical: true),
            expectedDimensions: VideoDimensions(width: 320, height: 180),
            expectedAudio: true
        )
        try await runTransform(
            service: service,
            ffmpegPath: ffmpegPath,
            ffprobePath: ffprobePath,
            request: transformRequest(input: input, output: combined, rotation: .clockwise90, flipHorizontal: true),
            expectedDimensions: VideoDimensions(width: 180, height: 320),
            expectedAudio: true
        )
        try await runTransform(
            service: service,
            ffmpegPath: ffmpegPath,
            ffprobePath: ffprobePath,
            request: transformRequest(input: input, output: noAudio, rotation: .clockwise90, hasAudio: false),
            expectedDimensions: VideoDimensions(width: 180, height: 320),
            expectedAudio: false
        )

        let tagRotation = try await ProcessRunner().run(
            executablePath: ffmpegPath,
            arguments: [
                "-y", "-nostdin",
                "-i", input.path,
                "-c", "copy",
                "-metadata:s:v:0", "rotate=90",
                tagged.path
            ]
        )
        XCTAssertEqual(tagRotation.exitCode, 0, tagRotation.stderrText)
        let taggedMetadata = try await FFprobeRunner().loadMetadata(ffprobePath: ffprobePath, inputURL: tagged)
        if taggedMetadata.rotationDegrees == 90 {
            try await runTransform(
                service: service,
                ffmpegPath: ffmpegPath,
                ffprobePath: ffprobePath,
                request: transformRequest(input: tagged, output: taggedOutput, width: 320, height: 180, sourceRotationDegrees: taggedMetadata.rotationDegrees, flipHorizontal: true),
                expectedDimensions: VideoDimensions(width: 180, height: 320),
                expectedAudio: true
            )
        }
    }

    func testOptionalFFmpegSyntheticCombinedEditPlans() async throws {
        let ffmpegPath = "/opt/homebrew/bin/ffmpeg"
        let ffprobePath = "/opt/homebrew/bin/ffprobe"
        guard FileManager.default.isExecutableFile(atPath: ffmpegPath),
              FileManager.default.isExecutableFile(atPath: ffprobePath) else {
            throw XCTSkip("FFmpeg or FFprobe is not available at the default Homebrew paths")
        }
        let encoders = try await FFmpegRunner().encoders(ffmpegPath: ffmpegPath)
        guard encoders.contains("libx264") else {
            throw XCTSkip("FFmpeg does not include libx264")
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let input = directory.appendingPathComponent("input.mp4")
        let planAOutput = directory.appendingPathComponent("plan-a.mp4")
        let planBOutput = directory.appendingPathComponent("plan-b.mp4")
        let planCOutput = directory.appendingPathComponent("plan-c.mp4")

        let generate = try await ProcessRunner().run(
            executablePath: ffmpegPath,
            arguments: [
                "-y", "-nostdin",
                "-f", "lavfi",
                "-i", "testsrc=size=1280x720:rate=10:duration=4",
                "-f", "lavfi",
                "-i", "sine=frequency=1000:duration=4",
                "-shortest",
                "-c:v", "libx264",
                "-g", "10",
                "-pix_fmt", "yuv420p",
                "-c:a", "aac",
                "-b:a", "96k",
                input.path
            ]
        )
        XCTAssertEqual(generate.exitCode, 0, generate.stderrText)

        let service = VideoEditingService()

        let planA = VideoEditPlan(
            inputURL: input,
            outputURL: planAOutput,
            sourceDuration: 4,
            sourceDimensions: VideoDimensions(width: 1280, height: 720),
            sourceRotationDegrees: nil,
            hasVideoStream: true,
            hasAudioStream: true,
            trim: TrimConfiguration(mode: .trimStart, removeStartSeconds: 1.2, removeEndSeconds: 0, executionMode: .fast),
            transform: nil,
            resize: nil,
            compression: nil,
            audioMode: .remove
        )
        XCTAssertEqual(try planA.executionStrategy(), .streamCopy)
        try await runEditPlan(service: service, ffmpegPath: ffmpegPath, ffprobePath: ffprobePath, plan: planA)
        var metadata = try await FFprobeRunner().loadMetadata(ffprobePath: ffprobePath, inputURL: planAOutput)
        XCTAssertNil(metadata.audioCodec)
        XCTAssertEqual(metadata.width, 1280)
        XCTAssertEqual(metadata.height, 720)

        let planB = VideoEditPlan(
            inputURL: input,
            outputURL: planBOutput,
            sourceDuration: 4,
            sourceDimensions: VideoDimensions(width: 1280, height: 720),
            sourceRotationDegrees: nil,
            hasVideoStream: true,
            hasAudioStream: true,
            trim: nil,
            transform: VideoTransformConfiguration(rotation: .clockwise90, flipHorizontal: false, flipVertical: false),
            resize: ResizeConfiguration(resolution: .p720, customHeight: nil),
            compression: CompressionConfiguration(quality: .balanced, customCRF: 24, encoderPreset: .medium),
            speed: try VideoSpeed(multiplier: 2.0),
            audioMode: .keep
        )
        XCTAssertEqual(try planB.executionStrategy(), .reencode)
        let planBCommand = try service.editPlanCommand(ffmpegPath: ffmpegPath, plan: planB)
        XCTAssertEqual(planBCommand.arguments.commandValue(after: "-vf"), "transpose=clock,scale=-2:min(720\\,ih),setpts=PTS/2.0")
        XCTAssertEqual(planBCommand.arguments.commandValue(after: "-af"), "atempo=2.0")
        try await runEditPlan(service: service, ffmpegPath: ffmpegPath, ffprobePath: ffprobePath, plan: planB)
        metadata = try await FFprobeRunner().loadMetadata(ffprobePath: ffprobePath, inputURL: planBOutput)
        XCTAssertEqual(metadata.videoCodec, "h264")
        XCTAssertNotNil(metadata.audioCodec)
        XCTAssertEqual(metadata.width, 406)
        XCTAssertEqual(metadata.height, 720)
        XCTAssertEqual(metadata.duration, 2.0, accuracy: max(0.15, 2.0 / 10.0) + 0.001)

        let planC = VideoEditPlan(
            inputURL: input,
            outputURL: planCOutput,
            sourceDuration: 4,
            sourceDimensions: VideoDimensions(width: 1280, height: 720),
            sourceRotationDegrees: nil,
            hasVideoStream: true,
            hasAudioStream: true,
            trim: TrimConfiguration(mode: .trimBoth, removeStartSeconds: 0.7, removeEndSeconds: 0.8, executionMode: .fast),
            transform: VideoTransformConfiguration(rotation: .counterclockwise90, flipHorizontal: true, flipVertical: false),
            resize: ResizeConfiguration(resolution: .p480, customHeight: nil),
            compression: nil,
            audioMode: .remove
        )
        XCTAssertEqual(try planC.executionStrategy(), .reencode)
        try await runEditPlan(service: service, ffmpegPath: ffmpegPath, ffprobePath: ffprobePath, plan: planC)
        metadata = try await FFprobeRunner().loadMetadata(ffprobePath: ffprobePath, inputURL: planCOutput)
        XCTAssertEqual(metadata.videoCodec, "h264")
        XCTAssertNil(metadata.audioCodec)
        XCTAssertEqual(metadata.width, 270)
        XCTAssertEqual(metadata.height, 480)

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(Set(files), Set(["input.mp4", "plan-a.mp4", "plan-b.mp4", "plan-c.mp4"]))
    }

    func testOptionalFFmpegSyntheticSpeedChanges() async throws {
        let ffmpegPath = "/opt/homebrew/bin/ffmpeg"
        let ffprobePath = "/opt/homebrew/bin/ffprobe"
        guard FileManager.default.isExecutableFile(atPath: ffmpegPath),
              FileManager.default.isExecutableFile(atPath: ffprobePath) else {
            throw XCTSkip("FFmpeg or FFprobe is not available at the default Homebrew paths")
        }
        let encoders = try await FFmpegRunner().encoders(ffmpegPath: ffmpegPath)
        guard encoders.contains("libx264") else {
            throw XCTSkip("FFmpeg does not include libx264")
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let input = directory.appendingPathComponent("input.mp4")
        let noAudioInput = directory.appendingPathComponent("input-no-audio.mp4")
        let service = VideoEditingService()

        let generate = try await ProcessRunner().run(
            executablePath: ffmpegPath,
            arguments: [
                "-y", "-nostdin",
                "-f", "lavfi",
                "-i", "testsrc=size=160x120:rate=12:duration=2",
                "-f", "lavfi",
                "-i", "sine=frequency=880:duration=2",
                "-shortest",
                "-c:v", "libx264",
                "-pix_fmt", "yuv420p",
                "-c:a", "aac",
                "-b:a", "96k",
                input.path
            ]
        )
        XCTAssertEqual(generate.exitCode, 0, generate.stderrText)

        let generateNoAudio = try await ProcessRunner().run(
            executablePath: ffmpegPath,
            arguments: [
                "-y", "-nostdin",
                "-f", "lavfi",
                "-i", "testsrc=size=160x120:rate=12:duration=2",
                "-c:v", "libx264",
                "-pix_fmt", "yuv420p",
                noAudioInput.path
            ]
        )
        XCTAssertEqual(generateNoAudio.exitCode, 0, generateNoAudio.stderrText)

        try await runSpeed(
            service: service,
            ffmpegPath: ffmpegPath,
            ffprobePath: ffprobePath,
            request: speedRequest(input: input, output: directory.appendingPathComponent("speed-0_5x.mp4"), speed: 0.5, hasAudio: true, audioMode: .keep)
        )
        try await runSpeed(
            service: service,
            ffmpegPath: ffmpegPath,
            ffprobePath: ffprobePath,
            request: speedRequest(input: input, output: directory.appendingPathComponent("speed-2x.mp4"), speed: 2.0, hasAudio: true, audioMode: .keep)
        )
        try await runSpeed(
            service: service,
            ffmpegPath: ffmpegPath,
            ffprobePath: ffprobePath,
            request: speedRequest(input: input, output: directory.appendingPathComponent("speed-0_25x.mp4"), speed: 0.25, hasAudio: true, audioMode: .keep)
        )
        try await runSpeed(
            service: service,
            ffmpegPath: ffmpegPath,
            ffprobePath: ffprobePath,
            request: speedRequest(input: input, output: directory.appendingPathComponent("speed-4x.mp4"), speed: 4.0, hasAudio: true, audioMode: .keep)
        )
        try await runSpeed(
            service: service,
            ffmpegPath: ffmpegPath,
            ffprobePath: ffprobePath,
            request: speedRequest(input: input, output: directory.appendingPathComponent("speed-muted.mp4"), speed: 1.5, hasAudio: true, audioMode: .remove)
        )
        try await runSpeed(
            service: service,
            ffmpegPath: ffmpegPath,
            ffprobePath: ffprobePath,
            request: speedRequest(input: noAudioInput, output: directory.appendingPathComponent("speed-no-audio.mp4"), speed: 1.5, hasAudio: false, audioMode: .keep)
        )
    }

    func testOptionalFFmpegSyntheticFrameExport() async throws {
        let tools = try MediaFixtures.requireTools()
        try await MediaFixtures.ensureGenerated()
        let fixture = try MediaFixtures.fixture(id: "frameIdentifiable")
        let input = MediaFixtures.url(for: fixture)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pngStart = directory.appendingPathComponent("frame-start.png")
        let pngLater = directory.appendingPathComponent("frame-later.png")
        let jpegNearEnd = directory.appendingPathComponent("frame-end.jpg")
        let service = VideoEditingService()

        let startRequest = try frameExportRequest(input: input, fixture: fixture, output: pngStart, timestamp: 0, format: .png)
        let laterRequest = try frameExportRequest(input: input, fixture: fixture, output: pngLater, timestamp: 1.25, format: .png)
        let jpegRequest = try frameExportRequest(input: input, fixture: fixture, output: jpegNearEnd, timestamp: 2.75, format: .jpeg)

        let startCommand = try service.frameExportCommand(ffmpegPath: tools.ffmpeg, request: startRequest)
        XCTAssertEqual(startCommand.arguments.commandValue(after: "-i"), input.path)
        XCTAssertGreaterThan(
            try XCTUnwrap(startCommand.arguments.firstIndex(of: "-ss")),
            try XCTUnwrap(startCommand.arguments.firstIndex(of: "-i"))
        )

        for (request, command) in [
            (startRequest, startCommand),
            (laterRequest, try service.frameExportCommand(ffmpegPath: tools.ffmpeg, request: laterRequest)),
            (jpegRequest, try service.frameExportCommand(ffmpegPath: tools.ffmpeg, request: jpegRequest))
        ] {
            let result = try await ProcessRunner().run(executablePath: command.executablePath, arguments: command.arguments)
            XCTAssertEqual(result.exitCode, 0, result.stderrText)
            let info = try FrameExportOutputValidator.verify(imageURL: request.outputURL, request: request)
            XCTAssertEqual(info.dimensions, VideoDimensions(width: 160, height: 120))
        }

        XCTAssertNotEqual(try Data(contentsOf: pngStart), try Data(contentsOf: pngLater))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(), [
            "frame-end.jpg",
            "frame-later.png",
            "frame-start.png"
        ])
    }

    func testOptionalFFmpegSyntheticIntervalFrameExport() async throws {
        let tools = try MediaFixtures.requireTools()
        try await MediaFixtures.ensureGenerated()
        let standard = try MediaFixtures.fixture(id: "standardLandscape")
        let input = MediaFixtures.url(for: standard)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let service = VideoEditingService()

        let entireDirectory = directory.appendingPathComponent("entire", isDirectory: true)
        let rangeDirectory = directory.appendingPathComponent("range", isDirectory: true)
        let fractionalDirectory = directory.appendingPathComponent("fractional", isDirectory: true)
        let jpegDirectory = directory.appendingPathComponent("jpeg", isDirectory: true)
        for outputDirectory in [entireDirectory, rangeDirectory, fractionalDirectory, jpegDirectory] {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        }

        let entire = try intervalRequest(input: input, fixture: standard, outputDirectory: entireDirectory, start: 0, end: 10, interval: 2, format: .png)
        try await runIntervalFrameExport(service: service, ffmpegPath: tools.ffmpeg, request: entire)

        let range = try intervalRequest(input: input, fixture: standard, outputDirectory: rangeDirectory, start: 2, end: 8, interval: 2, format: .png)
        try await runIntervalFrameExport(service: service, ffmpegPath: tools.ffmpeg, request: range)

        let fractional = try intervalRequest(input: input, fixture: standard, outputDirectory: fractionalDirectory, start: 0, end: 2, interval: 0.5, format: .png)
        try await runIntervalFrameExport(service: service, ffmpegPath: tools.ffmpeg, request: fractional)

        let jpeg = try intervalRequest(input: input, fixture: standard, outputDirectory: jpegDirectory, start: 0, end: 2, interval: 1, format: .jpeg)
        try await runIntervalFrameExport(service: service, ffmpegPath: tools.ffmpeg, request: jpeg)

        let first = try Data(contentsOf: entire.outputURL(forSequenceNumber: 1))
        let middle = try Data(contentsOf: entire.outputURL(forSequenceNumber: 3))
        XCTAssertNotEqual(first, middle)
    }

    func testOptionalFFmpegSyntheticGIFExport() async throws {
        let tools = try MediaFixtures.requireTools()
        try await MediaFixtures.ensureGenerated()
        let standard = try MediaFixtures.fixture(id: "standardLandscape")
        let portrait = try MediaFixtures.fixture(id: "portraitVideo")
        let vfr = try MediaFixtures.fixture(id: "variableFrameRate")
        let service = VideoEditingService()

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let basic = try gifRequest(
            input: MediaFixtures.url(for: standard),
            fixture: standard,
            output: directory.appendingPathComponent("basic.gif"),
            start: 0,
            end: 2,
            width: .wide320,
            quality: .balanced,
            loop: .forever
        )
        try await runGIFExport(service: service, ffmpegPath: tools.ffmpeg, request: basic)

        let playOnce = try gifRequest(
            input: MediaFixtures.url(for: standard),
            fixture: standard,
            output: directory.appendingPathComponent("play-once.gif"),
            start: 1,
            end: 3,
            width: .wide320,
            quality: .high,
            loop: .once
        )
        try await runGIFExport(service: service, ffmpegPath: tools.ffmpeg, request: playOnce)

        let portraitRequest = try gifRequest(
            input: MediaFixtures.url(for: portrait),
            fixture: portrait,
            output: directory.appendingPathComponent("portrait.gif"),
            start: 0,
            end: 2,
            width: .wide320,
            quality: .smallFile,
            loop: .forever
        )
        try await runGIFExport(service: service, ffmpegPath: tools.ffmpeg, request: portraitRequest)
        XCTAssertEqual(try GIFExportOutputValidator.verify(gifURL: portraitRequest.outputURL, request: portraitRequest).dimensions, VideoDimensions(width: 180, height: 320))

        let vfrRequest = try gifRequest(
            input: MediaFixtures.url(for: vfr),
            fixture: vfr,
            output: directory.appendingPathComponent("vfr.gif"),
            start: 0,
            end: 2,
            width: .wide320,
            quality: .balanced,
            loop: .forever
        )
        try await runGIFExport(service: service, ffmpegPath: tools.ffmpeg, request: vfrRequest)
    }

    private func transformRequest(
        input: URL,
        output: URL,
        width: Int = 320,
        height: Int = 180,
        sourceRotationDegrees: Int? = nil,
        rotation: VideoRotation = .none,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false,
        hasAudio: Bool = true
    ) -> VideoTransformRequest {
        VideoTransformRequest(
            inputURL: input,
            outputURL: output,
            sourceDuration: 2,
            sourceDimensions: VideoDimensions(width: width, height: height),
            sourceRotationDegrees: sourceRotationDegrees,
            hasVideoStream: true,
            hasAudioStream: hasAudio,
            rotation: rotation,
            flipHorizontal: flipHorizontal,
            flipVertical: flipVertical
        )
    }

    private func runTransform(
        service: VideoEditingService,
        ffmpegPath: String,
        ffprobePath: String,
        request: VideoTransformRequest,
        expectedDimensions: VideoDimensions,
        expectedAudio: Bool
    ) async throws {
        let command = try service.transformCommand(ffmpegPath: ffmpegPath, request: request)
        let result = try await ProcessRunner().run(executablePath: command.executablePath, arguments: command.arguments)
        XCTAssertEqual(result.exitCode, 0, result.stderrText)
        let metadata = try await FFprobeRunner().loadMetadata(ffprobePath: ffprobePath, inputURL: request.outputURL)
        XCTAssertEqual(metadata.videoCodec, "h264")
        XCTAssertEqual(metadata.width, expectedDimensions.width)
        XCTAssertEqual(metadata.height, expectedDimensions.height)
        XCTAssertEqual(metadata.audioCodec != nil, expectedAudio)
        XCTAssertTrue(metadata.rotationDegrees == nil || metadata.rotationDegrees == 0)
        XCTAssertNoThrow(try VideoTransformOutputValidator.verify(metadata: metadata, request: request))
    }

    private func runEditPlan(
        service: VideoEditingService,
        ffmpegPath: String,
        ffprobePath: String,
        plan: VideoEditPlan
    ) async throws {
        let command = try service.editPlanCommand(ffmpegPath: ffmpegPath, plan: plan)
        let result = try await ProcessRunner().run(executablePath: command.executablePath, arguments: command.arguments)
        XCTAssertEqual(result.exitCode, 0, result.stderrText)
        let metadata = try await FFprobeRunner().loadMetadata(ffprobePath: ffprobePath, inputURL: plan.outputURL)
        XCTAssertNoThrow(try VideoEditPlanOutputValidator.verify(metadata: metadata, plan: plan))
    }

    private func speedRequest(
        input: URL,
        output: URL,
        speed: Double,
        hasAudio: Bool,
        audioMode: SpeedAudioMode
    ) throws -> VideoSpeedRequest {
        VideoSpeedRequest(
            inputURL: input,
            outputURL: output,
            sourceDuration: 2,
            sourceDimensions: VideoDimensions(width: 160, height: 120),
            sourceRotationDegrees: nil,
            hasVideoStream: true,
            hasAudioStream: hasAudio,
            speed: try VideoSpeed(multiplier: speed),
            audioMode: audioMode
        )
    }

    private func runSpeed(
        service: VideoEditingService,
        ffmpegPath: String,
        ffprobePath: String,
        request: VideoSpeedRequest
    ) async throws {
        let command = try service.speedCommand(ffmpegPath: ffmpegPath, request: request)
        let result = try await ProcessRunner().run(executablePath: command.executablePath, arguments: command.arguments)
        XCTAssertEqual(result.exitCode, 0, result.stderrText)
        let metadata = try await FFprobeRunner().loadMetadata(ffprobePath: ffprobePath, inputURL: request.outputURL)
        XCTAssertEqual(metadata.videoCodec, "h264")
        XCTAssertEqual(metadata.audioCodec != nil, request.keepsAudio)
        XCTAssertNoThrow(try VideoSpeedOutputValidator.verify(metadata: metadata, request: request))
    }

    private func frameExportRequest(
        input: URL,
        fixture: MediaFixture,
        output: URL,
        timestamp: TimeInterval,
        format: FrameImageFormat
    ) throws -> FrameExportRequest {
        FrameExportRequest(
            inputURL: input,
            outputURL: output,
            timestampSeconds: timestamp,
            sourceDuration: fixture.durationSeconds,
            sourceDimensions: VideoDimensions(width: fixture.codedWidth, height: fixture.codedHeight),
            sourceRotationDegrees: fixture.rotationDegrees,
            hasVideoStream: true,
            format: format,
            jpegQuality: format == .jpeg ? try JPEGQuality(ffmpegValue: 4) : nil
        )
    }

    private func intervalRequest(
        input: URL,
        fixture: MediaFixture,
        outputDirectory: URL,
        start: TimeInterval,
        end: TimeInterval,
        interval: TimeInterval,
        format: FrameImageFormat
    ) throws -> IntervalFrameExportRequest {
        IntervalFrameExportRequest(
            inputURL: input,
            outputDirectoryURL: outputDirectory,
            sourceDuration: fixture.durationSeconds,
            sourceDimensions: VideoDimensions(width: fixture.codedWidth, height: fixture.codedHeight),
            sourceRotationDegrees: fixture.rotationDegrees,
            hasVideoStream: true,
            interval: try FrameInterval(seconds: interval),
            range: try FrameExportRange(startSeconds: start, endSeconds: end, sourceDuration: fixture.durationSeconds),
            format: format,
            jpegQuality: format == .jpeg ? try JPEGQuality(ffmpegValue: 4) : nil,
            countTolerance: 1
        )
    }

    private func gifRequest(
        input: URL,
        fixture: MediaFixture,
        output: URL,
        start: TimeInterval,
        end: TimeInterval,
        width: GIFSizePreset,
        quality: GIFQualityPreset,
        loop: GIFLoopMode
    ) throws -> GIFExportRequest {
        GIFExportRequest(
            inputURL: input,
            outputURL: output,
            sourceDuration: fixture.durationSeconds,
            sourceDimensions: VideoDimensions(width: fixture.codedWidth, height: fixture.codedHeight),
            sourceRotationDegrees: fixture.rotationDegrees,
            hasVideoStream: true,
            range: try FrameExportRange(startSeconds: start, endSeconds: end, sourceDuration: fixture.durationSeconds),
            frameRate: try GIFFrameRate(framesPerSecond: 10),
            sizePreset: width,
            customWidth: nil,
            quality: quality,
            loopMode: loop,
            frameCountTolerance: 2,
            durationTolerance: 0.45
        )
    }

    private func runGIFExport(
        service: VideoEditingService,
        ffmpegPath: String,
        request: GIFExportRequest
    ) async throws {
        let command = try service.gifExportCommand(ffmpegPath: ffmpegPath, request: request)
        XCTAssertTrue(command.arguments.contains("-filter_complex"))
        XCTAssertFalse(command.arguments.joined(separator: " ").contains("\""))
        let result = try await ProcessRunner().run(executablePath: command.executablePath, arguments: command.arguments)
        XCTAssertEqual(result.exitCode, 0, result.stderrText)
        let verification = try GIFExportOutputValidator.verify(gifURL: request.outputURL, request: request)
        XCTAssertGreaterThan(verification.frameCount, 1)
        XCTAssertEqual(verification.dimensions, try request.outputDimensions())
    }

    private func runIntervalFrameExport(
        service: VideoEditingService,
        ffmpegPath: String,
        request: IntervalFrameExportRequest
    ) async throws {
        let command = try service.intervalFrameExportCommand(ffmpegPath: ffmpegPath, request: request)
        let result = try await ProcessRunner().run(executablePath: command.executablePath, arguments: command.arguments)
        XCTAssertEqual(result.exitCode, 0, result.stderrText)
        let files = IntervalFrameExportOutputValidator.matchingFiles(
            in: request.outputDirectoryURL,
            request: request,
            fileSystem: LocalEditingFileSystem()
        )
        let verification = try IntervalFrameExportOutputValidator.verify(request: request, files: files)
        XCTAssertEqual(verification.dimensions, try request.expectedDimensions())
        XCTAssertGreaterThanOrEqual(verification.imageCount, max(1, request.expectedImageCount - request.countTolerance))
        XCTAssertLessThanOrEqual(verification.imageCount, request.expectedImageCount + request.countTolerance)
    }
}

private extension Array where Element == String {
    func commandValue(after option: String) -> String? {
        guard let index = firstIndex(of: option), indices.contains(index + 1) else { return nil }
        return self[index + 1]
    }
}
