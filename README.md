# FFMpegasus

FFMpegasus is a native macOS SwiftUI desktop app that wraps FFmpeg and FFprobe for basic video playback, inspection, and lightweight export workflows. It is a development-stage project, not a polished production video editor.

## Features

- Open local MP4, MOV, MKV, and other AVFoundation/FFmpeg-readable videos.
- Play, pause, stop, seek, and scrub with an AVPlayer timeline.
- Inspect duration, dimensions, video codec, audio codec, frame rate, and rotation metadata through FFprobe.
- Export edits with FFmpeg:
  - Fast and Accurate trim
  - Remove Audio
  - Compress / Resize
  - Rotate / Flip
  - Change Speed
  - Combined Export
  - Export Current Frame
  - Export Frames at Intervals
- Show operation progress, diagnostics, cancellation, output verification, Reveal in Finder, and Open Output actions.
- Configure FFmpeg and FFprobe executable paths in Settings.

## Requirements

- macOS with SwiftUI and AVKit support.
- Apple Swift toolchain. The current local development toolchain is Apple Swift 6.3.2 on arm64 macOS.
- Full Xcode for native XCUITests.
- FFmpeg and FFprobe installed locally.

Default executable paths:

```text
/opt/homebrew/bin/ffmpeg
/opt/homebrew/bin/ffprobe
```

The app runs FFmpeg and FFprobe through `Foundation.Process` with argument arrays. It does not invoke shell command strings.

## Build And Run

```bash
swift build
swift run FFMpegasus
```

The repository also includes a Makefile:

```bash
make build
make run
make clean
```

## Tests

Core unit and optional FFmpeg-backed integration tests:

```bash
swift package clean
swift test
swift build
```

Optional FFmpeg integration tests skip when the required FFmpeg/FFprobe tools or encoders are unavailable.

## Fixtures

Synthetic media fixtures live under `Tests/Fixtures`. Generated media is not downloaded and is not third-party copyrighted content.

```bash
make fixtures
make fixtures-validate
make fixtures-clean
```

The fixture script generates and validates:

- standard landscape video with audio
- silent video
- portrait video
- rotation-metadata video
- variable-frame-rate video
- unusual-dimensions video
- frame-identifiable video

Generated fixture files are written to `Tests/Fixtures/generated/`. Tests treat fixtures as read-only and write outputs into temporary directories.

## GUI Smoke Tests

Process-driven GUI smoke tests launch the built SwiftPM executable with narrow test-only environment variables:

```bash
make ui-test
```

These tests verify launch, fixture loading, playback controls, timeline availability, editing-section presence, and one current-frame export. Normal app launches are unaffected when the `FFMPEGASUS_UI_TEST_*` variables are absent.

## Native XCUITests

Native macOS accessibility interaction tests live in `Tests/FFMpegasusXCUITests` and are hosted by the minimal `FFMpegasusXCUITests.xcodeproj`:

```bash
make xcui-test
```

The Xcode project is only a UI-test host around the Swift package. `Package.swift` remains the authoritative source definition.

XCUITests require:

- Full Xcode selected with `xcode-select`.
- A logged-in macOS GUI session.
- Permission for Xcode's UI testing runner to control the app through Accessibility, if macOS prompts for it.
- FFmpeg and FFprobe for fixture generation and export workflows.

System Open and Save panels are still treated as manual workflows in the automated UI suites. Test-only fixture and output-path injection is intentionally narrow.

## Playback Scrubbing Policy

Live timeline scrubbing uses throttled preview seeks so rapid slider input coalesces instead of building a seek queue. The retained comparison policy is 75 ms with 0.075 seconds of preview tolerance. The active policy is 50 ms with 0.05 seconds of preview tolerance.

Only preview seeks use that looser policy. The final seek after releasing the slider remains zero-tolerance, playback resumes only when it was playing before scrubbing, and stale seek completions are generation guarded.

## Development Notes

- FFmpeg command behavior is covered by pure command-construction tests.
- Media-output verification is handled after FFmpeg exits; the UI should not report completion until verification succeeds.
- Cancellation is a first-class operation state and should not be replaced by missing-output verification failures.
- Shared fixture generation should be recoverable: failed generation does not poison later retries, and deleted fixtures can be regenerated in the same test process.
