import Foundation

struct EditingPreflightValidator {
    let fileSystem: any EditingFileSystemChecking

    func validate(ffmpegPath: String, request: EditingRequest) throws {
        _ = try request.trimPlan()
        try validate(ffmpegPath: ffmpegPath, inputURL: request.inputURL, outputURL: request.outputURL)
    }

    func validate(ffmpegPath: String, inputURL: URL, outputURL: URL) throws {
        if inputURL.standardizedFileURL == outputURL.standardizedFileURL {
            throw VideoEditingError.outputMatchesInput
        }

        let outputDirectory = outputURL.deletingLastPathComponent()
        guard fileSystem.directoryExists(at: outputDirectory) else {
            throw VideoEditingError.missingOutputDirectory(outputDirectory.path)
        }

        guard fileSystem.isWritableDirectory(at: outputDirectory) else {
            throw VideoEditingError.outputDirectoryNotWritable(outputDirectory.path)
        }

        try validateFFmpegExecutable(ffmpegPath)
    }

    func validateDirectory(ffmpegPath: String, inputURL: URL, outputDirectoryURL: URL) throws {
        guard fileSystem.fileExists(at: inputURL) else {
            throw VideoEditingError.inputMissing(inputURL.path)
        }
        guard fileSystem.directoryExists(at: outputDirectoryURL) else {
            throw VideoEditingError.missingOutputDirectory(outputDirectoryURL.path)
        }
        guard fileSystem.isWritableDirectory(at: outputDirectoryURL) else {
            throw VideoEditingError.outputDirectoryNotWritable(outputDirectoryURL.path)
        }
        try validateFFmpegExecutable(ffmpegPath)
    }

    private func validateFFmpegExecutable(_ ffmpegPath: String) throws {
        let ffmpegURL = URL(fileURLWithPath: ffmpegPath)
        guard fileSystem.fileExists(at: ffmpegURL) else {
            throw VideoEditingError.missingFFmpegExecutable(ffmpegPath)
        }
        guard fileSystem.isExecutableFile(at: ffmpegURL) else {
            throw VideoEditingError.ffmpegNotExecutable(ffmpegPath)
        }
    }
}

struct EditingOutputFileValidator {
    let fileSystem: any EditingFileSystemChecking

    func validateSuccessfulOutput(at outputURL: URL) throws -> UInt64 {
        guard fileSystem.fileExists(at: outputURL) else {
            throw VideoEditingError.outputMissing(outputURL.path)
        }

        guard let size = fileSystem.fileSize(at: outputURL), size > 0 else {
            throw VideoEditingError.outputEmpty(outputURL.path)
        }

        return size
    }
}
