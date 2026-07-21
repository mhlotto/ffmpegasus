import Foundation

public protocol CompressionEncoderChecking: Sendable {
    func supportsLibx264(ffmpegPath: String) async throws -> Bool
}

public final class FFmpegCompressionEncoderChecker: CompressionEncoderChecking, @unchecked Sendable {
    private let libx264Support = LockedValue<[String: Bool]>([:])

    public init() {}

    public func supportsLibx264(ffmpegPath: String) async throws -> Bool {
        if libx264Support.value[ffmpegPath] == true {
            return true
        }
        let encoders = try await FFmpegRunner().encoders(ffmpegPath: ffmpegPath)
        let supported = encoders.contains("libx264")
        libx264Support.update { $0[ffmpegPath] = supported }
        return supported
    }
}

public struct LocalEditingFileSystem: EditingFileSystemChecking {
    public init() {}

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    public func isExecutableFile(at url: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: url.path)
    }

    public func isWritableDirectory(at url: URL) -> Bool {
        FileManager.default.isWritableFile(atPath: url.path)
    }

    public func fileSize(at url: URL) -> UInt64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return nil
        }
        return size.uint64Value
    }

    public func contentsOfDirectory(at url: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
    }

    public func removeFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set(_ newValue: Bool) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    var isSet: Bool {
        lock.lock()
        let current = value
        lock.unlock()
        return current
    }
}

public final class FFmpegEditingProcessExecutor: EditingProcessExecuting, @unchecked Sendable {
    private let activeProcess = ActiveProcess()
    private let parser = FFmpegProgressParser()
    private let processRunner = ProcessRunner()

    public init() {}

    public func cancel() {
        activeProcess.terminate()
    }

    public func run(
        command: EditingCommand,
        totalDuration: TimeInterval,
        onStarted: @escaping @Sendable () -> Void,
        onProgress: @escaping @Sendable (Double) -> Void,
        onActivity: @escaping @Sendable (ProcessActivity) -> Void
    ) async throws -> ProcessResult {
        let parser = parser
        let didStart = LockedValue(false)
        return try await processRunner.run(
            executablePath: command.executablePath,
            arguments: command.arguments,
            activeProcess: activeProcess,
            stdoutLineHandler: { line in
                guard let parsed = parser.parse(line), let outTime = parsed.outTime, totalDuration > 0 else { return }
                onProgress(min(max(outTime / totalDuration, 0), 1))
            },
            activityHandler: { activity in
                if activity.processIdentifier != nil, !didStart.value {
                    didStart.set(true)
                    onStarted()
                }
                onActivity(activity)
            }
        )
    }
}
