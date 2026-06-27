import AppKit
import AVFoundation
import Foundation

extension CaptureSessionController {
    @MainActor
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    @MainActor
    func startRecording() {
        guard isRunning else {
            recordingStatus = L10n.tr("Start capture before recording")
            return
        }

        guard recordingAvailable else {
            recordingStatus = L10n.tr("Movie recording output is unavailable")
            return
        }

        guard !movieOutput.isRecording else {
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.quickTimeMovie]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "ThermoCam-\(timestampForFilename()).mov"
        panel.title = L10n.tr("Save Recording")

        panel.begin { @MainActor [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }

            self?.startRecording(to: url)
        }
    }

    @MainActor
    func stopRecording() {
        sessionQueue.async { [weak self] in
            guard let self else {
                return
            }

            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            }
        }
    }

    @MainActor
    private func startRecording(to url: URL) {
        recordingStatus = L10n.tr("Starting recording")

        sessionQueue.async { [weak self] in
            guard let self else {
                return
            }

            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }

            guard self.ensureMovieOutputAttached() else {
                DispatchQueue.main.async { [weak self] in
                    self?.recordingStatus = L10n.tr("Movie recording output is unavailable")
                    self?.recordingAvailable = false
                }
                return
            }

            self.movieOutput.startRecording(to: url, recordingDelegate: self)
        }
    }

    private func ensureMovieOutputAttached() -> Bool {
        if session.outputs.contains(where: { $0 === movieOutput }) {
            return true
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard session.canAddOutput(movieOutput) else {
            return false
        }

        session.addOutput(movieOutput)
        movieOutput.connection(with: .video)?.isEnabled = true
        return true
    }

    private func detachMovieOutputIfIdle() {
        guard !movieOutput.isRecording,
              session.outputs.contains(where: { $0 === movieOutput }) else {
            return
        }

        session.beginConfiguration()
        session.removeOutput(movieOutput)
        session.commitConfiguration()
    }
}

extension CaptureSessionController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.isRecording = true
            self?.recordingStatus = L10n.tr("Recording %@", fileURL.lastPathComponent)
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        sessionQueue.async { [weak self] in
            self?.detachMovieOutputIfIdle()
        }

        DispatchQueue.main.async { [weak self] in
            self?.isRecording = false

            if let error {
                self?.recordingStatus = L10n.tr("Recording failed: %@", error.localizedDescription)
            } else {
                self?.recordingStatus = L10n.tr("Saved %@", outputFileURL.lastPathComponent)
            }
        }
    }
}
