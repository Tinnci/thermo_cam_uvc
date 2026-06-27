import AVFoundation
import Foundation

extension CaptureSessionController {
    func installSessionObservers() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleSessionRuntimeError(_:)),
            name: AVCaptureSession.runtimeErrorNotification,
            object: session
        )
        center.addObserver(
            self,
            selector: #selector(handleSessionWasInterrupted(_:)),
            name: AVCaptureSession.wasInterruptedNotification,
            object: session
        )
        center.addObserver(
            self,
            selector: #selector(handleSessionInterruptionEnded(_:)),
            name: AVCaptureSession.interruptionEndedNotification,
            object: session
        )
    }

    @objc private func handleSessionRuntimeError(_ notification: Notification) {
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
        appendSessionEvent(
            stage: "session_runtime",
            reason: L10n.tr(
                "AVCaptureSession runtime error: %@",
                error?.localizedDescription ?? L10n.tr("Unknown")
            ),
            decision: L10n.tr("Stop capture and reconfigure the session before retrying")
        )
    }

    @objc private func handleSessionWasInterrupted(_ notification: Notification) {
        appendSessionEvent(
            stage: "session_interruption",
            reason: L10n.tr("AVCaptureSession was interrupted: %@", L10n.tr("Unknown")),
            decision: L10n.tr("Wait for the system to end the interruption, then retry capture")
        )
    }

    @objc private func handleSessionInterruptionEnded(_ notification: Notification) {
        appendSessionEvent(
            stage: "session_interruption",
            reason: L10n.tr("AVCaptureSession interruption ended"),
            decision: L10n.tr("Retry capture if frames do not resume automatically")
        )
    }

    private func appendSessionEvent(stage: String, reason: String, decision: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.fallbackEvents.removeAll { $0.stage == stage }
            self.fallbackEvents.append(
                FallbackEvent(
                    stage: stage,
                    reason: reason,
                    decision: decision
                )
            )

            if stage == "session_runtime" {
                self.captureState = .failed
                self.statusMessage = reason
            }
        }
    }
}
