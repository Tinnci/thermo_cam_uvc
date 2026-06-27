import Foundation
import IOKit

final class USBTopologyProbe: @unchecked Sendable {
    private let hikvisionVendorID = 0x2BDF

    func probeHikvisionDevice() -> USBTopologySnapshot {
        let interfaces = interfaceDictionaries()
            .filter { integerValue($0["idVendor"]) == hikvisionVendorID }
            .compactMap(makeInterfaceFact)
            .sorted { left, right in
                if left.number == right.number {
                    return left.alternateSetting < right.alternateSetting
                }

                return left.number < right.number
            }

        return USBTopologySnapshot(
            status: interfaces.isEmpty ? L10n.tr("No Hikvision USB interface found") : L10n.tr("Probed"),
            deviceSummary: deviceSummary(),
            interfaces: interfaces
        )
    }

    private func interfaceDictionaries() -> [[String: Any]] {
        registryDictionaries(matchingClassName: "IOUSBInterface")
    }

    private func deviceSummary() -> String {
        let devices = registryDictionaries(matchingClassName: "IOUSBDevice")
        guard let device = devices.first(where: { dictionary in
            integerValue(dictionary["idVendor"]) == hikvisionVendorID
        }) else {
            return L10n.tr("No HIKVISION USB device found")
        }

        let vendor = stringValue(device["USB Vendor Name"])
            ?? stringValue(device["kUSBVendorString"])
            ?? "HIKVISION"
        let product = stringValue(device["USB Product Name"])
            ?? stringValue(device["kUSBProductString"])
            ?? L10n.tr("Unknown product")
        let productID = integerValue(device["idProduct"]).map { String(format: "0x%04X", $0) } ?? L10n.tr("unknown PID")
        let serial = stringValue(device["USB Serial Number"])
            ?? stringValue(device["kUSBSerialNumberString"])
            ?? L10n.tr("no serial")

        return "\(vendor) \(product), VID 0x2BDF, PID \(productID), serial \(serial)"
    }

    private func registryDictionaries(matchingClassName: String) -> [[String: Any]] {
        var iterator: io_iterator_t = 0
        let status = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching(matchingClassName),
            &iterator
        )

        guard status == KERN_SUCCESS else {
            return []
        }

        defer {
            IOObjectRelease(iterator)
        }

        var results: [[String: Any]] = []

        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else {
                break
            }

            if let dictionary = properties(for: service) {
                results.append(dictionary)
            }

            IOObjectRelease(service)
        }

        return results
    }

    private func properties(for service: io_object_t) -> [String: Any]? {
        var unmanagedProperties: Unmanaged<CFMutableDictionary>?
        let status = IORegistryEntryCreateCFProperties(
            service,
            &unmanagedProperties,
            kCFAllocatorDefault,
            0
        )

        guard status == KERN_SUCCESS,
              let properties = unmanagedProperties?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        return properties
    }

    private func makeInterfaceFact(_ dictionary: [String: Any]) -> USBInterfaceFact? {
        guard let number = integerValue(dictionary["bInterfaceNumber"]),
              let interfaceClass = integerValue(dictionary["bInterfaceClass"]),
              let subClass = integerValue(dictionary["bInterfaceSubClass"]),
              let interfaceProtocol = integerValue(dictionary["bInterfaceProtocol"]) else {
            return nil
        }

        let alternateSetting = integerValue(dictionary["bAlternateSetting"]) ?? 0
        let endpointCount = integerValue(dictionary["bNumEndpoints"]) ?? 0
        let productID = integerValue(dictionary["idProduct"]) ?? 0
        let name = stringValue(dictionary["USB Interface Name"]) ?? L10n.tr("Interface %@", "\(number)")

        return USBInterfaceFact(
            id: "\(productID):\(number):\(alternateSetting)",
            number: number,
            interfaceClass: interfaceClass,
            interfaceSubClass: subClass,
            interfaceProtocol: interfaceProtocol,
            alternateSetting: alternateSetting,
            endpointCount: endpointCount,
            name: name
        )
    }

    private func integerValue(_ value: Any?) -> Int? {
        if let integer = value as? Int {
            return integer
        }

        if let number = value as? NSNumber {
            return number.intValue
        }

        if let string = value as? String {
            return Int(string)
        }

        return nil
    }

    private func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            return string
        }

        if let value {
            return String(describing: value)
        }

        return nil
    }
}
