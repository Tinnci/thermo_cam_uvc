import SwiftUI

extension ContentView {
    var privateControlPanel: some View {
        Panel(title: "Hikvision Private Control") {
            DiagnosticRow(title: "Device", value: controller.usbTopology.deviceSummary)
            DiagnosticRow(title: "Topology", value: controller.usbInterpretation.summary)

            Button {
                controller.refreshUSBTopology()
            } label: {
                Label("Refresh USB", systemImage: "arrow.clockwise")
            }

            if isRecognizedHikvisionDevice {
                privateControlDetails
            }
        }
    }

    private var privateControlDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
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

            Text(LocalizedStringKey(controller.privateControlCapability.reason))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(LocalizedStringKey(controller.privateControlCapability.decision))
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    controller.enterPrivateControlMode()
                } label: {
                    Label(
                        controller.isRunning ? L10n.tr("Stop Preview + Probe") : L10n.tr("Enter Read-only Probe"),
                        systemImage: controller.isRunning ? "stop.circle" : "magnifyingglass"
                    )
                }
                .disabled(!canEnterPrivateControlMode)
            }

            Divider()

            DiagnosticRow(title: "Session", value: controller.privateControlPlan.state.displayName)
            Text(LocalizedStringKey(controller.privateControlPlan.reason))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(LocalizedStringKey(controller.privateControlPlan.nextAction))
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if !controller.privateControlPlan.steps.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(controller.privateControlPlan.steps, id: \.self) { step in
                        Label(L10n.tr(step), systemImage: "checklist")
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
                        Text(L10n.tr("Interface %@: %@", "\(interface.number)", interface.classLabel))
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

    private var isRecognizedHikvisionDevice: Bool {
        controller.usbInterpretation.isHikvisionDevicePresent
    }

    private var canEnterPrivateControlMode: Bool {
        let capability = controller.privateControlCapability
        return isRecognizedHikvisionDevice &&
            (capability.sidebandAvailable || capability.exclusiveCandidate)
    }
}
