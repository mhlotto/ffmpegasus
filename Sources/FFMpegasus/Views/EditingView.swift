import FFMpegasusCore
import SwiftUI
import UniformTypeIdentifiers

struct EditingView: View {
    let inputURL: URL?
    let duration: TimeInterval
    @ObservedObject var operationState: EditingOperationState
    let onStart: (EditingRequest) -> Void
    let onCancel: () -> Void

    @State private var mode: EditingMode = .trimStart
    @State private var startSeconds = "0"
    @State private var endSeconds = "0"
    @State private var validationMessage: String?
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

            if let validationMessage {
                Text(validationMessage)
                    .foregroundStyle(.red)
            }
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
        panel.allowedContentTypes = [UTType(filenameExtension: inputURL.pathExtension) ?? .movie]
        panel.nameFieldStringValue = defaultOutputName(for: inputURL)

        guard panel.runModal() == .OK, let outputURL = panel.url else { return }

        let request = EditingRequest(
            inputURL: inputURL,
            outputURL: outputURL,
            sourceDuration: duration,
            removeStartSeconds: start,
            removeEndSeconds: end,
            mode: mode,
            method: .streamCopy
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
        let base = inputURL.deletingPathExtension().lastPathComponent
        let ext = inputURL.pathExtension.isEmpty ? "mp4" : inputURL.pathExtension
        return "\(base)-trimmed.\(ext)"
    }
}
