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
    @Published private(set) var timeline = PlaybackTimelineState()

    private var timeObserver: Any?
    private weak var timeObserverPlayer: AVPlayer?
    private var itemStatusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var shouldResumeAfterScrub = false
    private var pendingLivePreviewSeconds: TimeInterval?
    private var livePreviewTask: Task<Void, Never>?
    private var livePreviewSeekInFlight = false
    private let liveScrubbingPolicy = PlaybackScrubbingPolicy.default
    #if DEBUG
    private(set) var liveScrubbingDiagnostics = PlaybackScrubbingDiagnostics()
    #endif

    var fileName: String {
        videoURL?.lastPathComponent ?? "No video open"
    }

    var currentTime: TimeInterval { timeline.displayedTimeSeconds }
    var committedTime: TimeInterval { timeline.committedTimeSeconds }
    var duration: TimeInterval { timeline.durationSeconds }
    var isPlaying: Bool { timeline.isPlaying }
    var isSeekingOrScrubbing: Bool {
        timeline.hasPendingSeek || timeline.isScrubbing || livePreviewSeekInFlight || livePreviewTask != nil
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
        timeline.open(duration: 0)

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        observeItem(item)
        attachTimeObserver(to: player)

        Task {
            do {
                let loadedMetadata = try await FFprobeRunner().loadMetadata(ffprobePath: ffprobePath, inputURL: url)
                guard self.videoURL == url else { return }
                metadata = loadedMetadata
                timeline.setDuration(loadedMetadata.duration)
                metadataMessage = nil
            } catch {
                guard self.videoURL == url else { return }
                metadata = nil
                metadataMessage = error.localizedDescription
                let assetDuration = try? await AVURLAsset(url: url).load(.duration).seconds
                timeline.setDuration(assetDuration ?? 0)
            }
        }
    }

    func closeVideo() {
        removeTimeObserver()
        itemStatusObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        videoURL = nil
        metadata = nil
        metadataMessage = nil
        shouldResumeAfterScrub = false
        cancelLivePreviewSeekScheduling()
        livePreviewSeekInFlight = false
        timeline.close()
    }

    func play() {
        guard let player else { return }
        if timeline.durationSeconds > 0, timeline.committedTimeSeconds >= timeline.durationSeconds - 0.05 {
            let seek = timeline.beginSeek(to: 0)
            player.seek(to: cmTime(seek.target), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    guard self.timeline.completeSeek(generation: seek.generation, actualTime: 0) else { return }
                    self.player?.play()
                    self.timeline.setPlaying(true)
                }
            }
            return
        }
        player.play()
        timeline.setPlaying(true)
    }

    func pause() {
        player?.pause()
        timeline.setPlaying(false)
    }

    func stop() {
        guard let player else {
            timeline.close()
            return
        }
        player.pause()
        cancelLivePreviewSeekScheduling()
        livePreviewSeekInFlight = false
        let seek = timeline.stop()
        player.seek(to: seekTime(seek.target), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                _ = self?.timeline.completeSeek(generation: seek.generation, actualTime: 0)
            }
        }
    }

    func seek(to seconds: TimeInterval) {
        guard let player else { return }
        let seek = timeline.beginSeek(to: seconds)
        player.seek(to: seekTime(seek.target), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                _ = self?.timeline.completeSeek(generation: seek.generation, actualTime: seek.target)
            }
        }
    }

    func beginScrubbing() {
        cancelLivePreviewSeekScheduling()
        pendingLivePreviewSeconds = nil
        livePreviewSeekInFlight = false
        shouldResumeAfterScrub = timeline.isPlaying
        player?.pause()
        timeline.beginScrubbing()
    }

    func updateScrubPosition(_ seconds: TimeInterval) {
        timeline.updateScrubPosition(seconds)
        guard timeline.isScrubbing else { return }
        #if DEBUG
        let replacedPendingTarget = pendingLivePreviewSeconds != nil
        #endif
        pendingLivePreviewSeconds = timeline.scrubTimeSeconds
        #if DEBUG
        liveScrubbingDiagnostics.recordSliderUpdate(replacedPendingTarget: replacedPendingTarget)
        liveScrubbingDiagnostics.recordPendingDepth(
            inFlight: livePreviewSeekInFlight,
            hasPendingTarget: pendingLivePreviewSeconds != nil || livePreviewTask != nil
        )
        #endif
        scheduleLivePreviewSeek()
    }

    func endScrubbing() {
        cancelLivePreviewSeekScheduling()
        guard let player, let seek = timeline.beginSeekFromScrub() else { return }
        pendingLivePreviewSeconds = nil
        let targetTime = seekTime(seek.target)
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.timeline.completeSeek(generation: seek.generation, actualTime: seek.target) else { return }
                if self.shouldResumeAfterScrub {
                    self.player?.play()
                    self.timeline.setPlaying(true)
                }
                self.shouldResumeAfterScrub = false
            }
        }
    }

    private func scheduleLivePreviewSeek() {
        guard livePreviewTask == nil, !livePreviewSeekInFlight else { return }
        livePreviewTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: liveScrubbingPolicy.previewSeekThrottleNanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.livePreviewTask = nil
                self.performLivePreviewSeek()
            }
        }
    }

    private func performLivePreviewSeek() {
        guard let player, timeline.isScrubbing, let target = pendingLivePreviewSeconds else { return }
        pendingLivePreviewSeconds = nil
        guard let seek = timeline.beginLivePreviewSeek(to: target) else { return }
        livePreviewSeekInFlight = true
        #if DEBUG
        liveScrubbingDiagnostics.recordPreviewSeekSubmitted(
            inFlight: livePreviewSeekInFlight,
            hasPendingTarget: pendingLivePreviewSeconds != nil || livePreviewTask != nil
        )
        #endif
        let tolerance = CMTime(seconds: liveScrubbingPolicy.previewSeekToleranceSeconds, preferredTimescale: 600)
        player.seek(to: seekTime(seek.target), toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.livePreviewSeekInFlight = false
                let completed = self.timeline.completeLivePreviewSeek(generation: seek.generation)
                #if DEBUG
                self.liveScrubbingDiagnostics.recordPreviewSeekCompleted(
                    stale: !completed,
                    inFlight: self.livePreviewSeekInFlight,
                    hasPendingTarget: self.pendingLivePreviewSeconds != nil || self.livePreviewTask != nil
                )
                #endif
                if self.timeline.isScrubbing, self.pendingLivePreviewSeconds != nil {
                    self.scheduleLivePreviewSeek()
                }
            }
        }
    }

    private func cancelLivePreviewSeekScheduling() {
        livePreviewTask?.cancel()
        livePreviewTask = nil
        pendingLivePreviewSeconds = nil
    }

    private func attachTimeObserver(to player: AVPlayer) {
        removeTimeObserver()
        timeObserverPlayer = player
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                self.timeline.applyObserverTime(time.seconds)
            }
        }
    }

    private func removeTimeObserver() {
        if let timeObserver, let timeObserverPlayer {
            timeObserverPlayer.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        timeObserverPlayer = nil
    }

    private func observeItem(_ item: AVPlayerItem) {
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] observedItem, _ in
            Task { @MainActor in
                guard let self, self.player?.currentItem === observedItem else { return }
                self.timeline.setReadyForSeeking(observedItem.status == .readyToPlay)
                if observedItem.status == .readyToPlay {
                    let duration = observedItem.duration.seconds
                    if TimeFormatting.isSeekableDuration(duration) {
                        self.timeline.setDuration(duration)
                    }
                } else if observedItem.status == .failed {
                    self.metadataMessage = observedItem.error?.localizedDescription ?? "Playback item failed."
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.player?.currentItem === item else { return }
                self.timeline.applyObserverTime(self.timeline.durationSeconds)
                self.timeline.setPlaying(false)
            }
        }
    }

    private func cmTime(_ seconds: TimeInterval) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }

    private func seekTime(_ seconds: TimeInterval) -> CMTime {
        let clamped = TimeFormatting.clampedPlaybackTime(seconds, duration: timeline.durationSeconds)
        let safeEnd: TimeInterval
        if timeline.durationSeconds > 0, clamped >= timeline.durationSeconds {
            safeEnd = max(0, timeline.durationSeconds - 0.001)
        } else {
            safeEnd = clamped
        }
        return cmTime(safeEnd)
    }

    deinit {
        MainActor.assumeIsolated {
            if let timeObserver, let timeObserverPlayer {
                timeObserverPlayer.removeTimeObserver(timeObserver)
            }
            if let endObserver {
                NotificationCenter.default.removeObserver(endObserver)
            }
            livePreviewTask?.cancel()
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
    @State private var didRunUITestAutomation = false

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
                        canSeek: model.timeline.canSeek,
                        isScrubbing: model.timeline.isScrubbing,
                        isSeeking: model.timeline.isSeeking,
                        onPlay: model.play,
                        onPause: model.pause,
                        onStop: model.stop,
                        onBeginScrubbing: model.beginScrubbing,
                        onScrubChanged: model.updateScrubPosition(_:),
                        onEndScrubbing: model.endScrubbing
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
                        canExportCurrentFrame: !model.isSeekingOrScrubbing,
                        onCancel: { editingController.cancel(state: operationState) }
                    )
                    OperationProgressView(state: operationState, onCancel: { editingController.cancel(state: operationState) })
                }
                .padding(20)
            }
            .accessibilityIdentifier("main.content")
        }
        .task {
            await runXCUITestLaunchConfigurationIfNeeded()
            await runUITestAutomationIfNeeded()
        }
    }

    private var toolbar: some View {
        HStack {
            Button {
                model.openVideo()
            } label: {
                Label("Open", systemImage: "folder")
            }
            .accessibilityIdentifier("toolbar.open")

            Button {
                model.closeVideo()
            } label: {
                Label("Close", systemImage: "xmark.circle")
            }
            .disabled(model.videoURL == nil || operationState.isRunning)
            .accessibilityIdentifier("toolbar.close")

            Spacer()

            Text(model.fileName)
                .font(.headline)
                .lineLimit(1)
                .accessibilityIdentifier("toolbar.loadedFile")
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
        .accessibilityIdentifier("metadata.section")
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
        model.committedTime
    }

    private func runXCUITestLaunchConfigurationIfNeeded() async {
        guard !didRunUITestAutomation else { return }
        let environment = ProcessInfo.processInfo.environment
        guard environment["FFMPEGASUS_XCUITEST_MODE"] == "1" else { return }
        didRunUITestAutomation = true

        if let fixturePath = environment["FFMPEGASUS_XCUITEST_FIXTURE"], !fixturePath.isEmpty {
            model.loadVideo(URL(fileURLWithPath: fixturePath))
        }
    }

    private func runUITestAutomationIfNeeded() async {
        guard !didRunUITestAutomation else { return }
        let environment = ProcessInfo.processInfo.environment
        guard environment["FFMPEGASUS_UI_TEST_MODE"] == "1" else { return }
        didRunUITestAutomation = true

        var result: [String: Any] = [
            "launched": true,
            "mainContentPresent": true,
            "editingSections": [
                "Trim",
                "Remove Audio",
                "Combined Export",
                "Rotate / Flip",
                "Compress / Resize",
                "Change Speed",
                "Export Current Frame",
                "Export Frames at Intervals"
            ]
        ]

        if let fixturePath = environment["FFMPEGASUS_UI_TEST_FIXTURE"], !fixturePath.isEmpty {
            await runLoadedFixtureSmoke(fixturePath: fixturePath, environment: environment, result: &result)
        }

        if let resultPath = environment["FFMPEGASUS_UI_TEST_RESULT"] {
            writeUITestResult(result, to: URL(fileURLWithPath: resultPath))
        }

        if environment["FFMPEGASUS_UI_TEST_QUIT_AFTER"] == "1" {
            NSApp.terminate(nil)
        }
    }

    private func runLoadedFixtureSmoke(fixturePath: String, environment: [String: String], result: inout [String: Any]) async {
        let fixtureURL = URL(fileURLWithPath: fixturePath)
        model.loadVideo(fixtureURL)
        result["fixturePath"] = fixtureURL.path

        let metadataLoaded = await waitUntil(timeout: 8) {
            model.metadata != nil && model.duration > 0
        }
        result["fixtureLoaded"] = metadataLoaded
        result["loadedFile"] = model.fileName
        result["metadataVisible"] = model.metadata != nil
        result["duration"] = model.duration
        result["playbackControlsEnabled"] = model.videoURL != nil

        guard metadataLoaded else { return }

        let timelineAvailable = await waitUntil(timeout: 4) {
            model.timeline.canSeek
        }
        result["timelineAvailable"] = timelineAvailable

        model.play()
        let playbackAdvanced = await waitUntil(timeout: 4) {
            model.currentTime > 0.25
        }
        let playingTime = model.currentTime
        result["playbackAdvanced"] = playbackAdvanced

        model.pause()
        try? await Task.sleep(nanoseconds: 500_000_000)
        result["pauseStable"] = abs(model.currentTime - playingTime) < 0.5

        model.seek(to: min(2.0, max(0, model.duration - 0.5)))
        let seekChanged = await waitUntil(timeout: 4) {
            abs(model.committedTime - min(2.0, max(0, model.duration - 0.5))) < 0.35
        }
        result["seekChanged"] = seekChanged

        model.stop()
        let stopReset = await waitUntil(timeout: 4) {
            model.committedTime < 0.2
        }
        result["stopReset"] = stopReset

        if let outputPath = environment["FFMPEGASUS_UI_TEST_FRAME_OUTPUT"] {
            await runFrameExportSmoke(outputPath: outputPath, result: &result)
        }
    }

    private func runFrameExportSmoke(outputPath: String, result: inout [String: Any]) async {
        guard let inputURL = model.videoURL,
              let width = model.metadata?.width,
              let height = model.metadata?.height else {
            result["frameExportCompleted"] = false
            result["frameExportError"] = "Missing loaded input or metadata."
            return
        }

        let targetTime = min(1.25, max(0, model.duration - 0.25))
        model.seek(to: targetTime)
        _ = await waitUntil(timeout: 4) {
            abs(model.committedTime - targetTime) < 0.35
        }

        let outputURL = URL(fileURLWithPath: outputPath)
        let request = FrameExportRequest(
            inputURL: inputURL,
            outputURL: outputURL,
            timestampSeconds: model.committedTime,
            sourceDuration: model.duration,
            sourceDimensions: VideoDimensions(width: width, height: height),
            sourceRotationDegrees: model.metadata?.rotationDegrees,
            hasVideoStream: model.metadata?.videoCodec != nil,
            format: .png,
            jpegQuality: nil
        )

        editingController.exportFrame(ffmpegPath: model.ffmpegPath, request: request, state: operationState)
        let completed = await waitUntil(timeout: 10) {
            if case .completed = operationState.phase {
                return true
            }
            return false
        }
        result["frameExportCompleted"] = completed
        result["frameExportOutput"] = outputURL.path
        result["operationStatus"] = operationState.status
        result["operationMessage"] = operationState.message ?? ""
        result["frameExportOutputExists"] = FileManager.default.fileExists(atPath: outputURL.path)
        result["frameExportOutputSize"] = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber)?.uint64Value ?? 0
    }

    private func waitUntil(timeout: TimeInterval, condition: @escaping @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return condition()
    }

    private func writeUITestResult(_ result: [String: Any], to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("FFMpegasus UI test result write failed: \(error.localizedDescription)")
        }
    }
}
