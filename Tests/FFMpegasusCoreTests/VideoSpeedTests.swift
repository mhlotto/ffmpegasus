import XCTest
@testable import FFMpegasusCore

final class VideoSpeedTests: XCTestCase {
    func testSpeedValidationAcceptsSupportedValues() {
        for value in [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 4.0] {
            XCTAssertNoThrow(try VideoSpeed(multiplier: value))
        }
        XCTAssertTrue((try? VideoSpeed(multiplier: 1.0))?.isNoChange == true)
    }

    func testSpeedValidationRejectsInvalidValues() {
        XCTAssertThrowsError(try VideoSpeed(multiplier: 0.24))
        XCTAssertThrowsError(try VideoSpeed(multiplier: 4.01))
        XCTAssertThrowsError(try VideoSpeed(multiplier: 0))
        XCTAssertThrowsError(try VideoSpeed(multiplier: -1))
        XCTAssertThrowsError(try VideoSpeed(multiplier: .nan))
        XCTAssertThrowsError(try VideoSpeed(multiplier: .infinity))
    }

    func testExpectedDurationCalculations() throws {
        XCTAssertEqual(try VideoSpeed(multiplier: 0.5).expectedDuration(sourceDuration: 30), 60)
        XCTAssertEqual(try VideoSpeed(multiplier: 0.75).expectedDuration(sourceDuration: 30), 40)
        XCTAssertEqual(try VideoSpeed(multiplier: 1.5).expectedDuration(sourceDuration: 30), 20)
        XCTAssertEqual(try VideoSpeed(multiplier: 2.0).expectedDuration(sourceDuration: 30), 15)
        XCTAssertEqual(try VideoSpeed(multiplier: 1.25).expectedDuration(sourceDuration: 12.5), 10)
        XCTAssertThrowsError(try VideoSpeed(multiplier: 2.0).expectedDuration(sourceDuration: 0))
        XCTAssertThrowsError(try VideoSpeed(multiplier: 2.0).expectedDuration(sourceDuration: .infinity))
    }

    func testVideoFilterConstruction() throws {
        XCTAssertEqual(try VideoSpeed(multiplier: 0.5).videoFilter(), "setpts=PTS/0.5")
        XCTAssertEqual(try VideoSpeed(multiplier: 0.75).videoFilter(), "setpts=PTS/0.75")
        XCTAssertEqual(try VideoSpeed(multiplier: 1.5).videoFilter(), "setpts=PTS/1.5")
        XCTAssertEqual(try VideoSpeed(multiplier: 2.0).videoFilter(), "setpts=PTS/2.0")
        XCTAssertFalse(try VideoSpeed(multiplier: 1.25).videoFilter().contains("\""))
        XCTAssertFalse(try VideoSpeed(multiplier: 1.25).videoFilter().contains("'"))
        XCTAssertFalse(try VideoSpeed(multiplier: 1.25).videoFilter().contains(","))
    }

    func testAudioTempoConstruction() throws {
        XCTAssertEqual(try VideoSpeed(multiplier: 0.5).audioTempoFilter(), "atempo=0.5")
        XCTAssertEqual(try VideoSpeed(multiplier: 0.75).audioTempoFilter(), "atempo=0.75")
        XCTAssertEqual(try VideoSpeed(multiplier: 1.25).audioTempoFilter(), "atempo=1.25")
        XCTAssertEqual(try VideoSpeed(multiplier: 1.5).audioTempoFilter(), "atempo=1.5")
        XCTAssertEqual(try VideoSpeed(multiplier: 2.0).audioTempoFilter(), "atempo=2.0")
        XCTAssertEqual(try VideoSpeed(multiplier: 0.25).audioTempoFilter(), "atempo=0.5,atempo=0.5")
        XCTAssertEqual(try VideoSpeed(multiplier: 4.0).audioTempoFilter(), "atempo=2.0,atempo=2.0")
        XCTAssertEqual(try VideoSpeed(multiplier: 0.3).audioTempoFilter(), "atempo=0.5,atempo=0.6")
        XCTAssertEqual(try VideoSpeed(multiplier: 3.5).audioTempoFilter(), "atempo=2.0,atempo=1.75")
    }

    func testAudioTempoFactorsAreInSupportedRangeAndMatchRequestedSpeed() throws {
        for value in [0.25, 0.3, 0.75, 1.25, 2.0, 3.5, 4.0] {
            let factors = try VideoSpeed(multiplier: value).audioTempoFactors()
            XCTAssertTrue(factors.allSatisfy { (0.5...2.0).contains($0) })
            XCTAssertEqual(factors.reduce(1.0, *), value, accuracy: 0.000_001)
        }
    }

    func testFilenameGeneration() throws {
        XCTAssertEqual(OutputFilename.speedName(for: URL(fileURLWithPath: "/tmp/input.mp4"), speed: try VideoSpeed(multiplier: 0.5)), "input-speed-0_5x.mp4")
        XCTAssertEqual(OutputFilename.speedName(for: URL(fileURLWithPath: "/tmp/input.mov"), speed: try VideoSpeed(multiplier: 0.75)), "input-speed-0_75x.mp4")
        XCTAssertEqual(OutputFilename.speedName(for: URL(fileURLWithPath: "/tmp/input.mkv"), speed: try VideoSpeed(multiplier: 1.5)), "input-speed-1_5x.mp4")
        XCTAssertEqual(OutputFilename.speedName(for: URL(fileURLWithPath: "/tmp/input.mp4"), speed: try VideoSpeed(multiplier: 2.0)), "input-speed-2x.mp4")
    }

    func testRequestRejectsNoChangeForExport() throws {
        let request = speedRequest(speed: try VideoSpeed(multiplier: 1.0))
        XCTAssertThrowsError(try request.validateForExport()) { error in
            XCTAssertEqual(error as? VideoSpeedValidationError, .noSpeedChange)
        }
    }

    func testOutputDimensionsNormalizeRotationAndStayEven() throws {
        let request = speedRequest(
            sourceDimensions: VideoDimensions(width: 1081, height: 1921),
            rotation: 90,
            speed: try VideoSpeed(multiplier: 2.0)
        )
        XCTAssertEqual(try request.outputDimensions(), VideoDimensions(width: 1920, height: 1080))
    }

    private func speedRequest(
        sourceDimensions: VideoDimensions = VideoDimensions(width: 1920, height: 1080),
        rotation: Int? = nil,
        speed: VideoSpeed,
        audioMode: SpeedAudioMode = .keep,
        hasAudio: Bool = true
    ) -> VideoSpeedRequest {
        VideoSpeedRequest(
            inputURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            outputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
            sourceDuration: 30,
            sourceDimensions: sourceDimensions,
            sourceRotationDegrees: rotation,
            hasVideoStream: true,
            hasAudioStream: hasAudio,
            speed: speed,
            audioMode: audioMode
        )
    }
}
