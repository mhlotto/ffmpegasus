import XCTest
@testable import FFMpegasusCore

final class FFmpegCommandTests: XCTestCase {
    func testStreamCopyCommandArgumentConstruction() throws {
        let request = EditingRequest(
            inputURL: URL(fileURLWithPath: "/tmp/input.mov"),
            outputURL: URL(fileURLWithPath: "/tmp/output.mov"),
            sourceDuration: 100,
            removeStartSeconds: 10,
            removeEndSeconds: 15,
            mode: .trimBoth,
            method: .streamCopy
        )

        let command = try VideoEditingService().command(ffmpegPath: "/opt/homebrew/bin/ffmpeg", request: request)

        XCTAssertEqual(command.executablePath, "/opt/homebrew/bin/ffmpeg")
        XCTAssertEqual(command.arguments, [
            "-y",
            "-nostdin",
            "-ss", "10.000000",
            "-i", "/tmp/input.mov",
            "-t", "75.000000",
            "-map", "0",
            "-c", "copy",
            "-progress", "pipe:1",
            "-nostats",
            "/tmp/output.mov"
        ])
    }

    func testStreamCopyCommandIncludesNostdinAsOwnArgument() throws {
        let request = EditingRequest(
            inputURL: URL(fileURLWithPath: "/tmp/input.mov"),
            outputURL: URL(fileURLWithPath: "/tmp/output.mov"),
            sourceDuration: 100,
            removeStartSeconds: 10,
            removeEndSeconds: 15,
            mode: .trimBoth,
            method: .streamCopy
        )

        let command = try VideoEditingService().command(ffmpegPath: "/opt/homebrew/bin/ffmpeg", request: request)

        XCTAssertTrue(command.arguments.contains("-nostdin"))
        XCTAssertFalse(command.arguments.contains { $0.contains(" -nostdin") || $0.contains("-nostdin ") })
    }

    func testAccurateTrimCommandUsesH264AndAACWhenAudioExists() throws {
        let request = EditingRequest(
            inputURL: URL(fileURLWithPath: "/tmp/input.mov"),
            outputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
            sourceDuration: 30,
            removeStartSeconds: 5,
            removeEndSeconds: 3,
            mode: .trimBoth,
            method: .streamCopy,
            trimExecutionMode: .accurate,
            hasVideoStream: true,
            hasAudioStream: true
        )

        let command = try VideoEditingService().command(ffmpegPath: "/opt/homebrew/bin/ffmpeg", request: request)

        XCTAssertTrue(command.arguments.contains("-nostdin"))
        XCTAssertEqual(command.arguments.commandValue(after: "-ss"), "5.000000")
        XCTAssertEqual(command.arguments.commandValue(after: "-t"), "22.000000")
        XCTAssertEqual(command.arguments.commandValue(after: "-map"), "0:v:0")
        XCTAssertTrue(command.arguments.contains("0:a:0?"))
        XCTAssertEqual(command.arguments.commandValue(after: "-c:v"), "libx264")
        XCTAssertEqual(command.arguments.commandValue(after: "-crf"), "20")
        XCTAssertEqual(command.arguments.commandValue(after: "-preset"), "medium")
        XCTAssertEqual(command.arguments.commandValue(after: "-pix_fmt"), "yuv420p")
        XCTAssertEqual(command.arguments.commandValue(after: "-c:a"), "aac")
        XCTAssertEqual(command.arguments.commandValue(after: "-b:a"), "128k")
        XCTAssertEqual(command.arguments.commandValue(after: "-movflags"), "+faststart")
        XCTAssertFalse(command.arguments.contains("-c"))
        XCTAssertLessThan(command.arguments.firstIndex(of: "-ss")!, command.arguments.firstIndex(of: "-i")!)
    }

    func testAccurateTrimOmitsAudioArgumentsWhenNoAudioExists() throws {
        let request = EditingRequest(
            inputURL: URL(fileURLWithPath: "/tmp/input.mov"),
            outputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
            sourceDuration: 30,
            removeStartSeconds: 5,
            removeEndSeconds: 0,
            mode: .trimStart,
            method: .streamCopy,
            trimExecutionMode: .accurate,
            hasVideoStream: true,
            hasAudioStream: false
        )

        let command = try VideoEditingService().command(ffmpegPath: "/opt/homebrew/bin/ffmpeg", request: request)

        XCTAssertFalse(command.arguments.contains("0:a:0?"))
        XCTAssertFalse(command.arguments.contains("-c:a"))
        XCTAssertFalse(command.arguments.contains("-b:a"))
    }

