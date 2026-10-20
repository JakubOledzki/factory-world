#!/usr/bin/env python3
"""Draws the 9-slice textures of the game's interface into client/art/ui/.

Run: python3 tools/generate_ui.py

Dark, bevelled metal panels and buttons with a slight noise, so the interface matches the
rendered 3D art. Margins for 9-slicing are listed in client/ui/ui.gd.
"""
import random
from pathlib import Path

from PIL import Image

OUT = Path(__file__).resolve().parent.parent / "client" / "art" / "ui"

random.seed(3)


def hex_rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def bevel(size: int, top: str, bottom: str, light: str, shadow: str, outline: str | None = "#0a0a0b",
          noise: int = 4, inner_light: str | None = None) -> Image.Image:
    """A square with a vertical gradient, a lit top-left edge and a shaded bottom-right edge."""
    img = Image.new("RGBA", (size, size))
    px = img.load()
    t, b = hex_rgb(top), hex_rgb(bottom)
    lt, sh = hex_rgb(light), hex_rgb(shadow)
    o = 1 if outline else 0
    for y in range(size):
        for x in range(size):
            if outline and (x == 0 or y == 0 or x == size - 1 or y == size - 1):
                c = hex_rgb(outline)
                # Rounded corners.
                if (x in (0, size - 1)) and (y in (0, size - 1)):
                    px[x, y] = (0, 0, 0, 0)
                    continue
            elif y == o or x == o:
                c = lt
            elif y == size - 1 - o or x == size - 1 - o:
                c = sh
            elif inner_light and y == o + 1:
                c = hex_rgb(inner_light)
            else:
                c = lerp(t, b, y / (size - 1))
            n = random.randint(-noise, noise)
            px[x, y] = (*(max(0, min(255, v + n)) for v in c), 255)
    return img


def bar(top: str, bottom: str, light: str) -> Image.Image:
    img = Image.new("RGBA", (12, 12))
    px = img.load()
    for y in range(12):
        for x in range(12):
            c = hex_rgb(light) if y == 0 else lerp(hex_rgb(top), hex_rgb(bottom), y / 11)
            px[x, y] = (*c, 255)
    return img


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    images = {
        "panel": bevel(48, "#2c2c2f", "#2c2c2f", "#4c4c50", "#161617"),
        "inset": bevel(32, "#19191b", "#1e1e20", "#0d0d0e", "#38383b", outline=None, noise=3),
        "button": bevel(32, "#5a5a5f", "#424246", "#7a7a80", "#26262a"),
        "button_hover": bevel(32, "#6a6a70", "#4e4e53", "#8e8e95", "#2c2c30"),
        "button_pressed": bevel(32, "#333336", "#3c3c40", "#1c1c1e", "#55555a"),
        "button_accent": bevel(32, "#f2a43a", "#c8741c", "#ffd48a", "#7a4410"),
        "button_accent_hover": bevel(32, "#ffb84e", "#d88424", "#ffe2a6", "#86501a"),
        "bar_xp": bar("#f5b041", "#c9781c", "#ffe0a0"),
        "bar_progress": bar("#7ccf4a", "#3f8f2a", "#c4f0a0"),
    }
    for name, img in images.items():
        img.save(OUT / f"{name}.png")
    print(f"Wrote {len(images)} textures to {OUT}")


if __name__ == "__main__":
    main()
