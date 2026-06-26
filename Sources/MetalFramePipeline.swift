import CoreVideo
import Foundation
import Metal

struct MetalImportSnapshot: Equatable {
    let status: String
    let textureDescription: String
    let usesMetal: Bool

    static let idle = MetalImportSnapshot(
        status: "Idle",
        textureDescription: "None",
        usesMetal: false
    )
}

final class MetalFramePipeline {
    private let device: MTLDevice?
    private var textureCache: CVMetalTextureCache?

    init() {
        self.device = MTLCreateSystemDefaultDevice()

        if let device {
            var cache: CVMetalTextureCache?
            let status = CVMetalTextureCacheCreate(
                kCFAllocatorDefault,
                nil,
                device,
                nil,
                &cache
            )

            if status == kCVReturnSuccess {
                self.textureCache = cache
            }
        }
    }

    func importPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> MetalImportSnapshot {
        guard device != nil else {
            return MetalImportSnapshot(
                status: "Metal unavailable",
                textureDescription: "CPU CVPixelBuffer path",
                usesMetal: false
            )
        }

        guard let textureCache else {
            return MetalImportSnapshot(
                status: "CVMetalTextureCache unavailable",
                textureDescription: "CPU CVPixelBuffer path",
                usesMetal: false
            )
        }

        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)

        if isNV12(pixelFormat), CVPixelBufferGetPlaneCount(pixelBuffer) >= 2 {
            let lumaStatus = createTexture(
                cache: textureCache,
                pixelBuffer: pixelBuffer,
                metalPixelFormat: .r8Unorm,
                width: CVPixelBufferGetWidthOfPlane(pixelBuffer, 0),
                height: CVPixelBufferGetHeightOfPlane(pixelBuffer, 0),
                planeIndex: 0
            )

            let chromaStatus = createTexture(
                cache: textureCache,
                pixelBuffer: pixelBuffer,
                metalPixelFormat: .rg8Unorm,
                width: CVPixelBufferGetWidthOfPlane(pixelBuffer, 1),
                height: CVPixelBufferGetHeightOfPlane(pixelBuffer, 1),
                planeIndex: 1
            )

            if lumaStatus == kCVReturnSuccess && chromaStatus == kCVReturnSuccess {
                return MetalImportSnapshot(
                    status: "OK",
                    textureDescription: "NV12 luma+chroma textures",
                    usesMetal: true
                )
            }

            return MetalImportSnapshot(
                status: "NV12 import failed \(lumaStatus)/\(chromaStatus)",
                textureDescription: "CPU CVPixelBuffer path",
                usesMetal: false
            )
        }

        let bgraStatus = createTexture(
            cache: textureCache,
            pixelBuffer: pixelBuffer,
            metalPixelFormat: .bgra8Unorm,
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer),
            planeIndex: 0
        )

        if bgraStatus == kCVReturnSuccess {
            return MetalImportSnapshot(
                status: "OK",
                textureDescription: "BGRA texture",
                usesMetal: true
            )
        }

        return MetalImportSnapshot(
            status: "Texture import failed \(bgraStatus)",
            textureDescription: "CPU CVPixelBuffer path",
            usesMetal: false
        )
    }

    private func createTexture(
        cache: CVMetalTextureCache,
        pixelBuffer: CVPixelBuffer,
        metalPixelFormat: MTLPixelFormat,
        width: Int,
        height: Int,
        planeIndex: Int
    ) -> CVReturn {
        var cvTexture: CVMetalTexture?

        return CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            pixelBuffer,
            nil,
            metalPixelFormat,
            width,
            height,
            planeIndex,
            &cvTexture
        )
    }

    private func isNV12(_ pixelFormat: FourCharCode) -> Bool {
        pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
            pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
    }
}
