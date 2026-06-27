import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

struct HikvisionCameraProfile {
    func preferredOutputPixelFormat(in supportedPixelFormats: [FourCharCode]) -> FourCharCode {
        let preferences = [
            kCVPixelFormatType_32BGRA,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelFormatType_422YpCbCr8_yuvs,
            kCVPixelFormatType_422YpCbCr8
        ]

        return preferences.first { supportedPixelFormats.contains($0) } ?? kCVPixelFormatType_32BGRA
    }

    func matches(_ device: AVCaptureDevice) -> Bool {
        let name = device.localizedName.lowercased()
        let id = device.uniqueID.lowercased()
        return name.contains("hik") ||
            name.contains("hikvision") ||
            id.contains("2bdf") ||
            id.contains("0x2bdf")
    }

    func compatibilityFormat(in formats: [CameraFormatInfo]) -> CameraFormatInfo? {
        formats.min { left, right in
            let leftScore = compatibilityScore(left)
            let rightScore = compatibilityScore(right)

            if leftScore != rightScore {
                return leftScore < rightScore
            }

            return formatPreference(right, left)
        }
    }

    func formatProfileEvent(
        for device: AVCaptureDevice,
        selectedFormat: CameraFormatInfo,
        useHikvisionCompatibility: Bool
    ) -> FallbackEvent? {
        guard useHikvisionCompatibility else {
            return nil
        }

        return FallbackEvent(
            stage: "format_profile",
            reason: L10n.tr(
                "Hikvision bulk-only UVC camera detected; Windows can drive its standard UVC path, but macOS AVFoundation may enumerate it without delivering frames"
            ),
            decision: L10n.tr("Start with a conservative UVC compatibility format: %@", selectedFormat.label)
        )
    }

    func outputPixelFormatEvent(
        for device: AVCaptureDevice,
        outputPixelFormat: FourCharCode,
        supportedPixelFormats: [FourCharCode],
        useHikvisionCompatibility: Bool
    ) -> FallbackEvent? {
        guard useHikvisionCompatibility else {
            return nil
        }

        let supported = supportedPixelFormats
            .map(pixelFormatName)
            .joined(separator: ", ")

        return FallbackEvent(
            stage: "output_pixel_format",
            reason: L10n.tr(
                "Hikvision Windows DirectShow can read the camera, but macOS CVPixelBuffer output should use a format AVFoundation can reliably deliver. Supported outputs: %@",
                supported.isEmpty ? L10n.tr("Unknown") : supported
            ),
            decision: L10n.tr(
                "Request %@ CVPixelBuffer output and keep the UVC active format selection separate from the app pixel-buffer format",
                pixelFormatName(outputPixelFormat)
            )
        )
    }

    private func compatibilityScore(_ format: CameraFormatInfo) -> Int {
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
        let pixelFormatScore = pixelFormatScore(format.mediaSubType)
        return resolutionScore + frameRateScore + pixelFormatScore
    }

    private func pixelFormatScore(_ mediaSubType: FourCharCode) -> Int {
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
}
