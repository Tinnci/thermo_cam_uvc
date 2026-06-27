import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

final class CameraDeviceManager {
    private let hikvisionProfile = HikvisionCameraProfile()

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
           let preferred = hikvisionProfile.compatibilityFormat(in: formats) {
            return preferred
        }

        return bestFormat(in: formats)
    }

    func isHikvisionCamera(_ device: AVCaptureDevice) -> Bool {
        hikvisionProfile.matches(device)
    }

    func preferredOutputPixelFormat(for device: AVCaptureDevice) -> FourCharCode {
        if isHikvisionCamera(device) {
            return hikvisionProfile.preferredOutputPixelFormat
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

    func hikvisionFormatProfileEvent(
        for device: AVCaptureDevice,
        selectedFormat: CameraFormatInfo
    ) -> FallbackEvent? {
        hikvisionProfile.formatProfileEvent(for: device, selectedFormat: selectedFormat)
    }

    func hikvisionOutputPixelFormatEvent(
        for device: AVCaptureDevice,
        outputPixelFormat: FourCharCode
    ) -> FallbackEvent? {
        hikvisionProfile.outputPixelFormatEvent(for: device, outputPixelFormat: outputPixelFormat)
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
}
