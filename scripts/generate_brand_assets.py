#!/usr/bin/env python3
"""Render the tvOS app icon layers and top-shelf images into the asset catalog.

    python3 scripts/generate_brand_assets.py

The icon is the dashboard in one picture, in the app's own colours: a wall-calendar page
(front layer) showing one week as the app does, today's column in amber, over an amber sun (middle layer), on the app's
night-to-day sky (back layer). The parallax tilt slides the page across the sun. No text,
so it stays sharp at every size and in every language.

The top shelf is the week: seven day cards in a row, today's in amber, the sun beside them.
tvOS scales the shelf image up, crops the outer eighth on each side and covers the bottom
with the app row (as IdleHoursTV found on tvOS 27), so everything sits in the upper middle.

Every shape is drawn at 4x and downsampled, for clean edges. Needs Pillow. Every output is
derived; re-run after changing anything here.
"""
from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

REPO = Path(__file__).resolve().parent.parent
BRAND = REPO / "HomeDashboardTV" / "Resources" / "Assets.xcassets" / "App Icon & Top Shelf Image.brandassets"
PREVIEW = REPO / "docs"

# The app's palette (DashboardView.swift, Palette), in 0-255.
NIGHT = (13, 15, 23)
DAY = (33, 48, 77)
CARD_DARK = (34, 39, 52)
AMBER = (250, 199, 107)
AMBER_DEEP = (232, 150, 52)
PAGE = (244, 241, 234)
GRID = (206, 211, 221)
RING = (52, 58, 74)
BAR = (88, 98, 120)

SS = 4  # supersampling factor
INFO = {"info": {"author": "xcode", "version": 1}}


def canvas(width: int, height: int, fill=(0, 0, 0, 0)) -> Image.Image:
    return Image.new("RGBA", (width * SS, height * SS), fill)


def finish(image: Image.Image, width: int, height: int) -> Image.Image:
    return image.resize((width, height), Image.Resampling.LANCZOS)


def sky(width: int, height: int) -> Image.Image:
    """The app's ground: the day colour at the top easing into night."""
    column = Image.new("RGBA", (1, height))
    for y in range(height):
        t = (y / max(height - 1, 1)) ** 0.8
        column.putpixel((0, y), tuple(round(d + (n - d) * t) for d, n in zip(DAY, NIGHT)) + (255,))
    return column.resize((width, height))


