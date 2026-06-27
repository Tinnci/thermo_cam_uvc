import AVFoundation
import Foundation

extension CaptureSessionController {
    func refreshDevices() {
        let discoveredDevices = manager.discoverDevices()
        let infos = manager.deviceInfos(from: discoveredDevices)

        devices = infos

        if selectedDeviceID == nil || !infos.contains(where: { $0.id == selectedDeviceID }) {
            selectedDeviceID = infos.first?.id
        }

        refreshFormatsForSelectedDevice()

        if infos.isEmpty {
            statusMessage = L10n.tr("No AVFoundation camera device found")
        } else if statusMessage == L10n.tr("No AVFoundation camera device found") {
            statusMessage = L10n.tr("Idle")
        }

        refreshUSBTopology()
    }

    func selectDevice(_ uniqueID: String) {
        guard selectedDeviceID != uniqueID else {
            return
        }

        selectedDeviceID = uniqueID
        refreshFormatsForSelectedDevice()

        if isRunning {
            restart()
        }
    }

    func selectFormat(_ formatID: String) {
        guard selectedFormatID != formatID else {
            return
        }

        selectedFormatID = formatID

        if isRunning {
            restart()
        }
    }

    func applyAutoControls() {
        guard let selectedDeviceID,
              let device = manager.device(withUniqueID: selectedDeviceID) else {
            statusMessage = L10n.tr("No selected camera")
            return
        }

        do {
            try manager.configureSupportedAutoControls(on: device)
            controlStates = manager.controlStates(for: device)
            statusMessage = L10n.tr("Applied supported auto controls")
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func refreshFormatsForSelectedDevice() {
        guard let selectedDeviceID,
              let device = manager.device(withUniqueID: selectedDeviceID) else {
            formats = []
            selectedFormatID = nil
            controlStates = []
            return
        }

        let availableFormats = manager.formats(for: device)
        formats = availableFormats

        if selectedFormatID == nil || !availableFormats.contains(where: { $0.id == selectedFormatID }) {
            selectedFormatID = manager.bestFormat(for: device, in: availableFormats)?.id
        }

        controlStates = manager.controlStates(for: device)
    }
}
