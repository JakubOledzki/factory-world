#!/usr/bin/env python3
"""Draws the icons of the bottom toolbar with Pillow alone: the backpack of the inventory, the
garage, the market stall and the rest, into client/art/icons/toolbar_<name>.png.

Plain light grey like the buttons' text, in two shades, with details cut out so the button shows
through. Drawn on a 64-unit grid at 4× and scaled down, so the edges come out soft.

    python3 tools/draw_toolbar_icons.py
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw

ICONS = Path(__file__).resolve().parent.parent / "client" / "art" / "icons"
S = 4  # supersampling
ICON = 64

INK = (230, 225, 214, 255)  # UI.TEXT
SHADE = (172, 168, 160, 255)  # the second, darker part of a shape
GOLD = SHADE
GREEN = INK
CUT = (0, 0, 0, 0)  # drawing this makes a hole
DARK = CUT


class Pen:
    """Drawing on the 64-unit grid: every coordinate is scaled to the supersampled image."""

    def __init__(self) -> None:
        self.img = Image.new("RGBA", (ICON * S, ICON * S), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)

    @staticmethod
    def _p(points):
        return [(x * S, y * S) for x, y in points]

    def rect(self, x0, y0, x1, y1, fill, r=0):
        self.d.rounded_rectangle((x0 * S, y0 * S, x1 * S, y1 * S), radius=r * S, fill=fill)

    def poly(self, points, fill):
        self.d.polygon(self._p(points), fill=fill)

    def line(self, points, fill, w):
        self.d.line(self._p(points), fill=fill, width=round(w * S), joint="curve")
        for x, y in (points[0], points[-1]):
            self.dot(x, y, w / 2, fill)

    def dot(self, x, y, r, fill):
        self.d.ellipse(((x - r) * S, (y - r) * S, (x + r) * S, (y + r) * S), fill=fill)

    def ring(self, x, y, r, fill, w):
        self.d.ellipse(((x - r) * S, (y - r) * S, (x + r) * S, (y + r) * S), outline=fill, width=round(w * S))

    def arc(self, x, y, r, start, end, fill, w):
        self.d.arc(((x - r) * S, (y - r) * S, (x + r) * S, (y + r) * S), start, end, fill=fill, width=round(w * S))

    def save(self, name: str) -> None:
        out = self.img.resize((ICON, ICON), Image.LANCZOS)
        out.save(ICONS / f"toolbar_{name}.png")


def backpack():
    p = Pen()
    p.arc(32, 15, 8, 180, 360, INK, 3.5)  # handle
    p.rect(14, 14, 50, 56, INK, 10)
    p.rect(14, 14, 50, 26, GOLD, 8)  # flap
    p.rect(14, 22, 50, 26, GOLD)
    p.rect(29, 22, 35, 30, DARK, 1.5)  # buckle
    p.rect(30.5, 24, 33.5, 28.5, GOLD, 1)
    p.rect(20, 37, 44, 51, DARK, 4)  # front pocket
    p.rect(22, 39, 42, 49, INK, 3)
    p.line([(22, 43), (42, 43)], DARK, 1.6)
    p.save("inventory")


def garage():
    p = Pen()
    p.poly([(6, 26), (32, 8), (58, 26), (58, 31), (32, 13), (6, 31)], GOLD)  # roof
    p.poly([(11, 28), (32, 14), (53, 28), (53, 56), (11, 56)], INK)
    p.rect(17, 31, 47, 56, DARK, 1)  # opening
    for y in (34, 39.5, 45, 50.5):  # roll-up door
        p.rect(18.5, y, 45.5, y + 3.8, INK, 0.8)
    p.save("garage")


def market():
    p = Pen()
    p.rect(12, 30, 15.5, 57, INK)  # posts
    p.rect(48.5, 30, 52, 57, INK)
    p.rect(8, 42, 56, 49, INK, 2)  # counter
    p.rect(19, 36, 25, 42, GOLD, 1.5)  # goods
    p.dot(32, 38.5, 3.6, GREEN)
    p.rect(38, 35, 45, 42, GOLD, 1.5)
    p.poly([(12, 8), (52, 8), (58, 22), (6, 22)], INK)  # awning
    for i in range(5):
        x = 6 + i * 52 / 5
        if i % 2 == 0:
            p.poly([(12 + i * 8, 8), (12 + (i + 1) * 8, 8), (x + 52 / 5, 22), (x, 22)], GOLD)
    for i in range(5):  # scalloped edge
        x = 6 + 52 / 10 + i * 52 / 5
        p.d.pieslice(((x - 5.2) * S, 17 * S, (x + 5.2) * S, 27.4 * S), 0, 180, fill=GOLD if i % 2 == 0 else INK)
    p.save("market")


def contracts():
    p = Pen()
    p.rect(13, 11, 51, 58, SHADE, 4)  # board
    p.rect(17, 17, 47, 54, INK, 2)  # paper
    p.rect(23, 7, 41, 15, GOLD, 3)  # clip
    p.rect(28, 9.5, 36, 12.5, DARK, 1.5)
    for i, y in enumerate((25, 35, 45)):
        p.line([(20.5, y), (23, y + 2.6), (27, y - 2.4)], DARK, 2.2)
        p.line([(31, y), (43, y)], DARK, 2.2)
    p.save("contracts")


def company():
    p = Pen()
    p.rect(23, 9, 41, 21, INK, 4)  # handle
    p.d.rounded_rectangle((27 * S, 13 * S, 37 * S, 21 * S), radius=1 * S, fill=(0, 0, 0, 0))
    p.rect(7, 18, 57, 55, INK, 6)  # case
    p.rect(7, 31, 57, 36, GOLD)  # band
    p.rect(27, 28, 37, 39, GOLD, 2)  # lock
    p.rect(30, 31, 34, 36, DARK, 1)
    p.save("company")


def stats():
    p = Pen()
    p.line([(9, 8), (9, 55), (57, 55)], INK, 3.5)  # axes
    p.rect(15, 38, 23, 52, GOLD, 1.5)
    p.rect(27, 27, 35, 52, INK, 1.5)
    p.rect(39, 33, 47, 52, GOLD, 1.5)
    p.rect(51, 17, 57, 52, INK, 1.5)
    p.line([(15, 30), (28, 19), (40, 25), (54, 10)], CUT, 7)  # trend, with a gap around it
    p.line([(15, 30), (28, 19), (40, 25), (54, 10)], INK, 3)
    p.save("stats")


def achievements():
    p = Pen()
    p.arc(15, 20, 8, 90, 270, GOLD, 3.5)  # handles
    p.arc(49, 20, 8, 270, 90, GOLD, 3.5)
    p.d.chord((15 * S, -6 * S, 49 * S, 40 * S), 0, 180, fill=GOLD)  # cup
    p.rect(15, 8, 49, 17, GOLD)
    p.rect(13, 6, 51, 10, GOLD, 2)
    p.rect(28.5, 38, 35.5, 47, GOLD)  # stem
    p.rect(19, 46, 45, 51, INK, 1.5)  # base
    p.rect(16, 51, 48, 58, INK, 2)
    p.poly(star(32, 21, 7.5, 3.3), INK)
    p.save("achievements")


def star(cx, cy, r_out, r_in):
    return [(cx + (r_out if i % 2 == 0 else r_in) * math.sin(i * math.pi / 5),
             cy - (r_out if i % 2 == 0 else r_in) * math.cos(i * math.pi / 5)) for i in range(10)]


def world_map():
    p = Pen()
    p.dot(32, 32, 25, SHADE)  # sea
    # Land: rough continents.
    p.poly([(16, 15), (27, 11), (31, 18), (26, 24), (28, 32), (22, 36), (17, 30), (12, 26)], GREEN)
    p.poly([(36, 12), (46, 14), (52, 22), (47, 27), (40, 24), (35, 19)], GREEN)
    p.poly([(36, 33), (46, 31), (53, 38), (47, 50), (40, 52), (37, 44)], GREEN)
    p.poly([(18, 42), (25, 40), (28, 47), (22, 52)], GREEN)
    p.arc(32, 32, 25, 0, 360, INK, 3)
    p.d.ellipse((20 * S, 7 * S, 44 * S, 57 * S), outline=CUT, width=round(1.3 * S))
    p.line([(7.5, 32), (56.5, 32)], CUT, 1.3)
    p.save("world_map")


def logout():
    p = Pen()
    p.rect(10, 7, 38, 58, INK, 2)  # frame
    p.poly([(14, 10), (32, 14), (32, 58), (14, 55)], GOLD)  # open door
    p.dot(28, 35, 2.2, DARK)
    p.rect(38, 7, 39, 58, INK)
    p.line([(36, 32), (56, 32)], GREEN, 4.5)  # arrow out
    p.poly([(49, 22), (60, 32), (49, 42)], GREEN)
    p.save("logout")


def station():
    p = Pen()
    p.rect(14, 8, 50, 49, INK, 9)  # front of the engine
    p.rect(19, 14, 45, 29, DARK, 3)  # windscreen
    p.rect(21, 16, 43, 27, SHADE, 2)
    p.rect(14, 33, 50, 37, GOLD)
    p.dot(22, 42, 3.5, GOLD)  # lamps
    p.dot(42, 42, 3.5, GOLD)
    p.line([(19, 50), (12, 58)], INK, 3.5)  # rails
    p.line([(45, 50), (52, 58)], INK, 3.5)
    p.line([(9, 56), (55, 56)], INK, 2.5)
    p.save("station")


def plant():
    p = Pen()
    p.poly([(18, 42), (46, 42), (42, 58), (22, 58)], GOLD)  # pot
    p.rect(15, 38, 49, 44, GOLD, 2)
    p.line([(32, 39), (32, 18)], GREEN, 3.5)  # stem
    p.d.chord((10 * S, 14 * S, 34 * S, 34 * S), 200, 20, fill=GREEN)  # leaves
    p.d.chord((30 * S, 4 * S, 56 * S, 26 * S), 160, 340, fill=GREEN)
    p.line([(32, 30), (17, 22)], DARK, 1.3)
    p.line([(32, 20), (49, 13)], DARK, 1.3)
    p.save("plant")


def mine_upgrade():
    p = Pen()
    p.line([(12, 56), (39, 17)], GOLD, 5)  # handle
    p.arc(39, 42, 28, 222, 318, INK, 6.5)  # pick head
    p.line([(50, 58), (50, 42)], GREEN, 4.5)  # arrow up
    p.poly([(42, 44), (50, 33), (58, 44)], GREEN)
    p.save("mine_upgrade")


def city():
    p = Pen()
    p.poly([(6, 24), (32, 8), (58, 24)], INK)  # roof of the town hall
    p.rect(9, 24, 55, 28, SHADE)
    p.dot(32, 18, 3.5, DARK)  # clock
    for x in (13, 24, 36, 47):  # columns
        p.rect(x, 30, x + 5, 50, INK, 1)
    p.rect(7, 51, 57, 57, SHADE, 1)  # steps
    p.save("city")


def main() -> None:
    for draw in (backpack, garage, market, contracts, company, stats, achievements, world_map, logout,
                 station, plant, mine_upgrade, city):
        draw()


if __name__ == "__main__":
    main()
