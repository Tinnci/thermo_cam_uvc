import SwiftUI

struct CaptureCommandActions {
    var toggleCapture: () -> Void
    var stopCapture: () -> Void
    var refreshDevices: () -> Void
    var applyAutoControls: () -> Void
    var saveCurrentFrame: () -> Void
    var toggleRecording: () -> Void
    var refreshUSBTopology: () -> Void
    var enterPrivateControlMode: () -> Void
}

private struct CaptureCommandActionsKey: FocusedValueKey {
    typealias Value = CaptureCommandActions
}

extension FocusedValues {
    var captureCommandActions: CaptureCommandActions? {
        get { self[CaptureCommandActionsKey.self] }
        set { self[CaptureCommandActionsKey.self] = newValue }
    }
}

struct CaptureCommands: Commands {
    @FocusedValue(\.captureCommandActions) private var actions

    var body: some Commands {
        CommandMenu(L10n.tr("Capture")) {
            Button(L10n.tr("Start or Stop Capture")) {
                actions?.toggleCapture()
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(actions == nil)

            Button(L10n.tr("Stop Capture")) {
                actions?.stopCapture()
            }
            .keyboardShortcut(".", modifiers: [.command])
            .disabled(actions == nil)

            Divider()

            Button(L10n.tr("Save Current Frame")) {
                actions?.saveCurrentFrame()
            }
            .keyboardShortcut("s", modifiers: [.command])
            .disabled(actions == nil)

            Button(L10n.tr("Start or Stop Recording")) {
                actions?.toggleRecording()
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(actions == nil)

            Divider()

            Button(L10n.tr("Refresh Devices")) {
                actions?.refreshDevices()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(actions == nil)

            Button(L10n.tr("Apply Auto Controls")) {
                actions?.applyAutoControls()
            }
            .disabled(actions == nil)

            Divider()

            Button(L10n.tr("Refresh USB Topology")) {
                actions?.refreshUSBTopology()
            }
            .disabled(actions == nil)

            Button(L10n.tr("Enter Private Control Probe")) {
                actions?.enterPrivateControlMode()
            }
            .disabled(actions == nil)
        }
    }
}
