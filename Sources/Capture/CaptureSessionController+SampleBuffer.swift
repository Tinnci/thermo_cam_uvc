import AVFoundation
import CoreFoundation
import CoreMedia
import CoreVideo
import Foundation

extension CaptureSessionController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let isFirstFrame = totalFrames == 0
        totalFrames += 1
        framesInWindow += 1
        latestPixelBuffer = pixelBuffer

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if let lastPresentationTime {
            lastFrameIntervalMS = max(0, presentationTime.seconds - lastPresentationTime.seconds) * 1000
        }
        lastPresentationTime = presentationTime

        let deliveredPixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        if deliveredPixelFormat != requestedOutputPixelFormat && !reportedPixelFormatMismatch {
            reportedPixelFormatMismatch = true
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                if !self.fallbackEvents.contains(where: { $0.stage == "pixel_format" }) {
                    self.fallbackEvents.append(
                        FallbackEvent(
                            stage: "pixel_format",
                            reason: L10n.tr(
                                "Requested %@ but received %@",
                                pixelFormatName(self.requestedOutputPixelFormat),
                                pixelFormatName(deliveredPixelFormat)
                            ),
                            decision: L10n.tr("Use delivered CVPixelBuffer format for the live processing path")
                        )
                    )
                }
            }
        }

        let metalSnapshot = metalPipeline.importPixelBuffer(pixelBuffer)
        if isFirstFrame {
            let firstFrameSnapshot = DiagnosticsSnapshot(
                totalFrames: totalFrames,
                droppedFrames: droppedFrames,
                measuredFPS: 0,
                frameIntervalMS: 0,
                frameSize: "\(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer))",
                deliveredPixelFormat: pixelFormatName(deliveredPixelFormat),
                metalStatus: metalSnapshot.status,
                metalTexture: metalSnapshot.textureDescription
            )

            DispatchQueue.main.async { [weak self, firstFrameSnapshot] in
                guard let self else {
                    return
                }

                self.captureState = .streaming
                self.statusMessage = L10n.tr("Streaming")
                self.diagnostics = firstFrameSnapshot
            }
        }

        let shouldInspectThermalData = totalFrames == 1 || totalFrames.isMultiple(of: 30)

        if shouldInspectThermalData {
            let thermalSnapshot = thermalParser.inspect(
                sampleBuffer: sampleBuffer,
                pixelBuffer: pixelBuffer,
                inspectedFrames: totalFrames
            )

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                self.thermalInspection = thermalSnapshot
                self.updateROIMeasurement()
            }
        }

        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - windowStartTime

        guard elapsed >= 0.5 else {
            return
        }

        let fps = Double(framesInWindow) / elapsed
        framesInWindow = 0
        windowStartTime = now

        let snapshot = DiagnosticsSnapshot(
            totalFrames: totalFrames,
            droppedFrames: droppedFrames,
            measuredFPS: fps,
            frameIntervalMS: lastFrameIntervalMS,
            frameSize: "\(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer))",
            deliveredPixelFormat: pixelFormatName(deliveredPixelFormat),
            metalStatus: metalSnapshot.status,
            metalTexture: metalSnapshot.textureDescription
        )

        DispatchQueue.main.async { [weak self] in
            self?.diagnostics = snapshot
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        droppedFrames += 1
    }
}
