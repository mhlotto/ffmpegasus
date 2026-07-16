import XCTest
@testable import FFMpegasusCore

final class VideoTransformVerificationTests: XCTestCase {
    func testValidClockwiseOutputSucceeds() throws {
        XCTAssertNoThrow(try VideoTransformOutputValidator.verify(metadata: metadata(width: 1080, height: 1920), request: request(rotation: .clockwise90)))
    }

    func testValidCounterclockwiseOutputSucceeds() throws {
        XCTAssertNoThrow(try VideoTransformOutputValidator.verify(metadata: metadata(width: 1080, height: 1920), request: request(rotation: .counterclockwise90)))
    }

    func testValidRotate180OutputSucceeds() throws {
        XCTAssertNoThrow(try VideoTransformOutputValidator.verify(metadata: metadata(), request: request(rotation: .rotate180)))
    }

    func testValidFlipOutputSucceeds() throws {
        XCTAssertNoThrow(try VideoTransformOutputValidator.verify(metadata: metadata(), request: request(flipHorizontal: true)))
    }

    func testWrongDimensionsFail() {
        XCTAssertThrowsError(try VideoTransformOutputValidator.verify(metadata: metadata(width: 1920, height: 1080), request: request(rotation: .clockwise90)))
    }

    func testWrongCodecFails() {
        XCTAssertThrowsError(try VideoTransformOutputValidator.verify(metadata: metadata(videoCodec: "hevc"), request: request(rotation: .rotate180)))
    }

    func testMissingVideoFails() {
        XCTAssertThrowsError(try VideoTransformOutputValidator.verify(metadata: metadata(videoCodec: nil), request: request(rotation: .rotate180)))
    }

    func testMissingExpectedAudioFails() {
        XCTAssertThrowsError(try VideoTransformOutputValidator.verify(metadata: metadata(audioCodec: nil), request: request(rotation: .rotate180, hasAudio: true)))
    }

    func testUnexpectedAudioFails() {
        XCTAssertThrowsError(try VideoTransformOutputValidator.verify(metadata: metadata(audioCodec: "aac"), request: request(rotation: .rotate180, hasAudio: false)))
    }

    func testStaleRotationMetadataFails() {
        XCTAssertThrowsError(try VideoTransformOutputValidator.verify(metadata: metadata(rotationDegrees: 90), request: request(rotation: .rotate180)))
    }

    func testDurationMismatchFails() {
        XCTAssertThrowsError(try VideoTransformOutputValidator.verify(metadata: metadata(duration: 9.7), request: request(rotation: .rotate180)))
    }

    private func request(rotation: VideoRotation = .none, flipHorizontal: Bool = false, hasAudio: Bool = true) -> VideoTransformRequest {
        VideoTransformRequest(
            inputURL: URL(fileURLWithPath: "/tmp/input.mov"),
            outputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
            sourceDuration: 10,
            sourceDimensions: VideoDimensions(width: 1920, height: 1080),
            sourceRotationDegrees: nil,
            hasVideoStream: true,
            hasAudioStream: hasAudio,
            rotation: rotation,
            flipHorizontal: flipHorizontal,
            flipVertical: false
        )
    }

    private func metadata(
        duration: TimeInterval = 10,
        width: Int = 1920,
        height: Int = 1080,
        videoCodec: String? = "h264",
        audioCodec: String? = "aac",
        rotationDegrees: Int? = nil
    ) -> VideoMetadata {
        VideoMetadata(duration: duration, width: width, height: height, videoCodec: videoCodec, audioCodec: audioCodec, frameRate: 30, pixelFormat: "yuv420p", rotationDegrees: rotationDegrees)
    }
}
