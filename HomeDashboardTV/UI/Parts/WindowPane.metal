#include "SkyPass.h"
using namespace metal;

// The Window layout's pane, one pixel at a time: light and colour at the hour and in the
// weather, seen far out of focus through glass, with beads of water sitting on the glass and
// drops running down it. Each bead and drop is a small lens: it brings the lights behind it
// into focus as points, upside down, as a real one does. Frost creeps in from the edges below freezing and mist fogs the glass. The
// colours are worked out in Swift (`WindowView`, from `WindowPane` in DashboardCore); this
// only composes them. Positions are in points, as SwiftUI lays out. Drawn by `SkyLayer` into
// a 16-bit extended-range layer: with headroom, the lights beyond the glass, the lanterns,
// the drops' glints and the lightning go brighter than white.

namespace pane {

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

float fbm(float2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 4; i++) {
        value += amplitude * noise(p);
        p = p * 2.03 + float2(17.1, 9.2);
        amplitude *= 0.5;
    }
    return value;
}

/// The light beyond the glass, for one moment.
struct Scene {
    float2 size;
    float3 zenith, horizon, ground, glow, lights;
    float night;
    float drift;
    float flash;
    float time;
    /// The headroom above white, 0 (none) to `Sky.peak` - 1: the lights' extra brightness.
    float boost;
    int lampCount;
    float3 lamp[4];
};

/// A light seen at *d* points from its centre: out of focus (*blur* 12 or more) a flat disc
/// with a crisp edge and a brighter rim, as a lens draws one; in focus, a small bright point.
/// A drop's trail, sharper than the clear glass, still draws the lights as whole discs.
float bokeh(float d, float r, float blur) {
    float disc = 1.0 - smoothstep(r - 1.2, r + 1.2, d);
    float rim = smoothstep(r * 0.72, r, d) * disc;
    float point = exp(-d * d / max(r * r * 0.5, 0.01));
    return mix(point * 1.4, disc * (0.6 + 0.25 * rim) * 0.6, saturate(blur / 12.0));
}

/// The view through the glass at *p*, as a lens focused *blur* points short of it: the sky's
/// colour running down to a darker ground, washes of glow drifting slowly across it, a scatter
/// of lights, and the lanterns that stand for what's next.
float3 scene(float2 p, float blur, thread const Scene &s) {
    float2 u = p / s.size;
    float3 col = u.y < 0.55 ? mix(s.zenith, s.horizon, smoothstep(0.0, 0.55, u.y))
                            : mix(s.horizon, s.ground, smoothstep(0.55, 1.0, u.y));
    col += float3(0.75, 0.8, 1.0) * s.flash * 0.45 * (1.0 - 0.5 * u.y) * (1.0 + s.boost);

    // Washes of glow, each wandering on its own slow loop, a whole number of times an hour.
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float a = s.time * 6.2831853 * float(2 + i) / 3600.0;
        float b = s.time * 6.2831853 * float(3 + 2 * i) / 3600.0;
        float2 c = float2(0.5 + 0.32 * sin(a + fi * 2.1), 0.42 + 0.16 * sin(b + fi * 1.3)) * s.size;
        float r = s.size.y * (0.32 + 0.08 * fi);
        float2 d = (p - c) / r;
        col += s.glow * (0.22 - 0.05 * fi) * exp(-dot(d, d) * 1.6);
    }

    // The scatter of lights, in rows that sway a little with the wind; most warm, some cool,
    // brighter after dark.
    float cell = 150.0;
    float2 ci = floor(p / cell);
    for (int j = -1; j <= 1; j++) {
        for (int k = -1; k <= 1; k++) {
            float2 c = ci + float2(j, k);
            float h = hash(c + 31.0);
            if (h > 0.26) { continue; }
            float sway = s.drift * 18.0 * sin(s.time * 6.2831853 * float(17 + int(h * 40.0)) / 3600.0 + h * 30.0);
            float2 at = (c + 0.2 + 0.6 * float2(hash(c + 2.7), hash(c + 5.9))) * cell + float2(sway, 0.0);
            float3 tint = hash(c + 8.1) < 0.7 ? s.lights : float3(0.72, 0.82, 1.0);
            float r = mix(2.5, 12.0 + 26.0 * hash(c + 4.4), saturate(blur / 12.0));
            float rate = 6.2831853 * float(30 + int(h * 90.0)) / 3600.0;
            float bright = (0.25 + 0.55 * s.night) * (0.35 + 0.65 * hash(c + 6.6)) * (0.75 + 0.25 * sin(s.time * rate + h * 50.0))
                * (1.0 + 0.7 * s.boost);
            col += tint * bright * bokeh(length(p - at), r, blur);
        }
    }

    // The lanterns that stand for what's next: the biggest and warmest lights, pulsing slowly.
    const float2 places[4] = { float2(0.56, 0.37), float2(0.68, 0.27), float2(0.79, 0.38), float2(0.46, 0.29) };
    const float sizes[4] = { 0.09, 0.07, 0.058, 0.075 };
    for (int i = 0; i < s.lampCount; i++) {
        float2 at = places[i] * s.size;
        float rate = 6.2831853 * float(41 + 7 * i) / 3600.0;
        float flicker = 6.2831853 * float(53 + 9 * i) / 3600.0;
        float r = mix(5.0, s.size.y * sizes[i], saturate(blur / 12.0)) * (1.0 + 0.03 * sin(s.time * rate + float(i) * 2.0));
        col += s.lamp[i] * (0.4 + 0.3 * s.night + 0.06 * sin(s.time * flicker + float(i))) * (1.0 + 0.5 * s.boost)
            * bokeh(length(p - at), r, blur);
    }
    return col;
}

