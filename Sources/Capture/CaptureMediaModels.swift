import CoreVideo
import Foundation

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
            return L10n.tr("No AVFoundation video device is available.")
        case .noUsableFormat:
            return L10n.tr("The selected camera has no usable video format.")
        case .cannotAddInput:
            return L10n.tr("AVCaptureSession rejected the selected camera input.")
        case .cannotAddOutput:
            return L10n.tr("AVCaptureSession rejected AVCaptureVideoDataOutput.")
        case .cannotStartSession:
            return L10n.tr("AVCaptureSession did not enter the running state.")
        case .cannotCreateImage:
            return L10n.tr("Could not create a CGImage from the current CVPixelBuffer.")
        case .cannotCreateImageDestination:
            return L10n.tr("Could not create the selected image file.")
        case .cannotWriteImage:
            return L10n.tr("ImageIO could not write the selected image file.")
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
