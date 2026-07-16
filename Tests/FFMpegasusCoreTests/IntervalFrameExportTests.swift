import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import FFMpegasusCore

final class IntervalFrameExportTests: XCTestCase {
    func testIntervalValidation() throws {
        for value in [0.1, 0.25, 0.5, 1, 5, 3600] {
            XCTAssertEqual(try FrameInterval(seconds: value).seconds, value)
        }
        for value in [0, -1, 0.099, 3600.1, Double.nan, Double.infinity] {
            XCTAssertThrowsError(try FrameInterval(seconds: value))
        }
    }

    func testRangeValidationAndEstimatedCount() throws {
        XCTAssertEqual(try FrameExportRange.entireVideo(duration: 10).estimatedImageCount(interval: try FrameInterval(seconds: 5)), 3)
        XCTAssertEqual(try FrameExportRange(startSeconds: 0, endSeconds: 9, sourceDuration: 10).estimatedImageCount(interval: try FrameInterval(seconds: 5)), 2)
        XCTAssertEqual(try FrameExportRange(startSeconds: 2, endSeconds: 12, sourceDuration: 12).estimatedImageCount(interval: try FrameInterval(seconds: 5)), 3)
        XCTAssertEqual(try FrameExportRange(startSeconds: 0, endSeconds: 1.5, sourceDuration: 2).estimatedImageCount(interval: try FrameInterval(seconds: 0.5)), 4)
        XCTAssertEqual(try FrameExportRange(startSeconds: 0, endSeconds: 0.2, sourceDuration: 1).estimatedImageCount(interval: try FrameInterval(seconds: 0.5)), 1)

        XCTAssertThrowsError(try FrameExportRange(startSeconds: 1, endSeconds: 1, sourceDuration: 10))
        XCTAssertThrowsError(try FrameExportRange(startSeconds: 2, endSeconds: 1, sourceDuration: 10))
        XCTAssertThrowsError(try FrameExportRange(startSeconds: -1, endSeconds: 1, sourceDuration: 10))
        XCTAssertThrowsError(try FrameExportRange(startSeconds: 0, endSeconds: 11, sourceDuration: 10))
    }

    func testFilenamePatternAndMatching() throws {
        let request = try intervalRequest(
            inputURL: URL(fileURLWithPath: "/tmp/my.input video.mov"),
            outputDirectoryURL: URL(fileURLWithPath: "/tmp/frames"),
            format: .jpeg
        )

        XCTAssertEqual(OutputFilename.intervalFramePattern(for: request.inputURL, format: .jpeg), "my.input-video-frame-%06d.jpg")
        XCTAssertEqual(request.outputPattern.path, "/tmp/frames/my.input-video-frame-%06d.jpg")
        XCTAssertTrue(request.matchesGeneratedFrameName("my.input-video-frame-000001.jpg"))
        XCTAssertTrue(request.matchesGeneratedFrameName("my.input-video-frame-999999.jpg"))
        XCTAssertFalse(request.matchesGeneratedFrameName("my.input-video-frame-000001.png"))
        XCTAssertFalse(request.matchesGeneratedFrameName("other-frame-000001.jpg"))
        XCTAssertFalse(request.outputPattern.path.contains(" "))
    }

    func testPNGCommandConstruction() throws {
        let command = try VideoEditingService().intervalFrameExportCommand(
            ffmpegPath: "/opt/homebrew/bin/ffmpeg",
            request: try intervalRequest()
        )

        XCTAssertEqual(command.arguments, [
            "-y",
            "-nostdin",
            "-ss", "0.000000",
            "-i", "/tmp/input.mov",
            "-t", "10.000000",
            "-map", "0:v:0",
            "-vf", "setpts=PTS-STARTPTS,fps=1/5:start_time=0",
            "-start_number", "1",
            "-an",
            "-sn",
            "-dn",
            "-progress", "pipe:1",
            "-nostats",
            "/tmp/frames/input-frame-%06d.png"
        ])
        XCTAssertFalse(command.arguments.contains("-q:v"))
        XCTAssertFalse(command.arguments.joined().contains("\""))
    }

    func testJPEGCommandAndCustomRangeConstruction() throws {
        let command = try VideoEditingService().intervalFrameExportCommand(
            ffmpegPath: "/opt/homebrew/bin/ffmpeg",
            request: try intervalRequest(
                range: FrameExportRange(startSeconds: 2, endSeconds: 12, sourceDuration: 12),
                interval: FrameInterval(seconds: 2.5),
                format: .jpeg,
                jpegQuality: JPEGQuality(ffmpegValue: 4)
            )
        )

        XCTAssertEqual(command.arguments.commandValue(after: "-ss"), "2.000000")
        XCTAssertEqual(command.arguments.commandValue(after: "-t"), "10.000000")
        XCTAssertEqual(command.arguments.commandValue(after: "-vf"), "setpts=PTS-STARTPTS,fps=1/2.5:start_time=0")
        XCTAssertEqual(command.arguments.commandValue(after: "-q:v"), "4")
        XCTAssertEqual(command.arguments.last, "/tmp/frames/input-frame-%06d.jpg")
    }

