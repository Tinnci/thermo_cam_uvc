import SwiftUI

struct SettingsView: View {
    @AppStorage("autoStartCapture") private var autoStartCapture = false
    @AppStorage("showDiagnosticsPanel") private var showDiagnosticsPanel = true
    @AppStorage("showFallbacksPanel") private var showFallbacksPanel = true

    var body: some View {
        Form {
            Section("Capture") {
                Toggle("Start capture on launch", isOn: $autoStartCapture)
            }

            Section("Panels") {
                Toggle("Diagnostics", isOn: $showDiagnosticsPanel)
                Toggle("Fallbacks", isOn: $showFallbacksPanel)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 420)
    }
}
