import Foundation

struct AdvancedFeatureState: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let status: String
    let backend: String
    let reason: String
    let nextStep: String

    static let currentDefaults = [
        AdvancedFeatureState(
            id: "thermal_private_data",
            name: L10n.tr("Thermal Private Data"),
            status: L10n.tr("Partial"),
            backend: "CMSampleBuffer / CVPixelBuffer",
            reason: L10n.tr("The parser detects L016 raw matrices and thermal metadata keys in delivered AVFoundation frames"),
            nextStep: L10n.tr("Confirm Hikvision append-data layout before applying calibrated temperature conversion")
        ),
        AdvancedFeatureState(
            id: "hikvision_usb_control",
            name: L10n.tr("Hikvision USB Control"),
            status: L10n.tr("Not enabled"),
            backend: L10n.tr("IOUSBHost / vendor protocol"),
            reason: L10n.tr("macOS UVCAssistant owns the standard UVC interfaces while AVFoundation is active"),
            nextStep: L10n.tr("Design a separate private-control helper after command transport is confirmed")
        ),
        AdvancedFeatureState(
            id: "virtual_camera",
            name: L10n.tr("Virtual Camera Output"),
            status: L10n.tr("Not enabled"),
            backend: L10n.tr("Core Media I/O Camera Extension"),
            reason: L10n.tr("Virtual camera output requires a separate System Extension target"),
            nextStep: L10n.tr("Add a CoreMediaIO Camera Extension target when processed output must appear in Zoom/Teams")
        )
    ]
}
