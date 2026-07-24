import XCTest
@testable import FFMpegasusCore

final class ExportProfileTests: XCTestCase {
    func testProfileDefinitions() throws {
        XCTAssertEqual(ExportProfile.mp4H264.displayName, "MP4 - H.264")
        XCTAssertEqual(ExportProfile.mp4H264.fileExtension, "mp4")
        XCTAssertEqual(ExportProfile.mp4HEVC.fileExtension, "mp4")
        XCTAssertEqual(ExportProfile.webmVP9.fileExtension, "webm")
        XCTAssertEqual(ExportProfile.movProRes422.fileExtension, "mov")
        XCTAssertEqual(ExportProfile.mp4H264.requiredVideoEncoder, "libx264")
        XCTAssertEqual(ExportProfile.mp4HEVC.requiredVideoEncoder, "libx265")
        XCTAssertEqual(ExportProfile.webmVP9.requiredVideoEncoder, "libvpx-vp9")
        XCTAssertEqual(ExportProfile.webmVP9.requiredAudioEncoder, "libopus")
        XCTAssertEqual(ExportProfile.movProRes422.requiredVideoEncoder, "prores_ks")
        XCTAssertTrue(ExportProfile.movProRes422.isLargeOutputProfile)
    }

    func testCapabilityDetectionIdentifiesMissingEncoders() {
        let capabilities = ExportProfileCapabilities(encoders: ["libx264", "aac", "libvpx-vp9"])
        XCTAssertTrue(capabilities.support(for: .mp4H264).isSupported)
        XCTAssertFalse(capabilities.support(for: .webmVP9).isSupported)
        XCTAssertEqual(capabilities.support(for: .webmVP9).missingEncoders, ["libopus"])
        XCTAssertFalse(capabilities.support(for: .mp4HEVC).isSupported)
    }

    func testHEVCCompressionCommand() throws {
        let command = try VideoEditingService().compressionCommand(
            ffmpegPath: "/opt/homebrew/bin/ffmpeg",
            request: compressionRequest(profile: .mp4HEVC)
        )
        XCTAssertEqual(command.arguments.commandValue(after: "-c:v"), "libx265")
        XCTAssertEqual(command.arguments.commandValue(after: "-c:a"), "aac")
        XCTAssertEqual(command.arguments.commandValue(after: "-tag:v"), "hvc1")
        XCTAssertEqual(command.arguments.commandValue(after: "-movflags"), "+faststart")
        XCTAssertFalse(command.arguments.contains("libx264"))
    }

    func testVP9CompressionCommand() throws {
        let command = try VideoEditingService().compressionCommand(
            ffmpegPath: "/opt/homebrew/bin/ffmpeg",
            request: compressionRequest(profile: .webmVP9, output: "output.webm")
        )
        XCTAssertEqual(command.arguments.commandValue(after: "-c:v"), "libvpx-vp9")
        XCTAssertEqual(command.arguments.commandValue(after: "-c:a"), "libopus")
        XCTAssertEqual(command.arguments.commandValue(after: "-b:v"), "0")
        XCTAssertNil(command.arguments.commandValue(after: "-movflags"))
        XCTAssertFalse(command.arguments.contains("aac"))
    }

    func testProResCompressionCommand() throws {
        let command = try VideoEditingService().compressionCommand(
            ffmpegPath: "/opt/homebrew/bin/ffmpeg",
            request: compressionRequest(profile: .movProRes422, output: "output.mov")
        )
        XCTAssertEqual(command.arguments.commandValue(after: "-c:v"), "prores_ks")
        XCTAssertEqual(command.arguments.commandValue(after: "-profile:v"), "2")
        XCTAssertEqual(command.arguments.commandValue(after: "-pix_fmt"), "yuv422p10le")
        XCTAssertEqual(command.arguments.commandValue(after: "-c:a"), "pcm_s16le")
        XCTAssertFalse(command.arguments.contains("-crf"))
        XCTAssertFalse(command.arguments.contains("-preset"))
    }

    func testRemoveAudioPolicyAppliesForEveryProfile() throws {
        let command = try VideoEditingService().compressionCommand(
            ffmpegPath: "/opt/homebrew/bin/ffmpeg",
            request: compressionRequest(profile: .webmVP9, output: "output.webm", audioMode: .remove)
        )
        XCTAssertTrue(command.arguments.contains("-an"))
        XCTAssertFalse(command.arguments.contains("libopus"))
        XCTAssertFalse(command.arguments.contains("aac"))
    }

