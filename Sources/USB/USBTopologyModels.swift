import Foundation

struct USBTopologyInterpretation: Equatable, Sendable {
    let isHikvisionDevicePresent: Bool
    let hasVendorSpecificInterface: Bool
    let hasUVCVideoControl: Bool
    let hasUVCVideoStreaming: Bool
    let transport: HikvisionPrivateTransport
    let summary: String
    let evidence: String

    static let unknown = USBTopologyInterpretation(
        isHikvisionDevicePresent: false,
        hasVendorSpecificInterface: false,
        hasUVCVideoControl: false,
        hasUVCVideoStreaming: false,
        transport: .unknown,
        summary: L10n.tr("USB topology has not been interpreted"),
        evidence: L10n.tr("No USB facts available")
    )
}

struct USBInterfaceFact: Identifiable, Equatable, Sendable {
    let id: String
    let number: Int
    let interfaceClass: Int
    let interfaceSubClass: Int
    let interfaceProtocol: Int
    let alternateSetting: Int
    let endpointCount: Int
    let name: String

    var classLabel: String {
        switch interfaceClass {
        case 14:
            switch interfaceSubClass {
            case 1:
                return L10n.tr("VideoControl")
            case 2:
                return L10n.tr("VideoStreaming")
            default:
                return L10n.tr("Video")
            }
        case 255:
            return L10n.tr("Vendor Specific")
        default:
            return L10n.tr("Class %@", "\(interfaceClass)")
        }
    }
}

struct USBTopologySnapshot: Equatable, Sendable {
    let status: String
    let deviceSummary: String
    let interfaces: [USBInterfaceFact]

    static let unknown = USBTopologySnapshot(
        status: L10n.tr("Not probed"),
        deviceSummary: L10n.tr("No Hikvision USB facts loaded"),
        interfaces: []
    )
}
