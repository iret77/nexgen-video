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
    ///   - detail: raises the bar for what counts as noise, so fine texture survives.
    static func apply(
        _ image: CIImage, extent: CGRect, luma: Double, chromaBias: Double, detail: Double
    ) -> CIImage {
        guard let kernel, luma > 0, extent.width > 0, extent.height > 0 else { return image }
        // Deliberately small: this is a denoise, not a blur. The radius is the neighbourhood the
        // local mean is taken over — grow it and flat areas go plastic.
        let radius = 1.0 + luma * 1.5
        let blurred = image.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: extent)
        let chroma = min(1.0, luma * (1.0 + chromaBias))
        return kernel.apply(
            extent: extent, roiCallback: { _, rect in rect },
            arguments: [image, blurred, Float(luma), Float(chroma), Float(detail)]) ?? image
    }
}
