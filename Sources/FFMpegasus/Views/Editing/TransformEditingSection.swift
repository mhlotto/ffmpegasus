import FFMpegasusCore
import SwiftUI
import UniformTypeIdentifiers

struct TransformEditingSection: View {
    let inputURL: URL?
    let duration: TimeInterval
    let metadata: VideoMetadata?
    let exportProfileCapabilities: ExportProfileCapabilities?
    let exportProfileCapabilityMessage: String?
    @ObservedObject var operationState: EditingOperationState
    @Binding var validationMessage: String?
    let onTransform: (VideoTransformRequest) -> Void

    @AppStorage("transformRotation") private var transformRotationRaw = VideoRotation.none.rawValue
    @AppStorage("transformFlipHorizontal") private var transformFlipHorizontal = false
    @AppStorage("transformFlipVertical") private var transformFlipVertical = false
    @AppStorage("exportProfile") private var exportProfileRaw = ExportProfile.mp4H264.rawValue

    private var controlsDisabled: Bool {
        inputURL == nil || operationState.isRunning
    }

    private var transformRotation: VideoRotation {
        get { VideoRotation(rawValue: transformRotationRaw) ?? .none }
        nonmutating set { transformRotationRaw = newValue.rawValue }
    }

    private var exportProfile: ExportProfile {
        get { ExportProfile(rawValue: exportProfileRaw) ?? .mp4H264 }
        nonmutating set { exportProfileRaw = newValue.rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rotate / Flip")
                .font(.headline)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("editing.transform")

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

            ExportProfileSelector(
                selectedProfile: Binding(get: { exportProfile }, set: { exportProfile = $0 }),
                capabilities: exportProfileCapabilities,
                capabilityMessage: exportProfileCapabilityMessage,
                disabled: controlsDisabled
            )

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
        controlsDisabled || metadata?.videoCodec == nil || selectedProfileUnsupported || transformRequest(outputURL: URL(fileURLWithPath: "/tmp/output.\(exportProfile.fileExtension)")) == nil
    }

    private var transformSummary: String {
        guard let request = transformRequest(outputURL: URL(fileURLWithPath: "/tmp/output.\(exportProfile.fileExtension)")) else {
            return """
            Rotation: \(transformRotation.title)
            Horizontal flip: \(transformFlipHorizontal ? "Yes" : "No")
            Vertical flip: \(transformFlipVertical ? "Yes" : "No")
            Output: \(exportProfile.displayName)
            Audio: unavailable
            Expected resolution: unavailable
            """
        }
        let dimensions = try? request.outputDimensions()
        let audio = request.hasAudioStream ? request.exportProfile.expectedAudioCodecs.sorted().joined(separator: ", ").uppercased() : "No audio"
        return """
        Rotation: \(request.rotation.title)
        Horizontal flip: \(request.flipHorizontal ? "Yes" : "No")
        Vertical flip: \(request.flipVertical ? "Yes" : "No")
        Output: \(request.exportProfile.displayName)
        Audio: \(audio)
        Expected resolution: \(dimensions.map { "\($0.width)x\($0.height)" } ?? "unavailable")
        """
    }

    private func chooseTransformOutputAndStart() {
        guard let inputURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: exportProfile.fileExtension) ?? .movie]
        panel.nameFieldStringValue = OutputFilename.transformedName(
            for: inputURL,
            rotation: transformRotation,
            flipHorizontal: transformFlipHorizontal,
            flipVertical: transformFlipVertical,
            profile: exportProfile
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
            flipVertical: transformFlipVertical,
            exportProfile: exportProfile
        )
        guard (try? request.filterChain()) != nil, (try? request.outputDimensions()) != nil else {
            return nil
        }
        return request
    }

    private var selectedProfileUnsupported: Bool {
        exportProfileCapabilities?.support(for: exportProfile).isSupported == false
    }
}
