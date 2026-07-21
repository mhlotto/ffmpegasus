import FFMpegasusCore
import SwiftUI

struct IntervalFrameExportEditingSection: View {
    let inputURL: URL?
    let duration: TimeInterval
    let metadata: VideoMetadata?
    @ObservedObject var operationState: EditingOperationState
    @Binding var validationMessage: String?
    let onExportFramesAtIntervals: (IntervalFrameExportRequest) -> Void

    @AppStorage("frameImageFormat") private var frameImageFormatRaw = FrameImageFormat.png.rawValue
    @AppStorage("frameJPEGQualityPreset") private var frameJPEGQualityPresetRaw = JPEGQualityPreset.balanced.rawValue
    @AppStorage("frameCustomJPEGQuality") private var frameCustomJPEGQuality = 4
    @AppStorage("intervalFramePreset") private var intervalFramePresetRaw = FrameIntervalPreset.every5.rawValue
    @AppStorage("intervalFrameCustomSeconds") private var intervalFrameCustomSeconds = "5"
    @AppStorage("intervalFrameRangeMode") private var intervalFrameRangeModeRaw = FrameExportRangeMode.entireVideo.rawValue
    @State private var intervalFrameStartSeconds = "0"
    @State private var intervalFrameEndSeconds = ""

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

    private var intervalFramePreset: FrameIntervalPreset {
        get { FrameIntervalPreset(rawValue: intervalFramePresetRaw) ?? .every5 }
        nonmutating set { intervalFramePresetRaw = newValue.rawValue }
    }

