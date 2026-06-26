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
        CommandMenu("Capture") {
            Button("Start or Stop Capture") {
                actions?.toggleCapture()
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(actions == nil)

            Button("Stop Capture") {
                actions?.stopCapture()
            }
            .keyboardShortcut(".", modifiers: [.command])
            .disabled(actions == nil)

            Divider()

            Button("Save Current Frame") {
                actions?.saveCurrentFrame()
            }
            .keyboardShortcut("s", modifiers: [.command])
            .disabled(actions == nil)

            Button("Start or Stop Recording") {
                actions?.toggleRecording()
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(actions == nil)

            Divider()

            Button("Refresh Devices") {
                actions?.refreshDevices()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(actions == nil)

            Button("Apply Auto Controls") {
                actions?.applyAutoControls()
            }
            .disabled(actions == nil)

            Divider()

            Button("Refresh USB Topology") {
                actions?.refreshUSBTopology()
            }
            .disabled(actions == nil)

            Button("Enter Private Control Probe") {
                actions?.enterPrivateControlMode()
            }
            .disabled(actions == nil)
        }
    }
}
