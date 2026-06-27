import AVFoundation
import CoreMedia
import Foundation

extension CaptureSessionController {
    func configureSession(
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
        let useHikvisionCompatibility = shouldUseHikvisionCompatibilityProfile(
            for: device,
            discoveredDevices: discoveredDevices
        )

        if requestedDeviceID != nil && requestedDeviceID != device.uniqueID {
            fallbackEvents.append(
                FallbackEvent(
                    stage: "device_selection",
                    reason: L10n.tr("Requested camera is no longer present"),
                    decision: L10n.tr("Fallback to %@", device.localizedName)
                )
            )
        }

        let availableFormats = manager.formats(for: device)
        guard let bestFormat = manager.bestFormat(
            for: device,
            in: availableFormats,
            useHikvisionCompatibility: useHikvisionCompatibility
        ) else {
            throw CameraCaptureError.noUsableFormat
        }

        let requestedFormat = requestedFormatID.flatMap { requestedID in
            availableFormats.first { $0.id == requestedID }
        }
        let selectedFormat = useHikvisionCompatibility ? bestFormat : (requestedFormat ?? bestFormat)

        if let event = manager.hikvisionFormatProfileEvent(
            for: device,
            selectedFormat: selectedFormat,
            useHikvisionCompatibility: useHikvisionCompatibility
        ) {
            fallbackEvents.append(event)
        }

        if requestedFormatID != nil && requestedFormatID != selectedFormat.id {
            fallbackEvents.append(
                FallbackEvent(
                    stage: "format_selection",
                    reason: requestedFormat == nil
                        ? L10n.tr("Requested format is not present in AVCaptureDevice.formats")
                        : L10n.tr("HikCamera uses the measured native bulk target profile instead of the previously selected AVFoundation format"),
                    decision: L10n.tr("Fallback to %@", selectedFormat.label)
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

        let outputPixelFormat = configureVideoDataOutputPixelFormat(
            for: device,
            useHikvisionCompatibility: useHikvisionCompatibility,
            fallbackEvents: &fallbackEvents
        )

        guard session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            throw CameraCaptureError.cannotAddOutput
        }

        session.addOutput(videoOutput)
        videoOutput.connection(with: .video)?.isEnabled = true

        let canRecordMovie = session.canAddOutput(movieOutput)
        fallbackEvents.append(recordingAvailabilityEvent(canRecordMovie: canRecordMovie))

        session.commitConfiguration()

        return ConfigurationResult(
            deviceID: device.uniqueID,
            formatID: selectedFormat.id,
            activeConfiguration: ActiveConfiguration(
                requestedFormat: requestedFormatID == nil ? L10n.tr("Automatic") : selectedFormat.label,
                activeFormat: manager.activeFormatDescription(for: device),
                outputPixelFormat: outputPixelFormat.map(pixelFormatName) ?? L10n.tr("AVFoundation automatic")
            ),
            fallbackEvents: fallbackEvents,
            controlStates: manager.controlStates(for: device),
            recordingAvailable: canRecordMovie,
            requiresNativeBackendOnNoFrames: useHikvisionCompatibility
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
                reason: L10n.tr("External UVC/DAL devices can terminate the process when forcing active frame duration"),
                decision: L10n.tr("Use the selected active format and let AVFoundation report the actual frame duration")
            )
        }

        guard avFormat.videoSupportedFrameRateRanges.contains(where: { range in
            range.minFrameRate - 0.01 <= format.fps && format.fps <= range.maxFrameRate + 0.01
        }) else {
            return FallbackEvent(
                stage: "frame_rate",
                reason: L10n.tr("Requested frame rate is not inside the active format's supported ranges"),
                decision: L10n.tr("Use the selected active format without forcing active frame duration")
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

    func shouldUseHikvisionCompatibilityProfile(
        for device: AVCaptureDevice,
        discoveredDevices: [AVCaptureDevice]
    ) -> Bool {
        if manager.isHikvisionCamera(device) {
            return true
        }

        guard device.deviceType == .external else {
            return false
        }

        let externalDeviceCount = discoveredDevices.filter { $0.deviceType == .external }.count
        guard externalDeviceCount == 1 else {
            return false
        }

        let topology = usbTopologyProbe.probeHikvisionDevice()
        let interpretation = privateControlPolicy.interpret(topology: topology)
        return interpretation.isHikvisionDevicePresent && interpretation.hasUVCVideoStreaming
    }

    private func configureVideoDataOutputPixelFormat(
        for device: AVCaptureDevice,
        useHikvisionCompatibility: Bool,
        fallbackEvents: inout [FallbackEvent]
    ) -> FourCharCode? {
        let supportedOutputPixelFormats = videoOutput.availableVideoPixelFormatTypes

        if useHikvisionCompatibility {
            requestedOutputPixelFormat = nil
            videoOutput.videoSettings = nil
            fallbackEvents.append(
                FallbackEvent(
                    stage: "output_pixel_format",
                    reason: L10n.tr(
                        "Hikvision compatibility mode is active and fixed YUY2/BGRA/NV12 requests did not produce video"
                    ),
                    decision: L10n.tr("Do not request a CVPixelBuffer pixel format; let AVFoundation choose the native output")
                )
            )
            return nil
        }

        let outputPixelFormat = manager.preferredOutputPixelFormat(
            for: device,
            supportedPixelFormats: supportedOutputPixelFormats
        )
        requestedOutputPixelFormat = outputPixelFormat
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: outputPixelFormat
        ]

        if let event = manager.hikvisionOutputPixelFormatEvent(
            for: device,
            outputPixelFormat: outputPixelFormat,
            supportedPixelFormats: supportedOutputPixelFormats,
            useHikvisionCompatibility: useHikvisionCompatibility
        ) {
            fallbackEvents.append(event)
        }

        return outputPixelFormat
    }

    private func recordingAvailabilityEvent(canRecordMovie: Bool) -> FallbackEvent {
        if canRecordMovie {
            return FallbackEvent(
                stage: "recording",
                reason: L10n.tr("Movie recording output is available but not attached during preview startup"),
                decision: L10n.tr("Attach recording output only when recording starts to keep the live preview path simple")
            )
        }

        return FallbackEvent(
            stage: "recording",
            reason: L10n.tr("AVCaptureSession rejected AVCaptureMovieFileOutput"),
            decision: L10n.tr("Disable video recording for this session")
        )
    }
}
