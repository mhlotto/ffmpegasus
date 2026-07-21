import FFMpegasusCore
import SwiftUI
import UniformTypeIdentifiers

struct RemoveAudioEditingSection: View {
    let inputURL: URL?
    let duration: TimeInterval
    let metadata: VideoMetadata?
    @ObservedObject var operationState: EditingOperationState
    @Binding var validationMessage: String?
    let onRemoveAudio: (RemoveAudioRequest) -> Void

    private var controlsDisabled: Bool {
        inputURL == nil || operationState.isRunning
    }

    private var removeAudioDisabled: Bool {
        controlsDisabled || metadata?.videoCodec == nil || metadata?.audioCodec == nil
    }

    var body: some View {
        HStack {
            Button {
                chooseRemoveAudioOutputAndStart()
            } label: {
                Label(operationState.isRunning ? "Removing Audio..." : "Remove Audio", systemImage: "speaker.slash")
            }
            .disabled(removeAudioDisabled)
            .accessibilityIdentifier("editing.removeAudio")

            if metadata?.audioCodec == nil, inputURL != nil {
                Text("This video has no audio stream.")
                    .foregroundStyle(.secondary)
            }
        }
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
        panel.nameFieldStringValue = OutputFilename.mutedName(for: inputURL)

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
}
