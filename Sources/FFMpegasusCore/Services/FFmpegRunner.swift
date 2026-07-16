import Darwin
import Foundation

public final class ActiveProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?

    public init() {}

    public func set(_ process: Process?) {
        lock.lock()
        self.process = process
        lock.unlock()
    }

    public var processIdentifier: Int32? {
        lock.lock()
        let pid = process?.processIdentifier
        lock.unlock()
        return pid
    }

    public func terminate() {
        lock.lock()
        let process = self.process
        lock.unlock()
        process?.terminate()
    }

    public func terminateThenKill(after delayNanoseconds: UInt64 = 1_000_000_000) {
        lock.lock()
        let process = self.process
        lock.unlock()

        guard let process else { return }
        process.terminate()

        Task.detached {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }
}

public struct ProcessActivity: Sendable {
    public let processIdentifier: Int32?
    public let stderrTail: String
    public let lastActivityAt: Date

    public init(processIdentifier: Int32?, stderrTail: String, lastActivityAt: Date) {
        self.processIdentifier = processIdentifier
        self.stderrTail = stderrTail
        self.lastActivityAt = lastActivityAt
    }
}

final class ProcessPipeCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var textBuffer = ""
    private var tailData = Data()
    private let tailLimit: Int
    private let lineHandler: (@Sendable (String) -> Void)?
    private let activityHandler: (@Sendable (String) -> Void)?

    init(
        tailLimit: Int = 65_536,
        lineHandler: (@Sendable (String) -> Void)? = nil,
        activityHandler: (@Sendable (String) -> Void)? = nil
    ) {
        self.tailLimit = tailLimit
        self.lineHandler = lineHandler
        self.activityHandler = activityHandler
    }

    func append(_ newData: Data) {
        guard !newData.isEmpty else { return }

        var lines: [String] = []
        let text = String(data: newData, encoding: .utf8) ?? ""

        lock.lock()
        data.append(newData)
        tailData.append(newData)
        if tailData.count > tailLimit {
            tailData.removeFirst(tailData.count - tailLimit)
        }

        textBuffer += text
        while let newlineRange = textBuffer.range(of: "\n") {
            lines.append(String(textBuffer[..<newlineRange.lowerBound]))
            textBuffer.removeSubrange(..<newlineRange.upperBound)
        }
        lock.unlock()

        activityHandler?(tailText)
        for line in lines {
            lineHandler?(line)
        }
    }

    func finishUnterminatedLine() {
        var finalLine: String?

        lock.lock()
        if !textBuffer.isEmpty {
            finalLine = textBuffer
            textBuffer = ""
        }
        lock.unlock()

        if let finalLine {
            lineHandler?(finalLine)
        }
    }

    var snapshot: Data {
        lock.lock()
        let copy = data
        lock.unlock()
        return copy
    }

    var tailText: String {
        lock.lock()
        let copy = tailData
        lock.unlock()
        return String(data: copy, encoding: .utf8) ?? ""
    }
}

final class ProcessCompletionCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutEOF = false
    private var stderrEOF = false
    private var terminated = false
    private var exitCode: Int32 = -1
    private var resumed = false
    private let stdoutCollector: ProcessPipeCollector
    private let stderrCollector: ProcessPipeCollector
    private let activeProcess: ActiveProcess?
    private let continuation: CheckedContinuation<ProcessResult, Error>

    init(
        stdoutCollector: ProcessPipeCollector,
        stderrCollector: ProcessPipeCollector,
        activeProcess: ActiveProcess?,
        continuation: CheckedContinuation<ProcessResult, Error>
    ) {
        self.stdoutCollector = stdoutCollector
        self.stderrCollector = stderrCollector
        self.activeProcess = activeProcess
        self.continuation = continuation
    }

    func markStdoutEOF() {
        stdoutCollector.finishUnterminatedLine()
        update { stdoutEOF = true }
    }

    func markStderrEOF() {
        stderrCollector.finishUnterminatedLine()
        update { stderrEOF = true }
    }

    func markTerminated(exitCode: Int32) {
        update {
            self.exitCode = exitCode
            terminated = true
            stdoutEOF = true
            stderrEOF = true
        }
    }

    func fail(_ error: Error) {
        lock.lock()
        guard !resumed else {
            lock.unlock()
            return
        }
        resumed = true
        lock.unlock()

        activeProcess?.set(nil)
        continuation.resume(throwing: error)
    }

    private func update(_ changes: () -> Void) {
        lock.lock()
        changes()
        let shouldResume = terminated && stdoutEOF && stderrEOF && !resumed
        if shouldResume {
            resumed = true
        }
        let result = ProcessResult(exitCode: exitCode, stdout: stdoutCollector.snapshot, stderr: stderrCollector.snapshot)
        lock.unlock()

        if shouldResume {
            activeProcess?.set(nil)
            continuation.resume(returning: result)
        }
    }
}

