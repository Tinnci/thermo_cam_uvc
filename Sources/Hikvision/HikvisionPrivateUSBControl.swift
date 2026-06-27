import Foundation

struct HikvisionPrivateUSBCommand: Identifiable, Equatable, Sendable {
    let code: Int
    let symbol: String
    let purpose: String

    var id: Int {
        code
    }
}

enum HikvisionPrivateUSBControl {
    static let knownCommands = [
        HikvisionPrivateUSBCommand(
            code: 2030,
            symbol: "USB_GET_THERMOMETRY_BASIC_PARAM",
            purpose: L10n.tr("Read thermometry baseline parameters")
        ),
        HikvisionPrivateUSBCommand(
            code: 2038,
            symbol: "USB_GET_THERMAL_STREAM_PARAM",
            purpose: L10n.tr("Read thermal stream parameters")
        ),
        HikvisionPrivateUSBCommand(
            code: 2046,
            symbol: "USB_GET_JPEGPIC_WITH_APPENDDATA",
            purpose: L10n.tr("Request JPEG image with appended private data")
        )
    ]
}
