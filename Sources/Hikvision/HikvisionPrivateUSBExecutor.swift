import Foundation

final class HikvisionPrivateUSBExecutor: @unchecked Sendable {
    func makeReadOnlyProbePlan(
        capability: HikvisionPrivateControlCapability,
        isAVFoundationRunning: Bool
    ) -> PrivateControlSessionPlan {
        guard capability.transport != .none else {
            return PrivateControlSessionPlan(
                state: .failed,
                title: L10n.tr("Private control unsupported"),
                reason: capability.reason,
                nextAction: L10n.tr("Use AVFoundation capture only"),
                failureKind: .notHikvisionDevice,
                steps: []
            )
        }

        guard capability.transport != .unknown else {
            return PrivateControlSessionPlan(
                state: .failed,
                title: L10n.tr("Topology unknown"),
                reason: capability.reason,
                nextAction: L10n.tr("Refresh USB topology"),
                failureKind: .topologyUnknown,
                steps: []
            )
        }

        if isAVFoundationRunning && capability.concurrency == .blockedByActiveCapture {
            return PrivateControlSessionPlan(
                state: .blockedByCapture,
                title: L10n.tr("Capture must stop first"),
                reason: L10n.tr("The selected transport cannot be used while AVFoundation owns the UVC interface"),
                nextAction: L10n.tr("Stop preview and enter private control mode"),
                failureKind: .captureStillActive,
                steps: []
            )
        }

        guard capability.readOnlyProbeAllowed else {
            return PrivateControlSessionPlan(
                state: .failed,
                title: L10n.tr("Read-only probe not allowed"),
                reason: capability.reason,
                nextAction: capability.decision,
                failureKind: .requiresExclusiveMode,
                steps: []
            )
        }

        return PrivateControlSessionPlan(
            state: .readyForReadOnlyProbe,
            title: L10n.tr("Read-only probe session ready"),
            reason: L10n.tr("The current policy allows only non-mutating Hikvision private-control discovery"),
            nextAction: L10n.tr(
                "Probe Extension Unit descriptors, GET_INFO, GET_LEN, and GET_CUR after transport is implemented"
            ),
            failureKind: nil,
            steps: [
                L10n.tr("Confirm transport remains %@", capability.transport.displayName),
                L10n.tr("Search UVC descriptors for Extension Unit entity IDs"),
                L10n.tr("Try allowlisted GET_INFO selectors only"),
                L10n.tr("Read GET_LEN before GET_CUR and verify returned lengths"),
                L10n.tr("Keep all SET requests blocked by policy")
            ]
        )
    }
}
