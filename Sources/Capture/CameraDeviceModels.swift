import CoreMedia
import Foundation

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
        requestedFormat: L10n.tr("None"),
        activeFormat: L10n.tr("None"),
        outputPixelFormat: L10n.tr("None")
    )
}
