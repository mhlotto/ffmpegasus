import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import FFMpegasusCore

final class GIFExportTests: XCTestCase {
    func testFrameRateValidation() throws {
        XCTAssertEqual(try GIFFrameRate(framesPerSecond: 1).framesPerSecond, 1)
        XCTAssertEqual(try GIFFrameRate(framesPerSecond: 10).framesPerSecond, 10)
        XCTAssertEqual(try GIFFrameRate(framesPerSecond: 30).framesPerSecond, 30)
        XCTAssertEqual(GIFFrameRate.parse(" 15 ")?.framesPerSecond, 15)
        XCTAssertNil(GIFFrameRate.parse("0"))
        XCTAssertNil(GIFFrameRate.parse("-1"))
        XCTAssertNil(GIFFrameRate.parse("31"))
        XCTAssertNil(GIFFrameRate.parse("not-number"))
        XCTAssertThrowsError(try GIFFrameRate(framesPerSecond: .nan))
        XCTAssertThrowsError(try GIFFrameRate(framesPerSecond: .infinity))
    }

    func testWidthValidationAndDimensions() throws {
        XCTAssertEqual(try GIFWidth(pixels: 64).pixels, 64)
        XCTAssertEqual(try GIFWidth(pixels: 1920).pixels, 1920)
        XCTAssertEqual(GIFWidth.parse(" 480 ")?.pixels, 480)
        XCTAssertNil(GIFWidth.parse("63"))
        XCTAssertNil(GIFWidth.parse("1921"))
        XCTAssertNil(GIFWidth.parse("480.5"))

        XCTAssertEqual(try request(sizePreset: .wide480).outputDimensions(), VideoDimensions(width: 480, height: 270))
        XCTAssertEqual(try request(sizePreset: .wide1080).outputDimensions(), VideoDimensions(width: 640, height: 360))
        XCTAssertEqual(try request(sizePreset: .custom, customWidth: GIFWidth(pixels: 320)).outputDimensions(), VideoDimensions(width: 320, height: 180))
        XCTAssertEqual(
            try request(sourceDimensions: VideoDimensions(width: 1080, height: 1920), sourceRotationDegrees: 90, sizePreset: .wide720).outputDimensions(),
            VideoDimensions(width: 720, height: 405)
        )
    }

    func testEstimatedFrameCountAndFilenameGeneration() throws {
        XCTAssertEqual(try request(range: FrameExportRange(startSeconds: 0, endSeconds: 6, sourceDuration: 10)).estimatedFrameCount(), 60)
        XCTAssertEqual(try request(range: FrameExportRange(startSeconds: 2, endSeconds: 8, sourceDuration: 10), frameRate: GIFFrameRate(framesPerSecond: 5)).estimatedFrameCount(), 30)

        let input = URL(fileURLWithPath: "/tmp/video.with.dots.mp4")
        XCTAssertEqual(
            OutputFilename.gifName(for: input, range: try FrameExportRange.entireVideo(duration: 10), sourceDuration: 10),
            "video.with.dots.gif"
        )
        XCTAssertEqual(
            OutputFilename.gifName(for: input, range: try FrameExportRange(startSeconds: 2, endSeconds: 8, sourceDuration: 10), sourceDuration: 10),
            "video.with.dots-00-00-02-000-to-00-00-08-000.gif"
        )
    }

    func testQualityAndLoopMappings() {
        XCTAssertEqual(GIFQualityPreset.high.maxColors, 256)
        XCTAssertEqual(GIFQualityPreset.balanced.maxColors, 192)
        XCTAssertEqual(GIFQualityPreset.smallFile.maxColors, 128)
        XCTAssertEqual(GIFQualityPreset.high.dither, "sierra2_4a")
        XCTAssertEqual(GIFLoopMode.forever.ffmpegLoopValue, "0")
        XCTAssertEqual(GIFLoopMode.once.ffmpegLoopValue, "-1")
    }

    func testFilterGraphConstruction() throws {
        let filter = try request(
            frameRate: GIFFrameRate(framesPerSecond: 10),
            sizePreset: .wide480,
            quality: .balanced
        ).filterComplex()

        XCTAssertTrue(filter.contains("setpts=PTS-STARTPTS"))
        XCTAssertTrue(filter.contains("fps=10"))
        XCTAssertTrue(filter.contains("scale=480:-1:flags=lanczos"))
        XCTAssertTrue(filter.contains("split[s0][s1]"))
        XCTAssertTrue(filter.contains("palettegen=max_colors=192"))
        XCTAssertTrue(filter.contains("paletteuse=dither=bayer:bayer_scale=3"))
        XCTAssertFalse(filter.contains("\""))
        XCTAssertFalse(filter.contains("'"))
    }

    func testCommandConstruction() throws {
        let command = try VideoEditingService().gifExportCommand(
            ffmpegPath: "/opt/homebrew/bin/ffmpeg",
            request: request(
                inputURL: URL(fileURLWithPath: "/tmp/input video.mov"),
                outputURL: URL(fileURLWithPath: "/tmp/output file.gif"),
                range: FrameExportRange(startSeconds: 2, endSeconds: 8, sourceDuration: 10),
                loopMode: .once
            )
        )

        XCTAssertEqual(command.arguments[0...1], ["-y", "-nostdin"])
        XCTAssertEqual(command.arguments.commandValue(after: "-ss"), "2.000000")
        XCTAssertEqual(command.arguments.commandValue(after: "-i"), "/tmp/input video.mov")
        XCTAssertEqual(command.arguments.commandValue(after: "-t"), "6.000000")
        XCTAssertNotNil(command.arguments.commandValue(after: "-filter_complex"))
        XCTAssertEqual(command.arguments.commandValue(after: "-loop"), "-1")
        XCTAssertTrue(command.arguments.contains("-an"))
        XCTAssertTrue(command.arguments.contains("-sn"))
        XCTAssertTrue(command.arguments.contains("-dn"))
        XCTAssertTrue(command.arguments.contains("-progress"))
        XCTAssertEqual(command.arguments.commandValue(after: "-progress"), "pipe:1")
        XCTAssertTrue(command.arguments.contains("-nostats"))
        XCTAssertEqual(command.arguments.last, "/tmp/output file.gif")
        XCTAssertFalse(command.arguments.contains("-map"))
        XCTAssertFalse(command.arguments.contains("-c"))
        XCTAssertFalse(command.arguments.joined(separator: " ").contains("\""))
    }

