#!/usr/bin/env python3
"""Renders the art of plots (the land a player owns) with Blender into client/art/plot/, and the
icons of tools and raw materials into client/art/icons/.

Same studio as tools/render_art.py (it reuses its helpers), same 45° view from above, but at a
smaller scale: a tile of a plot is 2 × 2 m on screen, 64 × 45 px, at 32 px per metre.

    .venv-art/bin/python tools/render_plot_art.py [floors] [nature] [station] [rail] [icons]

Writes client/art/plot/layout.json with each sprite's anchor: the pixel that stands on the
centre of the tile (or, for the station, the middle of its south edge).
"""
import json
import math
import random
import sys
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import render_art as ra  # noqa: E402  (imports bpy first)
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402
from PIL import Image, ImageChops, ImageFilter  # noqa: E402

OUT = ra.ART / "plot"
ICONS = ra.ART / "icons"
TMP = ra.TMP / "plot"
PPM = 32
PITCH = math.radians(45)
TILE_M = 2.0

random.seed(11)


# --- Studio -----------------------------------------------------------------------------------

def outdoor_scene(width_px: int, height_px: int, target: Vector, samples=64, pitch=PITCH):
    """Dusk under a heavy sky: a warm sun from the front left and a cold blue fill."""
    scene = ra.reset()
    scene.cycles.samples = samples
    ra.set_world((0.035, 0.045, 0.065), 1.0)
    ra.camera(scene, target, width_px / PPM, (width_px, height_px), pitch=pitch)
    ra.light("SUN", (0, 0, 10), 2.6, (1.0, 0.82, 0.62), size=0.06,
             rotation=(math.radians(36), 0, math.radians(-40)))
    ra.light("SUN", (0, 0, 10), 0.35, (0.55, 0.65, 0.9), size=0.6,
             rotation=(math.radians(20), 0, math.radians(30)))
    return scene


def anchor(width_px: int, height_px: int, target: Vector, point=Vector((0, 0, 0))) -> tuple[int, int]:
    """Pixel of a world point in a render made by outdoor_scene (orthographic, looking north)."""
    rel = point - target
    up = Vector((0, math.sin(PITCH), math.cos(PITCH)))
    return round(width_px / 2 + rel.x * PPM), round(height_px / 2 - rel.dot(up) * PPM)


def shadow_catcher(size=40.0):
    plane = ra.box("ground", (size, size, 0.01), (0, 0, -0.005))
    plane.is_shadow_catcher = True
    return plane


def render_sprite(name: str, width: int, height: int, target: Vector, build) -> dict:
    """Renders an object and, separately, the shadow it throws on the ground."""
    outdoor_scene(width, height, target)
    objs = build()
    catcher = shadow_catcher()
    catcher.hide_render = True
    ra.render(TMP / f"{name}.png")
    catcher.hide_render = False
    for o in objs:
        o.visible_camera = False
    ra.render(TMP / f"{name}_shadow.png")
    OUT.mkdir(parents=True, exist_ok=True)
    Image.open(TMP / f"{name}.png").save(OUT / f"{name}.png", optimize=True)
    shadow = Image.open(TMP / f"{name}_shadow.png").convert("RGBA")
    # Keep only the darkening, as a soft black shape.
    alpha = shadow.getchannel("A").point(lambda v: min(255, int(v * 0.85)))
    flat = Image.new("RGBA", shadow.size, (2, 3, 6, 0))
    flat.putalpha(alpha.filter(ImageFilter.GaussianBlur(1.2)))
    flat.save(OUT / f"{name}_shadow.png", optimize=True)
    ax, ay = anchor(width, height, target)
    print("sprite", name)
    return {"anchorX": ax, "anchorY": ay}


def meshes():
    return [o for o in bpy.context.scene.objects if o.type == "MESH" and o.name != "ground"]


# --- Materials ----------------------------------------------------------------------------------

def foliage(name, color, variation=0.35):
    m = ra.Mat(name)
    n = m.noise(9.0, detail=8)
    big = m.noise(1.5)
    lo = tuple(c * (1 - variation) for c in color)
    hi = tuple(min(1, c * (1 + variation)) for c in color)
    col = m.ramp(n.outputs["Fac"], [(0.35, lo), (0.65, hi)]).outputs["Color"]
    col = m.mix(m.ramp(big.outputs["Fac"], [(0.3, (0.8, 0.8, 0.8)), (0.7, (1.1, 1.1, 1.0))]).outputs["Color"], col, col, "MULTIPLY")
    col = m.grime(col, 0.9, 0.5)
    return m.done(col, 0.85, 0.0, n.outputs["Fac"], 0.6)


