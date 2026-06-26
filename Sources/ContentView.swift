import SwiftUI

struct ContentView: View {
    @State private var controller = CaptureSessionController()
    @AppStorage("autoStartCapture") private var autoStartCapture = false
    @AppStorage("showDiagnosticsPanel") private var showDiagnosticsPanel = true
    @AppStorage("showFallbacksPanel") private var showFallbacksPanel = true
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
                        controller.isRunning ? "Stop" : "Start",
                        systemImage: controller.isRunning ? "stop.fill" : "play.fill"
                    )
                }
                .disabled(controller.devices.isEmpty)

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
                        controller.isRecording ? "Stop Recording" : "Record",
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

    private var previewPane: some View {
        ZStack {
            Color.black

            CameraPreviewView(session: controller.session)
                .opacity(controller.isRunning ? 1 : 0.35)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if shouldShowPreviewOverlay {
                VStack(spacing: 8) {
                    Image(systemName: previewStatusIcon)
                        .font(.system(size: 34, weight: .semibold))
                    Text(controller.statusMessage)
                        .font(.headline)
                    Text(previewStatusDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
                .padding(20)
                .foregroundStyle(.white)
            }
        }
    }

    private var controlPane: some View {
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
                        controller.isRunning ? "Stop" : "Start",
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
                        controller.isRecording ? "Stop Recording" : "Record",
                        systemImage: controller.isRecording ? "stop.circle.fill" : "record.circle"
                    )
                }
                .disabled(!controller.isRunning || !controller.recordingAvailable)
            }

            DiagnosticRow(title: "Photo", value: controller.photoSaveStatus)
            DiagnosticRow(title: "Recording", value: controller.recordingStatus)
        }
    }

    private var configurationSummary: some View {
        Panel(title: "Configuration") {
            DiagnosticRow(title: "Permission", value: controller.authorizationState.displayName)
            DiagnosticRow(title: "Requested", value: controller.activeConfiguration.requestedFormat)
            DiagnosticRow(title: "Active", value: controller.activeConfiguration.activeFormat)
            DiagnosticRow(title: "Output", value: controller.activeConfiguration.outputPixelFormat)
        }
    }

    private var diagnostics: some View {
        Panel(title: "Diagnostics") {
            DiagnosticRow(title: "Stream", value: controller.captureState.displayName)
            DiagnosticRow(title: "Frames", value: "\(controller.diagnostics.totalFrames)")
            DiagnosticRow(title: "Dropped", value: "\(controller.diagnostics.droppedFrames)")
            DiagnosticRow(title: "Measured FPS", value: String(format: "%.1f", controller.diagnostics.measuredFPS))
            DiagnosticRow(title: "Interval", value: String(format: "%.1f ms", controller.diagnostics.frameIntervalMS))
            DiagnosticRow(title: "Frame Size", value: controller.diagnostics.frameSize)
            DiagnosticRow(title: "Delivered", value: controller.diagnostics.deliveredPixelFormat)
            DiagnosticRow(title: "Metal", value: controller.diagnostics.metalStatus)
            DiagnosticRow(title: "Texture", value: controller.diagnostics.metalTexture)
        }
    }

    private var thermalData: some View {
        Panel(title: "Thermal Data") {
            DiagnosticRow(title: "Status", value: controller.thermalInspection.status)
            DiagnosticRow(title: "Frames", value: "\(controller.thermalInspection.inspectedFrames)")
            DiagnosticRow(title: "Matrix", value: controller.thermalInspection.matrixSize)
            Text(controller.thermalInspection.evidence)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var roiPanel: some View {
        Panel(title: "ROI Temperature") {
            Toggle("Enable ROI", isOn: Binding(
                get: { controller.roiEnabled },
                set: { controller.setROIEnabled($0) }
            ))

            roiSlider("X", value: \.roiXPercent, range: 0...95)
            roiSlider("Y", value: \.roiYPercent, range: 0...95)
            roiSlider("W", value: \.roiWidthPercent, range: 5...100)
            roiSlider("H", value: \.roiHeightPercent, range: 5...100)

            DiagnosticRow(title: "Status", value: controller.roiMeasurement.status)
            DiagnosticRow(title: "Region", value: controller.roiMeasurement.region)
            DiagnosticRow(title: "Min", value: controller.roiMeasurement.minTemperature)
            DiagnosticRow(title: "Max", value: controller.roiMeasurement.maxTemperature)
            DiagnosticRow(title: "Average", value: controller.roiMeasurement.averageTemperature)
        }
    }

    private func roiSlider(
        _ label: String,
        value: ReferenceWritableKeyPath<CaptureSessionController, Double>,
        range: ClosedRange<Double>
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .leading)

            Slider(value: Binding(
                get: { controller[keyPath: value] },
                set: { controller.setROIValue(value, value: $0) }
            ), in: range)
            .disabled(!controller.roiEnabled)

            Text("\(Int(controller[keyPath: value].rounded()))%")
                .font(.caption.monospacedDigit())
                .frame(width: 42, alignment: .trailing)
        }
    }

    private var advancedFeatures: some View {
        Panel(title: "Advanced Features") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(controller.advancedFeatureStates) { state in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(state.name)
                                .font(.callout.weight(.semibold))
                            Spacer()
                            Text(state.status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        DiagnosticRow(title: "Backend", value: state.backend)
                        Text(state.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(state.nextStep)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider()

                Text("Known Hikvision USB Commands")
                    .font(.callout.weight(.semibold))

                ForEach(controller.hikvisionUSBCommands) { command in
                    VStack(alignment: .leading, spacing: 2) {
                        DiagnosticRow(title: "\(command.code)", value: command.symbol)
                        Text(command.purpose)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var privateControlPanel: some View {
        Panel(title: "Hikvision Private Control") {
            DiagnosticRow(title: "Device", value: controller.usbTopology.deviceSummary)
            DiagnosticRow(title: "Topology", value: controller.usbInterpretation.summary)
            DiagnosticRow(title: "Transport", value: controller.privateControlCapability.transport.displayName)
            DiagnosticRow(title: "Concurrency", value: controller.privateControlCapability.concurrency.displayName)
            DiagnosticRow(title: "Maturity", value: controller.privateControlCapability.maturity.displayName)
            DiagnosticRow(title: "Risk", value: controller.privateControlCapability.risk.displayName)
            DiagnosticRow(
                title: "Sideband",
                value: controller.privateControlCapability.sidebandAvailable ? "Available" : "Unavailable"
            )
            DiagnosticRow(
                title: "Exclusive",
                value: controller.privateControlCapability.exclusiveCandidate ? "Candidate" : "Unavailable"
            )
            DiagnosticRow(
                title: "Read-only",
                value: controller.privateControlCapability.readOnlyProbeAllowed ? "Allowed" : "Blocked"
            )
            DiagnosticRow(title: "Write", value: controller.privateControlCapability.writePolicy.displayName)

            Text(controller.privateControlCapability.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(controller.privateControlCapability.decision)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    controller.refreshUSBTopology()
                } label: {
                    Label("Refresh USB", systemImage: "arrow.clockwise")
                }

                Button {
                    controller.enterPrivateControlMode()
                } label: {
                    Label(
                        controller.isRunning ? "Stop Preview + Probe" : "Enter Read-only Probe",
                        systemImage: controller.isRunning ? "stop.circle" : "magnifyingglass"
                    )
                }
                .disabled(!canEnterPrivateControlMode)
            }

            Divider()

            DiagnosticRow(title: "Session", value: controller.privateControlPlan.state.displayName)
            Text(controller.privateControlPlan.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(controller.privateControlPlan.nextAction)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if !controller.privateControlPlan.steps.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(controller.privateControlPlan.steps, id: \.self) { step in
                        Label(step, systemImage: "checklist")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Divider()

            if controller.usbTopology.interfaces.isEmpty {
                Text("No Hikvision USB interfaces found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(controller.usbTopology.interfaces) { interface in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Interface \(interface.number): \(interface.classLabel)")
                            .font(.callout.weight(.semibold))
                        DiagnosticRow(
                            title: "USB",
                            value: "class \(interface.interfaceClass), subclass \(interface.interfaceSubClass), protocol \(interface.interfaceProtocol)"
                        )
                        DiagnosticRow(title: "Endpoints", value: "\(interface.endpointCount)")
                    }
                }
            }
        }
    }

    private var canEnterPrivateControlMode: Bool {
        controller.privateControlCapability.sidebandAvailable ||
            controller.privateControlCapability.exclusiveCandidate
    }

    private var controlAvailability: some View {
        Panel(title: "Controls") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(controller.controlStates) { state in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: state.available ? "checkmark.circle.fill" : "minus.circle")
                            .foregroundStyle(state.available ? .green : .secondary)
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(state.name)
                                    .font(.callout.weight(.semibold))
                                Spacer()
                                Text(state.backend)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text(state.mode)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Text(state.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private var fallbackSummary: some View {
        Panel(title: "Fallbacks") {
            if controller.fallbackEvents.isEmpty {
                Text("None")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(controller.fallbackEvents) { event in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.stage)
                                .font(.callout.weight(.semibold))
                            Text(event.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(event.decision)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func toggleCapture() {
        if controller.isRunning {
            controller.stop()
        } else {
            controller.start()
        }
    }

    private var shouldShowPreviewOverlay: Bool {
        !controller.isRunning || controller.captureState.needsOverlay
    }

    private var previewStatusIcon: String {
        if controller.isRunning {
            switch controller.captureState {
            case .starting, .waitingForFirstFrame:
                return "hourglass"
            case .noFrames:
                return "video.slash"
            case .failed:
                return "exclamationmark.triangle"
            case .streaming, .stopping, .idle:
                break
            }
        }

        switch controller.authorizationState {
        case .authorized:
            return controller.devices.isEmpty ? "video.slash" : "video"
        case .notDetermined:
            return "lock.open"
        case .denied, .restricted:
            return "lock"
        }
    }

    private var previewStatusDetail: String {
        if controller.isRunning {
            switch controller.captureState {
            case .starting:
                return "Preparing the AVFoundation capture session."
            case .waitingForFirstFrame:
                return "Camera permission is authorized. Waiting for AVCaptureVideoDataOutput to deliver the first frame."
            case .noFrames:
                return "Camera permission is authorized and the session is running, but no sample buffer arrived. " +
                    "This points to macOS UVC negotiation or device format compatibility, not a SwiftUI drawing failure."
            case .failed:
                return "The capture session failed before delivering video."
            case .streaming, .stopping, .idle:
                break
            }
        }

        switch controller.authorizationState {
        case .authorized:
            return controller.devices.isEmpty ? "No video device is visible to AVFoundation." : "Select a camera and start capture."
        case .notDetermined:
            return "macOS will ask for camera access when capture starts."
        case .denied:
            return "Enable access in System Settings > Privacy & Security > Camera."
        case .restricted:
            return "Camera access is restricted by system policy."
        }
    }
}

private struct Panel<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private struct DiagnosticRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)

            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
