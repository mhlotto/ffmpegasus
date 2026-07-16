import AVFoundation
import FFMpegasusCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppViewModel: ObservableObject {
    @AppStorage("ffmpegPath") var ffmpegPath = FFmpegRunner.defaultPath
    @AppStorage("ffprobePath") var ffprobePath = FFprobeRunner.defaultPath

    @Published var videoURL: URL?
    @Published var player: AVPlayer?
    @Published var metadata: VideoMetadata?
    @Published var metadataMessage: String?
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isPlaying = false

    private var timeObserver: Any?

    var fileName: String {
        videoURL?.lastPathComponent ?? "No video open"
    }

    func openVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie, UTType(filenameExtension: "mkv")].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadVideo(url)
    }

    func loadVideo(_ url: URL) {
        closeVideo()
        videoURL = url
        metadataMessage = "Loading metadata"

        let player = AVPlayer(url: url)
        self.player = player
        attachTimeObserver(to: player)

        Task {
            do {
                let loadedMetadata = try await FFprobeRunner().loadMetadata(ffprobePath: ffprobePath, inputURL: url)
                metadata = loadedMetadata
                duration = loadedMetadata.duration
                metadataMessage = nil
            } catch {
                metadata = nil
                metadataMessage = error.localizedDescription
                let assetDuration = try? await AVURLAsset(url: url).load(.duration).seconds
                duration = assetDuration ?? 0
            }
        }
    }

    func closeVideo() {
        if let player, let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        player?.pause()
        player = nil
        timeObserver = nil
        videoURL = nil
        metadata = nil
        metadataMessage = nil
        currentTime = 0
        duration = 0
        isPlaying = false
    }

    func play() {
        player?.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func stop() {
        player?.pause()
        player?.seek(to: .zero)
        currentTime = 0
        isPlaying = false
    }

    func seek(to seconds: TimeInterval) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = seconds
    }

    private func attachTimeObserver(to player: AVPlayer) {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                self.currentTime = time.seconds.isFinite ? time.seconds : 0
            }
        }
    }
}

@MainActor
final class EditingOperationController: ObservableObject {
    private let editingService = VideoEditingService()

    func start(ffmpegPath: String, ffprobePath: String, request: EditingRequest, state: EditingOperationState) {
        Task {
            await editingService.run(ffmpegPath: ffmpegPath, ffprobePath: ffprobePath, request: request, state: state)
        }
    }

    func removeAudio(ffmpegPath: String, request: RemoveAudioRequest, state: EditingOperationState) {
        Task {
            await editingService.runRemoveAudio(ffmpegPath: ffmpegPath, request: request, state: state)
        }
    }

    func compress(ffmpegPath: String, ffprobePath: String, request: CompressionRequest, state: EditingOperationState) {
        Task {
            await editingService.runCompression(ffmpegPath: ffmpegPath, ffprobePath: ffprobePath, request: request, state: state)
        }
    }

    func transform(ffmpegPath: String, ffprobePath: String, request: VideoTransformRequest, state: EditingOperationState) {
        Task {
            await editingService.runTransform(ffmpegPath: ffmpegPath, ffprobePath: ffprobePath, request: request, state: state)
        }
    }

    func exportPlan(ffmpegPath: String, ffprobePath: String, plan: VideoEditPlan, state: EditingOperationState) {
        Task {
            await editingService.runEditPlan(ffmpegPath: ffmpegPath, ffprobePath: ffprobePath, plan: plan, state: state)
        }
    }

    func changeSpeed(ffmpegPath: String, ffprobePath: String, request: VideoSpeedRequest, state: EditingOperationState) {
        Task {
            await editingService.runSpeedChange(ffmpegPath: ffmpegPath, ffprobePath: ffprobePath, request: request, state: state)
        }
    }

    func exportFrame(ffmpegPath: String, request: FrameExportRequest, state: EditingOperationState) {
        Task {
            await editingService.runFrameExport(ffmpegPath: ffmpegPath, request: request, state: state)
        }
    }

    func exportFramesAtIntervals(ffmpegPath: String, request: IntervalFrameExportRequest, state: EditingOperationState) {
        Task {
            await editingService.runIntervalFrameExport(ffmpegPath: ffmpegPath, request: request, state: state)
        }
    }

    func cancel(state: EditingOperationState) {
        editingService.requestCancellation(state: state)
    }
}

