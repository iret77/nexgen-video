import CoreImage
import Foundation

/// Edge-aware, chroma-weighted denoise against a small-radius blur of the frame (#219).
/// Kernel: `Metal/Denoise.metal`.
///
/// Replaces the `CINoiseReduction` slider, which is spatial-only and treats luma and chroma alike —
/// it softens detail to reach the noise. This keeps edges (deviation gate) and smooths chroma
/// harder than luma, which is where the noise actually lives.
enum DenoiseKernel {
    private static let kernel = CIKernelLoader.kernel("Denoise", "denoiseEdgeAware")

    /// - Parameters:
    ///   - luma: master strength, 0 = off.
    ///   - chromaBias: extra chroma smoothing over luma (chroma noise needs more).
    ///   - detail: protects fine texture by tightening the kernel's edge threshold.
    static func apply(
        _ image: CIImage, extent: CGRect, luma: Double, chromaBias: Double, detail: Double
    ) -> CIImage {
        guard let kernel, luma > 0, extent.width > 0, extent.height > 0 else { return image }
        let chroma = min(1.0, luma * (1.0 + chromaBias))
        return kernel.apply(
            extent: extent,
            // The kernel reads a 5×5 neighbourhood, so it needs 2px around each output pixel.
            roiCallback: { _, rect in rect.insetBy(dx: -2, dy: -2) },
            arguments: [image.clampedToExtent(), Float(luma), Float(chroma), Float(detail)]) ?? image
    }
}
