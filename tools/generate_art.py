#!/usr/bin/env python3
"""Draws the game's pixel art into client/art/. Run: python3 tools/generate_art.py

Sprites are written as character grids: each letter is a colour from PALETTE, '.' is transparent.
Keeping the art as code makes it easy to tweak colours and regenerate everything at once.
"""
import random
from pathlib import Path

from PIL import Image

OUT = Path(__file__).resolve().parent.parent / "client" / "art"

# Endesga 32 palette (subset), by letter.
PALETTE = {
    "K": "#181425",  # near black outline
    "N": "#262b44",  # navy shadow
    "D": "#3a4466",  # dark slate
    "S": "#5a6988",  # slate
    "G": "#8b9bb4",  # grey
    "L": "#c0cbdc",  # light grey
    "W": "#ffffff",  # white
    "c": "#ead4aa",  # cream
    "t": "#e4a672",  # tan
    "b": "#b86f50",  # brick
    "m": "#733e39",  # mortar / dark brown
    "r": "#3e2731",  # very dark brown
    "R": "#a22633",  # dark red
    "e": "#e43b44",  # red
    "o": "#f77622",  # orange
    "y": "#feae34",  # yellow-orange
    "Y": "#fee761",  # yellow
    "g": "#63c74d",  # green
    "h": "#3e8948",  # dark green
    "H": "#265c42",  # deeper green
    "u": "#124e89",  # dark blue
    "B": "#0099db",  # blue
    "C": "#2ce8f5",  # cyan
    "p": "#d77643",  # copper
    "P": "#be4a2f",  # dark copper
}


def rgba(hex_color: str, alpha: int = 255) -> tuple:
    h = hex_color.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), alpha)


def sprite(rows: list[str]) -> Image.Image:
    width = max(len(r) for r in rows)
    img = Image.new("RGBA", (width, len(rows)), (0, 0, 0, 0))
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch != ".":
                img.putpixel((x, y), rgba(PALETTE[ch]))
    return img


def save(name: str, img: Image.Image) -> None:
    img.save(OUT / f"{name}.png")


# --- Tiles -------------------------------------------------------------------

def floor_tile() -> Image.Image:
    """Concrete garage floor, 16×16, tiles seamlessly."""
    rnd = random.Random(7)
    img = Image.new("RGBA", (16, 16), rgba(PALETTE["G"]))
    for _ in range(26):
        img.putpixel((rnd.randrange(16), rnd.randrange(16)), rgba(PALETTE["S"]))
    for _ in range(10):
        img.putpixel((rnd.randrange(16), rnd.randrange(16)), rgba(PALETTE["L"]))
    for x in range(16):  # slab seam along the top edge
        img.putpixel((x, 0), rgba(PALETTE["S"]))
    for y in range(16):
        img.putpixel((0, y), rgba(PALETTE["S"]))
    return img


def brick_tile() -> Image.Image:
    """Brick wall, 16×16: two rows of offset bricks with mortar and a lit top edge."""
    img = Image.new("RGBA", (16, 16), rgba(PALETTE["m"]))
    rnd = random.Random(3)
    for row in range(2):
        y0 = row * 8
        offset = 0 if row == 0 else 8
        for brick in range(-1, 2):
            x0 = brick * 16 + offset
            for y in range(y0 + 1, y0 + 8):
                for x in range(x0 + 1, x0 + 16):
                    if 0 <= x < 16:
                        color = "b"
                        if y == y0 + 1:
                            color = "t"
                        elif y == y0 + 7:
                            color = "P"
                        elif rnd.random() < 0.06:
                            color = "P"
                        img.putpixel((x, y), rgba(PALETTE[color]))
    return img


def baseboard_tile() -> Image.Image:
    """Concrete strip where wall meets floor, 16×6."""
    rows = [
        "LLLLLLLLLLLLLLLL",
        "GGGGGGGGGGGGGGGG",
        "GGGGGSGGGGGGGSGG",
        "SSSSSSSSSSSSSSSS",
        "DDDDDDDDDDDDDDDD",
        "NNNNNNNNNNNNNNNN",
    ]
    return sprite(rows)


# --- Props -------------------------------------------------------------------