/// A lens on the glass: its *offset* to where it looks beyond it, how much of the pixel it
/// covers, and whether a running drop has wiped this spot clear.
struct Lens {
    float2 offset;
    float mask;
    float2 normal;
    float trail;
};

/// Beads sitting on the glass, one at most in each *cell*-point square, each forming and
/// drying over its own minute or two.
Lens beads(float2 p, float cell, float density, float time, float seed) {
    Lens out = { float2(0.0), 0.0, float2(0.0), 0.0 };
    float2 id = floor(p / cell);
    float h = hash(id + seed);
    if (h > density) { return out; }
    float2 centre = (id + 0.3 + 0.4 * float2(hash(id + seed + 3.1), hash(id + seed + 7.7))) * cell;
    float rate = (20.0 + floor(40.0 * hash(id + seed + 5.3))) / 3600.0;
    float life = fract(time * rate + h * 9.0);
    float grown = smoothstep(0.0, 0.1, life) * (1.0 - smoothstep(0.85, 1.0, life));
    float r = cell * (0.1 + 0.2 * pow(hash(id + seed + 9.9), 2.0)) * grown;
    if (r < 0.3) { return out; }
    float2 d = p - centre;
    out.mask = 1.0 - smoothstep(r - 0.8, r + 0.4, length(d));
    out.normal = d / r;
    out.offset = -d * 5.5;
    return out;
}

/// Drops running down the glass in columns *colW* wide, leaning with the wind: each moves in
/// fits and starts, wipes a clear trail behind it and leaves small beads along the trail.
Lens runners(float2 p, float colW, float wet, float drift, float time, float height, float seed) {
    Lens out = { float2(0.0), 0.0, float2(0.0), 0.0 };
    float lean = drift * 0.35;
    float2 q = float2(p.x - lean * p.y, p.y);
    float ci = floor(q.x / colW);
    float h = hash(float2(ci, seed));
    if (h > (wet - 0.15) * 1.05) { return out; }

    // Once down the pane every 5 to 12 seconds, a whole number of times an hour, pausing
    // three times on the way: the slope never goes negative, so a drop never climbs.
    float rate = (300.0 + floor(400.0 * hash(float2(ci, seed + 1.0)))) / 3600.0;
    float run = fract(time * rate + h * 7.0);
    float y = (run - sin(6.2831853 * run * 3.0) / (6.2831853 * 3.0)) * height * 1.3 - height * 0.15;
    float r = colW * (0.07 + 0.05 * hash(float2(ci, seed + 2.0)));
    float cx = (ci + 0.5) * colW + colW * 0.2 * sin(q.y * 0.015 + h * 40.0);

    float2 d = float2(q.x - cx, q.y - y);
    float2 body = float2(d.x, d.y * (d.y < 0.0 ? 0.7 : 1.0));
    float drop = 1.0 - smoothstep(r - 0.8, r + 0.4, length(body));
    if (drop > 0.0) {
        out.mask = drop;
        out.normal = body / r;
        out.offset = -body * 5.5;
        return out;
    }

    float trailLength = height * 0.35 * (0.5 + h);
    float above = y - q.y;
    if (above > 0.0 && above < trailLength) {
        out.trail = (1.0 - smoothstep(trailLength * 0.6, trailLength, above)) * (1.0 - smoothstep(r * 0.5, r * 0.9, abs(d.x)));
        // The beads it left, at fixed places down its path, smaller the longer they've sat.
        float spacing = r * 2.6;
        float k = floor(q.y / spacing);
        float by = (k + 0.5) * spacing;
        float since = y - by;
        if (since > r * 1.5 && hash(float2(k, ci + seed)) < 0.75) {
            float br = r * 0.32 * saturate(1.0 - since / trailLength);
            float2 bd = float2(d.x, q.y - by);
            float bead = 1.0 - smoothstep(br - 0.6, br + 0.4, length(bd));
            if (bead > 0.0 && br > 0.3) {
                out.mask = bead;
                out.normal = bd / br;
                out.offset = -bd * 5.5;
            }
        }
    }
    return out;
}

}  // namespace pane

