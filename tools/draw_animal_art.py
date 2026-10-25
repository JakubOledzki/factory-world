#!/usr/bin/env python3
"""Draws the art of husbandry with Pillow alone (no Blender): the hen, the sheep, the cow, the camel and the work horse that
stand on a plot (client/art/plot/, with their shadows and anchors in layout.json) and the icons of
the animals, their products and the shears (client/art/icons/).

Same framing as tools/render_plot_art.py: a plot sprite is 112 × 96 px with the tile's centre at
(56, 62), the view is 45° from above at 32 px per metre, and the light comes warm from the front
left. Everything is drawn at 4× and scaled down, so the edges come out soft like the renders.

    python3 tools/draw_animal_art.py
"""
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ART = Path(__file__).resolve().parent.parent / "client" / "art"
PLOT = ART / "plot"
ICONS = ART / "icons"
S = 4  # supersampling
PLOT_SS = 2  # plot sprites are stored twice their size on screen, like the renders (SS in render_plot_art.py)
SPRITE = (112, 96)
ANCHOR = (56, 62)
ICON = 64


def shade(color, k):
    """The colour lit by k (1 = as is, < 1 darker, > 1 lighter), kept in range."""
    return tuple(max(0, min(255, round(c * k))) for c in color[:3]) + ((color[3],) if len(color) > 3 else ())


def blob(draw, box, color, outline=None, light=0.22, width=0):
    """An ellipse lit from the front left: the base colour, a darker underside and a highlight."""
    x0, y0, x1, y1 = box
    draw.ellipse(box, fill=shade(color, 1 - light * 1.2))
    w, h = x1 - x0, y1 - y0
    draw.ellipse((x0 + w * 0.02, y0, x1 - w * 0.08, y1 - h * 0.22), fill=color)
    draw.ellipse((x0 + w * 0.14, y0 + h * 0.08, x0 + w * 0.6, y0 + h * 0.5), fill=shade(color, 1 + light))
    if outline:
        draw.ellipse(box, outline=outline, width=width or S)


