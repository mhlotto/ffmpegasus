# Native XCUITests

These tests exercise the visible FFMpegasus macOS application through
`XCUIApplication` and the accessibility hierarchy. They complement, but do not
replace, the SwiftPM process-driven GUI smoke tests in `Tests/FFMpegasusGUITests`.

The Xcode project in `FFMpegasusXCUITests.xcodeproj` is intentionally narrow:

- `Package.swift` remains the authoritative source definition.
- The host app target runs `swift build --product FFMpegasus`.
- The host target assembles the SwiftPM executable into a temporary `.app` bundle.
- The XCUITest target launches that app and interacts with accessibility identifiers.

Run locally with:

```bash
make xcui-test
```

Requirements:

- Full Xcode selected with `xcode-select`.
- A logged-in macOS graphical user session.
- FFmpeg and FFprobe available for fixture generation and frame export.
- Generated fixtures under `Tests/Fixtures/generated/`.

The suite disables parallel execution by using one scheme invocation and one visible
application instance at a time. System Open and Save panels are intentionally not
automated in this initial layer; current-frame export uses a narrow test-only output
path environment variable after the real Export Current Frame button is clicked.