def bark():
    return ra.plain("bark", (0.07, 0.045, 0.03), 0.9, variation=0.4, scale=30, bump=0.5)


def rock(name="rock", color=(0.16, 0.155, 0.15)):
    m = ra.Mat(name)
    n = m.noise(4.0, detail=10)
    fine = m.noise(35.0)
    col = m.ramp(n.outputs["Fac"], [(0.3, tuple(c * 0.6 for c in color)), (0.7, color)]).outputs["Color"]
    lichen = m.ramp(m.noise(2.5).outputs["Fac"], [(0.62, (0, 0, 0)), (0.7, (1, 1, 1))]).outputs["Color"]
    col = m.mix(lichen, col, (0.1, 0.11, 0.06))
    col = m.grime(col, 0.9, 0.3)
    return m.done(col, 0.85, 0.0, fine.outputs["Fac"], 0.5)


def sand_mat():
    m = ra.Mat("sand")
    wave = m.node("ShaderNodeTexWave", wave_type="BANDS", bands_direction="Y")
    wave.inputs["Scale"].default_value = 1.2
    wave.inputs["Distortion"].default_value = 3.0
    wave.inputs["Detail"].default_value = 3.0
    m.link(m.coord.outputs["Object"], wave.inputs["Vector"])
    fine = m.noise(60.0)
    col = m.ramp(fine.outputs["Fac"], [(0.3, (0.27, 0.19, 0.09)), (0.7, (0.38, 0.28, 0.14))]).outputs["Color"]
    return m.done(col, 0.95, 0.0, wave.outputs["Fac"], 0.35)


# --- Floors -------------------------------------------------------------------------------------

def floor_material(kind):
    m = ra.Mat(kind)
    if kind == "concrete":
        return ra.concrete_floor()
    if kind == "sand":
        return sand_mat()
    if kind == "gravel":
        vor = m.node("ShaderNodeTexVoronoi")
        vor.inputs["Scale"].default_value = 9.0
        m.link(m.coord.outputs["Object"], vor.inputs["Vector"])
        fine = m.noise(40.0)
        col = m.ramp(vor.outputs["Distance"], [(0.0, (0.15, 0.145, 0.14)), (0.5, (0.07, 0.068, 0.065))]).outputs["Color"]
        col = m.mix(0.5, col, m.ramp(fine.outputs["Fac"], [(0.3, (0.6, 0.6, 0.6)), (0.7, (1, 1, 1))]).outputs["Color"], "MULTIPLY")
        return m.done(col, 0.9, 0.0, vor.outputs["Distance"], 0.8)
    colors = {
        "forest": [(0.0, (0.022, 0.03, 0.014)), (0.5, (0.045, 0.05, 0.022)), (1.0, (0.07, 0.05, 0.03))],
        "grass": [(0.0, (0.035, 0.065, 0.02)), (0.6, (0.07, 0.1, 0.035)), (1.0, (0.09, 0.09, 0.04))],
        "dry_grass": [(0.0, (0.09, 0.08, 0.035)), (0.6, (0.15, 0.13, 0.06)), (1.0, (0.1, 0.11, 0.05))],
        "tundra": [(0.0, (0.06, 0.07, 0.06)), (0.6, (0.1, 0.11, 0.09)), (1.0, (0.13, 0.12, 0.1))],
        "snow": [(0.0, (0.45, 0.5, 0.58)), (0.6, (0.62, 0.66, 0.72)), (1.0, (0.7, 0.73, 0.78))],
    }[kind]
    big = m.noise(0.7, detail=4)
    fine = m.noise(45.0 if kind != "snow" else 12.0, detail=8)
    col = m.ramp(big.outputs["Fac"], colors).outputs["Color"]
    col = m.mix(0.6, col, m.ramp(fine.outputs["Fac"], [(0.25, (0.5, 0.5, 0.5)), (0.75, (1.3, 1.3, 1.3))]).outputs["Color"], "MULTIPLY")
    return m.done(col, 0.95 if kind != "snow" else 0.6, 0.0, fine.outputs["Fac"], 0.6 if kind != "snow" else 0.15)


