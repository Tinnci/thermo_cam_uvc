import AVFoundation
import CoreGraphics
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import Observation

@Observable
final class CaptureSessionController: NSObject, @unchecked Sendable {
    @ObservationIgnored
    let session = AVCaptureSession()

    var authorizationState = CameraAuthorizationState(
        status: AVCaptureDevice.authorizationStatus(for: .video)
    )
    var devices: [CameraDeviceInfo] = []
    var formats: [CameraFormatInfo] = []
    var activeConfiguration = ActiveConfiguration.empty
    var diagnostics = DiagnosticsSnapshot.empty
    var fallbackEvents: [FallbackEvent] = []
    var controlStates: [CameraControlState] = []
    var isRunning = false
    var captureState = CaptureStreamState.idle
    var statusMessage = L10n.tr("Idle")
    var photoSaveStatus = L10n.tr("No frame saved")
    var isRecording = false
    var recordingStatus = L10n.tr("Idle")
    var recordingAvailable = false
    var previewImage: CGImage?
    var thermalInspection = ThermalInspectionSnapshot.empty
    var roiMeasurement = ROITemperatureSnapshot.unsupported
    var advancedFeatureStates = AdvancedFeatureState.currentDefaults
    var hikvisionUSBCommands = HikvisionPrivateUSBControl.knownCommands
    var usbTopology = USBTopologySnapshot.unknown
    var usbInterpretation = USBTopologyInterpretation.unknown
    var privateControlCapability = HikvisionPrivateControlCapability.unknown
    var privateControlPlan = PrivateControlSessionPlan.inactive

    var selectedDeviceID: String?
    var selectedFormatID: String?
    var roiEnabled = false
    var roiXPercent = 25.0
    var roiYPercent = 25.0
    var roiWidthPercent = 50.0
    var roiHeightPercent = 50.0

    @ObservationIgnored
    let manager = CameraDeviceManager()
    @ObservationIgnored
    let videoOutput = AVCaptureVideoDataOutput()
    @ObservationIgnored
    let movieOutput = AVCaptureMovieFileOutput()
    @ObservationIgnored
    let sessionQueue = DispatchQueue(label: "camera.session.queue", qos: .userInitiated)
    @ObservationIgnored
    let outputQueue = DispatchQueue(label: "camera.output.queue", qos: .userInitiated)
    @ObservationIgnored
    let metalPipeline = MetalFramePipeline()
    @ObservationIgnored
    let thermalParser = ThermalDataParser()
    @ObservationIgnored
    let imageContext = CIContext()
    @ObservationIgnored
    let usbTopologyProbe = USBTopologyProbe()
    @ObservationIgnored
    let privateControlPolicy = HikvisionPrivateControlPolicy()
    @ObservationIgnored
    let privateControlExecutor = HikvisionPrivateUSBExecutor()

    @ObservationIgnored
    let firstFrameTimeout: TimeInterval = 5
    @ObservationIgnored
    var totalFrames = 0
    @ObservationIgnored
    var droppedFrames = 0
    @ObservationIgnored
    var framesInWindow = 0
    @ObservationIgnored
    var windowStartTime = CFAbsoluteTimeGetCurrent()
    @ObservationIgnored
    var lastPresentationTime: CMTime?
    @ObservationIgnored
    var lastFrameIntervalMS = 0.0
    @ObservationIgnored
    var requestedOutputPixelFormat: FourCharCode?
    @ObservationIgnored
    var reportedPixelFormatMismatch = false
    @ObservationIgnored
    var latestPixelBuffer: CVPixelBuffer?
    @ObservationIgnored
    var shouldEnterPrivateControlAfterStop = false
    @ObservationIgnored
    var captureGeneration = 0

    override init() {
        super.init()
        installSessionObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func bootstrap() {
        authorizationState = CameraAuthorizationState(
            status: AVCaptureDevice.authorizationStatus(for: .video)
        )
        refreshDevices()
        refreshUSBTopology()
    }
}