/// - frame: the view's size in points, the layer's scale, and the time in seconds, wrapping
///   hourly: everything that moves turns a whole number of times an hour, so the wrap is
///   seamless.
/// - zenith, horizon, ground: the colour beyond the glass, at the top, across the middle and
///   at the bottom.
/// - glow: the drifting washes of light; lights: the scattered lights.
/// - light: night (x, 0 to 1), the headroom (y, 1 to `Sky.peak`: how bright the lights may go,
///   as a multiple of white), the storm (z, 0 or 1: lightning), and how far the build-in has
///   brought the scene up (w).
/// - glass: how wet the pane is (x), the wind's lean (y), frost (z) and mist (w), each 0 to 1.
/// - extra: snow on the glass (x), and how many of the lanterns stand for something (y, 0 to 4).
/// - lamp0…lamp3: those lanterns' colours, as the text's dots have them.
/// - motion: the burn-in drift (z, w) the lights move with, so they never hold one place.
struct WindowUniforms {
    float4 frame;
    float4 zenith;
    float4 horizon;
    float4 ground;
    float4 glow;
    float4 lights;
    float4 light;
    float4 glass;
    float4 extra;
    float4 lamp0;
    float4 lamp1;
    float4 lamp2;
    float4 lamp3;
    float4 motion;
};

