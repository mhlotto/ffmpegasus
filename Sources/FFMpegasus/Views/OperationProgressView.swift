import FFMpegasusCore
import AppKit
import SwiftUI

struct OperationProgressView: View {
    @ObservedObject var state: EditingOperationState
    let onCancel: () -> Void
    @State private var now = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Output")
                .font(.headline)
                .accessibilityIdentifier("operation.progress")

            HStack {
                if let progress = state.progress {
                    ProgressView(value: progress)
                        .frame(maxWidth: 360)
                } else if state.isRunning {
                    ProgressView()
                        .frame(maxWidth: 180)
                } else {
                    ProgressView(value: 0)
                        .frame(maxWidth: 360)
                }

                Text(state.status)
                    .foregroundStyle(statusColor)
                    .accessibilityIdentifier("operation.status")

                Button {
                    onCancel()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
                .disabled(!state.isRunning)
                .accessibilityIdentifier("operation.cancel")
            }

            if let message = state.message {
                Text(message)
                    .foregroundStyle(messageColor)
                    .accessibilityIdentifier("operation.message")
            }

            if state.isRunning, let lastActivityAt = state.diagnostics.lastActivityAt, now.timeIntervalSince(lastActivityAt) > 10 {
                Text("FFmpeg is still running but has produced no recent output.")
                    .foregroundStyle(.orange)
            }

            if let outputURL = state.outputURL {
                Text(outputURL.path)
                    .font(.callout)
                    .textSelection(.enabled)

                HStack {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                    } label: {
                        Label("Reveal in Finder", systemImage: "magnifyingglass")
                    }
                    .accessibilityIdentifier("operation.revealOutput")

                    Button {
                        NSWorkspace.shared.open(outputURL)
                    } label: {
                        Label("Open Output", systemImage: "play.rectangle")
                    }
                    .accessibilityIdentifier("operation.openOutput")
                }
            }

            if shouldShowDiagnostics {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Diagnostics")
                        .font(.subheadline)
                        .bold()

                    Text(diagnosticsText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            if state.isRunning {
                now = date
            }
        }
    }

    private var statusColor: Color {
        switch state.phase.presentationKind {
        case .failure:
            .red
        case .success:
            .green
        case .cancelled:
            .secondary
        case .running:
            .accentColor
        case .neutral:
            .secondary
        }
    }

    private var messageColor: Color {
        switch state.phase.presentationKind {
        case .failure:
            .red
        case .cancelled:
            .secondary
        default:
            .primary
        }
    }

    private var shouldShowDiagnostics: Bool {
        switch state.phase {
        case .failed:
            true
        default:
            !state.diagnostics.stderr.isEmpty
        }
    }

    private var diagnosticsText: String {
        let arguments = state.diagnostics.arguments
            .enumerated()
            .map { "\($0.offset): \($0.element)" }
            .joined(separator: "\n")

        return """
        Process ID:
        \(state.diagnostics.processIdentifier.map(String.init) ?? "(not started)")

        Started:
        \(state.diagnostics.startedAt.map(String.init(describing:)) ?? "(unknown)")

        Last activity:
        \(state.diagnostics.lastActivityAt.map(String.init(describing:)) ?? "(unknown)")

        FFmpeg path:
        \(state.diagnostics.ffmpegPath)

        Arguments:
        \(arguments.isEmpty ? "(not constructed)" : arguments)

        stderr:
        \(state.diagnostics.stderr.isEmpty ? (state.diagnostics.stderrTail.isEmpty ? "(empty)" : state.diagnostics.stderrTail) : state.diagnostics.stderr)
        """
    }
}
