import SwiftUI

extension ContentView {
    var configurationSummary: some View {
        Panel(title: "Configuration") {
            DiagnosticRow(title: "Permission", value: controller.authorizationState.displayName)
            DiagnosticRow(title: "Requested", value: controller.activeConfiguration.requestedFormat)
            DiagnosticRow(title: "Active", value: controller.activeConfiguration.activeFormat)
            DiagnosticRow(title: "Output", value: controller.activeConfiguration.outputPixelFormat)
        }
    }

    var diagnostics: some View {
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

    var thermalData: some View {
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

    var roiPanel: some View {
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

    var advancedFeatures: some View {
        Panel(title: "Advanced Features") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(controller.advancedFeatureStates) { state in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(LocalizedStringKey(state.name))
                                .font(.callout.weight(.semibold))
                            Spacer()
                            Text(LocalizedStringKey(state.status))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        DiagnosticRow(title: "Backend", value: state.backend)
                        Text(LocalizedStringKey(state.reason))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(LocalizedStringKey(state.nextStep))
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
                        Text(LocalizedStringKey(command.purpose))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    var controlAvailability: some View {
        Panel(title: "Controls") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(controller.controlStates) { state in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: state.available ? "checkmark.circle.fill" : "minus.circle")
                            .foregroundStyle(state.available ? .green : .secondary)
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(LocalizedStringKey(state.name))
                                    .font(.callout.weight(.semibold))
                                Spacer()
                                Text(LocalizedStringKey(state.backend))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text(LocalizedStringKey(state.mode))
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Text(LocalizedStringKey(state.reason))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    var fallbackSummary: some View {
        Panel(title: "Fallbacks") {
            if controller.fallbackEvents.isEmpty {
                Text("None")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(controller.fallbackEvents) { event in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(LocalizedStringKey(event.stage))
                                .font(.callout.weight(.semibold))
                            Text(LocalizedStringKey(event.reason))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(LocalizedStringKey(event.decision))
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
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
}
