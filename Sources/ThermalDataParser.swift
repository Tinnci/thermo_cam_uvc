import CoreMedia
import CoreVideo
import Foundation

final class ThermalDataParser: @unchecked Sendable {
    func inspect(
        sampleBuffer: CMSampleBuffer,
        pixelBuffer: CVPixelBuffer,
        inspectedFrames: Int
    ) -> ThermalInspectionSnapshot {
        let dimensions = "\(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer))"
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)

        if pixelFormat == kCVPixelFormatType_OneComponent16 {
            return ThermalInspectionSnapshot(
                inspectedFrames: inspectedFrames,
                status: "Raw 16-bit matrix detected",
                evidence: "Delivered CVPixelBuffer format is L016. Raw samples are available; vendor temperature calibration is not applied.",
                matrixSize: dimensions
            )
        }

        let sampleKeys = attachmentKeys(
            CMCopyDictionaryOfAttachments(
                allocator: kCFAllocatorDefault,
                target: sampleBuffer,
                attachmentMode: kCMAttachmentMode_ShouldPropagate
            )
        )

        let pixelKeys = attachmentKeys(
            CVBufferCopyAttachments(pixelBuffer, .shouldPropagate)
        )

        let combinedKeys = (sampleKeys + pixelKeys).sorted()
        let thermalKeys = combinedKeys.filter { key in
            let lowercased = key.lowercased()
            return lowercased.contains("thermal") ||
                lowercased.contains("temperature") ||
                lowercased.contains("radiometric") ||
                lowercased.contains("hik")
        }

        if thermalKeys.isEmpty {
            let evidence = combinedKeys.isEmpty
                ? "No sample or pixel-buffer attachments were delivered"
                : "Attachment keys: \(combinedKeys.prefix(8).joined(separator: ", "))"

            return ThermalInspectionSnapshot(
                inspectedFrames: inspectedFrames,
                status: "No radiometric matrix detected",
                evidence: evidence,
                matrixSize: "Unavailable; video frame is \(dimensions)"
            )
        }

        return ThermalInspectionSnapshot(
            inspectedFrames: inspectedFrames,
            status: "Potential thermal metadata detected",
            evidence: thermalKeys.joined(separator: ", "),
            matrixSize: "Unknown; parser needs vendor payload layout"
        )
    }

    func measureROI(pixelBuffer: CVPixelBuffer, roi: NormalizedROI) -> ROITemperatureSnapshot? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_OneComponent16 else {
            return nil
        }

        let lockStatus = CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        guard lockStatus == kCVReturnSuccess else {
            return ROITemperatureSnapshot(
                status: "Matrix lock failed",
                region: regionLabel(roi),
                minTemperature: "Unavailable",
                maxTemperature: "Unavailable",
                averageTemperature: "Unavailable"
            )
        }

        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return ROITemperatureSnapshot(
                status: "Matrix memory unavailable",
                region: regionLabel(roi),
                minTemperature: "Unavailable",
                maxTemperature: "Unavailable",
                averageTemperature: "Unavailable"
            )
        }

        let imageWidth = CVPixelBufferGetWidth(pixelBuffer)
        let imageHeight = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        let rect = pixelRect(for: roi, width: imageWidth, height: imageHeight)
        guard rect.xRange.lowerBound < rect.xRange.upperBound,
              rect.yRange.lowerBound < rect.yRange.upperBound else {
            return ROITemperatureSnapshot(
                status: "ROI is empty",
                region: regionLabel(roi),
                minTemperature: "Unavailable",
                maxTemperature: "Unavailable",
                averageTemperature: "Unavailable"
            )
        }

        var minimum = UInt16.max
        var maximum = UInt16.min
        var sum: UInt64 = 0
        var count: UInt64 = 0

        for rowIndex in rect.yRange {
            let row = baseAddress
                .advanced(by: rowIndex * bytesPerRow)
                .assumingMemoryBound(to: UInt16.self)

            for columnIndex in rect.xRange {
                let value = UInt16(littleEndian: row[columnIndex])
                minimum = min(minimum, value)
                maximum = max(maximum, value)
                sum += UInt64(value)
                count += 1
            }
        }

        let average = count == 0 ? 0 : Double(sum) / Double(count)

        return ROITemperatureSnapshot(
            status: "Raw matrix values",
            region: "\(rect.xRange.lowerBound)..<\(rect.xRange.upperBound), \(rect.yRange.lowerBound)..<\(rect.yRange.upperBound)",
            minTemperature: "raw \(minimum)",
            maxTemperature: "raw \(maximum)",
            averageTemperature: String(format: "raw %.1f", average)
        )
    }

    private func attachmentKeys(_ attachments: CFDictionary?) -> [String] {
        guard let attachments = attachments as? [AnyHashable: Any] else {
            return []
        }

        return attachments.keys.map { key in
            if let string = key as? String {
                return string
            }

            return String(describing: key)
        }
    }

    private func pixelRect(
        for roi: NormalizedROI,
        width: Int,
        height: Int
    ) -> (xRange: Range<Int>, yRange: Range<Int>) {
        let xStart = clampedPixel(percent: roi.xPercent, extent: width)
        let yStart = clampedPixel(percent: roi.yPercent, extent: height)
        let roiWidth = max(1, Int((Double(width) * roi.widthPercent / 100).rounded()))
        let roiHeight = max(1, Int((Double(height) * roi.heightPercent / 100).rounded()))
        let xEnd = min(width, xStart + roiWidth)
        let yEnd = min(height, yStart + roiHeight)

        return (xStart..<xEnd, yStart..<yEnd)
    }

    private func clampedPixel(percent: Double, extent: Int) -> Int {
        guard extent > 0 else {
            return 0
        }

        let scaled = Int((Double(extent) * percent / 100).rounded(.down))
        return min(max(0, scaled), extent - 1)
    }

    private func regionLabel(_ roi: NormalizedROI) -> String {
        String(
            format: "x %.0f%%, y %.0f%%, w %.0f%%, h %.0f%%",
            roi.xPercent,
            roi.yPercent,
            roi.widthPercent,
            roi.heightPercent
        )
    }
}
