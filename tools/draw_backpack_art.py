#!/usr/bin/env python3
"""Draws the icons of the backpacks with Pillow alone (client/art/icons/item_backpack_*.png): the
cheaper the smaller and plainer, the million-dollar one in leather with gold. Same style as the
icons of tools/draw_animal_art.py: 64 × 64 px, drawn at 4× and scaled down, lit from the front left.

    python3 tools/draw_backpack_art.py
"""
from pathlib import Path

from PIL import Image, ImageDraw

ICONS = Path(__file__).resolve().parent.parent / "client" / "art" / "icons"
S = 4
ICON = 64
OUTLINE = (40, 32, 26)

# id: (cloth, trim, width and height of the bag in px, pockets on the sides)
BACKPACKS = {
    "school": ((70, 120, 200), (230, 196, 60), 30, 36, False),
    "hiking": ((70, 140, 80), (60, 60, 60), 34, 40, False),
    "trekking": ((210, 110, 40), (60, 60, 60), 36, 46, True),
    "expedition": ((150, 40, 40), (200, 200, 200), 40, 50, True),
    "tycoon": ((110, 64, 36), (232, 186, 64), 42, 52, True),
}


def shade(color, k):
    return tuple(max(0, min(255, round(c * k))) for c in color)


def draw_backpack(cloth, trim, w, h, pockets):
    img = Image.new("RGBA", (ICON * S, ICON * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, bottom = 32, 60
    x0, x1, y0 = cx - w / 2, cx + w / 2, bottom - h
    # The carrying loop on top.
    d.arc(((cx - 7) * S, (y0 - 7) * S, (cx + 7) * S, (y0 + 7) * S), 180, 360, fill=OUTLINE, width=3 * S)
    if pockets:
        for side in (-1, 1):
            px = x0 - 5 if side < 0 else x1 - 3
            d.rounded_rectangle((px * S, (bottom - h * 0.55) * S, (px + 8) * S, (bottom - 4) * S), radius=3 * S,
                                fill=shade(cloth, 0.75), outline=OUTLINE, width=S)
    d.rounded_rectangle((x0 * S, y0 * S, x1 * S, bottom * S), radius=9 * S, fill=cloth, outline=OUTLINE, width=S)
    # Light from the front left, shadow on the right.
    d.rounded_rectangle(((x0 + 3) * S, (y0 + 4) * S, (x0 + w * 0.32) * S, (bottom - 6) * S), radius=6 * S, fill=shade(cloth, 1.18))
    d.rectangle(((x1 - w * 0.18) * S, (y0 + 8) * S, (x1 - 2) * S, (bottom - 6) * S), fill=shade(cloth, 0.8))
    # The flap and its buckle.
    d.rounded_rectangle(((x0 + 1) * S, (y0 + 1) * S, (x1 - 1) * S, (y0 + h * 0.36) * S), radius=8 * S,
                        fill=shade(cloth, 0.88), outline=OUTLINE, width=S)
    d.rounded_rectangle(((cx - 3) * S, (y0 + h * 0.3) * S, (cx + 3) * S, (y0 + h * 0.46) * S), radius=S,
                        fill=trim, outline=OUTLINE, width=S)
    # The front pocket.
    d.rounded_rectangle(((x0 + w * 0.2) * S, (bottom - h * 0.38) * S, (x1 - w * 0.2) * S, (bottom - 4) * S), radius=5 * S,
                        fill=shade(cloth, 0.92), outline=OUTLINE, width=S)
    d.line(((x0 + w * 0.24) * S, (bottom - h * 0.3) * S, (x1 - w * 0.24) * S, (bottom - h * 0.3) * S), fill=trim, width=2 * S)
    return img.resize((ICON, ICON), Image.LANCZOS)


if __name__ == "__main__":
    for name, (cloth, trim, w, h, pockets) in BACKPACKS.items():
        draw_backpack(cloth, trim, w, h, pockets).save(ICONS / f"item_backpack_{name}.png", optimize=True)
