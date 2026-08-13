#include <metal_stdlib>
using namespace metal;

/// A single sine wave "crest" that travels top→bottom on a 2-second loop.
/// Displacement is concentrated in a narrow band around the crest (gaussian
/// falloff) so most of the receipt stays crisp while the band ripples through.
///
/// Parameters:
///   position  — pixel position in points (SwiftUI-injected)
///   time      — seconds, monotonically increasing (host-provided)
///   amplitude — peak displacement in points at the crest
///   height    — the view's height in points, so the wave sweeps cleanly
///
/// Used by SwiftUI `.distortionEffect(...)` — see `ProcessingShimmerModifier`.
[[ stitchable ]]
float2 processingShimmer(float2 position, float time, float amplitude, float height) {
    const float period = 2.0;                 // seconds per top→bottom pass
    const float margin = 80.0;                // extends sweep past top and bottom
    const float band   = 55.0;                // gaussian sigma — crest thickness
    const float lateralFreq = 0.055;          // horizontal ripple frequency
    const float lateralSpeed = 4.5;           // how fast ripples wobble inside the crest

    float progress = fract(time / period);
    float centerY  = progress * (height + 2.0 * margin) - margin;
    float distFromCenter = position.y - centerY;
    float falloff = exp(-(distFromCenter * distFromCenter) / (2.0 * band * band));

    float dx = sin(position.x * lateralFreq + time * lateralSpeed) * amplitude * falloff;
    float dy = cos(position.x * lateralFreq * 0.7 + time * lateralSpeed * 0.6)
             * amplitude * falloff * 0.35;

    return position + float2(dx, dy);
}
