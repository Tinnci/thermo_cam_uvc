import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

struct HikvisionCameraProfile {
    static let nativeBulkFormatName = "MJPG"
    static let nativeBulkWidth: Int32 = 240
    static let nativeBulkHeight: Int32 = 320
    static let nativeBulkFPS = 30.0
    private static let mjpgMediaSubType: FourCharCode = 0x4D4A5047

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
        if let measuredNativeTarget = formats.first(where: isMeasuredNativeBulkTarget) {
            return measuredNativeTarget
        }

        return formats.min { left, right in
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
                "Hikvision bulk-only UVC camera detected; exclusive native probing produced a valid JPEG frame at MJPG 240x320 @ 30 fps"
            ),
            decision: L10n.tr("Use the measured HikCamera native bulk target profile: %@", selectedFormat.label)
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
        if isMeasuredNativeBulkTarget(format) {
            return 0
        }

        let resolutionScore: Int
        if format.width == Self.nativeBulkWidth && format.height == Self.nativeBulkHeight {
            resolutionScore = 0
        } else if format.width == 320 && format.height == 240 {
            resolutionScore = 10
        } else if format.width == 640 && format.height == 360 {
            resolutionScore = 20
        } else if format.width == 640 && format.height == 480 {
            resolutionScore = 30
        } else {
            let pixels = Int(format.width) * Int(format.height)
            resolutionScore = pixels <= 640 * 512 ? 40 : 70
        }

        let frameRateScore = Int((abs(format.fps - 30) * 10).rounded())
        let pixelFormatScore = pixelFormatScore(format.mediaSubType)
        return resolutionScore + frameRateScore + pixelFormatScore
    }

    private func pixelFormatScore(_ mediaSubType: FourCharCode) -> Int {
        switch mediaSubType {
        case Self.mjpgMediaSubType:
            return 0
        case kCVPixelFormatType_422YpCbCr8_yuvs:
            return 8
        case kCVPixelFormatType_422YpCbCr8:
            return 10
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            return 12
        default:
            return 16
        }
    }

    private func isMeasuredNativeBulkTarget(_ format: CameraFormatInfo) -> Bool {
        format.mediaSubType == Self.mjpgMediaSubType &&
            format.width == Self.nativeBulkWidth &&
            format.height == Self.nativeBulkHeight &&
            abs(format.fps - Self.nativeBulkFPS) < 0.01
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
