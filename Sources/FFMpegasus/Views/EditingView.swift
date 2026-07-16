import FFMpegasusCore
import SwiftUI
import UniformTypeIdentifiers

struct EditingView: View {
    let inputURL: URL?
    let duration: TimeInterval
    let metadata: VideoMetadata?
    @ObservedObject var operationState: EditingOperationState
    let onStart: (EditingRequest) -> Void
    let onRemoveAudio: (RemoveAudioRequest) -> Void
    let onCompress: (CompressionRequest) -> Void
    let onTransform: (VideoTransformRequest) -> Void
    let onExportPlan: (VideoEditPlan) -> Void
    let onChangeSpeed: (VideoSpeedRequest) -> Void
    let onCancel: () -> Void

    @State private var mode: EditingMode = .trimStart
    @State private var startSeconds = "0"
    @State private var endSeconds = "0"
    @State private var validationMessage: String?
    @AppStorage("trimExecutionMode") private var trimExecutionModeRaw = TrimExecutionMode.fast.rawValue
    @AppStorage("compressionQuality") private var compressionQualityRaw = CompressionQuality.balanced.rawValue
    @AppStorage("compressionCustomCRF") private var compressionCustomCRF = 24
    @AppStorage("compressionEncoderPreset") private var compressionEncoderPresetRaw = EncoderPreset.medium.rawValue
    @AppStorage("compressionResolution") private var compressionResolutionRaw = OutputResolution.p720.rawValue
    @AppStorage("compressionCustomHeight") private var compressionCustomHeight = "720"
    @AppStorage("compressionAudioMode") private var compressionAudioModeRaw = CompressionAudioMode.keep.rawValue
    @AppStorage("transformRotation") private var transformRotationRaw = VideoRotation.none.rawValue
    @AppStorage("transformFlipHorizontal") private var transformFlipHorizontal = false
    @AppStorage("transformFlipVertical") private var transformFlipVertical = false
    @AppStorage("speedPreset") private var speedPresetRaw = SpeedPreset.x1_0.rawValue
    @AppStorage("speedCustomValue") private var speedCustomValue = "1.0"
    @AppStorage("speedAudioMode") private var speedAudioModeRaw = SpeedAudioMode.keep.rawValue
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
    @FocusState private var focusedField: TrimField?

    private enum TrimField {
        case start
        case end
    }

