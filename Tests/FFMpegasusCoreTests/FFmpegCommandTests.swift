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
}
