import Foundation

extension CaptureSessionController {
    func scheduleFirstFrameWatchdog(
        generation: Int,
        requiresNativeBackendOnNoFrames: Bool
    ) {
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

            let connectionEvidence = self.outputConnectionEvidence()

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.isRunning,
                      self.diagnostics.totalFrames == 0,
                      self.captureState == .waitingForFirstFrame else {
                    return
                }

                self.captureState = requiresNativeBackendOnNoFrames ? .nativeBackendRequired : .noFrames
                self.statusMessage = requiresNativeBackendOnNoFrames
                    ? L10n.tr("Native USB backend required")
                    : L10n.tr("No frames from AVFoundation")
                self.fallbackEvents.removeAll { event in
                    event.stage == "stream_start" || event.stage == "native_backend"
                }

                let timeout = Int(self.firstFrameTimeout)
                let stage = requiresNativeBackendOnNoFrames ? "native_backend" : "stream_start"
                let reason = firstFrameTimeoutReason(
                    timeout: timeout,
                    connectionEvidence: connectionEvidence,
                    requiresNativeBackendOnNoFrames: requiresNativeBackendOnNoFrames
                )
                let decision = firstFrameTimeoutDecision(
                    requiresNativeBackendOnNoFrames: requiresNativeBackendOnNoFrames
                )

                self.fallbackEvents.append(
                    FallbackEvent(
                        stage: stage,
                        reason: reason,
                        decision: decision
                    )
                )
            }
        }
    }

    private func firstFrameTimeoutReason(
        timeout: Int,
        connectionEvidence: String,
        requiresNativeBackendOnNoFrames: Bool
    ) -> String {
        if requiresNativeBackendOnNoFrames {
            return L10n.tr(
                "HikCamera bulk-only UVC device reached a running AVCaptureSession, but no sample buffer arrived within %@ seconds for %@ / %@. %@",
                "\(timeout)",
                activeConfiguration.activeFormat,
                activeConfiguration.outputPixelFormat,
                connectionEvidence
            )
        }

        return L10n.tr(
            "Camera permission is %@ and AVCaptureSession is running, but AVCaptureVideoDataOutput delivered no frame within %@ seconds for %@ / %@. %@",
            authorizationState.displayName,
            "\(timeout)",
            activeConfiguration.activeFormat,
            activeConfiguration.outputPixelFormat,
            connectionEvidence
        )
    }

    private func firstFrameTimeoutDecision(requiresNativeBackendOnNoFrames: Bool) -> String {
        if requiresNativeBackendOnNoFrames {
            return L10n.tr(
                "Mark HikCamera preview as requiring an exclusive native USB backend; do not keep cycling AVFoundation pixel formats."
            )
        }

        return L10n.tr(
            "Treat this as a macOS AVFoundation compatibility failure for this bulk-only UVC device. " +
                "Use an explicit exclusive native USB backend or capture the Windows USBPcap startup sequence; " +
                "do not keep cycling AVFoundation pixel formats."
        )
    }

    private func outputConnectionEvidence() -> String {
        let videoConnection = videoOutput.connection(with: .video)
        let dataConnection = videoConnection.map { connection in
            "\(L10n.tr("present"))/\(connection.isEnabled ? L10n.tr("enabled") : L10n.tr("disabled"))"
        } ?? L10n.tr("missing")
        let movieAttached = session.outputs.contains { $0 === movieOutput }
            ? L10n.tr("yes")
            : L10n.tr("no")
        let outputs = session.outputs
            .map { String(describing: type(of: $0)) }
            .joined(separator: ", ")

        return L10n.tr(
            "Output connections: videoData=%@, movieOutputAttached=%@, sessionOutputs=%@",
            dataConnection,
            movieAttached,
            outputs.isEmpty ? L10n.tr("None") : outputs
        )
    }
}
