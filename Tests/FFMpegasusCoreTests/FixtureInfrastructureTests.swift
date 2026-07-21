import XCTest
@testable import FFMpegasusCore

final class FixtureInfrastructureTests: XCTestCase {
    func testManifestLoadsAndFixtureNamesAreUnique() throws {
        let manifest = try MediaFixtures.loadManifest()
        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertFalse(manifest.fixtures.isEmpty)

        let names = manifest.fixtures.map(\.filename)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertTrue(names.allSatisfy { !$0.contains(" ") })
    }

    func testRequiredMetadataFieldsArePresent() throws {
        let manifest = try MediaFixtures.loadManifest()
        for fixture in manifest.fixtures {
            XCTAssertFalse(fixture.id.isEmpty)
            XCTAssertFalse(fixture.filename.isEmpty)
            XCTAssertFalse(fixture.purpose.isEmpty)
            XCTAssertFalse(fixture.container.isEmpty)
            XCTAssertFalse(fixture.videoCodec.isEmpty)
            XCTAssertGreaterThan(fixture.codedWidth, 0)
            XCTAssertGreaterThan(fixture.codedHeight, 0)
            XCTAssertGreaterThan(fixture.displayWidth, 0)
            XCTAssertGreaterThan(fixture.displayHeight, 0)
            XCTAssertGreaterThan(fixture.durationSeconds, 0)
            XCTAssertGreaterThanOrEqual(fixture.durationToleranceSeconds, 0)
            XCTAssertFalse(fixture.pixelFormat.isEmpty)
            XCTAssertFalse(fixture.expectedTests.isEmpty)
        }
    }

    func testFixturePathsAreRelativeToPackageRoot() throws {
        let standard = try MediaFixtures.fixture(id: "standardLandscape")
        let url = MediaFixtures.url(for: standard)
        XCTAssertTrue(url.path.hasPrefix(MediaFixtures.packageRoot.path))
        XCTAssertFalse(standard.filename.hasPrefix("/"))
        XCTAssertEqual(url.lastPathComponent, "standard-landscape.mp4")
    }

    func testMissingFixtureMessageIncludesUsefulCommand() throws {
        let fixture = try MediaFixtures.fixture(id: "standardLandscape")
        let message = MediaFixtures.missingFixtureMessage(fixture)
        XCTAssertTrue(message.contains("make fixtures"))
        XCTAssertTrue(message.contains(fixture.filename))
    }

    func testOptionalFixtureGenerationIsIdempotentAndValidates() async throws {
        _ = try MediaFixtures.requireTools()

        let firstGeneration = try await ProcessRunner().run(executablePath: MediaFixtures.scriptURL.path, arguments: ["generate"])
        XCTAssertEqual(firstGeneration.exitCode, 0, firstGeneration.stderrText.isEmpty ? firstGeneration.stdoutText : firstGeneration.stderrText)

        let manifest = try MediaFixtures.loadManifest()
        let before = try manifest.fixtures.map { fixture -> (String, UInt64) in
            let url = MediaFixtures.url(for: fixture)
            let size = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)
            return (fixture.filename, size.uint64Value)
        }

        let secondGeneration = try await ProcessRunner().run(executablePath: MediaFixtures.scriptURL.path, arguments: ["generate"])
        XCTAssertEqual(secondGeneration.exitCode, 0, secondGeneration.stderrText.isEmpty ? secondGeneration.stdoutText : secondGeneration.stderrText)
        try await MediaFixtures.validateGenerated()