    func testOutputVerificationAcceptsAnimatedGIF() throws {
        let directory = try temporaryDirectory()
        let output = directory.appendingPathComponent("animation.gif")
        let request = request(outputURL: output, range: try FrameExportRange(startSeconds: 0, endSeconds: 1, sourceDuration: 2), frameRate: try GIFFrameRate(framesPerSecond: 10))
        try writeGIF(to: output, width: 480, height: 270, frameCount: 10, delay: 0.1, loopCount: 0)

        let result = try GIFExportOutputValidator.verify(gifURL: output, request: request)

        XCTAssertEqual(result.frameCount, 10)
        XCTAssertEqual(result.dimensions, VideoDimensions(width: 480, height: 270))
        XCTAssertEqual(result.loopMode, GIFLoopMode.forever)
        XCTAssertEqual(result.duration ?? 0, 1, accuracy: 0.001)
    }

    func testOutputVerificationFailures() throws {
        let directory = try temporaryDirectory()
        let valid = directory.appendingPathComponent("valid.gif")
        let wrongDimensions = directory.appendingPathComponent("wrong-dimensions.gif")
        let singleFrame = directory.appendingPathComponent("single.gif")
        let invalid = directory.appendingPathComponent("invalid.gif")
        let wrongExtension = directory.appendingPathComponent("valid.png")
        let validRequest = request(outputURL: valid, range: try FrameExportRange(startSeconds: 0, endSeconds: 1, sourceDuration: 2), frameRate: try GIFFrameRate(framesPerSecond: 10))

        try writeGIF(to: valid, width: 480, height: 270, frameCount: 10, delay: 0.1, loopCount: 0)
        try writeGIF(to: wrongDimensions, width: 320, height: 180, frameCount: 10, delay: 0.1, loopCount: 0)
        try writeGIF(to: singleFrame, width: 480, height: 270, frameCount: 1, delay: 0.1, loopCount: 0)
        try Data("not a gif".utf8).write(to: invalid)
        try FileManager.default.copyItem(at: valid, to: wrongExtension)

        XCTAssertThrowsError(try GIFExportOutputValidator.verify(gifURL: invalid, request: validRequest))
        XCTAssertThrowsError(try GIFExportOutputValidator.verify(gifURL: wrongDimensions, request: request(outputURL: wrongDimensions)))
        XCTAssertThrowsError(try GIFExportOutputValidator.verify(gifURL: singleFrame, request: request(outputURL: singleFrame)))
        XCTAssertThrowsError(try GIFExportOutputValidator.verify(gifURL: wrongExtension, request: request(outputURL: wrongExtension)))
    }

    private func request(
        inputURL: URL = URL(fileURLWithPath: "/tmp/input.mov"),
        outputURL: URL = URL(fileURLWithPath: "/tmp/output.gif"),
        sourceDuration: TimeInterval = 10,
        sourceDimensions: VideoDimensions = VideoDimensions(width: 640, height: 360),
        sourceRotationDegrees: Int? = nil,
        hasVideoStream: Bool = true,
        range: FrameExportRange? = nil,
        frameRate: GIFFrameRate = try! GIFFrameRate(framesPerSecond: 10),
        sizePreset: GIFSizePreset = .wide480,
        customWidth: GIFWidth? = nil,
        quality: GIFQualityPreset = .balanced,
        loopMode: GIFLoopMode = .forever
    ) -> GIFExportRequest {
        GIFExportRequest(
            inputURL: inputURL,
            outputURL: outputURL,
            sourceDuration: sourceDuration,
            sourceDimensions: sourceDimensions,
            sourceRotationDegrees: sourceRotationDegrees,
            hasVideoStream: hasVideoStream,
            range: range ?? (try! FrameExportRange.entireVideo(duration: sourceDuration)),
            frameRate: frameRate,
            sizePreset: sizePreset,
            customWidth: customWidth,
            quality: quality,
            loopMode: loopMode
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeGIF(to url: URL, width: Int, height: Int, frameCount: Int, delay: TimeInterval, loopCount: Int) throws {
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frameCount, nil)
        )
        let gifProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: loopCount
            ]
        ]
        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)
        for index in 0..<frameCount {
            let image = try makeImage(width: width, height: height, seed: index)
            let frameProperties: [CFString: Any] = [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: delay
                ]
            ]
            CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func makeImage(width: Int, height: Int, seed: Int) throws -> CGImage {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * bytesPerPixel
                pixels[offset] = UInt8((x + seed * 11) % 255)
                pixels[offset + 1] = UInt8((y + seed * 17) % 255)
                pixels[offset + 2] = UInt8((seed * 29) % 255)
                pixels[offset + 3] = 255
            }
        }
        let data = Data(pixels)
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        return try XCTUnwrap(CGImage(
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
    }
}

private extension Array where Element == String {
    func commandValue(after option: String) -> String? {
        guard let index = firstIndex(of: option), indices.contains(index + 1) else { return nil }
        return self[index + 1]
    }
}
