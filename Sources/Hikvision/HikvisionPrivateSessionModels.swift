import Foundation

enum PrivateControlSessionState: String, Sendable {
    case inactive
    case blockedByCapture
    case readyForReadOnlyProbe
    case probing
    case completed
    case failed

    var displayName: String {
        switch self {
        case .inactive:
            return L10n.tr("Inactive")
        case .blockedByCapture:
            return L10n.tr("Blocked by capture")
        case .readyForReadOnlyProbe:
            return L10n.tr("Ready for read-only probe")
        case .probing:
            return L10n.tr("Probing")
        case .completed:
            return L10n.tr("Completed")
        case .failed:
            return L10n.tr("Failed")
        }
    }
}

enum PrivateControlFailureKind: String, Sendable {
    case notHikvisionDevice
    case noVendorSpecificInterface
    case requiresExclusiveMode
    case captureStillActive
    case interfaceClaimFailed
    case extensionUnitNotFound
    case selectorUnsupported
    case readLengthMismatch
    case timeout
    case writeBlockedByPolicy
    case unsupportedFirmware
    case topologyUnknown
}

struct PrivateControlSessionPlan: Equatable, Sendable {
    let state: PrivateControlSessionState
    let title: String
    let reason: String
    let nextAction: String
    let failureKind: PrivateControlFailureKind?
    let steps: [String]

    static let inactive = PrivateControlSessionPlan(
        state: .inactive,
        title: L10n.tr("No private control session"),
        reason: L10n.tr("Private USB control has not been requested"),
        nextAction: L10n.tr("Probe USB topology first"),
        failureKind: nil,
        steps: []
    )
}
