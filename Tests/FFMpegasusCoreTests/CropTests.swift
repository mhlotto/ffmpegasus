import XCTest
@testable import FFMpegasusCore

final class CropTests: XCTestCase {
    func testAspectRatioCalculation() throws {
        XCTAssertEqual(try aspect(.square, source: landscape).resolvedRectangle(sourceDimensions: landscape), rectangle(1080, 1080, 420, 0, source: landscape))
        XCTAssertEqual(try aspect(.square, source: portrait).resolvedRectangle(sourceDimensions: portrait), rectangle(1080, 1080, 0, 420, source: portrait))
        XCTAssertEqual(try aspect(.sixteenNine, source: portrait).resolvedRectangle(sourceDimensions: portrait), rectangle(1080, 606, 0, 657, source: portrait))
        XCTAssertEqual(try aspect(.nineSixteen, source: landscape).resolvedRectangle(sourceDimensions: landscape), rectangle(606, 1080, 657, 0, source: landscape))
        XCTAssertEqual(try aspect(.fourThree, source: landscape).resolvedRectangle(sourceDimensions: landscape), rectangle(1440, 1080, 240, 0, source: landscape))
        XCTAssertEqual(try aspect(.threeFour, source: landscape).resolvedRectangle(sourceDimensions: landscape), rectangle(810, 1080, 555, 0, source: landscape))
        XCTAssertEqual(try aspect(.twentyOneNine, source: landscape).resolvedRectangle(sourceDimensions: landscape), rectangle(1920, 822, 0, 129, source: landscape))

        let custom = try CropAspectRatio(width: 2.39, height: 1)
        let configuration = CropConfiguration(
            mode: .aspectRatio,
            aspectRatioPreset: .custom,
            customAspectRatio: custom,
            position: .center,
            customX: nil,
            customY: nil,
            customWidth: nil,
            customHeight: nil
        )
        XCTAssertEqual(try configuration.resolvedRectangle(sourceDimensions: landscape), rectangle(1920, 802, 0, 139, source: landscape))
    }

    func testPositionCalculation() throws {
        XCTAssertEqual(try aspect(.square, position: .center).resolvedRectangle(sourceDimensions: landscape).x, 420)
        XCTAssertEqual(try aspect(.square, position: .top).resolvedRectangle(sourceDimensions: landscape), rectangle(1080, 1080, 420, 0, source: landscape))
        XCTAssertEqual(try aspect(.square, position: .bottom).resolvedRectangle(sourceDimensions: landscape), rectangle(1080, 1080, 420, 0, source: landscape))
        XCTAssertEqual(try aspect(.square, position: .left).resolvedRectangle(sourceDimensions: landscape), rectangle(1080, 1080, 0, 0, source: landscape))
        XCTAssertEqual(try aspect(.square, position: .right).resolvedRectangle(sourceDimensions: landscape), rectangle(1080, 1080, 840, 0, source: landscape))
        XCTAssertEqual(try aspect(.square, position: .topLeft).resolvedRectangle(sourceDimensions: landscape), rectangle(1080, 1080, 0, 0, source: landscape))
        XCTAssertEqual(try aspect(.square, position: .topRight).resolvedRectangle(sourceDimensions: landscape), rectangle(1080, 1080, 840, 0, source: landscape))
        XCTAssertEqual(try aspect(.square, position: .bottomLeft).resolvedRectangle(sourceDimensions: landscape), rectangle(1080, 1080, 0, 0, source: landscape))
        XCTAssertEqual(try aspect(.square, position: .bottomRight).resolvedRectangle(sourceDimensions: landscape), rectangle(1080, 1080, 840, 0, source: landscape))

        let custom = CropConfiguration(
            mode: .customRectangle,
            aspectRatioPreset: .square,
            customAspectRatio: nil,
            position: .custom,
            customX: 10,
            customY: 20,
            customWidth: 640,
            customHeight: 360
        )
        XCTAssertEqual(try custom.resolvedRectangle(sourceDimensions: landscape), rectangle(640, 360, 10, 20, source: landscape))
    }

