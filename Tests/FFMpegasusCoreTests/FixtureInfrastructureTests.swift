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
}