    private var intervalFrameRangeMode: FrameExportRangeMode {
        get { FrameExportRangeMode(rawValue: intervalFrameRangeModeRaw) ?? .entireVideo }
        nonmutating set { intervalFrameRangeModeRaw = newValue.rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Export Frames at Intervals")
                .font(.headline)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("editing.intervalFrameExport")

            Picker("Interval", selection: Binding(get: { intervalFramePreset }, set: { intervalFramePreset = $0 })) {
                ForEach(FrameIntervalPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .disabled(controlsDisabled)

            if intervalFramePreset == .custom {
                TextField("Custom interval seconds", text: $intervalFrameCustomSeconds)
                    .textFieldStyle(.roundedBorder)
                    .disabled(controlsDisabled)
            }

            Text("A frame will be exported at each interval throughout the video.\nSmaller intervals create more images.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Picker("Range", selection: Binding(get: { intervalFrameRangeMode }, set: { intervalFrameRangeMode = $0 })) {
                ForEach(FrameExportRangeMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(controlsDisabled)

            if intervalFrameRangeMode == .custom {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("Start time")
                        TextField("Start seconds", text: $intervalFrameStartSeconds)
                            .textFieldStyle(.roundedBorder)
                            .disabled(controlsDisabled)
                        Text(FrameExportTimestamp.displayTime(Double(intervalFrameStartSeconds) ?? 0))
                            .foregroundStyle(.secondary)
                    }
                    GridRow {
                        Text("End time")
                        TextField("End seconds", text: $intervalFrameEndSeconds)
                            .textFieldStyle(.roundedBorder)
                            .disabled(controlsDisabled)
                        Text(FrameExportTimestamp.displayTime(Double(intervalFrameEndSeconds) ?? duration))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text(intervalFrameExportSummary)
                .font(.callout)
                .textSelection(.enabled)

            Button {
                chooseIntervalFrameDirectoryAndStart()
            } label: {
                Label(operationState.isRunning ? "Exporting Frames..." : "Export Frames", systemImage: "photo.on.rectangle")
            }
            .disabled(intervalFrameExportDisabled)
        }
        .onChange(of: inputURL) { _, _ in
            intervalFrameStartSeconds = "0"
            intervalFrameEndSeconds = ""
        }
    }

    private var intervalFrameExportDisabled: Bool {
        controlsDisabled || metadata?.videoCodec == nil || intervalFrameRequest(outputDirectoryURL: URL(fileURLWithPath: "/tmp")) == nil
    }

    private var intervalFrameExportSummary: String {
        guard let request = intervalFrameRequest(outputDirectoryURL: URL(fileURLWithPath: "/tmp")) else {
            return "Select a valid interval and range."
        }
        let dimensions = (try? request.expectedDimensions()).map { "\($0.width)x\($0.height)" } ?? "unavailable"
        var lines = [
            "Format: \(frameImageFormat.title)",
            "Interval: \(intervalFramePreset.title)",
            "Range: \(FrameExportTimestamp.displayTime(request.range.startSeconds)) to \(FrameExportTimestamp.displayTime(request.range.endSeconds))",
            "Estimated images: \(request.expectedImageCount)",
            "Expected dimensions: \(dimensions)"
        ]
        if frameImageFormat == .jpeg {
            lines.insert("Quality: \(frameJPEGQualityPreset.title)", at: 1)
        }
        return lines.joined(separator: "\n")
    }

    private func chooseIntervalFrameDirectoryAndStart() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let directoryURL = panel.url else { return }

        guard var request = intervalFrameRequest(outputDirectoryURL: directoryURL) else {
            validationMessage = "Frame interval export settings are invalid."
            return
        }

        let existingMatches = existingIntervalFrameMatches(for: request)
        if !existingMatches.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Matching frame files already exist"
            alert.informativeText = "\(existingMatches.count) files matching \(request.outputPrefix)######.\(request.format.fileExtension) already exist. Replace only those matching files?"
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            request = IntervalFrameExportRequest(
                inputURL: request.inputURL,
                outputDirectoryURL: request.outputDirectoryURL,
                sourceDuration: request.sourceDuration,
                sourceDimensions: request.sourceDimensions,
                sourceRotationDegrees: request.sourceRotationDegrees,
                hasVideoStream: request.hasVideoStream,
                interval: request.interval,
                range: request.range,
                format: request.format,
                jpegQuality: request.jpegQuality,
                replaceExisting: true,
                countTolerance: request.countTolerance
            )
        }

        do {
            try request.validate()
            validationMessage = nil
            onExportFramesAtIntervals(request)
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func intervalFrameRequest(outputDirectoryURL: URL) -> IntervalFrameExportRequest? {
        guard let inputURL,
              let width = metadata?.width,
              let height = metadata?.height else {
            return nil
        }
        let interval: FrameInterval
        do {
            if let presetSeconds = intervalFramePreset.seconds {
                interval = try FrameInterval(seconds: presetSeconds)
            } else if let custom = FrameInterval.parse(intervalFrameCustomSeconds) {
                interval = custom
            } else {
                return nil
            }
        } catch {
            return nil
        }

        let range: FrameExportRange
        do {
            if intervalFrameRangeMode == .entireVideo {
                range = try FrameExportRange.entireVideo(duration: duration)
            } else {
                guard let start = Double(intervalFrameStartSeconds.trimmingCharacters(in: .whitespacesAndNewlines)),
                      let end = Double(intervalFrameEndSeconds.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    return nil
                }
                range = try FrameExportRange(startSeconds: start, endSeconds: end, sourceDuration: duration)
            }
        } catch {
            return nil
        }

        let request = IntervalFrameExportRequest(
            inputURL: inputURL,
            outputDirectoryURL: outputDirectoryURL,
            sourceDuration: duration,
            sourceDimensions: VideoDimensions(width: width, height: height),
            sourceRotationDegrees: metadata?.rotationDegrees,
            hasVideoStream: metadata?.videoCodec != nil,
            interval: interval,
            range: range,
            format: frameImageFormat,
            jpegQuality: frameImageFormat == .jpeg ? frameJPEGQuality : nil
        )
        guard (try? request.validate()) != nil else { return nil }
        return request
    }

    private var frameJPEGQuality: JPEGQuality? {
        guard frameImageFormat == .jpeg else { return nil }
        let value = frameJPEGQualityPreset.qualityValue ?? frameCustomJPEGQuality
        return try? JPEGQuality(ffmpegValue: value)
    }

    private func existingIntervalFrameMatches(for request: IntervalFrameExportRequest) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: request.outputDirectoryURL.path)) ?? []
        return names
            .filter { request.matchesGeneratedFrameName($0) }
            .map { request.outputDirectoryURL.appendingPathComponent($0) }
    }
}