    func testPathsContainingSpacesRemainSingleArguments() throws {
        let command = try VideoEditingService().intervalFrameExportCommand(
            ffmpegPath: "/opt/homebrew/bin/ffmpeg",
            request: try intervalRequest(
                inputURL: URL(fileURLWithPath: "/tmp/Input Video.mov"),
                outputDirectoryURL: URL(fileURLWithPath: "/tmp/Output Frames")
            )
        )

        XCTAssertEqual(command.arguments.commandValue(after: "-i"), "/tmp/Input Video.mov")
        XCTAssertEqual(command.arguments.last, "/tmp/Output Frames/Input-Video-frame-%06d.png")
    }

    func testSequenceVerificationSucceedsAndFails() throws {
        let directory = try temporaryDirectory()
        let request = try intervalRequest(outputDirectoryURL: directory)
        for number in 1...3 {
            try writeImage(to: request.outputURL(forSequenceNumber: number), format: .png, width: 8, height: 6)
        }

        let files = (1...3).map { request.outputURL(forSequenceNumber: $0) }
        let result = try IntervalFrameExportOutputValidator.verify(request: request, files: files)
        XCTAssertEqual(result.imageCount, 3)
        XCTAssertEqual(result.dimensions, VideoDimensions(width: 8, height: 6))

        XCTAssertThrowsError(try IntervalFrameExportOutputValidator.verify(request: request, files: Array(files.dropFirst())))

        let empty = request.outputURL(forSequenceNumber: 4)
        FileManager.default.createFile(atPath: empty.path, contents: Data())
        var fourFileRequest = request
        fourFileRequest = try intervalRequest(outputDirectoryURL: directory, range: FrameExportRange(startSeconds: 0, endSeconds: 15, sourceDuration: 15))
        XCTAssertThrowsError(try IntervalFrameExportOutputValidator.verify(request: fourFileRequest, files: files + [empty]))
    }

    func testMatchingFilesDetectionIgnoresUnrelatedFiles() throws {
        let directory = try temporaryDirectory()
        let request = try intervalRequest(outputDirectoryURL: directory)
        try writeImage(to: request.outputURL(forSequenceNumber: 1), format: .png, width: 8, height: 6)
        try Data("x".utf8).write(to: directory.appendingPathComponent("unrelated.png"))
        try Data("x".utf8).write(to: directory.appendingPathComponent("other-frame-000001.png"))

        let files = IntervalFrameExportOutputValidator.matchingFiles(
            in: directory,
            request: request,
            fileSystem: LocalEditingFileSystem()
        )

        XCTAssertEqual(files.map(\.lastPathComponent), ["input-frame-000001.png"])
    }

    private func intervalRequest(
        inputURL: URL = URL(fileURLWithPath: "/tmp/input.mov"),
        outputDirectoryURL: URL = URL(fileURLWithPath: "/tmp/frames"),
        range: FrameExportRange? = nil,
        interval: FrameInterval? = nil,
        format: FrameImageFormat = .png,
        jpegQuality: JPEGQuality? = nil
    ) throws -> IntervalFrameExportRequest {
        let resolvedInterval = try interval ?? FrameInterval(seconds: 5)
        let resolvedRange = try range ?? FrameExportRange(startSeconds: 0, endSeconds: 10, sourceDuration: 12)
        return IntervalFrameExportRequest(
            inputURL: inputURL,
            outputDirectoryURL: outputDirectoryURL,
            sourceDuration: 12,
            sourceDimensions: VideoDimensions(width: 8, height: 6),
            sourceRotationDegrees: nil,
            hasVideoStream: true,
            interval: resolvedInterval,
            range: resolvedRange,
            format: format,
            jpegQuality: jpegQuality,
            countTolerance: 1
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeImage(to url: URL, format: FrameImageFormat, width: Int, height: Int) throws {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let pixels = [UInt8](repeating: 200, count: width * height * bytesPerPixel)
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        let image = try XCTUnwrap(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
        let typeIdentifier = format == .png ? UTType.png.identifier : UTType.jpeg.identifier
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, typeIdentifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}

private extension Array where Element == String {
    func commandValue(after option: String) -> String? {
        guard let index = firstIndex(of: option), indices.contains(index + 1) else { return nil }
        return self[index + 1]
    }
}
