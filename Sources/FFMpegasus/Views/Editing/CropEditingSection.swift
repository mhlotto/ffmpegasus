import FFMpegasusCore
import SwiftUI
import UniformTypeIdentifiers

struct CropEditingSection: View {
    let inputURL: URL?
    let duration: TimeInterval
    let metadata: VideoMetadata?
    let exportProfileCapabilities: ExportProfileCapabilities?
    let exportProfileCapabilityMessage: String?
    @ObservedObject var operationState: EditingOperationState
    @Binding var validationMessage: String?
    let testAutomationCropOutputURL: URL?
    let onCrop: (CropRequest) -> Void

    @AppStorage("cropMode") private var cropModeRaw = CropMode.aspectRatio.rawValue
    @AppStorage("cropAspectRatioPreset") private var cropAspectRatioPresetRaw = CropAspectRatioPreset.square.rawValue
    @AppStorage("cropPositionPreset") private var cropPositionPresetRaw = CropPositionPreset.center.rawValue
    @AppStorage("cropCustomRatioWidth") private var cropCustomRatioWidth = "2.39"
    @AppStorage("cropCustomRatioHeight") private var cropCustomRatioHeight = "1"
    @AppStorage("cropCustomWidth") private var cropCustomWidth = ""
    @AppStorage("cropCustomHeight") private var cropCustomHeight = ""
    @AppStorage("cropCustomX") private var cropCustomX = "0"
    @AppStorage("cropCustomY") private var cropCustomY = "0"
    @AppStorage("exportProfile") private var exportProfileRaw = ExportProfile.mp4H264.rawValue

    private var controlsDisabled: Bool {
        inputURL == nil || operationState.isRunning
    }

    private var cropMode: CropMode {
        get { CropMode(rawValue: cropModeRaw) ?? .aspectRatio }
        nonmutating set { cropModeRaw = newValue.rawValue }
    }

    private var aspectRatioPreset: CropAspectRatioPreset {
        get { CropAspectRatioPreset(rawValue: cropAspectRatioPresetRaw) ?? .square }
        nonmutating set { cropAspectRatioPresetRaw = newValue.rawValue }
    }

    private var positionPreset: CropPositionPreset {
        get { CropPositionPreset(rawValue: cropPositionPresetRaw) ?? .center }
        nonmutating set { cropPositionPresetRaw = newValue.rawValue }
    }

    private var exportProfile: ExportProfile {
        get { ExportProfile(rawValue: exportProfileRaw) ?? .mp4H264 }
        nonmutating set { exportProfileRaw = newValue.rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Crop Video")
                .font(.headline)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("editing.crop")

            Picker("Crop mode", selection: Binding(get: { cropMode }, set: { cropMode = $0 })) {
                ForEach(CropMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(controlsDisabled)
            .accessibilityIdentifier("crop.modePicker")

            if cropMode == .aspectRatio {
                aspectRatioControls
            } else {
                customRectangleControls
            }

            ExportProfileSelector(
                selectedProfile: Binding(get: { exportProfile }, set: { exportProfile = $0 }),
                capabilities: exportProfileCapabilities,
                capabilityMessage: exportProfileCapabilityMessage,
                disabled: controlsDisabled
            )

            Text(cropSummary)
                .font(.callout)
                .textSelection(.enabled)
                .accessibilityIdentifier("crop.summary")

            Button {
                chooseCropOutputAndStart()
            } label: {
                Label(operationState.isRunning ? "Cropping..." : "Crop Video", systemImage: "crop")
            }
            .disabled(cropDisabled)
            .accessibilityIdentifier("crop.exportButton")
        }
        .onChange(of: inputURL) {
            resetSourceSpecificFields()
        }
    }

    private var aspectRatioControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Aspect ratio", selection: Binding(get: { aspectRatioPreset }, set: { aspectRatioPreset = $0 })) {
                ForEach(CropAspectRatioPreset.allCases) { ratio in
                    Text(ratio.title).tag(ratio)
                }
            }
            .pickerStyle(.menu)
            .disabled(controlsDisabled)
            .accessibilityIdentifier("crop.ratioPicker")

            if aspectRatioPreset == .custom {
                HStack {
                    TextField("Width ratio", text: $cropCustomRatioWidth)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    Text(":")
                    TextField("Height ratio", text: $cropCustomRatioHeight)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
                .disabled(controlsDisabled)
            }

            Picker("Position", selection: Binding(get: { positionPreset }, set: { positionPreset = $0 })) {
                ForEach(CropPositionPreset.allCases) { position in
                    Text(position.title).tag(position)
                }
            }
            .pickerStyle(.menu)
            .disabled(controlsDisabled)
            .accessibilityIdentifier("crop.positionPicker")

            if positionPreset == .custom {
                HStack {
                    TextField("X", text: $cropCustomX)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .accessibilityIdentifier("crop.xField")
                    TextField("Y", text: $cropCustomY)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .accessibilityIdentifier("crop.yField")
                }
                .disabled(controlsDisabled)
            }
        }
    }

