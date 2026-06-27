import AVFoundation
import Foundation

extension CameraDeviceManager {
    func configureSupportedAutoControls(on device: AVCaptureDevice) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }

        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            device.whiteBalanceMode = .continuousAutoWhiteBalance
        }

        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
    }

    func controlStates(for device: AVCaptureDevice) -> [CameraControlState] {
        [
            CameraControlState(
                id: "exposure_auto",
                name: L10n.tr("Exposure"),
                available: device.isExposureModeSupported(.continuousAutoExposure),
                backend: "AVCaptureDevice",
                mode: exposureModeLabel(device.exposureMode),
                reason: device.isExposureModeSupported(.continuousAutoExposure)
                    ? L10n.tr("continuousAutoExposure is supported")
                    : L10n.tr("continuousAutoExposure is unsupported")
            ),
            CameraControlState(
                id: "white_balance_auto",
                name: L10n.tr("White Balance"),
                available: device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance),
                backend: "AVCaptureDevice",
                mode: whiteBalanceModeLabel(device.whiteBalanceMode),
                reason: device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance)
                    ? L10n.tr("continuousAutoWhiteBalance is supported")
                    : L10n.tr("continuousAutoWhiteBalance is unsupported")
            ),
            CameraControlState(
                id: "focus_auto",
                name: L10n.tr("Focus"),
                available: device.isFocusModeSupported(.continuousAutoFocus),
                backend: "AVCaptureDevice",
                mode: focusModeLabel(device.focusMode),
                reason: device.isFocusModeSupported(.continuousAutoFocus)
                    ? L10n.tr("continuousAutoFocus is supported")
                    : L10n.tr("continuousAutoFocus is unsupported")
            ),
            CameraControlState(
                id: "uvc_extension_unit",
                name: L10n.tr("UVC Extension Unit"),
                available: false,
                backend: "IOUSBHost",
                mode: L10n.tr("Unavailable"),
                reason: L10n.tr("Standard UVC video interface is owned by the macOS camera stack")
            )
        ]
    }

    func deviceTypeLabel(_ type: AVCaptureDevice.DeviceType) -> String {
        switch type {
        case .external:
            return L10n.tr("External")
        case .builtInWideAngleCamera:
            return L10n.tr("Built-in")
        default:
            return type.rawValue
        }
    }

    func positionLabel(_ position: AVCaptureDevice.Position) -> String {
        switch position {
        case .front:
            return L10n.tr("Front")
        case .back:
            return L10n.tr("Back")
        case .unspecified:
            return L10n.tr("Unspecified")
        @unknown default:
            return L10n.tr("Unknown")
        }
    }

    private func exposureModeLabel(_ mode: AVCaptureDevice.ExposureMode) -> String {
        switch mode {
        case .continuousAutoExposure:
            return L10n.tr("continuousAutoExposure")
        case .autoExpose:
            return L10n.tr("autoExpose")
        case .locked:
            return L10n.tr("locked")
        case .custom:
            return L10n.tr("custom")
        @unknown default:
            return L10n.tr("unknown")
        }
    }

    private func whiteBalanceModeLabel(_ mode: AVCaptureDevice.WhiteBalanceMode) -> String {
        switch mode {
        case .continuousAutoWhiteBalance:
            return L10n.tr("continuousAutoWhiteBalance")
        case .autoWhiteBalance:
            return L10n.tr("autoWhiteBalance")
        case .locked:
            return L10n.tr("locked")
        @unknown default:
            return L10n.tr("unknown")
        }
    }

    private func focusModeLabel(_ mode: AVCaptureDevice.FocusMode) -> String {
        switch mode {
        case .continuousAutoFocus:
            return L10n.tr("continuousAutoFocus")
        case .autoFocus:
            return L10n.tr("autoFocus")
        case .locked:
            return L10n.tr("locked")
        @unknown default:
            return L10n.tr("unknown")
        }
    }
}
