import FFMpegasusCore
import SwiftUI

struct SettingsView: View {
    @AppStorage("ffmpegPath") private var ffmpegPath = FFmpegRunner.defaultPath
    @AppStorage("ffprobePath") private var ffprobePath = FFprobeRunner.defaultPath

    @State private var ffmpegStatus = ""
    @State private var ffprobeStatus = ""
    @State private var isTestingFFmpeg = false
    @State private var isTestingFFprobe = false

    var body: some View {
        Form {
            executableSection(
                title: "FFmpeg",
                path: $ffmpegPath,
                status: ffmpegStatus,
                isTesting: isTestingFFmpeg,
                defaultPath: FFmpegRunner.defaultPath,
                selectAction: { selectExecutable(into: $ffmpegPath) },
                testAction: testFFmpeg
            )

            executableSection(
                title: "FFprobe",
                path: $ffprobePath,
                status: ffprobeStatus,
                isTesting: isTestingFFprobe,
                defaultPath: FFprobeRunner.defaultPath,
                selectAction: { selectExecutable(into: $ffprobePath) },
                testAction: testFFprobe
            )
        }
        .padding(20)
        .frame(width: 680)
    }

    private func executableSection(
        title: String,
        path: Binding<String>,
        status: String,
        isTesting: Bool,
        defaultPath: String,
        selectAction: @escaping () -> Void,
        testAction: @escaping () -> Void
    ) -> some View {
        Section(title) {
            TextField("\(title) path", text: path)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Select", action: selectAction)
                Button("Restore Default") {
                    path.wrappedValue = defaultPath
                }
                Button("Test", action: testAction)
                    .disabled(isTesting)
            }

            if !status.isEmpty {
                Text(status)
                    .font(.callout)
                    .textSelection(.enabled)
            }
        }
    }

    private func selectExecutable(into path: Binding<String>) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        path.wrappedValue = url.path
    }

    private func testFFmpeg() {
        isTestingFFmpeg = true
        ffmpegStatus = "Testing"
        Task {
            do {
                ffmpegStatus = try await FFmpegRunner().version(ffmpegPath: ffmpegPath)
            } catch {
                ffmpegStatus = error.localizedDescription
            }
            isTestingFFmpeg = false
        }
    }

    private func testFFprobe() {
        isTestingFFprobe = true
        ffprobeStatus = "Testing"
        Task {
            do {
                ffprobeStatus = try await FFprobeRunner().version(ffprobePath: ffprobePath)
            } catch {
                ffprobeStatus = error.localizedDescription
            }
            isTestingFFprobe = false
        }
    }
}
