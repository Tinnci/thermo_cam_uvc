import Foundation

final class HikvisionPrivateUSBExecutor: @unchecked Sendable {
    func makeReadOnlyProbePlan(
        capability: HikvisionPrivateControlCapability,
        isAVFoundationRunning: Bool
    ) -> PrivateControlSessionPlan {
        guard capability.transport != .none else {
            return PrivateControlSessionPlan(
                state: .failed,
                title: "Private control unsupported",
                reason: capability.reason,
                nextAction: "Use AVFoundation capture only",
                failureKind: .notHikvisionDevice,
                steps: []
            )
        }

        guard capability.transport != .unknown else {
            return PrivateControlSessionPlan(
                state: .failed,
                title: "Topology unknown",
                reason: capability.reason,
                nextAction: "Refresh USB topology",
                failureKind: .topologyUnknown,
                steps: []
            )
        }

        if isAVFoundationRunning && capability.concurrency == .blockedByActiveCapture {
            return PrivateControlSessionPlan(
                state: .blockedByCapture,
                title: "Capture must stop first",
                reason: "The selected transport cannot be used while AVFoundation owns the UVC interface",
                nextAction: "Stop preview and enter private control mode",
                failureKind: .captureStillActive,
                steps: []
            )
        }

        guard capability.readOnlyProbeAllowed else {
            return PrivateControlSessionPlan(
                state: .failed,
                title: "Read-only probe not allowed",
                reason: capability.reason,
                nextAction: capability.decision,
                failureKind: .requiresExclusiveMode,
                steps: []
            )
        }

        return PrivateControlSessionPlan(
            state: .readyForReadOnlyProbe,
            title: "Read-only probe session ready",
            reason: "The current policy allows only non-mutating Hikvision private-control discovery",
            nextAction: "Probe Extension Unit descriptors, GET_INFO, GET_LEN, and GET_CUR after transport is implemented",
            failureKind: nil,
            steps: [
                "Confirm transport remains \(capability.transport.displayName)",
                "Search UVC descriptors for Extension Unit entity IDs",
                "Try allowlisted GET_INFO selectors only",
                "Read GET_LEN before GET_CUR and verify returned lengths",
                "Keep all SET requests blocked by policy"
            ]
        )
    }
}
