import FFMpegasusCore
import SwiftUI
import UniformTypeIdentifiers

struct CombinedExportEditingSection: View {
    let inputURL: URL?
    let duration: TimeInterval
    let metadata: VideoMetadata?
    @ObservedObject var operationState: EditingOperationState
    @Binding var validationMessage: String?
    let onExportPlan: (VideoEditPlan) -> Void

    @State private var combinedTrimEnabled = false
    @State private var combinedMode: EditingMode = .trimStart
    @State private var combinedStartSeconds = "0"
    @State private var combinedEndSeconds = "0"
    @State private var combinedTrimExecutionMode: TrimExecutionMode = .fast
    @State private var combinedTransformEnabled = false
    @State private var combinedRotation: VideoRotation = .none
    @State private var combinedFlipHorizontal = false
    @State private var combinedFlipVertical = false
    @State private var combinedResizeEnabled = false
    @State private var combinedResolution: OutputResolution = .original
    @State private var combinedCustomHeight = "720"
    @State private var combinedCompressionEnabled = false
    @State private var combinedQuality: CompressionQuality = .balanced
    @State private var combinedCustomCRF = 24
    @State private var combinedEncoderPreset: EncoderPreset = .medium
    @State private var combinedSpeedEnabled = false
    @State private var combinedSpeedPreset: SpeedPreset = .x1_0
    @State private var combinedCustomSpeed = "1.0"
    @State private var combinedAudioMode: ExportAudioMode = .keep

