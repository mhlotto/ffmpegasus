import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
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
