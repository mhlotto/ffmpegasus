import XCTest
@testable import FFMpegasusCore

final class FFmpegIntegrationTests: XCTestCase {
    func testOptionalFFmpegSyntheticStreamCopyTrim() async throws {
        let ffmpegPath = "/opt/homebrew/bin/ffmpeg"
        guard FileManager.default.isExecutableFile(atPath: ffmpegPath) else {
            throw XCTSkip("FFmpeg is not available at \(ffmpegPath)")
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let input = directory.appendingPathComponent("input.mp4")
        let output = directory.appendingPathComponent("output.mp4")

        let generate = try await ProcessRunner().run(
            executablePath: ffmpegPath,
            arguments: [
                "-y", "-nostdin",
                "-f", "lavfi",
                "-i", "testsrc=size=160x120:rate=10:duration=2",
                "-pix_fmt", "yuv420p",
                input.path
            ]
        )
        XCTAssertEqual(generate.exitCode, 0, generate.stderrText)

        let request = EditingRequest(
            inputURL: input,
            outputURL: output,
            sourceDuration: 2,
            removeStartSeconds: 0.5,
            removeEndSeconds: 0,
            mode: .trimStart,
            method: .streamCopy
        )
        let command = try VideoEditingService().command(ffmpegPath: ffmpegPath, request: request)
        let trim = try await ProcessRunner().run(executablePath: command.executablePath, arguments: command.arguments)

        XCTAssertEqual(trim.exitCode, 0, trim.stderrText)
        let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
        let size = try XCTUnwrap(attributes[.size] as? NSNumber)
        XCTAssertGreaterThan(size.uint64Value, 0)
    }
}
