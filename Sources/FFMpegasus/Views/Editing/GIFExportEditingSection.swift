import FFMpegasusCore
import SwiftUI

struct GIFExportEditingSection: View {
    let inputURL: URL?
    let duration: TimeInterval
    let metadata: VideoMetadata?
    @ObservedObject var operationState: EditingOperationState
    @Binding var validationMessage: String?
    let testAutomationGIFOutputURL: URL?
    let onExportGIF: (GIFExportRequest) -> Void

    @AppStorage("gifFrameRatePreset") private var frameRatePresetRaw = GIFFrameRatePreset.fps10.rawValue
    @AppStorage("gifCustomFrameRate") private var customFrameRate = "10"
    @AppStorage("gifSizePreset") private var sizePresetRaw = GIFSizePreset.wide480.rawValue
    @AppStorage("gifCustomWidth") private var customWidth = "480"
    @AppStorage("gifQualityPreset") private var qualityPresetRaw = GIFQualityPreset.balanced.rawValue
    @AppStorage("gifLoopMode") private var loopModeRaw = GIFLoopMode.forever.rawValue
    @AppStorage("gifRangeMode") private var rangeModeRaw = FrameExportRangeMode.entireVideo.rawValue
    @State private var startSeconds = "0"
    @State private var endSeconds = ""

    private var controlsDisabled: Bool {
        inputURL == nil || operationState.isRunning
    }

    private var frameRatePreset: GIFFrameRatePreset {
        get { GIFFrameRatePreset(rawValue: frameRatePresetRaw) ?? .fps10 }
        nonmutating set { frameRatePresetRaw = newValue.rawValue }
    }

    private var sizePreset: GIFSizePreset {
        get { GIFSizePreset(rawValue: sizePresetRaw) ?? .wide480 }
        nonmutating set { sizePresetRaw = newValue.rawValue }
    }

    private var qualityPreset: GIFQualityPreset {
        get { GIFQualityPreset(rawValue: qualityPresetRaw) ?? .balanced }
        nonmutating set { qualityPresetRaw = newValue.rawValue }
    }

    private var loopMode: GIFLoopMode {
        get { GIFLoopMode(rawValue: loopModeRaw) ?? .forever }
        nonmutating set { loopModeRaw = newValue.rawValue }
    }

