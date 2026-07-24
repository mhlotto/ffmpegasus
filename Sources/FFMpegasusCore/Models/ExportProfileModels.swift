import Foundation

public enum ExportProfile: String, CaseIterable, Identifiable, Codable, Sendable {
    case mp4H264
    case mp4HEVC
    case webmVP9
    case movProRes422

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .mp4H264: "MP4 - H.264"
        case .mp4HEVC: "MP4 - HEVC"
        case .webmVP9: "WebM - VP9"
        case .movProRes422: "MOV - ProRes 422"
        }
    }

    public var description: String {
        switch self {
        case .mp4H264:
            "Best compatibility with common players and devices."
        case .mp4HEVC:
            "Smaller MP4 files at comparable visual quality when HEVC is supported."
        case .webmVP9:
            "Modern web delivery with VP9 video and Opus audio."
        case .movProRes422:
            "High-quality editing format. Produces very large files."
        }
    }

    public var fileExtension: String {
        switch self {
        case .mp4H264, .mp4HEVC: "mp4"
        case .webmVP9: "webm"
        case .movProRes422: "mov"
        }
    }

    public var requiredVideoEncoder: String {
        switch self {
        case .mp4H264: "libx264"
        case .mp4HEVC: "libx265"
        case .webmVP9: "libvpx-vp9"
        case .movProRes422: "prores_ks"
        }
    }

    public var requiredAudioEncoder: String {
        switch self {
        case .mp4H264, .mp4HEVC: "aac"
        case .webmVP9: "libopus"
        case .movProRes422: "pcm_s16le"
        }
    }

    public var expectedVideoCodecs: Set<String> {
        switch self {
        case .mp4H264: ["h264"]
        case .mp4HEVC: ["hevc"]
        case .webmVP9: ["vp9"]
        case .movProRes422: ["prores"]
        }
    }

    public var expectedAudioCodecs: Set<String> {
        switch self {
        case .mp4H264, .mp4HEVC: ["aac"]
        case .webmVP9: ["opus"]
        case .movProRes422: ["pcm_s16le"]
        }
    }

    public var expectedFormatNames: Set<String> {
        switch self {
        case .mp4H264, .mp4HEVC:
            ["mov,mp4,m4a,3gp,3g2,mj2"]
        case .webmVP9:
            ["matroska,webm"]
        case .movProRes422:
            ["mov,mp4,m4a,3gp,3g2,mj2"]
        }
    }

    public var isLargeOutputProfile: Bool {
        self == .movProRes422
    }

    public var usesCRFQuality: Bool {
        self != .movProRes422
    }

    public var forcesReencode: Bool {
        self != .mp4H264
    }

    public func qualitySettings(from base: CompressionQualitySettings) -> ExportProfileQualitySettings {
        switch self {
        case .mp4H264:
            ExportProfileQualitySettings(crf: base.crf, preset: base.preset.rawValue)
        case .mp4HEVC:
            ExportProfileQualitySettings(crf: hevcCRF(for: base.crf), preset: base.preset.rawValue)
        case .webmVP9:
            ExportProfileQualitySettings(crf: vp9CRF(for: base.crf), preset: webmCpuUsed(for: base.preset.rawValue))
        case .movProRes422:
            ExportProfileQualitySettings(crf: nil, preset: "profile 2")
        }
    }

    public func videoArguments(quality: CompressionQualitySettings) -> [String] {
        let profileQuality = qualitySettings(from: quality)
        switch self {
        case .mp4H264:
            return [
                "-c:v", "libx264",
                "-preset", quality.preset.rawValue,
                "-crf", String(quality.crf),
                "-pix_fmt", "yuv420p"
            ]
        case .mp4HEVC:
            return [
                "-c:v", "libx265",
                "-preset", profileQuality.preset,
                "-crf", String(profileQuality.crf ?? 28),
                "-pix_fmt", "yuv420p",
                "-tag:v", "hvc1"
            ]
        case .webmVP9:
            return [
                "-c:v", "libvpx-vp9",
                "-crf", String(profileQuality.crf ?? 32),
                "-b:v", "0",
                "-deadline", "good",
                "-cpu-used", profileQuality.preset,
                "-pix_fmt", "yuv420p"
            ]
        case .movProRes422:
            return [
                "-c:v", "prores_ks",
                "-profile:v", "2",
                "-pix_fmt", "yuv422p10le"
            ]
        }
    }

    public func audioArguments() -> [String] {
        switch self {
        case .mp4H264, .mp4HEVC:
            ["-c:a", "aac", "-b:a", "128k"]
        case .webmVP9:
            ["-c:a", "libopus", "-b:a", "128k"]
        case .movProRes422:
            ["-c:a", "pcm_s16le"]
        }
    }

    public var containerArguments: [String] {
        switch self {
        case .mp4H264, .mp4HEVC:
            ["-movflags", "+faststart"]
        case .webmVP9, .movProRes422:
            []
        }
    }

    private func hevcCRF(for h264CRF: Int) -> Int {
        switch h264CRF {
        case ...20: 24
        case 21...24: 28
        default: 32
        }
    }

    private func vp9CRF(for h264CRF: Int) -> Int {
        switch h264CRF {
        case ...20: 28
        case 21...24: 32
        default: 36
        }
    }

    private func webmCpuUsed(for preset: String) -> String {
        switch preset {
        case "slow", "slower": "2"
        case "ultrafast", "veryfast": "4"
        default: "3"
        }
    }
}

