#!/usr/bin/env python3
"""Renders the garage's room in layers for its upgrades, into client/art/garage/rooms/.

The game stacks three pictures under the furniture: the floor (floor_<level>.jpg, one for each
level of the floor upgrade), the walls with everything on them (walls_<level>.png, transparent
where the floor shows, one for each level of the walls upgrade, the last an office with glass
walls over the city) and a vignette darkening the edges (vignette.png). The lighting upgrade only
brightens the room in the game, so it needs no pictures.

Same setup as render_art.py:
    .venv-art/bin/python tools/render_garage_rooms.py [floors] [walls] [vignette] [floor_<n>...] [walls_<n>...]
"""
import math
import random
import sys
from pathlib import Path

import render_art as ra  # noqa: I001  (imports bpy first)
import bpy
from mathutils import Vector
from PIL import Image, ImageDraw, ImageFilter

from render_art import (FRONT_H, ROOM_D, ROOM_W, SCREEN_H, SCREEN_W, TMP, WALL_H, WALL_T, Mat, box, cylinder, mesh_from,
                        plain, rusty_metal)

OUT = ra.ART / "garage" / "rooms"

# What each level of the floor and walls upgrades looks like, as the server names them (GarageUpgrades).
FLOORS = ["Surowy beton w plamach", "Oczyszczony beton", "Beton szlifowany", "Posadzka żywiczna", "Płytki warsztatowe",
          "Gres", "Panele", "Deski sosnowe", "Parkiet dębowy", "Lastryko", "Marmur"]
WALLS = ["Gołe pustaki", "Tynk", "Białe ściany", "Boazeria", "Płytki do połowy", "Cegła klinkierowa", "Dębowe panele",
         "Duże okna", "Beton architektoniczny", "Przeszklenie", "Biuro z widokiem na miasto"]

DOOR_X, DOOR_W, DOOR_H = 1.9, 2.8, 2.3


# --- Floors ---------------------------------------------------------------------------------------

def tiles(m: Mat, width, height, color1, color2, mortar, mortar_size=0.004, offset=0.0, rotate=False):
    """A brick texture laid flat: tiles or boards `width` × `height` metres. Returns (colour, mask)."""
    brick = m.node("ShaderNodeTexBrick", offset=offset)
    brick.inputs["Scale"].default_value = 1.0
    brick.inputs["Mortar Size"].default_value = mortar_size
    brick.inputs["Brick Width"].default_value = width
    brick.inputs["Row Height"].default_value = height
    brick.inputs["Color1"].default_value = (*color1, 1)
    brick.inputs["Color2"].default_value = (*color2, 1)
    brick.inputs["Mortar"].default_value = (*mortar, 1)
    brick.inputs["Bias"].default_value = 0.0
    if rotate:
        mapping = m.node("ShaderNodeMapping")
        m.link(m.coord.outputs["Object"], mapping.inputs["Vector"])
        ra._input(mapping, "Rotation").default_value = (0, 0, math.pi / 2)
        m.link(mapping.outputs["Vector"], brick.inputs["Vector"])
    else:
        m.link(m.coord.outputs["Object"], brick.inputs["Vector"])
    return brick.outputs["Color"], brick.outputs["Fac"]


def finish(m: Mat, col, roughness, bump=None, bump_strength=0.15, grime=0.5):
    col = m.grime(col, grime, 0.4)
    return m.done(col, roughness, 0.0, bump, bump_strength)


def concrete(stains: bool, base=(0.085, 0.085, 0.09), hi=(0.16, 0.155, 0.15), roughness=0.85, slabs=True):
    m = Mat("floor")
    big = m.noise(0.8, detail=4)
    fine = m.noise(30.0, detail=8)
    col = m.ramp(fine.outputs["Fac"], [(0.35, base), (0.65, hi)]).outputs["Color"]
    if stains:
        stain = m.ramp(big.outputs["Fac"], [(0.58, (0, 0, 0)), (0.66, (1, 1, 1))]).outputs["Color"]
        col = m.mix(stain, col, (0.02, 0.018, 0.016))
    if slabs:
        joints, _ = tiles(m, 2.0, 2.0, (1, 1, 1), (1, 1, 1), (0.45, 0.45, 0.45), 0.005)
        col = m.mix(1.0, col, joints, "MULTIPLY")
    return finish(m, col, roughness, fine.outputs["Fac"], 0.2, 0.8)


