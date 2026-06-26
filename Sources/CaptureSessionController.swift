import AppKit
import AVFoundation
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers

@Observable
final class CaptureSessionController: NSObject, @unchecked Sendable {
    @ObservationIgnored
    let session = AVCaptureSession()

    private(set) var authorizationState = CameraAuthorizationState(
        status: AVCaptureDevice.authorizationStatus(for: .video)
    )
    private(set) var devices: [CameraDeviceInfo] = []
    private(set) var formats: [CameraFormatInfo] = []
    private(set) var activeConfiguration = ActiveConfiguration.empty
    private(set) var diagnostics = DiagnosticsSnapshot.empty
    private(set) var fallbackEvents: [FallbackEvent] = []
    private(set) var controlStates: [CameraControlState] = []
    private(set) var isRunning = false
    private(set) var captureState = CaptureStreamState.idle
    private(set) var statusMessage = "Idle"
    private(set) var photoSaveStatus = "No frame saved"
    private(set) var isRecording = false
    private(set) var recordingStatus = "Idle"
    private(set) var recordingAvailable = false
    private(set) var thermalInspection = ThermalInspectionSnapshot.empty
    private(set) var roiMeasurement = ROITemperatureSnapshot.unsupported
    private(set) var advancedFeatureStates = AdvancedFeatureState.currentDefaults
    private(set) var hikvisionUSBCommands = HikvisionPrivateUSBControl.knownCommands
    private(set) var usbTopology = USBTopologySnapshot.unknown
    private(set) var usbInterpretation = USBTopologyInterpretation.unknown
    private(set) var privateControlCapability = HikvisionPrivateControlCapability.unknown
    private(set) var privateControlPlan = PrivateControlSessionPlan.inactive

    var selectedDeviceID: String?
    var selectedFormatID: String?
    var roiEnabled = false
    var roiXPercent = 25.0
    var roiYPercent = 25.0
    var roiWidthPercent = 50.0
    var roiHeightPercent = 50.0

    @ObservationIgnored
    private let manager = CameraDeviceManager()
    @ObservationIgnored
    private let videoOutput = AVCaptureVideoDataOutput()
    @ObservationIgnored
    private let movieOutput = AVCaptureMovieFileOutput()
    @ObservationIgnored
    private let sessionQueue = DispatchQueue(label: "camera.session.queue", qos: .userInitiated)
    @ObservationIgnored
    private let outputQueue = DispatchQueue(label: "camera.output.queue", qos: .userInitiated)
    @ObservationIgnored
    private let metalPipeline = MetalFramePipeline()
    @ObservationIgnored
    private let thermalParser = ThermalDataParser()
    @ObservationIgnored
    private let imageContext = CIContext()
    @ObservationIgnored
    private let usbTopologyProbe = USBTopologyProbe()
    @ObservationIgnored
    private let privateControlPolicy = HikvisionPrivateControlPolicy()
    @ObservationIgnored
    private let privateControlExecutor = HikvisionPrivateUSBExecutor()

    @ObservationIgnored
    private let firstFrameTimeout: TimeInterval = 5
    @ObservationIgnored
    private var totalFrames = 0
    @ObservationIgnored
    private var droppedFrames = 0
    @ObservationIgnored
    private var framesInWindow = 0
    @ObservationIgnored
    private var windowStartTime = CFAbsoluteTimeGetCurrent()
    @ObservationIgnored
    private var lastPresentationTime: CMTime?
    @ObservationIgnored
    private var lastFrameIntervalMS = 0.0
    @ObservationIgnored
    private var requestedOutputPixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    @ObservationIgnored
    private var reportedPixelFormatMismatch = false
    @ObservationIgnored
    private var latestPixelBuffer: CVPixelBuffer?
    @ObservationIgnored
    private var shouldEnterPrivateControlAfterStop = false
    @ObservationIgnored
    private var captureGeneration = 0

    func bootstrap() {
        authorizationState = CameraAuthorizationState(
            status: AVCaptureDevice.authorizationStatus(for: .video)
        )
        refreshDevices()
        refreshUSBTopology()
    }