public struct ExportProfileQualitySettings: Equatable, Sendable {
    public let crf: Int?
    public let preset: String
}

public struct ExportProfileCapabilities: Equatable, Sendable {
    public let encoders: Set<String>

    public init(encoders: Set<String>) {
        self.encoders = encoders
    }

    public func support(for profile: ExportProfile) -> ExportProfileSupport {
        var missing: [String] = []
        if !encoders.contains(profile.requiredVideoEncoder) {
            missing.append(profile.requiredVideoEncoder)
        }
        if !encoders.contains(profile.requiredAudioEncoder) {
            missing.append(profile.requiredAudioEncoder)
        }
        return ExportProfileSupport(profile: profile, missingEncoders: missing)
    }
}

public struct ExportProfileSupport: Equatable, Sendable {
    public let profile: ExportProfile
    public let missingEncoders: [String]

    public var isSupported: Bool {
        missingEncoders.isEmpty
    }

    public var explanation: String? {
        guard !isSupported else { return nil }
        return "Missing encoder\(missingEncoders.count == 1 ? "" : "s"): \(missingEncoders.joined(separator: ", "))"
    }
}

public enum ExportProfileValidationError: LocalizedError, Equatable, Sendable {
    case missingEncoder(profile: ExportProfile, encoder: String)
    case wrongVideoCodec(expected: ExportProfile, actual: String?)
    case wrongAudioCodec(expected: ExportProfile, actual: String?)
    case wrongContainer(expected: ExportProfile, actual: String?)
    case wrongExtension(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .missingEncoder(let profile, let encoder):
            "\(profile.displayName) requires an FFmpeg build with the \(encoder) encoder."
        case .wrongVideoCodec(let expected, let actual):
            "Output video codec does not match \(expected.displayName). Detected codec: \(actual ?? "unknown")."
        case .wrongAudioCodec(let expected, let actual):
            "Output audio codec does not match \(expected.displayName). Detected codec: \(actual ?? "unknown")."
        case .wrongContainer(let expected, let actual):
            "Output container does not match \(expected.displayName). Detected format: \(actual ?? "unknown")."
        case .wrongExtension(let expected, let actual):
            "Output filename must use .\(expected), not .\(actual)."
        }
    }
}

extension OutputFilename {
    public static func applying(profile: ExportProfile, to suggestedName: String) -> String {
        let url = URL(fileURLWithPath: suggestedName)
        return url.deletingPathExtension().lastPathComponent + "." + profile.fileExtension
    }
}
