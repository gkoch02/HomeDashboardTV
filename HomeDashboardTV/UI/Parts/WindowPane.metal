#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// The Window layout's pane, one pixel at a time: a street at the hour and in the weather,
// seen out of focus through glass, with beads of water sitting on the glass and drops running
// down it. Each bead and drop is a small lens: it shows the street sharp and upside down, as a
// real one does. Frost creeps in from the edges below freezing and mist fogs the glass. The
// colours are worked out in Swift (`WindowView`, from `WindowPane` in DashboardCore); this
// only composes them. Positions are in points, as SwiftUI lays out.

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

/// The street's inks and light, for one moment.
struct Street {
    float2 size;
    float ground;
    float3 zenith, horizon, building, windows, lamps;
    float night;
    float lit;
    float flash;
    float time;
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
    return mix(point * 1.4, disc * (0.5 + 0.4 * rim) * 0.6, saturate(blur / 12.0));
}

/// One row of buildings over *col*: blocks of random height in cells *cellW* wide, with lit
/// windows, which out of focus merge to each block's glow.
float3 buildings(float3 col, float2 p, float blur, thread const Street &s,
                 float cellW, float minH, float maxH, float shade, float seed) {
    float b = max(blur, 0.75);
    float ci = floor(p.x / cellW);
    float best = 0.0, cell = ci, top = 0.0;
    // A neighbour's soft edge can spill into this cell: the strongest of the three wins.
    for (int j = -1; j <= 1; j++) {
        float c = ci + float(j);
        float inset = cellW * (0.04 + 0.12 * hash(float2(c, seed + 1.0)));
        float x0 = c * cellW + inset, x1 = (c + 1.0) * cellW - inset;
        float t = s.ground - (minH + (maxH - minH) * hash(float2(c, seed)));
        float m = smoothstep(-b, b, p.x - x0) * smoothstep(-b, b, x1 - p.x) * smoothstep(-b, b, p.y - t);
        if (m > best) { best = m; cell = c; top = t; }
    }
    if (best <= 0.0) { return col; }
    float lit = s.lit * (0.4 + 1.2 * hash(float2(cell, seed + 2.0)));
    float3 glow = s.windows * lit * 0.35;
    if (blur < 8.0) {
        float2 g = float2(p.x / 26.0, (p.y - top) / 30.0);
        float2 id = floor(g);
        float2 f = fract(g);
        float on = step(hash(id + float2(cell * 7.0, seed)), lit);
        float pane = step(0.25, f.x) * step(f.x, 0.75) * step(0.2, f.y) * step(f.y, 0.75) * step(0.8, g.y);
        float3 sharp = s.windows * on * pane * (0.6 + 0.4 * hash(id + 3.3));
        glow = mix(sharp, glow, saturate(blur / 8.0));
    }
    return mix(col, s.building * shade + glow, best);
}

/// The street lights and car lights along the road, and their streaks on the wet surface.
float3 streetLights(float2 p, float blur, thread const Street &s) {
    float3 sum = float3(0.0);
    float cell = 120.0;
    float ci = floor(p.x / cell);
    for (int j = -1; j <= 1; j++) {
        float c = ci + float(j);
        float2 at = float2((c + 0.15 + 0.7 * hash(float2(c, 41.0))) * cell,
                           s.ground + 10.0 + 130.0 * hash(float2(c, 42.0)));
        if (hash(float2(c, 40.0)) > 0.65) { continue; }
        float3 tint = hash(float2(c, 43.0)) < 0.3 ? float3(1.0, 0.3, 0.24) : s.lamps;
        float bright = (0.25 + 0.5 * hash(float2(c, 44.0))) * (0.25 + 0.75 * s.night);
        float r = mix(3.0, 10.0 + 20.0 * hash(float2(c, 45.0)), saturate(blur / 12.0));
        sum += tint * bright * bokeh(length(p - at), r, blur);
        if (p.y > at.y) {
            float dx = (p.x - at.x) / (r * 0.6 + 2.0);
            sum += tint * bright * 0.12 * exp(-dx * dx) * exp(-(p.y - at.y) / 140.0);
        }
    }
    return sum;
}