fragment half4 windowPane(SkyVertex in [[stage_in]], constant WindowUniforms &sky [[buffer(0)]]) {
    using namespace pane;

    float2 pos = skyPoint(in.position, sky.frame);
    float2 size = sky.frame.xy;
    float time = sky.frame.w;
    float4 zenith = sky.zenith, horizon = sky.horizon, ground = sky.ground, glow = sky.glow, lights = sky.lights;
    float4 light = sky.light, glass = sky.glass, extra = sky.extra;
    float4 lamp0 = sky.lamp0, lamp1 = sky.lamp1, lamp2 = sky.lamp2, lamp3 = sky.lamp3;
    float4 motion = sky.motion;

    // Lightning: in a storm, a flash in about half of each six seconds, with an after-flicker.
    float flash = 0.0;
    if (light.z > 0.0) {
        float k = floor(time / 6.0);
        float hk = hash(float2(k, 5.3));
        float dt = time - (k * 6.0 + hk * 4.0);
        if (hk > 0.45 && dt > 0.0) {
            flash = exp(-dt * 10.0) + 0.7 * step(0.16, dt) * exp(-(dt - 0.16) * 9.0);
        }
    }

    Scene s;
    s.size = size;
    s.zenith = float3(zenith.rgb);
    s.horizon = float3(horizon.rgb);
    s.ground = float3(ground.rgb);
    s.glow = float3(glow.rgb);
    s.lights = float3(lights.rgb);
    s.night = light.x;
    s.drift = glass.y;
    s.flash = flash;
    s.time = time;
    s.boost = light.y - 1.0;
    s.lampCount = int(clamp(extra.y, 0.0, 4.0));
    s.lamp[0] = float3(lamp0.rgb);
    s.lamp[1] = float3(lamp1.rgb);
    s.lamp[2] = float3(lamp2.rgb);
    s.lamp[3] = float3(lamp3.rgb);

    float wet = glass.x;
    float snow = extra.x;
    float2 shift = motion.zw;
    float2 view = pos - shift;

    // What's on the glass here: a running drop or its trail first, then the beads it left.
    Lens lens = runners(pos, 64.0, wet, glass.y, time, size.y, 3.0);
    Lens wide = runners(pos, 104.0, wet * 0.8, glass.y, time, size.y, 11.0);
    if (wide.mask > lens.mask) { lens.offset = wide.offset; lens.mask = wide.mask; lens.normal = wide.normal; }
    float trail = max(lens.trail, wide.trail);
    float isBead = 0.0;
    if (lens.mask <= 0.0) {
        float density = max(wet, snow * 0.6);
        Lens bead = beads(pos, 16.0, density * 0.6, time, 1.0);
        Lens fine = beads(pos, 7.0, density * density * 0.5, time, 29.0);
        if (fine.mask > bead.mask) { bead = fine; }
        bead.mask *= 1.0 - trail;
        lens.offset = bead.offset; lens.mask = bead.mask; lens.normal = bead.normal;
        isBead = 1.0;
    }

    // Through clear glass, out of focus; sharper where a drop has just wiped it.
    float3 col = scene(view, mix(16.0, 12.0, trail), s);
    if (lens.mask > 0.0) {
        float3 seen = mix(scene(view + lens.offset, 2.5, s), col * 1.15, 0.35);
        // Snow catches on the glass as white flakes, not lenses.
        seen = mix(seen, float3(0.88, 0.9, 0.94) * (0.35 + 0.6 * (1.0 - s.night)), snow * isBead * 0.85);
        float edge = smoothstep(0.55, 1.0, length(lens.normal));
        seen *= 1.0 - 0.3 * edge;
        // Its lower rim catches the light behind, as a drop's does.
        seen += (col * 1.4 + 0.04) * edge * smoothstep(0.0, 0.7, lens.normal.y);
        float2 toGlint = lens.normal - float2(-0.35, -0.45);
        seen += float3(1.0) * 0.4 * (1.0 + s.boost) * exp(-dot(toGlint, toGlint) * 18.0);
        col = mix(col, seen, lens.mask);
    }

    // Mist on the glass, wiped where the drops have run.
    float mist = glass.w * (1.0 - trail) * (1.0 - lens.mask);
    col = mix(col, s.horizon * 0.55 + 0.12, mist * 0.55);

    // Frost from the edges inward, in feathery crystals.
    if (glass.z > 0.0) {
        float2 u = pos / size;
        float edge = min(min(u.x, 1.0 - u.x) * 1.6, min(u.y, 1.0 - u.y) * 2.2);
        float reach = glass.z * 0.2 + 0.16 * fbm(pos / 120.0) - edge;
        float frost = smoothstep(0.0, 0.16, reach);
        // Feathers: fine ridges that grow inward, thinning toward the clear middle.
        float feathers = smoothstep(0.45, 0.75, fbm(pos / 7.0 + fbm(pos / 34.0) * 4.0));
        float cover = frost * (0.25 + 0.5 * feathers) * (0.5 + 0.5 * frost);
        col = mix(col, float3(0.86, 0.9, 0.95) * (0.3 + 0.55 * (1.0 - s.night)), cover);
    }

    // Darker behind the text: the clock at the top left, what's next at the bottom right.
    float2 u = pos / size;
    float clock = 1.0 - smoothstep(0.0, 0.42, length((u - float2(0.14, 0.24)) * float2(1.0, 1.5)));
    float next = 1.0 - smoothstep(0.0, 0.32, length((u - float2(0.82, 0.8)) * float2(1.0, 1.5)));
    col *= 1.0 - 0.5 * max(clock, next);

    col *= light.w;
    // A step of dither breaks up banding in the long dark gradients.
    col += (hash(pos * 1.37) - 0.5) / 255.0 * light.w;
    return half4(half3(max(col, 0.0)), 1.0h);
}
