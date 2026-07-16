import XCTest
@testable import FFMpegasusCore

final class VideoEditPlanTests: XCTestCase {
    func testStrategySelection() throws {
        XCTAssertEqual(try plan(trim: trim(.fast)).executionStrategy(), .streamCopy)
        XCTAssertEqual(try plan(trim: trim(.fast), audioMode: .remove).executionStrategy(), .streamCopy)
        XCTAssertEqual(try plan(trim: trim(.accurate)).executionStrategy(), .reencode)
        XCTAssertEqual(try plan(transform: transform(rotation: .clockwise90)).executionStrategy(), .reencode)
        XCTAssertEqual(try plan(transform: transform(flipHorizontal: true)).executionStrategy(), .reencode)
        XCTAssertEqual(try plan(resize: ResizeConfiguration(resolution: .p720, customHeight: nil)).executionStrategy(), .reencode)
        XCTAssertEqual(try plan(compression: compression()).executionStrategy(), .reencode)
        XCTAssertEqual(try plan(trim: trim(.fast), transform: transform(rotation: .clockwise90)).executionStrategy(), .reencode)
        XCTAssertEqual(try plan(trim: trim(.fast), compression: compression()).executionStrategy(), .reencode)
    }

    func testFilterConstructionOrder() throws {
        XCTAssertEqual(try plan(transform: transform(rotation: .clockwise90)).filterChain(), "transpose=clock")
        XCTAssertEqual(try plan(transform: transform(flipHorizontal: true)).filterChain(), "hflip")
        XCTAssertEqual(try plan(resize: ResizeConfiguration(resolution: .p720, customHeight: nil)).filterChain(), "scale=-2:min(720\\,ih)")
        XCTAssertEqual(try plan(transform: transform(rotation: .clockwise90, flipHorizontal: true)).filterChain(), "transpose=clock,hflip")
        XCTAssertEqual(try plan(transform: transform(rotation: .clockwise90), resize: ResizeConfiguration(resolution: .p720, customHeight: nil)).filterChain(), "transpose=clock,scale=-2:min(720\\,ih)")
        XCTAssertEqual(
            try plan(transform: transform(rotation: .counterclockwise90, flipHorizontal: true, flipVertical: true), resize: ResizeConfiguration(resolution: .p720, customHeight: nil)).filterChain(),
            "transpose=cclock,hflip,vflip,scale=-2:min(720\\,ih)"
        )
    }

    func testCombinedCommandTrimPlusRemoveAudioUsesStreamCopy() throws {
        let command = try VideoEditingService().editPlanCommand(
            ffmpegPath: "/opt/homebrew/bin/ffmpeg",
            plan: plan(trim: trim(.fast), audioMode: .remove)
        )

        XCTAssertTrue(command.arguments.contains("-nostdin"))
        XCTAssertEqual(command.arguments.commandValue(after: "-ss"), "2.000000")
        XCTAssertEqual(command.arguments.commandValue(after: "-t"), "15.000000")
        XCTAssertEqual(command.arguments.commandValue(after: "-c:v"), "copy")
        XCTAssertTrue(command.arguments.contains("-an"))
        XCTAssertFalse(command.arguments.contains("libx264"))
    }

    func testCombinedCommandTrimPlusResizeReencodes() throws {
        let command = try VideoEditingService().editPlanCommand(
            ffmpegPath: "/opt/homebrew/bin/ffmpeg",
            plan: plan(trim: trim(.fast), resize: ResizeConfiguration(resolution: .p720, customHeight: nil))
        )

        XCTAssertEqual(command.arguments.commandValue(after: "-vf"), "scale=-2:min(720\\,ih)")
        XCTAssertEqual(command.arguments.commandValue(after: "-c:v"), "libx264")
        XCTAssertEqual(command.arguments.commandValue(after: "-crf"), "20")
        XCTAssertFalse(command.arguments.contains("-c"))
        XCTAssertFalse(command.arguments.contains("copy"))
    }

    func testCombinedCommandRotatePlusCompression() throws {
        let command = try VideoEditingService().editPlanCommand(
            ffmpegPath: "/opt/homebrew/bin/ffmpeg",
            plan: plan(transform: transform(rotation: .clockwise90), compression: compression())
        )

        XCTAssertEqual(command.arguments.commandValue(after: "-vf"), "transpose=clock")
        XCTAssertEqual(command.arguments.commandValue(after: "-crf"), "24")
        XCTAssertEqual(command.arguments.commandValue(after: "-preset"), "medium")
        XCTAssertEqual(command.arguments.commandValue(after: "-pix_fmt"), "yuv420p")
        XCTAssertEqual(command.arguments.commandValue(after: "-movflags"), "+faststart")
    }

    func testCombinedCommandTrimRotateResizeRemoveAudio() throws {
        let command = try VideoEditingService().editPlanCommand(
            ffmpegPath: "/opt/homebrew/bin/ffmpeg",
            plan: plan(
                trim: trim(.accurate),
                transform: transform(rotation: .clockwise90, flipHorizontal: true),
                resize: ResizeConfiguration(resolution: .p720, customHeight: nil),
                audioMode: .remove
            )
        )

        XCTAssertEqual(command.arguments.commandValue(after: "-vf"), "transpose=clock,hflip,scale=-2:min(720\\,ih)")
        XCTAssertTrue(command.arguments.contains("-an"))
        XCTAssertFalse(command.arguments.contains("0:a:0?"))
        XCTAssertEqual(command.arguments.commandValue(after: "-metadata:s:v:0"), "rotate=0")
    }

