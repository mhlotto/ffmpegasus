import FFMpegasusCore
import SwiftUI
import UniformTypeIdentifiers

struct TrimEditingSection: View {
    let inputURL: URL?
    let duration: TimeInterval
    let metadata: VideoMetadata?
    @ObservedObject var operationState: EditingOperationState
    @Binding var validationMessage: String?
    let onStart: (EditingRequest) -> Void
    let onCancel: () -> Void

    @State private var mode: EditingMode = .trimStart
    @State private var startSeconds = "0"
    @State private var endSeconds = "0"
    @AppStorage("trimExecutionMode") private var trimExecutionModeRaw = TrimExecutionMode.fast.rawValue
    @FocusState private var focusedField: TrimField?

    private enum TrimField {
        case start
        case end
    }

    private var controlsDisabled: Bool {
        inputURL == nil || operationState.isRunning
    }

    private var trimExecutionMode: TrimExecutionMode {
        get { TrimExecutionMode(rawValue: trimExecutionModeRaw) ?? .fast }
        nonmutating set { trimExecutionModeRaw = newValue.rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Editing")
                .font(.headline)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("editing.trim")

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

            Text("Stream-copy cuts are fast, but may align to keyframes and may not be frame-accurate.")
                .font(.callout)
                .foregroundStyle(.secondary)
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
        panel.nameFieldStringValue = OutputFilename.trimmedName(for: inputURL, mode: trimExecutionMode)

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
}
