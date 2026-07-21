
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
