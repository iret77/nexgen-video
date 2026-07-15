#include <CoreImage/CoreImage.h>
using namespace metal;

// Edge-aware, chroma-weighted denoise (#219). `blurred` is a small-radius Gaussian of the frame,
// i.e. the local mean.
//
// Two ideas do the work:
//   * Noise is a SMALL deviation from the local mean; an edge is a LARGE one. Gating on that
//     deviation lets flat areas fall back to the mean while edges keep their original pixel — the
//     bilateral idea, without the multi-tap cost.
//   * Sensor and codec noise sits mostly in CHROMA, while the eye reads detail from LUMA. So chroma
//     is smoothed harder than luma. That is the difference between "denoised" and "soft".
//
// Rec.709 luma; Cb/Cr scaled as in BT.709 so the round-trip is exact.

static inline float3 rgbToYCbCr(float3 c) {
    float y = dot(c, float3(0.2126, 0.7152, 0.0722));
    return float3(y, (c.b - y) / 1.8556, (c.r - y) / 1.5748);
}

static inline float3 ycbcrToRGB(float3 v) {
    float r = v.x + 1.5748 * v.z;
    float b = v.x + 1.8556 * v.y;
    float g = (v.x - 0.2126 * r - 0.0722 * b) / 0.7152;
    return float3(r, g, b);
}

extern "C" float4 denoiseEdgeAware(coreimage::sampler img, coreimage::sampler blurred,
                                   float luma, float chroma, float detail) {
    float4 s = img.sample(img.coord());
    float3 mean = blurred.sample(blurred.coord()).rgb;

    float3 src = rgbToYCbCr(s.rgb);
    float3 avg = rgbToYCbCr(mean);

    // How far is this pixel from its neighbourhood? Small → noise, large → structure. `detail`
    // raises the bar for what still counts as noise, so a high value protects fine texture.
    float deviation = abs(src.x - avg.x);
    float edge = smoothstep(0.02 + detail * 0.18, 0.06 + detail * 0.30, deviation);

    float y = mix(src.x, avg.x, (1.0 - edge) * luma);
    // Chroma keeps a little edge protection too — otherwise saturated edges bleed.
    float chromaWeight = chroma * mix(1.0, 0.35, edge);
    float cb = mix(src.y, avg.y, chromaWeight);
    float cr = mix(src.z, avg.z, chromaWeight);

    return float4(saturate(ycbcrToRGB(float3(y, cb, cr))), s.a);
}
