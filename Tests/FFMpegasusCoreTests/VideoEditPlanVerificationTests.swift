import XCTest
@testable import FFMpegasusCore

final class VideoEditPlanVerificationTests: XCTestCase {
    func testValidCombinedOutputSucceeds() throws {
        XCTAssertNoThrow(try VideoEditPlanOutputValidator.verify(
            metadata: metadata(duration: 15, width: 406, height: 720, audioCodec: nil),
            plan: plan(trim: trim(), transform: transform(rotation: .clockwise90), resize: ResizeConfiguration(resolution: .p720, customHeight: nil), audioMode: .remove)
        ))
    }

    func testWrongDurationFails() {
        XCTAssertThrowsError(try VideoEditPlanOutputValidator.verify(metadata: metadata(duration: 18), plan: plan(trim: trim())))
    }

    func testWrongDimensionsFails() {
        XCTAssertThrowsError(try VideoEditPlanOutputValidator.verify(metadata: metadata(width: 1920, height: 1080), plan: plan(transform: transform(rotation: .clockwise90))))
    }

    func testWrongCodecFailsForReencode() {
        XCTAssertThrowsError(try VideoEditPlanOutputValidator.verify(metadata: metadata(videoCodec: "hevc"), plan: plan(transform: transform(rotation: .clockwise90))))
    }

    func testStreamCopyAllowsOriginalCodec() throws {
        XCTAssertNoThrow(try VideoEditPlanOutputValidator.verify(metadata: metadata(duration: 15, videoCodec: "hevc"), plan: plan(trim: trim())))
    }

    func testUnexpectedAudioFails() {
        XCTAssertThrowsError(try VideoEditPlanOutputValidator.verify(metadata: metadata(audioCodec: "aac"), plan: plan(transform: transform(rotation: .clockwise90), audioMode: .remove)))
    }

    func testMissingExpectedAudioFails() {
        XCTAssertThrowsError(try VideoEditPlanOutputValidator.verify(metadata: metadata(audioCodec: nil), plan: plan(transform: transform(rotation: .clockwise90), audioMode: .keep, hasAudio: true)))
    }

    func testStaleRotationMetadataFails() {
        XCTAssertThrowsError(try VideoEditPlanOutputValidator.verify(metadata: metadata(rotationDegrees: 90), plan: plan(transform: transform(rotation: .clockwise90))))
    }

    func testSpeedAdjustedDurationSucceeds() throws {
        XCTAssertNoThrow(try VideoEditPlanOutputValidator.verify(
            metadata: metadata(duration: 10, audioDuration: 10),
            plan: plan(speed: try VideoSpeed(multiplier: 2.0))
        ))
    }

    func testSpeedAdjustedWrongDurationFails() throws {
        XCTAssertThrowsError(try VideoEditPlanOutputValidator.verify(
            metadata: metadata(duration: 20, audioDuration: 20),
            plan: plan(speed: try VideoSpeed(multiplier: 2.0))
        ))
    }

    func testSpeedAudioVideoDurationMismatchFails() throws {
        XCTAssertThrowsError(try VideoEditPlanOutputValidator.verify(
            metadata: metadata(duration: 10, audioDuration: 9.7),
            plan: plan(speed: try VideoSpeed(multiplier: 2.0))
        ))
    }

    func testMissingVideoFails() {
        XCTAssertThrowsError(try VideoEditPlanOutputValidator.verify(metadata: metadata(videoCodec: nil), plan: plan(transform: transform(rotation: .clockwise90))))
    }

    private func trim() -> TrimConfiguration {
        TrimConfiguration(mode: .trimBoth, removeStartSeconds: 2, removeEndSeconds: 3, executionMode: .fast)
    }

    private func transform(rotation: VideoRotation = .none) -> VideoTransformConfiguration {
        VideoTransformConfiguration(rotation: rotation, flipHorizontal: false, flipVertical: false)
    }

    private func plan(
        trim: TrimConfiguration? = nil,
        transform: VideoTransformConfiguration? = nil,
        resize: ResizeConfiguration? = nil,
        speed: VideoSpeed? = nil,
        audioMode: ExportAudioMode = .keep,
        hasAudio: Bool = true
    ) -> VideoEditPlan {
        VideoEditPlan(
            inputURL: URL(fileURLWithPath: "/tmp/input.mov"),
            outputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
            sourceDuration: 20,
            sourceDimensions: VideoDimensions(width: 1920, height: 1080),
            sourceRotationDegrees: nil,
            hasVideoStream: true,
            hasAudioStream: hasAudio,
            trim: trim,
            transform: transform,
            resize: resize,
            compression: nil,
            speed: speed,
            audioMode: audioMode
        )
    }

    private func metadata(
        duration: TimeInterval = 20,
        width: Int = 1920,
        height: Int = 1080,
        videoCodec: String? = "h264",
        audioCodec: String? = "aac",
        audioDuration: TimeInterval? = nil,
        rotationDegrees: Int? = nil
    ) -> VideoMetadata {
        VideoMetadata(duration: duration, width: width, height: height, videoCodec: videoCodec, audioCodec: audioCodec, audioDuration: audioDuration, frameRate: 30, pixelFormat: "yuv420p", rotationDegrees: rotationDegrees)
    }
}
