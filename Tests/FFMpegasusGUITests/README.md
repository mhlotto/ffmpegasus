# FFMpegasus GUI Smoke Tests

The GUI smoke tests are a SwiftPM XCTest target that launches the built `FFMpegasus`
macOS executable. This keeps `Package.swift` authoritative and avoids adding a separate
Xcode project solely for UI smoke coverage.

The tests are disabled during ordinary `swift test` runs. Use:

```bash
make ui-test
```

`make ui-test` regenerates fixtures, builds the executable, and runs only
`FFMpegasusGUITests` with `FFMPEGASUS_RUN_GUI_TESTS=1`.

The application only enters automation mode when explicit `FFMPEGASUS_UI_TEST_*`
environment variables are present. Normal launches are unaffected.

Requirements:

- macOS with a logged-in graphical user session
- Swift/Xcode toolchain capable of building the package
- FFmpeg and FFprobe for fixture generation and the frame-export smoke
- Generated fixtures under `Tests/Fixtures/generated/`

The smoke tests use a temporary output directory and never modify shared fixtures.
Failure diagnostics are attached to the XCTest result as stdout, stderr, and the
application-written JSON smoke result when available.