    private var customRectangleControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Width", text: $cropCustomWidth)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .accessibilityIdentifier("crop.widthField")
                TextField("Height", text: $cropCustomHeight)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .accessibilityIdentifier("crop.heightField")
            }
            HStack {
                TextField("X", text: $cropCustomX)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .accessibilityIdentifier("crop.xField")
                TextField("Y", text: $cropCustomY)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .accessibilityIdentifier("crop.yField")
            }
            .disabled(controlsDisabled)
        }
        .disabled(controlsDisabled)
    }

    private var cropDisabled: Bool {
        controlsDisabled || metadata?.videoCodec == nil || selectedProfileUnsupported || cropRequest(outputURL: URL(fileURLWithPath: "/tmp/output.\(exportProfile.fileExtension)")) == nil
    }

    private var cropSummary: String {
        guard let request = cropRequest(outputURL: URL(fileURLWithPath: "/tmp/output.\(exportProfile.fileExtension)")) else {
            return """
            Source display size: unavailable
            Crop rectangle: unavailable
            Output: \(exportProfile.displayName)
            """
        }
        guard let displayDimensions = try? request.displayDimensions(),
              let rectangle = try? request.resolvedRectangle() else {
            return "Crop settings are invalid."
        }
        let audio = request.hasAudioStream ? request.exportProfile.expectedAudioCodecs.sorted().joined(separator: ", ").uppercased() : "No audio"
        return """
        Source display size: \(displayDimensions.width)x\(displayDimensions.height)
        Crop mode: \(cropMode.title)
        Crop rectangle: \(rectangle.width)x\(rectangle.height)
        Position: \(positionPreset.title)
        Origin: x=\(rectangle.x), y=\(rectangle.y)
        Output size: \(rectangle.width)x\(rectangle.height)
        Output: \(request.exportProfile.displayName)
        Audio: \(audio)
        """
    }

    private func chooseCropOutputAndStart() {
        guard let inputURL else { return }
        let outputURL: URL
        if let testAutomationCropOutputURL {
            outputURL = testAutomationCropOutputURL
        } else {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType(filenameExtension: exportProfile.fileExtension) ?? .movie]
            let previewRectangle = cropRequest(outputURL: URL(fileURLWithPath: "/tmp/output.\(exportProfile.fileExtension)")).flatMap { try? $0.resolvedRectangle() }
            panel.nameFieldStringValue = OutputFilename.croppedName(for: inputURL, rectangle: previewRectangle, profile: exportProfile)
            guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
            outputURL = selectedURL
        }
        guard let request = cropRequest(outputURL: outputURL) else {
            validationMessage = "Crop settings are invalid."
            return
        }
        validationMessage = nil
        onCrop(request)
    }

    private func cropRequest(outputURL: URL) -> CropRequest? {
        guard let inputURL,
              let width = metadata?.width,
              let height = metadata?.height else {
            return nil
        }
        let configuration = cropConfiguration()
        let request = CropRequest(
            inputURL: inputURL,
            outputURL: outputURL,
            sourceDuration: duration,
            sourceDimensions: VideoDimensions(width: width, height: height),
            sourceRotationDegrees: metadata?.rotationDegrees,
            hasVideoStream: metadata?.videoCodec != nil,
            hasAudioStream: metadata?.audioCodec != nil,
            configuration: configuration,
            exportProfile: exportProfile
        )
        guard (try? request.validate()) != nil else { return nil }
        return request
    }

    private func cropConfiguration() -> CropConfiguration {
        CropConfiguration(
            mode: cropMode,
            aspectRatioPreset: aspectRatioPreset,
            customAspectRatio: CropAspectRatio.parse(width: cropCustomRatioWidth, height: cropCustomRatioHeight),
            position: positionPreset,
            customX: Int(cropCustomX.trimmingCharacters(in: .whitespacesAndNewlines)),
            customY: Int(cropCustomY.trimmingCharacters(in: .whitespacesAndNewlines)),
            customWidth: Int(cropCustomWidth.trimmingCharacters(in: .whitespacesAndNewlines)),
            customHeight: Int(cropCustomHeight.trimmingCharacters(in: .whitespacesAndNewlines))
        )
    }

    private func resetSourceSpecificFields() {
        cropCustomX = "0"
        cropCustomY = "0"
        if let width = metadata?.width, let height = metadata?.height {
            let dimensions = try? CropGeometry.displayDimensions(
                sourceDimensions: VideoDimensions(width: width, height: height),
                rotationDegrees: metadata?.rotationDegrees
            )
            cropCustomWidth = dimensions.map { String($0.width) } ?? ""
            cropCustomHeight = dimensions.map { String($0.height) } ?? ""
        }
    }

    private var selectedProfileUnsupported: Bool {
        exportProfileCapabilities?.support(for: exportProfile).isSupported == false
    }
}
