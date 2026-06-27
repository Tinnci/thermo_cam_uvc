import Foundation

struct ThermalInspectionSnapshot: Equatable, Sendable {
    var inspectedFrames: Int
    var status: String
    var evidence: String
    var matrixSize: String

    static let empty = ThermalInspectionSnapshot(
        inspectedFrames: 0,
        status: L10n.tr("Not inspected"),
        evidence: L10n.tr("Capture has not delivered a frame yet"),
        matrixSize: L10n.tr("Unavailable")
    )
}

struct ROITemperatureSnapshot: Equatable, Sendable {
    var status: String
    var region: String
    var minTemperature: String
    var maxTemperature: String
    var averageTemperature: String

    static let unsupported = ROITemperatureSnapshot(
        status: L10n.tr("Unavailable"),
        region: L10n.tr("None"),
        minTemperature: L10n.tr("No radiometric matrix"),
        maxTemperature: L10n.tr("No radiometric matrix"),
        averageTemperature: L10n.tr("No radiometric matrix")
    )
}
