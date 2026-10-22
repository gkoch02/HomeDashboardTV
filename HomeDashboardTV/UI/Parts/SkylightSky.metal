#include "SkyPass.h"
using namespace metal;

// The Skylight layout's sky, one pixel at a time: the sky's gradient for the sun's altitude,
// the sun and its glow, stars, cloud, rain or snow, fog and lightning, over two ridges with
// true black below them (an OLED's pixels off). The colours are worked out in Swift
// (`SkylightView`); this only composes them. Positions are in points, as SwiftUI lays out.
// Drawn by `SkyLayer` into a 16-bit extended-range layer: with headroom, the sun, its glow's
// core, the stars and the lightning go brighter than white.

namespace skylight {

float hash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + float2(1, 0)), u.x),
               mix(hash(i + float2(0, 1)), hash(i + float2(1, 1)), u.x), u.y);
}

float fbm(float2 p, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < octaves; i++) {
        value += amplitude * noise(p);
        p = p * 2.03 + float2(17.1, 9.2);
        amplitude *= 0.5;
    }
    return value;
}

/// *v* folded into 0..<1024: precipitation phases wrap at 1024 cells, and a cell's id folded
/// the same way hashes alike either side of the wrap, so the fall never jumps.
float fold(float v) { return v - 1024.0 * floor(v / 1024.0); }

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

}  // namespace skylight

/// - frame: the view's size in points, the layer's scale, and the time in seconds, wrapping
///   hourly: what moves in a cycle (the stars' twinkle, the snow's sway, the lightning) runs at
///   rates that fit an hour exactly, so the wrap is seamless.
/// - clouds: how far the cloud has drifted with the wind (x) and changed shape (y, z), summed
///   frame by frame in Swift so a change of wind changes its speed, not its place.
/// - rain: each layer's fall, in cells, folded at 1024 (`fold`).
/// - snow: each layer's fall, and the wind's sideways carry (w), likewise folded.
/// - zenith, horizon: the sky's colours at the top and at the horizon.
/// - glow: the sun's glow colour.
/// - sun: its centre (x, y), radius, and how much of the disc shows (0 below the horizon or
///   behind cloud).
/// - light: the glow's strength, the twilight band's strength along the horizon, how bright
///   the stars are, and the storm (0 or 1: lightning).
/// - weather: cloud cover, rain, snow and fog, each 0 to 1.
/// - cloudLit, cloudShade: cloud on its sunward side and in its own shadow.
/// - ground: where the ground starts (x), the headroom (y, 1 to `Sky.peak`: how bright the
///   highlights may go, as a multiple of white) and the build-in's light (z, 0 black to 1).
/// - motion: the wind's push (x), and the burn-in drift (z, w) the ridges move with, so
///   their edge never holds one place.
struct SkylightUniforms {
    float4 frame;
    float4 clouds;
    float4 rain;
    float4 snow;
    float4 zenith;
    float4 horizon;
    float4 glow;
    float4 sun;
    float4 light;
    float4 weather;
    float4 cloudLit;
    float4 cloudShade;
    float4 ground;
    float4 motion;
};