def garage_door() -> Image.Image:
    """Roller shutter, 64×56."""
    w, h = 64, 56
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for y in range(h):
        for x in range(w):
            if x < 3 or x >= w - 3 or y < 3:
                c = "D" if (x in (0, w - 1) or y == 0) else "S"
            elif y >= h - 2:
                c = "N"
            else:
                slat = (y - 3) % 6
                c = {0: "W", 1: "L", 2: "L", 3: "L", 4: "G", 5: "S"}[slat]
                if x in (3, w - 4):
                    c = "G"
            img.putpixel((x, y), rgba(PALETTE[c]))
    # Handle.
    for x in range(28, 36):
        img.putpixel((x, h - 8), rgba(PALETTE["K"]))
        img.putpixel((x, h - 7), rgba(PALETTE["D"]))
    return img


def window() -> Image.Image:
    """Small window with sky, 28×20."""
    rows = []
    for y in range(20):
        row = ""
        for x in range(28):
            if x in (0, 27) or y in (0, 19):
                row += "K"
            elif x in (1, 26) or y in (1, 18):
                row += "L"
            elif x == 13 or x == 14 or y == 9:
                row += "L" if (x == 13 or y == 9) else "G"
            else:
                sky = "C" if y < 5 else "B"
                if (x + y) % 9 == 0 and y < 9:
                    sky = "W"
                row += sky
        rows.append(row)
    return sprite(rows)


def workbench() -> Image.Image:
    """Wooden workbench with a vice and tools, 40×22."""
    rows = [
        "....KK..........................KKK.....",
        "...KGGK....................KK..KLLK.....",
        "...KGLK...................KyyK.KGGK.....",
        "..KKGGKK..................KooK..KK......",
        "KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK",
        "KttttttttttttttttttttttttttttttttttttttK",
        "KbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbK",
        "KmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmK",
        "KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK",
        ".Kbm.................................KbK",
        ".Kbm..KKKKKKKKKKKKKKKKKKKKKKKKKKKKK..KbK",
        ".Kbm..KtttttttttttttttttttttttttttK..KbK",
        ".Kbm..KbbbbbbbbbbbbbmmbbbbbbbbbbbbK..KbK",
        ".Kbm..KbbbbbbbbbbbbbbbbbbbbbbbbbbbK..KbK",
        ".Kbm..KmmmmmmmmmmmmmmmmmmmmmmmmmmmK..KbK",
        ".Kbm..KKKKKKKKKKKKKKKKKKKKKKKKKKKKK..KbK",
        ".Kbm.................................KbK",
        ".Kbm.................................KbK",
        ".Kbm.................................KbK",
        ".Kbm.................................KbK",
        ".KKK.................................KKK",
        "........................................",
    ]
    return sprite(rows)


def trash_bin() -> Image.Image:
    """Big green trash bin with bags peeking out, 24×30."""
    rows = [
        "......KKKKKK............",
        ".....KNNDNNNK...........",
        "....KNDDNNDDNK..KKK.....",
        "...KKNNNNKKKNNKKNDNK....",
        "..KKKKKKKKKKKKKKKKKKKK..",
        ".KgggggggggggggggggggggK",
        ".KhhhhhhhhhhhhhhhhhhhhhK",
        "..KKKKKKKKKKKKKKKKKKKKK.",
        "..KghhhhhhhhhhhhhhhhhHK.",
        "..KghhhhhhhhhhhhhhhhhHK.",
        "..KghhgggggggggggghhhHK.",
        "..KghhgWWWWgggWWWWghhHK.",
        "..KghhgWgggWgWgggWghhHK.",
        "..KghhgggWggggWgggghhHK.",
        "..KghhggWgggggWWgggHhHK.",
        "..KghhgWWWWggWWggggHhHK.",
        "..KghhgggggggggggggHhHK.",
        "..KghhhhhhhhhhhhhhhhhHK.",
        "..KghhhhhhhhhhhhhhhhhHK.",
        "..KghhhhhhhhhhhhhhhhhHK.",
        "..KghhhhhhhhhhhhhhhhhHK.",
        "..KghhhhhhhhhhhhhhhhhHK.",
        "..KghhhhhhhhhhhhhhhhhHK.",
        "..KghhhhhhhhhhhhhhhhhHK.",
        "..KHHHHHHHHHHHHHHHHHHHK.",
        "..KKKKKKKKKKKKKKKKKKKKK.",
        "..KDK..............KDK..",
        "..KKK..............KKK..",
        "........................",
        "........................",
    ]
    return sprite(rows)


