import SwiftUI

@main
struct ThermoCamUVCApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .commands {
            CaptureCommands()
        }

        Settings {
            SettingsView()
        }
    }
}
