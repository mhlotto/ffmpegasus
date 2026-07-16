import XCTest
@testable import FFMpegasusCore

final class VideoSpeedVerificationTests: XCTestCase {
    func testValidSlowOutputSucceeds() throws {
        let request = speedRequest(speed: try VideoSpeed(multiplier: 0.5))
        let metadata = metadata(duration: 60, audioDuration: 60)
        XCTAssertNoThrow(try VideoSpeedOutputValidator.verify(metadata: metadata, request: request))
    }

    func testValidFastOutputSucceeds() throws {
        let request = speedRequest(speed: try VideoSpeed(multiplier: 2.0))
        let metadata = metadata(duration: 15, audioDuration: 15)
        XCTAssertNoThrow(try VideoSpeedOutputValidator.verify(metadata: metadata, request: request))
    }

    func testWrongDurationFails() throws {
        let request = speedRequest(speed: try VideoSpeed(multiplier: 2.0))
        XCTAssertThrowsError(try VideoSpeedOutputValidator.verify(metadata: metadata(duration: 20, audioDuration: 20), request: request))
    }

    func testWrongCodecFails() throws {
        let request = speedRequest(speed: try VideoSpeed(multiplier: 2.0))
        XCTAssertThrowsError(try VideoSpeedOutputValidator.verify(metadata: metadata(videoCodec: "hevc", duration: 15, audioDuration: 15), request: request))
    }

    func testMissingExpectedAudioFails() throws {
        let request = speedRequest(speed: try VideoSpeed(multiplier: 2.0))
        XCTAssertThrowsError(try VideoSpeedOutputValidator.verify(metadata: metadata(audioCodec: nil, duration: 15, audioDuration: nil), request: request))
    }

    func testUnexpectedAudioFails() throws {
        let request = speedRequest(speed: try VideoSpeed(multiplier: 2.0), audioMode: .remove)
        XCTAssertThrowsError(try VideoSpeedOutputValidator.verify(metadata: metadata(duration: 15, audioDuration: 15), request: request))
    }

    func testAudioVideoDurationMismatchFails() throws {
        let request = speedRequest(speed: try VideoSpeed(multiplier: 2.0))
        XCTAssertThrowsError(try VideoSpeedOutputValidator.verify(metadata: metadata(duration: 15, audioDuration: 14.7), request: request))
    }

    func testOddDimensionsFail() throws {
        let request = speedRequest(speed: try VideoSpeed(multiplier: 2.0))
        XCTAssertThrowsError(try VideoSpeedOutputValidator.verify(metadata: metadata(width: 1919, height: 1080, duration: 15, audioDuration: 15), request: request))
    }

    func testStaleRotationMetadataFails() throws {
        let request = speedRequest(speed: try VideoSpeed(multiplier: 2.0))
        XCTAssertThrowsError(try VideoSpeedOutputValidator.verify(metadata: metadata(duration: 15, audioDuration: 15, rotation: 90), request: request))
    }

    private func speedRequest(speed: VideoSpeed, audioMode: SpeedAudioMode = .keep) -> VideoSpeedRequest {
        VideoSpeedRequest(
            inputURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            outputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
            sourceDuration: 30,
            sourceDimensions: VideoDimensions(width: 1920, height: 1080),
            sourceRotationDegrees: nil,
            hasVideoStream: true,
            hasAudioStream: true,
            speed: speed,
            audioMode: audioMode
        )
    }

    private func metadata(
        videoCodec: String? = "h264",
        audioCodec: String? = "aac",
        width: Int? = 1920,
        height: Int? = 1080,
        duration: TimeInterval,
        audioDuration: TimeInterval?,
        rotation: Int? = nil
    ) -> VideoMetadata {
        VideoMetadata(
            duration: duration,
            width: width,
            height: height,
            videoCodec: videoCodec,
            audioCodec: audioCodec,
            audioDuration: audioDuration,
            frameRate: 30,
            pixelFormat: "yuv420p",
            rotationDegrees: rotation
        )
    }
}