/// The view through the glass at *p*, as a lens focused *blur* points short of it.
float3 street(float2 p, float blur, thread const Street &s) {
    float ty = saturate(p.y / s.ground);
    float3 col = mix(s.zenith, s.horizon, pow(ty, 1.4));
    col += float3(0.75, 0.8, 1.0) * s.flash * 0.45 * (1.0 - 0.5 * ty);

    col = buildings(col, p, blur, s, 150.0, s.size.y * 0.24, s.size.y * 0.48, 1.25, 7.0);
    col = buildings(col, p, blur, s, 220.0, s.size.y * 0.3, s.size.y * 0.66, 0.75, 19.0);

    // The road, wet and dark.
    float road = smoothstep(-max(blur, 0.75), max(blur, 0.75), p.y - s.ground);
    if (road > 0.0) {
        float depth = saturate((p.y - s.ground) / (s.size.y - s.ground));
        col = mix(col, mix(s.building * 0.9, s.building * 0.45, depth), road);
    }
    col += streetLights(p, blur, s);

    // The lamps that stand for what's next: big and soft out of focus, pulsing slowly.
    const float2 places[4] = { float2(0.585, 0.52), float2(0.705, 0.43), float2(0.80, 0.54), float2(0.49, 0.40) };
    const float sizes[4] = { 0.09, 0.07, 0.058, 0.075 };
    for (int i = 0; i < s.lampCount; i++) {
        float2 at = places[i] * s.size;
        float rate = 6.2831853 * float(41 + 7 * i) / 3600.0;
        float r = mix(5.0, s.size.y * sizes[i], saturate(blur / 12.0)) * (1.0 + 0.03 * sin(s.time * rate + float(i) * 2.0));
        col += s.lamp[i] * (0.42 + 0.08 * sin(s.time * rate * 1.3 + float(i))) * bokeh(length(p - at), r, blur);
    }
    return col;
}

/// A lens on the glass: its *offset* to where it looks in the street, how much of the pixel it
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

/// - size: the view, in points.
/// - time: seconds, wrapping hourly: everything that moves turns a whole number of times an
///   hour, so the wrap is seamless.
/// - zenith, horizon: the sky beyond the glass, at the top and at the street.
/// - building: the buildings' ink; windows, lamps: the light in their windows and the street's.
/// - light: night (x, 0 to 1), the share of windows lit (y), the storm (z, 0 or 1: lightning),
///   and how far the build-in has brought the scene up (w).
/// - glass: how wet the pane is (x), the wind's lean (y), frost (z) and mist (w), each 0 to 1.
/// - extra: snow on the glass (x), and how many of the lamps stand for something (y, 0 to 4).
/// - lamp0…lamp3: those lamps' colours, as the text's dots have them.
/// - motion: the burn-in drift (z, w) the street moves with, so its edges never hold one place.
[[ stitchable ]] half4 windowPane(float2 pos, half4 current,
                                  float2 size, float time,
                                  half4 zenith, half4 horizon, half4 building, half4 windows, half4 lamps,
                                  float4 light, float4 glass, float4 extra,
                                  half4 lamp0, half4 lamp1, half4 lamp2, half4 lamp3,
                                  float4 motion) {
    using namespace pane;

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

    Street s;
    s.size = size;
    s.ground = size.y * 0.8;
    s.zenith = float3(zenith.rgb);
    s.horizon = float3(horizon.rgb);
    s.building = float3(building.rgb);
    s.windows = float3(windows.rgb);
    s.lamps = float3(lamps.rgb);
    s.night = light.x;
    s.lit = light.y;
    s.flash = flash;
    s.time = time;
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
        Lens bead = beads(pos, 16.0, density * 0.6 + 0.04, time, 1.0);
        Lens fine = beads(pos, 7.0, density * density * 0.5, time, 29.0);
        if (fine.mask > bead.mask) { bead = fine; }
        bead.mask *= 1.0 - trail;
        lens.offset = bead.offset; lens.mask = bead.mask; lens.normal = bead.normal;
        isBead = 1.0;
    }

    // Through clear glass, out of focus; sharper where a drop has just wiped it.
    float3 col = street(view, mix(26.0, 12.0, trail), s);
    if (lens.mask > 0.0) {
        float3 seen = mix(street(view + lens.offset, 2.5, s), col * 1.15, 0.35);
        // Snow catches on the glass as white flakes, not lenses.
        seen = mix(seen, float3(0.88, 0.9, 0.94) * (0.35 + 0.6 * (1.0 - s.night)), snow * isBead * 0.85);
        float edge = smoothstep(0.55, 1.0, length(lens.normal));
        seen *= 1.0 - 0.3 * edge;
        // Its lower rim catches the light behind, as a drop's does.
        seen += (col * 1.4 + 0.04) * edge * smoothstep(0.0, 0.7, lens.normal.y);
        float2 toGlint = lens.normal - float2(-0.35, -0.45);
        seen += float3(1.0) * 0.4 * exp(-dot(toGlint, toGlint) * 18.0);
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
    return half4(half3(saturate(col)), 1.0h);
}