    private var controlsDisabled: Bool {
        inputURL == nil || operationState.isRunning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Editing")
                .font(.headline)

            Picker("Operation", selection: $mode) {
                ForEach(EditingMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(controlsDisabled)

            Picker("Trim Mode", selection: Binding(get: { trimExecutionMode }, set: { trimExecutionMode = $0 })) {
                ForEach(TrimExecutionMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(controlsDisabled)

            Text(trimExecutionMode.description)
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                TextField("First seconds", text: $startSeconds)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .start)
                    .disabled(mode == .trimEnd || controlsDisabled)

                TextField("Last seconds", text: $endSeconds)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .end)
                    .disabled(mode == .trimStart || controlsDisabled)

                Button {
                    chooseOutputAndStart()
                } label: {
                    Label(operationState.isRunning ? "Trimming..." : "Trim", systemImage: "scissors")
                }
                .disabled(controlsDisabled)

                Button {
                    onCancel()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
                .disabled(!operationState.isRunning)
            }

            inlineOperationStatus

            Text("Stream-copy cuts are fast, but may align to keyframes and may not be frame-accurate.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()

            HStack {
                Button {
                    chooseRemoveAudioOutputAndStart()
                } label: {
                    Label(operationState.isRunning ? "Removing Audio..." : "Remove Audio", systemImage: "speaker.slash")
                }
                .disabled(removeAudioDisabled)

                if metadata?.audioCodec == nil, inputURL != nil {
                    Text("This video has no audio stream.")
                        .foregroundStyle(.secondary)
                }
            }

            if let validationMessage {
                Text(validationMessage)
                    .foregroundStyle(.red)
            }

            Divider()

            combinedExportSection

            Divider()

            transformSection

            Divider()

            compressionSection

            Divider()

            speedSection
        }
        .onChange(of: mode) { _, newMode in
            switch newMode {
            case .trimStart where focusedField == .end:
                focusedField = .start
            case .trimEnd where focusedField == .start:
                focusedField = .end
            default:
                break
            }
        }
        .onChange(of: operationState.isRunning) { _, isRunning in
            if isRunning {
                focusedField = nil
            }
        }
    }

    @ViewBuilder
    private var inlineOperationStatus: some View {
        switch operationState.phase {
        case .idle:
            EmptyView()
        case .starting, .cancelling:
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text(operationState.status)
                    .foregroundStyle(.secondary)
            }
        case .running(let progress):
            HStack {
                if let progress {
                    ProgressView(value: progress)
                        .frame(width: 180)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(operationState.status)
                    .foregroundStyle(.secondary)
            }
        case .completed:
            Text(operationState.message ?? "Trim complete")
                .foregroundStyle(.green)
                .textSelection(.enabled)
        case .failed:
            Text(operationState.message ?? "Trim failed")
                .foregroundStyle(.red)
                .textSelection(.enabled)
        case .cancelled:
            Text(operationState.message ?? "Operation cancelled.")
                .foregroundStyle(.secondary)
        }
    }

    private func chooseOutputAndStart() {
        guard let inputURL else { return }

        let start = mode == .trimEnd ? 0 : TrimSecondsParser.parse(startSeconds)
        let end = mode == .trimStart ? 0 : TrimSecondsParser.parse(endSeconds)

        guard let start, let end else {
            validationMessage = "Enter valid numeric trim values."
            return
        }

        let panel = NSSavePanel()
        let outputExtension = trimExecutionMode == .accurate ? "mp4" : inputURL.pathExtension
        panel.allowedContentTypes = [UTType(filenameExtension: outputExtension) ?? .movie]
        panel.nameFieldStringValue = defaultOutputName(for: inputURL)

        guard panel.runModal() == .OK, let outputURL = panel.url else { return }

        let request = EditingRequest(
            inputURL: inputURL,
            outputURL: outputURL,
            sourceDuration: duration,
            removeStartSeconds: start,
            removeEndSeconds: end,
            mode: mode,
            method: .streamCopy,
            trimExecutionMode: trimExecutionMode,
            hasVideoStream: metadata?.videoCodec != nil,
            hasAudioStream: metadata?.audioCodec != nil
        )

        do {
            _ = try request.trimPlan()
            validationMessage = nil
            onStart(request)
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func defaultOutputName(for inputURL: URL) -> String {
        OutputFilename.trimmedName(for: inputURL, mode: trimExecutionMode)
    }

    private var trimExecutionMode: TrimExecutionMode {
        get { TrimExecutionMode(rawValue: trimExecutionModeRaw) ?? .fast }
        nonmutating set { trimExecutionModeRaw = newValue.rawValue }
    }

    private var removeAudioDisabled: Bool {
        controlsDisabled || metadata?.videoCodec == nil || metadata?.audioCodec == nil
    }

    private func chooseRemoveAudioOutputAndStart() {
        guard let inputURL else {
            validationMessage = "Open a video first."
            return
        }
        guard metadata?.videoCodec != nil else {
            validationMessage = "Input contains no video stream."
            return
        }
        guard metadata?.audioCodec != nil else {
            validationMessage = "Input contains no audio stream."
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: inputURL.pathExtension) ?? .movie]
        panel.nameFieldStringValue = mutedOutputName(for: inputURL)

        guard panel.runModal() == .OK, let outputURL = panel.url else { return }

        validationMessage = nil
        onRemoveAudio(RemoveAudioRequest(
            inputURL: inputURL,
            outputURL: outputURL,
            sourceDuration: duration,
            hasVideoStream: metadata?.videoCodec != nil,
            hasAudioStream: metadata?.audioCodec != nil
        ))
    }

    private func mutedOutputName(for inputURL: URL) -> String {
        OutputFilename.mutedName(for: inputURL)
    }

    private var compressionQuality: CompressionQuality {
        get { CompressionQuality(rawValue: compressionQualityRaw) ?? .balanced }
        nonmutating set { compressionQualityRaw = newValue.rawValue }
    }

    private var encoderPreset: EncoderPreset {
        get { EncoderPreset(rawValue: compressionEncoderPresetRaw) ?? .medium }
        nonmutating set { compressionEncoderPresetRaw = newValue.rawValue }
    }

    private var compressionResolution: OutputResolution {
        get { OutputResolution(rawValue: compressionResolutionRaw) ?? .p720 }
        nonmutating set { compressionResolutionRaw = newValue.rawValue }
    }

    private var compressionAudioMode: CompressionAudioMode {
        get { CompressionAudioMode(rawValue: compressionAudioModeRaw) ?? .keep }
        nonmutating set { compressionAudioModeRaw = newValue.rawValue }
    }

    private var transformRotation: VideoRotation {
        get { VideoRotation(rawValue: transformRotationRaw) ?? .none }
        nonmutating set { transformRotationRaw = newValue.rawValue }
    }

    private var speedPreset: SpeedPreset {
        get { SpeedPreset(rawValue: speedPresetRaw) ?? .x1_0 }
        nonmutating set { speedPresetRaw = newValue.rawValue }
    }

    private var speedAudioMode: SpeedAudioMode {
        get { SpeedAudioMode(rawValue: speedAudioModeRaw) ?? .keep }
        nonmutating set { speedAudioModeRaw = newValue.rawValue }
    }

    @ViewBuilder
    private var combinedExportSection: some View {
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

    @ViewBuilder
    private var transformSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rotate / Flip")
                .font(.headline)

            Picker("Rotation", selection: Binding(get: { transformRotation }, set: { transformRotation = $0 })) {
                ForEach(VideoRotation.allCases) { rotation in
                    Text(rotation.title).tag(rotation)
                }
            }
            .pickerStyle(.menu)
            .disabled(controlsDisabled)

            Toggle("Flip horizontally", isOn: $transformFlipHorizontal)
                .disabled(controlsDisabled)
            Toggle("Flip vertically", isOn: $transformFlipVertical)
                .disabled(controlsDisabled)

            Text(transformSummary)
                .font(.callout)
                .textSelection(.enabled)

            Button {
                chooseTransformOutputAndStart()
            } label: {
                Label(operationState.isRunning ? "Transforming..." : "Export Transformed Video", systemImage: "rotate.right")
            }
            .disabled(transformDisabled)
        }
    }

    private var transformDisabled: Bool {
        controlsDisabled || metadata?.videoCodec == nil || transformRequest(outputURL: URL(fileURLWithPath: "/tmp/output.mp4")) == nil
    }

    private var transformSummary: String {
        guard let request = transformRequest(outputURL: URL(fileURLWithPath: "/tmp/output.mp4")) else {
            return """
            Rotation: \(transformRotation.title)
            Horizontal flip: \(transformFlipHorizontal ? "Yes" : "No")
            Vertical flip: \(transformFlipVertical ? "Yes" : "No")
            Output: MP4 / H.264
            Audio: unavailable
            Expected resolution: unavailable
            """
        }
        let dimensions = try? request.outputDimensions()
        let audio = request.hasAudioStream ? "AAC 128 kbps" : "No audio"
        return """
        Rotation: \(request.rotation.title)
        Horizontal flip: \(request.flipHorizontal ? "Yes" : "No")
        Vertical flip: \(request.flipVertical ? "Yes" : "No")
        Output: MP4 / H.264
        Audio: \(audio)
        Expected resolution: \(dimensions.map { "\($0.width)x\($0.height)" } ?? "unavailable")
        """
    }

    private func chooseTransformOutputAndStart() {
        guard let inputURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "mp4") ?? .mpeg4Movie]
        panel.nameFieldStringValue = OutputFilename.transformedName(
            for: inputURL,
            rotation: transformRotation,
            flipHorizontal: transformFlipHorizontal,
            flipVertical: transformFlipVertical
        )
        guard panel.runModal() == .OK, let outputURL = panel.url else { return }
        guard let request = transformRequest(outputURL: outputURL) else {
            validationMessage = "Transformation settings are invalid."
            return
        }
        validationMessage = nil
        onTransform(request)
    }