    func refreshDevices() {
        let discoveredDevices = manager.discoverDevices()
        let infos = manager.deviceInfos(from: discoveredDevices)

        devices = infos

        if selectedDeviceID == nil || !infos.contains(where: { $0.id == selectedDeviceID }) {
            selectedDeviceID = infos.first?.id
        }

        refreshFormatsForSelectedDevice()

        if infos.isEmpty {
            statusMessage = "No AVFoundation camera device found"
        } else if statusMessage == "No AVFoundation camera device found" {
            statusMessage = "Idle"
        }

        refreshUSBTopology()
    }

    func selectDevice(_ uniqueID: String) {
        guard selectedDeviceID != uniqueID else {
            return
        }

        selectedDeviceID = uniqueID
        refreshFormatsForSelectedDevice()

        if isRunning {
            restart()
        }
    }

    private func refreshFormatsForSelectedDevice() {
        guard let selectedDeviceID,
              let device = manager.device(withUniqueID: selectedDeviceID) else {
            formats = []
            selectedFormatID = nil
            controlStates = []
            return
        }

        let availableFormats = manager.formats(for: device)
        formats = availableFormats

        if selectedFormatID == nil || !availableFormats.contains(where: { $0.id == selectedFormatID }) {
            selectedFormatID = manager.bestFormat(for: device, in: availableFormats)?.id
        }

        controlStates = manager.controlStates(for: device)
    }

    func selectFormat(_ formatID: String) {
        guard selectedFormatID != formatID else {
            return
        }

        selectedFormatID = formatID

        if isRunning {
            restart()
        }
    }