public struct ProcessRunner: Sendable {
    public init() {}

    public static func nullStandardInput() -> FileHandle {
        FileHandle(forReadingAtPath: "/dev/null") ?? FileHandle.standardInput
    }

    public func run(
        executablePath: String,
        arguments: [String],
        activeProcess: ActiveProcess? = nil,
        stdoutLineHandler: (@Sendable (String) -> Void)? = nil,
        activityHandler: (@Sendable (ProcessActivity) -> Void)? = nil
    ) async throws -> ProcessResult {
        let activeProcess = activeProcess

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let process = Process()
                let stdout = Pipe()
                let stderr = Pipe()
                let lastActivity = LockedValue(Date())
                let pid = LockedValue<Int32?>(nil)

                let stdoutCollector = ProcessPipeCollector(lineHandler: stdoutLineHandler) { _ in
                    lastActivity.set(Date())
                    activityHandler?(ProcessActivity(processIdentifier: pid.value, stderrTail: "", lastActivityAt: lastActivity.value))
                }
                let stderrCollector = ProcessPipeCollector { stderrTail in
                    lastActivity.set(Date())
                    activityHandler?(ProcessActivity(processIdentifier: pid.value, stderrTail: stderrTail, lastActivityAt: lastActivity.value))
                }
                let coordinator = ProcessCompletionCoordinator(
                    stdoutCollector: stdoutCollector,
                    stderrCollector: stderrCollector,
                    activeProcess: activeProcess,
                    continuation: continuation
                )

                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = arguments
                process.standardInput = Self.nullStandardInput()
                process.standardOutput = stdout
                process.standardError = stderr

                stdout.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty {
                        handle.readabilityHandler = nil
                        coordinator.markStdoutEOF()
                    } else {
                        stdoutCollector.append(data)
                    }
                }

                stderr.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty {
                        handle.readabilityHandler = nil
                        coordinator.markStderrEOF()
                    } else {
                        stderrCollector.append(data)
                    }
                }

                process.terminationHandler = { terminatedProcess in
                    stdout.fileHandleForReading.readabilityHandler = nil
                    stderr.fileHandleForReading.readabilityHandler = nil
                    stdoutCollector.finishUnterminatedLine()
                    stderrCollector.finishUnterminatedLine()
                    coordinator.markTerminated(exitCode: terminatedProcess.terminationStatus)
                }

                do {
                    try process.run()
                    activeProcess?.set(process)
                    pid.set(process.processIdentifier)
                    lastActivity.set(Date())
                    activityHandler?(ProcessActivity(processIdentifier: process.processIdentifier, stderrTail: "", lastActivityAt: lastActivity.value))
                } catch {
                    stdout.fileHandleForReading.readabilityHandler = nil
                    stderr.fileHandleForReading.readabilityHandler = nil
                    coordinator.fail(ProcessExecutionError.launchFailed(error.localizedDescription))
                }
            }
        } onCancel: {
            activeProcess?.terminateThenKill()
        }
    }
}

final class LockedValue<Value>: @unchecked Sendable {
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
}

public struct FFmpegRunner {
    public static let defaultPath = "/opt/homebrew/bin/ffmpeg"

    public init() {}

    public func versionArguments() -> [String] {
        ["-nostdin", "-version"]
    }

    public func version(ffmpegPath: String) async throws -> String {
        let result = try await ProcessRunner().run(executablePath: ffmpegPath, arguments: versionArguments())
        guard result.exitCode == 0 else {
            throw ProcessExecutionError.nonZeroExit(code: result.exitCode, stderr: result.stderrText)
        }
        return result.stdoutText.components(separatedBy: .newlines).first ?? "Version detected"
    }
}