def glow(size: tuple[int, int], centre: tuple[float, float], radius: float, colour, alpha: int) -> Image.Image:
    """A soft halo, drawn small and blurred so it costs nothing at 4x."""
    w, h = size
    small = Image.new("RGBA", (w // 8, h // 8), (0, 0, 0, 0))
    ImageDraw.Draw(small).ellipse(
        [(centre[0] - radius) / 8, (centre[1] - radius) / 8, (centre[0] + radius) / 8, (centre[1] + radius) / 8],
        fill=colour + (alpha,),
    )
    small = small.filter(ImageFilter.GaussianBlur(radius / 16))
    return small.resize(size, Image.Resampling.BICUBIC)


def sun(layer: Image.Image, cx: float, cy: float, r: float) -> None:
    """An amber disc with a clean radial highlight towards the upper left and a tight halo."""
    layer.alpha_composite(glow(layer.size, (cx, cy), r * 1.32, AMBER_DEEP, 90))
    disc = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(disc)
    hx, hy = cx - r * 0.34, cy - r * 0.34
    steps = 96
    for i in range(steps + 1):
        t = i / steps  # 0 at the rim, 1 at the highlight
        ease = t * t * (3 - 2 * t)
        colour = tuple(round(a + (b - a) * ease) for a, b in zip(AMBER_DEEP, (255, 222, 150)))
        rr = r * (1 - t) * 1.0 + r * 0.06 * t
        ox, oy = cx + (hx - cx) * t, cy + (hy - cy) * t
        d.ellipse([ox - rr, oy - rr, ox + rr, oy + rr], fill=colour + (255,))
    mask = Image.new("L", layer.size, 0)
    ImageDraw.Draw(mask).ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    layer.paste(disc, (0, 0), mask)


def shadow(size: tuple[int, int], box, radius: float, offset: float, blur: float, alpha: int) -> Image.Image:
    w, h = size
    small = Image.new("RGBA", (w // 4, h // 4), (0, 0, 0, 0))
    x0, y0, x1, y1 = box
    ImageDraw.Draw(small).rounded_rectangle(
        [x0 / 4, (y0 + offset) / 4, x1 / 4, (y1 + offset) / 4], radius / 4, fill=(0, 0, 0, alpha)
    )
    small = small.filter(ImageFilter.GaussianBlur(blur / 4))
    return small.resize(size, Image.Resampling.BICUBIC)


# --- app icon ---------------------------------------------------------------

def icon_layers(width: int, height: int) -> dict[str, Image.Image]:
    """Composed on an 800x480 grid (the @2x icon) and scaled to *width*."""
    s = width / 800 * SS

    back = sky(width * SS, height * SS)

    middle = canvas(width, height)
    sun(middle, 606 * s, 160 * s, 108 * s)

    front = canvas(width, height)
    page = (176 * s, 118 * s, 572 * s, 416 * s)
    front.alpha_composite(shadow(front.size, page, 34 * s, 14 * s, 22 * s, 120))
    d = ImageDraw.Draw(front)
    d.rounded_rectangle(page, 34 * s, fill=PAGE + (255,))
    # The header band: the page's top, clipped to its rounded corners.
    header = Image.new("L", front.size, 0)
    ImageDraw.Draw(header).rounded_rectangle(page, 34 * s, fill=255)
    ImageDraw.Draw(header).rectangle([0, page[1] + 74 * s, front.size[0], front.size[1]], fill=0)
    front.paste(Image.new("RGBA", front.size, AMBER + (255,)), (0, 0), header)
    # Binder rings through the header.
    for rx in (270, 478):
        d.rounded_rectangle(
            [(rx - 11) * s, (page[1] / s - 26) * s, (rx + 11) * s, (page[1] / s + 30) * s],
            11 * s,
            fill=RING + (255,),
        )
    # The week, as the app shows it: seven day columns with a few events in each, today's
    # in amber.
    cols = 7
    gx0, gy0, gx1, gy1 = 212, 222, 536, 388
    gap = 10
    cw = (gx1 - gx0 - gap * (cols - 1)) / cols
    events = (2, 3, 1, 3, 2, 1, 2)
    today = 3
    for c in range(cols):
        x = gx0 + c * (cw + gap)
        lit = c == today
        d.rounded_rectangle(
            [x * s, gy0 * s, (x + cw) * s, gy1 * s],
            9 * s,
            fill=(AMBER_DEEP if lit else GRID) + (255,),
        )
        bar = ((255, 236, 200) if lit else (164, 172, 188)) + (255,)
        for e in range(events[c]):
            y = gy0 + 16 + e * 26
            d.rounded_rectangle(
                [(x + 7) * s, y * s, (x + cw - 7) * s, (y + 14) * s],
                5 * s,
                fill=bar,
            )

    return {name: finish(layer, width, height) for name, layer in
            (("Back", back), ("Middle", middle), ("Front", front))}


def write_icon_stack(stack: str, sizes: list[tuple[int, int, str]]) -> None:
    rendered = {(w, h): icon_layers(w, h) for w, h, _ in sizes}
    root = BRAND / f"{stack}.imagestack"
    (root / "Contents.json").parent.mkdir(parents=True, exist_ok=True)
    (root / "Contents.json").write_text(json.dumps(
        {"layers": [{"filename": f"{n}.imagestacklayer"} for n in ("Front", "Middle", "Back")], **INFO},
        indent=2,
    ))
    for layer in ("Back", "Middle", "Front"):
        layer_dir = root / f"{layer}.imagestacklayer"
        imageset = layer_dir / "Content.imageset"
        imageset.mkdir(parents=True, exist_ok=True)
        (layer_dir / "Contents.json").write_text(json.dumps(INFO, indent=2))
        images = []
        for w, h, scale in sizes:
            name = f"{stack.lower().replace(' ', '-')}-{layer.lower()}@{scale}.png"
            image = rendered[(w, h)][layer]
            if layer == "Back":
                image = image.convert("RGB")  # the back layer must be opaque
            image.save(imageset / name, optimize=True)
            images.append({"idiom": "tv", "scale": scale, "filename": name})
        (imageset / "Contents.json").write_text(json.dumps({"images": images, **INFO}, indent=2))


# --- top shelf ----------------------------------------------------------------

def top_shelf(width: int, height: int) -> Image.Image:
    """The week, composed for the safe region: the middle three quarters across, the top
    two thirds down."""
    s = height / 720 * SS
    image = sky(width * SS, height * SS)
    W = width * SS
    safe_left, safe_right = W * 0.15, W * 0.85
    span = safe_right - safe_left

    sun_r = 92 * s
    sun_cx = safe_right - sun_r - 10 * s
    sun_cy = 250 * s
    layer = Image.new("RGBA", image.size, (0, 0, 0, 0))
    sun(layer, sun_cx, sun_cy, sun_r)
    image.alpha_composite(layer)

    cards_right = sun_cx - sun_r - 70 * s
    gap = 22 * s
    card_w = (cards_right - safe_left - gap * 6) / 7
    top, bottom = 120 * s, 400 * s
    d = ImageDraw.Draw(image)
    for i in range(7):
        x = safe_left + i * (card_w + gap)
        today = i == 2
        box = (x, top, x + card_w, bottom)
        image.alpha_composite(shadow(image.size, box, 24 * s, 10 * s, 16 * s, 90))
        d = ImageDraw.Draw(image)
        d.rounded_rectangle(box, 24 * s, fill=(AMBER if today else CARD_DARK) + (255,))
        # A header bar and a few event bars, shorter towards the end of the week.
        ink = (AMBER_DEEP if today else BAR) + (255,)
        faint = ((214, 160, 80) if today else (64, 72, 90)) + (255,)
        pad = 20 * s
        d.rounded_rectangle([x + pad, top + 26 * s, x + card_w * 0.62, top + 46 * s], 10 * s, fill=ink)
        events = (4, 3, 4, 2, 3, 1, 2)[i]
        for e in range(events):
            y = top + 82 * s + e * 44 * s
            length = (0.82, 0.64, 0.74, 0.55)[e % 4]
            d.rounded_rectangle([x + pad, y, x + pad + (card_w - 2 * pad) * length, y + 14 * s], 7 * s, fill=faint)
    return image.resize((width, height), Image.Resampling.LANCZOS).convert("RGB")


def write_top_shelf(imageset: str, base: tuple[int, int]) -> None:
    folder = BRAND / f"{imageset}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    images = []
    for scale, factor in (("1x", 1), ("2x", 2)):
        name = f"{imageset.lower().replace(' ', '-')}@{scale}.png"
        top_shelf(base[0] * factor, base[1] * factor).save(folder / name, optimize=True)
        images.append({"idiom": "tv", "scale": scale, "filename": name})
    (folder / "Contents.json").write_text(json.dumps({"images": images, **INFO}, indent=2))


def write_brand_contents() -> None:
    BRAND.mkdir(parents=True, exist_ok=True)
    (BRAND / "Contents.json").write_text(json.dumps({"assets": [
        {"filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"},
        {"filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"},
        {"filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"},
        {"filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"},
    ], **INFO}, indent=2))


def write_preview() -> None:
    layers = icon_layers(800, 480)
    icon = layers["Back"].copy()
    icon.alpha_composite(layers["Middle"])
    icon.alpha_composite(layers["Front"])
    PREVIEW.mkdir(exist_ok=True)
    icon.convert("RGB").save(PREVIEW / "app-icon.png", optimize=True)
    top_shelf(1920, 720).resize((1400, 525), Image.Resampling.LANCZOS).save(PREVIEW / "top-shelf.png", optimize=True)


def main() -> None:
    write_brand_contents()
    write_icon_stack("App Icon", [(400, 240, "1x"), (800, 480, "2x")])
    write_icon_stack("App Icon - App Store", [(1280, 768, "1x")])
    write_top_shelf("Top Shelf Image", (1920, 720))
    write_top_shelf("Top Shelf Image Wide", (2320, 720))
    write_preview()
    print("brand assets written")


if __name__ == "__main__":
    main()