    private var rangeMode: FrameExportRangeMode {
        get { FrameExportRangeMode(rawValue: rangeModeRaw) ?? .entireVideo }
        nonmutating set { rangeModeRaw = newValue.rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Export GIF")
                .font(.headline)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("editing.gifExport")

            Picker("Range", selection: Binding(get: { rangeMode }, set: { rangeMode = $0 })) {
                ForEach(FrameExportRangeMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(controlsDisabled)

            if rangeMode == .custom {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("Start time")
                        TextField("Start seconds", text: $startSeconds)
                            .textFieldStyle(.roundedBorder)
                            .disabled(controlsDisabled)
                        Text(FrameExportTimestamp.displayTime(Double(startSeconds) ?? 0))
                            .foregroundStyle(.secondary)
                    }
                    GridRow {
                        Text("End time")
                        TextField("End seconds", text: $endSeconds)
                            .textFieldStyle(.roundedBorder)
                            .disabled(controlsDisabled)
                        Text(FrameExportTimestamp.displayTime(Double(endSeconds) ?? duration))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Picker("Frame rate", selection: Binding(get: { frameRatePreset }, set: { frameRatePreset = $0 })) {
                ForEach(GIFFrameRatePreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .disabled(controlsDisabled)

            if frameRatePreset == .custom {
                TextField("Custom frames per second", text: $customFrameRate)
                    .textFieldStyle(.roundedBorder)
                    .disabled(controlsDisabled)
            }

            Text("Higher frame rates produce smoother motion and larger files.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Picker("Size", selection: Binding(get: { sizePreset }, set: { sizePreset = $0 })) {
                ForEach(GIFSizePreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .disabled(controlsDisabled)

            if sizePreset == .custom {
                TextField("Custom width", text: $customWidth)
                    .textFieldStyle(.roundedBorder)
                    .disabled(controlsDisabled)
            }

            Picker("Quality", selection: Binding(get: { qualityPreset }, set: { qualityPreset = $0 })) {
                ForEach(GIFQualityPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .disabled(controlsDisabled)

            Picker("Loop", selection: Binding(get: { loopMode }, set: { loopMode = $0 })) {
                ForEach(GIFLoopMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(controlsDisabled)

            Text(gifSummary)
                .font(.callout)
                .textSelection(.enabled)
                .accessibilityIdentifier("gifExport.summary")

            Button {
                chooseGIFOutputAndStart()
            } label: {
                Label(operationState.isRunning ? "Exporting GIF..." : "Export GIF", systemImage: "film.stack")
            }
            .disabled(gifExportDisabled)
            .accessibilityIdentifier("gifExport.exportButton")
        }
        .onChange(of: inputURL) { _, _ in
            startSeconds = "0"
            endSeconds = ""
        }
    }

    private var gifExportDisabled: Bool {
        controlsDisabled || metadata?.videoCodec == nil || gifRequest(outputURL: URL(fileURLWithPath: "/tmp/output.gif")) == nil
    }

    private var gifSummary: String {
        guard let request = gifRequest(outputURL: URL(fileURLWithPath: "/tmp/output.gif")) else {
            return "Select valid GIF export settings."
        }
        let dimensions = (try? request.outputDimensions()).map { "\($0.width)x\($0.height)" } ?? "unavailable"
        let estimatedFrames = (try? request.estimatedFrameCount()).map(String.init) ?? "unavailable"
        var lines = [
            "Range: \(FrameExportTimestamp.displayTime(request.range.startSeconds)) to \(FrameExportTimestamp.displayTime(request.range.endSeconds))",
            String(format: "Duration: %.3f seconds", request.range.duration),
            "Frame rate: \(FrameExportTimestamp.compactSeconds(request.frameRate.framesPerSecond)) fps",
            "Estimated frames: \(estimatedFrames)",
            "Size: \(dimensions)",
            "Quality: \(request.quality.title)",
            "Loop: \(request.loopMode == .forever ? "Forever" : "Play Once")"
        ]
        if request.likelyLargeOutput {
            lines.append("Large GIF warning: these settings may create a very large file.")
        }
        return lines.joined(separator: "\n")
    }

    private func chooseGIFOutputAndStart() {
        if let testAutomationGIFOutputURL {
            startGIFExport(outputURL: testAutomationGIFOutputURL)
            return
        }

        guard let inputURL, let request = gifRequest(outputURL: URL(fileURLWithPath: "/tmp/output.gif")) else {
            validationMessage = "GIF export settings are invalid."
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.gif]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = OutputFilename.gifName(for: inputURL, range: request.range, sourceDuration: duration)
        guard panel.runModal() == .OK, let outputURL = panel.url else { return }
        startGIFExport(outputURL: outputURL)
    }

    private func startGIFExport(outputURL: URL) {
        guard let request = gifRequest(outputURL: outputURL) else {
            validationMessage = "GIF export settings are invalid."
            return
        }

        do {
            try request.validate()
            validationMessage = nil
            onExportGIF(request)
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func gifRequest(outputURL: URL) -> GIFExportRequest? {
        guard let inputURL,
              let width = metadata?.width,
              let height = metadata?.height else {
            return nil
        }
        let frameRate: GIFFrameRate
        do {
            if let presetFPS = frameRatePreset.framesPerSecond {
                frameRate = try GIFFrameRate(framesPerSecond: presetFPS)
            } else if let parsed = GIFFrameRate.parse(customFrameRate) {
                frameRate = parsed
            } else {
                return nil
            }
        } catch {
            return nil
        }

        let range: FrameExportRange
        do {
            if rangeMode == .entireVideo {
                range = try FrameExportRange.entireVideo(duration: duration)
            } else {
                guard let start = Double(startSeconds.trimmingCharacters(in: .whitespacesAndNewlines)),
                      let end = Double(endSeconds.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    return nil
                }
                range = try FrameExportRange(startSeconds: start, endSeconds: end, sourceDuration: duration)
            }
        } catch {
            return nil
        }

        let parsedCustomWidth = sizePreset == .custom ? GIFWidth.parse(customWidth) : nil
        if sizePreset == .custom, parsedCustomWidth == nil {
            return nil
        }

        let request = GIFExportRequest(
            inputURL: inputURL,
            outputURL: outputURL,
            sourceDuration: duration,
            sourceDimensions: VideoDimensions(width: width, height: height),
            sourceRotationDegrees: metadata?.rotationDegrees,
            hasVideoStream: metadata?.videoCodec != nil,
            range: range,
            frameRate: frameRate,
            sizePreset: sizePreset,
            customWidth: parsedCustomWidth,
            quality: qualityPreset,
            loopMode: loopMode
        )
        guard (try? request.validate()) != nil else { return nil }
        return request
    }
}