def epoxy():
    m = Mat("floor")
    fine = m.noise(60.0, detail=4)
    col = m.ramp(fine.outputs["Fac"], [(0.3, (0.16, 0.17, 0.18)), (0.7, (0.19, 0.2, 0.21))]).outputs["Color"]
    # A yellow safety line round the walls.
    sep = m.node("ShaderNodeSeparateXYZ")
    m.link(m.coord.outputs["Object"], sep.inputs["Vector"])
    edge = None
    for axis, half in (("X", ROOM_W / 2), ("Y", ROOM_D / 2)):
        a = m.node("ShaderNodeMath", operation="ABSOLUTE")
        m.link(sep.outputs[axis], a.inputs[0])
        d = m.node("ShaderNodeMath", operation="SUBTRACT")
        d.inputs[0].default_value = half
        m.link(a.outputs[0], d.inputs[1])
        edge = d if edge is None else _min(m, edge, d)
    band = m.ramp(edge.outputs[0], [(0.12, (1, 1, 1)), (0.121, (0, 0, 0)), (0.2, (0, 0, 0)), (0.201, (1, 1, 1))]).outputs["Color"]
    inv = m.node("ShaderNodeInvert")
    m.link(band, inv.inputs["Color"])
    col = m.mix(inv.outputs["Color"], col, (0.55, 0.42, 0.05))
    return finish(m, col, 0.32, fine.outputs["Fac"], 0.03, 0.4)


def _min(m: Mat, a, b):
    n = m.node("ShaderNodeMath", operation="MINIMUM")
    m.link(a.outputs[0], n.inputs[0])
    m.link(b.outputs[0], n.inputs[1])
    return n


def tiled(width, height, color1, color2, grout, roughness, offset=0.0, grout_size=0.004):
    m = Mat("floor")
    fine = m.noise(25.0, detail=6)
    col, fac = tiles(m, width, height, color1, color2, grout, grout_size, offset)
    shade = m.ramp(fine.outputs["Fac"], [(0.3, (0.85, 0.85, 0.85)), (0.7, (1, 1, 1))]).outputs["Color"]
    col = m.mix(1.0, col, shade, "MULTIPLY")
    return finish(m, col, roughness, fac, 0.08)


def boards(color, width, length, roughness, rotate=True, grain=3.0, alt=0.85):
    m = Mat("floor")
    col, fac = tiles(m, length, width, color, tuple(c * alt for c in color), tuple(c * 0.35 for c in color), 0.003, 0.5, rotate)
    wave = m.node("ShaderNodeTexWave", wave_type="BANDS", bands_direction="Y" if rotate else "X")
    wave.inputs["Scale"].default_value = grain
    wave.inputs["Distortion"].default_value = 8.0
    wave.inputs["Detail"].default_value = 4.0
    m.link(m.coord.outputs["Object"], wave.inputs["Vector"])
    grain_col = m.ramp(wave.outputs["Fac"], [(0.2, (0.78, 0.78, 0.78)), (0.8, (1, 1, 1))]).outputs["Color"]
    col = m.mix(1.0, col, grain_col, "MULTIPLY")
    return finish(m, col, roughness, fac, 0.1)


def terrazzo():
    m = Mat("floor")
    vor = m.node("ShaderNodeTexVoronoi")
    vor.inputs["Scale"].default_value = 70.0
    m.link(m.coord.outputs["Object"], vor.inputs["Vector"])
    chips = m.ramp(vor.outputs["Distance"], [(0.08, (1, 1, 1)), (0.12, (0, 0, 0))]).outputs["Color"]
    chip_col = m.ramp(m.noise(40.0).outputs["Fac"], [(0.35, (0.12, 0.1, 0.09)), (0.5, (0.45, 0.3, 0.22)), (0.65, (0.5, 0.5, 0.48))]).outputs["Color"]
    col = m.mix(chips, (0.62, 0.58, 0.52), chip_col)
    joints, fac = tiles(m, 1.0, 1.0, (1, 1, 1), (1, 1, 1), (0.6, 0.55, 0.5), 0.003)
    col = m.mix(1.0, col, joints, "MULTIPLY")
    return finish(m, col, 0.35, fac, 0.05, 0.4)


def marble():
    m = Mat("floor")
    n = m.noise(1.5, detail=8, roughness=0.7)
    wave = m.node("ShaderNodeTexWave", wave_type="BANDS", bands_direction="DIAGONAL")
    wave.inputs["Scale"].default_value = 0.35
    wave.inputs["Distortion"].default_value = 14.0
    wave.inputs["Detail"].default_value = 8.0
    m.link(m.coord.outputs["Object"], wave.inputs["Vector"])
    veins = m.ramp(wave.outputs["Fac"], [(0.0, (0.8, 0.79, 0.78)), (0.025, (1, 1, 1))]).outputs["Color"]
    # The veins fade in and out, as in real stone.
    fade = m.ramp(m.noise(0.6, detail=3).outputs["Fac"], [(0.4, (0, 0, 0)), (0.65, (1, 1, 1))]).outputs["Color"]
    veins = m.mix(fade, veins, (1.0, 1.0, 1.0))
    base = m.ramp(n.outputs["Fac"], [(0.3, (0.74, 0.73, 0.71)), (0.7, (0.86, 0.85, 0.83))]).outputs["Color"]
    col = m.mix(1.0, base, veins, "MULTIPLY")
    joints, fac = tiles(m, 1.2, 1.2, (1, 1, 1), (0.96, 0.96, 0.95), (0.4, 0.4, 0.4), 0.002)
    col = m.mix(1.0, col, joints, "MULTIPLY")
    return finish(m, col, 0.3, fac, 0.03, 0.35)


