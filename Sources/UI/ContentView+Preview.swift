import SwiftUI

extension ContentView {
    var previewPane: some View {
        ZStack {
            Color.black

            CameraPreviewView(session: controller.session)
                .opacity(controller.isRunning ? 1 : 0.35)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if shouldShowPreviewOverlay {
                VStack(spacing: 8) {
                    Image(systemName: previewStatusIcon)
                        .font(.system(size: 34, weight: .semibold))
                    Text(LocalizedStringKey(controller.statusMessage))
                        .font(.headline)
                    Text(previewStatusDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
                .padding(20)
                .foregroundStyle(.white)
            }
        }
    }

    private var shouldShowPreviewOverlay: Bool {
        !controller.isRunning || controller.captureState.needsOverlay
    }

    private var previewStatusIcon: String {
        if controller.isRunning {
            switch controller.captureState {
            case .starting, .waitingForFirstFrame:
                return "hourglass"
            case .noFrames:
                return "video.slash"
            case .failed:
                return "exclamationmark.triangle"
            case .streaming, .stopping, .idle:
                break
            }
        }

        switch controller.authorizationState {
        case .authorized:
            return controller.devices.isEmpty ? "video.slash" : "video"
        case .notDetermined:
            return "lock.open"
        case .denied, .restricted:
            return "lock"
        }
    }

    private var previewStatusDetail: String {
        if controller.isRunning {
            switch controller.captureState {
            case .starting:
                return L10n.tr("Preparing the AVFoundation capture session.")
            case .waitingForFirstFrame:
                return L10n.tr("Camera permission is authorized. Waiting for AVCaptureVideoDataOutput to deliver the first frame.")
            case .noFrames:
                return L10n.tr(
                    "Camera permission is authorized and the session is running, but no sample buffer arrived. " +
                        "This points to macOS UVC negotiation or device format compatibility, not a SwiftUI drawing failure."
                )
            case .failed:
                return L10n.tr("The capture session failed before delivering video.")
            case .streaming, .stopping, .idle:
                break
            }
        }

        switch controller.authorizationState {
        case .authorized:
            return controller.devices.isEmpty
                ? L10n.tr("No video device is visible to AVFoundation.")
                : L10n.tr("Select a camera and start capture.")
        case .notDetermined:
            return L10n.tr("macOS will ask for camera access when capture starts.")
        case .denied:
            return L10n.tr("Enable access in System Settings > Privacy & Security > Camera.")
        case .restricted:
            return L10n.tr("Camera access is restricted by system policy.")
        }
    }
}
