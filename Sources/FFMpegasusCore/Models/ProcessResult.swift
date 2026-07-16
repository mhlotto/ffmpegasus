import Foundation

public struct ProcessResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: Data
    public let stderr: Data

    public init(exitCode: Int32, stdout: Data = Data(), stderr: Data = Data()) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }

    public var stdoutText: String {
        String(data: stdout, encoding: .utf8) ?? ""
    }

    public var stderrText: String {
        String(data: stderr, encoding: .utf8) ?? ""
    }
}

public enum ProcessExecutionError: LocalizedError, Sendable {
    case launchFailed(String)
    case nonZeroExit(code: Int32, stderr: String)
    case cancelled(stderr: String)

    public var errorDescription: String? {
        switch self {
        case .launchFailed(let message):
            "Could not start process: \(message)"
        case .nonZeroExit(let code, let stderr):
            "Process exited with code \(code). \(stderr)"
        case .cancelled:
            "Operation cancelled."
        }
    }
}
