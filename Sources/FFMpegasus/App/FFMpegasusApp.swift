import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = ProcessInfo.processInfo.environment
        if environment["FFMPEGASUS_UI_TEST_RESET_DEFAULTS"] == "1"
            || environment["FFMPEGASUS_XCUITEST_RESET_DEFAULTS"] == "1" {
            [
                "ffmpegPath",
                "ffprobePath",
                "trimExecutionMode",
                "compressionQuality",
                "compressionCustomCRF",
                "compressionEncoderPreset",
                "compressionResolution",
                "compressionCustomHeight",
                "compressionAudioMode",
                "transformRotation",
                "transformFlipHorizontal",
                "transformFlipVertical",
                "speedPreset",
                "speedCustomValue",
                "speedAudioMode",
                "frameImageFormat",
                "frameJPEGQualityPreset",
                "frameCustomJPEGQuality",
                "intervalFramePreset",
                "intervalFrameCustomSeconds",
                "intervalFrameRangeMode"
            ].forEach { UserDefaults.standard.removeObject(forKey: $0) }
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }
}

@main
struct FFMpegasusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 980, minHeight: 720)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
        }
    }
}