        let after = try manifest.fixtures.map { fixture -> (String, UInt64) in
            let url = MediaFixtures.url(for: fixture)
            let size = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)
            return (fixture.filename, size.uint64Value)
        }
        XCTAssertEqual(before.map { $0.0 }, after.map { $0.0 })
        XCTAssertEqual(before.count, after.count)
        XCTAssertTrue(after.allSatisfy { $0.1 > 0 })
    }

    func testOptionalFixtureGenerationRegeneratesDeletedFixtureInSameProcess() async throws {
        _ = try MediaFixtures.requireTools()
        try await MediaFixtures.ensureGenerated()

        let fixture = try MediaFixtures.fixture(id: "standardLandscape")
        let url = MediaFixtures.url(for: fixture)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        try FileManager.default.removeItem(at: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        try await MediaFixtures.ensureGenerated()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        try await MediaFixtures.validateGenerated()
    }

    func testFixtureCoordinatorReusesValidExistingFixture() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixtureURL = directory.appendingPathComponent("fixture.mp4")
        let runsURL = directory.appendingPathComponent("runs.txt")
        let scriptURL = try fixtureValidationScript(in: directory, fixtureURL: fixtureURL, runsURL: runsURL)
        try "valid".write(to: fixtureURL, atomically: true, encoding: .utf8)

        let coordinator = FixtureGenerationCoordinator()
        try await coordinator.ensureReady(scriptURL: scriptURL, expectedFixtureURLs: [fixtureURL])
        try await coordinator.ensureReady(scriptURL: scriptURL, expectedFixtureURLs: [fixtureURL])

        XCTAssertFalse(FileManager.default.fileExists(atPath: runsURL.path))
    }

    func testFixtureCoordinatorRejectsZeroByteFixtureAndRegenerates() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixtureURL = directory.appendingPathComponent("fixture.mp4")
        let runsURL = directory.appendingPathComponent("runs.txt")
        let scriptURL = try fixtureValidationScript(in: directory, fixtureURL: fixtureURL, runsURL: runsURL)
        FileManager.default.createFile(atPath: fixtureURL.path, contents: Data())

        let coordinator = FixtureGenerationCoordinator()
        try await coordinator.ensureReady(scriptURL: scriptURL, expectedFixtureURLs: [fixtureURL])

        XCTAssertEqual(try String(contentsOf: fixtureURL, encoding: .utf8), "valid")
        XCTAssertEqual(try String(contentsOf: runsURL, encoding: .utf8), "generate\n")
    }

    func testFixtureCoordinatorRejectsCorruptFixtureAndRegenerates() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixtureURL = directory.appendingPathComponent("fixture.mp4")
        let runsURL = directory.appendingPathComponent("runs.txt")
        let scriptURL = try fixtureValidationScript(in: directory, fixtureURL: fixtureURL, runsURL: runsURL)
        try "corrupt".write(to: fixtureURL, atomically: true, encoding: .utf8)

        let coordinator = FixtureGenerationCoordinator()
        try await coordinator.ensureReady(scriptURL: scriptURL, expectedFixtureURLs: [fixtureURL])

        XCTAssertEqual(try String(contentsOf: fixtureURL, encoding: .utf8), "valid")
        XCTAssertEqual(try String(contentsOf: runsURL, encoding: .utf8), "generate\n")
    }

    func testFixtureCoordinatorRegeneratesMissingFixtureAndSharesConcurrentRequests() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixtureURL = directory.appendingPathComponent("fixture.mp4")
        let runsURL = directory.appendingPathComponent("runs.txt")
        let scriptURL = try fixtureValidationScript(in: directory, fixtureURL: fixtureURL, runsURL: runsURL)

        let coordinator = FixtureGenerationCoordinator()
        async let first: Void = coordinator.ensureReady(scriptURL: scriptURL, expectedFixtureURLs: [fixtureURL])
        async let second: Void = coordinator.ensureReady(scriptURL: scriptURL, expectedFixtureURLs: [fixtureURL])
        _ = try await (first, second)

        XCTAssertEqual(try String(contentsOf: fixtureURL, encoding: .utf8), "valid")
        XCTAssertEqual(try String(contentsOf: runsURL, encoding: .utf8), "generate\n")
    }

    func testFixtureCleanupSelfTestRemovesWorkDirectoriesAfterFailure() async throws {
        _ = try MediaFixtures.requireTools()
        try FileManager.default.createDirectory(at: MediaFixtures.generatedDirectory, withIntermediateDirectories: true)
        let before = Set(workDirectoryNames())

        let result = try await ProcessRunner().run(executablePath: MediaFixtures.scriptURL.path, arguments: ["cleanup-self-test"])
        XCTAssertNotEqual(result.exitCode, 0)

        let after = Set(workDirectoryNames())
        XCTAssertEqual(after.subtracting(before), [])
    }

    func testSourceArchiveExcludesGeneratedFixturesAndWorkDirectories() async throws {
        let generatedFile = MediaFixtures.generatedDirectory.appendingPathComponent("archive-exclusion-test.mp4")
        let workDirectory = MediaFixtures.generatedDirectory.appendingPathComponent("rotation-work.archive-test", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        try Data([0x01]).write(to: generatedFile)
        defer {
            try? FileManager.default.removeItem(at: generatedFile)
            try? FileManager.default.removeItem(at: workDirectory)
        }

        let archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ffmpegasus-source-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: archiveURL) }

        let scriptURL = MediaFixtures.packageRoot.appendingPathComponent("scripts/ziprepo.bash")
        let result = try await ProcessRunner().run(executablePath: scriptURL.path, arguments: [archiveURL.path])
        XCTAssertEqual(result.exitCode, 0, result.stderrText)

        let listing = try await ProcessRunner().run(executablePath: "/usr/bin/unzip", arguments: ["-Z1", archiveURL.path])
        XCTAssertEqual(listing.exitCode, 0, listing.stderrText)
        XCTAssertFalse(listing.stdoutText.contains("Tests/Fixtures/generated/"))
        XCTAssertFalse(listing.stdoutText.contains("rotation-work."))
        XCTAssertFalse(listing.stdoutText.contains("vfr-work."))
    }

    func testFixtureGenerationCoordinatorSharesConcurrentRequests() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let runsURL = directory.appendingPathComponent("runs.txt")
        let scriptURL = directory.appendingPathComponent("generate-fixtures")
        try writeExecutableScript(
            to: scriptURL,
            contents: """
            #!/bin/sh
            printf run >> '\(runsURL.path)'
            sleep 0.1
            exit 0
            """
        )

        let coordinator = FixtureGenerationCoordinator()
        async let first: Void = coordinator.generate(scriptURL: scriptURL)
        async let second: Void = coordinator.generate(scriptURL: scriptURL)
        _ = try await (first, second)

        XCTAssertEqual(try String(contentsOf: runsURL, encoding: .utf8), "run")
    }

    func testFixtureGenerationCoordinatorRetriesAfterFailure() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let failingScriptURL = directory.appendingPathComponent("fail-fixtures")
        let successScriptURL = directory.appendingPathComponent("generate-fixtures")
        try writeExecutableScript(
            to: failingScriptURL,
            contents: """
            #!/bin/sh
            echo failed >&2
            exit 2
            """
        )
        try writeExecutableScript(
            to: successScriptURL,
            contents: """
            #!/bin/sh
            exit 0
            """
        )

        let coordinator = FixtureGenerationCoordinator()
        do {
            try await coordinator.generate(scriptURL: failingScriptURL)
            XCTFail("Expected failing fixture generation script to throw")
        } catch {
            XCTAssertTrue(String(describing: error).contains("failed"))
        }

        try await coordinator.generate(scriptURL: successScriptURL)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ffmpegasus-fixture-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeExecutableScript(to url: URL, contents: String) throws {
        try contents.data(using: .utf8)!.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func workDirectoryNames() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: MediaFixtures.generatedDirectory.path)) ?? [])
            .filter { $0.hasPrefix("rotation-work.") || $0.hasPrefix("vfr-work.") }
    }

    private func fixtureValidationScript(in directory: URL, fixtureURL: URL, runsURL: URL) throws -> URL {
        let scriptURL = directory.appendingPathComponent("fixtures")
        try writeExecutableScript(
            to: scriptURL,
            contents: """
            #!/bin/sh
            set -eu
            case "$1" in
              validate)
                test -s '\(fixtureURL.path)' || exit 3
                test "$(cat '\(fixtureURL.path)')" = "valid" || exit 4
                ;;
              generate)
                printf 'generate\\n' >> '\(runsURL.path)'
                printf valid > '\(fixtureURL.path)'
                ;;
              *)
                exit 2
                ;;
            esac
            """
        )
        return scriptURL
    }
}