def floor_material(level: int):
    return [
        lambda: concrete(True),
        lambda: concrete(False),
        lambda: concrete(False, (0.14, 0.14, 0.14), (0.2, 0.2, 0.19), 0.45, False),
        epoxy,
        lambda: tiled(0.3, 0.3, (0.32, 0.12, 0.07), (0.28, 0.1, 0.06), (0.1, 0.09, 0.08), 0.55),
        lambda: tiled(0.6, 0.6, (0.42, 0.41, 0.39), (0.4, 0.39, 0.37), (0.2, 0.2, 0.19), 0.38, grout_size=0.002),
        lambda: boards((0.48, 0.36, 0.24), 0.2, 1.3, 0.45, grain=1.5, alt=0.92),
        lambda: boards((0.5, 0.31, 0.15), 0.18, 2.4, 0.6),
        lambda: boards((0.3, 0.19, 0.11), 0.08, 0.4, 0.45, rotate=False, grain=6.0, alt=0.8),
        terrazzo,
        marble,
    ][level]()


def build_floor(coll, level: int):
    box("floor", (ROOM_W, ROOM_D, 0.02), (ROOM_W / 2, ROOM_D / 2, -0.01), floor_material(level), coll)
    if level == 0:
        # Scattered paper, as in the garage the player starts in.
        rnd = random.Random(7)
        paper = plain("paper", (0.26, 0.25, 0.22), 0.9, variation=0.2)
        for _ in range(8):
            box("scrap", (rnd.uniform(0.1, 0.25), rnd.uniform(0.1, 0.2), 0.005),
                (rnd.uniform(0.9, 5.0), rnd.uniform(0.6, 5.2), 0.004), paper, coll, rotation=(0, 0, rnd.random() * 3))


# --- Walls ----------------------------------------------------------------------------------------

def wall_mapped(m: Mat):
    """Brick and noise coordinates for a wall standing in the XZ plane."""
    mapping = m.node("ShaderNodeMapping")
    m.link(m.coord.outputs["Object"], mapping.inputs["Vector"])
    ra._input(mapping, "Rotation").default_value = (math.pi / 2, 0, 0)
    return mapping.outputs["Vector"]


def plaster(name, color, roughness=0.88, grime=0.5, damp=False):
    m = Mat(name)
    fine = m.noise(35.0, detail=8)
    big = m.noise(1.5, detail=4)
    lo = tuple(c * 0.9 for c in color)
    col = m.ramp(big.outputs["Fac"], [(0.35, lo), (0.65, color)]).outputs["Color"]
    if damp:
        col = m.mix(0.5, col, m.ramp(fine.outputs["Fac"], [(0.3, (0.7, 0.7, 0.7)), (0.7, (1, 1, 1))]).outputs["Color"], "MULTIPLY")
    col = m.grime(col, grime, 0.3)
    return m.done(col, roughness, 0.0, fine.outputs["Fac"], 0.12)


def wall_bricks(name, width, height, color1, color2, mortar, mortar_size=0.01, roughness=0.85, offset=0.5):
    m = Mat(name)
    brick = m.node("ShaderNodeTexBrick", offset=offset)
    brick.inputs["Scale"].default_value = 1.0
    brick.inputs["Mortar Size"].default_value = mortar_size
    brick.inputs["Brick Width"].default_value = width
    brick.inputs["Row Height"].default_value = height
    brick.inputs["Color1"].default_value = (*color1, 1)
    brick.inputs["Color2"].default_value = (*color2, 1)
    brick.inputs["Mortar"].default_value = (*mortar, 1)
    m.link(wall_mapped(m), brick.inputs["Vector"])
    fine = m.noise(25.0)
    col = m.mix(0.35, brick.outputs["Color"], m.ramp(fine.outputs["Fac"], [(0.3, (0.6, 0.6, 0.6)), (0.7, (1, 1, 1))]).outputs["Color"], "MULTIPLY")
    col = m.grime(col, 0.6, 0.3)
    return m.done(col, roughness, 0.0, brick.outputs["Fac"], 0.3)