def seamless(img: Image.Image) -> Image.Image:
    """Blends the image with itself shifted by half, so its edges meet when tiled."""
    w, h = img.size
    shifted = ImageChops.offset(img, w // 2, h // 2)
    mask = Image.new("L", (w, h))
    px = mask.load()
    for y in range(h):
        for x in range(w):
            d = max(abs(x - w / 2) / (w / 2), abs(y - h / 2) / (h / 2))
            px[x, y] = int(255 * max(0.0, min(1.0, (1 - d) * 3)))
    return Image.composite(img, shifted, mask)


FLOORS = ["forest", "grass", "dry_grass", "sand", "gravel", "tundra", "snow", "concrete"]


def render_floors():
    """Square swatches of ground seen straight from above; the game squashes them to the 45° view."""
    for kind in FLOORS:
        scene = outdoor_scene(256, 256, Vector((0, 0, 0)), samples=48, pitch=math.radians(90))
        scene.render.film_transparent = False
        # Larger than the 8 m frame, so the rounded edges of the subdivided box stay out of view.
        ground = ra.box("ground", (24, 24, 0.02), (0, 0, -0.01), floor_material(kind))
        if kind in ("forest", "grass", "dry_grass", "tundra"):
            ra.displace(ground, 0.04, 0.15, 7)
        ra.render(TMP / f"floor_{kind}.png")
        OUT.mkdir(parents=True, exist_ok=True)
        seamless(Image.open(TMP / f"floor_{kind}.png").convert("RGB")).save(OUT / f"floor_{kind}.png", optimize=True)
        print("floor", kind)


# --- Nature ---------------------------------------------------------------------------------------

def conifer(height, width, color):
    ra.cylinder("trunk", 0.18, height * 0.35, (0, 0, height * 0.175), bark())
    leaves = foliage("needles", color)
    tiers = 4
    for i in range(tiers):
        t = i / tiers
        r = width * (1 - t * 0.7) / 2
        z = height * (0.2 + t * 0.68)
        cone = ra.cylinder("tier", r, height * 0.38, (0, 0, z + height * 0.15), leaves, radius2=0.02, verts=16)
        ra.displace(cone, 0.12, 0.4, 2)
    return meshes()


def broadleaf(height, width, color):
    ra.cylinder("trunk", 0.2, height * 0.5, (0, 0, height * 0.25), bark())
    leaves = foliage("leaves", color, 0.45)
    for _ in range(6):
        off = Vector((random.uniform(-0.5, 0.5), random.uniform(-0.5, 0.5), random.uniform(-0.3, 0.4))) * width * 0.4
        s = ra.sphere("crown", width * random.uniform(0.28, 0.36), Vector((0, 0, height * 0.68)) + off, leaves, segments=16)
        ra.displace(s, 0.25, 0.35, 2)
    return meshes()


def boulder(size, color=(0.16, 0.155, 0.15), seed=0):
    random.seed(seed)
    mat = rock(f"rock{seed}", color)
    main = ra.sphere("rock", size / 2, (0, 0, size * 0.25), mat, scale=(1, 0.85, 0.65), segments=12)
    ra.displace(main, size * 0.18, 0.5, 2)
    for _ in range(2):
        a = random.random() * math.tau
        s = ra.sphere("stone", size * 0.16, (math.cos(a) * size * 0.5, math.sin(a) * size * 0.45, size * 0.06), mat, segments=8)
        ra.displace(s, size * 0.05, 0.4, 1)
    return meshes()


def bush(size, color):
    leaves = foliage("bush", color, 0.4)
    for _ in range(4):
        off = Vector((random.uniform(-0.3, 0.3), random.uniform(-0.3, 0.3), 0)) * size
        s = ra.sphere("bush", size * 0.3, off + Vector((0, 0, size * 0.22)), leaves, scale=(1, 1, 0.8), segments=12)
        ra.displace(s, size * 0.1, 0.3, 1)
    return meshes()


def dune(size):
    d = ra.sphere("dune", size / 2, (0, 0, -size * 0.12), sand_mat(), scale=(1.2, 0.9, 0.45), segments=24)
    ra.displace(d, size * 0.08, 0.6, 2)
    return meshes()


NATURE = {
    # name: (canvas width, height, camera target height, builder)
    "tree_0": (256, 288, 2.6, lambda: conifer(6.0, 2.6, (0.045, 0.11, 0.05))),
    "tree_1": (256, 288, 2.4, lambda: conifer(5.2, 2.3, (0.055, 0.12, 0.06))),
    "tree_2": (256, 288, 2.8, lambda: conifer(6.6, 2.8, (0.04, 0.095, 0.045))),
    "tree_3": (256, 256, 2.2, lambda: broadleaf(4.8, 3.0, (0.07, 0.13, 0.04))),
    "tree_4": (256, 256, 2.0, lambda: broadleaf(4.2, 2.7, (0.11, 0.13, 0.04))),
    "rock_0": (160, 144, 0.7, lambda: boulder(2.4, (0.13, 0.125, 0.12), seed=1)),
    "rock_1": (160, 144, 0.6, lambda: boulder(2.0, (0.1, 0.095, 0.09), seed=2)),
    "rock_2": (160, 144, 0.8, lambda: boulder(2.8, (0.15, 0.14, 0.13), seed=3)),
    "bush_0": (112, 96, 0.4, lambda: bush(1.3, (0.06, 0.12, 0.04))),
    "bush_1": (112, 96, 0.4, lambda: bush(1.1, (0.12, 0.13, 0.05))),
    "dune_0": (160, 112, 0.3, lambda: dune(2.6)),
    "dune_1": (160, 112, 0.3, lambda: dune(2.2)),
}


def render_nature(layout: dict):
    for name, (w, h, tz, build) in NATURE.items():
        random.seed(zlib.crc32(name.encode()))
        layout[name] = render_sprite(name, w, h, Vector((0, 0, tz)), build)


# --- Railway --------------------------------------------------------------------------------------

def track(length):
    """A standard-gauge track along x: sleepers every 0.8 m on ballast, two steel rails."""
    ballast = ra.Mat("ballast")
    vor = ballast.node("ShaderNodeTexVoronoi")
    vor.inputs["Scale"].default_value = 18.0
    ballast.link(ballast.coord.outputs["Object"], vor.inputs["Vector"])
    col = ballast.ramp(vor.outputs["Distance"], [(0.0, (0.11, 0.1, 0.095)), (0.5, (0.04, 0.038, 0.035))]).outputs["Color"]
    ra.box("ballast", (length + 4, 2.6, 0.12), (0, 0, 0.06), ballast.done(col, 0.9, 0.0, vor.outputs["Distance"], 0.6))
    sleeper = ra.wood("sleeper", (0.08, 0.05, 0.03))
    n = int((length + 4) / 0.8)
    for i in range(n):
        ra.box("sleeper", (0.24, 2.3, 0.1), (-(length + 4) / 2 + 0.4 + i * 0.8, 0, 0.16), sleeper, bevel=0.01)
    steel = ra.rusty_metal("rail", (0.32, 0.3, 0.28), rust=0.5)
    for y in (-0.72, 0.72):
        ra.box("rail", (length + 4, 0.08, 0.14), (0, y, 0.28), steel)
        ra.box("rail_head", (length + 4, 0.1, 0.03), (0, y, 0.36), ra.plain("head", (0.5, 0.5, 0.52), 0.25, 1.0, grime=0.1))
    return meshes()


def render_rail(layout: dict):
    """A strip of track 8 m long that tiles left to right."""
    w, h = 256, 96
    outdoor_scene(w, h, Vector((0, 0, 0)))
    track(8)
    ra.render(TMP / "rail.png")
    Image.open(TMP / "rail.png").save(OUT / "rail.png", optimize=True)
    ax, ay = anchor(w, h, Vector((0, 0, 0)))
    layout["rail"] = {"anchorX": ax, "anchorY": ay, "lengthPx": w}
    print("sprite rail")


# --- Station --------------------------------------------------------------------------------------

def station():
    """A small brick station with a platform, lit windows and lamps, 24 × 12 m. Its south edge
    (the platform's) is y = 0; the track runs just south of it."""
    brick = ra.block_wall()
    roof = ra.corrugated("roof", (0.12, 0.05, 0.035), rust=0.4)
    concrete = ra.concrete_floor()
    window = ra.emission("window", (1.0, 0.62, 0.28), 6.0)
    lamp = ra.emission("lamp", (1.0, 0.75, 0.45), 30.0)
    steel = ra.rusty_metal("steel", (0.12, 0.12, 0.13), rust=0.3)
    sign_mat = ra.plain("sign", (0.02, 0.06, 0.12), 0.5)
    sign_text = ra.emission("sign_text", (0.9, 0.85, 0.7), 2.0)

    ra.box("platform", (24, 4, 0.5), (0, 2, 0.25), concrete, bevel=0.03)
    ra.box("edge", (24, 0.25, 0.04), (0, 0.15, 0.52), ra.plain("edge", (0.55, 0.45, 0.05), 0.6))
    ra.box("building", (16, 7, 4.2), (0, 8, 2.1), brick)
    # Pitched roof as two slabs.
    for side in (-1, 1):
        slab = ra.box("roof", (17, 4.2, 0.18), (0, 8 + side * 1.75, 4.95), roof, rotation=(side * math.radians(-28), 0, 0))
        slab.name = "roof"
    ra.box("canopy", (20, 3.4, 0.15), (0, 2.6, 3.4), roof)
    for x in (-9, -4.5, 0, 4.5, 9):
        ra.cylinder("post", 0.1, 2.9, (x, 1.2, 1.95), steel)
    for x in (-6, -3, 3, 6):
        ra.box("window", (1.4, 0.1, 1.6), (x, 4.46, 2.2), window)
        ra.box("frame", (1.6, 0.12, 1.8), (x, 4.47, 2.2), steel)
    ra.box("door", (1.8, 0.1, 2.6), (0, 4.46, 1.3), ra.wood("door", (0.1, 0.06, 0.035)))
    ra.box("sign", (5, 0.15, 0.8), (0, 4.4, 3.7), sign_mat)
    ra.box("sign_text", (4.2, 0.05, 0.25), (0, 4.31, 3.7), sign_text)
    for x in (-10.5, 10.5):
        ra.cylinder("lamp_post", 0.07, 3.2, (x, 0.8, 2.1), steel)
        ra.sphere("lamp", 0.22, (x, 0.8, 3.8), lamp, segments=12)
        ra.light("POINT", (x, 0.6, 3.6), 120, (1.0, 0.7, 0.4), size=0.2)
    # Crates waiting on the platform.
    crate = ra.wood("crate", (0.14, 0.09, 0.05))
    for i, (x, y) in enumerate(((7.5, 2.4), (8.4, 2.6), (7.9, 3.2))):
        ra.box("crate", (0.8, 0.8, 0.7), (x, y, 0.85 + (0.7 if i == 2 else 0)), crate, bevel=0.03)
    return meshes()


def render_station(layout: dict):
    w, h = 832, 512
    target = Vector((0, 5.5, 3.0))
    layout["station"] = render_sprite("station", w, h, target, station)


# --- Icons ------------------------------------------------------------------------------------------

def icon_models():
    def axe():
        handle = ra.wood("handle", (0.25, 0.15, 0.07))
        ra.cylinder("handle", 0.022, 0.5, (0, 0, 0.04), handle, rotation=(0, math.radians(90), math.radians(20)))
        head = ra.rusty_metal("head", (0.35, 0.35, 0.37), rust=0.2)
        ra.box("head", (0.07, 0.03, 0.16), (0.2, 0.07, 0.08), head, bevel=0.01, rotation=(0, 0, math.radians(20)))
        ra.box("edge", (0.03, 0.032, 0.2), (0.24, 0.085, 0.08), ra.plain("edge", (0.7, 0.7, 0.72), 0.2, 1.0, grime=0.1),
               rotation=(0, 0, math.radians(20)))

    def shovel():
        ra.cylinder("handle", 0.02, 0.45, (-0.08, 0, 0.04), ra.wood("handle", (0.25, 0.15, 0.07)),
                    rotation=(0, math.radians(90), math.radians(-25)))
        blade = ra.rusty_metal("blade", (0.3, 0.32, 0.34), rust=0.35)
        b = ra.box("blade", (0.2, 0.17, 0.02), (0.2, -0.09, 0.03), blade, bevel=0.01, rotation=(0, 0, math.radians(-25)))
        ra.displace(b, 0.01, 0.5, 1)
        ra.box("grip", (0.04, 0.12, 0.03), (-0.31, 0.11, 0.05), ra.plain("grip", (0.05, 0.05, 0.05), 0.5),
               rotation=(0, 0, math.radians(-25)))

    def pickaxe():
        ra.cylinder("handle", 0.022, 0.5, (0, -0.02, 0.04), ra.wood("handle", (0.25, 0.15, 0.07)),
                    rotation=(0, math.radians(90), math.radians(-60)))
        head = ra.rusty_metal("head", (0.33, 0.33, 0.35), rust=0.25)
        ra.cylinder("pick", 0.025, 0.48, (0.13, 0.2, 0.06), head, radius2=0.008,
                    rotation=(0, math.radians(90), math.radians(30)))

    def wood():
        bark_m = bark()
        cut = ra.wood("cut", (0.32, 0.2, 0.1))
        for i, (x, z) in enumerate(((-0.1, 0.07), (0.1, 0.07), (0.0, 0.2))):
            ra.cylinder("log", 0.085, 0.45, (x, 0, z), bark_m, rotation=(math.radians(90), 0, 0))
            for y in (-0.226, 0.226):
                ra.cylinder("end", 0.08, 0.005, (x, y, z), cut, rotation=(math.radians(90), 0, 0))

    def stones(color, specks=None):
        def build():
            mat = rock("stone", color)
            for i in range(4):
                a = i / 4 * math.tau + 0.4
                s = ra.sphere("stone", random.uniform(0.08, 0.12), (math.cos(a) * 0.11, math.sin(a) * 0.1, 0.07), mat,
                              scale=(1, 0.9, 0.7), segments=10)
                ra.displace(s, 0.03, 0.15, 1)
            if specks:
                m = ra.plain("speck", specks, 0.35, 0.6)
                for _ in range(10):
                    a = random.random() * math.tau
                    ra.sphere("speck", 0.02, (math.cos(a) * 0.12, math.sin(a) * 0.1, 0.13), m, segments=6)
        return build

    def coal():
        m = ra.plain("coal", (0.012, 0.012, 0.014), 0.3, variation=0.5, bump=0.8)
        for i in range(6):
            a = i / 6 * math.tau
            s = ra.sphere("lump", random.uniform(0.06, 0.1), (math.cos(a) * 0.12, math.sin(a) * 0.1, 0.06), m, segments=8)
            ra.displace(s, 0.035, 0.2, 1)

    def sand():
        d = ra.sphere("pile", 0.22, (0, 0, -0.04), sand_mat(), scale=(1, 1, 0.75), segments=24)
        ra.displace(d, 0.02, 0.2, 2)

    return {
        "item_tool_axe": axe, "item_tool_shovel": shovel, "item_tool_pickaxe": pickaxe,
        "item_wood": wood, "item_stone": stones((0.2, 0.19, 0.18)), "item_sand": sand, "item_coal": coal,
        "item_iron_ore": stones((0.18, 0.09, 0.05), (0.4, 0.4, 0.42)),
        "item_copper_ore": stones((0.14, 0.13, 0.12), (0.75, 0.35, 0.12)),
    }


def render_icons():
    ICONS.mkdir(parents=True, exist_ok=True)
    for name, build in icon_models().items():
        random.seed(zlib.crc32(name.encode()))
        ra.icon_scene()
        build()
        ra.render(TMP / f"{name}.png")
        ra.icon_from(Image.open(TMP / f"{name}.png").convert("RGBA"), ICONS / f"{name}.png")
        print("icon", name)


if __name__ == "__main__":
    args = sys.argv[1:] or ["floors", "nature", "station", "rail", "icons"]
    TMP.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    layout_file = OUT / "layout.json"
    layout = json.loads(layout_file.read_text()) if layout_file.exists() else {}
    layout["tile"] = {"width": round(TILE_M * PPM), "height": round(TILE_M * PPM * math.sin(PITCH)), "pixelsPerMetre": PPM}
    if "floors" in args:
        render_floors()
    if "nature" in args:
        render_nature(layout)
    if "rail" in args:
        render_rail(layout)
    if "station" in args:
        render_station(layout)
    if "icons" in args:
        render_icons()
    layout_file.write_text(json.dumps(layout, indent=1))
