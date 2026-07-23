import Foundation

struct TestAutomationConfiguration: Equatable {
    let processSmokeMode: Bool
    let nativeXCUIMode: Bool
    let resetDefaults: Bool
    let fixtureURL: URL?
    let frameOutputURL: URL?
    let gifOutputURL: URL?
    let resultURL: URL?
    let quitAfterAutomation: Bool

    var isEnabled: Bool {
        processSmokeMode || nativeXCUIMode
    }

    static func current(environment: [String: String] = ProcessInfo.processInfo.environment) -> TestAutomationConfiguration {
        let processSmokeMode = environment["FFMPEGASUS_UI_TEST_MODE"] == "1"
        let nativeXCUIMode = environment["FFMPEGASUS_XCUITEST_MODE"] == "1"

        return TestAutomationConfiguration(
            processSmokeMode: processSmokeMode,
            nativeXCUIMode: nativeXCUIMode,
            resetDefaults: environment["FFMPEGASUS_UI_TEST_RESET_DEFAULTS"] == "1"
                || environment["FFMPEGASUS_XCUITEST_RESET_DEFAULTS"] == "1",
            fixtureURL: Self.url(from: environment["FFMPEGASUS_UI_TEST_FIXTURE"])
                ?? Self.url(from: environment["FFMPEGASUS_XCUITEST_FIXTURE"]),
            frameOutputURL: Self.url(from: environment["FFMPEGASUS_UI_TEST_FRAME_OUTPUT"])
                ?? Self.url(from: environment["FFMPEGASUS_XCUITEST_FRAME_OUTPUT"]),
            gifOutputURL: Self.url(from: environment["FFMPEGASUS_UI_TEST_GIF_OUTPUT"])
                ?? Self.url(from: environment["FFMPEGASUS_XCUITEST_GIF_OUTPUT"]),
            resultURL: Self.url(from: environment["FFMPEGASUS_UI_TEST_RESULT"]),
            quitAfterAutomation: environment["FFMPEGASUS_UI_TEST_QUIT_AFTER"] == "1"
        )
    }

    private static func url(from path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }
}
