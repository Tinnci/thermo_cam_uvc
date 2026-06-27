import SwiftUI

struct SettingsView: View {
    @AppStorage("autoStartCapture") private var autoStartCapture = false
    @AppStorage("showDiagnosticsPanel") private var showDiagnosticsPanel = true
    @AppStorage("showFallbacksPanel") private var showFallbacksPanel = true

    var body: some View {
        Form {
            Section(L10n.tr("Capture")) {
                Toggle(L10n.tr("Start capture on launch"), isOn: $autoStartCapture)
            }

            Section(L10n.tr("Panels")) {
                Toggle(L10n.tr("Diagnostics"), isOn: $showDiagnosticsPanel)
                Toggle(L10n.tr("Fallbacks"), isOn: $showFallbacksPanel)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 420)
    }
}
