import FFMpegasusCore
import SwiftUI

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
    let onExportFrame: (FrameExportRequest) -> Void
    let onExportFramesAtIntervals: (IntervalFrameExportRequest) -> Void
    let onExportGIF: (GIFExportRequest) -> Void
    let currentPlaybackTime: () -> TimeInterval
    let canExportCurrentFrame: Bool
    let testAutomationFrameOutputURL: URL?
    let testAutomationGIFOutputURL: URL?
    let onCancel: () -> Void

    @State private var validationMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let validationMessage {
                Text(validationMessage)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("editing.validationMessage")

                Divider()
            }

            TrimEditingSection(
                inputURL: inputURL,
                duration: duration,
                metadata: metadata,
                operationState: operationState,
                validationMessage: $validationMessage,
                onStart: onStart,
                onCancel: onCancel
            )

            Divider()

            RemoveAudioEditingSection(
                inputURL: inputURL,
                duration: duration,
                metadata: metadata,
                operationState: operationState,
                validationMessage: $validationMessage,
                onRemoveAudio: onRemoveAudio
            )

            Divider()

            CombinedExportEditingSection(
                inputURL: inputURL,
                duration: duration,
                metadata: metadata,
                operationState: operationState,
                validationMessage: $validationMessage,
                onExportPlan: onExportPlan
            )

            Divider()

            TransformEditingSection(
                inputURL: inputURL,
                duration: duration,
                metadata: metadata,
                operationState: operationState,
                validationMessage: $validationMessage,
                onTransform: onTransform
            )

            Divider()

            CompressionEditingSection(
                inputURL: inputURL,
                duration: duration,
                metadata: metadata,
                operationState: operationState,
                validationMessage: $validationMessage,
                onCompress: onCompress
            )

            Divider()

            SpeedEditingSection(
                inputURL: inputURL,
                duration: duration,
                metadata: metadata,
                operationState: operationState,
                validationMessage: $validationMessage,
                onChangeSpeed: onChangeSpeed
            )

            Divider()

            FrameExportEditingSection(
                inputURL: inputURL,
                duration: duration,
                metadata: metadata,
                operationState: operationState,
                validationMessage: $validationMessage,
                currentPlaybackTime: currentPlaybackTime,
                canExportCurrentFrame: canExportCurrentFrame,
                testAutomationFrameOutputURL: testAutomationFrameOutputURL,
                onExportFrame: onExportFrame
            )

            Divider()

            IntervalFrameExportEditingSection(
                inputURL: inputURL,
                duration: duration,
                metadata: metadata,
                operationState: operationState,
                validationMessage: $validationMessage,
                onExportFramesAtIntervals: onExportFramesAtIntervals
            )

            Divider()

            GIFExportEditingSection(
                inputURL: inputURL,
                duration: duration,
                metadata: metadata,
                operationState: operationState,
                validationMessage: $validationMessage,
                testAutomationGIFOutputURL: testAutomationGIFOutputURL,
                onExportGIF: onExportGIF
            )
        }
    }
}