    func testValidationRejectsInvalidRectangles() throws {
        XCTAssertThrowsError(try CropRectangle(width: 0, height: 360, x: 0, y: 0, sourceDimensions: landscape))
        XCTAssertThrowsError(try CropRectangle(width: 641, height: 360, x: 0, y: 0, sourceDimensions: landscape))
        XCTAssertThrowsError(try CropRectangle(width: 640, height: 360, x: -1, y: 0, sourceDimensions: landscape))
        XCTAssertThrowsError(try CropRectangle(width: 2000, height: 360, x: 0, y: 0, sourceDimensions: landscape))
        XCTAssertThrowsError(try CropRectangle(width: 640, height: 360, x: 1500, y: 0, sourceDimensions: landscape))
        XCTAssertThrowsError(try CropAspectRatio(width: 0, height: 1))
        XCTAssertThrowsError(try CropAspectRatio(width: .infinity, height: 1))
    }

    func testRotationAwareDisplayDimensions() throws {
        XCTAssertEqual(
            try CropGeometry.displayDimensions(sourceDimensions: VideoDimensions(width: 1920, height: 1080), rotationDegrees: 90),
            VideoDimensions(width: 1080, height: 1920)
        )
        XCTAssertEqual(try request(width: 1920, height: 1080, rotationDegrees: 90).displayDimensions(), VideoDimensions(width: 1080, height: 1920))
        XCTAssertEqual(try request(width: 1920, height: 1080, rotationDegrees: 90).resolvedRectangle(), rectangle(1080, 1080, 0, 420, source: portrait))
    }

    func testStandaloneCropCommand() throws {
        let command = try VideoEditingService().cropCommand(
            ffmpegPath: "/opt/homebrew/bin/ffmpeg",
            request: request(input: "/tmp/input video.mov", output: "/tmp/output video.mp4")
        )

        XCTAssertTrue(command.arguments.contains("-nostdin"))
        XCTAssertEqual(command.arguments.commandValue(after: "-i"), "/tmp/input video.mov")
        XCTAssertEqual(command.arguments.commandValue(after: "-map"), "0:v:0")
        XCTAssertTrue(command.arguments.contains("0:a:0?"))
        XCTAssertEqual(command.arguments.commandValue(after: "-vf"), "crop=1080:1080:420:0")
        XCTAssertFalse(command.arguments.contains("\"crop=1080:1080:420:0\""))
        XCTAssertEqual(command.arguments.commandValue(after: "-c:v"), "libx264")
        XCTAssertEqual(command.arguments.commandValue(after: "-crf"), "20")
        XCTAssertEqual(command.arguments.commandValue(after: "-preset"), "medium")
        XCTAssertEqual(command.arguments.commandValue(after: "-pix_fmt"), "yuv420p")
        XCTAssertEqual(command.arguments.commandValue(after: "-c:a"), "aac")
        XCTAssertEqual(command.arguments.commandValue(after: "-b:a"), "128k")
        XCTAssertEqual(command.arguments.commandValue(after: "-metadata:s:v:0"), "rotate=0")
        XCTAssertEqual(command.arguments.commandValue(after: "-movflags"), "+faststart")
        XCTAssertEqual(command.arguments.commandValue(after: "-progress"), "pipe:1")
        XCTAssertEqual(command.arguments.last, "/tmp/output video.mp4")
        XCTAssertFalse(command.arguments.contains("copy"))
    }

    func testStandaloneCropCommandUsesAnWithoutSourceAudio() throws {
        let command = try VideoEditingService().cropCommand(
            ffmpegPath: "/opt/homebrew/bin/ffmpeg",
            request: request(hasAudio: false)
        )

        XCTAssertTrue(command.arguments.contains("-an"))
        XCTAssertFalse(command.arguments.contains("0:a:0?"))
        XCTAssertFalse(command.arguments.contains("-c:a"))
    }

    func testCombinedExportUsesCropFilterOrder() throws {
        let crop = CropConfiguration(
            mode: .aspectRatio,
            aspectRatioPreset: .square,
            customAspectRatio: nil,
            position: .center,
            customX: nil,
            customY: nil,
            customWidth: nil,
            customHeight: nil
        )
        let plan = VideoEditPlan(
            inputURL: URL(fileURLWithPath: "/tmp/input.mov"),
            outputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
            sourceDuration: 20,
            sourceDimensions: landscape,
            sourceRotationDegrees: nil,
            hasVideoStream: true,
            hasAudioStream: true,
            trim: nil,
            transform: VideoTransformConfiguration(rotation: .clockwise90, flipHorizontal: true, flipVertical: true),
            crop: crop,
            resize: ResizeConfiguration(resolution: .p720, customHeight: nil),
            compression: nil,
            speed: try VideoSpeed(multiplier: 1.5),
            audioMode: .keep
        )

        XCTAssertEqual(try plan.executionStrategy(), .reencode)
        XCTAssertEqual(try plan.filterChain(), "transpose=clock,hflip,vflip,crop=1080:1080:0:420,scale=-2:min(720\\,ih),setpts=PTS/1.5")
        XCTAssertEqual(try plan.outputDimensions(), VideoDimensions(width: 720, height: 720))

        let command = try VideoEditingService().editPlanCommand(ffmpegPath: "/opt/homebrew/bin/ffmpeg", plan: plan)
        XCTAssertEqual(command.arguments.commandValue(after: "-vf"), "transpose=clock,hflip,vflip,crop=1080:1080:0:420,scale=-2:min(720\\,ih),setpts=PTS/1.5")
    }

