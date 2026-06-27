import Foundation

extension CaptureSessionController {
    func setROIEnabled(_ isEnabled: Bool) {
        roiEnabled = isEnabled
        updateROIMeasurement()
    }

    func setROIValue(_ keyPath: ReferenceWritableKeyPath<CaptureSessionController, Double>, value: Double) {
        self[keyPath: keyPath] = value
        updateROIMeasurement()
    }

    func updateROIMeasurement() {
        guard roiEnabled else {
            roiMeasurement = .unsupported
            return
        }

        let selection = NormalizedROI(
            xPercent: roiXPercent,
            yPercent: roiYPercent,
            widthPercent: roiWidthPercent,
            heightPercent: roiHeightPercent
        )

        let region = roiRegionLabel(selection)

        roiMeasurement = ROITemperatureSnapshot(
            status: L10n.tr("Checking latest frame"),
            region: region,
            minTemperature: L10n.tr("Unavailable"),
            maxTemperature: L10n.tr("Unavailable"),
            averageTemperature: L10n.tr("Unavailable")
        )

        outputQueue.async { [weak self, selection, region] in
            guard let self else {
                return
            }

            let measurement: ROITemperatureSnapshot
            if let pixelBuffer = self.latestPixelBuffer {
                measurement = self.thermalParser.measureROI(
                    pixelBuffer: pixelBuffer,
                    roi: selection
                ) ?? ROITemperatureSnapshot(
                    status: L10n.tr("No radiometric matrix"),
                    region: region,
                    minTemperature: L10n.tr("No L016 matrix"),
                    maxTemperature: L10n.tr("No L016 matrix"),
                    averageTemperature: L10n.tr("No L016 matrix")
                )
            } else {
                measurement = ROITemperatureSnapshot(
                    status: L10n.tr("No frame available"),
                    region: region,
                    minTemperature: L10n.tr("Unavailable"),
                    maxTemperature: L10n.tr("Unavailable"),
                    averageTemperature: L10n.tr("Unavailable")
                )
            }

            DispatchQueue.main.async { [weak self, measurement] in
                self?.roiMeasurement = measurement
            }
        }
    }

    private func roiRegionLabel(_ roi: NormalizedROI) -> String {
        String(
            format: "x %.0f%%, y %.0f%%, w %.0f%%, h %.0f%%",
            roi.xPercent,
            roi.yPercent,
            roi.widthPercent,
            roi.heightPercent
        )
    }
}