struct ContentView: View {
    @StateObject private var model = AppViewModel()
    @StateObject private var operationState = EditingOperationState()
    @StateObject private var editingController = EditingOperationController()

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VideoPlayerView(player: model.player)
                    PlaybackControlsView(
                        hasVideo: model.videoURL != nil,
                        isPlaying: model.isPlaying,
                        currentTime: model.currentTime,
                        duration: model.duration,
                        onPlay: model.play,
                        onPause: model.pause,
                        onStop: model.stop,
                        onSeek: model.seek(to:)
                    )
                    metadataSection
                    EditingView(
                        inputURL: model.videoURL,
                        duration: model.duration,
                        metadata: model.metadata,
                        operationState: operationState,
                        onStart: startEditing,
                        onRemoveAudio: startRemoveAudio,
                        onCompress: startCompression,
                        onTransform: startTransform,
                        onExportPlan: startEditPlanExport,
                        onChangeSpeed: startSpeedChange,
                        onExportFrame: startFrameExport,
                        onExportFramesAtIntervals: startIntervalFrameExport,
                        currentPlaybackTime: currentPlaybackTime,
                        onCancel: { editingController.cancel(state: operationState) }
                    )
                    OperationProgressView(state: operationState, onCancel: { editingController.cancel(state: operationState) })
                }
                .padding(20)
            }
        }
    }

    private var toolbar: some View {
        HStack {
            Button {
                model.openVideo()
            } label: {
                Label("Open", systemImage: "folder")
            }

            Button {
                model.closeVideo()
            } label: {
                Label("Close", systemImage: "xmark.circle")
            }
            .disabled(model.videoURL == nil || operationState.isRunning)

            Spacer()

            Text(model.fileName)
                .font(.headline)
                .lineLimit(1)
        }
        .padding(12)
        .background(.bar)
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Metadata")
                .font(.headline)

            if let metadata = model.metadata {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                    GridRow { Text("Duration"); Text(TimeFormatting.clockTime(metadata.duration)) }
                    GridRow { Text("Dimensions"); Text(metadata.dimensionsText) }
                    GridRow { Text("Video codec"); Text(metadata.videoCodec ?? "Unknown") }
                    GridRow { Text("Audio codec"); Text(metadata.audioCodec ?? "None detected") }
                    GridRow {
                        Text("Frame rate")
                        Text(metadata.frameRate.map { String(format: "%.3f fps", $0) } ?? "Unknown")
                    }
                }
            } else {
                Text(model.metadataMessage ?? "Open a video to inspect metadata.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func startEditing(_ request: EditingRequest) {
        let ffmpegPath = model.ffmpegPath
        let ffprobePath = model.ffprobePath
        let operationState = operationState
        editingController.start(ffmpegPath: ffmpegPath, ffprobePath: ffprobePath, request: request, state: operationState)
    }

    private func startRemoveAudio(_ request: RemoveAudioRequest) {
        let ffmpegPath = model.ffmpegPath
        let operationState = operationState
        editingController.removeAudio(ffmpegPath: ffmpegPath, request: request, state: operationState)
    }

    private func startCompression(_ request: CompressionRequest) {
        editingController.compress(ffmpegPath: model.ffmpegPath, ffprobePath: model.ffprobePath, request: request, state: operationState)
    }

    private func startTransform(_ request: VideoTransformRequest) {
        editingController.transform(ffmpegPath: model.ffmpegPath, ffprobePath: model.ffprobePath, request: request, state: operationState)
    }

    private func startEditPlanExport(_ plan: VideoEditPlan) {
        editingController.exportPlan(ffmpegPath: model.ffmpegPath, ffprobePath: model.ffprobePath, plan: plan, state: operationState)
    }

    private func startSpeedChange(_ request: VideoSpeedRequest) {
        editingController.changeSpeed(ffmpegPath: model.ffmpegPath, ffprobePath: model.ffprobePath, request: request, state: operationState)
    }

    private func startFrameExport(_ request: FrameExportRequest) {
        editingController.exportFrame(ffmpegPath: model.ffmpegPath, request: request, state: operationState)
    }

    private func startIntervalFrameExport(_ request: IntervalFrameExportRequest) {
        editingController.exportFramesAtIntervals(ffmpegPath: model.ffmpegPath, request: request, state: operationState)
    }

    private func currentPlaybackTime() -> TimeInterval {
        let seconds = model.player?.currentTime().seconds ?? model.currentTime
        return seconds.isFinite ? seconds : model.currentTime
    }
}
