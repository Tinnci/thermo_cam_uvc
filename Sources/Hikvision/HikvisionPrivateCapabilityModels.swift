import Foundation

enum HikvisionPrivateControlMode: String, Sendable {
    case unknown = "Unknown"
    case sideband = "Sideband"
    case exclusive = "Exclusive"
    case disabled = "Disabled"
}

enum HikvisionPrivateTransport: String, Sendable {
    case none
    case vendorSpecificInterface
    case uvcVideoControlInterface
    case unknown

    var displayName: String {
        switch self {
        case .none:
            return L10n.tr("None")
        case .vendorSpecificInterface:
            return L10n.tr("Vendor-specific interface")
        case .uvcVideoControlInterface:
            return L10n.tr("UVC VideoControl interface")
        case .unknown:
            return L10n.tr("Unknown")
        }
    }
}

enum HikvisionPrivateConcurrency: String, Sendable {
    case canRunWithAVFoundation
    case requiresCaptureStopped
    case blockedByActiveCapture
    case unavailable
    case unknown

    var displayName: String {
        switch self {
        case .canRunWithAVFoundation:
            return L10n.tr("Can run with AVFoundation")
        case .requiresCaptureStopped:
            return L10n.tr("Requires capture stopped")
        case .blockedByActiveCapture:
            return L10n.tr("Blocked by active capture")
        case .unavailable:
            return L10n.tr("Unavailable")
        case .unknown:
            return L10n.tr("Unknown")
        }
    }
}

enum HikvisionPrivateMaturity: String, Sendable {
    case topologyOnly
    case readOnlyProbe
    case writeAllowlisted
    case unsupported

    var displayName: String {
        switch self {
        case .topologyOnly:
            return L10n.tr("Topology only")
        case .readOnlyProbe:
            return L10n.tr("Read-only probe")
        case .writeAllowlisted:
            return L10n.tr("Write allowlisted")
        case .unsupported:
            return L10n.tr("Unsupported")
        }
    }
}

enum HikvisionPrivateRisk: String, Sendable {
    case safe
    case experimental
    case dangerous

    var displayName: String {
        switch self {
        case .safe:
            return L10n.tr("Safe")
        case .experimental:
            return L10n.tr("Experimental")
        case .dangerous:
            return L10n.tr("Dangerous")
        }
    }
}

enum HikvisionPrivateWritePolicy: String, Sendable {
    case unavailable
    case disabledByPolicy
    case allowlistedOnly

    var displayName: String {
        switch self {
        case .unavailable:
            return L10n.tr("Unavailable")
        case .disabledByPolicy:
            return L10n.tr("Disabled by policy")
        case .allowlistedOnly:
            return L10n.tr("Allowlisted only")
        }
    }
}

struct HikvisionPrivateControlCapability: Equatable, Sendable {
    let transport: HikvisionPrivateTransport
    let concurrency: HikvisionPrivateConcurrency
    let maturity: HikvisionPrivateMaturity
    let risk: HikvisionPrivateRisk
    let writePolicy: HikvisionPrivateWritePolicy
    let sidebandAvailable: Bool
    let exclusiveCandidate: Bool
    let readOnlyProbeAllowed: Bool
    let requiresUserConfirmation: Bool
    let blockedReason: String?
    let reason: String
    let evidence: String
    let decision: String

    var status: String {
        if let blockedReason {
            return blockedReason
        }

        switch maturity {
        case .unsupported:
            return L10n.tr("Unsupported")
        case .topologyOnly:
            return L10n.tr("Topology only")
        case .readOnlyProbe:
            return concurrency == .blockedByActiveCapture
                ? L10n.tr("Needs capture stop")
                : L10n.tr("Read-only probe available")
        case .writeAllowlisted:
            return L10n.tr("Allowlisted write available")
        }
    }

    static let unknown = HikvisionPrivateControlCapability(
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
        reason: L10n.tr("USB topology has not been probed"),
        evidence: L10n.tr("No IOUSBInterface facts available"),
        decision: L10n.tr("Probe USB topology before enabling private control")
    )
}