    func start() {
        authorizationState = CameraAuthorizationState(
            status: AVCaptureDevice.authorizationStatus(for: .video)
        )

        switch authorizationState {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            statusMessage = "Requesting camera permission"
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else {
                        return
                    }

                    self.authorizationState = CameraAuthorizationState(
                        status: AVCaptureDevice.authorizationStatus(for: .video)
                    )

                    if granted {
                        self.configureAndStart()
                    } else {
                        self.statusMessage = "Camera permission denied"
                    }
                }
            }
        case .denied:
            statusMessage = "Camera permission denied"
        case .restricted:
            statusMessage = "Camera permission restricted"
        }
    }

    func stop() {
        captureState = .stopping
        statusMessage = "Stopping"

        sessionQueue.async { [weak self] in
            guard let self else {
                return
            }

            self.captureGeneration += 1

            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            }

            if self.session.isRunning {
                self.session.stopRunning()
            }

            DispatchQueue.main.async {
                self.isRunning = false
                if self.shouldEnterPrivateControlAfterStop {
                    self.shouldEnterPrivateControlAfterStop = false
                    self.captureState = .idle
                    self.statusMessage = "Capture stopped for private control"
                    self.beginPrivateControlReadOnlyProbe()
                } else {
                    self.captureState = .idle
                    self.statusMessage = "Stopped"
                    self.refreshUSBTopology()
                }
            }
        }
    }

    func refreshUSBTopology() {
        let captureRunning = isRunning

        sessionQueue.async { [weak self, captureRunning] in
            guard let self else {
                return
            }

            let topology = self.usbTopologyProbe.probeHikvisionDevice()
            let interpretation = self.privateControlPolicy.interpret(topology: topology)
            let capability = self.privateControlPolicy.decide(
                interpretation: interpretation,
                isAVFoundationRunning: captureRunning
            )
            let plan = self.privateControlExecutor.makeReadOnlyProbePlan(
                capability: capability,
                isAVFoundationRunning: captureRunning
            )

            DispatchQueue.main.async { [weak self, topology, interpretation, capability, plan] in
                self?.usbTopology = topology
                self?.usbInterpretation = interpretation
                self?.privateControlCapability = capability
                self?.privateControlPlan = plan.state == .blockedByCapture ? plan : .inactive
            }
        }
    }

    @MainActor
    func enterPrivateControlMode() {
        if isRunning {
            shouldEnterPrivateControlAfterStop = true
            privateControlPlan = privateControlExecutor.makeReadOnlyProbePlan(
                capability: privateControlCapability,
                isAVFoundationRunning: true
            )
            stop()
            return
        }

        beginPrivateControlReadOnlyProbe()
    }

    @MainActor
    private func beginPrivateControlReadOnlyProbe() {
        let topology = usbTopologyProbe.probeHikvisionDevice()
        let interpretation = privateControlPolicy.interpret(topology: topology)
        let capability = privateControlPolicy.decide(
            interpretation: interpretation,
            isAVFoundationRunning: false
        )
        let plan = privateControlExecutor.makeReadOnlyProbePlan(
            capability: capability,
            isAVFoundationRunning: false
        )

        usbTopology = topology
        usbInterpretation = interpretation
        privateControlCapability = capability
        privateControlPlan = plan
        statusMessage = plan.title
    }

    func applyAutoControls() {
        guard let selectedDeviceID,
              let device = manager.device(withUniqueID: selectedDeviceID) else {
            statusMessage = "No selected camera"
            return
        }

        do {
            try manager.configureSupportedAutoControls(on: device)
            controlStates = manager.controlStates(for: device)
            statusMessage = "Applied supported auto controls"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    @MainActor
    func saveCurrentFrame() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "ThermoCam-\(timestampForFilename()).png"
        panel.title = "Save Current Frame"

        panel.begin { @MainActor [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }

            self?.writeCurrentFrame(to: url)
        }
    }

    @MainActor
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    @MainActor
    func startRecording() {
        guard isRunning else {
            recordingStatus = "Start capture before recording"
            return
        }

        guard recordingAvailable else {
            recordingStatus = "Movie recording output is unavailable"
            return
        }

        guard !movieOutput.isRecording else {
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.quickTimeMovie]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "ThermoCam-\(timestampForFilename()).mov"
        panel.title = "Save Recording"

        panel.begin { @MainActor [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }

            self?.startRecording(to: url)
        }
    }

    @MainActor
    func stopRecording() {
        sessionQueue.async { [weak self] in
            guard let self else {
                return
            }

            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            }
        }
    }

    func setROIEnabled(_ isEnabled: Bool) {
        roiEnabled = isEnabled
        updateROIMeasurement()
    }

    func setROIValue(_ keyPath: ReferenceWritableKeyPath<CaptureSessionController, Double>, value: Double) {
        self[keyPath: keyPath] = value
        updateROIMeasurement()
    }

    private func restart() {
        configureAndStart(shouldStopFirst: true)
    }

    private func writeCurrentFrame(to url: URL) {
        photoSaveStatus = "Saving frame"

        outputQueue.async { [weak self] in
            guard let self else {
                return
            }

            guard let pixelBuffer = self.latestPixelBuffer else {
                DispatchQueue.main.async {
                    self.photoSaveStatus = "No frame is available yet"
                }
                return
            }

            let result = self.writePNG(pixelBuffer: pixelBuffer, to: url)

            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.photoSaveStatus = "Saved \(url.lastPathComponent)"
                case .failure(let error):
                    self.photoSaveStatus = "Save failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func writePNG(pixelBuffer: CVPixelBuffer, to url: URL) -> Result<Void, Error> {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let rect = CGRect(
            x: 0,
            y: 0,
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )

        guard let cgImage = imageContext.createCGImage(image, from: rect) else {
            return .failure(CameraCaptureError.cannotCreateImage)
        }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return .failure(CameraCaptureError.cannotCreateImageDestination)
        }

        CGImageDestinationAddImage(destination, cgImage, nil)

        if CGImageDestinationFinalize(destination) {
            return .success(())
        }

        return .failure(CameraCaptureError.cannotWriteImage)
    }

    @MainActor
    private func startRecording(to url: URL) {
        recordingStatus = "Starting recording"

        sessionQueue.async { [weak self] in
            guard let self else {
                return
            }

            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }

            self.movieOutput.startRecording(to: url, recordingDelegate: self)
        }
    }

    private func updateROIMeasurement() {
        guard roiEnabled else {
            roiMeasurement = .unsupported
            return
        }

        let selection = NormalizedROI(
            xPercent: roiXPercent,
            yPercent: roiYPercent,
            widthPercent: roiWidthPercent,
            heightPercent: roiHeightPercent
        )

        let region = roiRegionLabel(selection)

        roiMeasurement = ROITemperatureSnapshot(
            status: "Checking latest frame",
            region: region,
            minTemperature: "Unavailable",
            maxTemperature: "Unavailable",
            averageTemperature: "Unavailable"
        )

        outputQueue.async { [weak self, selection, region] in
            guard let self else {
                return
            }

            let measurement: ROITemperatureSnapshot
            if let pixelBuffer = self.latestPixelBuffer {
                measurement = self.thermalParser.measureROI(
                    pixelBuffer: pixelBuffer,
                    roi: selection
                ) ?? ROITemperatureSnapshot(
                    status: "No radiometric matrix",
                    region: region,
                    minTemperature: "No L016 matrix",
                    maxTemperature: "No L016 matrix",
                    averageTemperature: "No L016 matrix"
                )
            } else {
                measurement = ROITemperatureSnapshot(
                    status: "No frame available",
                    region: region,
                    minTemperature: "Unavailable",
                    maxTemperature: "Unavailable",
                    averageTemperature: "Unavailable"
                )
            }

            DispatchQueue.main.async { [weak self, measurement] in
                self?.roiMeasurement = measurement
            }
        }
    }

    private func timestampForFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private func roiRegionLabel(_ roi: NormalizedROI) -> String {
        String(
            format: "x %.0f%%, y %.0f%%, w %.0f%%, h %.0f%%",
            roi.xPercent,
            roi.yPercent,
            roi.widthPercent,
            roi.heightPercent
        )
    }

    private func configureAndStart(shouldStopFirst: Bool = false) {
        let requestedDeviceID = selectedDeviceID
        let requestedFormatID = selectedFormatID

        captureState = .starting
        statusMessage = shouldStopFirst ? "Reconfiguring camera" : "Starting camera"

        sessionQueue.async { [weak self] in
            guard let self else {
                return
            }

            do {
                if shouldStopFirst, self.session.isRunning {
                    self.session.stopRunning()
                }

                let result = try self.configureSession(
                    requestedDeviceID: requestedDeviceID,
                    requestedFormatID: requestedFormatID
                )

                self.resetFrameCounters()
                self.captureGeneration += 1
                let generation = self.captureGeneration

                if !self.session.isRunning {
                    self.session.startRunning()
                }

                guard self.session.isRunning else {
                    throw CameraCaptureError.cannotStartSession
                }

                self.scheduleFirstFrameWatchdog(generation: generation)

                DispatchQueue.main.async {
                    self.selectedDeviceID = result.deviceID
                    self.selectedFormatID = result.formatID
                    self.activeConfiguration = result.activeConfiguration
                    self.fallbackEvents = result.fallbackEvents
                    self.controlStates = result.controlStates
                    self.recordingAvailable = result.recordingAvailable
                    self.isRunning = true
                    self.captureState = .waitingForFirstFrame
                    self.statusMessage = "Waiting for first frame"
                    self.refreshUSBTopology()
                }
            } catch {
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.captureState = .failed
                    self.statusMessage = error.localizedDescription
                    self.refreshUSBTopology()
                }
            }
        }
    }

    private func configureSession(
        requestedDeviceID: String?,
        requestedFormatID: String?
    ) throws -> ConfigurationResult {
        let discoveredDevices = manager.discoverDevices()
        guard !discoveredDevices.isEmpty else {
            throw CameraCaptureError.noDevice
        }

        var fallbackEvents: [FallbackEvent] = []

        let device = requestedDeviceID.flatMap { requestedID in
            discoveredDevices.first { $0.uniqueID == requestedID }
        } ?? discoveredDevices[0]

        if requestedDeviceID != nil && requestedDeviceID != device.uniqueID {
            fallbackEvents.append(
                FallbackEvent(
                    stage: "device_selection",
                    reason: "Requested camera is no longer present",
                    decision: "Fallback to \(device.localizedName)"
                )
            )
        }

        let availableFormats = manager.formats(for: device)
        guard let bestFormat = manager.bestFormat(for: device, in: availableFormats) else {
            throw CameraCaptureError.noUsableFormat
        }

        let selectedFormat = requestedFormatID.flatMap { requestedID in
            availableFormats.first { $0.id == requestedID }
        } ?? bestFormat

        if requestedFormatID == nil,
           let event = manager.hikvisionFormatProfileEvent(for: device, selectedFormat: selectedFormat) {
            fallbackEvents.append(event)
        }

        if requestedFormatID != nil && requestedFormatID != selectedFormat.id {
            fallbackEvents.append(
                FallbackEvent(
                    stage: "format_selection",
                    reason: "Requested format is not present in AVCaptureDevice.formats",
                    decision: "Fallback to \(selectedFormat.label)"
                )
            )
        }

        if let frameRateFallback = try apply(format: selectedFormat, to: device) {
            fallbackEvents.append(frameRateFallback)
        }
        try manager.configureSupportedAutoControls(on: device)

        let input = try AVCaptureDeviceInput(device: device)

        session.beginConfiguration()

        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw CameraCaptureError.cannotAddInput
        }

        session.addInput(input)

        videoOutput.setSampleBufferDelegate(self, queue: outputQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true

        let outputPixelFormat = manager.preferredOutputPixelFormat(for: device)
        requestedOutputPixelFormat = outputPixelFormat
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: outputPixelFormat
        ]

        if let event = manager.hikvisionOutputPixelFormatEvent(
            for: device,
            outputPixelFormat: outputPixelFormat
        ) {
            fallbackEvents.append(event)
        }

        guard session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            throw CameraCaptureError.cannotAddOutput
        }

        session.addOutput(videoOutput)
        videoOutput.connection(with: .video)?.isEnabled = true

        let canRecordMovie = session.canAddOutput(movieOutput)
        if canRecordMovie {
            session.addOutput(movieOutput)
        } else {
            fallbackEvents.append(
                FallbackEvent(
                    stage: "recording",
                    reason: "AVCaptureSession rejected AVCaptureMovieFileOutput",
                    decision: "Disable video recording for this session"
                )
            )
        }

        session.commitConfiguration()

        return ConfigurationResult(
            deviceID: device.uniqueID,
            formatID: selectedFormat.id,
            activeConfiguration: ActiveConfiguration(
                requestedFormat: requestedFormatID == nil ? "Automatic" : selectedFormat.label,
                activeFormat: manager.activeFormatDescription(for: device),
                outputPixelFormat: pixelFormatName(outputPixelFormat)
            ),
            fallbackEvents: fallbackEvents,
            controlStates: manager.controlStates(for: device),
            recordingAvailable: canRecordMovie
        )
    }

    private func apply(format: CameraFormatInfo, to device: AVCaptureDevice) throws -> FallbackEvent? {
        let avFormat = device.formats[format.formatIndex]
        let duration = frameDuration(for: format.fps)

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        device.activeFormat = avFormat

        guard device.deviceType != .external else {
            return FallbackEvent(
                stage: "frame_rate",
                reason: "External UVC/DAL devices can terminate the process when forcing active frame duration",
                decision: "Use the selected active format and let AVFoundation report the actual frame duration"
            )
        }

        guard avFormat.videoSupportedFrameRateRanges.contains(where: { range in
            range.minFrameRate - 0.01 <= format.fps && format.fps <= range.maxFrameRate + 0.01
        }) else {
            return FallbackEvent(
                stage: "frame_rate",
                reason: "Requested frame rate is not inside the active format's supported ranges",
                decision: "Use the selected active format without forcing active frame duration"
            )
        }

        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
        return nil
    }

    private func frameDuration(for fps: Double) -> CMTime {
        let timescale = CMTimeScale(max(1, Int32((fps * 1000).rounded())))
        return CMTime(value: 1000, timescale: timescale)
    }

    private func resetFrameCounters() {
        outputQueue.sync {
            self.totalFrames = 0
            self.droppedFrames = 0
            self.framesInWindow = 0
            self.windowStartTime = CFAbsoluteTimeGetCurrent()
            self.lastPresentationTime = nil
            self.lastFrameIntervalMS = 0
            self.reportedPixelFormatMismatch = false
            self.latestPixelBuffer = nil

            DispatchQueue.main.async {
                self.diagnostics = .empty
                self.thermalInspection = .empty
                self.roiMeasurement = .unsupported
            }
        }
    }

    private func scheduleFirstFrameWatchdog(generation: Int) {
        sessionQueue.asyncAfter(deadline: .now() + firstFrameTimeout) { [weak self] in
            guard let self else {
                return
            }

            guard generation == self.captureGeneration, self.session.isRunning else {
                return
            }

            let frameCount = self.outputQueue.sync {
                self.totalFrames
            }

            guard frameCount == 0 else {
                return
            }

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.isRunning,
                      self.diagnostics.totalFrames == 0,
                      self.captureState == .waitingForFirstFrame else {
                    return
                }

                self.captureState = .noFrames
                self.statusMessage = "No frames from AVFoundation"
                self.fallbackEvents.removeAll { event in
                    event.stage == "stream_start"
                }

                let timeout = Int(self.firstFrameTimeout)
                let reason = """
                Camera permission is \(self.authorizationState.displayName) and AVCaptureSession is running, \
                but AVCaptureVideoDataOutput delivered no frame within \(timeout) seconds for \
                \(self.activeConfiguration.activeFormat) / \(self.activeConfiguration.outputPixelFormat)
                """
                let decision = """
                Treat this as a macOS UVC stream negotiation failure, not a SwiftUI drawing failure. \
                Compare the Windows UVC probe/commit parameters and try that known-good format profile \
                before adding private writes.
                """

                self.fallbackEvents.append(
                    FallbackEvent(
                        stage: "stream_start",
                        reason: reason,
                        decision: decision
                    )
                )
            }
        }
    }
}

