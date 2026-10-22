#pragma once
#include <metal_stdlib>

// What the shader skies share (`SkyLayer`): the one triangle covering the screen from
// `SkyPass.metal`, and the fragment's place in points, as the skies were written for. Every
// sky's uniforms start with `frame`: the view's size in points (x, y), the layer's scale (z)
// and the sky's time (w).

struct SkyVertex {
    metal::float4 position [[position]];
};

/// The fragment's position in points, from its pixel position and the layer's scale.
inline metal::float2 skyPoint(metal::float4 position, metal::float4 frame) { return position.xy / frame.z; }
