#!/usr/bin/env python3
"""Render the README banner at docs/banner.png.

    python3 scripts/make_banner.py

The app's own sky and sun from generate_brand_assets.py, its faces (Figtree for the
wordmark, DM Sans for the rest) and its palette, beside the Dashboard layout as the
README shows it (docs/dashboard.png) in a thin bezel. Drawn at 2x and downsampled, like
the icon. Needs Pillow. The output is derived; re-run after changing anything here or
reshooting docs/dashboard.png.
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "scripts"))
from generate_brand_assets import AMBER, PAGE, RING, shadow, sky, sun  # noqa: E402

FONTS = REPO / "HomeDashboardTV" / "Resources" / "Fonts"
OUT = REPO / "docs" / "banner.png"
SHOT = REPO / "docs" / "dashboard.png"

WIDTH, HEIGHT = 1600, 400
S = 2  # supersample


def font(name: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONTS / name), size * S)


def main() -> None:
    w, h = WIDTH * S, HEIGHT * S
    image = sky(w, h)
    sun(image, w * 0.565, h * 0.30, 110 * S)

    # The Dashboard layout in a bezel, with the icon's soft shadow under it.
    shot = Image.open(SHOT).convert("RGB").resize((640 * S, 360 * S), Image.Resampling.LANCZOS)
    sx, sy = w - shot.width - 70 * S, (h - shot.height) // 2 + 6 * S
    bezel = 6 * S
    box = (sx - bezel, sy - bezel, sx + shot.width + bezel, sy + shot.height + bezel)
    image.alpha_composite(shadow(image.size, box, 10 * S, 10 * S, 18 * S, 120))
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle(box, 10 * S, fill=RING + (255,))
    image.paste(shot, (sx, sy))

    x = 80 * S
    draw.text((x, 92 * S), "Home Dashboard", font=font("Figtree-ExtraBold.ttf", 92), fill=PAGE + (255,))
    draw.text((x + 4 * S, 206 * S), "for Apple TV", font=font("DMSans.ttf", 44), fill=AMBER + (255,))
    draw.text(
        (x + 4 * S, 276 * S), "the Pi's dashboard, drawn for the big screen",
        font=font("DMSans.ttf", 28), fill=PAGE + (255,),
    )
    draw.text(
        (x + 4 * S, 318 * S), "tvOS and a Mac screensaver  ·  reads the Pi's snapshot, fetches nothing itself",
        font=font("DMSans.ttf", 20), fill=(206, 211, 221, 255),
    )

    out = image.resize((WIDTH, HEIGHT), Image.Resampling.LANCZOS).convert("RGB")
    out.save(OUT, optimize=True)
    print(f"wrote {OUT.relative_to(REPO)} ({WIDTH}×{HEIGHT})")


if __name__ == "__main__":
    main()
