#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// The Aurora layout's sky, one pixel at a time: three curtains of light over a line of hills
// and a still lake that holds their reflection, with stars behind, all on true black (an
// OLED's pixels off). The colours are worked out in Swift (`AuroraView`, from `Aurora` in
// DashboardCore); this only composes them. Positions are in points, as SwiftUI lays out.

namespace aurora {

float hash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

/// A ridge line's height at *x*, 0 to about 1: one-dimensional fractal noise.
float ridge(float x, float seed) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 4; i++) {
        float i0 = floor(x);
        float f = fract(x);
        float u = f * f * (3.0 - 2.0 * f);
        value += amplitude * mix(hash(float2(i0, seed)), hash(float2(i0 + 1.0, seed)), u);
        x *= 2.1;
        amplitude *= 0.5;
    }
    return value;
}

/// The light of all three curtains at (*u*, *y*), *u* across the width 0 to 1 and *y* in
/// points: how bright in the edge's colour (x) and in the fringe's (y).
///
/// Each curtain hangs from a lower edge that sways in slow waves, sharp below and fading
/// upward, its height and brightness rolling along it like folds of cloth, streaked with rays.
/// The waves move with *phase*, which runs once round 2π and wraps; every term turns a whole
/// number of times per wrap, so the wrap is seamless. *unrest* (the wind) adds a fast ripple.
float2 curtains(float u, float y, float height, float phase, float unrest) {
    float2 light = float2(0.0);
    for (int k = 0; k < 3; k++) {
        float fk = float(k);
        float base = height * (0.26 + 0.08 * fk)
            + height * (0.10 - 0.02 * fk) * (0.6 * sin(u * 6.9 + phase + fk * 1.7)
                                             + 0.3 * sin(u * 18.2 - phase * 3.0 + fk * 2.3)
                                             + 0.12 * unrest * sin(u * 52.0 + phase * 9.0));
        float tall = height * (0.19 + 0.11 * sin(u * 8.2 + phase * 2.0 + fk) + 0.07 * sin(u * 24.0 - phase * 3.0));
        float fold = sin(u * 21.6 + phase * 4.0 + fk * 4.0);
        float strength = (0.08 + 0.22 * fold * fold) * (k == 1 ? 1.0 : 0.7);
        float rays = 0.72 + 0.28 * sin(u * 150.0 + 2.0 * sin(u * 37.0 + phase * 2.0) + phase * 6.0 + fk * 5.0);

        float d = (base - y) / tall;
        if (d > -0.4 && d < 1.0) {
            float edge = smoothstep(-0.02, 0.025, d);
            float fade = exp(-1.7 * max(d, 0.0)) * (1.0 - smoothstep(0.7, 1.0, d));
            float body = edge * fade * strength * rays;
            float top = smoothstep(0.3, 0.85, d);
            light += float2(body * (1.0 - top), body * top);
        }
        // The glow the curtain throws round its lower edge.
        light.x += strength * 0.32 * exp(-abs(y - base + tall * 0.15) / (height * 0.06));
    }
    return light;
}

}  // namespace aurora

/// - size: the view, in points.
/// - phase: the curtains' motion, 0 to 2π, summed frame by frame in Swift so a change of wind
///   changes their speed, never their place.
/// - time: seconds, wrapping hourly, for the stars' twinkle and the lake's ripple, which turn
///   a whole number of times an hour.
/// - unrest: how restless the wind makes the curtains, 0 to 1.6.
/// - edge, fringe: the curtains' colour at the lower edge and at the top.
/// - light: how far the build-in has brought the sky up (x), 0 to 1.
/// - motion: the burn-in drift (z, w) the hills move with, so their line never holds one place.
[[ stitchable ]] half4 auroraSky(float2 pos, half4 current,
                                 float2 size, float phase, float time, float unrest,
                                 half4 edge, half4 fringe,
                                 float4 light, float4 motion) {
    using namespace aurora;

    float2 shift = motion.zw;
    float x = pos.x - shift.x;
    float ground = size.y * 0.72 + shift.y;

    // The hills: black against the sky.
    float hillTop = ground - (6.0 + 34.0 * ridge(x / size.x * 6.0 + 5.0, 3.0));
    if (pos.y >= hillTop && pos.y < ground) { return half4(0, 0, 0, 1); }

    float3 edgeColour = float3(edge.rgb);
    float3 fringeColour = float3(fringe.rgb);
    float3 col = float3(0.0);

    if (pos.y < ground) {
        float2 l = curtains(pos.x / size.x, pos.y, size.y, phase, unrest);
        col = edgeColour * l.x + fringeColour * l.y;
        // A faint airglow along the horizon, so the hills stand out against it.
        col += edgeColour * 0.05 * exp(-(ground - pos.y) / (size.y * 0.06));

        // Stars: one in about seventy 7-point cells, each twinkling at its own rate, lost
        // behind the bright parts of the curtains.
        float2 cell = floor(pos / 7.0);
        float h = hash(cell);
        if (h > 0.986) {
            float2 centre = (cell + 0.2 + 0.6 * float2(hash(cell + 3.1), hash(cell + 7.7))) * 7.0;
            float r = 0.45 + 1.0 * fract(h * 91.0) * fract(h * 37.0);
            float spot = 1.0 - smoothstep(r - 0.45, r + 0.75, length(pos - centre));
            float rate = 6.2831853 * (400.0 + floor(1150.0 * fract(h * 13.0))) / 3600.0;
            float twinkle = 0.65 + 0.35 * sin(time * rate + h * 80.0);
            float veil = 1.0 - saturate((l.x + l.y) * 2.5);
            col += float3(0.9, 0.93, 1.0) * spot * twinkle * 0.8 * veil;
        }
    } else {
        // The lake: the curtains reflected, squashed toward the shore and rippled, darkening
        // with depth.
        float depth = (pos.y - ground) / max(size.y - ground, 1.0);
        float ripple = sin(pos.y * 0.15 + time * 6.2831853 * 917.0 / 3600.0) * 6.0 * depth;
        float mirrored = ground - (pos.y - ground) / 0.32;
        float2 l = curtains((pos.x + ripple) / size.x, mirrored, size.y, phase, unrest);
        col = (edgeColour * l.x + fringeColour * l.y) * 0.2 * (1.0 - 0.6 * depth);
    }

    // Bright, never blown: a soft shoulder keeps the folds' colour where curtains overlap.
    col = (1.0 - exp(-col * 1.6)) * float(light.x);

    // A step of dither breaks up banding in the long dark gradients.
    col += (hash(pos * 1.37) - 0.5) / 255.0 * float(light.x);
    return half4(half3(saturate(col)), 1.0h);
}
