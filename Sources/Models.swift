import AVFoundation
import CoreMedia
import CoreVideo
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
            return "Authorized"
        case .notDetermined:
            return "Not Requested"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        }
    }
}

struct CameraDeviceInfo: Identifiable, Hashable, Sendable {
    let id: String
    let localizedName: String
    let deviceType: String
    let position: String

    var label: String {
        "\(localizedName) - \(deviceType)"
    }
}

struct CameraFormatInfo: Identifiable, Hashable, Sendable {
    let id: String
    let formatIndex: Int
    let width: Int32
    let height: Int32
    let fps: Double
    let mediaSubType: FourCharCode
    let frameRateRangeDescription: String

    var label: String {
        "\(width)x\(height) @ \(formatFPSLabel(fps)) fps - \(pixelFormatName(mediaSubType))"
    }
}

struct ActiveConfiguration: Equatable, Sendable {
    var requestedFormat: String
    var activeFormat: String
    var outputPixelFormat: String

    static let empty = ActiveConfiguration(
        requestedFormat: "None",
        activeFormat: "None",
        outputPixelFormat: "None"
    )
}

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
        frameSize: "None",
        deliveredPixelFormat: "None",
        metalStatus: "Idle",
        metalTexture: "None"
    )
}

enum CaptureStreamState: String, Sendable {
    case idle
    case starting
    case waitingForFirstFrame
    case streaming
    case noFrames
    case stopping
    case failed

    var displayName: String {
        switch self {
        case .idle:
            return "Idle"
        case .starting:
            return "Starting"
        case .waitingForFirstFrame:
            return "Waiting for first frame"
        case .streaming:
            return "Streaming"
        case .noFrames:
            return "No frames"
        case .stopping:
            return "Stopping"
        case .failed:
            return "Failed"
        }
    }

    var needsOverlay: Bool {
        switch self {
        case .idle, .starting, .waitingForFirstFrame, .noFrames, .failed:
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

struct ThermalInspectionSnapshot: Equatable, Sendable {
    var inspectedFrames: Int
    var status: String
    var evidence: String
    var matrixSize: String

    static let empty = ThermalInspectionSnapshot(
        inspectedFrames: 0,
        status: "Not inspected",
        evidence: "Capture has not delivered a frame yet",
        matrixSize: "Unavailable"
    )
}

struct ROITemperatureSnapshot: Equatable, Sendable {
    var status: String
    var region: String
    var minTemperature: String
    var maxTemperature: String
    var averageTemperature: String

    static let unsupported = ROITemperatureSnapshot(
        status: "Unavailable",
        region: "None",
        minTemperature: "No radiometric matrix",
        maxTemperature: "No radiometric matrix",
        averageTemperature: "No radiometric matrix"
    )
}

struct AdvancedFeatureState: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let status: String
    let backend: String
    let reason: String
    let nextStep: String

    static let currentDefaults = [
        AdvancedFeatureState(
            id: "thermal_private_data",
            name: "Thermal Private Data",
            status: "Partial",
            backend: "CMSampleBuffer / CVPixelBuffer",
            reason: "The parser detects L016 raw matrices and thermal metadata keys in delivered AVFoundation frames",
            nextStep: "Confirm Hikvision append-data layout before applying calibrated temperature conversion"
        ),
        AdvancedFeatureState(
            id: "hikvision_usb_control",
            name: "Hikvision USB Control",
            status: "Not enabled",
            backend: "IOUSBHost / vendor protocol",
            reason: "macOS UVCAssistant owns the standard UVC interfaces while AVFoundation is active",
            nextStep: "Design a separate private-control helper after command transport is confirmed"
        ),
        AdvancedFeatureState(
            id: "virtual_camera",
            name: "Virtual Camera Output",
            status: "Not enabled",
            backend: "Core Media I/O Camera Extension",
            reason: "Virtual camera output requires a separate System Extension target",
            nextStep: "Add a CoreMediaIO Camera Extension target when processed output must appear in Zoom/Teams"
        )
    ]
}

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
            return "None"
        case .vendorSpecificInterface:
            return "Vendor-specific interface"
        case .uvcVideoControlInterface:
            return "UVC VideoControl interface"
        case .unknown:
            return "Unknown"
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
            return "Can run with AVFoundation"
        case .requiresCaptureStopped:
            return "Requires capture stopped"
        case .blockedByActiveCapture:
            return "Blocked by active capture"
        case .unavailable:
            return "Unavailable"
        case .unknown:
            return "Unknown"
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
            return "Topology only"
        case .readOnlyProbe:
            return "Read-only probe"
        case .writeAllowlisted:
            return "Write allowlisted"
        case .unsupported:
            return "Unsupported"
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
            return "Safe"
        case .experimental:
            return "Experimental"
        case .dangerous:
            return "Dangerous"
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
            return "Unavailable"
        case .disabledByPolicy:
            return "Disabled by policy"
        case .allowlistedOnly:
            return "Allowlisted only"
        }
    }
}

