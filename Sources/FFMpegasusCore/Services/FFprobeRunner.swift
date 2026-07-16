import Foundation

public struct FFprobeRunner {
    public static let defaultPath = "/opt/homebrew/bin/ffprobe"

    public init() {}

    public func metadataArguments(inputURL: URL) -> [String] {
        [
            "-v", "error",
            "-print_format", "json",
            "-show_format",
            "-show_streams",
            inputURL.path
        ]
    }

    public func versionArguments() -> [String] {
        ["-version"]
    }

    public func loadMetadata(ffprobePath: String, inputURL: URL) async throws -> VideoMetadata {
        let result = try await ProcessRunner().run(executablePath: ffprobePath, arguments: metadataArguments(inputURL: inputURL))
        guard result.exitCode == 0 else {
            throw ProcessExecutionError.nonZeroExit(code: result.exitCode, stderr: result.stderrText)
        }
        let response = try JSONDecoder().decode(FFprobeResponse.self, from: result.stdout)
        return response.videoMetadata()
    }

    public func version(ffprobePath: String) async throws -> String {
        let result = try await ProcessRunner().run(executablePath: ffprobePath, arguments: versionArguments())
        guard result.exitCode == 0 else {
            throw ProcessExecutionError.nonZeroExit(code: result.exitCode, stderr: result.stderrText)
        }
        return result.stdoutText.components(separatedBy: .newlines).first ?? "Version detected"
    }
}