    func testTrimFilenamesDistinguishFastAndAccurateModes() {
        XCTAssertEqual(OutputFilename.trimmedName(for: URL(fileURLWithPath: "/tmp/input.mov"), mode: .fast), "input-trimmed.mov")
        XCTAssertEqual(OutputFilename.trimmedName(for: URL(fileURLWithPath: "/tmp/input.mkv"), mode: .fast), "input-trimmed.mkv")
        XCTAssertEqual(OutputFilename.trimmedName(for: URL(fileURLWithPath: "/tmp/input.mov"), mode: .accurate), "input-trimmed-accurate.mp4")
        XCTAssertEqual(OutputFilename.trimmedName(for: URL(fileURLWithPath: "/tmp/input.mkv"), mode: .accurate), "input-trimmed-accurate.mp4")
    }

    func testCommandSupportsPathsContainingSpaces() throws {
        let request = EditingRequest(
            inputURL: URL(fileURLWithPath: "/tmp/Input Video.mov"),
            outputURL: URL(fileURLWithPath: "/tmp/Output Video.mov"),
            sourceDuration: 100,
            removeStartSeconds: 10,
            removeEndSeconds: 15,
            mode: .trimBoth,
            method: .streamCopy
        )

        let command = try VideoEditingService().command(ffmpegPath: "/opt/homebrew/bin/ffmpeg", request: request)

        XCTAssertEqual(command.arguments, [
            "-y",
            "-nostdin",
            "-ss", "10.000000",
            "-i", "/tmp/Input Video.mov",
            "-t", "75.000000",
            "-map", "0",
            "-c", "copy",
            "-progress", "pipe:1",
            "-nostats",
            "/tmp/Output Video.mov"
        ])
    }

    func testRemoveAudioCommandArgumentConstruction() {
        let request = RemoveAudioRequest(
            inputURL: URL(fileURLWithPath: "/tmp/input.mov"),
            outputURL: URL(fileURLWithPath: "/tmp/output.mov"),
            sourceDuration: 10,
            hasVideoStream: true,
            hasAudioStream: true
        )

        let command = VideoEditingService().removeAudioCommand(ffmpegPath: "/opt/homebrew/bin/ffmpeg", request: request)

        XCTAssertEqual(command.arguments, [
            "-y",
            "-nostdin",
            "-i", "/tmp/input.mov",
            "-map", "0:v",
            "-c:v", "copy",
            "-an",
            "-progress", "pipe:1",
            "-nostats",
            "/tmp/output.mov"
        ])
        XCTAssertTrue(command.arguments.contains("-nostdin"))
        XCTAssertTrue(command.arguments.contains("-an"))
        XCTAssertEqual(command.arguments.commandValue(after: "-c:v"), "copy")
        XCTAssertFalse(command.arguments.contains("-c:a"))
        XCTAssertFalse(command.arguments.contains("-codec:a"))
    }

    func testRemoveAudioCommandSupportsPathsContainingSpaces() {
        let request = RemoveAudioRequest(
            inputURL: URL(fileURLWithPath: "/tmp/Input Video.mov"),
            outputURL: URL(fileURLWithPath: "/tmp/Output Video.mov"),
            sourceDuration: 10,
            hasVideoStream: true,
            hasAudioStream: true
        )

        let command = VideoEditingService().removeAudioCommand(ffmpegPath: "/opt/homebrew/bin/ffmpeg", request: request)

        XCTAssertEqual(command.arguments.commandValue(after: "-i"), "/tmp/Input Video.mov")
        XCTAssertEqual(command.arguments.last, "/tmp/Output Video.mov")
    }

    func testMutedFilenameUsesMutedSuffixAndPreservesExtension() {
        XCTAssertEqual(OutputFilename.mutedName(for: URL(fileURLWithPath: "/tmp/video.mov")), "video-muted.mov")
        XCTAssertEqual(OutputFilename.mutedName(for: URL(fileURLWithPath: "/tmp/clip.mp4")), "clip-muted.mp4")
    }
}

private extension Array where Element == String {
    func commandValue(after option: String) -> String? {
        guard let index = firstIndex(of: option), indices.contains(index + 1) else { return nil }
        return self[index + 1]
    }
}
