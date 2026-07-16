import XCTest
@testable import FFMpegasusCore

final class VideoTransformTests: XCTestCase {
    func testFilterConstruction() throws {
        XCTAssertThrowsError(try request(rotation: .none).filterChain())
        XCTAssertEqual(try request(rotation: .clockwise90).filterChain(), "transpose=clock")
        XCTAssertEqual(try request(rotation: .counterclockwise90).filterChain(), "transpose=cclock")
        XCTAssertEqual(try request(rotation: .rotate180).filterChain(), "hflip,vflip")
        XCTAssertEqual(try request(flipHorizontal: true).filterChain(), "hflip")
        XCTAssertEqual(try request(flipVertical: true).filterChain(), "vflip")
        XCTAssertEqual(try request(rotation: .clockwise90, flipHorizontal: true).filterChain(), "transpose=clock,hflip")
        XCTAssertEqual(try request(rotation: .counterclockwise90, flipVertical: true).filterChain(), "transpose=cclock,vflip")
        XCTAssertEqual(try request(flipHorizontal: true, flipVertical: true).filterChain(), "hflip,vflip")
    }

    func testDimensionCalculation() throws {
        XCTAssertEqual(try request(width: 1920, height: 1080, rotation: .clockwise90).outputDimensions(), VideoDimensions(width: 1080, height: 1920))
        XCTAssertEqual(try request(width: 1920, height: 1080, rotation: .counterclockwise90).outputDimensions(), VideoDimensions(width: 1080, height: 1920))
        XCTAssertEqual(try request(width: 1920, height: 1080, rotation: .rotate180).outputDimensions(), VideoDimensions(width: 1920, height: 1080))
        XCTAssertEqual(try request(width: 1920, height: 1080, flipHorizontal: true).outputDimensions(), VideoDimensions(width: 1920, height: 1080))
        XCTAssertEqual(try request(width: 1920, height: 1080, flipVertical: true).outputDimensions(), VideoDimensions(width: 1920, height: 1080))
        XCTAssertEqual(try request(width: 1080, height: 1920, rotation: .clockwise90).outputDimensions(), VideoDimensions(width: 1920, height: 1080))
        XCTAssertEqual(try request(width: 1919, height: 1079, rotation: .rotate180).outputDimensions(), VideoDimensions(width: 1918, height: 1078))
        XCTAssertEqual(try request(width: 1920, height: 1080, sourceRotationDegrees: 90, rotation: .none, flipHorizontal: true).normalizedSourceDimensions(), VideoDimensions(width: 1080, height: 1920))
    }

    func testTransformCommandKeepsAudio() throws {
        let command = try VideoEditingService().transformCommand(
            ffmpegPath: "/opt/homebrew/bin/ffmpeg",
            request: request(input: "/tmp/input.mov", output: "/tmp/output.mp4", rotation: .clockwise90, flipHorizontal: true)
        )

        XCTAssertTrue(command.arguments.contains("-nostdin"))
        XCTAssertEqual(command.arguments.commandValue(after: "-map"), "0:v:0")
        XCTAssertTrue(command.arguments.contains("0:a:0?"))
        XCTAssertEqual(command.arguments.commandValue(after: "-vf"), "transpose=clock,hflip")
        XCTAssertFalse(command.arguments.contains("\"transpose=clock,hflip\""))
        XCTAssertEqual(command.arguments.commandValue(after: "-c:v"), "libx264")
        XCTAssertEqual(command.arguments.commandValue(after: "-crf"), "20")
        XCTAssertEqual(command.arguments.commandValue(after: "-preset"), "medium")
        XCTAssertEqual(command.arguments.commandValue(after: "-pix_fmt"), "yuv420p")
        XCTAssertEqual(command.arguments.commandValue(after: "-c:a"), "aac")
        XCTAssertEqual(command.arguments.commandValue(after: "-b:a"), "128k")
        XCTAssertEqual(command.arguments.commandValue(after: "-movflags"), "+faststart")
        XCTAssertEqual(command.arguments.commandValue(after: "-metadata:s:v:0"), "rotate=0")
        XCTAssertFalse(command.arguments.contains("-c"))
        XCTAssertFalse(command.arguments.contains("copy"))
    }

    func testTransformCommandRemovesAudioWhenSourceHasNoAudio() throws {
        let command = try VideoEditingService().transformCommand(
            ffmpegPath: "/opt/homebrew/bin/ffmpeg",
            request: request(rotation: .clockwise90, hasAudio: false)
        )

        XCTAssertTrue(command.arguments.contains("-an"))
        XCTAssertFalse(command.arguments.contains("0:a:0?"))
        XCTAssertFalse(command.arguments.contains("-c:a"))
    }

    func testTransformCommandSupportsPathsContainingSpaces() throws {
        let command = try VideoEditingService().transformCommand(
            ffmpegPath: "/opt/homebrew/bin/ffmpeg",
            request: request(input: "/tmp/Input Video.mov", output: "/tmp/Output Video.mp4", rotation: .clockwise90)
        )

        XCTAssertEqual(command.arguments.commandValue(after: "-i"), "/tmp/Input Video.mov")
        XCTAssertEqual(command.arguments.last, "/tmp/Output Video.mp4")
    }

    func testTransformFilenames() {
        XCTAssertEqual(OutputFilename.transformedName(for: URL(fileURLWithPath: "/tmp/input.mp4"), rotation: .clockwise90, flipHorizontal: false, flipVertical: false), "input-rotated.mp4")
        XCTAssertEqual(OutputFilename.transformedName(for: URL(fileURLWithPath: "/tmp/input.mov"), rotation: .none, flipHorizontal: true, flipVertical: false), "input-flipped.mp4")
        XCTAssertEqual(OutputFilename.transformedName(for: URL(fileURLWithPath: "/tmp/input.mkv"), rotation: .clockwise90, flipHorizontal: true, flipVertical: false), "input-transformed.mp4")
    }

    private func request(
        input: String = "/tmp/input.mov",
        output: String = "/tmp/output.mp4",
        width: Int = 1920,
        height: Int = 1080,
        sourceRotationDegrees: Int? = nil,
        rotation: VideoRotation = .none,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false,
        hasAudio: Bool = true
    ) -> VideoTransformRequest {
        VideoTransformRequest(
            inputURL: URL(fileURLWithPath: input),
            outputURL: URL(fileURLWithPath: output),
            sourceDuration: 10,
            sourceDimensions: VideoDimensions(width: width, height: height),
            sourceRotationDegrees: sourceRotationDegrees,
            hasVideoStream: true,
            hasAudioStream: hasAudio,
            rotation: rotation,
            flipHorizontal: flipHorizontal,
            flipVertical: flipVertical
        )
    }
}

private extension Array where Element == String {
    func commandValue(after option: String) -> String? {
        guard let index = firstIndex(of: option), indices.contains(index + 1) else { return nil }
        return self[index + 1]
    }
}
