import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

final class CameraDeviceManager {
    func discoverDevices() -> [AVCaptureDevice] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .external,
                .builtInWideAngleCamera
            ],
            mediaType: .video,
            position: .unspecified
        )

        var seen = Set<String>()
        return discovery.devices
            .filter { seen.insert($0.uniqueID).inserted }
            .sorted { left, right in
                if left.deviceType == right.deviceType {
                    return left.localizedName.localizedCaseInsensitiveCompare(right.localizedName) == .orderedAscending
                }

                return left.deviceType == .external
            }
    }

    func device(withUniqueID uniqueID: String) -> AVCaptureDevice? {
        discoverDevices().first { $0.uniqueID == uniqueID }
    }

    func deviceInfos(from devices: [AVCaptureDevice]) -> [CameraDeviceInfo] {
        devices.map { device in
            CameraDeviceInfo(
                id: device.uniqueID,
                localizedName: device.localizedName,
                deviceType: deviceTypeLabel(device.deviceType),
                position: positionLabel(device.position)
            )
        }
    }

    func formats(for device: AVCaptureDevice) -> [CameraFormatInfo] {
        device.formats.enumerated().flatMap { index, format -> [CameraFormatInfo] in
            let description = format.formatDescription
            let dimensions = CMVideoFormatDescriptionGetDimensions(description)
            let mediaSubType = CMFormatDescriptionGetMediaSubType(description)
            let ranges = format.videoSupportedFrameRateRanges
            let rangeDescription = ranges
                .map { range in
                    "\(formatFPSLabel(range.minFrameRate))-\(formatFPSLabel(range.maxFrameRate))"
                }
                .joined(separator: ", ")

            return candidateFrameRates(in: ranges).map { fps in
                let id = [
                    "\(index)",
                    "\(dimensions.width)x\(dimensions.height)",
                    "\(mediaSubType)",
                    formatFPSLabel(fps)
                ].joined(separator: ":")

                return CameraFormatInfo(
                    id: id,
                    formatIndex: index,
                    width: dimensions.width,
                    height: dimensions.height,
                    fps: fps,
                    mediaSubType: mediaSubType,
                    frameRateRangeDescription: rangeDescription
                )
            }
        }
    }

    func bestFormat(for device: AVCaptureDevice, in formats: [CameraFormatInfo]) -> CameraFormatInfo? {
        if isHikvisionCamera(device),
           let preferred = hikvisionCompatibilityFormat(in: formats) {
            return preferred
        }

        return bestFormat(in: formats)
    }

    func isHikvisionCamera(_ device: AVCaptureDevice) -> Bool {
        let name = device.localizedName.lowercased()
        let id = device.uniqueID.lowercased()
        return name.contains("hik") ||
            name.contains("hikvision") ||
            id.contains("2bdf") ||
            id.contains("0x2bdf")
    }

    func preferredOutputPixelFormat(for device: AVCaptureDevice) -> FourCharCode {
        if isHikvisionCamera(device) {
            return kCVPixelFormatType_422YpCbCr8_yuvs
        }

        return kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    }

    func activeFormatDescription(for device: AVCaptureDevice) -> String {
        let description = device.activeFormat.formatDescription
        let dimensions = CMVideoFormatDescriptionGetDimensions(description)
        let mediaSubType = CMFormatDescriptionGetMediaSubType(description)
        let duration = device.activeVideoMinFrameDuration
        let fps = duration.seconds > 0 ? 1.0 / duration.seconds : 0

        return "\(dimensions.width)x\(dimensions.height) @ \(formatFPSLabel(fps)) fps - \(pixelFormatName(mediaSubType))"
    }

    func configureSupportedAutoControls(on device: AVCaptureDevice) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }

        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            device.whiteBalanceMode = .continuousAutoWhiteBalance
        }

        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
    }

    func hikvisionFormatProfileEvent(
        for device: AVCaptureDevice,
        selectedFormat: CameraFormatInfo
    ) -> FallbackEvent? {
        guard isHikvisionCamera(device) else {
            return nil
        }

        return FallbackEvent(
            stage: "format_profile",
            reason: "Hikvision camera detected; Android APK uses YUY2/30fps and Windows proves a standard UVC video path exists",
            decision: "Start with a conservative UVC compatibility format: \(selectedFormat.label)"
        )
    }

    func hikvisionOutputPixelFormatEvent(
        for device: AVCaptureDevice,
        outputPixelFormat: FourCharCode
    ) -> FallbackEvent? {
        guard isHikvisionCamera(device) else {
            return nil
        }

        return FallbackEvent(
            stage: "output_pixel_format",
            reason: "Hikvision Android preview config requests YUY2 before starting stream callbacks",
            decision: "Request \(pixelFormatName(outputPixelFormat)) CVPixelBuffer output when AVFoundation supports it"
        )
    }

    func controlStates(for device: AVCaptureDevice) -> [CameraControlState] {
        [
            CameraControlState(
                id: "exposure_auto",
                name: "Exposure",
                available: device.isExposureModeSupported(.continuousAutoExposure),
                backend: "AVCaptureDevice",
                mode: exposureModeLabel(device.exposureMode),
                reason: device.isExposureModeSupported(.continuousAutoExposure)
                    ? "continuousAutoExposure is supported"
                    : "isExposureModeSupported(.continuousAutoExposure) == false"
            ),
            CameraControlState(
                id: "white_balance_auto",
                name: "White Balance",
                available: device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance),
                backend: "AVCaptureDevice",
                mode: whiteBalanceModeLabel(device.whiteBalanceMode),
                reason: device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance)
                    ? "continuousAutoWhiteBalance is supported"
                    : "isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) == false"
            ),
            CameraControlState(
                id: "focus_auto",
                name: "Focus",
                available: device.isFocusModeSupported(.continuousAutoFocus),
                backend: "AVCaptureDevice",
                mode: focusModeLabel(device.focusMode),
                reason: device.isFocusModeSupported(.continuousAutoFocus)
                    ? "continuousAutoFocus is supported"
                    : "isFocusModeSupported(.continuousAutoFocus) == false"
            ),
            CameraControlState(
                id: "uvc_extension_unit",
                name: "UVC Extension Unit",
                available: false,
                backend: "IOUSBHost",
                mode: "Unavailable",
                reason: "Standard UVC video interface is owned by the macOS camera stack"
            )
        ]
    }

    private func bestFormat(in formats: [CameraFormatInfo]) -> CameraFormatInfo? {
        if let fullHD30 = formats.first(where: { format in
            format.width == 1920 && format.height == 1080 && abs(format.fps - 30) < 0.01
        }) {
            return fullHD30
        }

        let normalFPSFormats = formats.filter { $0.fps <= 30.01 }
        if let bestNormal = normalFPSFormats.max(by: formatPreference) {
            return bestNormal
        }

        return formats.max(by: formatPreference)
    }

    private func hikvisionCompatibilityFormat(in formats: [CameraFormatInfo]) -> CameraFormatInfo? {
        formats.min { left, right in
            let leftScore = hikvisionCompatibilityScore(left)
            let rightScore = hikvisionCompatibilityScore(right)

            if leftScore != rightScore {
                return leftScore < rightScore
            }

            return formatPreference(right, left)
        }
    }

    private func hikvisionCompatibilityScore(_ format: CameraFormatInfo) -> Int {
        let resolutionScore: Int
        switch (format.width, format.height) {
        case (640, 360):
            resolutionScore = 0
        case (640, 480):
            resolutionScore = 10
        case (320, 240), (240, 320):
            resolutionScore = 20
        default:
            let pixels = Int(format.width) * Int(format.height)
            resolutionScore = pixels <= 640 * 512 ? 30 : 60
        }

        let frameRateScore = Int((abs(format.fps - 30) * 10).rounded())
        let pixelFormatScore = hikvisionPixelFormatScore(format.mediaSubType)
        return resolutionScore + frameRateScore + pixelFormatScore
    }

    private func hikvisionPixelFormatScore(_ mediaSubType: FourCharCode) -> Int {
        switch mediaSubType {
        case kCVPixelFormatType_422YpCbCr8_yuvs:
            return 0
        case kCVPixelFormatType_422YpCbCr8:
            return 2
        case 0x4D4A5047:
            return 4
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            return 8
        default:
            return 12
        }
    }

    private func formatPreference(_ left: CameraFormatInfo, _ right: CameraFormatInfo) -> Bool {
        let leftPixels = Int64(left.width) * Int64(left.height)
        let rightPixels = Int64(right.width) * Int64(right.height)

        if leftPixels != rightPixels {
            return leftPixels < rightPixels
        }

        return left.fps < right.fps
    }

    private func candidateFrameRates(in ranges: [AVFrameRateRange]) -> [Double] {
        let commonRates = [15.0, 24.0, 25.0, 29.97, 30.0, 50.0, 59.94, 60.0, 90.0, 120.0]
        var values: [Double] = []

        for range in ranges {
            for fps in commonRates where contains(range: range, fps: fps) {
                values.append(roundToHundredths(fps))
            }

            values.append(roundToHundredths(range.maxFrameRate))
        }

        return values
            .sorted()
            .reduce(into: [Double]()) { result, fps in
                if !result.contains(where: { abs($0 - fps) < 0.01 }) {
                    result.append(fps)
                }
            }
    }

    private func contains(range: AVFrameRateRange, fps: Double) -> Bool {
        range.minFrameRate - 0.01 <= fps && fps <= range.maxFrameRate + 0.01
    }

    private func roundToHundredths(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    private func deviceTypeLabel(_ type: AVCaptureDevice.DeviceType) -> String {
        switch type {
        case .external:
            return "External"
        case .builtInWideAngleCamera:
            return "Built-in"
        default:
            return type.rawValue
        }
    }

    private func positionLabel(_ position: AVCaptureDevice.Position) -> String {
        switch position {
        case .front:
            return "Front"
        case .back:
            return "Back"
        case .unspecified:
            return "Unspecified"
        @unknown default:
            return "Unknown"
        }
    }

    private func exposureModeLabel(_ mode: AVCaptureDevice.ExposureMode) -> String {
        switch mode {
        case .continuousAutoExposure:
            return "continuousAutoExposure"
        case .autoExpose:
            return "autoExpose"
        case .locked:
            return "locked"
        case .custom:
            return "custom"
        @unknown default:
            return "unknown"
        }
    }

    private func whiteBalanceModeLabel(_ mode: AVCaptureDevice.WhiteBalanceMode) -> String {
        switch mode {
        case .continuousAutoWhiteBalance:
            return "continuousAutoWhiteBalance"
        case .autoWhiteBalance:
            return "autoWhiteBalance"
        case .locked:
            return "locked"
        @unknown default:
            return "unknown"
        }
    }

    private func focusModeLabel(_ mode: AVCaptureDevice.FocusMode) -> String {
        switch mode {
        case .continuousAutoFocus:
            return "continuousAutoFocus"
        case .autoFocus:
            return "autoFocus"
        case .locked:
            return "locked"
        @unknown default:
            return "unknown"
        }
    }
}
