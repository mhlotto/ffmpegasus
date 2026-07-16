import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import FFMpegasusCore

final class FrameExportTests: XCTestCase {
    func testTimestampClampingAndValidation() throws {
        XCTAssertEqual(try FrameExportTimestamp.clamped(0, duration: 10), 0)
        XCTAssertEqual(try FrameExportTimestamp.clamped(1.25, duration: 10), 1.25)
        XCTAssertEqual(try FrameExportTimestamp.clamped(-1, duration: 10), 0)
        XCTAssertEqual(try FrameExportTimestamp.clamped(12, duration: 10), 10)
        XCTAssertThrowsError(try FrameExportTimestamp.clamped(.nan, duration: 10))
        XCTAssertThrowsError(try FrameExportTimestamp.clamped(.infinity, duration: 10))
        XCTAssertThrowsError(try FrameExportTimestamp.clamped(-.infinity, duration: 10))
        XCTAssertThrowsError(try FrameExportTimestamp.clamped(1, duration: .nan))
    }

    func testTimestampFormattingIsDeterministic() {
        XCTAssertEqual(FrameExportTimestamp.ffmpegSeconds(0), "0.000000")
        XCTAssertEqual(FrameExportTimestamp.ffmpegSeconds(1.25), "1.250000")
        XCTAssertEqual(FrameExportTimestamp.ffmpegSeconds(83.45), "83.450000")
        XCTAssertEqual(FrameExportTimestamp.displayTime(83.45), "00:01:23.450")
        XCTAssertEqual(FrameExportTimestamp.displayTime(3_723.456), "01:02:03.456")
        XCTAssertEqual(FrameExportTimestamp.filenameLabel(83.45), "00-01-23-450")
    }

    func testFrameFilenameGeneration() {
        let png = OutputFilename.frameName(
            for: URL(fileURLWithPath: "/tmp/video.mp4"),
            timestamp: 1.25,
            format: .png
        )
        let jpeg = OutputFilename.frameName(
            for: URL(fileURLWithPath: "/tmp/clip.final.mov"),
            timestamp: 83.45,
            format: .jpeg
        )
        let spaced = OutputFilename.frameName(
            for: URL(fileURLWithPath: "/tmp/Input Video.mov"),
            timestamp: 0.5,
            format: .png
        )

        XCTAssertEqual(png, "video-frame-00-00-01-250.png")
        XCTAssertEqual(jpeg, "clip.final-frame-00-01-23-450.jpg")
        XCTAssertEqual(spaced, "Input-Video-frame-00-00-00-500.png")
        XCTAssertFalse(spaced.contains(" "))
    }

    func testJPEGQualityPresetsAndValidation() throws {
        XCTAssertEqual(JPEGQualityPreset.high.qualityValue, 2)
        XCTAssertEqual(JPEGQualityPreset.balanced.qualityValue, 4)
        XCTAssertEqual(JPEGQualityPreset.smallFile.qualityValue, 7)
        XCTAssertEqual(try JPEGQuality(ffmpegValue: 2).ffmpegValue, 2)
        XCTAssertEqual(try JPEGQuality(ffmpegValue: 31).ffmpegValue, 31)
        XCTAssertThrowsError(try JPEGQuality(ffmpegValue: 1))
        XCTAssertThrowsError(try JPEGQuality(ffmpegValue: 32))
    }

    func testRequestValidationAndExpectedDimensions() throws {
        let portraitRequest = request(
            timestamp: 1,
            dimensions: VideoDimensions(width: 1920, height: 1080),
            rotation: 90
        )
        XCTAssertEqual(try portraitRequest.expectedDimensions(), VideoDimensions(width: 1080, height: 1920))

        XCTAssertThrowsError(try request(timestamp: -1).validate())
        XCTAssertThrowsError(try request(timestamp: 11).validate())
        XCTAssertThrowsError(try request(timestamp: .nan).validate())
        XCTAssertThrowsError(try request(hasVideoStream: false).validate())
        XCTAssertThrowsError(try request(format: .jpeg, jpegQuality: nil).validate())
    }

    func testPNGCommandConstructionUsesOutputSideSeek() throws {
        let command = try VideoEditingService().frameExportCommand(
            ffmpegPath: "/opt/homebrew/bin/ffmpeg",
            request: request(timestamp: 83.45, duration: 120, format: .png)
        )

        XCTAssertEqual(command.arguments, [
            "-y",
            "-nostdin",
            "-i", "/tmp/input.mov",
            "-ss", "83.450000",
            "-map", "0:v:0",
            "-frames:v", "1",
            "-an",
            "-sn",
            "-dn",
            "/tmp/output.png"
        ])
        XCTAssertFalse(command.arguments.contains("-q:v"))
        XCTAssertLessThan(
            try XCTUnwrap(command.arguments.firstIndex(of: "-i")),
            try XCTUnwrap(command.arguments.firstIndex(of: "-ss"))
        )
        XCTAssertFalse(command.arguments.joined(separator: " ").contains("\""))
    }

