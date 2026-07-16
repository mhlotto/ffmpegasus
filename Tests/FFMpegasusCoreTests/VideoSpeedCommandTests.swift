import XCTest
@testable import FFMpegasusCore

final class VideoSpeedCommandTests: XCTestCase {
    func testSpeedCommandKeepsAudio() throws {
        let request = speedRequest(speed: try VideoSpeed(multiplier: 1.5))
        let command = try VideoEditingService().speedCommand(ffmpegPath: "/opt/homebrew/bin/ffmpeg", request: request)

        XCTAssertEqual(command.arguments.commandValue(after: "-i"), "/tmp/input.mp4")
        XCTAssertTrue(command.arguments.contains("-nostdin"))
        XCTAssertTrue(command.arguments.contains("0:v:0"))
        XCTAssertTrue(command.arguments.contains("0:a:0?"))
        XCTAssertEqual(command.arguments.commandValue(after: "-vf"), "setpts=PTS/1.5")
        XCTAssertEqual(command.arguments.commandValue(after: "-af"), "atempo=1.5")
        XCTAssertEqual(command.arguments.commandValue(after: "-c:v"), "libx264")
        XCTAssertEqual(command.arguments.commandValue(after: "-crf"), "20")
        XCTAssertEqual(command.arguments.commandValue(after: "-preset"), "medium")
        XCTAssertEqual(command.arguments.commandValue(after: "-pix_fmt"), "yuv420p")
        XCTAssertEqual(command.arguments.commandValue(after: "-c:a"), "aac")
        XCTAssertEqual(command.arguments.commandValue(after: "-b:a"), "128k")
        XCTAssertEqual(command.arguments.commandValue(after: "-movflags"), "+faststart")
        XCTAssertEqual(command.arguments.commandValue(after: "-metadata:s:v:0"), "rotate=0")
        XCTAssertFalse(command.arguments.contains("-c"))
        XCTAssertFalse(command.arguments.contains("-r"))
        XCTAssertEqual(command.arguments.last, "/tmp/output.mp4")
    }

    func testSpeedCommandRemovesAudio() throws {
        let request = speedRequest(speed: try VideoSpeed(multiplier: 2.0), audioMode: .remove)
        let command = try VideoEditingService().speedCommand(ffmpegPath: "/opt/homebrew/bin/ffmpeg", request: request)

        XCTAssertTrue(command.arguments.contains("-an"))
        XCTAssertFalse(command.arguments.contains("0:a:0?"))
        XCTAssertFalse(command.arguments.contains("-af"))
        XCTAssertFalse(command.arguments.contains("-c:a"))
        XCTAssertFalse(command.arguments.contains("-b:a"))
    }

    func testSpeedCommandTreatsNoAudioSourceAsRemoveAudio() throws {
        let request = speedRequest(speed: try VideoSpeed(multiplier: 0.5), audioMode: .keep, hasAudio: false)
        let command = try VideoEditingService().speedCommand(ffmpegPath: "/opt/homebrew/bin/ffmpeg", request: request)

        XCTAssertTrue(command.arguments.contains("-an"))
        XCTAssertFalse(command.arguments.contains("0:a:0?"))
        XCTAssertFalse(command.arguments.contains("-af"))
    }

    func testSpeedCommandSupportsPathsContainingSpaces() throws {
        let request = VideoSpeedRequest(
            inputURL: URL(fileURLWithPath: "/tmp/Input Video.mov"),
            outputURL: URL(fileURLWithPath: "/tmp/Output Video.mp4"),
            sourceDuration: 30,
            sourceDimensions: VideoDimensions(width: 1920, height: 1080),
            sourceRotationDegrees: nil,
            hasVideoStream: true,
            hasAudioStream: true,
            speed: try VideoSpeed(multiplier: 1.25),
            audioMode: .keep
        )
        let command = try VideoEditingService().speedCommand(ffmpegPath: "/opt/homebrew/bin/ffmpeg", request: request)

        XCTAssertEqual(command.arguments.commandValue(after: "-i"), "/tmp/Input Video.mov")
        XCTAssertEqual(command.arguments.last, "/tmp/Output Video.mp4")
        XCTAssertFalse(command.arguments.contains { $0.contains("\\ ") })
    }

    func testSpeedCommandRejectsInputOutputEquality() async throws {
        let process = FakeEditingProcessExecutor()
        let fileSystem = FakeEditingFileSystem()
        fileSystem.directories = ["/tmp", "/opt/homebrew/bin"]
        fileSystem.writableDirectories = ["/tmp"]
        fileSystem.files = ["/opt/homebrew/bin/ffmpeg"]
        fileSystem.executables = ["/opt/homebrew/bin/ffmpeg"]
        let state = await EditingOperationState()
        let service = VideoEditingService(processExecutor: process, fileSystem: fileSystem, encoderChecker: FakeEncoderChecker())
        let request = VideoSpeedRequest(
            inputURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            outputURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            sourceDuration: 30,
            sourceDimensions: VideoDimensions(width: 1920, height: 1080),
            sourceRotationDegrees: nil,
            hasVideoStream: true,
            hasAudioStream: true,
            speed: try VideoSpeed(multiplier: 2.0),
            audioMode: .keep
        )

        await service.runSpeedChange(ffmpegPath: "/opt/homebrew/bin/ffmpeg", ffprobePath: "/opt/homebrew/bin/ffprobe", request: request, state: state)

        guard case .failed(let summary) = await state.phase else {
            return XCTFail("Expected failed state")
        }
        XCTAssertTrue(summary.contains("different from the input"))
    }

    private func speedRequest(speed: VideoSpeed, audioMode: SpeedAudioMode = .keep, hasAudio: Bool = true) -> VideoSpeedRequest {
        VideoSpeedRequest(
            inputURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            outputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
            sourceDuration: 30,
            sourceDimensions: VideoDimensions(width: 1920, height: 1080),
            sourceRotationDegrees: nil,
            hasVideoStream: true,
            hasAudioStream: hasAudio,
            speed: speed,
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
