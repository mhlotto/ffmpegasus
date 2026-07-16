import XCTest
@testable import FFMpegasusCore

final class TrimOutputVerificationTests: XCTestCase {
    func testValidFastOutputSucceedsWithinFastTolerance() throws {
        XCTAssertNoThrow(try TrimOutputValidator.verify(metadata: metadata(duration: 21.0, videoCodec: "h264"), request: request(mode: .fast)))
    }

    func testFastOutputOutsideToleranceFails() {
        XCTAssertThrowsError(try TrimOutputValidator.verify(metadata: metadata(duration: 22.1), request: request(mode: .fast)))
    }

    func testValidAccurateOutputSucceedsWithinAccurateTolerance() throws {
        XCTAssertNoThrow(try TrimOutputValidator.verify(metadata: metadata(duration: 20.9), request: request(mode: .accurate)))
    }

    func testAccurateOutputOutsideToleranceFails() {
        XCTAssertThrowsError(try TrimOutputValidator.verify(metadata: metadata(duration: 20.8), request: request(mode: .accurate)))
    }

    func testAccurateOutputWithWrongCodecFails() {
        XCTAssertThrowsError(try TrimOutputValidator.verify(metadata: metadata(videoCodec: "hevc"), request: request(mode: .accurate)))
    }

    func testAccurateOutputWithOddDimensionsFails() {
        XCTAssertThrowsError(try TrimOutputValidator.verify(metadata: metadata(width: 1279, height: 720), request: request(mode: .accurate)))
    }

    func testAccurateOutputMissingExpectedAudioFails() {
        XCTAssertThrowsError(try TrimOutputValidator.verify(metadata: metadata(audioCodec: nil), request: request(mode: .accurate, hasAudioStream: true)))
    }

    func testAccurateOutputWithoutSourceAudioSucceedsWithoutAudio() throws {
        XCTAssertNoThrow(try TrimOutputValidator.verify(metadata: metadata(audioCodec: nil), request: request(mode: .accurate, hasAudioStream: false)))
    }

    func testMissingVideoStreamFails() {
        XCTAssertThrowsError(try TrimOutputValidator.verify(metadata: metadata(videoCodec: nil), request: request(mode: .fast)))
    }

    private func request(mode: TrimExecutionMode, hasAudioStream: Bool = true) -> EditingRequest {
        EditingRequest(
            inputURL: URL(fileURLWithPath: "/tmp/input.mov"),
            outputURL: URL(fileURLWithPath: mode == .accurate ? "/tmp/output.mp4" : "/tmp/output.mov"),
            sourceDuration: 30,
            removeStartSeconds: 5,
            removeEndSeconds: 4,
            mode: .trimBoth,
            method: .streamCopy,
            trimExecutionMode: mode,
            hasVideoStream: true,
            hasAudioStream: hasAudioStream
        )
    }

    private func metadata(
        duration: TimeInterval = 21,
        width: Int = 1280,
        height: Int = 720,
        videoCodec: String? = "h264",
        audioCodec: String? = "aac"
    ) -> VideoMetadata {
        VideoMetadata(duration: duration, width: width, height: height, videoCodec: videoCodec, audioCodec: audioCodec, frameRate: 30, pixelFormat: "yuv420p")
    }
}