    func testCombinedCommandWithoutAudioSourceUsesAn() throws {
        let command = try VideoEditingService().editPlanCommand(
            ffmpegPath: "/opt/homebrew/bin/ffmpeg",
            plan: plan(transform: transform(rotation: .clockwise90), hasAudio: false)
        )

        XCTAssertTrue(command.arguments.contains("-an"))
        XCTAssertFalse(command.arguments.contains("0:a:0?"))
        XCTAssertFalse(command.arguments.contains("-c:a"))
    }

    func testCombinedCommandSupportsPathsContainingSpaces() throws {
        let command = try VideoEditingService().editPlanCommand(
            ffmpegPath: "/opt/homebrew/bin/ffmpeg",
            plan: plan(input: "/tmp/Input Video.mov", output: "/tmp/Output Video.mp4", transform: transform(rotation: .clockwise90))
        )

        XCTAssertEqual(command.arguments.commandValue(after: "-i"), "/tmp/Input Video.mov")
        XCTAssertEqual(command.arguments.last, "/tmp/Output Video.mp4")
    }

    func testPlannedDimensions() throws {
        XCTAssertEqual(try plan(width: 1920, height: 1080, transform: transform(rotation: .clockwise90)).outputDimensions(), VideoDimensions(width: 1080, height: 1920))
        XCTAssertEqual(
            try plan(width: 1920, height: 1080, transform: transform(rotation: .clockwise90), resize: ResizeConfiguration(resolution: .p720, customHeight: nil)).outputDimensions(),
            VideoDimensions(width: 406, height: 720)
        )
        XCTAssertEqual(try plan(width: 1280, height: 720, resize: ResizeConfiguration(resolution: .p1080, customHeight: nil)).outputDimensions(), VideoDimensions(width: 1280, height: 720))
        XCTAssertEqual(try plan(width: 853, height: 481, transform: transform(flipVertical: true)).outputDimensions(), VideoDimensions(width: 852, height: 480))
    }

    func testPlannedDuration() throws {
        XCTAssertEqual(try plan(transform: transform(flipHorizontal: true)).trimPlan().outputDuration, 20)
        XCTAssertEqual(try plan(trim: trim(.fast, start: 2.5, end: 0)).trimPlan().outputDuration, 17.5)
        XCTAssertEqual(try plan(trim: trim(.fast, start: 0, end: 3.25)).trimPlan().outputDuration, 16.75)
        XCTAssertEqual(try plan(trim: trim(.fast, start: 2.5, end: 3.25)).trimPlan().outputDuration, 14.25)
        XCTAssertThrowsError(try plan(trim: trim(.fast, start: 20, end: 0)).trimPlan())
    }

    func testOutputFilename() {
        XCTAssertEqual(OutputFilename.editedName(for: URL(fileURLWithPath: "/tmp/input.mp4")), "input-edited.mp4")
        XCTAssertEqual(OutputFilename.editedName(for: URL(fileURLWithPath: "/tmp/input.mov")), "input-edited.mp4")
        XCTAssertEqual(OutputFilename.editedName(for: URL(fileURLWithPath: "/tmp/input.mkv")), "input-edited.mp4")
    }

    private func trim(_ executionMode: TrimExecutionMode, start: TimeInterval = 2, end: TimeInterval = 3) -> TrimConfiguration {
        TrimConfiguration(mode: .trimBoth, removeStartSeconds: start, removeEndSeconds: end, executionMode: executionMode)
    }

    private func transform(rotation: VideoRotation = .none, flipHorizontal: Bool = false, flipVertical: Bool = false) -> VideoTransformConfiguration {
        VideoTransformConfiguration(rotation: rotation, flipHorizontal: flipHorizontal, flipVertical: flipVertical)
    }

    private func compression() -> CompressionConfiguration {
        CompressionConfiguration(quality: .balanced, customCRF: 24, encoderPreset: .medium)
    }

    private func plan(
        input: String = "/tmp/input.mov",
        output: String = "/tmp/output.mp4",
        width: Int = 1920,
        height: Int = 1080,
        trim: TrimConfiguration? = nil,
        transform: VideoTransformConfiguration? = nil,
        resize: ResizeConfiguration? = nil,
        compression: CompressionConfiguration? = nil,
        audioMode: ExportAudioMode = .keep,
        hasAudio: Bool = true
    ) -> VideoEditPlan {
        VideoEditPlan(
            inputURL: URL(fileURLWithPath: input),
            outputURL: URL(fileURLWithPath: output),
            sourceDuration: 20,
            sourceDimensions: VideoDimensions(width: width, height: height),
            sourceRotationDegrees: nil,
            hasVideoStream: true,
            hasAudioStream: hasAudio,
            trim: trim,
            transform: transform,
            resize: resize,
            compression: compression,
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
