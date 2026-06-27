import Foundation

final class HikvisionPrivateControlPolicy: @unchecked Sendable {
    func interpret(topology: USBTopologySnapshot) -> USBTopologyInterpretation {
        guard !topology.interfaces.isEmpty else {
            return USBTopologyInterpretation(
                isHikvisionDevicePresent: false,
                hasVendorSpecificInterface: false,
                hasUVCVideoControl: false,
                hasUVCVideoStreaming: false,
                transport: .none,
                summary: L10n.tr("No Hikvision USB interface was found"),
                evidence: topology.deviceSummary
            )
        }

        let hasVendorSpecific = topology.interfaces.contains { $0.interfaceClass == 255 }
        let hasVideoControl = topology.interfaces.contains {
            $0.interfaceClass == 14 && $0.interfaceSubClass == 1
        }
        let hasVideoStreaming = topology.interfaces.contains {
            $0.interfaceClass == 14 && $0.interfaceSubClass == 2
        }

        let transport: HikvisionPrivateTransport
        let summary: String
        if hasVendorSpecific {
            transport = .vendorSpecificInterface
            summary = L10n.tr("Device exposes a vendor-specific sideband interface")
        } else if hasVideoControl {
            transport = .uvcVideoControlInterface
            summary = L10n.tr("Device exposes only UVC video control/streaming interfaces")
        } else {
            transport = .unknown
            summary = L10n.tr("Device interface topology is not recognized")
        }

        return USBTopologyInterpretation(
            isHikvisionDevicePresent: true,
            hasVendorSpecificInterface: hasVendorSpecific,
            hasUVCVideoControl: hasVideoControl,
            hasUVCVideoStreaming: hasVideoStreaming,
            transport: transport,
            summary: summary,
            evidence: evidence(for: topology.interfaces)
        )
    }

    func decide(
        interpretation: USBTopologyInterpretation,
        isAVFoundationRunning: Bool
    ) -> HikvisionPrivateControlCapability {
        guard interpretation.isHikvisionDevicePresent else {
            return HikvisionPrivateControlCapability(
                transport: .none,
                concurrency: .unavailable,
                maturity: .unsupported,
                risk: .safe,
                writePolicy: .unavailable,
                sidebandAvailable: false,
                exclusiveCandidate: false,
                readOnlyProbeAllowed: false,
                requiresUserConfirmation: false,
                blockedReason: L10n.tr("Unsupported"),
                reason: L10n.tr("No Hikvision USB device is present"),
                evidence: interpretation.evidence,
                decision: L10n.tr("Keep AVFoundation available for normal camera devices")
            )
        }

        switch interpretation.transport {
        case .vendorSpecificInterface:
            return HikvisionPrivateControlCapability(
                transport: .vendorSpecificInterface,
                concurrency: .canRunWithAVFoundation,
                maturity: .readOnlyProbe,
                risk: .experimental,
                writePolicy: .disabledByPolicy,
                sidebandAvailable: true,
                exclusiveCandidate: false,
                readOnlyProbeAllowed: true,
                requiresUserConfirmation: true,
                blockedReason: nil,
                reason: L10n.tr("A separate vendor-specific USB interface can be used as sideband transport"),
                evidence: interpretation.evidence,
                decision: L10n.tr("Allow read-only private-control probing without stopping AVFoundation; keep writes disabled")
            )

        case .uvcVideoControlInterface:
            let concurrency: HikvisionPrivateConcurrency = isAVFoundationRunning
                ? .blockedByActiveCapture
                : .requiresCaptureStopped

            return HikvisionPrivateControlCapability(
                transport: .uvcVideoControlInterface,
                concurrency: concurrency,
                maturity: .readOnlyProbe,
                risk: .experimental,
                writePolicy: .disabledByPolicy,
                sidebandAvailable: false,
                exclusiveCandidate: true,
                readOnlyProbeAllowed: !isAVFoundationRunning,
                requiresUserConfirmation: true,
                blockedReason: isAVFoundationRunning ? L10n.tr("Needs capture stop") : nil,
                reason: L10n.tr("No independent vendor-specific interface is present; private controls may share UVC VideoControl"),
                evidence: interpretation.evidence,
                decision: isAVFoundationRunning
                    ? L10n.tr("Stop AVFoundation preview before entering read-only private-control probe mode")
                    : L10n.tr("Enter explicit read-only private-control probe mode; do not perform write controls")
            )

        case .none:
            return HikvisionPrivateControlCapability(
                transport: .none,
                concurrency: .unavailable,
                maturity: .unsupported,
                risk: .safe,
                writePolicy: .unavailable,
                sidebandAvailable: false,
                exclusiveCandidate: false,
                readOnlyProbeAllowed: false,
                requiresUserConfirmation: false,
                blockedReason: L10n.tr("Unsupported"),
                reason: L10n.tr("There is no private-control transport"),
                evidence: interpretation.evidence,
                decision: L10n.tr("Disable private USB control")
            )

        case .unknown:
            return HikvisionPrivateControlCapability(
                transport: .unknown,
                concurrency: .unknown,
                maturity: .topologyOnly,
                risk: .experimental,
                writePolicy: .disabledByPolicy,
                sidebandAvailable: false,
                exclusiveCandidate: false,
                readOnlyProbeAllowed: false,
                requiresUserConfirmation: true,
                blockedReason: L10n.tr("Unknown"),
                reason: L10n.tr("The USB topology does not match the known sideband or UVC-control shapes"),
                evidence: interpretation.evidence,
                decision: L10n.tr("Do not send private USB commands until the topology is understood")
            )
        }
    }

    private func evidence(for interfaces: [USBInterfaceFact]) -> String {
        interfaces
            .sorted { left, right in
                if left.number == right.number {
                    return left.alternateSetting < right.alternateSetting
                }

                return left.number < right.number
            }
            .map { interface in
                L10n.tr(
                    "Interface %@: %@, class %@, subclass %@, endpoints %@",
                    "\(interface.number)",
                    interface.classLabel,
                    "\(interface.interfaceClass)",
                    "\(interface.interfaceSubClass)",
                    "\(interface.endpointCount)"
                )
            }
            .joined(separator: "; ")
    }
}