def shelf() -> Image.Image:
    """Wall shelf with boxes and cans, 36×18."""
    rows = [
        "....KKKKKKK.........................",
        "....KtttttK....KKKK.KKKK............",
        "....KbbbbbK....KLLK.KeeK....KKKKKK..",
        "....KbtttbK....KGGK.KRRK....KyyyyK..",
        "....KbbbbbK....KLLK.KeeK....KooooK..",
        "....KmmmmmK....KGGK.KRRK....KyyyyK..",
        "KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK",
        "KttttttttttttttttttttttttttttttttttK",
        "KmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmK",
        "KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK",
        "..KmK..........................KmK..",
        "..KmK..........................KmK..",
        "...KK..........................KK...",
    ]
    return sprite(rows)


# --- Item icons (16×16) --------------------------------------------------------

ICONS = {
    "trash": [
        "................",
        "......KK.KK.....",
        ".......KKK......",
        "......KDDDK.....",
        ".....KNDDDNK....",
        "....KNDSDDDNK...",
        "...KNDSSDDDDNK..",
        "...KNDSDDDDDNK..",
        "..KNDDSDDDDDDNK.",
        "..KNDDDDDDDDDNK.",
        "..KNDDDDDDDDDNK.",
        "..KNNDDDDDDDNNK.",
        "...KNNNNNNNNNK..",
        "....KKKKKKKKK...",
        "................",
        "................",
    ],
    "waste_paper": [
        "................",
        "....KKKKKK......",
        "...KWWWWccKK....",
        "..KWWLLWWcccK...",
        "..KWcWWWLWccK...",
        ".KWWWcWWWWWcLK..",
        ".KWLLLWWLLWWcK..",
        ".KcWWWWcWWWLWK..",
        ".KWWcWLLLWWWcK..",
        "..KWWWWWWcWcK...",
        "..KcLWWcWWWLK...",
        "...KWcWWWWcK....",
        "....KKccLKK.....",
        "......KKK.......",
        "................",
        "................",
    ],
    "waste_plastic": [
        "................",
        "......KKKK......",
        "......KeeK......",
        "......KKKK......",
        ".....KCWCBK.....",
        "....KCWCCBBK....",
        "....KCWCCCBK....",
        "....KWWWWWWK....",
        "....KeeeeeRK....",
        "....KWWWWWWK....",
        "....KCWCCCBK....",
        "....KCWCCCBK....",
        "....KCWCCBBK....",
        "....KBBBBBuK....",
        ".....KKKKKK.....",
        "................",
    ],
    "waste_aluminium": [
        "................",
        "................",
        ".....KKKKKK.....",
        "....KLGGGGLK....",
        "....KWLLLLGK....",
        "....KWLLLLGK....",
        "...KKeeeeeRKK...",
        "....KeWeeeRK....",
        "...KKeWWeeRK....",
        "....KeeeeeRK....",
        "....KWLLGGSK.K..",
        "...KKWLLGSSKKK..",
        "....KLLGGSK.....",
        ".....KKKKKK.....",
        "................",
        "................",
    ],
    "waste_glass": [
        "................",
        "...........K....",
        "..........KCK...",
        ".........KCWK...",
        "....K...KCgCK...",
        "...KCK..KggK....",
        "..KCWgK.KghK....",
        "..KgCghKKhK.....",
        "...KgghhKK..K...",
        "....KhhK...KCK..",
        ".KK..KK...KCghK.",
        "KCWK.....KCgghK.",
        "KggK....KgghhK..",
        ".KhK.....KKKK...",
        "..K.............",
        "................",
    ],
    "waste_copper": [
        "................",
        ".......KKKK.....",
        ".....KKpyypKK...",
        "....KpyPPPPypK..",
        "...KpPKK..KKPpK.",
        "...KyK......KyK.",
        "..KpPK.KKKK.KPpK",
        "..KyK.KpyypK.KyK",
        "..KpK.KyKKPK.KpK",
        "..KyK.KpPKK.KPyK",
        "...KpK.KK..KpPK.",
        "...KPyKK..KKyPK.",
        "....KPpyyyypPK..",
        ".....KKPPPPKK...",
        ".......KKKK.....",
        "................",
    ],
}

