
<p align="center">
  <img src="app/src/main/res/drawable-nodpi/snooze_splash_full.png" alt="Snooze Reviews splash artwork" width="240">
</p>

# ffmpegasus

experiment in ui wrapper around ffmpeg executable

## Test commands

```bash
make fixtures
make fixtures-validate
swift test
swift build
make ui-test
make xcui-test
```

`make ui-test` runs the SwiftPM process-driven GUI smoke tests. `make xcui-test`
runs the native macOS XCUITest suite in `FFMpegasusXCUITests.xcodeproj`; that
project is only a thin host around the Swift package, which remains the
authoritative source definition.

Native XCUITests require full Xcode, a logged-in macOS GUI session, FFmpeg and
FFprobe for fixtures, and local permission for Xcode's UI testing runner to
control the app through accessibility.

## Playback scrubbing policy

Live timeline scrubbing uses throttled preview seeks so slider updates coalesce
instead of building a seek queue. The previous policy was a 75 ms preview seek
cadence with 0.075 seconds of tolerance. The current policy uses the smoother
candidate: 50 ms cadence with 0.05 seconds of preview tolerance.

Only preview seeks use this looser policy. The final seek after releasing the
slider remains the accurate zero-tolerance seek, playback resumes only when it
was playing before scrubbing, and stale seek completions remain generation
guarded.
