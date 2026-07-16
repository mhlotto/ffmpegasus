import XCTest
@testable import FFMpegasusCore

final class TestBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        lock.lock()
        let value = storage
        lock.unlock()
        return value
    }

    func set(_ value: Value) {
        lock.lock()
        storage = value
        lock.unlock()
    }

    func update(_ body: (inout Value) -> Void) {
        lock.lock()
        body(&storage)
        lock.unlock()
    }
}

final class ProcessRunnerTests: XCTestCase {
    func testNullStdinLetsCatExitImmediately() async throws {
        let result = try await ProcessRunner().run(executablePath: "/bin/cat", arguments: [])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, Data())
    }

    func testPartialStdoutProgressLinesAreBuffered() {
        let lines = TestBox<[String]>([])
        let collector = ProcessPipeCollector(lineHandler: { line in
            lines.update { $0.append(line) }
        })

        collector.append(Data("out_time_us=10".utf8))
        XCTAssertEqual(lines.value, [])

        collector.append(Data("00000\nprogress=continue\n".utf8))
        XCTAssertEqual(lines.value, ["out_time_us=1000000", "progress=continue"])
    }

    func testMultipleProgressRecordsInOneChunkAreParsed() {
        let lines = TestBox<[String]>([])
        let collector = ProcessPipeCollector(lineHandler: { line in
            lines.update { $0.append(line) }
        })

        collector.append(Data("out_time=00:00:01.000000\nprogress=continue\nout_time_ms=2000000\nprogress=end\n".utf8))

        XCTAssertEqual(lines.value, [
            "out_time=00:00:01.000000",
            "progress=continue",
            "out_time_ms=2000000",
            "progress=end"
        ])
    }

    func testEOFWithFinalUnterminatedLineIsHandled() {
        let lines = TestBox<[String]>([])
        let collector = ProcessPipeCollector(lineHandler: { line in
            lines.update { $0.append(line) }
        })

        collector.append(Data("progress=end".utf8))
        collector.finishUnterminatedLine()

        XCTAssertEqual(lines.value, ["progress=end"])
    }

    func testLargeStderrOutputIsDrainedAndTailIsBounded() async throws {
        let script = try makeExecutableScript("""
        #!/bin/sh
        i=0
        while [ $i -lt 5000 ]; do
          echo "stderr-line-$i" 1>&2
          i=$((i + 1))
        done
        echo done
        """)

        let latestTail = TestBox("")
        let result = try await ProcessRunner().run(
            executablePath: script.path,
            arguments: [],
            activityHandler: { activity in
                if !activity.stderrTail.isEmpty {
                    latestTail.set(activity.stderrTail)
                }
            }
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdoutText.contains("done"))
        XCTAssertTrue(result.stderrText.contains("stderr-line-4999"))
        XCTAssertLessThanOrEqual(latestTail.value.utf8.count, 65_536)
    }

    func testLaunchFailureThrows() async {
        do {
            _ = try await ProcessRunner().run(executablePath: "/tmp/definitely-missing-executable", arguments: [])
            XCTFail("Expected launch failure")
        } catch ProcessExecutionError.launchFailed {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRealProcessRunnerCapturesStdoutStderrAndExitStatus() async throws {
        let result = try await ProcessRunner().run(executablePath: "/bin/ls", arguments: ["/", "/definitely-missing-ffmpegasus-path"])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertFalse(result.stdoutText.isEmpty)
        XCTAssertTrue(result.stderrText.contains("/definitely-missing-ffmpegasus-path"))
    }

    func testCancellationCompletesOnce() async throws {
        let script = try makeExecutableScript("""
        #!/bin/sh
        trap 'exit 42' TERM
        while true; do
          sleep 1
        done
        """)
        let activeProcess = ActiveProcess()
        let task = Task {
            try await ProcessRunner().run(executablePath: script.path, arguments: [], activeProcess: activeProcess)
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        activeProcess.terminateThenKill(after: 100_000_000)

        do {
            let result = try await task.value
            XCTAssertTrue(result.exitCode == 42 || result.exitCode == 9 || result.exitCode == 15)
        } catch {
            XCTFail("Cancellation should settle through process termination result, got \(error)")
        }
    }

    private func makeExecutableScript(_ contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("script.sh")
        try contents.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }
}