    private var controlsDisabled: Bool {
        inputURL == nil || operationState.isRunning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Combined Export")
                .font(.headline)

            Toggle("Trim", isOn: $combinedTrimEnabled)
                .disabled(controlsDisabled)
            if combinedTrimEnabled {
                Picker("Trim type", selection: $combinedMode) {
                    ForEach(EditingMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(controlsDisabled)

                Picker("Trim Mode", selection: $combinedTrimExecutionMode) {
                    ForEach(TrimExecutionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(controlsDisabled)

                HStack {
                    TextField("First seconds", text: $combinedStartSeconds)
                        .textFieldStyle(.roundedBorder)
                        .disabled(controlsDisabled || combinedMode == .trimEnd)
                    TextField("Last seconds", text: $combinedEndSeconds)
                        .textFieldStyle(.roundedBorder)
                        .disabled(controlsDisabled || combinedMode == .trimStart)
                }
            }

            Toggle("Rotate / Flip", isOn: $combinedTransformEnabled)
                .disabled(controlsDisabled)
            if combinedTransformEnabled {
                Picker("Rotation", selection: $combinedRotation) {
                    ForEach(VideoRotation.allCases) { rotation in
                        Text(rotation.title).tag(rotation)
                    }
                }
                .pickerStyle(.menu)
                .disabled(controlsDisabled)
                Toggle("Flip horizontally", isOn: $combinedFlipHorizontal)
                    .disabled(controlsDisabled)
                Toggle("Flip vertically", isOn: $combinedFlipVertical)
                    .disabled(controlsDisabled)
            }

            Toggle("Resize", isOn: $combinedResizeEnabled)
                .disabled(controlsDisabled)
            if combinedResizeEnabled {
                Picker("Resolution", selection: $combinedResolution) {
                    ForEach(OutputResolution.allCases) { resolution in
                        Text(resolution.title).tag(resolution)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(controlsDisabled)
                if combinedResolution == .custom {
                    TextField("Maximum height", text: $combinedCustomHeight)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .disabled(controlsDisabled)
                }
            }

            Toggle("Compression", isOn: $combinedCompressionEnabled)
                .disabled(controlsDisabled)
            if combinedCompressionEnabled {
                Picker("Quality", selection: $combinedQuality) {
                    ForEach(CompressionQuality.allCases) { quality in
                        Text(quality.title).tag(quality)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(controlsDisabled)
                if combinedQuality == .custom {
                    HStack {
                        Stepper("CRF \(combinedCustomCRF)", value: $combinedCustomCRF, in: 16...35)
                        Picker("Encoder", selection: $combinedEncoderPreset) {
                            ForEach(EncoderPreset.allCases, id: \.rawValue) { preset in
                                Text(preset.rawValue).tag(preset)
                            }
                        }
                        .frame(maxWidth: 220)
                    }
                    .disabled(controlsDisabled)
                }
            }

            Toggle("Change Speed", isOn: $combinedSpeedEnabled)
                .disabled(controlsDisabled)
            if combinedSpeedEnabled {
                Picker("Speed", selection: $combinedSpeedPreset) {
                    ForEach(SpeedPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(controlsDisabled)

                if combinedSpeedPreset == .custom {
                    TextField("Custom speed", text: $combinedCustomSpeed)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .disabled(controlsDisabled)
                }

                Text("Lower values slow the video down. Higher values speed it up.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Picker("Audio", selection: $combinedAudioMode) {
                ForEach(ExportAudioMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(controlsDisabled || metadata?.audioCodec == nil)

            if metadata?.audioCodec == nil, inputURL != nil {
                Text("This video has no audio stream; combined output will have no audio.")
                    .foregroundStyle(.secondary)
            }

            Text(combinedSummary)
                .font(.callout)
                .textSelection(.enabled)

            DisclosureGroup("Planned invocation") {
                Text(combinedDiagnostics)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                chooseCombinedOutputAndStart()
            } label: {
                Label(operationState.isRunning ? "Exporting Changes..." : "Export Changes", systemImage: "square.and.arrow.up")
            }
            .disabled(combinedExportDisabled)
        }
    }

    private var combinedExportDisabled: Bool {
        controlsDisabled || metadata?.videoCodec == nil || combinedPlan(outputURL: URL(fileURLWithPath: "/tmp/output.mp4")) == nil
    }

    private var combinedSummary: String {
        guard let plan = combinedPlan(outputURL: URL(fileURLWithPath: "/tmp/output.mp4")) else {
            return "Selected changes\nSelect at least one change."
        }
        let strategy = (try? plan.executionStrategy()) ?? .reencode
        let quality = try? plan.qualitySettings()
        let dimensions = try? plan.outputDimensions()
        let fastUpgrade = plan.trim?.executionMode == .fast && strategy == .reencode
        var lines = [
            "Selected changes",
            "Trim: \(combinedTrimDescription(plan.trim))",
            "Rotation: \(plan.transform?.rotation.title ?? "None")",
            "Horizontal flip: \(plan.transform?.flipHorizontal == true ? "Yes" : "No")",
            "Vertical flip: \(plan.transform?.flipVertical == true ? "Yes" : "No")",
            "Resize: \(plan.resize?.resolution.title ?? "Original")",
            "Quality: \(plan.compression?.quality.title ?? "Default"), CRF \(quality?.crf ?? 20)",
            "Speed: \(plan.speed?.filenameLabel ?? "Original")",
            "Audio: \(plan.audioMode == .remove || !plan.hasAudioStream ? "Remove" : "Keep")",
            "Execution: \(strategy.title)",
            "Output: \(strategy == .reencode ? "MP4 / H.264" : "stream copy")",
            "Expected resolution: \(dimensions.map { "\($0.width)x\($0.height)" } ?? "unavailable")",
            "Expected duration: \(combinedExpectedDuration(plan))"
        ]
        if fastUpgrade {
            lines.append("Fast Trim requires stream copy. Because other selected edits require re-encoding, this export will use accurate trimming.")
        }
        return lines.joined(separator: "\n")
    }

    private func combinedExpectedDuration(_ plan: VideoEditPlan) -> String {
        guard let duration = try? plan.outputDuration() else { return "unavailable" }
        return String(format: "%.1f seconds", duration)
    }

    private var combinedDiagnostics: String {
        guard let plan = combinedPlan(outputURL: URL(fileURLWithPath: "/tmp/output.mp4")),
              let strategy = try? plan.executionStrategy() else {
            return "No valid edit plan."
        }
        let filter = (try? plan.filterChain()) ?? nil
        return """
        Execution strategy: \(strategy.title)
        Filter chain: \(filter ?? "none")
        Speed filter: \(plan.speed?.videoFilter() ?? "none")
        Audio policy: \(plan.audioMode == .remove || !plan.hasAudioStream ? "remove audio" : "keep primary audio")
        Argument array: generated after choosing an output file
        """
    }

    private func combinedTrimDescription(_ trim: TrimConfiguration?) -> String {
        guard let trim else { return "None" }
        switch trim.mode {
        case .trimStart:
            return String(format: "Remove first %.3g seconds", trim.removeStartSeconds)
        case .trimEnd:
            return String(format: "Remove last %.3g seconds", trim.removeEndSeconds)
        case .trimBoth:
            return String(format: "Remove first %.3g and last %.3g seconds", trim.removeStartSeconds, trim.removeEndSeconds)
        }
    }

    private func chooseCombinedOutputAndStart() {
        guard let inputURL else { return }
        guard let previewPlan = combinedPlan(outputURL: URL(fileURLWithPath: "/tmp/output.mp4")),
              let strategy = try? previewPlan.executionStrategy() else {
            validationMessage = combinedValidationMessage()
            return
        }
        let panel = NSSavePanel()
        let outputExtension = strategy == .reencode ? "mp4" : (inputURL.pathExtension.isEmpty ? "mp4" : inputURL.pathExtension)
        panel.allowedContentTypes = [UTType(filenameExtension: outputExtension) ?? .mpeg4Movie]
        panel.nameFieldStringValue = combinedOutputName(for: inputURL, strategy: strategy)
        guard panel.runModal() == .OK, let outputURL = panel.url else { return }
        guard let plan = combinedPlan(outputURL: outputURL) else {
            validationMessage = combinedValidationMessage()
            return
        }
        validationMessage = nil
        onExportPlan(plan)
    }

    private func combinedOutputName(for inputURL: URL, strategy: ExportExecutionStrategy) -> String {
        let base = inputURL.deletingPathExtension().lastPathComponent
        let ext = strategy == .reencode ? "mp4" : (inputURL.pathExtension.isEmpty ? "mp4" : inputURL.pathExtension)
        return "\(base)-edited.\(ext)"
    }

    private func combinedValidationMessage() -> String {
        guard let inputURL,
              let width = metadata?.width,
              let height = metadata?.height else {
            return "Open a video before exporting changes."
        }
        do {
            let plan = try makeCombinedPlan(inputURL: inputURL, outputURL: URL(fileURLWithPath: "/tmp/output.mp4"), width: width, height: height)
            try plan.validate()
            return "Combined export settings are invalid."
        } catch {
            return error.localizedDescription
        }
    }

    private func combinedPlan(outputURL: URL) -> VideoEditPlan? {
        guard let inputURL,
              let width = metadata?.width,
              let height = metadata?.height else {
            return nil
        }
        guard let plan = try? makeCombinedPlan(inputURL: inputURL, outputURL: outputURL, width: width, height: height),
              (try? plan.validate()) != nil else {
            return nil
        }
        return plan
    }

    private func makeCombinedPlan(inputURL: URL, outputURL: URL, width: Int, height: Int) throws -> VideoEditPlan {
        let trim = try combinedTrimConfiguration()
        let transform = combinedTransformEnabled ? VideoTransformConfiguration(
            rotation: combinedRotation,
            flipHorizontal: combinedFlipHorizontal,
            flipVertical: combinedFlipVertical
        ) : nil
        let resize = combinedResizeEnabled ? ResizeConfiguration(
            resolution: combinedResolution,
            customHeight: Int(combinedCustomHeight.trimmingCharacters(in: .whitespacesAndNewlines))
        ) : nil
        let compression = combinedCompressionEnabled ? CompressionConfiguration(
            quality: combinedQuality,
            customCRF: combinedCustomCRF,
            encoderPreset: combinedEncoderPreset
        ) : nil
        let speed = try combinedSpeedConfiguration()
        return VideoEditPlan(
            inputURL: inputURL,
            outputURL: outputURL,
            sourceDuration: duration,
            sourceDimensions: VideoDimensions(width: width, height: height),
            sourceRotationDegrees: metadata?.rotationDegrees,
            hasVideoStream: metadata?.videoCodec != nil,
            hasAudioStream: metadata?.audioCodec != nil,
            trim: trim,
            transform: transform?.hasTransformation == true ? transform : nil,
            resize: resize,
            compression: compression,
            speed: speed,
            audioMode: metadata?.audioCodec == nil ? .remove : combinedAudioMode
        )
    }

    private func combinedTrimConfiguration() throws -> TrimConfiguration? {
        guard combinedTrimEnabled else { return nil }
        let start = combinedMode == .trimEnd ? 0 : TrimSecondsParser.parse(combinedStartSeconds)
        let end = combinedMode == .trimStart ? 0 : TrimSecondsParser.parse(combinedEndSeconds)
        guard let start, let end else {
            throw EditingValidationError.negativeTrimValue
        }
        return TrimConfiguration(
            mode: combinedMode,
            removeStartSeconds: start,
            removeEndSeconds: end,
            executionMode: combinedTrimExecutionMode
        )
    }

    private func combinedSpeedConfiguration() throws -> VideoSpeed? {
        guard combinedSpeedEnabled else { return nil }
        if let multiplier = combinedSpeedPreset.multiplier {
            return try VideoSpeed(multiplier: multiplier)
        }
        guard let speed = VideoSpeed.parse(combinedCustomSpeed) else {
            throw VideoSpeedValidationError.invalidSpeed
        }
        return speed
    }
}