COIN = [
    "..KKKK..",
    ".KYYYyK.",
    "KYWYyyoK",
    "KYYKKyoK",
    "KYYKyyoK",
    "KyyyyooK",
    ".KyoooK.",
    "..KKKK..",
]

XP_STAR = [
    "...KK...",
    "...KYK..",
    "KKKYYKKK",
    "KYYWYYYK",
    ".KYYYyK.",
    ".KYKKyK.",
    "KyK..KyK",
    "KK....KK",
]


# --- UI 9-slices -----------------------------------------------------------------

def panel() -> Image.Image:
    """16×16 panel: dark outline, lit inner edge, flat fill; 6 px margins for 9-slicing."""
    img = Image.new("RGBA", (16, 16), rgba(PALETTE["N"]))
    for i in range(16):
        for (x, y) in ((i, 0), (i, 15), (0, i), (15, i)):
            img.putpixel((x, y), rgba(PALETTE["K"]))
    for i in range(1, 15):
        img.putpixel((i, 1), rgba(PALETTE["S"]))
        img.putpixel((1, i), rgba(PALETTE["D"]))
        img.putpixel((14, i), rgba(PALETTE["K"]))
        img.putpixel((i, 14), rgba(PALETTE["K"]))
    for i in range(2, 14):
        img.putpixel((i, 2), rgba(PALETTE["D"]))
    # Rivets in the corners.
    for (x, y) in ((3, 4), (12, 4), (3, 12), (12, 12)):
        img.putpixel((x, y), rgba(PALETTE["G"]))
    return img


def button(face: str, light: str, dark: str, pressed: bool = False) -> Image.Image:
    """12×12 button; pressed moves the face down one pixel."""
    img = Image.new("RGBA", (12, 12), (0, 0, 0, 0))
    top = 1 if pressed else 0
    for y in range(12):
        for x in range(12):
            if (x in (0, 11) and y in (top, 11)):
                continue  # rounded corners
            if y < top:
                continue
            if x in (0, 11) or y in (top, 11):
                c = "K"
            elif y == 10 and not pressed:
                c = dark
            elif y == top + 1:
                c = light
            else:
                c = face
            img.putpixel((x, y), rgba(PALETTE[c]))
    return img


def slot() -> Image.Image:
    """10×10 recessed inventory slot."""
    img = Image.new("RGBA", (10, 10), rgba(PALETTE["K"]))
    for y in range(1, 9):
        for x in range(1, 9):
            c = "N"
            if y == 8 or x == 8:
                c = "D"
            img.putpixel((x, y), rgba(PALETTE[c]))
    return img


def bar(fill: str, light: str) -> Image.Image:
    """6×6 progress bar fill with a highlight row."""
    img = Image.new("RGBA", (6, 6), rgba(PALETTE[fill]))
    for x in range(6):
        img.putpixel((x, 1), rgba(PALETTE[light]))
    return img


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    save("floor", floor_tile())
    save("bricks", brick_tile())
    save("baseboard", baseboard_tile())
    save("garage_door", garage_door())
    save("window", window())
    save("workbench", workbench())
    save("shelf", shelf())
    save("trash_bin", trash_bin())
    for name, rows in ICONS.items():
        save(f"item_{name}", sprite(rows))
    save("coin", sprite(COIN))
    save("xp_star", sprite(XP_STAR))
    save("ui_panel", panel())
    save("ui_button", button("D", "S", "N"))
    save("ui_button_hover", button("S", "G", "D"))
    save("ui_button_pressed", button("N", "D", "N", pressed=True))
    save("ui_button_accent", button("h", "g", "H"))
    save("ui_button_accent_hover", button("g", "Y", "h"))
    save("ui_slot", slot())
    save("ui_bar_xp", bar("y", "Y"))
    save("ui_bar_progress", bar("B", "C"))
    print(f"Wrote art to {OUT}")


if __name__ == "__main__":
    main()