struct USBTopologyInterpretation: Equatable, Sendable {
    let isHikvisionDevicePresent: Bool
    let hasVendorSpecificInterface: Bool
    let hasUVCVideoControl: Bool
    let hasUVCVideoStreaming: Bool
    let transport: HikvisionPrivateTransport
    let summary: String
    let evidence: String

    static let unknown = USBTopologyInterpretation(
        isHikvisionDevicePresent: false,
        hasVendorSpecificInterface: false,
        hasUVCVideoControl: false,
        hasUVCVideoStreaming: false,
        transport: .unknown,
        summary: "USB topology has not been interpreted",
        evidence: "No USB facts available"
    )
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
            return "Unsupported"
        case .topologyOnly:
            return "Topology only"
        case .readOnlyProbe:
            return concurrency == .blockedByActiveCapture ? "Needs capture stop" : "Read-only probe available"
        case .writeAllowlisted:
            return "Allowlisted write available"
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
        blockedReason: "Unknown",
        reason: "USB topology has not been probed",
        evidence: "No IOUSBInterface facts available",
        decision: "Probe USB topology before enabling private control"
    )
}

struct USBInterfaceFact: Identifiable, Equatable, Sendable {
    let id: String
    let number: Int
    let interfaceClass: Int
    let interfaceSubClass: Int
    let interfaceProtocol: Int
    let alternateSetting: Int
    let endpointCount: Int
    let name: String

    var classLabel: String {
        switch interfaceClass {
        case 14:
            switch interfaceSubClass {
            case 1:
                return "VideoControl"
            case 2:
                return "VideoStreaming"
            default:
                return "Video"
            }
        case 255:
            return "Vendor Specific"
        default:
            return "Class \(interfaceClass)"
        }
    }
}

struct USBTopologySnapshot: Equatable, Sendable {
    let status: String
    let deviceSummary: String
    let interfaces: [USBInterfaceFact]

    static let unknown = USBTopologySnapshot(
        status: "Not probed",
        deviceSummary: "No Hikvision USB facts loaded",
        interfaces: []
    )
}

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
            return "Inactive"
        case .blockedByCapture:
            return "Blocked by capture"
        case .readyForReadOnlyProbe:
            return "Ready for read-only probe"
        case .probing:
            return "Probing"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
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
        title: "No private control session",
        reason: "Private USB control has not been requested",
        nextAction: "Probe USB topology first",
        failureKind: nil,
        steps: []
    )
}

struct NormalizedROI: Equatable, Sendable {
    let xPercent: Double
    let yPercent: Double
    let widthPercent: Double
    let heightPercent: Double

    static let centered = NormalizedROI(
        xPercent: 25,
        yPercent: 25,
        widthPercent: 50,
        heightPercent: 50
    )
}

enum CameraCaptureError: LocalizedError, Sendable {
    case noDevice
    case noUsableFormat
    case cannotAddInput
    case cannotAddOutput
    case cannotStartSession
    case cannotCreateImage
    case cannotCreateImageDestination
    case cannotWriteImage

    var errorDescription: String? {
        switch self {
        case .noDevice:
            return "No AVFoundation video device is available."
        case .noUsableFormat:
            return "The selected camera has no usable video format."
        case .cannotAddInput:
            return "AVCaptureSession rejected the selected camera input."
        case .cannotAddOutput:
            return "AVCaptureSession rejected AVCaptureVideoDataOutput."
        case .cannotStartSession:
            return "AVCaptureSession did not enter the running state."
        case .cannotCreateImage:
            return "Could not create a CGImage from the current CVPixelBuffer."
        case .cannotCreateImageDestination:
            return "Could not create the selected image file."
        case .cannotWriteImage:
            return "ImageIO could not write the selected image file."
        }
    }
}

func formatFPSLabel(_ fps: Double) -> String {
    if abs(fps.rounded() - fps) < 0.01 {
        return "\(Int(fps.rounded()))"
    }

    return String(format: "%.2f", fps)
}

func pixelFormatName(_ code: FourCharCode) -> String {
    switch code {
    case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
        return "NV12 Video"
    case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
        return "NV12 Full"
    case kCVPixelFormatType_32BGRA:
        return "BGRA"
    case kCVPixelFormatType_422YpCbCr8:
        return "UYVY"
    case kCVPixelFormatType_422YpCbCr8_yuvs:
        return "YUY2/YUYV"
    case kCVPixelFormatType_OneComponent16:
        return "L016"
    case kCVPixelFormatType_OneComponent16Half:
        return "L00h"
    case kCVPixelFormatType_OneComponent32Float:
        return "L00f"
    default:
        return fourCharCodeString(code)
    }
}

func fourCharCodeString(_ code: FourCharCode) -> String {
    var bigEndianCode = code.bigEndian
    let data = Data(bytes: &bigEndianCode, count: MemoryLayout<FourCharCode>.size)

    if let string = String(data: data, encoding: .macOSRoman),
       string.unicodeScalars.allSatisfy({ scalar in
           scalar.value >= 32 && scalar.value <= 126
       }) {
        return string
    }

    return "0x\(String(code, radix: 16, uppercase: true))"
}
