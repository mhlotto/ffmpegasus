import Foundation
import XCTest

final class FFMpegasusGUITests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    private var packageRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            url.deleteLastPathComponent()
        }
        return url
    }

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try super.tearDownWithError()
    }

    func testLaunchSmoke() throws {
        try requireEnabled()

        let directory = try temporaryDirectory(named: "launch")
        let resultURL = directory.appendingPathComponent("result.json")

        let result = try launchAppAndReadResult(
            resultURL: resultURL,
            extraEnvironment: [:]
        )

        XCTAssertEqual(result["launched"] as? Bool, true)
        XCTAssertEqual(result["mainContentPresent"] as? Bool, true)
        XCTAssertNil(result["unexpectedError"])
    }

    func testLoadedFixturePlaybackSectionsAndFrameExportSmoke() throws {
        try requireEnabled()

        let fixtureURL = packageRoot
            .appendingPathComponent("Tests/Fixtures/generated/standard-landscape.mp4")
        guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
            throw XCTSkip("Missing generated fixture. Run `make fixtures` before `make ui-test`.")
        }

        let directory = try temporaryDirectory(named: "loaded-fixture")
        let resultURL = directory.appendingPathComponent("result.json")
        let frameOutputURL = directory.appendingPathComponent("frame-smoke.png")
        let gifOutputURL = directory.appendingPathComponent("gif-smoke.gif")

        let result = try launchAppAndReadResult(
            resultURL: resultURL,
            extraEnvironment: [
                "FFMPEGASUS_UI_TEST_FIXTURE": fixtureURL.path,
                "FFMPEGASUS_UI_TEST_FRAME_OUTPUT": frameOutputURL.path,
                "FFMPEGASUS_UI_TEST_GIF_OUTPUT": gifOutputURL.path
            ]
        )

        XCTAssertEqual(result["fixtureLoaded"] as? Bool, true)
        XCTAssertEqual(result["metadataVisible"] as? Bool, true)
        XCTAssertEqual(result["playbackControlsEnabled"] as? Bool, true)
        XCTAssertEqual(result["timelineAvailable"] as? Bool, true)
        XCTAssertEqual(result["playbackAdvanced"] as? Bool, true)
        XCTAssertEqual(result["pauseStable"] as? Bool, true)
        XCTAssertEqual(result["seekChanged"] as? Bool, true)
        XCTAssertEqual(result["stopReset"] as? Bool, true)

        let sections = try XCTUnwrap(result["editingSections"] as? [String])
        for expected in [
            "Trim",
            "Remove Audio",
            "Combined Export",
            "Rotate / Flip",
            "Compress / Resize",
            "Change Speed",
            "Export Current Frame",
            "Export Frames at Intervals",
            "Export GIF"
        ] {
            XCTAssertTrue(sections.contains(expected), "Missing editing section: \(expected)")
        }

        XCTAssertEqual(result["frameExportCompleted"] as? Bool, true, result["operationMessage"] as? String ?? "")
        XCTAssertTrue(FileManager.default.fileExists(atPath: frameOutputURL.path))
        let size = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: frameOutputURL.path)[.size] as? NSNumber)
        XCTAssertGreaterThan(size.uint64Value, 0)

        XCTAssertEqual(result["gifExportCompleted"] as? Bool, true, result["gifExportError"] as? String ?? "")
        XCTAssertTrue(FileManager.default.fileExists(atPath: gifOutputURL.path))
        let gifSize = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: gifOutputURL.path)[.size] as? NSNumber)
        XCTAssertGreaterThan(gifSize.uint64Value, 0)
    }

    private func requireEnabled() throws {
        guard ProcessInfo.processInfo.environment["FFMPEGASUS_RUN_GUI_TESTS"] == "1" else {
            throw XCTSkip("GUI smoke tests are disabled. Run `make ui-test`.")
        }
    }

    private func launchAppAndReadResult(
        resultURL: URL,
        extraEnvironment: [String: String],
        timeout: TimeInterval = 25
    ) throws -> [String: Any] {
        let appURL = try builtAppExecutable()
        let stdout = Pipe()
        let stderr = Pipe()
        let process = Process()
        process.executableURL = appURL
        process.standardOutput = stdout
        process.standardError = stderr
        process.environment = ProcessInfo.processInfo.environment.merging([
            "FFMPEGASUS_UI_TEST_MODE": "1",
            "FFMPEGASUS_UI_TEST_RESET_DEFAULTS": "1",
            "FFMPEGASUS_UI_TEST_RESULT": resultURL.path,
            "FFMPEGASUS_UI_TEST_QUIT_AFTER": "1"
        ].merging(extraEnvironment) { _, new in new }) { _, new in new }

        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, process.isRunning, !FileManager.default.fileExists(atPath: resultURL.path) {
            Thread.sleep(forTimeInterval: 0.1)
        }

        if process.isRunning {
            process.terminate()
        }

        let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        attachDiagnostics(resultURL: resultURL, stdout: stdoutText, stderr: stderrText)

        guard FileManager.default.fileExists(atPath: resultURL.path) else {
            XCTFail("FFMpegasus did not write UI smoke result before timeout.\nstdout:\n\(stdoutText)\nstderr:\n\(stderrText)")
            return [:]
        }

        let data = try Data(contentsOf: resultURL)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    private func builtAppExecutable() throws -> URL {
        let candidates = [
            packageRoot.appendingPathComponent(".build/debug/FFMpegasus"),
            packageRoot.appendingPathComponent(".build/arm64-apple-macosx/debug/FFMpegasus"),
            packageRoot.appendingPathComponent(".build/arm64-apple-macosx/debug/FFMpegasus.app/Contents/MacOS/FFMpegasus")
        ]
        if let candidate = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            return candidate
        }
        throw XCTSkip("Built FFMpegasus executable was not found. Run `swift build` before UI smoke tests.")
    }

    private func temporaryDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ffmpegasus-ui-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryDirectories.append(url)
        return url
    }

    private func attachDiagnostics(resultURL: URL, stdout: String, stderr: String) {
        if FileManager.default.fileExists(atPath: resultURL.path),
           let result = try? String(contentsOf: resultURL, encoding: .utf8) {
            let attachment = XCTAttachment(string: result)
            attachment.name = "ui-smoke-result.json"
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        let stdoutAttachment = XCTAttachment(string: stdout.isEmpty ? "(empty)" : stdout)
        stdoutAttachment.name = "ffmpegasus-stdout.txt"
        stdoutAttachment.lifetime = .keepAlways
        add(stdoutAttachment)

        let stderrAttachment = XCTAttachment(string: stderr.isEmpty ? "(empty)" : stderr)
        stderrAttachment.name = "ffmpegasus-stderr.txt"
        stderrAttachment.lifetime = .keepAlways
        add(stderrAttachment)
    }
}
