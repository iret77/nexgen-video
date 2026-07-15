#include <CoreImage/CoreImage.h>
using namespace metal;

// Edge-aware, chroma-weighted denoise (#219) — a bilateral filter over a 5×5 neighbourhood.
//
// Each neighbour is weighted by two things: how FAR it is (spatial) and how DIFFERENT it is
// (range). A neighbour across an edge is very different, so its weight collapses and it never
// bleeds in. That preserves edges by construction — unlike gating on the local mean, which fails
// exactly beside a step edge: there the mean is already contaminated by the other side, the centre
// pixel looks unremarkable next to it, and the edge quietly ramps.
//
// Chroma is smoothed harder than luma with a looser range weight: sensor and codec noise sits
// mostly in chroma, while the eye reads detail from luma. That is the difference between "clean"
// and merely "soft".
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

extern "C" float4 denoiseEdgeAware(coreimage::sampler img, float luma, float chroma, float detail) {
    float2 dc = coreimage::destCoord();
    float4 centre = img.sample(img.transform(dc));
    float3 c = rgbToYCbCr(centre.rgb);

    // The range sigma IS the edge threshold: a deviation much larger than sigma reads as structure
    // and is rejected. `detail` shrinks it, so finer texture survives — the parameter protects
    // detail, which is what its name says.
    float sigmaY = 0.015 + (1.0 - detail) * 0.085;
    float sigmaC = sigmaY * 2.5;              // chroma tolerates more before it counts as an edge
    float inv2sY = 1.0 / (2.0 * sigmaY * sigmaY);
    float inv2sC = 1.0 / (2.0 * sigmaC * sigmaC);

    float3 sum = float3(0.0);
    float wYsum = 0.0;
    float wCsum = 0.0;

    for (int dy = -2; dy <= 2; ++dy) {
        for (int dx = -2; dx <= 2; ++dx) {
            float3 t = rgbToYCbCr(img.sample(img.transform(dc + float2(dx, dy))).rgb);
            float spatial = exp(-float(dx * dx + dy * dy) / 4.0);   // sigma_spatial ≈ 1.41 px

            float dY = t.x - c.x;
            float wY = spatial * exp(-(dY * dY) * inv2sY);
            sum.x += t.x * wY;
            wYsum += wY;

            float dC = distance(t.yz, c.yz);
            float wC = spatial * exp(-(dC * dC) * inv2sC);
            sum.yz += t.yz * wC;
            wCsum += wC;
        }
    }

    float3 filtered = float3(sum.x / max(wYsum, 1e-5), sum.y / max(wCsum, 1e-5), sum.z / max(wCsum, 1e-5));
    float3 mixed = float3(mix(c.x, filtered.x, luma),
                          mix(c.y, filtered.y, chroma),
                          mix(c.z, filtered.z, chroma));
    return float4(saturate(ycbcrToRGB(mixed)), centre.a);
}
