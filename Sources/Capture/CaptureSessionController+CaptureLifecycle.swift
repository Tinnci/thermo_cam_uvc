import AVFoundation
import Foundation

extension CaptureSessionController {
    func start() {
        authorizationState = CameraAuthorizationState(
            status: AVCaptureDevice.authorizationStatus(for: .video)
        )

        switch authorizationState {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            statusMessage = L10n.tr("Requesting camera permission")
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
                        self.statusMessage = L10n.tr("Camera permission denied")
                    }
                }
            }
        case .denied:
            statusMessage = L10n.tr("Camera permission denied")
        case .restricted:
            statusMessage = L10n.tr("Camera permission restricted")
        }
    }

    func stop() {
        captureState = .stopping
        statusMessage = L10n.tr("Stopping")

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
                    self.statusMessage = L10n.tr("Capture stopped for private control")
                    self.beginPrivateControlReadOnlyProbe()
                } else {
                    self.captureState = .idle
                    self.statusMessage = L10n.tr("Stopped")
                    self.refreshUSBTopology()
                }
            }
        }
    }

    func restart() {
        configureAndStart(shouldStopFirst: true)
    }

    private func configureAndStart(shouldStopFirst: Bool = false) {
        let requestedDeviceID = selectedDeviceID
        let requestedFormatID = selectedFormatID

        captureState = .starting
        statusMessage = shouldStopFirst ? L10n.tr("Reconfiguring camera") : L10n.tr("Starting camera")

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
                    self.statusMessage = L10n.tr("Waiting for first frame")
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
}