def canvas(size):
    img = Image.new("RGBA", (size[0] * S, size[1] * S), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def finish(img, size):
    return img.resize(size, Image.LANCZOS)


def ground_shadow(size, anchor, rx, ry, strength=0.6):
    """A soft dark ellipse on the ground under the animal, like the renders' shadow pass."""
    img = Image.new("RGBA", (size[0] * S, size[1] * S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    cx, cy = anchor[0] * S, anchor[1] * S
    # The sun stands front left, so the shadow falls a little back and to the right.
    draw.ellipse((cx - rx * S + 2 * S, cy - ry * S - 2 * S, cx + rx * S + 4 * S, cy + ry * S - 1 * S), fill=(0, 0, 0, round(255 * strength)))
    img = img.filter(ImageFilter.GaussianBlur(2.5 * S))
    return finish(img, (size[0] * PLOT_SS, size[1] * PLOT_SS))


# --- Animals -------------------------------------------------------------------------------------

WOOL = (214, 206, 190)
WOOL_DARK = (118, 108, 96)
HIDE = (232, 224, 210)
PATCH = (54, 46, 42)
HEN = (196, 110, 62)
BEAK = (226, 182, 72)
COMB = (190, 46, 40)
LEG = (56, 42, 34)
OUTLINE = (28, 22, 18)


def draw_sheep(draw, cx, cy, k=1.0):
    """A sheep seen from the front left, standing on (cx, cy), k times the plot size."""
    s = S * k
    # Legs behind, the body, legs in front.
    for lx in (-11, 9):
        draw.rounded_rectangle((cx + lx * s, cy - 10 * s, cx + (lx + 4) * s, cy), radius=2 * s, fill=shade(LEG, 0.8))
    for lx in (-14, 6):
        draw.rounded_rectangle((cx + lx * s, cy - 9 * s, cx + (lx + 4) * s, cy + 1 * s), radius=2 * s, fill=LEG)
    blob(draw, (cx - 19 * s, cy - 27 * s, cx + 17 * s, cy - 5 * s), WOOL, OUTLINE, light=0.18)
    # Tufts along the back.
    for i, tx in enumerate((-13, -5, 3, 10)):
        blob(draw, (cx + tx * s, cy - (31 - (i % 2) * 2) * s, cx + (tx + 10) * s, cy - 20 * s), WOOL, light=0.12)
    # Head, dark with a woolly top.
    blob(draw, (cx - 27 * s, cy - 25 * s, cx - 13 * s, cy - 10 * s), WOOL_DARK, OUTLINE, light=0.2)
    blob(draw, (cx - 26 * s, cy - 28 * s, cx - 15 * s, cy - 20 * s), WOOL, light=0.12)
    draw.ellipse((cx - 25 * s, cy - 20 * s, cx - 22 * s, cy - 17 * s), fill=(10, 8, 8))
    draw.ellipse((cx - 19 * s, cy - 20 * s, cx - 16 * s, cy - 17 * s), fill=(10, 8, 8))
    # Ears.
    draw.ellipse((cx - 30 * s, cy - 24 * s, cx - 24 * s, cy - 20 * s), fill=shade(WOOL_DARK, 0.9), outline=OUTLINE, width=S)
    draw.ellipse((cx - 16 * s, cy - 24 * s, cx - 10 * s, cy - 20 * s), fill=shade(WOOL_DARK, 0.9), outline=OUTLINE, width=S)


def draw_cow(draw, cx, cy, k=1.0):
    s = S * k
    for lx in (-14, 11):
        draw.rounded_rectangle((cx + lx * s, cy - 14 * s, cx + (lx + 5) * s, cy), radius=2 * s, fill=shade(HIDE, 0.55))
    for lx in (-18, 7):
        draw.rounded_rectangle((cx + lx * s, cy - 13 * s, cx + (lx + 5) * s, cy + 1 * s), radius=2 * s, fill=shade(HIDE, 0.7))
    blob(draw, (cx - 24 * s, cy - 34 * s, cx + 22 * s, cy - 8 * s), HIDE, OUTLINE, light=0.16)
    # Patches.
    draw.ellipse((cx - 12 * s, cy - 32 * s, cx + 4 * s, cy - 20 * s), fill=PATCH)
    draw.ellipse((cx + 6 * s, cy - 24 * s, cx + 20 * s, cy - 12 * s), fill=PATCH)
    draw.ellipse((cx - 22 * s, cy - 22 * s, cx - 12 * s, cy - 13 * s), fill=PATCH)
    # Udder.
    draw.ellipse((cx + 2 * s, cy - 12 * s, cx + 14 * s, cy - 5 * s), fill=(214, 164, 150), outline=OUTLINE, width=S)
    # Head with horns and muzzle.
    blob(draw, (cx - 36 * s, cy - 34 * s, cx - 18 * s, cy - 14 * s), HIDE, OUTLINE, light=0.16)
    draw.ellipse((cx - 36 * s, cy - 23 * s, cx - 22 * s, cy - 14 * s), fill=(206, 170, 158), outline=OUTLINE, width=S)
    for hx in (-37, -22):
        draw.arc((cx + hx * s, cy - 44 * s, cx + (hx + 10) * s, cy - 30 * s), 200 if hx < -30 else 300, 360 if hx < -30 else 100,
                 fill=(224, 214, 190), width=3 * S)
    draw.ellipse((cx - 33 * s, cy - 30 * s, cx - 30 * s, cy - 27 * s), fill=(10, 8, 8))
    draw.ellipse((cx - 25 * s, cy - 30 * s, cx - 22 * s, cy - 27 * s), fill=(10, 8, 8))
    draw.ellipse((cx - 40 * s, cy - 34 * s, cx - 33 * s, cy - 29 * s), fill=shade(HIDE, 0.85), outline=OUTLINE, width=S)
    draw.ellipse((cx - 21 * s, cy - 34 * s, cx - 14 * s, cy - 29 * s), fill=shade(HIDE, 0.85), outline=OUTLINE, width=S)


def draw_hen(draw, cx, cy, k=1.0):
    s = S * k
    for lx in (-3, 3):
        draw.line((cx + lx * s, cy - 8 * s, cx + lx * s, cy), fill=BEAK, width=max(S, round(1.5 * S * k)))
        draw.line((cx + lx * s, cy, cx + (lx - 3) * s, cy + 1 * s), fill=BEAK, width=S)
        draw.line((cx + lx * s, cy, cx + (lx + 3) * s, cy + 1 * s), fill=BEAK, width=S)
    # Tail feathers behind.
    draw.polygon([(cx + 6 * s, cy - 14 * s), (cx + 17 * s, cy - 24 * s), (cx + 15 * s, cy - 12 * s)], fill=shade(HEN, 0.7), outline=OUTLINE)
    blob(draw, (cx - 10 * s, cy - 20 * s, cx + 10 * s, cy - 6 * s), HEN, OUTLINE, light=0.2)
    # Wing.
    draw.ellipse((cx - 6 * s, cy - 17 * s, cx + 7 * s, cy - 9 * s), fill=shade(HEN, 0.85), outline=OUTLINE, width=S)
    # Neck and head.
    draw.ellipse((cx - 14 * s, cy - 24 * s, cx - 4 * s, cy - 14 * s), fill=HEN, outline=OUTLINE, width=S)
    blob(draw, (cx - 17 * s, cy - 30 * s, cx - 7 * s, cy - 21 * s), HEN, OUTLINE, light=0.2)
    draw.polygon([(cx - 17 * s, cy - 26 * s), (cx - 22 * s, cy - 24 * s), (cx - 17 * s, cy - 23 * s)], fill=BEAK, outline=OUTLINE)
    draw.ellipse((cx - 14 * s, cy - 31 * s, cx - 8 * s, cy - 27 * s), fill=COMB, outline=OUTLINE, width=S)
    draw.ellipse((cx - 16 * s, cy - 24 * s, cx - 13 * s, cy - 21 * s), fill=COMB)
    draw.ellipse((cx - 14 * s, cy - 28 * s, cx - 12 * s, cy - 26 * s), fill=(10, 8, 8))


CAMEL = (186, 140, 84)


def draw_camel(draw, cx, cy, k=1.0):
    """A dromedary seen from the front left: long legs, one hump, a long curved neck."""
    s = S * k
    for lx in (-12, 10):
        draw.rounded_rectangle((cx + lx * s, cy - 20 * s, cx + (lx + 4) * s, cy), radius=2 * s, fill=shade(CAMEL, 0.6))
    for lx in (-16, 6):
        draw.rounded_rectangle((cx + lx * s, cy - 19 * s, cx + (lx + 4) * s, cy + 1 * s), radius=2 * s, fill=shade(CAMEL, 0.8))
    blob(draw, (cx - 20 * s, cy - 34 * s, cx + 18 * s, cy - 16 * s), CAMEL, OUTLINE, light=0.18)
    blob(draw, (cx - 9 * s, cy - 44 * s, cx + 9 * s, cy - 28 * s), CAMEL, OUTLINE, light=0.18)
    # The neck rising forward to the head.
    draw.polygon([(cx - 17 * s, cy - 30 * s), (cx - 24 * s, cy - 44 * s), (cx - 19 * s, cy - 47 * s), (cx - 11 * s, cy - 31 * s)],
                 fill=shade(CAMEL, 0.95), outline=OUTLINE)
    blob(draw, (cx - 32 * s, cy - 52 * s, cx - 16 * s, cy - 42 * s), CAMEL, OUTLINE, light=0.16)
    draw.ellipse((cx - 33 * s, cy - 48 * s, cx - 27 * s, cy - 43 * s), fill=shade(CAMEL, 0.75))
    draw.ellipse((cx - 23 * s, cy - 50 * s, cx - 20 * s, cy - 47 * s), fill=(10, 8, 8))
    draw.ellipse((cx - 19 * s, cy - 54 * s, cx - 15 * s, cy - 50 * s), fill=shade(CAMEL, 0.8), outline=OUTLINE, width=S)
    # Tail.
    draw.line((cx + 17 * s, cy - 28 * s, cx + 20 * s, cy - 18 * s), fill=shade(CAMEL, 0.6), width=2 * S)


HORSE = (122, 74, 40)
MANE = (40, 26, 18)


def draw_horse(draw, cx, cy, k=1.0):
    """A bay work horse seen from the front left: a heavy body, a dark mane and tail, white socks and a collar; tall, so
    drawn a little smaller to keep its head on the sprite."""
    s = S * k * 0.85
    for lx in (-14, 11):
        draw.rounded_rectangle((cx + lx * s, cy - 20 * s, cx + (lx + 5) * s, cy), radius=2 * s, fill=shade(HORSE, 0.6))
    for lx in (-18, 7):
        draw.rounded_rectangle((cx + lx * s, cy - 19 * s, cx + (lx + 5) * s, cy + 1 * s), radius=2 * s, fill=shade(HORSE, 0.8))
        draw.rounded_rectangle((cx + lx * s, cy - 5 * s, cx + (lx + 5) * s, cy + 1 * s), radius=2 * s, fill=(222, 214, 200))
    # Tail behind.
    draw.polygon([(cx + 19 * s, cy - 34 * s), (cx + 26 * s, cy - 22 * s), (cx + 22 * s, cy - 12 * s), (cx + 18 * s, cy - 26 * s)], fill=MANE, outline=OUTLINE)
    blob(draw, (cx - 22 * s, cy - 40 * s, cx + 22 * s, cy - 16 * s), HORSE, OUTLINE, light=0.18)
    # The neck rising forward, the mane along it, and the long head.
    draw.polygon([(cx - 18 * s, cy - 34 * s), (cx - 27 * s, cy - 52 * s), (cx - 19 * s, cy - 56 * s), (cx - 8 * s, cy - 36 * s)],
                 fill=shade(HORSE, 0.95), outline=OUTLINE)
    draw.polygon([(cx - 19 * s, cy - 56 * s), (cx - 8 * s, cy - 36 * s), (cx - 5 * s, cy - 38 * s), (cx - 15 * s, cy - 57 * s)], fill=MANE)
    blob(draw, (cx - 38 * s, cy - 60 * s, cx - 20 * s, cy - 48 * s), HORSE, OUTLINE, light=0.16)
    draw.ellipse((cx - 39 * s, cy - 56 * s, cx - 31 * s, cy - 48 * s), fill=shade(HORSE, 0.7), outline=OUTLINE, width=S)
    draw.ellipse((cx - 28 * s, cy - 58 * s, cx - 25 * s, cy - 55 * s), fill=(10, 8, 8))
    draw.polygon([(cx - 24 * s, cy - 60 * s), (cx - 22 * s, cy - 66 * s), (cx - 20 * s, cy - 59 * s)], fill=shade(HORSE, 0.85), outline=OUTLINE)
    # A blaze down the face and the collar of a work horse.
    draw.line((cx - 33 * s, cy - 59 * s, cx - 36 * s, cy - 51 * s), fill=(232, 226, 214), width=2 * S)
    draw.ellipse((cx - 22 * s, cy - 42 * s, cx - 8 * s, cy - 30 * s), outline=(70, 44, 24), width=3 * S)


ANIMALS = {
    # name: (draw, shadow radii)
    "sheep": (draw_sheep, (22, 7)),
    "cow": (draw_cow, (30, 8)),
    "chicken": (draw_hen, (12, 4)),
    "camel": (draw_camel, (28, 8)),
    "horse": (draw_horse, (30, 8)),
}


def render_animals(layout):
    for name, (paint, (rx, ry)) in ANIMALS.items():
        img, draw = canvas(SPRITE)
        paint(draw, ANCHOR[0] * S, ANCHOR[1] * S)
        finish(img, (SPRITE[0] * PLOT_SS, SPRITE[1] * PLOT_SS)).save(PLOT / f"{name}.png", optimize=True)
        ground_shadow(SPRITE, ANCHOR, rx, ry).save(PLOT / f"{name}_shadow.png", optimize=True)
        layout[name] = {"anchorX": ANCHOR[0], "anchorY": ANCHOR[1]}


# --- Icons -----------------------------------------------------------------------------------------

def icon():
    return canvas((ICON, ICON))


def save_icon(img, name):
    finish(img, (ICON, ICON)).save(ICONS / f"item_{name}.png", optimize=True)


def render_icons():
    for name, (paint, _) in ANIMALS.items():
        img, draw = icon()
        k = {"sheep": 1.05, "cow": 0.8, "chicken": 1.6, "camel": 0.85, "horse": 0.9}[name]
        paint(draw, 34 * S if name != "chicken" else 36 * S, 52 * S, k)
        save_icon(img, f"animal_{name}")

    # Eggs: three in a nest of straw.
    img, draw = icon()
    for i in range(14):
        a = i / 14 * math.tau
        draw.line((32 * S + math.cos(a) * 22 * S, 46 * S + math.sin(a) * 9 * S, 32 * S + math.cos(a + 0.9) * 26 * S, 44 * S + math.sin(a + 0.9) * 11 * S),
                  fill=(176, 142, 70), width=2 * S)
    draw.ellipse((6 * S, 36 * S, 58 * S, 58 * S), fill=(150, 118, 58), outline=OUTLINE, width=S)
    for (x, y) in ((16, 28), (34, 26), (26, 36)):
        blob(draw, (x * S, y * S, (x + 16) * S, (y + 20) * S), (236, 222, 196), OUTLINE, light=0.14)
    save_icon(img, "egg")

    # Wool: a fluffy fleece bundle.
    img, draw = icon()
    blob(draw, (8 * S, 18 * S, 56 * S, 54 * S), WOOL, OUTLINE, light=0.16)
    for (x, y, r) in ((12, 16, 11), (26, 10, 12), (40, 14, 11), (8, 32, 10), (46, 30, 11), (18, 40, 11), (36, 42, 11)):
        blob(draw, (x * S, y * S, (x + r * 2) * S, (y + r * 2) * S), WOOL, OUTLINE, light=0.12)
    save_icon(img, "wool")

    # Milk: a steel churn with a lid.
    img, draw = icon()
    steel = (166, 172, 180)
    draw.rounded_rectangle((18 * S, 22 * S, 46 * S, 60 * S), radius=5 * S, fill=steel, outline=OUTLINE, width=S)
    draw.rectangle((19 * S, 24 * S, 27 * S, 58 * S), fill=shade(steel, 1.2))
    draw.rectangle((38 * S, 24 * S, 45 * S, 58 * S), fill=shade(steel, 0.75))
    draw.rounded_rectangle((14 * S, 16 * S, 50 * S, 26 * S), radius=4 * S, fill=shade(steel, 0.9), outline=OUTLINE, width=S)
    draw.rounded_rectangle((26 * S, 6 * S, 38 * S, 18 * S), radius=3 * S, fill=shade(steel, 1.05), outline=OUTLINE, width=S)
    draw.ellipse((22 * S, 34 * S, 42 * S, 48 * S), fill=(240, 240, 234), outline=OUTLINE, width=S)
    save_icon(img, "milk")

    # Shears: two blades crossed on a spring.
    img, draw = icon()
    blade = (190, 196, 204)
    for sign in (-1, 1):
        pts = [(32 * S, 36 * S), ((32 + sign * 6) * S, 8 * S), ((32 + sign * 12) * S, 12 * S), ((32 + sign * 7) * S, 38 * S)]
        draw.polygon(pts, fill=blade, outline=OUTLINE)
        draw.line(((32 + sign * 2) * S, 36 * S, (32 + sign * 20) * S, 58 * S), fill=(96, 72, 48), width=5 * S)
        draw.line(((32 + sign * 2) * S, 36 * S, (32 + sign * 20) * S, 58 * S), fill=OUTLINE, width=S)
    draw.ellipse((26 * S, 32 * S, 38 * S, 42 * S), fill=(120, 124, 130), outline=OUTLINE, width=S)
    save_icon(img, "tool_shears")

    # Scrambled eggs on a plate.
    img, draw = icon()
    draw.ellipse((4 * S, 24 * S, 60 * S, 56 * S), fill=(226, 228, 224), outline=OUTLINE, width=S)
    draw.ellipse((10 * S, 28 * S, 54 * S, 52 * S), fill=(206, 208, 204))
    for (x, y, w, h) in ((14, 26, 20, 14), (28, 22, 22, 16), (20, 34, 24, 14), (36, 32, 16, 12)):
        blob(draw, (x * S, y * S, (x + w) * S, (y + h) * S), (232, 182, 70), OUTLINE, light=0.18)
    for (x, y) in ((22, 30), (38, 28), (30, 40)):
        draw.ellipse((x * S, y * S, (x + 3) * S, (y + 3) * S), fill=(60, 110, 50))
    save_icon(img, "scrambled_eggs")


if __name__ == "__main__":
    layout = json.loads((PLOT / "layout.json").read_text())
    render_animals(layout)
    render_icons()
    (PLOT / "layout.json").write_text(json.dumps(layout, indent=1) + "\n")
    print("drew", ", ".join(ANIMALS), "and the icons")
