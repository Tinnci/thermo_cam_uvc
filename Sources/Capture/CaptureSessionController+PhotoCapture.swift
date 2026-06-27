import AppKit
import CoreImage
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers

extension CaptureSessionController {
    @MainActor
    func saveCurrentFrame() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "ThermoCam-\(timestampForFilename()).png"
        panel.title = L10n.tr("Save Current Frame")

        panel.begin { @MainActor [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }

            self?.writeCurrentFrame(to: url)
        }
    }

    private func writeCurrentFrame(to url: URL) {
        photoSaveStatus = L10n.tr("Saving frame")

        outputQueue.async { [weak self] in
            guard let self else {
                return
            }

            guard let pixelBuffer = self.latestPixelBuffer else {
                DispatchQueue.main.async {
                    self.photoSaveStatus = L10n.tr("No frame is available yet")
                }
                return
            }

            let result = self.writePNG(pixelBuffer: pixelBuffer, to: url)

            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.photoSaveStatus = L10n.tr("Saved %@", url.lastPathComponent)
                case .failure(let error):
                    self.photoSaveStatus = L10n.tr("Save failed: %@", error.localizedDescription)
                }
            }
        }
    }

    private func writePNG(pixelBuffer: CVPixelBuffer, to url: URL) -> Result<Void, Error> {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let rect = CGRect(
            x: 0,
            y: 0,
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )

        guard let cgImage = imageContext.createCGImage(image, from: rect) else {
            return .failure(CameraCaptureError.cannotCreateImage)
        }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return .failure(CameraCaptureError.cannotCreateImageDestination)
        }

        CGImageDestinationAddImage(destination, cgImage, nil)

        if CGImageDestinationFinalize(destination) {
            return .success(())
        }

        return .failure(CameraCaptureError.cannotWriteImage)
    }

    func timestampForFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