fragment half4 skylightSky(SkyVertex in [[stage_in]], constant SkylightUniforms &sky [[buffer(0)]]) {
    using namespace skylight;

    float2 pos = skyPoint(in.position, sky.frame);
    float2 size = sky.frame.xy;
    float time = sky.frame.w;
    float4 clouds = sky.clouds, rain4 = sky.rain, snow4 = sky.snow;
    float4 zenith = sky.zenith, horizon = sky.horizon, glow = sky.glow;
    float4 sun = sky.sun, light = sky.light, weather = sky.weather;
    float4 cloudLit = sky.cloudLit, cloudShade = sky.cloudShade;
    float horizonY = sky.ground.x;
    float boost = sky.ground.y - 1.0;
    float4 motion = sky.motion;

    float2 shift = motion.zw;
    float x = pos.x - shift.x;
    float ground = horizonY + shift.y;

    // The ridges, then black below them: most of the lower screen returns here.
    float nearTop = ground - (4.0 + 30.0 * ridge(x / size.x * 7.0 + 11.0, 2.0));
    if (pos.y >= nearTop) { return half4(0, 0, 0, 1); }
    float farTop = ground - (18.0 + 64.0 * ridge(x / size.x * 3.6 + 3.0, 1.0));

    float cover = weather.x;
    float rain = weather.y;
    float snow = weather.z;
    float fog = weather.w;
    float drift = motion.x;

    float ty = saturate(pos.y / ground);
    float3 col = mix(float3(zenith.rgb), float3(horizon.rgb), pow(ty, 1.7));

    // The sun's glow, and the twilight band along the horizon under it.
    float2 toSun = sun.xy - pos;
    float dist = length(toSun) / size.y;
    float3 glowColour = float3(glow.rgb);
    col += glowColour * light.x * (0.5 * exp(-dist * 5.0) + 0.4 * (1.0 + 0.5 * boost) * exp(-dist * 16.0));
    float band = exp(-abs(pos.y - ground) / (size.y * 0.10));
    float spread = (pos.x - sun.x) / (size.x * 0.45);
    col += glowColour * light.y * band * exp(-spread * spread);

    // Stars: one in about seventy 7-point cells, each twinkling at its own rate.
    if (light.z > 0.0) {
        float2 cell = floor(pos / 7.0);
        float h = hash(cell);
        if (h > 0.986) {
            float2 centre = (cell + 0.2 + 0.6 * float2(hash(cell + 3.1), hash(cell + 7.7))) * 7.0;
            float r = 0.45 + 1.15 * fract(h * 91.0) * fract(h * 37.0);
            float spot = 1.0 - smoothstep(r - 0.45, r + 0.75, length(pos - centre));
            // A whole number of cycles an hour, from about 0.7 to 2.7 radians a second.
            float rate = 6.2831853 * (400.0 + floor(1150.0 * fract(h * 13.0))) / 3600.0;
            float twinkle = 0.7 + 0.3 * sin(time * rate + h * 80.0);
            col += float3(0.92, 0.95, 1.0) * spot * twinkle * light.z * (1.0 - 0.75 * ty) * (1.0 + 0.35 * boost);
        }
    }

    // The sun's disc.
    if (sun.w > 0.0) {
        float d = length(toSun);
        float disc = 1.0 - smoothstep(sun.z - 1.2, sun.z + 1.2, d);
        col = mix(col, float3(1.0, 0.97, 0.9) * (1.0 + boost), disc * sun.w);
    }

    // Cloud: fractal noise flattened toward the horizon, so the layer reads as seen from
    // below, drifting with the wind and slowly changing shape. Lit from the sun's side.
    float flash = 0.0;
    if (cover > 0.0) {
        float persp = mix(1.0, 3.4, ty * ty);
        float2 q = float2(x / size.y * 1.4, pos.y / size.y * 3.0 * persp);
        q.x -= clouds.x;
        float2 evolve = float2(clouds.y, -clouds.z);
        float n = fbm(q * 1.6 + evolve, 5);
        float density = smoothstep(0.75 - 0.55 * cover, 0.97 - 0.55 * cover, n);
        if (density > 0.001) {
            float2 sunward = normalize(toSun + float2(0.0001, 0.0)) * 0.07;
            float n2 = fbm(q * 1.6 + evolve + sunward, 3);
            float lit = saturate(0.6 + (n - n2) * 4.5);
            float3 cloud = mix(float3(cloudShade.rgb), float3(cloudLit.rgb), lit);
            cloud += glowColour * light.x * 0.6 * exp(-dist * 7.0) * (1.0 - density);
            col = mix(col, cloud, density * 0.96);
        }

        // Lightning: in a storm, a flash in about half of each six seconds, with an after-flicker.
        if (light.w > 0.0) {
            float k = floor(time / 6.0);
            float hk = hash(float2(k, 5.3));
            float dt = time - (k * 6.0 + hk * 4.0);
            if (hk > 0.45 && dt > 0.0) {
                flash = exp(-dt * 10.0) + 0.7 * step(0.16, dt) * exp(-(dt - 0.16) * 9.0);
            }
            col += float3(0.78, 0.82, 1.0) * flash * (0.25 + 0.75 * density) * 0.7 * (1.0 + boost);
        }
    }

    // Fog thickens toward the horizon.
    if (fog > 0.0) {
        float3 mist = mix(float3(horizon.rgb), float3(0.55, 0.57, 0.6) * (0.25 + 0.75 * float(horizon.g)), 0.5);
        col = mix(col, mist, fog * (0.25 + 0.65 * ty));
    }

    // The far ridge, hazed by the sky behind it.
    if (pos.y >= farTop) {
        float3 haze = float3(horizon.rgb) * 0.16 + glowColour * light.y * 0.05;
        col = mix(haze, col, 0.03 * (1.0 - fog) + 0.5 * fog);
    }

    // Rain: three layers of streaks leaning with the wind, nearer layers bigger and faster.
    if (rain > 0.0) {
        float angle = drift * 0.32;
        float2 rp = float2(pos.x * cos(angle) + pos.y * sin(angle), pos.y * cos(angle) - pos.x * sin(angle));
        for (int layer = 0; layer < 3; layer++) {
            float s = 1.0 + float(layer) * 0.7;
            float2 cellSize = float2(12.0, 74.0) * s;
            float2 g = rp / cellSize;
            g.y -= rain4[layer];
            g.x += float(layer) * 0.37;
            float2 id = floor(g);
            id.y = fold(id.y);
            if (hash(id + float(layer) * 17.0) < rain * 0.55) {
                float2 f = fract(g);
                float off = (f.x - (0.25 + 0.5 * hash(id + 1.7))) * cellSize.x;
                float streak = (1.0 - smoothstep(0.0, 0.6 + 0.4 * s, abs(off)))
                    * smoothstep(0.15, 0.45, f.y) * (1.0 - smoothstep(0.6, 0.95, f.y));
                col += float3(0.72, 0.78, 0.88) * streak * (0.16 + 0.08 * float(layer)) * (0.6 + 0.4 * float(horizon.g + 0.3));
            }
        }
    }

    // Snow: three layers of flakes, swaying as they fall.
    if (snow > 0.0) {
        for (int layer = 0; layer < 3; layer++) {
            float s = 1.0 + float(layer) * 0.8;
            float cellSize = 36.0 * s;
            float2 g = pos / cellSize;
            g.y -= snow4[layer];
            g.x += snow4.w + sin(time * 0.62831853 + g.y * 2.1 + float(layer) * 1.7) * 0.14;
            float2 id = floor(g);
            id = float2(fold(id.x), fold(id.y));
            if (hash(id + float(layer) * 23.0) < snow * 0.6) {
                float2 f = fract(g);
                float2 centre = 0.25 + 0.5 * float2(hash(id + 4.2), hash(id + 9.1));
                float r = 1.1 + 0.9 * float(layer);
                float flake = 1.0 - smoothstep(r - 0.6, r + 0.9, length((f - centre) * cellSize));
                col += float3(0.94, 0.96, 1.0) * flake * (0.5 + 0.18 * float(layer));
            }
        }
    }

    // Darker behind the text: the clock and agenda on the left, the weather on the right.
    float u = pos.x / size.x;
    float shade = mix(0.5, 1.0, smoothstep(0.0, 0.44, u)) * mix(0.68, 1.0, 1.0 - smoothstep(0.74, 1.0, u));
    col *= mix(shade, 1.0, flash * 0.5);

    // The build-in: the sky comes up out of the black.
    col *= sky.ground.z;
    // A step of dither breaks up banding in the long dark gradients.
    col += (hash(pos * 1.37) - 0.5) / 255.0 * sky.ground.z;
    return half4(half3(max(col, 0.0)), 1.0h);
}
