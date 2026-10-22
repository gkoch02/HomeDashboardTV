#include "SkyPass.h"
using namespace metal;

/// One triangle that covers the screen, so a sky's fragment shader runs over every pixel.
vertex SkyVertex skyVertex(uint id [[vertex_id]]) {
    float2 corner = float2(id == 2 ? 3.0 : -1.0, id == 1 ? 3.0 : -1.0);
    return { float4(corner, 0.0, 1.0) };
}
