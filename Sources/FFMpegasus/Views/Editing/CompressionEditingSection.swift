import FFMpegasusCore
import SwiftUI
import UniformTypeIdentifiers

struct CompressionEditingSection: View {
    let inputURL: URL?
    let duration: TimeInterval
    let metadata: VideoMetadata?
    @ObservedObject var operationState: EditingOperationState
    @Binding var validationMessage: String?
    let onCompress: (CompressionRequest) -> Void

    @AppStorage("compressionQuality") private var compressionQualityRaw = CompressionQuality.balanced.rawValue
    @AppStorage("compressionCustomCRF") private var compressionCustomCRF = 24
    @AppStorage("compressionEncoderPreset") private var compressionEncoderPresetRaw = EncoderPreset.medium.rawValue
    @AppStorage("compressionResolution") private var compressionResolutionRaw = OutputResolution.p720.rawValue
    @AppStorage("compressionCustomHeight") private var compressionCustomHeight = "720"
    @AppStorage("compressionAudioMode") private var compressionAudioModeRaw = CompressionAudioMode.keep.rawValue

    private var controlsDisabled: Bool {
        inputURL == nil || operationState.isRunning
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

    var body: some View {
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
}
