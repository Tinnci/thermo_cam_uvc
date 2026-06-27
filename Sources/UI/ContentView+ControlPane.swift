import SwiftUI

extension ContentView {
    var controlPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                captureControls
                mediaControls
                configurationSummary
                if showDiagnosticsPanel {
                    diagnostics
                }
                thermalData
                roiPanel
                privateControlPanel
                advancedFeatures
                controlAvailability
                if showFallbacksPanel {
                    fallbackSummary
                }
            }
            .padding(18)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ThermoCam UVC")
                .font(.title2.weight(.semibold))
            Text("AVFoundation capture")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var captureControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Device", selection: Binding(
                get: { controller.selectedDeviceID ?? "" },
                set: { controller.selectDevice($0) }
            )) {
                if controller.devices.isEmpty {
                    Text("No camera").tag("")
                }

                ForEach(controller.devices) { device in
                    Text(device.label).tag(device.id)
                }
            }
            .disabled(controller.isRunning)

            Picker("Format", selection: Binding(
                get: { controller.selectedFormatID ?? "" },
                set: { controller.selectFormat($0) }
            )) {
                if controller.formats.isEmpty {
                    Text("No format").tag("")
                }

                ForEach(controller.formats) { format in
                    Text(format.label).tag(format.id)
                }
            }
            .disabled(controller.isRunning || controller.formats.isEmpty)

            HStack(spacing: 10) {
                Button {
                    toggleCapture()
                } label: {
                    Label(
                        controller.isRunning ? L10n.tr("Stop") : L10n.tr("Start"),
                        systemImage: controller.isRunning ? "stop.fill" : "play.fill"
                    )
                }
                .keyboardShortcut(.space, modifiers: [])
                .buttonStyle(.borderedProminent)
                .disabled(controller.devices.isEmpty)

                Button {
                    controller.refreshDevices()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(controller.isRunning)

                Button {
                    controller.applyAutoControls()
                } label: {
                    Label("Auto", systemImage: "slider.horizontal.3")
                }
                .disabled(controller.selectedDeviceID == nil)
            }
        }
    }

    private var mediaControls: some View {
        Panel(title: "Media") {
            HStack(spacing: 10) {
                Button {
                    controller.saveCurrentFrame()
                } label: {
                    Label("Save Frame", systemImage: "camera.fill")
                }
                .disabled(!controller.isRunning)

                Button {
                    controller.toggleRecording()
                } label: {
                    Label(
                        controller.isRecording ? L10n.tr("Stop Recording") : L10n.tr("Record"),
                        systemImage: controller.isRecording ? "stop.circle.fill" : "record.circle"
                    )
                }
                .disabled(!controller.isRunning || !controller.recordingAvailable)
            }

            DiagnosticRow(title: "Photo", value: controller.photoSaveStatus)
            DiagnosticRow(title: "Recording", value: controller.recordingStatus)
        }
    }
}
