import Foundation

extension CaptureSessionController {
    func scheduleFirstFrameWatchdog(generation: Int) {
        sessionQueue.asyncAfter(deadline: .now() + firstFrameTimeout) { [weak self] in
            guard let self else {
                return
            }

            guard generation == self.captureGeneration, self.session.isRunning else {
                return
            }

            let frameCount = self.outputQueue.sync {
                self.totalFrames
            }

            guard frameCount == 0 else {
                return
            }

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.isRunning,
                      self.diagnostics.totalFrames == 0,
                      self.captureState == .waitingForFirstFrame else {
                    return
                }

                self.captureState = .noFrames
                self.statusMessage = L10n.tr("No frames from AVFoundation")
                self.fallbackEvents.removeAll { event in
                    event.stage == "stream_start"
                }

                let timeout = Int(self.firstFrameTimeout)
                let reason = L10n.tr(
                    "Camera permission is %@ and AVCaptureSession is running, but AVCaptureVideoDataOutput delivered no frame within %@ seconds for %@ / %@",
                    self.authorizationState.displayName,
                    "\(timeout)",
                    self.activeConfiguration.activeFormat,
                    self.activeConfiguration.outputPixelFormat
                )
                let decision = L10n.tr(
                    "Treat this as a macOS UVC stream negotiation failure, not a SwiftUI drawing failure. " +
                        "Compare the Windows UVC probe/commit parameters and try that known-good format profile " +
                        "before adding private writes."
                )

                self.fallbackEvents.append(
                    FallbackEvent(
                        stage: "stream_start",
                        reason: reason,
                        decision: decision
                    )
                )
            }
        }
    }
}