def wall_boards(name, color, width, roughness=0.5):
    m = Mat(name)
    brick = m.node("ShaderNodeTexBrick", offset=0.0)
    brick.inputs["Scale"].default_value = 1.0
    brick.inputs["Mortar Size"].default_value = 0.004
    brick.inputs["Brick Width"].default_value = width
    brick.inputs["Row Height"].default_value = 3.0
    brick.inputs["Color1"].default_value = (*color, 1)
    brick.inputs["Color2"].default_value = (*(c * 0.86 for c in color), 1)
    brick.inputs["Mortar"].default_value = (*(c * 0.3 for c in color), 1)
    m.link(wall_mapped(m), brick.inputs["Vector"])
    wave = m.node("ShaderNodeTexWave", wave_type="BANDS", bands_direction="X")
    wave.inputs["Scale"].default_value = 4.0
    wave.inputs["Distortion"].default_value = 7.0
    m.link(wall_mapped(m), wave.inputs["Vector"])
    col = m.mix(1.0, brick.outputs["Color"], m.ramp(wave.outputs["Fac"], [(0.2, (0.8, 0.8, 0.8)), (0.8, (1, 1, 1))]).outputs["Color"], "MULTIPLY")
    col = m.grime(col, 0.5, 0.3)
    return m.done(col, roughness, 0.0, brick.outputs["Fac"], 0.2)


