import Foundation

struct FallbackEvent: Identifiable, Equatable, Sendable {
    let id = UUID()
    let stage: String
    let reason: String
    let decision: String
}

struct DiagnosticsSnapshot: Equatable, Sendable {
    var totalFrames: Int
    var droppedFrames: Int
    var measuredFPS: Double
    var frameIntervalMS: Double
    var frameSize: String
    var deliveredPixelFormat: String
    var metalStatus: String
    var metalTexture: String

    static let empty = DiagnosticsSnapshot(
        totalFrames: 0,
        droppedFrames: 0,
        measuredFPS: 0,
        frameIntervalMS: 0,
        frameSize: L10n.tr("None"),
        deliveredPixelFormat: L10n.tr("None"),
        metalStatus: L10n.tr("Idle"),
        metalTexture: L10n.tr("None")
    )
}

enum CaptureStreamState: String, Sendable {
    case idle
    case starting
    case waitingForFirstFrame
    case streaming
    case noFrames
    case nativeBackendRequired
    case stopping
    case failed

    var displayName: String {
        switch self {
        case .idle:
            return L10n.tr("Idle")
        case .starting:
            return L10n.tr("Starting")
        case .waitingForFirstFrame:
            return L10n.tr("Waiting for first frame")
        case .streaming:
            return L10n.tr("Streaming")
        case .noFrames:
            return L10n.tr("No frames")
        case .nativeBackendRequired:
            return L10n.tr("Native backend required")
        case .stopping:
            return L10n.tr("Stopping")
        case .failed:
            return L10n.tr("Failed")
        }
    }

    var needsOverlay: Bool {
        switch self {
        case .idle, .starting, .waitingForFirstFrame, .noFrames, .nativeBackendRequired, .failed:
            return true
        case .streaming, .stopping:
            return false
        }
    }
}

struct CameraControlState: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let available: Bool
    let backend: String
    let mode: String
    let reason: String
}
