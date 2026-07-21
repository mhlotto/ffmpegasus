import FFMpegasusCore
import SwiftUI
import UniformTypeIdentifiers

struct SpeedEditingSection: View {
    let inputURL: URL?
    let duration: TimeInterval
    let metadata: VideoMetadata?
    @ObservedObject var operationState: EditingOperationState
    @Binding var validationMessage: String?
    let onChangeSpeed: (VideoSpeedRequest) -> Void

    @AppStorage("speedPreset") private var speedPresetRaw = SpeedPreset.x1_0.rawValue
    @AppStorage("speedCustomValue") private var speedCustomValue = "1.0"
    @AppStorage("speedAudioMode") private var speedAudioModeRaw = SpeedAudioMode.keep.rawValue

    private var controlsDisabled: Bool {
        inputURL == nil || operationState.isRunning
    }

    private var speedPreset: SpeedPreset {
        get { SpeedPreset(rawValue: speedPresetRaw) ?? .x1_0 }
        nonmutating set { speedPresetRaw = newValue.rawValue }
    }

    private var speedAudioMode: SpeedAudioMode {
        get { SpeedAudioMode(rawValue: speedAudioModeRaw) ?? .keep }
        nonmutating set { speedAudioModeRaw = newValue.rawValue }
    }

    var body: some View {
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