extension CaptureSessionController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let isFirstFrame = totalFrames == 0
        totalFrames += 1
        framesInWindow += 1
        latestPixelBuffer = pixelBuffer

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if let lastPresentationTime {
            lastFrameIntervalMS = max(0, presentationTime.seconds - lastPresentationTime.seconds) * 1000
        }
        lastPresentationTime = presentationTime

        let deliveredPixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        if deliveredPixelFormat != requestedOutputPixelFormat && !reportedPixelFormatMismatch {
            reportedPixelFormatMismatch = true
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                if !self.fallbackEvents.contains(where: { $0.stage == "pixel_format" }) {
                    self.fallbackEvents.append(
                        FallbackEvent(
                            stage: "pixel_format",
                            reason: "Requested \(pixelFormatName(self.requestedOutputPixelFormat)) but received \(pixelFormatName(deliveredPixelFormat))",
                            decision: "Use delivered CVPixelBuffer format for the live processing path"
                        )
                    )
                }
            }
        }

        let metalSnapshot = metalPipeline.importPixelBuffer(pixelBuffer)
        if isFirstFrame {
            let firstFrameSnapshot = DiagnosticsSnapshot(
                totalFrames: totalFrames,
                droppedFrames: droppedFrames,
                measuredFPS: 0,
                frameIntervalMS: 0,
                frameSize: "\(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer))",
                deliveredPixelFormat: pixelFormatName(deliveredPixelFormat),
                metalStatus: metalSnapshot.status,
                metalTexture: metalSnapshot.textureDescription
            )

            DispatchQueue.main.async { [weak self, firstFrameSnapshot] in
                guard let self else {
                    return
                }

                self.captureState = .streaming
                self.statusMessage = "Streaming"
                self.diagnostics = firstFrameSnapshot
            }
        }

        let shouldInspectThermalData = totalFrames == 1 || totalFrames.isMultiple(of: 30)

        if shouldInspectThermalData {
            let thermalSnapshot = thermalParser.inspect(
                sampleBuffer: sampleBuffer,
                pixelBuffer: pixelBuffer,
                inspectedFrames: totalFrames
            )

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                self.thermalInspection = thermalSnapshot
                self.updateROIMeasurement()
            }
        }

        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - windowStartTime

        guard elapsed >= 0.5 else {
            return
        }

        let fps = Double(framesInWindow) / elapsed
        framesInWindow = 0
        windowStartTime = now

        let snapshot = DiagnosticsSnapshot(
            totalFrames: totalFrames,
            droppedFrames: droppedFrames,
            measuredFPS: fps,
            frameIntervalMS: lastFrameIntervalMS,
            frameSize: "\(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer))",
            deliveredPixelFormat: pixelFormatName(deliveredPixelFormat),
            metalStatus: metalSnapshot.status,
            metalTexture: metalSnapshot.textureDescription
        )

        DispatchQueue.main.async { [weak self] in
            self?.diagnostics = snapshot
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        droppedFrames += 1
    }
}

extension CaptureSessionController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.isRecording = true
            self?.recordingStatus = "Recording \(fileURL.lastPathComponent)"
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.isRecording = false

            if let error {
                self?.recordingStatus = "Recording failed: \(error.localizedDescription)"
            } else {
                self?.recordingStatus = "Saved \(outputFileURL.lastPathComponent)"
            }
        }
    }
}

private struct ConfigurationResult {
    let deviceID: String
    let formatID: String
    let activeConfiguration: ActiveConfiguration
    let fallbackEvents: [FallbackEvent]
    let controlStates: [CameraControlState]
    let recordingAvailable: Bool
}
