import XCTest
@testable import FFMpegasusCore

final class CompressionVerificationTests: XCTestCase {
    func testValidH264OutputSucceeds() throws {
        XCTAssertNoThrow(try CompressionOutputValidator.verify(metadata: metadata(), request: request()))
    }

    func testWrongCodecFails() {
        XCTAssertThrowsError(try CompressionOutputValidator.verify(metadata: metadata(videoCodec: "hevc"), request: request()))
    }

    func testOversizedDimensionsFail() {
        XCTAssertThrowsError(try CompressionOutputValidator.verify(metadata: metadata(width: 1920, height: 1080), request: request()))
    }

    func testOddDimensionsFail() {
        XCTAssertThrowsError(try CompressionOutputValidator.verify(metadata: metadata(width: 1279, height: 719), request: request()))
    }

    func testUnexpectedAudioFails() {
        XCTAssertThrowsError(try CompressionOutputValidator.verify(metadata: metadata(audioCodec: "aac"), request: request(audioMode: .remove)))
    }

    func testMissingExpectedAudioFails() {
        XCTAssertThrowsError(try CompressionOutputValidator.verify(metadata: metadata(audioCodec: nil), request: request(audioMode: .keep)))
    }

    func testDurationMismatchFails() {
        XCTAssertThrowsError(try CompressionOutputValidator.verify(metadata: metadata(duration: 80), request: request()))
    }

    private func request(audioMode: CompressionAudioMode = .keep) -> CompressionRequest {
        CompressionRequest(
            inputURL: URL(fileURLWithPath: "/tmp/input.mov"),
            outputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
            sourceDuration: 100,
            sourceDimensions: VideoDimensions(width: 1920, height: 1080),
            hasVideoStream: true,
            hasAudioStream: true,
            quality: .balanced,
            customCRF: 24,
            encoderPreset: .medium,
            resolution: .p720,
            customHeight: nil,
            audioMode: audioMode
        )
    }

    private func metadata(
        duration: TimeInterval = 100,
        width: Int = 1280,
        height: Int = 720,
        videoCodec: String? = "h264",
        audioCodec: String? = "aac"
    ) -> VideoMetadata {
        VideoMetadata(duration: duration, width: width, height: height, videoCodec: videoCodec, audioCodec: audioCodec, frameRate: 30, pixelFormat: "yuv420p")
    }
}