    private func transformRequest(outputURL: URL) -> VideoTransformRequest? {
        guard let inputURL,
              let width = metadata?.width,
              let height = metadata?.height else {
            return nil
        }
        let request = VideoTransformRequest(
            inputURL: inputURL,
            outputURL: outputURL,
            sourceDuration: duration,
            sourceDimensions: VideoDimensions(width: width, height: height),
            sourceRotationDegrees: metadata?.rotationDegrees,
            hasVideoStream: metadata?.videoCodec != nil,
            hasAudioStream: metadata?.audioCodec != nil,
            rotation: transformRotation,
            flipHorizontal: transformFlipHorizontal,
            flipVertical: transformFlipVertical
        )
        guard (try? request.filterChain()) != nil, (try? request.outputDimensions()) != nil else {
            return nil
        }
        return request
    }

    @ViewBuilder
    private var compressionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Compress / Resize")
                .font(.headline)

            Picker("Quality", selection: Binding(get: { compressionQuality }, set: { compressionQuality = $0 })) {
                ForEach(CompressionQuality.allCases) { quality in
                    Text(quality.title).tag(quality)
                }
            }
            .pickerStyle(.segmented)
            .disabled(controlsDisabled)

            if compressionQuality == .custom {
                HStack {
                    Stepper("CRF \(compressionCustomCRF)", value: $compressionCustomCRF, in: 16...35)
                    Picker("Encoder", selection: Binding(get: { encoderPreset }, set: { encoderPreset = $0 })) {
                        ForEach(EncoderPreset.allCases, id: \.rawValue) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    .frame(maxWidth: 220)
                }
                .disabled(controlsDisabled)
            }

            Text("Lower CRF means higher quality and a larger file. Slower encoder presets usually produce better compression but take longer.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Picker("Resolution", selection: Binding(get: { compressionResolution }, set: { compressionResolution = $0 })) {
                ForEach(OutputResolution.allCases) { resolution in
                    Text(resolution.title).tag(resolution)
                }
            }
            .pickerStyle(.segmented)
            .disabled(controlsDisabled)

            if compressionResolution == .custom {
                TextField("Maximum height", text: $compressionCustomHeight)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .disabled(controlsDisabled)
            }

            Picker("Audio", selection: Binding(get: { compressionAudioMode }, set: { compressionAudioMode = $0 })) {
                ForEach(CompressionAudioMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(controlsDisabled || metadata?.audioCodec == nil)

            if metadata?.audioCodec == nil, inputURL != nil {
                Text("This video has no audio stream; compressed output will have no audio.")
                    .foregroundStyle(.secondary)
            }

            Text(compressionSummary)
                .font(.callout)
                .textSelection(.enabled)

            Button {
                chooseCompressionOutputAndStart()
            } label: {
                Label(operationState.isRunning ? "Compressing..." : "Compress Video", systemImage: "arrow.down.right.and.arrow.up.left")
            }
            .disabled(compressionDisabled)
        }
    }

    private var compressionDisabled: Bool {
        controlsDisabled || metadata?.videoCodec == nil || compressionRequest(outputURL: URL(fileURLWithPath: "/tmp/output.mp4")) == nil
    }

    private var compressionSummary: String {
        guard let request = compressionRequest(outputURL: URL(fileURLWithPath: "/tmp/output.mp4")) else {
            return "Output: MP4 / H.264\nResolution: unavailable\nEstimated size: varies by video content"
        }
        let quality = (try? request.qualitySettings())
        let dimensions = try? request.outputDimensions()
        let audio = request.hasAudioStream && request.audioMode == .keep ? "AAC 128 kbps" : "No audio"
        return """
        Output: MP4 / H.264
        Resolution: \(dimensions.map { "\($0.width)x\($0.height)" } ?? "Unavailable")
        Quality: \(request.quality.title), CRF \(quality?.crf ?? request.customCRF)
        Audio: \(audio)
        Estimated size: varies by video content
        """
    }

    private func chooseCompressionOutputAndStart() {
        guard let inputURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "mp4") ?? .mpeg4Movie]
        panel.nameFieldStringValue = OutputFilename.compressedName(for: inputURL)
        guard panel.runModal() == .OK, let outputURL = panel.url else { return }
        guard let request = compressionRequest(outputURL: outputURL) else {
            validationMessage = "Compression settings are invalid."
            return
        }
        validationMessage = nil
        onCompress(request)
    }

    private func compressionRequest(outputURL: URL) -> CompressionRequest? {
        guard let inputURL,
              let width = metadata?.width,
              let height = metadata?.height else {
            return nil
        }
        let customHeight = Int(compressionCustomHeight.trimmingCharacters(in: .whitespacesAndNewlines))
        let audioMode = metadata?.audioCodec == nil ? CompressionAudioMode.remove : compressionAudioMode
        let request = CompressionRequest(
            inputURL: inputURL,
            outputURL: outputURL,
            sourceDuration: duration,
            sourceDimensions: VideoDimensions(width: width, height: height),
            hasVideoStream: metadata?.videoCodec != nil,
            hasAudioStream: metadata?.audioCodec != nil,
            quality: compressionQuality,
            customCRF: compressionCustomCRF,
            encoderPreset: encoderPreset,
            resolution: compressionResolution,
            customHeight: customHeight,
            audioMode: audioMode
        )
        guard (try? request.qualitySettings()) != nil, (try? request.outputDimensions()) != nil else {
            return nil
        }
        return request
    }

    @ViewBuilder
    private var speedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Change Speed")
                .font(.headline)

            Picker("Speed", selection: Binding(get: { speedPreset }, set: { speedPreset = $0 })) {
                ForEach(SpeedPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .disabled(controlsDisabled)

            if speedPreset == .custom {
                TextField("Custom speed", text: $speedCustomValue)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .disabled(controlsDisabled)
            }

            Text("Lower values slow the video down. Higher values speed it up. Audio pitch is preserved when audio is kept.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Picker("Audio", selection: Binding(get: { speedAudioMode }, set: { speedAudioMode = $0 })) {
                ForEach(SpeedAudioMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(controlsDisabled || metadata?.audioCodec == nil)

            if metadata?.audioCodec == nil, inputURL != nil {
                Text("This video has no audio stream; speed output will have no audio.")
                    .foregroundStyle(.secondary)
            }

            Text(speedSummary)
                .font(.callout)
                .textSelection(.enabled)

            Button {
                chooseSpeedOutputAndStart()
            } label: {
                Label(operationState.isRunning ? "Changing Speed..." : "Export Speed-Changed Video", systemImage: "speedometer")
            }
            .disabled(speedExportDisabled)
        }
    }

    private var speedExportDisabled: Bool {
        controlsDisabled || metadata?.videoCodec == nil || speedRequest(outputURL: URL(fileURLWithPath: "/tmp/output.mp4")) == nil
    }

    private var speedSummary: String {
        guard let request = speedRequest(outputURL: URL(fileURLWithPath: "/tmp/output.mp4")) else {
            return """
            Speed: \(currentSpeedDescription)
            Original duration: \(TimeFormatting.clockTime(duration))
            Expected duration: unavailable
            Video: H.264
            Audio: unavailable
            """
        }
        let expected = (try? request.expectedDuration()) ?? 0
        let audio = request.keepsAudio ? "AAC 128 kbps" : "No audio"
        return """
        Speed: \(request.speed.filenameLabel)
        Original duration: \(String(format: "%.1f seconds", request.sourceDuration))
        Expected duration: \(String(format: "%.1f seconds", expected))
        Video: H.264
        Audio: \(audio)
        """
    }

    private var currentSpeedDescription: String {
        guard let speed = selectedSpeed else { return "Invalid" }
        return speed.filenameLabel
    }

    private var selectedSpeed: VideoSpeed? {
        if let multiplier = speedPreset.multiplier {
            return try? VideoSpeed(multiplier: multiplier)
        }
        return VideoSpeed.parse(speedCustomValue)
    }

    private func chooseSpeedOutputAndStart() {
        guard let inputURL else { return }
        guard let speed = selectedSpeed else {
            validationMessage = "Enter a valid speed between 0.25x and 4.0x."
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "mp4") ?? .mpeg4Movie]
        panel.nameFieldStringValue = OutputFilename.speedName(for: inputURL, speed: speed)
        guard panel.runModal() == .OK, let outputURL = panel.url else { return }

        guard let request = speedRequest(outputURL: outputURL) else {
            validationMessage = "Speed settings are invalid."
            return
        }
        do {
            try request.validateForExport()
            validationMessage = nil
            onChangeSpeed(request)
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func speedRequest(outputURL: URL) -> VideoSpeedRequest? {
        guard let inputURL,
              let width = metadata?.width,
              let height = metadata?.height,
              let speed = selectedSpeed else {
            return nil
        }
        let request = VideoSpeedRequest(
            inputURL: inputURL,
            outputURL: outputURL,
            sourceDuration: duration,
            sourceDimensions: VideoDimensions(width: width, height: height),
            sourceRotationDegrees: metadata?.rotationDegrees,
            hasVideoStream: metadata?.videoCodec != nil,
            hasAudioStream: metadata?.audioCodec != nil,
            speed: speed,
            audioMode: metadata?.audioCodec == nil ? .remove : speedAudioMode
        )
        guard (try? request.validateForExport()) != nil else {
            return nil
        }
        return request
    }
}
