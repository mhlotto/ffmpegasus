import Foundation
import XCTest
@testable import FFMpegasusCore

struct FixtureManifest: Decodable {
    let schemaVersion: Int
    let generatedDirectory: String
    let fixtures: [MediaFixture]
}

struct MediaFixture: Decodable {
    let id: String
    let filename: String
    let purpose: String
    let container: String
    let videoCodec: String
    let audioCodec: String?
    let codedWidth: Int
    let codedHeight: Int
    let displayWidth: Int
    let displayHeight: Int
    let frameRatePolicy: String
    let durationSeconds: TimeInterval
    let durationToleranceSeconds: TimeInterval
    let rotationDegrees: Int?
    let pixelFormat: String
    let specialTiming: String
    let expectedTests: [String]
}

enum MediaFixtures {
    private static let generationCoordinator = FixtureGenerationCoordinator()

    static var packageRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 {
            url.deleteLastPathComponent()
        }
        return url
    }

    static var fixturesDirectory: URL {
        packageRoot.appendingPathComponent("Tests/Fixtures", isDirectory: true)
    }

    static var generatedDirectory: URL {
        fixturesDirectory.appendingPathComponent("generated", isDirectory: true)
    }

    static var manifestURL: URL {
        fixturesDirectory.appendingPathComponent("manifest.json")
    }

    static var scriptURL: URL {
        packageRoot.appendingPathComponent("scripts/fixtures.sh")
    }

    static func loadManifest() throws -> FixtureManifest {
        let data = try Data(contentsOf: manifestURL)
        return try JSONDecoder().decode(FixtureManifest.self, from: data)
    }

    static func fixture(id: String) throws -> MediaFixture {
        let manifest = try loadManifest()
        guard let fixture = manifest.fixtures.first(where: { $0.id == id }) else {
            throw FixtureError.unknownFixture(id)
        }
        return fixture
    }

    static func url(for fixture: MediaFixture) -> URL {
        generatedDirectory.appendingPathComponent(fixture.filename)
    }

    static func url(forID id: String) throws -> URL {
        try url(for: fixture(id: id))
    }

    static func missingFixtureMessage(_ fixture: MediaFixture) -> String {
        "Missing generated fixture \(fixture.filename). Run `make fixtures` from \(packageRoot.path)."
    }

    static func requireTools() throws -> (ffmpeg: String, ffprobe: String) {
        let ffmpeg = toolPath(environmentKey: "FFMPEG", defaultPath: "/opt/homebrew/bin/ffmpeg", name: "ffmpeg")
        let ffprobe = toolPath(environmentKey: "FFPROBE", defaultPath: "/opt/homebrew/bin/ffprobe", name: "ffprobe")
        guard let ffmpeg, let ffprobe else {
            throw XCTSkip("FFmpeg or FFprobe is unavailable; run fixture-backed integration tests on a machine with both tools installed.")
        }
        return (ffmpeg, ffprobe)
    }

    static func ensureGenerated() async throws {
        let manifest = try loadManifest()
        _ = try requireTools()

        do {
            try await generationCoordinator.ensureReady(
                scriptURL: scriptURL,
                expectedFixtureURLs: manifest.fixtures.map { url(for: $0) }
            )
        } catch {
            XCTFail(String(describing: error))
            throw FixtureError.generationFailed
        }
    }

    static func validateGenerated() async throws {
        _ = try requireTools()
        let result = try await ProcessRunner().run(executablePath: scriptURL.path, arguments: ["validate"])
        guard result.exitCode == 0 else {
            XCTFail(result.stderrText.isEmpty ? result.stdoutText : result.stderrText)
            throw FixtureError.validationFailed
        }
    }

    private static func toolPath(environmentKey: String, defaultPath: String, name: String) -> String? {
        let environmentValue = ProcessInfo.processInfo.environment[environmentKey]
        if let environmentValue, FileManager.default.isExecutableFile(atPath: environmentValue) {
            return environmentValue
        }
        if FileManager.default.isExecutableFile(atPath: defaultPath) {
            return defaultPath
        }
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for directory in paths {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(name).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}

enum FixtureError: Error {
    case unknownFixture(String)
    case generationFailed
    case validationFailed
}

actor FixtureGenerationCoordinator {
    private var readinessTask: Task<Void, Error>?
    private var validatedSignature: String?

    func ensureReady(scriptURL: URL, expectedFixtureURLs: [URL]) async throws {
        if let readinessTask {
            try await readinessTask.value
            return
        }
        let signature = fixtureSignature(for: expectedFixtureURLs)
        if let signature, signature == validatedSignature {
            return
        }

        let task = Task {
            if expectedFixtureURLs.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) {
                let validation = try await ProcessRunner().run(executablePath: scriptURL.path, arguments: ["validate"])
                if validation.exitCode == 0 {
                    return
                }
            }

            let generation = try await ProcessRunner().run(executablePath: scriptURL.path, arguments: ["generate"])
            guard generation.exitCode == 0 else {
                throw FixtureCommandError(message: generation.stderrText.isEmpty ? generation.stdoutText : generation.stderrText)
            }
        }
        readinessTask = task

        do {
            try await task.value
            readinessTask = nil
            validatedSignature = fixtureSignature(for: expectedFixtureURLs)
        } catch {
            readinessTask = nil
            validatedSignature = nil
            throw error
        }
    }

    func generate(scriptURL: URL) async throws {
        if let readinessTask {
            try await readinessTask.value
            return
        }

        let task = Task {
            let generation = try await ProcessRunner().run(executablePath: scriptURL.path, arguments: ["generate"])
            guard generation.exitCode == 0 else {
                throw FixtureCommandError(message: generation.stderrText.isEmpty ? generation.stdoutText : generation.stderrText)
            }
        }
        readinessTask = task

        do {
            try await task.value
            readinessTask = nil
            validatedSignature = nil
        } catch {
            readinessTask = nil
            validatedSignature = nil
            throw error
        }
    }

    private func fixtureSignature(for urls: [URL]) -> String? {
        guard !urls.isEmpty else { return nil }
        var components: [String] = []
        for url in urls {
            guard
                let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                let size = attributes[.size] as? NSNumber,
                let modified = attributes[.modificationDate] as? Date
            else {
                return nil
            }
            components.append("\(url.lastPathComponent):\(size.uint64Value):\(modified.timeIntervalSince1970)")
        }
        return components.sorted().joined(separator: "|")
    }
}

private struct FixtureCommandError: Error, CustomStringConvertible {
    let message: String

    var description: String {
        message
    }
}