    func testNonH264TrimForcesReencode() throws {
        let request = EditingRequest(
            inputURL: URL(fileURLWithPath: "/tmp/input.mov"),
            outputURL: URL(fileURLWithPath: "/tmp/output.webm"),
            sourceDuration: 20,
            removeStartSeconds: 2,
            removeEndSeconds: 3,
            mode: .trimBoth,
            method: .streamCopy,
            trimExecutionMode: .fast,
            hasVideoStream: true,
            hasAudioStream: true,
            exportProfile: .webmVP9
        )
        XCTAssertEqual(request.effectiveTrimExecutionMode, .accurate)
        let command = try VideoEditingService().command(ffmpegPath: "/opt/homebrew/bin/ffmpeg", request: request)
        XCTAssertEqual(command.arguments.commandValue(after: "-c:v"), "libvpx-vp9")
        XCTAssertFalse(command.arguments.contains("-c"))
        XCTAssertFalse(command.arguments.contains("copy"))
    }

    func testCombinedExportProfileForcesReencode() throws {
        let plan = VideoEditPlan(
            inputURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            outputURL: URL(fileURLWithPath: "/tmp/output.mov"),
            sourceDuration: 20,
            sourceDimensions: VideoDimensions(width: 1920, height: 1080),
            sourceRotationDegrees: nil,
            hasVideoStream: true,
            hasAudioStream: true,
            trim: TrimConfiguration(mode: .trimStart, removeStartSeconds: 2, removeEndSeconds: 0, executionMode: .fast),
            transform: nil,
            resize: nil,
            compression: nil,
            audioMode: .keep,
            exportProfile: .movProRes422
        )
        XCTAssertEqual(try plan.executionStrategy(), .reencode)
        let command = try VideoEditingService().editPlanCommand(ffmpegPath: "/opt/homebrew/bin/ffmpeg", plan: plan)
        XCTAssertEqual(command.arguments.commandValue(after: "-c:v"), "prores_ks")
        XCTAssertEqual(command.arguments.commandValue(after: "-c:a"), "pcm_s16le")
    }

    func testProfileVerification() throws {
        XCTAssertNoThrow(try ExportProfileOutputValidator.verify(
            metadata: metadata(formatName: "matroska,webm", videoCodec: "vp9", audioCodec: "opus"),
            profile: .webmVP9,
            outputURL: URL(fileURLWithPath: "/tmp/output.webm"),
            expectsAudio: true
        ))
        XCTAssertThrowsError(try ExportProfileOutputValidator.verify(
            metadata: metadata(formatName: "matroska,webm", videoCodec: "h264", audioCodec: "opus"),
            profile: .webmVP9,
            outputURL: URL(fileURLWithPath: "/tmp/output.webm"),
            expectsAudio: true
        ))
        XCTAssertThrowsError(try ExportProfileOutputValidator.verify(
            metadata: metadata(formatName: "mov,mp4,m4a,3gp,3g2,mj2", videoCodec: "hevc", audioCodec: "aac"),
            profile: .mp4HEVC,
            outputURL: URL(fileURLWithPath: "/tmp/output.webm"),
            expectsAudio: true
        ))
    }

    private func compressionRequest(
        profile: ExportProfile,
        output: String = "output.mp4",
        audioMode: CompressionAudioMode = .keep
    ) -> CompressionRequest {
        CompressionRequest(
            inputURL: URL(fileURLWithPath: "/tmp/input with spaces.mov"),
            outputURL: URL(fileURLWithPath: "/tmp/\(output)"),
            sourceDuration: 10,
            sourceDimensions: VideoDimensions(width: 1920, height: 1080),
            hasVideoStream: true,
            hasAudioStream: true,
            quality: .balanced,
            customCRF: 24,
            encoderPreset: .medium,
            resolution: .p720,
            customHeight: nil,
            audioMode: audioMode,
            exportProfile: profile
        )
    }

    private func metadata(formatName: String, videoCodec: String?, audioCodec: String?) -> VideoMetadata {
        VideoMetadata(
            duration: 10,
            width: 1280,
            height: 720,
            videoCodec: videoCodec,
            audioCodec: audioCodec,
            frameRate: 30,
            formatName: formatName
        )
    }
}

private extension Array where Element == String {
    func commandValue(after option: String) -> String? {
        guard let index = firstIndex(of: option), indices.contains(index + 1) else { return nil }
        return self[index + 1]
    }
}
