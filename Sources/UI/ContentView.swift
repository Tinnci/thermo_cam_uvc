import SwiftUI

struct ContentView: View {
    @State var controller = CaptureSessionController()
    @AppStorage("autoStartCapture") var autoStartCapture = false
    @AppStorage("showDiagnosticsPanel") var showDiagnosticsPanel = true
    @AppStorage("showFallbacksPanel") var showFallbacksPanel = true
    @Environment(\.openSettings) private var openSettings
    @State private var didBootstrap = false

    var body: some View {
        HStack(spacing: 0) {
            previewPane

            Divider()

            controlPane
                .frame(width: 390)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 1040, minHeight: 650)
        .onAppear {
            guard !didBootstrap else {
                return
            }

            didBootstrap = true
            controller.bootstrap()

            if autoStartCapture {
                controller.start()
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    toggleCapture()
                } label: {
                    Label(
                        controller.isRunning ? L10n.tr("Stop") : L10n.tr("Start"),
                        systemImage: controller.isRunning ? "stop.fill" : "play.fill"
                    )
                }
                .disabled(controller.devices.isEmpty)

                Button {
                    controller.saveCurrentFrame()
                } label: {
                    Label("Save Frame", systemImage: "camera.fill")
                }
                .disabled(controller.diagnostics.totalFrames == 0)

                Button {
                    controller.toggleRecording()
                } label: {
                    Label(
                        controller.isRecording ? L10n.tr("Stop Recording") : L10n.tr("Record"),
                        systemImage: controller.isRecording ? "stop.circle.fill" : "record.circle"
                    )
                }
                .disabled(!controller.isRunning || !controller.recordingAvailable)

                Button {
                    controller.refreshDevices()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(controller.isRunning)

                Button {
                    openSettings()
                } label: {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
            }
        }
        .focusedSceneValue(\.captureCommandActions, CaptureCommandActions(
            toggleCapture: toggleCapture,
            stopCapture: controller.stop,
            refreshDevices: controller.refreshDevices,
            applyAutoControls: controller.applyAutoControls,
            saveCurrentFrame: controller.saveCurrentFrame,
            toggleRecording: controller.toggleRecording,
            refreshUSBTopology: controller.refreshUSBTopology,
            enterPrivateControlMode: controller.enterPrivateControlMode
        ))
    }

    func toggleCapture() {
        if controller.isRunning {
            controller.stop()
        } else {
            controller.start()
        }
    }
}
