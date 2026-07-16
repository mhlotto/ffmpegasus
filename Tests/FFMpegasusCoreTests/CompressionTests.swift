import XCTest
@testable import FFMpegasusCore

final class CompressionTests: XCTestCase {
    func testQualityPresets() throws {
        XCTAssertEqual(try CompressionQuality.highQuality.settings(customCRF: 24, customPreset: .slow), try CompressionQualitySettings(crf: 20, preset: .medium))
        XCTAssertEqual(try CompressionQuality.balanced.settings(customCRF: 20, customPreset: .slow), try CompressionQualitySettings(crf: 24, preset: .medium))
        XCTAssertEqual(try CompressionQuality.smallFile.settings(customCRF: 20, customPreset: .medium), try CompressionQualitySettings(crf: 28, preset: .slow))
        XCTAssertEqual(try CompressionQuality.custom.settings(customCRF: 22, customPreset: .fast), try CompressionQualitySettings(crf: 22, preset: .fast))
    }

    func testInvalidCRFValuesAreRejected() {
        XCTAssertThrowsError(try CompressionQualitySettings(crf: 15, preset: .medium))
        XCTAssertThrowsError(try CompressionQualitySettings(crf: 36, preset: .medium))
    }

    func testUnsupportedPresetStringIsRejected() {
        XCTAssertNil(EncoderPreset(rawValue: "placebo"))
    }

    func testResolutionCalculations() throws {
        XCTAssertEqual(try request(width: 1920, height: 1080, resolution: .p720).outputDimensions(), VideoDimensions(width: 1280, height: 720))
        XCTAssertEqual(try request(width: 3840, height: 2160, resolution: .p720).outputDimensions(), VideoDimensions(width: 1280, height: 720))
        XCTAssertEqual(try request(width: 1280, height: 720, resolution: .p1080).outputDimensions(), VideoDimensions(width: 1280, height: 720))
        XCTAssertEqual(try request(width: 1080, height: 1920, resolution: .p720).outputDimensions(), VideoDimensions(width: 404, height: 720))
        XCTAssertEqual(try request(width: 853, height: 480, resolution: .original).outputDimensions(), VideoDimensions(width: 852, height: 480))
    }

    func testScaleFilterOnlyWhenNeeded() throws {
        XCTAssertNil(try request(width: 1280, height: 720, resolution: .original).scaleFilter())
        XCTAssertNil(try request(width: 1280, height: 720, resolution: .p1080).scaleFilter())
        XCTAssertEqual(try request(width: 1920, height: 1080, resolution: .p720).scaleFilter(), "scale=-2:min(720\\,ih)")
    }

    func testInvalidCustomResolutionValues() {
        XCTAssertThrowsError(try request(width: 1920, height: 1080, resolution: .custom, customHeight: 143).outputDimensions())
        XCTAssertThrowsError(try request(width: 1920, height: 1080, resolution: .custom, customHeight: 1200).outputDimensions())
        XCTAssertThrowsError(try request(width: 1920, height: 1080, resolution: .custom, customHeight: nil).outputDimensions())
    }

    func testCompressionCommandKeepsAudio() throws {
        let command = try VideoEditingService().compressionCommand(ffmpegPath: "/opt/homebrew/bin/ffmpeg", request: request())

        XCTAssertTrue(command.arguments.contains("-nostdin"))
        XCTAssertEqual(command.arguments.commandValue(after: "-map"), "0:v:0")
        XCTAssertTrue(command.arguments.contains("0:a:0?"))
        XCTAssertEqual(command.arguments.commandValue(after: "-c:v"), "libx264")
        XCTAssertEqual(command.arguments.commandValue(after: "-crf"), "24")
        XCTAssertEqual(command.arguments.commandValue(after: "-preset"), "medium")
        XCTAssertEqual(command.arguments.commandValue(after: "-pix_fmt"), "yuv420p")
        XCTAssertEqual(command.arguments.commandValue(after: "-movflags"), "+faststart")
        XCTAssertEqual(command.arguments.commandValue(after: "-c:a"), "aac")
        XCTAssertEqual(command.arguments.commandValue(after: "-b:a"), "128k")
        XCTAssertFalse(command.arguments.contains("-c"))
        XCTAssertFalse(command.arguments.contains("\"scale=-2:min(720\\,ih)\""))
        XCTAssertEqual(command.arguments.commandValue(after: "-vf"), "scale=-2:min(720\\,ih)")
    }

    func testCompressionCommandRemovesAudio() throws {
        let command = try VideoEditingService().compressionCommand(ffmpegPath: "/opt/homebrew/bin/ffmpeg", request: request(audioMode: .remove))

        XCTAssertTrue(command.arguments.contains("-an"))
        XCTAssertFalse(command.arguments.contains("-c:a"))
        XCTAssertFalse(command.arguments.contains("0:a:0?"))
    }

    func testCompressionCommandSupportsPathsContainingSpaces() throws {
        let command = try VideoEditingService().compressionCommand(
            ffmpegPath: "/opt/homebrew/bin/ffmpeg",
            request: request(input: "/tmp/Input Video.mov", output: "/tmp/Output Video.mp4")
        )

        XCTAssertEqual(command.arguments.commandValue(after: "-i"), "/tmp/Input Video.mov")
        XCTAssertEqual(command.arguments.last, "/tmp/Output Video.mp4")
    }

    func testCompressedFilenameAlwaysUsesMP4() {
        XCTAssertEqual(OutputFilename.compressedName(for: URL(fileURLWithPath: "/tmp/input.mp4")), "input-compressed.mp4")
        XCTAssertEqual(OutputFilename.compressedName(for: URL(fileURLWithPath: "/tmp/input.mov")), "input-compressed.mp4")
        XCTAssertEqual(OutputFilename.compressedName(for: URL(fileURLWithPath: "/tmp/input.mkv")), "input-compressed.mp4")
        XCTAssertEqual(OutputFilename.compressedName(for: URL(fileURLWithPath: "/tmp/input-compressed.mp4")), "input-compressed-compressed.mp4")
    }

    private func request(
        input: String = "/tmp/input.mov",
        output: String = "/tmp/output.mp4",
        width: Int = 1920,
        height: Int = 1080,
        quality: CompressionQuality = .balanced,
        customCRF: Int = 24,
        preset: EncoderPreset = .medium,
        resolution: OutputResolution = .p720,
        customHeight: Int? = nil,
        audioMode: CompressionAudioMode = .keep,
        hasAudio: Bool = true
    ) -> CompressionRequest {
        CompressionRequest(
            inputURL: URL(fileURLWithPath: input),
            outputURL: URL(fileURLWithPath: output),
            sourceDuration: 10,
            sourceDimensions: VideoDimensions(width: width, height: height),
            hasVideoStream: true,
            hasAudioStream: hasAudio,
            quality: quality,
            customCRF: customCRF,
            encoderPreset: preset,
            resolution: resolution,
            customHeight: customHeight,
            audioMode: audioMode
        )
    }
}

private extension Array where Element == String {
    func commandValue(after option: String) -> String? {
        guard let index = firstIndex(of: option), indices.contains(index + 1) else { return nil }
        return self[index + 1]
    }
}
