import FFMpegasusCore
import SwiftUI

struct EditingInlineOperationStatus: View {
    @ObservedObject var operationState: EditingOperationState

    var body: some View {
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
}