    func testJPEGCommandConstructionIncludesQuality() throws {
        let command = try VideoEditingService().frameExportCommand(
            ffmpegPath: "/opt/homebrew/bin/ffmpeg",
            request: request(format: .jpeg, jpegQuality: try JPEGQuality(ffmpegValue: 4))
        )

        XCTAssertEqual(command.arguments.commandValue(after: "-q:v"), "4")
        XCTAssertEqual(command.arguments.commandValue(after: "-frames:v"), "1")
        XCTAssertTrue(command.arguments.contains("-an"))
        XCTAssertTrue(command.arguments.contains("-sn"))
        XCTAssertTrue(command.arguments.contains("-dn"))
        XCTAssertFalse(command.arguments.contains("-c"))
    }

    func testCommandSupportsPathsContainingSpaces() throws {
        let command = try VideoEditingService().frameExportCommand(
            ffmpegPath: "/opt/homebrew/bin/ffmpeg",
            request: request(
                inputURL: URL(fileURLWithPath: "/tmp/Input Video.mov"),
                outputURL: URL(fileURLWithPath: "/tmp/Output Frame.png"),
                timestamp: 1.25,
                format: .png
            )
        )

        XCTAssertEqual(command.arguments.commandValue(after: "-i"), "/tmp/Input Video.mov")
        XCTAssertEqual(command.arguments.last, "/tmp/Output Frame.png")
    }

    func testOutputVerificationAcceptsPNGAndJPEG() throws {
        let directory = try temporaryDirectory()
        let png = directory.appendingPathComponent("frame.png")
        let jpg = directory.appendingPathComponent("frame.jpg")
        try writeImage(to: png, format: .png, width: 8, height: 6)
        try writeImage(to: jpg, format: .jpeg, width: 8, height: 6)

        let pngInfo = try FrameExportOutputValidator.verify(imageURL: png, request: request(outputURL: png, format: .png))
        let jpgInfo = try FrameExportOutputValidator.verify(imageURL: jpg, request: request(outputURL: jpg, format: .jpeg, jpegQuality: try JPEGQuality(ffmpegValue: 4)))

        XCTAssertEqual(pngInfo.format, .png)
        XCTAssertEqual(jpgInfo.format, .jpeg)
        XCTAssertEqual(pngInfo.dimensions, VideoDimensions(width: 8, height: 6))
        XCTAssertEqual(jpgInfo.dimensions, VideoDimensions(width: 8, height: 6))
    }

    func testOutputVerificationFailures() throws {
        let directory = try temporaryDirectory()
        let png = directory.appendingPathComponent("frame.png")
        let wrongExtension = directory.appendingPathComponent("frame.jpg")
        let invalid = directory.appendingPathComponent("invalid.png")
        try writeImage(to: png, format: .png, width: 8, height: 6)
        try writeImage(to: wrongExtension, format: .png, width: 8, height: 6)
        try "not an image".data(using: .utf8)!.write(to: invalid)

        XCTAssertThrowsError(try FrameExportOutputValidator.verify(imageURL: invalid, request: request(outputURL: invalid, format: .png)))
        XCTAssertThrowsError(try FrameExportOutputValidator.verify(imageURL: png, request: request(outputURL: png, dimensions: VideoDimensions(width: 7, height: 6), format: .png)))
        XCTAssertThrowsError(try FrameExportOutputValidator.verify(imageURL: wrongExtension, request: request(outputURL: wrongExtension, format: .png)))
        XCTAssertThrowsError(try FrameExportOutputValidator.verify(imageURL: png, request: request(outputURL: png, format: .jpeg, jpegQuality: try JPEGQuality(ffmpegValue: 4))))
    }

    private func request(
        inputURL: URL = URL(fileURLWithPath: "/tmp/input.mov"),
        outputURL: URL? = nil,
        timestamp: TimeInterval = 1,
        duration: TimeInterval = 10,
        dimensions: VideoDimensions = VideoDimensions(width: 8, height: 6),
        rotation: Int? = nil,
        hasVideoStream: Bool = true,
        format: FrameImageFormat = .png,
        jpegQuality: JPEGQuality? = nil
    ) -> FrameExportRequest {
        FrameExportRequest(
            inputURL: inputURL,
            outputURL: outputURL ?? URL(fileURLWithPath: "/tmp/output.\(format.fileExtension)"),
            timestampSeconds: timestamp,
            sourceDuration: duration,
            sourceDimensions: dimensions,
            sourceRotationDegrees: rotation,
            hasVideoStream: hasVideoStream,
            format: format,
            jpegQuality: jpegQuality
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
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * bytesPerPixel
                pixels[offset] = UInt8((x * 31) % 255)
                pixels[offset + 1] = UInt8((y * 47) % 255)
                pixels[offset + 2] = 180
                pixels[offset + 3] = 255
            }
        }
        let data = Data(pixels)
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
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
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, typeIdentifier as CFString, 1, nil)
        )
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
