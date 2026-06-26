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
                summary: "No Hikvision USB interface was found",
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
            summary = "Device exposes a vendor-specific sideband interface"
        } else if hasVideoControl {
            transport = .uvcVideoControlInterface
            summary = "Device exposes only UVC video control/streaming interfaces"
        } else {
            transport = .unknown
            summary = "Device interface topology is not recognized"
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
                blockedReason: "Unsupported",
                reason: "No Hikvision USB device is present",
                evidence: interpretation.evidence,
                decision: "Keep AVFoundation available for normal camera devices"
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
                reason: "A separate vendor-specific USB interface can be used as sideband transport",
                evidence: interpretation.evidence,
                decision: "Allow read-only private-control probing without stopping AVFoundation; keep writes disabled"
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
                blockedReason: isAVFoundationRunning ? "Needs capture stop" : nil,
                reason: "No independent vendor-specific interface is present; private controls may share UVC VideoControl",
                evidence: interpretation.evidence,
                decision: isAVFoundationRunning
                    ? "Stop AVFoundation preview before entering read-only private-control probe mode"
                    : "Enter explicit read-only private-control probe mode; do not perform write controls"
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
                blockedReason: "Unsupported",
                reason: "There is no private-control transport",
                evidence: interpretation.evidence,
                decision: "Disable private USB control"
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
                blockedReason: "Unknown",
                reason: "The USB topology does not match the known sideband or UVC-control shapes",
                evidence: interpretation.evidence,
                decision: "Do not send private USB commands until the topology is understood"
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
                "Interface \(interface.number): \(interface.classLabel), class \(interface.interfaceClass), subclass \(interface.interfaceSubClass), endpoints \(interface.endpointCount)"
            }
            .joined(separator: "; ")
    }
}
