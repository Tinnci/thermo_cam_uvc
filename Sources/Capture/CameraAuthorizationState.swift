import AVFoundation
import Foundation

enum CameraAuthorizationState: String, Sendable {
    case authorized
    case notDetermined
    case denied
    case restricted

    init(status: AVAuthorizationStatus) {
        switch status {
        case .authorized:
            self = .authorized
        case .notDetermined:
            self = .notDetermined
        case .denied:
            self = .denied
        case .restricted:
            self = .restricted
        @unknown default:
            self = .restricted
        }
    }

    var displayName: String {
        switch self {
        case .authorized:
            return L10n.tr("Authorized")
        case .notDetermined:
            return L10n.tr("Not Requested")
        case .denied:
            return L10n.tr("Denied")
        case .restricted:
            return L10n.tr("Restricted")
        }
    }
}