def skyline_image(path: Path, w=2400, h=840):
    """A city at dusk behind the windows: sky, three rows of towers with lit windows."""
    rnd = random.Random(11)
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        t = y / h
        top, mid, low = (12, 18, 46), (58, 50, 92), (214, 120, 70)
        if t < 0.55:
            c = tuple(int(top[i] + (mid[i] - top[i]) * t / 0.55) for i in range(3))
        else:
            c = tuple(int(mid[i] + (low[i] - mid[i]) * (t - 0.55) / 0.45) for i in range(3))
        for x in range(w):
            px[x, y] = c
    draw = ImageDraw.Draw(img)
    for row, (shade, lo, hi, lit) in enumerate([((48, 46, 70), 0.3, 0.6, 0.1), ((30, 30, 46), 0.2, 0.5, 0.16), ((16, 16, 24), 0.1, 0.45, 0.22)]):
        x = rnd.randint(-60, 0)
        while x < w:
            bw = rnd.randint(70, 190) - row * 10
            top = int(h * rnd.uniform(lo, hi))
            draw.rectangle([x, top, x + bw, h], fill=shade)
            if rnd.random() < 0.25:
                draw.rectangle([x + bw // 2 - 3, top - rnd.randint(20, 60), x + bw // 2 + 3, top], fill=shade)
            step_x, step_y = 11 - row * 2, 15 - row * 2
            for wy in range(top + 10, h - 6, step_y):
                for wx in range(x + 8, x + bw - 8, step_x):
                    if rnd.random() < lit:
                        warm = rnd.choice([(255, 214, 140), (255, 236, 190), (180, 210, 255)])
                        draw.rectangle([wx, wy, wx + step_x // 2, wy + step_y // 2], fill=warm)
            x += bw + rnd.randint(4, 30)
    img = img.filter(ImageFilter.GaussianBlur(1.2))
    img.save(path)


def city_glass(path: Path):
    """A window pane: the city behind it as light, a faint reflection on top. Mapped in world space,
    so the view runs on across every pane of the back wall."""
    m = Mat("city")
    nt = m.nt
    geo = m.node("ShaderNodeNewGeometry")
    sep = m.node("ShaderNodeSeparateXYZ")
    m.link(geo.outputs["Position"], sep.inputs["Vector"])
    u = m.node("ShaderNodeMath", operation="MULTIPLY_ADD")
    m.link(sep.outputs["X"], u.inputs[0])
    u.inputs[1].default_value = 1 / (ROOM_W + 0.6)
    u.inputs[2].default_value = 0.3 / (ROOM_W + 0.6)
    v = m.node("ShaderNodeMath", operation="MULTIPLY")
    m.link(sep.outputs["Z"], v.inputs[0])
    v.inputs[1].default_value = 1 / WALL_H
    uv = m.node("ShaderNodeCombineXYZ")
    m.link(u.outputs[0], uv.inputs["X"])
    m.link(v.outputs[0], uv.inputs["Y"])
    tex = m.node("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(str(path))
    tex.extension = "EXTEND"
    m.link(uv.outputs["Vector"], tex.inputs["Vector"])
    emit = m.node("ShaderNodeEmission", Strength=1.1)
    m.link(tex.outputs["Color"], emit.inputs["Color"])
    gloss = m.node("ShaderNodeBsdfGlossy")
    gloss.inputs["Roughness"].default_value = 0.08
    gloss.inputs["Color"].default_value = (0.6, 0.65, 0.7, 1)
    fres = m.node("ShaderNodeFresnel")
    fres.inputs["IOR"].default_value = 1.5
    mix = m.node("ShaderNodeMixShader")
    m.link(fres.outputs[0], mix.inputs[0])
    m.link(emit.outputs[0], mix.inputs[1])
    m.link(gloss.outputs[0], mix.inputs[2])
    out = nt.nodes["Material Output"]
    m.link(mix.outputs[0], out.inputs["Surface"])
    return m.m


def wall_block(name, x0, x1, y0, y1, h0, h1, mat, coll, cap_mat):
    """Wall block with height h0 at y0 and h1 at y1, and a cap on top (as render_art.build_room)."""
    v = [(x0, y0, 0), (x1, y0, 0), (x1, y1, 0), (x0, y1, 0), (x0, y0, h0), (x1, y0, h0), (x1, y1, h1), (x0, y1, h1)]
    f = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
    mesh_from(name, v, f, mat, coll)
    mesh_from(name + "_cap", [(x0 - 0.01, y0 - 0.01, h0), (x1 + 0.01, y0 - 0.01, h0), (x1 + 0.01, y1 + 0.01, h1),
                              (x0 - 0.01, y1 + 0.01, h1), (x0 - 0.01, y0 - 0.01, h0 + 0.04), (x1 + 0.01, y0 - 0.01, h0 + 0.04),
                              (x1 + 0.01, y1 + 0.01, h1 + 0.04), (x0 - 0.01, y1 + 0.01, h1 + 0.04)], f, cap_mat, coll)


def back_panel(name, x0, x1, z0, z1, mat, coll, depth=0.03):
    """A layer over the inside of the back wall between x0..x1 and z0..z1, leaving the door's opening alone."""
    door0, door1 = DOOR_X - DOOR_W / 2 - 0.15, DOOR_X + DOOR_W / 2 + 0.15
    spans = [(x0, x1)]
    if z0 < DOOR_H + 0.2:
        spans = [(a, b) for a, b in ((x0, min(x1, door0)), (max(x0, door1), x1)) if b - a > 0.01]
    for i, (a, b) in enumerate(spans):
        box(f"{name}{i}", (b - a, depth, z1 - z0), ((a + b) / 2, ROOM_D - depth / 2, (z0 + z1) / 2), mat, coll)


def build_walls(coll, level: int, city: Path, cable=True):
    """The walls of one level, everything hanging on them and the door."""
    frame_m = rusty_metal("frame", (0.12, 0.12, 0.13), 0.5 if level < 2 else 0.0)
    steel = rusty_metal("steel_wall", (0.18, 0.18, 0.19), 0.3 if level < 2 else 0.05)
    black = plain("black_metal", (0.02, 0.02, 0.022), 0.35, 0.8, variation=0.05, grime=0.2)
    white = (0.62, 0.61, 0.58)
    wall_m = {
        0: lambda: ra.block_wall(),
        1: lambda: plaster("plaster", (0.2, 0.195, 0.185), damp=True),
        2: lambda: plaster("white", white),
        3: lambda: plaster("white", white),
        4: lambda: plaster("white", white),
        5: lambda: wall_bricks("clinker", 0.25, 0.065, (0.3, 0.09, 0.04), (0.24, 0.07, 0.035), (0.33, 0.3, 0.27), 0.006),
        6: lambda: wall_boards("oak", (0.3, 0.17, 0.08), 0.18),
        7: lambda: plaster("light", (0.5, 0.48, 0.44)),
        8: lambda: wall_bricks("concrete", 1.2, 0.6, (0.3, 0.3, 0.29), (0.28, 0.28, 0.27), (0.18, 0.18, 0.18), 0.003, 0.7, 0.0),
        9: lambda: wall_bricks("concrete", 1.2, 0.6, (0.3, 0.3, 0.29), (0.28, 0.28, 0.27), (0.18, 0.18, 0.18), 0.003, 0.7, 0.0),
        10: lambda: plain("office_frame", (0.05, 0.05, 0.055), 0.4, 0.6, variation=0.05, grime=0.2),
    }[level]()
    cap_m = plain("wall_cap", (0.05, 0.05, 0.055), 0.9, variation=0.3) if level < 5 else black

    wall_block("wall_back", -WALL_T, ROOM_W + WALL_T, ROOM_D, ROOM_D + WALL_T, WALL_H, WALL_H, wall_m, coll, cap_m)
    wall_block("wall_left", -WALL_T, 0, -WALL_T, ROOM_D, FRONT_H, WALL_H, wall_m, coll, cap_m)
    wall_block("wall_right", ROOM_W, ROOM_W + WALL_T, -WALL_T, ROOM_D, FRONT_H, WALL_H, wall_m, coll, cap_m)
    wall_block("wall_front", 0, ROOM_W, -WALL_T, 0, FRONT_H, FRONT_H, wall_m, coll, cap_m)

    # Wainscot below, a different finish above.
    if level == 3:
        back_panel("wainscot", 0, ROOM_W, 0, 1.1, wall_boards("pine", (0.42, 0.25, 0.11), 0.12), coll)
        back_panel("wainscot_rail", 0, ROOM_W, 1.1, 1.14, ra.wood("rail", (0.25, 0.13, 0.05)), coll, 0.05)
    if level == 4:
        back_panel("tiles", 0, ROOM_W, 0, 1.3, wall_bricks("wall_tiles", 0.15, 0.15, (0.66, 0.67, 0.66), (0.63, 0.64, 0.63),
                                                           (0.32, 0.32, 0.31), 0.006, 0.3, 0.0), coll)
    if level == 9:
        back_panel("glass", 0, ROOM_W, 0.9, WALL_H, city_glass(city), coll, 0.02)

    # Skirting board along the back wall from the white walls on.
    if 2 <= level <= 8:
        back_panel("skirting", 0, ROOM_W, 0, 0.08, black if level >= 5 else plain("skirt", (0.5, 0.49, 0.46), 0.6), coll, 0.04)

    build_door(coll, level, frame_m, black, city)
    build_windows(coll, level, frame_m, black, city)

    # What hangs on the wall.
    if level <= 4:
        board = plain("pegboard", (0.12, 0.09, 0.06) if level < 2 else (0.3, 0.22, 0.12), 0.9)
        box("pegboard", (1.0, 0.03, 0.6), (5.25, ROOM_D - 0.02, 1.55), board, coll)
        rnd = random.Random(3)
        for i in range(5):
            box("tool", (0.04, 0.03, 0.25 + 0.1 * rnd.random()), (4.9 + i * 0.18, ROOM_D - 0.05, 1.55), steel, coll,
                rotation=(0, rnd.uniform(-0.2, 0.2), 0))
        fuse_m = plain("fuse", (0.3, 0.3, 0.27) if level < 2 else (0.55, 0.55, 0.52), 0.5, 0.3)
        box("fuse_box", (0.4, 0.15, 0.5), (4.3, ROOM_D - 0.08, 1.5), fuse_m, coll, bevel=0.02)
        box("fuse_sign", (0.12, 0.01, 0.1), (4.3, ROOM_D - 0.16, 1.62), plain("sign", (0.7, 0.5, 0.0), 0.5), coll)
    if level <= 2:
        pipe_m = rusty_metal("pipe", (0.2, 0.2, 0.21), 0.4) if level < 2 else plain("pipe_white", (0.6, 0.6, 0.58), 0.4)
        rot_x = (0, math.pi / 2, 0)
        cylinder("pipe", 0.06, ROOM_W, (ROOM_W / 2, ROOM_D - 0.12, 2.5), pipe_m, coll, rotation=rot_x)
        cylinder("pipe2", 0.035, ROOM_W, (ROOM_W / 2, ROOM_D - 0.1, 2.32), pipe_m, coll, rotation=rot_x)
        cylinder("pipe_down", 0.06, 2.5, (ROOM_W - 0.15, ROOM_D - 0.12, 1.25), pipe_m, coll)
        for x in (1.0, 3.5, 6.0):
            box("pipe_clamp", (0.06, 0.16, 0.16), (x, ROOM_D - 0.1, 2.5), steel, coll, bevel=0.01)
    if level == 0 and cable:
        # The cable from the fuse box over the floor.
        cable = plain("cable", (0.02, 0.02, 0.02), 0.5)
        pts = [(4.5, ROOM_D - 0.05, 1.2), (4.3, ROOM_D - 0.3, 0.02), (3.8, 4.8, 0.02), (3.4, 4.6, 0.02)]
        for a, b in zip(pts, pts[1:]):
            va, vb = Vector(a), Vector(b)
            c = cylinder("cable", 0.012, (vb - va).length, (va + vb) / 2, cable, coll, verts=8)
            c.rotation_mode = "QUATERNION"
            c.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(vb - va)
    if 5 <= level <= 9:
        # Wall lamps.
        lamp = ra.emission("lamp_glow", (1.0, 0.85, 0.6), 6.0)
        for x in (4.4, 7.6):
            box("sconce", (0.18, 0.08, 0.25), (x, ROOM_D - 0.05, 1.9), black, coll, bevel=0.01)
            box("sconce_glow", (0.12, 0.02, 0.06), (x, ROOM_D - 0.1, 1.98), lamp, coll)
    if level >= 7:
        # The company's name on the wall.
        sign = ra.emission("sign_glow", (0.95, 0.75, 0.3), 3.0)
        box("sign_plate", (1.1, 0.03, 0.26), (5.9, ROOM_D - 0.02, 2.35 if level < 10 else 2.5), black, coll, bevel=0.005)
        for i in range(5):
            box("sign_letter", (0.12, 0.01, 0.14), (5.5 + i * 0.2, ROOM_D - 0.04, 2.35 if level < 10 else 2.5), sign, coll)


def build_door(coll, level, frame_m, black, city: Path):
    x, w, h = DOOR_X, DOOR_W, DOOR_H
    if level >= 9:
        # A glass door in a black frame.
        box("door_glass", (w, 0.03, h), (x, ROOM_D - 0.02, h / 2), city_glass(city), coll)
        for dx in (-w / 2, 0, w / 2):
            box("door_post", (0.06, 0.06, h), (x + dx, ROOM_D - 0.04, h / 2), black, coll)
        box("door_head", (w + 0.06, 0.06, 0.08), (x, ROOM_D - 0.04, h), black, coll)
        for dx in (-0.12, 0.12):
            box("door_pull", (0.03, 0.05, 0.9), (x + dx, ROOM_D - 0.09, 1.05), plain("steel_pull", (0.5, 0.5, 0.5), 0.2, 1.0), coll)
        return
    if level <= 3:
        door_m = ra.corrugated("door", (0.2, 0.22, 0.24) if level < 2 else (0.5, 0.5, 0.48), rust=0.3 if level < 2 else 0.02)
        box("door", (w, 0.06, h), (x, ROOM_D - 0.02, h / 2), door_m, coll)
        box("door_box", (w + 0.3, 0.35, 0.35), (x, ROOM_D - 0.15, h + 0.15), frame_m, coll, bevel=0.02)
        for dx in (-w / 2 - 0.05, w / 2 + 0.05):
            box("door_rail", (0.12, 0.12, h), (x + dx, ROOM_D - 0.06, h / 2), frame_m, coll, bevel=0.01)
        box("door_handle", (0.3, 0.06, 0.05), (x, ROOM_D - 0.07, 0.25), frame_m, coll, bevel=0.01)
        return
    # A sectional door: wide panels, a row of small windows.
    color = {4: (0.6, 0.6, 0.58), 5: (0.55, 0.55, 0.53), 6: (0.08, 0.08, 0.085), 7: (0.6, 0.6, 0.58), 8: (0.08, 0.08, 0.085)}[level]
    panel_m = plain("sectional", color, 0.45, 0.4, variation=0.04, grime=0.3)
    sections = 5
    for i in range(sections):
        z = h * (i + 0.5) / sections
        box("door_section", (w, 0.06, h / sections - 0.02), (x, ROOM_D - 0.02, z), panel_m, coll, bevel=0.008)
    glow = city_glass(city)
    for i in range(4):
        box("door_window", (0.45, 0.02, 0.2), (x - 0.9 + i * 0.6, ROOM_D - 0.06, h * 3.5 / sections), glow, coll)
    for dx in (-w / 2 - 0.05, w / 2 + 0.05):
        box("door_rail", (0.1, 0.1, h), (x + dx, ROOM_D - 0.05, h / 2), black, coll, bevel=0.01)
    box("door_head", (w + 0.3, 0.1, 0.12), (x, ROOM_D - 0.05, h + 0.06), black, coll, bevel=0.01)


def build_windows(coll, level, frame_m, black, city: Path):
    glass = city_glass(city)
    if level <= 4:
        # The small window of the old garage, cleaner as the walls get better.
        box("window_frame", (1.1, 0.12, 0.7), (6.3, ROOM_D - 0.02, 1.85), frame_m if level < 2 else black, coll, bevel=0.02)
        box("window_glass", (0.95, 0.05, 0.55), (6.3, ROOM_D - 0.09, 1.85), glass if level >= 2 else _dirty_glass(), coll)
        box("window_bar", (0.04, 0.06, 0.55), (6.3, ROOM_D - 0.11, 1.85), frame_m, coll)
        box("window_bar2", (0.95, 0.06, 0.04), (6.3, ROOM_D - 0.11, 1.85), frame_m, coll)
    elif level <= 6:
        box("window_frame", (1.7, 0.1, 1.0), (6.3, ROOM_D - 0.02, 1.75), black, coll, bevel=0.01)
        box("window_glass", (1.56, 0.04, 0.86), (6.3, ROOM_D - 0.07, 1.75), glass, coll)
        box("window_bar", (0.04, 0.05, 0.86), (6.3, ROOM_D - 0.1, 1.75), black, coll)
        box("window_sill", (1.8, 0.16, 0.04), (6.3, ROOM_D - 0.08, 1.23), plain("sill", (0.55, 0.54, 0.5), 0.4), coll)
    elif level <= 8:
        for cx in (4.75, 6.95):
            box("window_frame", (1.9, 0.1, 1.6), (cx, ROOM_D - 0.02, 1.5), black, coll, bevel=0.01)
            box("window_glass", (1.78, 0.04, 1.48), (cx, ROOM_D - 0.07, 1.5), glass, coll)
            box("window_bar", (0.04, 0.05, 1.48), (cx, ROOM_D - 0.1, 1.5), black, coll)
    elif level == 9:
        for i in range(9):
            box("mullion", (0.05, 0.06, WALL_H - 0.9), (i * ROOM_W / 8, ROOM_D - 0.04, 0.9 + (WALL_H - 0.9) / 2), black, coll)
        box("transom", (ROOM_W, 0.06, 0.05), (ROOM_W / 2, ROOM_D - 0.04, 0.92), black, coll)
    else:
        # The office: glass from floor to ceiling, black mullions.
        back_panel("glass", 0, ROOM_W, 0, WALL_H, glass, coll, 0.02)
        for i in range(9):
            box("mullion", (0.05, 0.06, WALL_H), (i * ROOM_W / 8, ROOM_D - 0.04, WALL_H / 2), black, coll)
        box("transom", (ROOM_W, 0.06, 0.05), (ROOM_W / 2, ROOM_D - 0.04, 2.45), black, coll)
        box("sill", (ROOM_W, 0.08, 0.06), (ROOM_W / 2, ROOM_D - 0.05, 0.03), black, coll)


def _dirty_glass():
    glass = Mat("window_glass")
    n = glass.noise(6.0)
    col = glass.ramp(n.outputs["Fac"], [(0.3, (0.05, 0.09, 0.12)), (0.7, (0.18, 0.24, 0.28))]).outputs["Color"]
    em = glass.node("ShaderNodeEmission", Strength=1.2)
    glass.link(col, em.inputs["Color"])
    glass.link(em.outputs[0], glass.nt.nodes["Material Output"].inputs["Surface"])
    return glass.m


# --- Rendering ------------------------------------------------------------------------------------

SAMPLES = 128


def scene_for_room():
    scene = ra.reset()
    scene.cycles.samples = SAMPLES
    ra.set_world((0.012, 0.014, 0.018), 1.0)
    ra.garage_camera(scene)
    lights = ra.garage_lights()
    return scene, lights


def render_floor(level: int, city: Path):
    scene, _ = scene_for_room()
    room = ra.collection("room")
    ground_m = plain("asphalt", (0.035, 0.035, 0.04), 0.95, variation=0.4, scale=20, bump=0.4)
    box("ground", (40, 40, 0.1), (ROOM_W / 2, ROOM_D / 2, -0.06), ground_m, room)
    build_floor(room, level)
    # The walls of the old garage cast their shadows and light, but the walls layer draws them.
    walls = ra.collection("walls")
    build_walls(walls, 0, city, cable=False)
    for o in walls.objects:
        o.visible_camera = False
    scene.render.film_transparent = False
    ra.render(TMP / f"floor_{level}.png")
    Image.open(TMP / f"floor_{level}.png").convert("RGB").save(OUT / f"floor_{level}.jpg", quality=90)
    print("floor", level, FLOORS[level], flush=True)


def render_walls(level: int, city: Path):
    scene, _ = scene_for_room()
    room = ra.collection("room")
    floor = box("floor", (ROOM_W, ROOM_D, 0.02), (ROOM_W / 2, ROOM_D / 2, -0.01), floor_material(0), room)
    # Only lights the walls; the floor's own layer shows it.
    floor.is_holdout = True
    build_walls(room, level, city)
    scene.render.film_transparent = True
    ra.render(TMP / f"walls_{level}.png")
    img = Image.open(TMP / f"walls_{level}.png").convert("RGBA")
    img.save(OUT / f"walls_{level}.png", optimize=True)
    print("walls", level, WALLS[level], flush=True)


def render_vignette():
    """The darkening at the screen's edges that render_art.vignette bakes into a picture, as its own layer."""
    clear = Image.new("RGBA", (SCREEN_W, SCREEN_H), (0, 0, 0, 0))
    dark = ra.vignette(clear)
    dark.save(OUT / "vignette.png", optimize=True)
    print("vignette", flush=True)


def main(args):
    global SAMPLES
    if "quick" in args:
        SAMPLES = 24
    OUT.mkdir(parents=True, exist_ok=True)
    TMP.mkdir(parents=True, exist_ok=True)
    city = TMP / "skyline.png"
    skyline_image(city)
    floors = range(len(FLOORS)) if "floors" in args else [int(a[6:]) for a in args if a.startswith("floor_")]
    walls = range(len(WALLS)) if "walls" in args else [int(a[6:]) for a in args if a.startswith("walls_")]
    for level in floors:
        render_floor(level, city)
    for level in walls:
        render_walls(level, city)
    if "vignette" in args:
        render_vignette()


if __name__ == "__main__":
    main(sys.argv[1:] or ["floors", "walls", "vignette"])