    func testOutputFilename() {
        let rect = rectangle(1080, 1080, 420, 0, source: landscape)
        XCTAssertEqual(OutputFilename.croppedName(for: URL(fileURLWithPath: "/tmp/video.mp4")), "video-cropped.mp4")
        XCTAssertEqual(OutputFilename.croppedName(for: URL(fileURLWithPath: "/tmp/video.mov"), rectangle: rect), "video-crop-1080x1080.mp4")
    }

    func testVerification() throws {
        XCTAssertNoThrow(try CropOutputValidator.verify(metadata: metadata(width: 1080, height: 1080), request: request()))
        XCTAssertThrowsError(try CropOutputValidator.verify(metadata: metadata(width: 1920, height: 1080), request: request()))
        XCTAssertThrowsError(try CropOutputValidator.verify(metadata: metadata(videoCodec: "hevc"), request: request()))
        XCTAssertThrowsError(try CropOutputValidator.verify(metadata: metadata(audioCodec: nil), request: request(hasAudio: true)))
        XCTAssertThrowsError(try CropOutputValidator.verify(metadata: metadata(audioCodec: "aac"), request: request(hasAudio: false)))
        XCTAssertThrowsError(try CropOutputValidator.verify(metadata: metadata(duration: 9.7), request: request()))
        XCTAssertThrowsError(try CropOutputValidator.verify(metadata: metadata(rotationDegrees: 90), request: request()))
    }

    private var landscape: VideoDimensions {
        VideoDimensions(width: 1920, height: 1080)
    }

    private var portrait: VideoDimensions {
        VideoDimensions(width: 1080, height: 1920)
    }

    private func aspect(_ preset: CropAspectRatioPreset, source: VideoDimensions? = nil, position: CropPositionPreset = .center) -> CropConfiguration {
        CropConfiguration(
            mode: .aspectRatio,
            aspectRatioPreset: preset,
            customAspectRatio: nil,
            position: position,
            customX: nil,
            customY: nil,
            customWidth: nil,
            customHeight: nil
        )
    }

    private func rectangle(_ width: Int, _ height: Int, _ x: Int, _ y: Int, source: VideoDimensions) -> CropRectangle {
        try! CropRectangle(width: width, height: height, x: x, y: y, sourceDimensions: source)
    }

    private func request(
        input: String = "/tmp/input.mov",
        output: String = "/tmp/output.mp4",
        width: Int = 1920,
        height: Int = 1080,
        rotationDegrees: Int? = nil,
        hasAudio: Bool = true
    ) -> CropRequest {
        CropRequest(
            inputURL: URL(fileURLWithPath: input),
            outputURL: URL(fileURLWithPath: output),
            sourceDuration: 10,
            sourceDimensions: VideoDimensions(width: width, height: height),
            sourceRotationDegrees: rotationDegrees,
            hasVideoStream: true,
            hasAudioStream: hasAudio,
            configuration: aspect(.square)
        )
    }

    private func metadata(
        duration: TimeInterval = 10,
        width: Int = 1080,
        height: Int = 1080,
        videoCodec: String? = "h264",
        audioCodec: String? = "aac",
        rotationDegrees: Int? = nil
    ) -> VideoMetadata {
        VideoMetadata(duration: duration, width: width, height: height, videoCodec: videoCodec, audioCodec: audioCodec, frameRate: 30, pixelFormat: "yuv420p", rotationDegrees: rotationDegrees)
    }
}

private extension Array where Element == String {
    func commandValue(after option: String) -> String? {
        guard let index = firstIndex(of: option), indices.contains(index + 1) else { return nil }
        return self[index + 1]
    }
}
