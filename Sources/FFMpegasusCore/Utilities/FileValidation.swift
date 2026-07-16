import Foundation

enum FileValidation {
    static let supportedExtensions = ["mp4", "mov", "mkv", "m4v", "avi", "webm"]

    static func isLikelySupportedVideo(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }
}
