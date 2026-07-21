import FFMpegasusCore
import SwiftUI
import UniformTypeIdentifiers

struct FrameExportEditingSection: View {
    let inputURL: URL?
    let duration: TimeInterval
    let metadata: VideoMetadata?
    @ObservedObject var operationState: EditingOperationState
    @Binding var validationMessage: String?
    let currentPlaybackTime: () -> TimeInterval
    let canExportCurrentFrame: Bool
    let onExportFrame: (FrameExportRequest) -> Void

    @AppStorage("frameImageFormat") private var frameImageFormatRaw = FrameImageFormat.png.rawValue
    @AppStorage("frameJPEGQualityPreset") private var frameJPEGQualityPresetRaw = JPEGQualityPreset.balanced.rawValue
    @AppStorage("frameCustomJPEGQuality") private var frameCustomJPEGQuality = 4

    private var controlsDisabled: Bool {
        inputURL == nil || operationState.isRunning
    }

    private var frameImageFormat: FrameImageFormat {
        get { FrameImageFormat(rawValue: frameImageFormatRaw) ?? .png }
        nonmutating set { frameImageFormatRaw = newValue.rawValue }
    }

    private var frameJPEGQualityPreset: JPEGQualityPreset {
        get { JPEGQualityPreset(rawValue: frameJPEGQualityPresetRaw) ?? .balanced }
        nonmutating set { frameJPEGQualityPresetRaw = newValue.rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Export Current Frame")
                .font(.headline)

            Text("Current position: \(FrameExportTimestamp.displayTime(currentPlaybackTimeForDisplay))")
                .font(.callout)
                .textSelection(.enabled)

            Picker("Format", selection: Binding(get: { frameImageFormat }, set: { frameImageFormat = $0 })) {
                ForEach(FrameImageFormat.allCases) { format in
                    Text(format.title).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .disabled(controlsDisabled)

            JPEGQualityControls(
                isVisible: frameImageFormat == .jpeg,
                controlsDisabled: controlsDisabled,
                preset: Binding(get: { frameJPEGQualityPreset }, set: { frameJPEGQualityPreset = $0 }),
                customQuality: $frameCustomJPEGQuality
            )

            Text(frameExportSummary)
                .font(.callout)
                .textSelection(.enabled)

            Button {
                chooseFrameOutputAndStart()
            } label: {
                Label(operationState.isRunning ? "Exporting Frame..." : "Export Current Frame", systemImage: "photo")
            }
            .disabled(frameExportDisabled)
        }
    }

    private var currentPlaybackTimeForDisplay: TimeInterval {
        (try? FrameExportTimestamp.clamped(currentPlaybackTime(), duration: duration)) ?? 0
    }

    private var frameExportDisabled: Bool {
        controlsDisabled || metadata?.videoCodec == nil || frameJPEGQuality == nil || !canExportCurrentFrame || !(currentPlaybackTime().isFinite)
    }

    private var frameExportSummary: String {
        let dimensions = frameExpectedDimensions.map { "\($0.width)x\($0.height)" } ?? "unavailable"
        var lines = [
            "Frame time: \(FrameExportTimestamp.displayTime(currentPlaybackTimeForDisplay))",
            "Format: \(frameImageFormat.title)"
        ]
        if frameImageFormat == .jpeg {
            lines.append("Quality: \(frameJPEGQualityPreset.title)")
        }
        lines.append("Expected dimensions: \(dimensions)")
        return lines.joined(separator: "\n")
    }

    private var frameExpectedDimensions: VideoDimensions? {
        guard let width = metadata?.width, let height = metadata?.height else { return nil }
        let rawRotation = (metadata?.rotationDegrees ?? 0) % 360
        let rotation = rawRotation >= 0 ? rawRotation : rawRotation + 360
        if rotation == 90 || rotation == 270 {
            return VideoDimensions(width: height, height: width)
        }
        return VideoDimensions(width: width, height: height)
    }

    private var frameJPEGQuality: JPEGQuality? {
        guard frameImageFormat == .jpeg else { return nil }
        let value = frameJPEGQualityPreset.qualityValue ?? frameCustomJPEGQuality
        return try? JPEGQuality(ffmpegValue: value)
    }

    private func chooseFrameOutputAndStart() {
        guard let inputURL else { return }
        let capturedTime: TimeInterval
        do {
            capturedTime = try FrameExportTimestamp.clamped(currentPlaybackTime(), duration: duration)
        } catch {
            validationMessage = error.localizedDescription
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: frameImageFormat.fileExtension) ?? (frameImageFormat == .png ? .png : .jpeg)]
        panel.nameFieldStringValue = OutputFilename.frameName(for: inputURL, timestamp: capturedTime, format: frameImageFormat)
        guard panel.runModal() == .OK, let outputURL = panel.url else { return }

        guard let request = frameExportRequest(outputURL: outputURL, timestamp: capturedTime) else {
            validationMessage = "Frame export settings are invalid."
            return
        }
        do {
            try request.validate()
            validationMessage = nil
            onExportFrame(request)
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func frameExportRequest(outputURL: URL, timestamp: TimeInterval) -> FrameExportRequest? {
        guard let inputURL,
              let width = metadata?.width,
              let height = metadata?.height else {
            return nil
        }
        let quality = frameImageFormat == .jpeg ? frameJPEGQuality : nil
        let request = FrameExportRequest(
            inputURL: inputURL,
            outputURL: outputURL,
            timestampSeconds: timestamp,
            sourceDuration: duration,
            sourceDimensions: VideoDimensions(width: width, height: height),
            sourceRotationDegrees: metadata?.rotationDegrees,
            hasVideoStream: metadata?.videoCodec != nil,
            format: frameImageFormat,
            jpegQuality: quality
        )
        guard (try? request.validate()) != nil else { return nil }
        return request
    }
}
