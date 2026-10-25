#!/usr/bin/env python3
"""Renders the art of plots (the land a player owns) with Blender into client/art/plot/, and the
icons of tools and raw materials into client/art/icons/.

Same studio as tools/render_art.py (it reuses its helpers), same 45° view from above, but at a
smaller scale: a tile of a plot is 2 × 2 m on screen, 64 × 45 px, at 32 px per metre.

    .venv-art/bin/python tools/render_plot_art.py [floors] [nature] [station] [rail] [farming] [forestry] [mine] [crafting] [processing] [forestry_industry] [office] [power] [mountain] [coast] [oil] [logistics] [<sprite>...] [icons | item_<id>...]

Writes client/art/plot/layout.json with each sprite's anchor: the pixel that stands on the
centre of the tile (or, for the station and the mine, the middle of its south edge).
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

def outdoor_scene(width_px: int, height_px: int, target: Vector, samples=64, pitch=PITCH, true_scale=False):
    """Dusk under a heavy sky: a warm sun from the front left and a cold blue fill. Blender fits the
    camera's width to the longer side of the picture, so a tall one comes out zoomed in unless
    `true_scale` keeps it at PPM pixels per metre."""
    scene = ra.reset()
    scene.cycles.samples = samples
    ra.set_world((0.035, 0.045, 0.065), 1.0)
    ra.camera(scene, target, (max(width_px, height_px) if true_scale else width_px) / PPM, (width_px, height_px), pitch=pitch)
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


def render_sprite(name: str, width: int, height: int, target: Vector, build, true_scale=False) -> dict:
    """Renders an object and, separately, the shadow it throws on the ground."""
    outdoor_scene(width, height, target, true_scale=true_scale)
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


# --- Farming ---------------------------------------------------------------------------------------

def soil_mat():
    m = ra.Mat("soil")
    wave = m.node("ShaderNodeTexWave", wave_type="BANDS", bands_direction="X")
    wave.inputs["Scale"].default_value = 2.2
    wave.inputs["Distortion"].default_value = 0.6
    m.link(m.coord.outputs["Object"], wave.inputs["Vector"])
    fine = m.noise(50.0, detail=6)
    col = m.ramp(wave.outputs["Fac"], [(0.2, (0.03, 0.018, 0.01)), (0.8, (0.085, 0.055, 0.03))]).outputs["Color"]
    col = m.mix(0.5, col, m.ramp(fine.outputs["Fac"], [(0.3, (0.7, 0.7, 0.7)), (0.7, (1.2, 1.2, 1.2))]).outputs["Color"], "MULTIPLY")
    return m.done(col, 0.95, 0.0, wave.outputs["Fac"], 0.9)


def field():
    """A tilled patch 1.9 m square: furrows running across."""
    soil = soil_mat()
    ra.box("field", (1.9, 1.9, 0.04), (0, 0, 0.02), soil, bevel=0.02)
    for i in range(5):
        ridge = ra.box("ridge", (1.8, 0.18, 0.08), (0, -0.76 + i * 0.38, 0.06), soil, bevel=0.03)
        ra.displace(ridge, 0.015, 0.2, 2)
    return meshes()


def rows(count=4, per_row=4, jitter=0.06):
    """Planting spots in rows across a field, front to back."""
    spots = []
    for r in range(count):
        for c in range(per_row):
            spots.append((-0.66 + c * 1.32 / (per_row - 1) + random.uniform(-jitter, jitter),
                          -0.6 + r * 1.2 / (count - 1) + random.uniform(-jitter, jitter)))
    return spots


def wheat(scale):
    stalk = ra.plain("stalk", (0.55, 0.42, 0.15), 0.7)
    ear = ra.plain("ear", (0.8, 0.6, 0.2), 0.6, variation=0.25)
    for x, y in rows(5, 7, 0.08):
        h = random.uniform(0.75, 0.95) * scale
        lean = random.uniform(-0.12, 0.12)
        ra.cylinder("stalk", 0.012, h, (x, y, h / 2), stalk, rotation=(lean, lean, 0), verts=6)
        ra.sphere("ear", 0.045, (x + lean * h * 0.5, y - lean * h * 0.5, h), ear, scale=(1, 1, 2.6), segments=8)
    return meshes()


def corn(scale):
    stalk = ra.plain("cornstalk", (0.06, 0.13, 0.03), 0.7)
    leaf = foliage("cornleaf", (0.1, 0.24, 0.05), 0.3)
    cob = ra.plain("cob", (0.6, 0.42, 0.06), 0.5)
    for x, y in rows(3, 3, 0.05):
        h = random.uniform(1.6, 1.9) * scale
        ra.cylinder("stalk", 0.03, h, (x, y, h / 2), stalk, verts=8)
        for k in range(3):
            a = random.random() * math.tau
            ra.box("leaf", (0.5 * scale, 0.07, 0.01), (x + math.cos(a) * 0.2 * scale, y + math.sin(a) * 0.2 * scale, h * (0.4 + k * 0.2)),
                   leaf, rotation=(0, math.radians(-25), a))
        if scale > 0.8:
            ra.sphere("cob", 0.05, (x + 0.06, y - 0.04, h * 0.6), cob, scale=(1, 1, 2.8), segments=10)
        ra.sphere("tassel", 0.06, (x, y, h + 0.04), ra.plain("tassel", (0.5, 0.38, 0.12), 0.6), scale=(1, 1, 1.8), segments=8)
    return meshes()


def cabbage(scale):
    leaves = foliage("cabbage", (0.25, 0.45, 0.15), 0.25)
    for x, y in rows(3, 3, 0.05):
        r = random.uniform(0.17, 0.21) * scale
        head = ra.sphere("head", r, (x, y, r * 0.8), leaves, scale=(1, 1, 0.85), segments=16)
        ra.displace(head, r * 0.12, 0.12, 2)
        for k in range(4):
            a = k / 4 * math.tau + random.random()
            ra.sphere("outer", r * 0.75, (x + math.cos(a) * r * 0.7, y + math.sin(a) * r * 0.7, r * 0.3), leaves,
                      scale=(1.2, 1.2, 0.35), segments=10)
    return meshes()


def potato(scale):
    leaves = foliage("potato", (0.1, 0.24, 0.05), 0.35)
    flower = ra.plain("pflower", (0.6, 0.55, 0.65), 0.6)
    for x, y in rows(3, 4, 0.06):
        r = random.uniform(0.26, 0.32) * scale
        for k in range(3):
            o = Vector((random.uniform(-0.1, 0.1), random.uniform(-0.1, 0.1), 0)) * scale
            s = ra.sphere("leaves", r * 0.7, Vector((x, y, r * 0.8)) + o, leaves, segments=10)
            ra.displace(s, r * 0.25, 0.15, 1)
        if scale > 0.8:
            ra.sphere("flower", 0.03, (x, y, r * 1.5), flower, segments=6)
    return meshes()


def carrot(scale):
    tops = foliage("carrottop", (0.13, 0.34, 0.07), 0.3)
    root = ra.plain("root", (0.6, 0.18, 0.02), 0.6)
    for x, y in rows(4, 5, 0.05):
        for k in range(5):
            a = k / 5 * math.tau + random.random()
            ra.cylinder("frond", 0.015, 0.45 * scale, (x + math.cos(a) * 0.05, y + math.sin(a) * 0.05, 0.22 * scale), tops,
                        rotation=(math.cos(a) * 0.5, math.sin(a) * 0.5, 0), verts=5)
            ra.sphere("leaf", 0.075 * scale, (x + math.cos(a) * 0.14 * scale, y + math.sin(a) * 0.14 * scale, 0.42 * scale), tops,
                      scale=(1.3, 1.3, 0.6), segments=6)
        if scale > 0.8:
            ra.cylinder("root", 0.03, 0.05, (x, y, 0.03), root, verts=8)
    return meshes()


def sunflower(scale):
    stalk = ra.plain("sunstalk", (0.07, 0.12, 0.03), 0.7)
    leaf = foliage("sunleaf", (0.06, 0.13, 0.03), 0.3)
    petals = ra.plain("petals", (0.9, 0.6, 0.03), 0.5)
    disc = ra.plain("disc", (0.08, 0.04, 0.015), 0.8)
    for x, y in rows(3, 3, 0.05):
        h = random.uniform(1.5, 1.8) * scale
        ra.cylinder("stalk", 0.03, h, (x, y, h / 2), stalk, verts=8)
        for k in range(2):
            a = random.random() * math.tau
            ra.sphere("leaf", 0.13 * scale, (x + math.cos(a) * 0.12, y + math.sin(a) * 0.12, h * (0.4 + k * 0.25)), leaf,
                      scale=(1.4, 1, 0.25), segments=8)
        if scale > 0.8:
            # The heads face the camera, south.
            ra.cylinder("petals", 0.2, 0.03, (x, y - 0.05, h), petals, rotation=(math.radians(70), 0, 0), verts=16)
            ra.cylinder("disc", 0.12, 0.05, (x, y - 0.07, h), disc, rotation=(math.radians(70), 0, 0), verts=16)
        else:
            ra.sphere("bud", 0.06, (x, y, h), leaf, segments=8)
    return meshes()


def sprout(scale):
    leaves = foliage("sprout", (0.16, 0.42, 0.08), 0.3)
    for x, y in rows(4, 5, 0.06):
        for a in (0.4, 0.4 + math.pi):
            ra.sphere("leaf", 0.06, (x + math.cos(a) * 0.06, y + math.sin(a) * 0.06, 0.1), leaves, scale=(1.6, 0.8, 0.4), segments=8)
        ra.cylinder("stem", 0.01, 0.1, (x, y, 0.05), leaves, verts=5)
    return meshes()


CROPS = {"wheat": (wheat, 1.1), "carrot": (carrot, 0.5), "cabbage": (cabbage, 0.5), "corn": (corn, 2.0),
         "potato": (potato, 0.5), "sunflower": (sunflower, 1.9)}


def render_farming(layout: dict):
    """The tilled field (drawn flat under the crop) and every crop half-grown and ripe."""
    layout["field"] = render_sprite("field", 112, 96, Vector((0, 0, 0)), field)
    random.seed(3)
    layout["sprout"] = render_sprite("sprout", 112, 96, Vector((0, 0, 0)), lambda: sprout(1.0))
    for name, (build, height) in CROPS.items():
        for stage, scale in (("young", 0.55), ("ripe", 1.0)):
            random.seed(zlib.crc32(name.encode()))
            h = int(96 + height * scale * 32 * 0.8)
            layout[f"{name}_{stage}"] = render_sprite(f"{name}_{stage}", 128, h, Vector((0, 0, height * scale * 0.35)),
                                                      lambda b=build, s=scale: b(s))


# --- Forestry -------------------------------------------------------------------------------------

def planted(height, width, color):
    """A planted conifer on a mound of fresh soil."""
    mound = ra.sphere("mound", 0.55, (0, 0, -0.05), soil_mat(), scale=(1, 1, 0.3), segments=16)
    ra.displace(mound, 0.04, 0.3, 1)
    return conifer(height, width, color)


FORESTRY = {
    # name: (canvas width, height, camera target height, builder); a grown planted tree uses tree_0-2.
    "sapling": (112, 128, 0.6, lambda: planted(1.5, 0.9, (0.07, 0.17, 0.07))),
    "tree_young": (176, 192, 1.2, lambda: planted(3.0, 1.5, (0.055, 0.13, 0.06))),
}


def render_forestry(layout: dict):
    for name, (w, h, tz, build) in FORESTRY.items():
        random.seed(zlib.crc32(name.encode()))
        layout[name] = render_sprite(name, w, h, Vector((0, 0, tz)), build)


# --- Crafting -------------------------------------------------------------------------------------

def crafted(build):
    def make():
        build()
        return meshes()
    return make


def build_brick_furnace():
    """The furnace's second level: a square kiln of red brick on a stone plinth, an arched mouth
    full of embers, iron bands round it and a tall brick chimney at the back."""
    brick = ra.plain("brick", (0.32, 0.08, 0.04), 0.85, variation=0.35, scale=14, bump=0.5)
    mortar = rock("brick_plinth", (0.18, 0.17, 0.15))
    iron = ra.rusty_metal("brick_iron", (0.1, 0.1, 0.11), 0.5)
    dark = ra.plain("brick_soot", (0.02, 0.018, 0.017), 0.95, variation=0.3)
    ember = ra.emission("brick_ember", (1.0, 0.3, 0.04), 2.0)
    ra.box("plinth", (1.3, 1.3, 0.14), Vector((0, 0, 0.07)), mortar, bevel=0.03)
    for k in range(6):
        z = 0.14 + 0.11 * (k + 0.5)
        ra.box("brick_course", (1.16 - 0.02 * k, 1.16 - 0.02 * k, 0.1), Vector((0, 0, z)), brick, bevel=0.012)
    ra.box("brick_top", (1.1, 1.1, 0.08), Vector((0, 0, 0.84)), brick, bevel=0.02)
    for z in (0.3, 0.68):
        ra.box("brick_band", (1.2, 1.2, 0.035), Vector((0, 0, z)), iron)
    ra.box("brick_mouth", (0.44, 0.08, 0.34), Vector((0, -0.56, 0.36)), dark)
    ra.box("brick_glow", (0.36, 0.04, 0.16), Vector((0, -0.6, 0.27)), ember)
    ra.box("brick_lintel", (0.56, 0.12, 0.08), Vector((0, -0.58, 0.57)), iron, bevel=0.01)
    ra.box("brick_chimney", (0.34, 0.34, 0.9), Vector((0.24, 0.3, 1.3)), brick, bevel=0.02)
    ra.box("brick_chimney_cap", (0.42, 0.42, 0.06), Vector((0.24, 0.3, 1.78)), iron, bevel=0.01)


def build_blast_furnace():
    """The furnace's third level: a riveted steel shaft furnace on a brick base, banded and
    lined with fire, with a glowing tap hole at the front, a charging hopper on top and a pipe
    down its side."""
    steel = ra.rusty_metal("blast_steel", (0.17, 0.17, 0.18), 0.35)
    dark = ra.rusty_metal("blast_dark", (0.07, 0.07, 0.075), 0.5)
    brick = ra.plain("blast_brick", (0.3, 0.08, 0.04), 0.85, variation=0.35, scale=14, bump=0.5)
    ember = ra.emission("blast_ember", (1.0, 0.38, 0.05), 2.5)
    ra.box("blast_base", (1.36, 1.36, 0.3), Vector((0, 0, 0.15)), brick, bevel=0.03)
    ra.cylinder("blast_shaft", 0.5, 1.1, Vector((0, 0.05, 0.85)), steel, bevel=0.03, verts=24)
    for z in (0.42, 0.75, 1.08, 1.36):
        ra.cylinder("blast_band", 0.53, 0.05, Vector((0, 0.05, z)), dark, verts=24)
    ra.cylinder("blast_neck", 0.32, 0.22, Vector((0, 0.05, 1.5)), steel, bevel=0.02, verts=20)
    ra.cylinder("blast_hopper", 0.4, 0.12, Vector((0, 0.05, 1.66)), dark, bevel=0.02, verts=20)
    ra.box("blast_tap", (0.3, 0.1, 0.22), Vector((0, -0.48, 0.45)), dark, bevel=0.02)
    ra.box("blast_tap_glow", (0.2, 0.04, 0.12), Vector((0, -0.54, 0.44)), ember)
    ra.box("blast_spout", (0.14, 0.3, 0.06), Vector((0, -0.66, 0.3)), dark, rotation=(math.radians(15), 0, 0))
    ra.box("blast_pool", (0.22, 0.12, 0.02), Vector((0, -0.8, 0.31)), ember)
    ra.cylinder("blast_pipe", 0.07, 1.4, Vector((0.55, 0.3, 0.95)), dark, verts=12)
    ra.box("blast_pipe_top", (0.5, 0.12, 0.12), Vector((0.35, 0.3, 1.62)), dark, bevel=0.02)


CRAFTING = {
    # Objects a player puts on a plot, built like the garage's furniture; the furnace a bit larger
    # so it reads at the plot's scale. name: (canvas width, height, camera target height, builder).
    "workbench": (144, 128, 0.6, crafted(lambda: ra.build_workbench(None, Vector((0, 0, 0))))),
    "furnace": (96, 112, 0.6, crafted(lambda: ra.build_furnace(None, Vector((0, 0, 0)), 1.4))),
    "anvil": (96, 96, 0.5, crafted(lambda: ra.build_anvil(None, Vector((0, 0, 0)), 1.7))),
    # The upgraded furnaces stand on plots only; the inventory shows them as their sprites.
    "brick_furnace": (112, 144, 0.9, crafted(build_brick_furnace)),
    "blast_furnace": (112, 160, 1.0, crafted(build_blast_furnace)),
}

# Crafting sprites whose icon is their sprite cropped to a square, like the processing machines.
SPRITE_ICONS = ("brick_furnace", "blast_furnace")


# --- Food processing ------------------------------------------------------------------------------

def build_mill():
    """A small timber windmill on a stone footing: a boarded hut with a pitched roof, four lattice
    sails on a hub facing the camera, and a sack of flour by the door."""
    stone = rock("mill_stone", (0.2, 0.19, 0.17))
    planks = ra.wood("mill_planks", (0.2, 0.12, 0.06))
    dark = ra.wood("mill_dark", (0.09, 0.05, 0.03))
    roof = ra.plain("mill_roof", (0.18, 0.07, 0.04), 0.8, variation=0.3, bump=0.4)
    ra.box("footing", (1.3, 1.3, 0.25), (0, 0, 0.125), stone, bevel=0.04)
    hut = ra.box("hut", (1.1, 1.1, 1.2), (0, 0, 0.85), planks, bevel=0.02)
    for x in (-0.53, 0.53):
        for y in (-0.53, 0.53):
            ra.box("post", (0.08, 0.08, 1.2), (x, y, 0.85), dark)
    ra.box("door", (0.36, 0.04, 0.7), (-0.2, -0.56, 0.6), dark, bevel=0.01)
    # A pitched roof along x with gables.
    v = [(-0.7, -0.68, 1.45), (0.7, -0.68, 1.45), (0.7, 0.68, 1.45), (-0.7, 0.68, 1.45), (-0.7, 0, 2.05), (0.7, 0, 2.05)]
    ra.mesh_from("roof", v, [(0, 1, 5, 4), (3, 4, 5, 2), (0, 4, 3), (1, 2, 5), (0, 3, 2, 1)], roof)
    # Sails on a hub at the front gable, turned a little so all four read.
    hub = (0.15, -0.66, 1.55)
    ra.cylinder("axle", 0.07, 0.25, hub, dark, rotation=(math.radians(90), 0, 0))
    sail = ra.plain("sail", (0.55, 0.5, 0.4), 0.9, variation=0.2)
    for k in range(4):
        a = k * math.pi / 2 + 0.35
        d = Vector((math.cos(a), 0, math.sin(a)))
        ra.box("stock", (0.05, 0.04, 1.1), Vector(hub) + Vector((0, -0.08, 0)) + d * 0.55, dark, rotation=(0, -a + math.pi / 2, 0))
        side = Vector((math.cos(a + math.pi / 2), 0, math.sin(a + math.pi / 2)))
        ra.box("sail", (0.26, 0.02, 0.8), Vector(hub) + Vector((0, -0.1, 0)) + d * 0.62 + side * 0.14, sail,
               rotation=(0, -a + math.pi / 2, 0))
    sack = ra.plain("mill_sack", (0.55, 0.5, 0.4), 0.95, variation=0.2, bump=0.4)
    s = ra.sphere("sack", 0.2, (0.45, -0.75, 0.2), sack, scale=(0.9, 0.8, 1.2), segments=16)
    ra.displace(s, 0.02, 0.2, 1)


def build_oil_press():
    """A wooden screw press: a heavy frame over a tub, a big screw with a capstan bar, a spout
    running oil into a jug."""
    frame = ra.wood("press_frame", (0.17, 0.1, 0.05))
    steel = ra.rusty_metal("press_screw", (0.25, 0.25, 0.27), rust=0.3)
    ra.box("base", (1.1, 0.8, 0.2), (0, 0, 0.1), frame, bevel=0.02)
    for x in (-0.45, 0.45):
        ra.box("upright", (0.14, 0.18, 1.3), (x, 0, 0.85), frame, bevel=0.02)
    ra.box("beam", (1.1, 0.22, 0.18), (0, 0, 1.45), frame, bevel=0.02)
    ra.cylinder("tub", 0.3, 0.3, (0, 0, 0.35), ra.wood("press_tub", (0.22, 0.13, 0.06)), verts=24)
    for z in (0.25, 0.45):
        ra.cylinder("hoop", 0.31, 0.03, (0, 0, z), steel, verts=24)
    ra.cylinder("seeds", 0.27, 0.02, (0, 0, 0.5), ra.plain("seeds", (0.05, 0.04, 0.03), 0.6, bump=0.8), verts=24)
    ra.cylinder("plate", 0.26, 0.06, (0, 0, 0.62), frame, verts=24)
    ra.cylinder("screw", 0.05, 0.85, (0, 0, 1.05), steel, verts=12)
    ra.box("bar", (0.9, 0.05, 0.05), (0, 0, 1.25), frame, rotation=(0, 0, math.radians(25)))
    gold = ra.plain("oil", (0.75, 0.5, 0.05), 0.1, variation=0.05)
    ra.box("spout", (0.06, 0.25, 0.04), (0, -0.4, 0.3), steel)
    ra.cylinder("jug", 0.09, 0.22, (0, -0.55, 0.11), ra.plain("jug", (0.55, 0.3, 0.15), 0.4), verts=16)
    ra.cylinder("jug_oil", 0.08, 0.01, (0, -0.55, 0.22), gold, verts=16)


def build_pickling_barrel():
    """A tall oak barrel with iron hoops, a wooden lid and a stone holding the cabbage down."""
    staves = ra.wood("barrel_staves", (0.24, 0.14, 0.06))
    hoop = ra.rusty_metal("barrel_hoop", (0.15, 0.15, 0.16), rust=0.5)
    ra.cylinder("barrel", 0.42, 1.0, (0, 0, 0.5), staves, verts=28)
    for z in (0.12, 0.45, 0.88):
        ra.cylinder("hoop", 0.435, 0.05, (0, 0, z), hoop, verts=28)
    ra.cylinder("lid", 0.36, 0.04, (0, 0, 1.0), ra.wood("barrel_lid", (0.3, 0.19, 0.09)), verts=28)
    s = ra.sphere("weight", 0.17, (0.05, 0.02, 1.1), rock("weight", (0.25, 0.24, 0.22)), scale=(1, 0.9, 0.6), segments=12)
    ra.displace(s, 0.02, 0.15, 1)
    # A couple of cabbages waiting by the barrel.
    leaves = foliage("barrel_cabbage", (0.14, 0.28, 0.09), 0.25)
    for x, y in ((0.5, -0.3), (0.62, -0.05)):
        c = ra.sphere("cabbage", 0.14, (x, y, 0.12), leaves, scale=(1, 1, 0.85), segments=14)
        ra.displace(c, 0.015, 0.06, 1)


def build_bakery():
    """A clay bread oven: a domed vault on a brick plinth with a glowing arched mouth, a chimney
    and a wooden peel leaning on it."""
    brick = ra.plain("oven_brick", (0.32, 0.12, 0.06), 0.9, variation=0.35, scale=10, bump=0.5)
    clay = ra.plain("oven_clay", (0.42, 0.28, 0.17), 0.9, variation=0.25, bump=0.4)
    soot = ra.plain("oven_soot", (0.02, 0.018, 0.017), 0.95)
    ra.box("plinth", (1.4, 1.3, 0.6), (0, 0, 0.3), brick, bevel=0.03)
    ra.box("ledge", (1.5, 1.4, 0.06), (0, 0, 0.63), clay, bevel=0.02)
    dome = ra.sphere("dome", 0.62, (0, 0.05, 0.66), clay, scale=(1, 1, 0.85), segments=32, keep=lambda co: co.z >= -0.01)
    ra.displace(dome, 0.012, 0.2, 1)
    ra.cylinder("mouth", 0.24, 0.1, (0, -0.55, 0.85), clay, rotation=(math.radians(90), 0, 0), verts=24)
    ra.box("mouth_hole", (0.32, 0.12, 0.24), (0, -0.6, 0.8), soot)
    ember = ra.emission("oven_ember", (1.0, 0.35, 0.06), 5.0)
    for i in range(5):
        ra.sphere("ember", 0.04, (-0.1 + i * 0.05, -0.55, 0.7), ember, segments=8)
    ra.cylinder("chimney", 0.1, 0.55, (0.3, 0.35, 1.3), brick, verts=12)
    ra.cylinder("peel", 0.025, 1.1, (-0.75, -0.45, 0.6), ra.wood("peel", (0.3, 0.2, 0.1)), rotation=(math.radians(-12), math.radians(8), 0), verts=8)
    ra.box("peel_blade", (0.22, 0.02, 0.28), (-0.75, -0.39, 0.12), ra.wood("peel", (0.3, 0.2, 0.1)), rotation=(math.radians(-12), 0, 0))
    crust = ra.plain("loaf", (0.42, 0.2, 0.06), 0.6, variation=0.2, bump=0.4)
    for x in (0.35, 0.55):
        ra.sphere("loaf", 0.11, (x, -0.55, 0.72), crust, scale=(1.4, 1, 0.7), segments=12)


def build_kitchen():
    """A field kitchen: a cast-iron stove on two cart wheels with a big lidded cauldron on top,
    a firebox door glowing below and a stove pipe."""
    iron = ra.rusty_metal("kitchen_iron", (0.08, 0.09, 0.08), rust=0.35)
    green = ra.rusty_metal("kitchen_green", (0.12, 0.17, 0.08), rust=0.25)
    ra.box("stove", (1.2, 0.8, 0.6), (0, 0, 0.55), green, bevel=0.03)
    ra.box("rim", (1.26, 0.86, 0.05), (0, 0, 0.87), iron, bevel=0.01)
    ra.cylinder("cauldron", 0.33, 0.5, (-0.15, 0, 1.1), iron, verts=24)
    ra.cylinder("lid", 0.35, 0.04, (-0.15, 0, 1.37), iron, verts=24)
    ra.sphere("knob", 0.05, (-0.15, 0, 1.42), iron, segments=10)
    ra.box("firebox", (0.3, 0.04, 0.22), (0.25, -0.41, 0.45), iron, bevel=0.01)
    ember = ra.emission("kitchen_ember", (1.0, 0.35, 0.06), 4.0)
    ra.box("glow", (0.22, 0.03, 0.06), (0.25, -0.43, 0.42), ember)
    ra.cylinder("pipe", 0.07, 0.9, (0.42, 0.2, 1.3), iron, verts=12)
    ra.cylinder("cap", 0.12, 0.04, (0.42, 0.2, 1.76), iron, verts=12)
    tyre = ra.plain("kitchen_tyre", (0.03, 0.03, 0.03), 0.7)
    for y in (-0.48, 0.48):
        ra.cylinder("wheel", 0.3, 0.1, (0.0, y, 0.3), tyre, rotation=(math.radians(90), 0, 0), verts=24)
        ra.cylinder("hub", 0.08, 0.12, (0.0, y, 0.3), iron, rotation=(math.radians(90), 0, 0), verts=12)
    ra.box("drawbar", (0.7, 0.06, 0.06), (-0.85, 0, 0.35), iron, rotation=(0, math.radians(15), 0))


PROCESSING = {
    # name: (canvas width, height, camera target height, builder); each stands on one tile.
    "mill": (128, 160, 0.95, build_mill),
    "oil_press": (112, 120, 0.7, build_oil_press),
    "pickling_barrel": (96, 96, 0.5, build_pickling_barrel),
    "bakery": (112, 120, 0.6, build_bakery),
    "kitchen": (112, 120, 0.75, build_kitchen),
}


def render_processing(layout: dict):
    for name, (w, h, tz, build) in PROCESSING.items():
        random.seed(zlib.crc32(name.encode()))
        layout[name] = render_sprite(name, w, h, Vector((0, 0, tz)), crafted(build))
        # The inventory shows the machine as its sprite, cropped to a square icon.
        ra.icon_from(Image.open(OUT / f"{name}.png").convert("RGBA"), ICONS / f"furniture_{name}.png")


# --- Forestry industry -------------------------------------------------------------------------------
# A forester's building covers 3 × 3 tiles (6 × 6 m) and is drawn once, on its middle tile, with its
# door to the south; the sawmills stand on one tile like the mill.

def log_wall(name, length, height, at, along_x, mat, cut, r=0.13):
    """A wall of stacked round logs, their cut ends showing a little past the corners."""
    for k in range(int(height / (2 * r * 0.9))):
        z = at[2] + r + k * 2 * r * 0.9
        rot = (0, math.radians(90), 0) if along_x else (math.radians(90), 0, 0)
        ra.cylinder(name, r, length + 0.3, Vector((at[0], at[1], z)), mat, rotation=rot, verts=12)
        for e in (-1, 1):
            end = Vector((e * (length / 2 + 0.152), 0, 0)) if along_x else Vector((0, e * (length / 2 + 0.152), 0))
            ra.cylinder(name + "_end", r - 0.015, 0.01, Vector((at[0], at[1], z)) + end, cut, rotation=rot, verts=12)


def gable_roof(name, w, d, eave, ridge, mat, at=(0, 0)):
    """A pitched roof along x over a w × d house, with overhangs."""
    x, y = at
    hw, hd = w / 2 + 0.25, d / 2 + 0.3
    v = [(x - hw, y - hd, eave), (x + hw, y - hd, eave), (x + hw, y + hd, eave), (x - hw, y + hd, eave),
         (x - hw, y, ridge), (x + hw, y, ridge)]
    ra.mesh_from(name, v, [(0, 1, 5, 4), (3, 4, 5, 2), (0, 4, 3), (1, 2, 5), (0, 3, 2, 1)], mat)


def gable_ends(name, w, d, eave, ridge, mat, at=(0, 0)):
    x, y = at
    for e in (-1, 1):
        gx = x + e * w / 2
        v = [(gx, y - d / 2, eave), (gx, y + d / 2, eave), (gx, y, ridge - 0.08)]
        ra.mesh_from(name, v, [(0, 1, 2)], mat)


def sapling_pots(at, count, needles, soil):
    at = (*at, 0)[:3]
    for i in range(count):
        p = Vector(at) + Vector((i * 0.34, (i % 2) * 0.12, 0))
        ra.cylinder("pot", 0.12, 0.18, p + Vector((0, 0, 0.09)), soil, verts=12)
        for t in range(3):
            ra.cylinder("pot_tree", 0.13 * (1 - t * 0.3), 0.18, p + Vector((0, 0, 0.26 + t * 0.12)), needles, radius2=0.01, verts=10)


def chopping_block(at, bark_m, cut, steel, handle):
    at = (*at, 0)[:3]
    ra.cylinder("block", 0.26, 0.45, Vector(at) + Vector((0, 0, 0.225)), bark_m, verts=16)
    ra.cylinder("block_top", 0.245, 0.01, Vector(at) + Vector((0, 0, 0.455)), cut, verts=16)
    ra.cylinder("axe_handle", 0.025, 0.7, Vector(at) + Vector((0.12, 0, 0.72)), handle, rotation=(0, math.radians(35), 0), verts=8)
    ra.box("axe_head", (0.2, 0.04, 0.12), Vector(at) + Vector((-0.06, 0, 0.47)), steel, rotation=(0, math.radians(35), 0))


def log_stack(at, rows, length, r, bark_m, cut, along_x=True):
    at = (*at, 0)[:3]
    for row, count in enumerate(rows):
        for i in range(count):
            off = (i - (count - 1) / 2) * 2 * r
            z = r + row * r * 1.75
            p = Vector(at) + (Vector((0, off, z)) if along_x else Vector((off, 0, z)))
            rot = (0, math.radians(90), 0) if along_x else (math.radians(90), 0, 0)
            ra.cylinder("stack_log", r, length, p, bark_m, rotation=rot, verts=12)
            for e in (-1, 1):
                end = Vector((e * (length / 2 + 0.002), 0, 0)) if along_x else Vector((0, e * (length / 2 + 0.002), 0))
                ra.cylinder("stack_end", r - 0.012, 0.01, p + end, cut, rotation=rot, verts=12)


def build_forester_hut():
    """The forester's hut: a log cabin with a shingle roof and a stone chimney, its door to the
    south, a chopping block with an axe, a stack of logs and saplings in pots waiting to be planted."""
    logs = bark()
    cut = ra.wood("hut_cut", (0.36, 0.23, 0.11))
    dark = ra.wood("hut_dark", (0.08, 0.045, 0.025))
    shingles = ra.plain("hut_shingles", (0.12, 0.08, 0.05), 0.85, variation=0.35, scale=18, bump=0.6)
    stone = rock("hut_stone", (0.2, 0.19, 0.17))
    steel = ra.rusty_metal("hut_axe", (0.3, 0.3, 0.32), rust=0.25)
    soil = soil_mat()
    needles = foliage("hut_needles", (0.07, 0.17, 0.07), 0.3)
    w, d, h = 3.2, 2.6, 1.9
    ra.box("hut_floor", (w + 0.3, d + 0.3, 0.16), Vector((0, 0.3, 0.08)), stone, bevel=0.03)
    for y in (-d / 2, d / 2):
        log_wall("hut_wall", w, h, (0, 0.3 + y, 0.16), True, logs, cut)
    for x in (-w / 2, w / 2):
        log_wall("hut_wall", d, h, (x, 0.3, 0.16), False, logs, cut)
    ra.box("hut_inside", (w, d, h), Vector((0, 0.3, 0.16 + h / 2)), dark)
    gable_ends("hut_gable", w, d, 0.16 + h, 0.16 + h + 1.3, ra.wood("hut_boards", (0.18, 0.11, 0.05)), (0, 0.3))
    gable_roof("hut_roof", w, d, 0.1 + h, 0.16 + h + 1.3, shingles, (0, 0.3))
    ra.box("hut_door", (0.7, 0.06, 1.35), Vector((0.2, 0.3 - d / 2 - 0.14, 0.16 + 0.68)), dark, bevel=0.02)
    glow = ra.emission("hut_window", (1.0, 0.65, 0.3), 1.6)
    ra.box("hut_window", (0.5, 0.04, 0.42), Vector((-0.95, 0.3 - d / 2 - 0.14, 1.15)), glow)
    ra.box("hut_frame", (0.62, 0.05, 0.08), Vector((-0.95, 0.3 - d / 2 - 0.15, 0.9)), dark)
    ra.box("hut_chimney", (0.5, 0.5, 1.5), Vector((1.2, 0.9, 2.8)), stone, bevel=0.04)
    ra.box("hut_step", (1.0, 0.4, 0.12), Vector((0.2, 0.3 - d / 2 - 0.35, 0.06)), stone, bevel=0.02)
    chopping_block((-1.6, -1.9), logs, cut, steel, dark)
    log_stack((1.95, -0.2), (4, 3, 2), 1.3, 0.13, logs, cut, along_x=False)
    sapling_pots((-1.2, -2.5), 3, needles, soil)


def build_forester_lodge():
    """The forester's lodge: a bigger timber house on a stone plinth with green shutters, a porch
    on posts over the door, a lean-to woodshed full of logs and rows of saplings."""
    boards = ra.wood("lodge_boards", (0.22, 0.13, 0.06))
    dark = ra.wood("lodge_dark", (0.08, 0.045, 0.025))
    logs = bark()
    cut = ra.wood("lodge_cut", (0.36, 0.23, 0.11))
    stone = rock("lodge_stone", (0.21, 0.2, 0.18))
    roof = ra.plain("lodge_roof", (0.2, 0.06, 0.04), 0.8, variation=0.3, scale=16, bump=0.5)
    green = ra.plain("lodge_shutter", (0.06, 0.16, 0.07), 0.7, variation=0.2)
    glow = ra.emission("lodge_window", (1.0, 0.65, 0.3), 1.6)
    soil = soil_mat()
    needles = foliage("lodge_needles", (0.07, 0.17, 0.07), 0.3)
    w, d, h = 3.8, 3.0, 2.3
    ra.box("lodge_plinth", (w + 0.2, d + 0.2, 0.5), Vector((-0.2, 0.4, 0.25)), stone, bevel=0.04)
    ra.box("lodge_walls", (w, d, h), Vector((-0.2, 0.4, 0.5 + h / 2)), boards, bevel=0.02)
    for x in (-w / 2, w / 2):
        for y in (-d / 2, d / 2):
            ra.box("lodge_corner", (0.14, 0.14, h), Vector((-0.2 + x, 0.4 + y, 0.5 + h / 2)), dark)
    gable_roof("lodge_roof", w, d, 0.45 + h, 0.5 + h + 1.5, roof, (-0.2, 0.4))
    front = 0.4 - d / 2 - 0.02
    ra.box("lodge_door", (0.75, 0.05, 1.5), Vector((-0.2, front, 0.5 + 0.75)), dark, bevel=0.02)
    for x in (-1.35, 0.95):
        ra.box("lodge_window", (0.55, 0.04, 0.6), Vector((x, front, 1.65)), glow)
        for e in (-1, 1):
            ra.box("lodge_shutter", (0.26, 0.05, 0.66), Vector((x + e * 0.42, front - 0.01, 1.65)), green, bevel=0.01)
    # The porch: a small roof on two posts and wide steps.
    ra.box("lodge_steps", (1.5, 0.6, 0.25), Vector((-0.2, front - 0.3, 0.125)), stone, bevel=0.02)
    ra.box("lodge_deck", (1.6, 0.9, 0.08), Vector((-0.2, front - 0.45, 0.46)), boards)
    for x in (-0.95, 0.55):
        ra.box("lodge_post", (0.12, 0.12, 1.75), Vector((x, front - 0.85, 1.35)), dark)
    ra.box("lodge_porch_roof", (1.9, 1.1, 0.08), Vector((-0.2, front - 0.5, 2.3)), roof, rotation=(math.radians(-14), 0, 0))
    # The woodshed against the east wall.
    ra.box("shed_roof", (1.2, 2.6, 0.06), Vector((2.3, 0.4, 1.95)), roof, rotation=(0, math.radians(-12), 0))
    for y in (-0.8, 1.6):
        ra.box("shed_post", (0.1, 0.1, 1.85), Vector((2.75, y, 0.93)), dark)
    log_stack((2.2, 0.4), (5, 4, 4, 3), 2.3, 0.13, logs, cut, along_x=False)
    ra.box("lodge_chimney", (0.45, 0.45, 1.4), Vector((-1.4, 1.1, 3.6)), stone, bevel=0.03)
    sapling_pots((-2.3, -2.3), 4, needles, soil)
    sapling_pots((-2.15, -2.75), 4, needles, soil)
    chopping_block((1.6, -2.0), logs, cut, ra.rusty_metal("lodge_axe", (0.3, 0.3, 0.32), rust=0.25), dark)


def build_forestry_station():
    """The forestry station: a two-storey office with a red roof, a timber lookout tower behind it,
    a yard of stacked logs and a yellow log loader."""
    plaster = ra.plain("station_plaster", (0.55, 0.5, 0.42), 0.85, variation=0.15, bump=0.3)
    timber = ra.wood("station_timber", (0.2, 0.12, 0.06))
    dark = ra.wood("station_dark", (0.08, 0.045, 0.025))
    roof = ra.plain("station_roof", (0.3, 0.07, 0.04), 0.75, variation=0.3, scale=16, bump=0.5)
    stone = rock("station_stone", (0.21, 0.2, 0.18))
    glow = ra.emission("station_window", (1.0, 0.68, 0.32), 1.6)
    green = ra.plain("station_green", (0.06, 0.16, 0.07), 0.7, variation=0.2)
    yellow = ra.rusty_metal("station_loader", (0.7, 0.45, 0.03), rust=0.2)
    steel = ra.rusty_metal("station_steel", (0.1, 0.1, 0.11), rust=0.35)
    tyre = ra.plain("station_tyre", (0.03, 0.03, 0.03), 0.7)
    logs = bark()
    cut = ra.wood("station_cut", (0.36, 0.23, 0.11))
    w, d, h = 3.4, 2.6, 3.0
    cx, cy = -0.9, 0.6
    ra.box("station_plinth", (w + 0.2, d + 0.2, 0.3), Vector((cx, cy, 0.15)), stone, bevel=0.03)
    ra.box("station_walls", (w, d, h), Vector((cx, cy, 0.3 + h / 2)), plaster, bevel=0.02)
    ra.box("station_band", (w + 0.04, d + 0.04, 0.12), Vector((cx, cy, 0.3 + h / 2)), timber)
    gable_roof("station_roof", w, d, 0.25 + h, 0.3 + h + 1.4, roof, (cx, cy))
    front = cy - d / 2 - 0.02
    ra.box("station_door", (0.7, 0.05, 1.35), Vector((cx, front, 0.3 + 0.68)), dark, bevel=0.02)
    for x in (cx - 1.1, cx + 1.1):
        for z in (1.15, 2.6):
            ra.box("station_window", (0.5, 0.04, 0.55), Vector((x, front, z)), glow)
            for e in (-1, 1):
                ra.box("station_shutter", (0.22, 0.05, 0.6), Vector((x + e * 0.37, front - 0.01, z)), green)
    ra.box("station_window", (0.5, 0.04, 0.55), Vector((cx, front, 2.6)), glow)
    ra.box("station_sign", (1.1, 0.05, 0.3), Vector((cx, front - 0.02, 1.95)), timber, bevel=0.01)
    ra.box("station_step", (1.1, 0.45, 0.15), Vector((cx, front - 0.25, 0.075)), stone)
    # The lookout tower: four legs braced crosswise, a cabin with a pyramid roof.
    tx, ty, th = 1.55, 1.6, 5.2
    for x in (-0.55, 0.55):
        for y in (-0.55, 0.55):
            ra.box("tower_leg", (0.14, 0.14, th), Vector((tx + x, ty + y, th / 2)), timber)
    for z in (1.3, 2.6, 3.9):
        for y in (-0.55, 0.55):
            ra.box("tower_brace", (1.1, 0.06, 0.08), Vector((tx, ty + y, z)), timber)
        for x in (-0.55, 0.55):
            ra.box("tower_brace", (0.06, 1.1, 0.08), Vector((tx + x, ty, z)), timber)
    ra.box("tower_cabin", (1.5, 1.5, 0.9), Vector((tx, ty, th + 0.45)), timber, bevel=0.02)
    ra.box("tower_glass", (1.2, 1.54, 0.4), Vector((tx, ty, th + 0.55)), glow)
    v = [(tx - 0.95, ty - 0.95, th + 0.9), (tx + 0.95, ty - 0.95, th + 0.9), (tx + 0.95, ty + 0.95, th + 0.9),
         (tx - 0.95, ty + 0.95, th + 0.9), (tx, ty, th + 1.65)]
    ra.mesh_from("tower_roof", v, [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)], roof)
    # The log yard in front of the tower and the loader beside it.
    log_stack((1.6, -0.35), (6, 5, 4), 2.4, 0.14, logs, cut)
    ra.box("loader_body", (1.0, 0.75, 0.55), Vector((1.75, -2.05, 0.6)), yellow, bevel=0.04)
    ra.box("loader_cab", (0.5, 0.6, 0.6), Vector((2.0, -2.05, 1.15)), yellow, bevel=0.03)
    ra.box("loader_glass", (0.42, 0.62, 0.38), Vector((2.0, -2.05, 1.2)), ra.plain("loader_glass", (0.08, 0.12, 0.14), 0.15))
    ra.box("loader_arm", (1.1, 0.12, 0.12), Vector((1.0, -2.05, 1.0)), yellow, rotation=(0, math.radians(-25), 0))
    ra.box("loader_grab", (0.12, 0.6, 0.4), Vector((0.5, -2.05, 0.65)), steel)
    for x in (1.4, 2.1):
        for y in (-2.47, -1.63):
            ra.cylinder("loader_wheel", 0.24, 0.16, Vector((x, y, 0.24)), tyre, rotation=(math.radians(90), 0, 0), verts=16)
    sapling_pots((-2.5, -2.5), 4, foliage("station_needles", (0.07, 0.17, 0.07), 0.3), soil_mat())


def build_sawmill():
    """A sawmill by hand: a log on two sawhorses under a wooden frame saw, a stack of fresh planks
    and a heap of sawdust."""
    frame = ra.wood("saw_frame", (0.17, 0.1, 0.05))
    fresh = ra.wood("saw_fresh", (0.5, 0.34, 0.17))
    logs = bark()
    cut = ra.wood("saw_cut", (0.36, 0.23, 0.11))
    steel = ra.rusty_metal("saw_blade", (0.4, 0.4, 0.42), rust=0.2)
    dust = ra.plain("sawdust", (0.55, 0.4, 0.2), 0.95, variation=0.2, bump=0.6)
    for x in (-0.45, 0.45):
        for y in (-0.15, 0.15):
            ra.box("horse_leg", (0.06, 0.06, 0.7), Vector((x, y, 0.33)), frame, rotation=(math.radians(18 if y > 0 else -18), 0, 0))
        ra.box("horse_beam", (0.08, 0.5, 0.08), Vector((x, 0, 0.66)), frame)
    ra.cylinder("saw_log", 0.17, 1.5, Vector((0, 0, 0.86)), logs, rotation=(0, math.radians(90), 0), verts=16)
    for x in (-0.751, 0.751):
        ra.cylinder("saw_log_end", 0.155, 0.01, Vector((x, 0, 0.86)), cut, rotation=(0, math.radians(90), 0), verts=16)
    # The frame saw stuck in the log.
    ra.box("saw_blade", (0.02, 0.6, 0.08), Vector((0.15, 0, 1.0)), steel)
    for y in (-0.3, 0.3):
        ra.box("saw_arm", (0.05, 0.05, 0.6), Vector((0.15, y, 1.25)), frame)
    ra.box("saw_top", (0.05, 0.64, 0.05), Vector((0.15, 0, 1.55)), frame)
    for k in range(4):
        ra.box("plank", (1.1, 0.24, 0.05), Vector((-0.1, -0.68 + (k % 2) * 0.02, 0.03 + k * 0.055)), fresh)
    d = ra.sphere("sawdust", 0.22, Vector((0.25, -0.2, -0.02)), dust, scale=(1.2, 1, 0.4), segments=16)
    ra.displace(d, 0.02, 0.2, 1)


def build_electric_sawmill():
    """The electric sawmill: a steel table with a big circular blade showing through its top, a blue
    motor underneath, a log being fed in and boards coming out."""
    steel = ra.rusty_metal("esaw_steel", (0.2, 0.2, 0.22), rust=0.25)
    dark = ra.rusty_metal("esaw_dark", (0.06, 0.06, 0.07), rust=0.3)
    blue = ra.rusty_metal("esaw_motor", (0.05, 0.12, 0.35), rust=0.15)
    blade = ra.plain("esaw_blade", (0.7, 0.7, 0.72), 0.2, 1.0, grime=0.15)
    fresh = ra.wood("esaw_fresh", (0.5, 0.34, 0.17))
    logs = bark()
    cut = ra.wood("esaw_cut", (0.36, 0.23, 0.11))
    for x in (-0.6, 0.6):
        for y in (-0.3, 0.3):
            ra.box("esaw_leg", (0.07, 0.07, 0.7), Vector((x, y, 0.35)), dark)
    ra.box("esaw_table", (1.5, 0.8, 0.08), Vector((0, 0, 0.74)), steel, bevel=0.01)
    ra.cylinder("esaw_blade", 0.34, 0.02, Vector((0, 0, 0.78)), blade, rotation=(math.radians(90), 0, 0), verts=32)
    ra.box("esaw_guard", (0.75, 0.1, 0.12), Vector((0, 0, 1.14)), ra.plain("esaw_guard", (0.75, 0.5, 0.04), 0.5))
    ra.box("esaw_guard_arm", (0.06, 0.06, 0.4), Vector((0.35, 0.0, 0.96)), dark)
    ra.cylinder("esaw_motor", 0.18, 0.4, Vector((0, 0.1, 0.35)), blue, rotation=(0, math.radians(90), 0), verts=20)
    ra.box("esaw_box", (0.25, 0.08, 0.3), Vector((0.55, -0.43, 0.5)), blue, bevel=0.01)
    ra.box("esaw_lamp", (0.06, 0.03, 0.06), Vector((0.55, -0.48, 0.58)), ra.emission("esaw_lamp", (0.2, 1.0, 0.3), 3.0))
    ra.cylinder("esaw_log", 0.14, 0.7, Vector((-0.5, 0, 0.92)), logs, rotation=(0, math.radians(90), 0), verts=14)
    ra.cylinder("esaw_log_end", 0.128, 0.01, Vector((-0.851, 0, 0.92)), cut, rotation=(0, math.radians(90), 0), verts=14)
    for k in range(3):
        ra.box("esaw_board", (0.5, 0.26, 0.04), Vector((0.5, 0.0, 0.8 + k * 0.045)), fresh)
    for k in range(5):
        ra.box("esaw_stack", (1.0, 0.24, 0.05), Vector((0.05, -0.75 + (k % 2) * 0.03, 0.03 + k * 0.055)), fresh)


def build_industrial_sawmill():
    """The industrial sawmill: a tall yellow band saw over a log carriage on rails, a control box
    with a red light and a pile of sawn beams."""
    yellow = ra.rusty_metal("isaw_yellow", (0.72, 0.46, 0.03), rust=0.2)
    dark = ra.rusty_metal("isaw_dark", (0.06, 0.06, 0.07), rust=0.3)
    steel = ra.rusty_metal("isaw_steel", (0.25, 0.25, 0.27), rust=0.25)
    blade = ra.plain("isaw_blade", (0.7, 0.7, 0.72), 0.2, 1.0, grime=0.15)
    fresh = ra.wood("isaw_fresh", (0.5, 0.34, 0.17))
    logs = bark()
    cut = ra.wood("isaw_cut", (0.36, 0.23, 0.11))
    ra.box("isaw_base", (1.7, 1.2, 0.12), Vector((0, 0.1, 0.06)), ra.plain("isaw_concrete", (0.3, 0.3, 0.28), 0.9), bevel=0.02)
    for y in (-0.15, 0.15):
        ra.box("isaw_rail", (1.6, 0.05, 0.05), Vector((0, y, 0.15)), steel)
    ra.box("isaw_carriage", (0.9, 0.42, 0.18), Vector((-0.3, 0, 0.27)), dark, bevel=0.02)
    ra.cylinder("isaw_log", 0.18, 1.1, Vector((-0.3, 0, 0.55)), logs, rotation=(0, math.radians(90), 0), verts=16)
    for x in (-0.851, 0.251):
        ra.cylinder("isaw_log_end", 0.165, 0.01, Vector((x, 0, 0.55)), cut, rotation=(0, math.radians(90), 0), verts=16)
    # The band saw: two wheels in a yellow housing on a column behind the line.
    ra.box("isaw_column", (0.3, 0.3, 1.6), Vector((0.45, 0.45, 0.92)), yellow, bevel=0.03)
    for z in (0.45, 1.55):
        ra.cylinder("isaw_wheel", 0.3, 0.16, Vector((0.45, 0.12, z)), yellow, rotation=(math.radians(90), 0, 0), verts=24)
        ra.cylinder("isaw_hub", 0.07, 0.18, Vector((0.45, 0.12, z)), dark, rotation=(math.radians(90), 0, 0), verts=12)
    ra.box("isaw_band", (0.03, 0.03, 1.1), Vector((0.45, 0.0, 1.0)), blade)
    ra.box("isaw_band_back", (0.03, 0.03, 1.1), Vector((0.75, 0.12, 1.0)), blade)
    ra.box("isaw_box", (0.3, 0.2, 0.5), Vector((-0.65, 0.5, 0.45)), dark, bevel=0.02)
    ra.box("isaw_light", (0.08, 0.03, 0.08), Vector((-0.65, 0.39, 0.6)), ra.emission("isaw_light", (1.0, 0.1, 0.05), 4.0))
    ra.box("isaw_screen", (0.18, 0.03, 0.12), Vector((-0.65, 0.39, 0.42)), ra.emission("isaw_screen", (0.2, 0.8, 0.4), 1.5))
    for row in range(3):
        for k in range(3 - row):
            ra.box("isaw_beam", (1.0, 0.16, 0.16), Vector((0.1, -0.62 + (k + row * 0.5) * 0.17 - 0.08, 0.2 + row * 0.16)), fresh, bevel=0.01)


FORESTRY_INDUSTRY = {
    # name: (canvas width, height, camera target height, builder). The forester's buildings cover
    # 3 × 3 tiles; the sawmills one, like the mill.
    "forester_hut": (240, 256, 1.6, build_forester_hut),
    "forester_lodge": (240, 272, 1.9, build_forester_lodge),
    "forestry_station": (240, 336, 2.9, build_forestry_station),
    "sawmill": (112, 120, 0.6, build_sawmill),
    "electric_sawmill": (112, 120, 0.6, build_electric_sawmill),
    "industrial_sawmill": (112, 144, 0.85, build_industrial_sawmill),
}


FORESTERS = ("forester_hut", "forester_lodge", "forestry_station")


def render_forestry_industry(layout: dict, only=()):
    for name, (w, h, tz, build) in FORESTRY_INDUSTRY.items():
        if only and name not in only:
            continue
        random.seed(zlib.crc32(name.encode()))
        # True scale keeps a tall building three tiles wide, the size of the ground it stands on.
        layout[name] = render_sprite(name, w, h, Vector((0, 0, tz)), crafted(build), true_scale=name in FORESTERS)
        ra.icon_from(Image.open(OUT / f"{name}.png").convert("RGBA"), ICONS / f"furniture_{name}.png")


# --- Office ---------------------------------------------------------------------------------------

def build_computer():
    """A computer on a small wooden desk: a monitor facing the camera with a market chart glowing on
    it, a keyboard and mouse in front, the case standing beside the desk."""
    top = ra.wood("desk_top", (0.24, 0.15, 0.08))
    legs = ra.wood("desk_legs", (0.12, 0.07, 0.04))
    plastic = ra.plain("computer_plastic", (0.62, 0.6, 0.55), 0.5, variation=0.1)
    dark = ra.plain("computer_dark", (0.03, 0.03, 0.035), 0.4)
    ra.box("desk", (1.3, 0.75, 0.06), (0, 0.05, 0.75), top, bevel=0.015)
    for x in (-0.6, 0.6):
        for y in (-0.27, 0.37):
            ra.box("desk_leg", (0.06, 0.06, 0.72), (x, y, 0.36), legs)
    # The monitor: a stand, a bezel and the screen with a rising line of prices on it.
    ra.box("stand", (0.24, 0.16, 0.03), (0, 0.2, 0.795), dark, bevel=0.01)
    ra.box("neck", (0.06, 0.05, 0.2), (0, 0.22, 0.9), dark)
    ra.box("monitor", (0.78, 0.07, 0.5), (0, 0.2, 1.22), plastic, bevel=0.02)
    ra.box("screen", (0.7, 0.01, 0.42), (0, 0.162, 1.22), ra.emission("screen", (0.05, 0.16, 0.24), 2.5))
    line = ra.emission("chart", (0.25, 1.0, 0.45), 6.0)
    points = [(-0.3, 1.08), (-0.18, 1.14), (-0.06, 1.11), (0.06, 1.22), (0.18, 1.2), (0.3, 1.34)]
    for (x0, z0), (x1, z1) in zip(points, points[1:]):
        length = math.hypot(x1 - x0, z1 - z0)
        ra.box("chart", (length, 0.012, 0.022), ((x0 + x1) / 2, 0.155, (z0 + z1) / 2), line,
               rotation=(0, -math.atan2(z1 - z0, x1 - x0), 0))
    ra.box("keyboard", (0.5, 0.17, 0.025), (-0.05, -0.12, 0.79), plastic, bevel=0.008)
    ra.box("keys", (0.46, 0.13, 0.008), (-0.05, -0.12, 0.806), dark)
    ra.sphere("mouse", 0.04, (0.32, -0.12, 0.79), plastic, scale=(0.8, 1.3, 0.5), segments=10)
    # The case on the ground by the right legs, with a lit power button.
    ra.box("case", (0.22, 0.5, 0.48), (0.82, 0.05, 0.24), plastic, bevel=0.015)
    ra.cylinder("power", 0.022, 0.01, (0.82, -0.205, 0.4), ra.emission("power", (0.3, 0.8, 1.0), 6.0),
                rotation=(math.radians(90), 0, 0), verts=12)


OFFICE = {
    # name: (canvas width, height, camera target height, builder); stands on one tile.
    "computer": (128, 112, 0.7, build_computer),
}


def render_office(layout: dict):
    for name, (w, h, tz, build) in OFFICE.items():
        random.seed(zlib.crc32(name.encode()))
        layout[name] = render_sprite(name, w, h, Vector((0, 0, tz)), crafted(build))
        ra.icon_from(Image.open(OUT / f"{name}.png").convert("RGBA"), ICONS / f"furniture_{name}.png")


def render_crafting(layout: dict, only=()):
    for name, (w, h, tz, build) in CRAFTING.items():
        if only and name not in only:
            continue
        random.seed(zlib.crc32(name.encode()))
        layout[name] = render_sprite(name, w, h, Vector((0, 0, tz)), build)
        if name in SPRITE_ICONS:
            ra.icon_from(Image.open(OUT / f"{name}.png").convert("RGBA"), ICONS / f"furniture_{name}.png")


# --- Logistics --------------------------------------------------------------------------------------

# Paint of belts and inserters by level, as in the factory games people know: yellow, red, blue.
TIER_PAINT = {"": (0.5, 0.33, 0.03), "fast": (0.45, 0.05, 0.03), "express": (0.04, 0.14, 0.45)}


def belt_frame(s=1.0, along_x=True, length=2.0, tier=""):
    """A conveyor belt the length of a tile, so belts on neighbouring tiles join up: a dark rubber
    band between two side rails on short legs, painted by level. The game draws the moving stripes and items."""
    paint = ra.plain("belt_paint" + tier, TIER_PAINT[tier], 0.5, 0.4, variation=0.2, grime=0.8)
    rubber = ra.plain("belt_rubber", (0.025, 0.025, 0.027), 0.8, variation=0.3, scale=20, bump=0.3)
    steel = ra.rusty_metal("belt_steel", (0.16, 0.16, 0.17), 0.3)

    def at(a, b, z):
        return Vector((a * s, b * s, z * s)) if along_x else Vector((b * s, a * s, z * s))

    def size(a, b, z):
        return (a * s, b * s, z * s) if along_x else (b * s, a * s, z * s)

    ra.box("belt_band", size(length, 0.96, 0.05), at(0, 0, 0.2), rubber)
    for side in (-0.53, 0.53):
        ra.box("belt_rail", size(length, 0.1, 0.16), at(0, side, 0.22), paint, bevel=0.015 * s)
        for a in (-length / 2 + 0.25, length / 2 - 0.25):
            ra.box("belt_leg", size(0.08, 0.08, 0.16), at(a, side, 0.08), steel)
    # Rollers under the band show at its sides.
    for k in range(5):
        a = -length / 2 + (k + 0.5) * length / 5
        rot = (math.radians(90), 0, 0) if along_x else (0, math.radians(90), 0)
        ra.cylinder("belt_roller", 0.07 * s, 1.0 * s, at(a, 0, 0.13), steel, rotation=rot, verts=12)


def arc_box(name, r_in, r_out, z0, z1, a0, a1, centre, mat, n=12):
    """A curved slab: the part of a ring between two radii and two angles (radians), from z0 to z1,
    about `centre` (x, y)."""
    verts, faces = [], []
    for k in range(n + 1):
        a = a0 + (a1 - a0) * k / n
        for r in (r_in, r_out):
            for z in (z0, z1):
                verts.append((centre[0] + r * math.cos(a), centre[1] + r * math.sin(a), z))
    for k in range(n):
        i, j = 4 * k, 4 * (k + 1)
        # inner, outer, bottom and top faces of the step
        faces += [(i, i + 1, j + 1, j), (i + 2, j + 2, j + 3, i + 3), (i, j, j + 2, i + 2), (i + 1, i + 3, j + 3, j + 1)]
    last = 4 * n
    faces += [(0, 2, 3, 1), (last, last + 1, last + 3, last + 2)]
    obj = ra.mesh_from(name, verts, faces, mat)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


# The sides of a tile a curve joins, as unit vectors in Blender's (east, north).
SIDES = {"n": (0, 1), "e": (1, 0), "s": (0, -1), "w": (-1, 0)}


def belt_curve(sides, tier=""):
    """A belt turning a corner between two sides of its tile: the band and rails bent round the
    tile's corner between those sides, like belt_frame laid in a quarter circle."""
    paint = ra.plain("belt_paint" + tier, TIER_PAINT[tier], 0.5, 0.4, variation=0.2, grime=0.8)
    rubber = ra.plain("belt_rubber", (0.025, 0.025, 0.027), 0.8, variation=0.3, scale=20, bump=0.3)
    steel = ra.rusty_metal("belt_steel", (0.16, 0.16, 0.17), 0.3)
    (ax, ay), (bx, by) = SIDES[sides[0]], SIDES[sides[1]]
    centre = (ax + bx, ay + by)
    mid = math.atan2(-centre[1], -centre[0])
    a0, a1 = mid - math.pi / 4, mid + math.pi / 4
    arc_box("belt_band", 1 - 0.48, 1 + 0.48, 0.175, 0.225, a0, a1, centre, rubber, n=16)
    for r in (1 - 0.53, 1 + 0.53):
        arc_box("belt_rail", r - 0.05, r + 0.05, 0.14, 0.30, a0, a1, centre, paint, n=16)
        for a in (a0 + 0.2, a1 - 0.2):
            ra.box("belt_leg", (0.08, 0.08, 0.16), Vector((centre[0] + r * math.cos(a), centre[1] + r * math.sin(a), 0.08)), steel)
    for k in range(4):
        a = a0 + (k + 0.5) * (a1 - a0) / 4
        ra.cylinder("belt_roller", 0.07, 1.0, Vector((centre[0] + math.cos(a), centre[1] + math.sin(a), 0.13)), steel,
                    rotation=(0, math.radians(90), a), verts=12)


def splitter(s=1.0):
    """The middle of a splitter: a steel wedge that turns what comes in to both
    sides, under a yellow cap with a lamp. The game draws the crossed belts under it, so it looks
    the same turned any way."""
    paint = ra.plain("splitter_paint", (0.55, 0.36, 0.03), 0.45, 0.4, variation=0.2, grime=0.7)
    steel = ra.rusty_metal("splitter_steel", (0.15, 0.15, 0.16), 0.25)
    ra.box("splitter_wedge", (0.62 * s, 0.62 * s, 0.34 * s), Vector((0, 0, 0.36 * s)), steel, bevel=0.03 * s,
           rotation=(0, 0, math.radians(45)))
    ra.box("splitter_cap", (0.7 * s, 0.7 * s, 0.08 * s), Vector((0, 0, 0.57 * s)), paint, bevel=0.025 * s,
           rotation=(0, 0, math.radians(45)))
    ra.cylinder("splitter_lamp", 0.06 * s, 0.06 * s, Vector((0, 0, 0.64 * s)), ra.emission("splitter_lamp", (0.3, 1.0, 0.25), 3.0), verts=12)


def inserter(s=1.0, arm=False, tier=""):
    """The base of an inserter: a steel foot and a turret painted by level; the game draws the arm
    swinging from the tile behind it to the tile in front. With `arm` (for its icon) the arm is modelled too."""
    paint = ra.plain("inserter_paint" + tier, (0.55, 0.36, 0.03) if tier == "" else TIER_PAINT[tier], 0.45, 0.4, variation=0.2, grime=0.7)
    steel = ra.rusty_metal("inserter_steel", (0.15, 0.15, 0.16), 0.25)
    ra.box("inserter_foot", (0.9 * s, 0.9 * s, 0.1 * s), Vector((0, 0, 0.05 * s)), steel, bevel=0.03 * s)
    ra.cylinder("inserter_base", 0.36 * s, 0.14 * s, Vector((0, 0, 0.17 * s)), steel, bevel=0.02 * s)
    ra.cylinder("inserter_turret", 0.24 * s, 0.36 * s, Vector((0, 0, 0.42 * s)), paint, bevel=0.03 * s)
    ra.cylinder("inserter_cap", 0.17 * s, 0.07 * s, Vector((0, 0, 0.635 * s)), steel, bevel=0.015 * s)
    ra.box("inserter_lamp", (0.08 * s, 0.03 * s, 0.05 * s), Vector((0, -0.24 * s, 0.5 * s)),
           ra.emission("inserter_lamp", (0.3, 1.0, 0.25), 3.0))
    if arm:
        ra.box("inserter_arm", (0.1 * s, 0.75 * s, 0.08 * s), Vector((0, 0.3 * s, 0.75 * s)), paint, bevel=0.02 * s,
               rotation=(math.radians(-25), 0, 0))
        ra.box("inserter_hand", (0.22 * s, 0.08 * s, 0.14 * s), Vector((0, 0.66 * s, 0.6 * s)), steel, bevel=0.02 * s)


def wooden_chest(s=1.0):
    """A chest of planks with iron bands and corners."""
    planks = ra.wood("chest_planks", (0.24, 0.14, 0.07))
    iron = ra.rusty_metal("chest_iron", (0.12, 0.12, 0.13), 0.4)
    w, d, h = 1.2, 0.85, 0.62
    for k in range(4):
        ra.box("chest_plank", (w * s, d * s, (h / 4 - 0.012) * s), Vector((0, 0, (h / 4) * (k + 0.5) * s)), planks, bevel=0.012 * s)
    ra.box("chest_lid", ((w + 0.04) * s, (d + 0.04) * s, 0.12 * s), Vector((0, 0, (h + 0.06) * s)), planks, bevel=0.02 * s)
    for x in (-w / 2 + 0.12, w / 2 - 0.12):
        ra.box("chest_band", (0.07 * s, (d + 0.03) * s, (h + 0.14) * s), Vector((x * s, 0, (h + 0.12) / 2 * s)), iron, bevel=0.01 * s)
    ra.box("chest_lock", (0.12 * s, 0.03 * s, 0.14 * s), Vector((0, -(d / 2 + 0.03) * s, (h - 0.02) * s)), iron, bevel=0.01 * s)


def iron_chest(s=1.0):
    """A riveted steel chest, larger than the wooden one."""
    plate = ra.rusty_metal("chest_plate", (0.24, 0.25, 0.27), 0.2)
    dark = ra.rusty_metal("chest_frame", (0.09, 0.09, 0.1), 0.35)
    w, d, h = 1.3, 0.95, 0.7
    ra.box("chest_body", (w * s, d * s, h * s), Vector((0, 0, h / 2 * s)), plate, bevel=0.03 * s)
    ra.box("chest_lid", ((w + 0.05) * s, (d + 0.05) * s, 0.1 * s), Vector((0, 0, (h + 0.05) * s)), dark, bevel=0.02 * s)
    for x in (-w / 2, w / 2):
        for y in (-d / 2, d / 2):
            ra.box("chest_corner", (0.09 * s, 0.09 * s, (h + 0.04) * s), Vector((x * s, y * s, (h + 0.04) / 2 * s)), dark, bevel=0.01 * s)
    for x in (-0.4, 0.0, 0.4):
        ra.sphere("chest_rivet", 0.025 * s, Vector((x * s, -(d / 2 + 0.01) * s, (h - 0.12) * s)), dark, segments=8)
    ra.box("chest_handle", (0.3 * s, 0.04 * s, 0.05 * s), Vector((0, -(d / 2 + 0.04) * s, (h - 0.25) * s)), dark, bevel=0.01 * s)


def wood_pile(s=1.0):
    """Logs stacked between two pairs of posts."""
    bark_m = bark()
    cut = ra.wood("pile_cut", (0.36, 0.23, 0.11))
    post = ra.wood("pile_post", (0.12, 0.07, 0.04))
    r, length = 0.15, 1.5
    rnd = random.Random(5)
    for row, count in enumerate((5, 4, 3)):
        for i in range(count):
            y = (i - (count - 1) / 2) * 2 * r
            z = r + row * r * 1.75
            jitter = rnd.uniform(-0.06, 0.06)
            ra.cylinder("pile_log", r * s, length * s, Vector((jitter * s, y * s, z * s)), bark_m, rotation=(0, math.radians(90), 0), verts=14)
            for x in (-length / 2 - 0.002, length / 2 + 0.002):
                ra.cylinder("pile_end", (r - 0.015) * s, 0.01 * s, Vector(((x + jitter) * s, y * s, z * s)), cut, rotation=(0, math.radians(90), 0), verts=14)
    for x in (-0.55, 0.55):
        for y in (-0.85, 0.85):
            ra.box("pile_post", (0.08 * s, 0.08 * s, 0.85 * s), Vector((x * s, y * s, 0.42 * s)), post, bevel=0.01 * s)


def heap(s=1.0):
    """A bay of stacked stone on three sides with a mound of loose rock and ore in it."""
    stone = ra.plain("heap_wall", (0.2, 0.19, 0.17), 0.9, variation=0.3, scale=8, bump=0.5)
    rnd = random.Random(3)
    for side, (cx, cy, w, d) in enumerate(((0, 0.8, 1.8, 0.22), (-0.8, 0.05, 0.22, 1.5), (0.8, 0.05, 0.22, 1.5))):
        for k in range(2):
            b = ra.box("heap_block", (w * s, d * s, 0.17 * s), Vector((cx * s, cy * s, (0.09 + 0.18 * k) * s)), stone, bevel=0.03 * s,
                       rotation=(0, 0, rnd.uniform(-0.03, 0.03)))
            ra.displace(b, 0.015 * s, 0.1, 1)
    mound = ra.sphere("heap_mound", 0.75 * s, Vector((0, 0.1 * s, 0)), rock("heap_rock", (0.15, 0.14, 0.13)), scale=(1, 0.95, 0.6), segments=24)
    ra.displace(mound, 0.08 * s, 0.25, 2)
    lumps = (rock("heap_coal", (0.03, 0.03, 0.03)), rock("heap_iron", (0.22, 0.12, 0.08)), rock("heap_copper", (0.2, 0.13, 0.06)))
    for i in range(14):
        a, d = rnd.uniform(0, math.tau), rnd.uniform(0.1, 0.6)
        x, y = math.cos(a) * d, math.sin(a) * d * 0.9 + 0.1
        z = 0.45 * math.sqrt(max(0.0, 1 - (d / 0.75) ** 2))
        boulder_m = lumps[i % len(lumps)]
        b = ra.sphere("heap_lump", rnd.uniform(0.06, 0.1) * s, Vector((x * s, y * s, z * s)), boulder_m, segments=10)
        ra.displace(b, 0.02 * s, 0.1, 1)


def grain_silo(s=1.0):
    """A corrugated steel silo with a cone roof and a ladder up its front."""
    sheet = ra.corrugated("silo_sheet", (0.42, 0.43, 0.44), 0.15)
    roof = ra.rusty_metal("silo_roof", (0.32, 0.33, 0.35), 0.2)
    steel = ra.rusty_metal("silo_steel", (0.12, 0.12, 0.13), 0.3)
    r, h = 0.72, 2.4
    ra.cylinder("silo_base", (r + 0.08) * s, 0.15 * s, Vector((0, 0, 0.075 * s)), ra.plain("silo_concrete", (0.3, 0.3, 0.29), 0.9), verts=40)
    ra.cylinder("silo_body", r * s, h * s, Vector((0, 0, (0.15 + h / 2) * s)), sheet, verts=48)
    for z in (0.7, 1.4, 2.1):
        ra.cylinder("silo_ring", (r + 0.015) * s, 0.04 * s, Vector((0, 0, (0.15 + z) * s)), steel, verts=48)
    ra.cylinder("silo_roof", (r + 0.06) * s, 0.55 * s, Vector((0, 0, (0.15 + h + 0.275) * s)), roof, verts=48, radius2=0.12 * s)
    ra.cylinder("silo_vent", 0.12 * s, 0.14 * s, Vector((0, 0, (0.15 + h + 0.6) * s)), steel, verts=16)
    for x in (-0.12, 0.12):
        ra.box("silo_ladder", (0.03 * s, 0.03 * s, h * s), Vector((x * s, -(r + 0.07) * s, (0.15 + h / 2) * s)), steel)
    for k in range(10):
        ra.box("silo_rung", (0.24 * s, 0.025 * s, 0.025 * s), Vector((0, -(r + 0.07) * s, (0.35 + k * 0.23) * s)), steel)
    ra.box("silo_hatch", (0.3 * s, 0.05 * s, 0.25 * s), Vector((0.35 * s, -(r - 0.08) * s, 0.4 * s)), steel, bevel=0.02 * s,
           rotation=(0, 0, math.radians(-25)))


LOGISTICS = {
    # name: (canvas width, height, camera target height, builder)
    "belt_ew": (72, 64, 0.1, crafted(lambda: belt_frame(along_x=True))),
    "belt_ns": (72, 72, 0.1, crafted(lambda: belt_frame(along_x=False))),
    "belt_ne": (72, 72, 0.1, crafted(lambda: belt_curve("ne"))),
    "belt_es": (72, 72, 0.1, crafted(lambda: belt_curve("es"))),
    "belt_sw": (72, 72, 0.1, crafted(lambda: belt_curve("sw"))),
    "belt_nw": (72, 72, 0.1, crafted(lambda: belt_curve("nw"))),
    "splitter": (64, 64, 0.3, crafted(lambda: splitter())),
    "inserter": (64, 64, 0.3, crafted(lambda: inserter())),
    "wooden_chest": (64, 64, 0.3, crafted(lambda: wooden_chest())),
    "iron_chest": (72, 64, 0.3, crafted(lambda: iron_chest())),
    "wood_pile": (72, 72, 0.3, crafted(lambda: wood_pile())),
    "heap": (80, 72, 0.2, crafted(lambda: heap())),
    "grain_silo": (72, 136, 1.4, crafted(lambda: grain_silo())),
}

# Fast and express belts and inserters: the same sprites in their own paint, named <sprite>_<tier>.
for _tier in ("fast", "express"):
    LOGISTICS.update({
        f"belt_ew_{_tier}": (72, 64, 0.1, crafted(lambda t=_tier: belt_frame(along_x=True, tier=t))),
        f"belt_ns_{_tier}": (72, 72, 0.1, crafted(lambda t=_tier: belt_frame(along_x=False, tier=t))),
        **{f"belt_{c}_{_tier}": (72, 72, 0.1, crafted(lambda t=_tier, c=c: belt_curve(c, tier=t))) for c in ("ne", "es", "sw", "nw")},
        f"inserter_{_tier}": (64, 64, 0.3, crafted(lambda t=_tier: inserter(tier=t))),
    })


def render_logistics(layout: dict, only=()):
    for name, (w, h, tz, build) in LOGISTICS.items():
        if only and name not in only:
            continue
        random.seed(zlib.crc32(name.encode()))
        layout[name] = render_sprite(name, w, h, Vector((0, 0, tz)), build, true_scale=True)


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


# --- Trains ---------------------------------------------------------------------------------------

def bogie(x, steel, wheel_mat):
    """A two-axle bogie under a rail vehicle, centred at x on the track."""
    ra.box("bogie", (2.4, 2.0, 0.4), (x, 0, 0.75), steel, bevel=0.03)
    for dx in (-0.75, 0.75):
        for y in (-0.72, 0.72):
            ra.cylinder("wheel", 0.42, 0.14, (x + dx, y * 1.02, 0.45), wheel_mat, rotation=(math.radians(90), 0, 0), verts=20)
        ra.cylinder("axle", 0.08, 1.7, (x + dx, 0, 0.45), steel, rotation=(math.radians(90), 0, 0), verts=10)


def couplers(length, steel):
    for side in (-1, 1):
        ra.box("buffer_beam", (0.2, 2.6, 0.35), (side * (length / 2 + 0.05), 0, 1.0), steel)
        for y in (-0.8, 0.8):
            ra.cylinder("buffer", 0.16, 0.35, (side * (length / 2 + 0.3), y, 1.0), steel, rotation=(0, math.radians(90), 0), verts=12)


def locomotive():
    """A diesel shunting locomotive 9 m long on the track along x, its cab and lamps at the west
    (left) end, where trains leave towards. Centred on the track at x = 0."""
    paint = ra.plain("loco_paint", (0.55, 0.13, 0.04), 0.4, grime=0.55)
    stripe = ra.plain("loco_stripe", (0.75, 0.6, 0.08), 0.5, grime=0.4)
    steel = ra.rusty_metal("loco_steel", (0.1, 0.1, 0.11), rust=0.25)
    wheel_mat = ra.rusty_metal("wheel", (0.2, 0.19, 0.18), rust=0.5)
    glass = ra.emission("cab_glass", (1.0, 0.7, 0.35), 3.0)
    lamp = ra.emission("headlamp", (1.0, 0.9, 0.7), 40.0)
    roof = ra.plain("loco_roof", (0.09, 0.09, 0.1), 0.6)

    ra.box("frame", (9, 2.7, 0.4), (0, 0, 1.15), steel, bevel=0.03)
    ra.box("skirt", (9.1, 2.75, 0.18), (0, 0, 1.3), stripe)
    for x in (-2.9, 2.9):
        bogie(x, steel, wheel_mat)
    couplers(9, steel)
    # Cab at the west end, the long hood behind it.
    ra.box("cab", (2.6, 2.7, 2.5), (-3.0, 0, 2.65), paint, bevel=0.06)
    ra.box("cab_roof", (2.9, 2.9, 0.18), (-3.0, 0, 3.95), roof, bevel=0.04)
    ra.box("hood", (5.6, 2.0, 2.0), (1.4, 0, 2.4), paint, bevel=0.08)
    ra.box("hood_top", (5.2, 1.6, 0.12), (1.4, 0, 3.45), roof)
    ra.box("hood_stripe", (5.62, 2.02, 0.16), (1.4, 0, 1.75), stripe)
    for x in (0.2, 1.4, 2.6):
        ra.cylinder("fan", 0.38, 0.08, (x, 0, 3.52), steel, verts=16)
    ra.cylinder("exhaust", 0.12, 0.6, (-0.8, 0.3, 3.7), steel, verts=12)
    for y in (-1.36, 1.36):
        for x in (-3.6, -2.5):
            ra.box("cab_window", (0.8, 0.04, 0.8), (x, y, 3.2), glass)
    ra.box("front_window", (0.04, 2.1, 0.8), (-4.31, 0, 3.2), glass)
    for y in (-0.8, 0.8):
        ra.sphere("headlamp", 0.14, (-4.35, y, 1.75), lamp, segments=10)
    ra.box("rail_guard", (0.1, 2.4, 0.08), (2.9, 0, 3.0), stripe)
    ra.light("POINT", (-4.8, 0, 1.8), 60, (1.0, 0.85, 0.6), size=0.2)
    return meshes()


def wagon(cargo):
    """A wagon 7 m long: a closed boxcar or an open one with crates. Centred on the track at x = 0."""
    steel = ra.rusty_metal("wagon_steel", (0.1, 0.1, 0.11), rust=0.3)
    wheel_mat = ra.rusty_metal("wheel", (0.2, 0.19, 0.18), rust=0.5)
    ra.box("frame", (7, 2.6, 0.35), (0, 0, 1.1), steel, bevel=0.03)
    for x in (-2.3, 2.3):
        bogie(x, steel, wheel_mat)
    couplers(7, steel)
    if not cargo:
        body = ra.corrugated("boxcar", (0.22, 0.07, 0.04), rust=0.45)
        ra.box("body", (7, 2.8, 2.6), (0, 0, 2.6), body, bevel=0.04)
        ra.box("roof", (7.1, 2.9, 0.2), (0, 0, 3.95), ra.plain("boxcar_roof", (0.12, 0.11, 0.1), 0.7), bevel=0.06)
        ra.box("door", (2.2, 0.06, 2.3), (0, -1.42, 2.55), ra.corrugated("boxcar_door", (0.17, 0.055, 0.035), rust=0.5))
        ra.box("door_rail", (4.6, 0.08, 0.08), (0, -1.45, 3.75), steel)
        return meshes()
    sides = ra.rusty_metal("gondola", (0.08, 0.16, 0.1), rust=0.4)
    ra.box("floor", (7, 2.8, 0.2), (0, 0, 1.4), sides)
    for y in (-1.35, 1.35):
        ra.box("side", (7, 0.1, 1.2), (0, y, 2.0), sides, bevel=0.02)
    for x in (-3.45, 3.45):
        ra.box("end", (0.1, 2.8, 1.2), (x, 0, 2.0), sides, bevel=0.02)
    for x in (-2.4, -1.2, 0, 1.2, 2.4):
        ra.box("rib", (0.12, 2.9, 1.2), (x, 0, 2.0), steel)
    crate = ra.wood("wagon_crate", (0.15, 0.1, 0.055))
    sack = ra.plain("sack", (0.35, 0.3, 0.2), 0.9, grime=0.3)
    for i, x in enumerate((-2.5, -1.3, -0.1, 1.1, 2.4)):
        for j, y in enumerate((-0.6, 0.6)):
            tall = 0.9 + random.random() * 0.4
            if (i + j) % 3 == 2:
                ra.sphere("sack", 0.5, (x, y, 1.9), sack, scale=(1.1, 0.9, 0.6), segments=12)
            else:
                ra.box("crate", (1.0, 1.0, tall), (x, y, 1.5 + tall / 2), crate, bevel=0.03,
                       rotation=(0, 0, math.radians(random.uniform(-6, 6))))
    return meshes()


TRAINS = {
    # name: (canvas width, height, builder)
    "train_locomotive": (352, 224, locomotive),
    "train_wagon": (288, 208, lambda: wagon(False)),
    "train_wagon_open": (288, 208, lambda: wagon(True)),
}


def render_trains(layout: dict):
    """Rail vehicles anchored on the middle of the track under their centre."""
    for name, (w, h, build) in TRAINS.items():
        random.seed(zlib.crc32(name.encode()))
        layout[name] = render_sprite(name, w, h, Vector((0, 0, 1.8)), build)
        layout[name]["lengthPx"] = round((9.0 if name == "train_locomotive" else 7.0) * PPM)


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


# --- Mine -----------------------------------------------------------------------------------------

def mine():
    """A mine on a mountain plot: a rocky hill 8 × 6 m with a timbered adit in its south face,
    a short track coming out of it and a cart of ore. Its south edge is y = 0."""
    stone = rock("hill", (0.11, 0.105, 0.1))
    hill = ra.sphere("hill", 1.0, (0, 3.6, -0.6), stone, scale=(3.9, 2.7, 3.4), segments=48)
    ra.displace(hill, 0.55, 0.45, 3)
    for i, (x, y, s) in enumerate(((-3.2, 1.2, 0.9), (3.1, 1.4, 1.1), (-2.2, 5.4, 1.2), (2.6, 5.2, 1.0), (3.6, 3.2, 0.8))):
        b = ra.sphere("boulder", s, (x, y, s * 0.2), stone, scale=(1.1, 1, 0.75), segments=14)
        ra.displace(b, 0.15, 0.4, 2)
    timber = ra.wood("timber", (0.12, 0.075, 0.04))
    dark = ra.emission("adit", (0.0, 0.0, 0.0), 0.0)
    # The adit: a dark opening held by two posts and a lintel, cut into the hill.
    ra.box("opening", (1.6, 1.6, 2.0), (0, 1.75, 1.0), dark)
    for x in (-0.95, 0.95):
        ra.box("post", (0.24, 0.24, 2.3), (x, 1.0, 1.15), timber, bevel=0.02)
    ra.box("lintel", (2.4, 0.3, 0.3), (0, 1.0, 2.35), timber, bevel=0.02)
    ra.box("sill", (2.2, 0.4, 0.12), (0, 1.0, 0.06), timber)
    # Track running out of the adit onto the ground.
    steel = ra.rusty_metal("rail", (0.3, 0.28, 0.26), rust=0.55)
    sleeper = ra.wood("sleeper", (0.08, 0.05, 0.03))
    for i in range(5):
        ra.box("sleeper", (1.3, 0.18, 0.08), (0, 1.5 - i * 0.45, 0.04), sleeper)
    for x in (-0.45, 0.45):
        ra.box("rail", (0.07, 2.4, 0.08), (x, 0.55, 0.12), steel)
    # A cart full of ore on the track, and a lamp by the entrance.
    cart = ra.rusty_metal("cart", (0.2, 0.12, 0.07), rust=0.6)
    ra.box("cart", (0.95, 1.0, 0.55), (0, -0.25, 0.5), cart, bevel=0.04)
    for x in (-0.5, 0.5):
        for y in (-0.6, 0.1):
            ra.cylinder("wheel", 0.15, 0.08, (x * 0.9, y, 0.17), steel, rotation=(0, math.radians(90), 0), verts=16)
    ore = rock("ore", (0.09, 0.07, 0.06))
    for k in range(7):
        a = k / 7 * math.tau
        o = ra.sphere("ore", 0.19, (math.cos(a) * 0.26, -0.25 + math.sin(a) * 0.28, 0.82), ore, segments=8)
        ra.displace(o, 0.06, 0.2, 1)
    ra.box("glint", (0.12, 0.12, 0.12), (0.12, -0.15, 0.95), ra.plain("glint", (0.75, 0.45, 0.15), 0.3, 0.8))
    # A timber headframe with its sheave wheel on top of the hill, seen from afar.
    for x in (-0.9, 0.9):
        ra.box("leg", (0.18, 0.18, 4.4), (x, 3.6, 3.3), timber, rotation=(0, x * math.radians(-9), 0))
    ra.box("brace", (2.0, 0.14, 0.14), (0, 3.6, 3.2), timber)
    ra.box("cap", (1.4, 0.4, 0.22), (0, 3.6, 5.45), timber)
    ra.torus("sheave", 0.55, 0.06, (0, 3.35, 5.6), steel, rotation=(math.radians(90), 0, 0))
    ra.cylinder("hub", 0.1, 0.2, (0, 3.35, 5.6), steel, rotation=(math.radians(90), 0, 0))
    ra.cylinder("lamp_post", 0.05, 2.4, (1.55, 0.7, 1.2), steel)
    ra.sphere("lamp", 0.16, (1.55, 0.7, 2.45), ra.emission("lamp", (1.0, 0.72, 0.4), 30.0), segments=10)
    ra.light("POINT", (1.4, 0.4, 2.3), 60, (1.0, 0.7, 0.4), size=0.2)
    return meshes()


def render_mine(layout: dict):
    w, h = 352, 384
    target = Vector((0, 3.0, 2.2))
    random.seed(zlib.crc32(b"mine"))
    layout["mine"] = render_sprite("mine", w, h, target, mine)


# --- Mountain industry ------------------------------------------------------------------------------
# Each stands on one tile: the drills next to a mine, the quarry in the mountains, the water wheel and
# the hydro plant by water. A cable station stands over a belt band (drawn by the client) with the
# cable's wheel on top, CABLE_TOP up, where the client hangs the rope.

CABLE_TOP = 2.3


def build_drill():
    """A mining drill: a yellow steel mast on a skid driving a bit into the rock, a motor at its foot,
    a short chute and a bin of ore beside it."""
    yellow = ra.rusty_metal("drill_yellow", (0.7, 0.45, 0.03), rust=0.25)
    dark = ra.rusty_metal("drill_dark", (0.06, 0.06, 0.07), rust=0.3)
    steel = ra.plain("drill_bit", (0.55, 0.55, 0.57), 0.25, 1.0, grime=0.3)
    ore = rock("drill_ore", (0.1, 0.08, 0.07))
    ra.box("drill_skid", (1.4, 1.1, 0.12), (0, 0, 0.06), dark, bevel=0.02)
    for x in (-0.25, 0.25):
        ra.box("drill_mast", (0.09, 0.09, 1.9), (x, 0.15, 1.05), yellow)
    for z in (0.6, 1.2, 1.8):
        ra.box("drill_rung", (0.6, 0.06, 0.06), (0, 0.15, z), yellow)
    ra.box("drill_head", (0.62, 0.4, 0.3), (0, 0.15, 1.45), yellow, bevel=0.03)
    ra.cylinder("drill_rod", 0.05, 1.5, (0, 0.15, 0.6), steel, verts=12)
    ra.cylinder("drill_tip", 0.12, 0.25, (0, 0.15, 0.14), steel, radius2=0.02, verts=12)
    ra.cylinder("drill_motor", 0.2, 0.42, (-0.45, -0.25, 0.35), dark, rotation=(0, math.radians(90), 0), verts=20)
    ra.box("drill_lamp", (0.06, 0.03, 0.06), (0.2, -0.06, 1.45), ra.emission("drill_lamp", (1.0, 0.55, 0.1), 4.0))
    ra.box("drill_chute", (0.2, 0.55, 0.06), (0.4, -0.25, 0.42), dark, rotation=(math.radians(-25), 0, 0))
    ra.box("drill_bin", (0.5, 0.45, 0.32), (0.4, -0.5, 0.28), dark, bevel=0.02)
    for k in range(6):
        a = k / 6 * math.tau
        o = ra.sphere("drill_ore", 0.09, (0.4 + math.cos(a) * 0.12, -0.5 + math.sin(a) * 0.1, 0.46), ore, segments=8)
        ra.displace(o, 0.03, 0.2, 1)


def build_heavy_drill():
    """The heavy drill: a taller red rig with a pneumatic hammer, braced legs, a compressor tank,
    a quartz-lit control box and a bigger ore bin."""
    red = ra.rusty_metal("hdrill_red", (0.45, 0.06, 0.03), rust=0.25)
    dark = ra.rusty_metal("hdrill_dark", (0.06, 0.06, 0.07), rust=0.3)
    steel = ra.plain("hdrill_bit", (0.55, 0.55, 0.57), 0.25, 1.0, grime=0.3)
    ore = rock("hdrill_ore", (0.1, 0.08, 0.07))
    ra.box("hdrill_base", (1.5, 1.2, 0.16), (0, 0, 0.08), dark, bevel=0.02)
    for x in (-0.32, 0.32):
        ra.box("hdrill_mast", (0.11, 0.11, 2.5), (x, 0.2, 1.4), red)
        ra.box("hdrill_brace", (0.07, 0.07, 1.2), (x * 1.7, 0.2, 0.62), red, rotation=(0, x * math.radians(-60), 0))
    for z in (0.7, 1.4, 2.1, 2.62):
        ra.box("hdrill_rung", (0.75, 0.07, 0.07), (0, 0.2, z), red)
    ra.box("hdrill_hammer", (0.5, 0.42, 0.55), (0, 0.2, 1.75), dark, bevel=0.04)
    ra.cylinder("hdrill_rod", 0.07, 1.6, (0, 0.2, 0.75), steel, verts=12)
    ra.cylinder("hdrill_tip", 0.15, 0.3, (0, 0.2, 0.17), steel, radius2=0.02, verts=12)
    ra.cylinder("hdrill_tank", 0.22, 0.7, (-0.45, -0.3, 0.42), red, rotation=(0, math.radians(90), 0), verts=20)
    ra.box("hdrill_box", (0.3, 0.2, 0.4), (-0.55, 0.45, 0.4), dark, bevel=0.02)
    ra.box("hdrill_light", (0.08, 0.03, 0.08), (-0.55, 0.34, 0.5), ra.emission("hdrill_light", (0.4, 0.8, 1.0), 4.0))
    ra.box("hdrill_bin", (0.6, 0.55, 0.38), (0.45, -0.45, 0.33), dark, bevel=0.02)
    for k in range(8):
        a = k / 8 * math.tau
        o = ra.sphere("hdrill_ore", 0.1, (0.45 + math.cos(a) * 0.15, -0.45 + math.sin(a) * 0.13, 0.55), ore, segments=8)
        ra.displace(o, 0.03, 0.2, 1)


def build_quarry():
    """A quarry: a stepped face of rock with fresh cuts, a wooden hand crane lifting a block, and cut
    stone stacked in front."""
    stone = rock("quarry_rock", (0.15, 0.145, 0.14))
    cut = ra.plain("quarry_cut", (0.32, 0.3, 0.28), 0.85, variation=0.2, bump=0.3)
    timber = ra.wood("quarry_timber", (0.15, 0.09, 0.05))
    rope = ra.plain("quarry_rope", (0.45, 0.35, 0.2), 0.9)
    face = ra.sphere("quarry_face", 1.0, (0, 0.45, 0.1), stone, scale=(0.95, 0.55, 0.75), segments=24)
    ra.displace(face, 0.12, 0.35, 2)
    for i, (w, z, y) in enumerate(((1.3, 0.12, -0.05), (0.9, 0.36, 0.1), (0.55, 0.6, 0.22))):
        ra.box("quarry_step", (w, 0.5, 0.24), (0, y, z), cut, bevel=0.02)
    for x, y in ((-0.55, -0.55), (-0.25, -0.6), (-0.4, -0.55)):
        ra.box("quarry_block", (0.26, 0.22, 0.2), (x, y, 0.1 + (0.2 if x == -0.4 else 0)), cut, bevel=0.015)
    # The crane: a mast with a jib swung over the face.
    ra.box("quarry_mast", (0.1, 0.1, 1.6), (0.6, -0.4, 0.8), timber)
    ra.box("quarry_jib", (0.9, 0.08, 0.08), (0.3, -0.25, 1.45), timber, rotation=(0, math.radians(-15), math.radians(25)))
    ra.box("quarry_strut", (0.06, 0.06, 0.8), (0.48, -0.36, 1.05), timber, rotation=(0, math.radians(-35), 0))
    ra.cylinder("quarry_line", 0.012, 0.7, (-0.05, -0.1, 1.15), rope, verts=6)
    ra.box("quarry_load", (0.26, 0.22, 0.2), (-0.05, -0.1, 0.75), cut, bevel=0.015)
    ra.cylinder("quarry_winch", 0.08, 0.3, (0.6, -0.55, 0.45), timber, rotation=(0, math.radians(90), 0), verts=12)


def build_crusher():
    """A jaw crusher: a green steel hopper on four legs over a heavy body, a flywheel and belt to its
    motor, and a heap of gravel under the chute."""
    green = ra.rusty_metal("crush_green", (0.07, 0.2, 0.08), rust=0.3)
    dark = ra.rusty_metal("crush_dark", (0.06, 0.06, 0.07), rust=0.3)
    gravel = rock("crush_gravel", (0.22, 0.21, 0.2))
    for x in (-0.38, 0.38):
        for y in (-0.15, 0.4):
            ra.box("crush_leg", (0.08, 0.08, 0.9), (x, y, 0.45), dark)
    ra.box("crush_body", (0.85, 0.65, 0.5), (0, 0.12, 0.95), green, bevel=0.03)
    v = [(-0.55, -0.25, 1.2), (0.55, -0.25, 1.2), (0.55, 0.5, 1.2), (-0.55, 0.5, 1.2),
         (-0.35, -0.1, 1.2), (0.35, -0.1, 1.2), (0.35, 0.35, 1.2), (-0.35, 0.35, 1.2)]
    top = [(x * 1.25, (y - 0.12) * 1.3 + 0.12, 1.6) for x, y, _ in v[:4]]
    ra.mesh_from("crush_hopper", top + v[:4], [(0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)], green)
    for k in range(9):
        ra.sphere("crush_stone", 0.08, (random.uniform(-0.4, 0.4), random.uniform(-0.1, 0.4), 1.25), gravel, segments=8)
    ra.box("crush_chute", (0.35, 0.5, 0.05), (0, -0.35, 0.6), dark, rotation=(math.radians(35), 0, 0))
    heap = ra.sphere("crush_heap", 0.38, (0, -0.65, 0.0), gravel, scale=(1.1, 0.9, 0.55), segments=16)
    ra.displace(heap, 0.04, 0.12, 2)
    ra.cylinder("crush_flywheel", 0.32, 0.06, (0.5, 0.1, 0.95), dark, rotation=(0, math.radians(90), 0), verts=28)
    ra.cylinder("crush_motor", 0.15, 0.32, (0.55, 0.5, 0.3), ra.rusty_metal("crush_motor", (0.05, 0.12, 0.35), rust=0.15),
                rotation=(0, math.radians(90), 0), verts=18)


def build_stonemason():
    """A stonemason's yard: a heavy timber bench with a block being dressed, a mallet and chisel, a
    slab of white marble leaning on it and dressed blocks beside."""
    timber = ra.wood("mason_timber", (0.2, 0.12, 0.06))
    stone = ra.plain("mason_stone", (0.34, 0.32, 0.3), 0.85, variation=0.2, bump=0.3)
    marble = ra.plain("mason_marble", (0.75, 0.74, 0.72), 0.3, variation=0.25, scale=3.0, grime=0.2, bump=0.05)
    steel = ra.rusty_metal("mason_steel", (0.35, 0.35, 0.37), rust=0.2)
    for x in (-0.5, 0.5):
        for y in (-0.22, 0.22):
            ra.box("mason_leg", (0.1, 0.1, 0.6), (x, y, 0.3), timber)
    ra.box("mason_top", (1.3, 0.6, 0.1), (0, 0, 0.65), timber, bevel=0.01)
    ra.box("mason_block", (0.4, 0.35, 0.3), (-0.15, 0, 0.85), stone, bevel=0.02)
    ra.cylinder("mason_mallet_handle", 0.02, 0.3, (0.3, -0.1, 0.73), timber, rotation=(0, math.radians(90), math.radians(30)), verts=8)
    ra.cylinder("mason_mallet", 0.06, 0.14, (0.42, -0.03, 0.75), timber, verts=12)
    ra.box("mason_chisel", (0.2, 0.02, 0.02), (0.15, 0.15, 0.71), steel, rotation=(0, 0, math.radians(-20)))
    ra.box("mason_slab", (0.7, 0.06, 0.55), (0.1, 0.42, 0.3), marble, rotation=(math.radians(-12), 0, 0))
    for x, z in ((-0.55, 0.12), (-0.25, 0.12), (-0.4, 0.34)):
        ra.box("mason_dressed", (0.28, 0.24, 0.22), (x, -0.55, z), stone, bevel=0.01)


def build_foundry():
    """A foundry: a round brick cupola with a glowing tap hole, a tall iron chimney, a crucible on a
    stand and ingot moulds cooling in front."""
    brick = ra.plain("found_brick", (0.3, 0.11, 0.06), 0.9, variation=0.35, scale=10, bump=0.5)
    iron = ra.rusty_metal("found_iron", (0.1, 0.1, 0.11), rust=0.35)
    glow = ra.emission("found_glow", (1.0, 0.4, 0.06), 6.0)
    bronze = ra.plain("found_bronze", (0.55, 0.32, 0.1), 0.35, 1.0, variation=0.15)
    ra.cylinder("found_cupola", 0.5, 1.2, (0, 0.15, 0.6), brick, verts=24)
    for z in (0.3, 0.9):
        ra.cylinder("found_band", 0.515, 0.06, (0, 0.15, z), iron, verts=24)
    ra.cylinder("found_cone", 0.5, 0.3, (0, 0.15, 1.35), brick, radius2=0.2, verts=24)
    ra.cylinder("found_chimney", 0.16, 1.1, (0, 0.15, 2.0), iron, verts=14)
    ra.cylinder("found_cap", 0.22, 0.06, (0, 0.15, 2.55), iron, verts=14)
    ra.box("found_tap", (0.18, 0.06, 0.14), (0, -0.36, 0.35), glow)
    ra.box("found_spout", (0.12, 0.3, 0.06), (0, -0.5, 0.28), iron, rotation=(math.radians(-15), 0, 0))
    ra.cylinder("found_crucible", 0.13, 0.18, (0.0, -0.75, 0.12), iron, verts=16)
    ra.cylinder("found_melt", 0.11, 0.01, (0.0, -0.75, 0.21), glow, verts=16)
    for k, x in enumerate((0.45, 0.62)):
        ra.box("found_mould", (0.14, 0.35, 0.06), (x, -0.45, 0.03), iron)
        ra.box("found_ingot", (0.1, 0.3, 0.04), (x, -0.45, 0.07), bronze if k == 0 else glow)
    ra.box("found_coal", (0.35, 0.3, 0.12), (-0.55, -0.35, 0.06), ra.plain("found_coal", (0.02, 0.02, 0.02), 0.7))


def water_mat(name):
    return ra.plain(name, (0.04, 0.14, 0.22), 0.05, variation=0.15, scale=4.0, grime=0.0, bump=0.3)


def build_water_wheel():
    """A water wheel: a wooden flume pouring onto a big paddled wheel turning a small dynamo shed,
    water running out below and a copper terminal for the pole's wire."""
    timber = ra.wood("wheel_timber", (0.17, 0.1, 0.05))
    dark = ra.wood("wheel_dark", (0.09, 0.055, 0.03))
    iron = ra.rusty_metal("wheel_iron", (0.1, 0.1, 0.11), rust=0.35)
    water = water_mat("wheel_water")
    copper = ra.plain("wheel_copper", (0.65, 0.28, 0.12), 0.35, 0.9, variation=0.15)
    ra.box("wheel_pool", (1.6, 1.2, 0.04), (0, 0, 0.02), water)
    # The wheel turns across the view, its axle running north into the shed's side.
    for e in (-1, 1):
        ra.torus("wheel_rim", 0.62, 0.04, (-0.2, 0.05 + e * 0.13, 0.75), dark, rotation=(math.radians(90), 0, 0))
    for k in range(12):
        a = k / 12 * math.tau
        ra.box("wheel_paddle", (0.22, 0.3, 0.03), (-0.2 + math.cos(a) * 0.6, 0.05, 0.75 + math.sin(a) * 0.6), timber,
               rotation=(0, -a + math.pi / 2, 0))
    for k in range(4):
        ra.box("wheel_spoke", (1.2, 0.04, 0.04), (-0.2, 0.05, 0.75), dark, rotation=(0, k * math.pi / 4, 0))
    ra.cylinder("wheel_axle", 0.06, 0.7, (-0.2, 0.3, 0.75), iron, rotation=(math.radians(90), 0, 0), verts=12)
    # The flume on trestles, pouring onto the top of the wheel from behind.
    ra.box("wheel_flume", (0.34, 0.9, 0.12), (-0.2, 0.75, 1.48), timber)
    ra.box("wheel_flow", (0.28, 0.88, 0.02), (-0.2, 0.75, 1.53), water)
    ra.box("wheel_fall", (0.24, 0.05, 0.25), (-0.2, 0.28, 1.4), water, rotation=(math.radians(20), 0, 0))
    for y in (0.6, 1.05):
        ra.box("wheel_trestle", (0.06, 0.06, 1.45), (-0.2, y, 0.72), dark)
    ra.box("wheel_shed", (0.45, 0.6, 0.6), (0.6, 0.25, 0.3), timber, bevel=0.01)
    ra.box("wheel_roof", (0.55, 0.7, 0.05), (0.6, 0.25, 0.63), iron)
    ra.cylinder("wheel_terminal", 0.04, 0.22, (0.7, 0.05, 0.75), copper, verts=10)
    ra.sphere("wheel_insulator", 0.05, (0.7, 0.05, 0.88), ra.plain("wheel_porcelain", (0.75, 0.72, 0.65), 0.3), segments=10)


def build_hydro_plant():
    """A small hydro power plant: a concrete turbine house with a big steel penstock coming down to it,
    white water foaming out of the tailrace, a transformer and its insulators on the roof."""
    concrete = ra.plain("hydro_concrete", (0.36, 0.35, 0.33), 0.9, variation=0.15)
    steel = ra.rusty_metal("hydro_steel", (0.2, 0.22, 0.24), rust=0.25)
    green = ra.rusty_metal("hydro_green", (0.06, 0.17, 0.1), rust=0.2)
    water = water_mat("hydro_water")
    foam = ra.plain("hydro_foam", (0.75, 0.8, 0.85), 0.4, variation=0.2)
    porcelain = ra.plain("hydro_porcelain", (0.75, 0.72, 0.65), 0.3)
    ra.box("hydro_house", (1.2, 0.85, 0.85), (0, 0.15, 0.43), concrete, bevel=0.02)
    ra.box("hydro_roof", (1.3, 0.95, 0.06), (0, 0.15, 0.88), steel)
    for x in (-0.3, 0.3):
        ra.box("hydro_window", (0.22, 0.02, 0.3), (x, -0.28, 0.5), ra.emission("hydro_window", (1.0, 0.8, 0.5), 2.0))
    ra.cylinder("hydro_penstock", 0.17, 1.6, (-0.3, 0.75, 1.1), steel, rotation=(math.radians(-50), 0, 0), verts=20)
    for t in (0.3, 0.75):
        ra.cylinder("hydro_ring", 0.185, 0.05, (-0.3, 0.5 + t * 0.6, 0.55 + t * 0.95), steel, rotation=(math.radians(-50), 0, 0), verts=20)
    ra.box("hydro_race", (0.5, 0.7, 0.04), (0.35, -0.55, 0.02), water)
    for k in range(6):
        ra.sphere("hydro_foam", random.uniform(0.06, 0.1), (0.35 + random.uniform(-0.15, 0.15), -0.32 - k * 0.08, 0.05), foam,
                  scale=(1.2, 1, 0.5), segments=8)
    ra.box("hydro_transformer", (0.35, 0.3, 0.35), (0.4, 0.3, 1.08), green, bevel=0.02)
    for x in (0.3, 0.5):
        ra.cylinder("hydro_insulator", 0.04, 0.22, (x, 0.3, 1.35), porcelain, verts=10)


def build_cable_station():
    """A cable station: a steel lattice tower astride the belt with a big bull wheel on top, its rope
    running off towards the next station, and a little gondola hanging at the platform."""
    steel = ra.rusty_metal("cable_steel", (0.2, 0.2, 0.22), rust=0.3)
    red = ra.rusty_metal("cable_red", (0.45, 0.05, 0.03), rust=0.2)
    dark = ra.rusty_metal("cable_dark", (0.06, 0.06, 0.07), rust=0.3)
    for x in (-0.55, 0.55):
        for y in (-0.55, 0.55):
            ra.box("cable_leg", (0.07, 0.07, CABLE_TOP - 0.1), (x * 0.85, y * 0.85, (CABLE_TOP - 0.1) / 2), steel,
                   rotation=(y * math.radians(-6), x * math.radians(6), 0))
    for z in (0.9, 1.6):
        for y in (-0.47, 0.47):
            ra.box("cable_brace", (1.0, 0.05, 0.05), (0, y, z), steel)
        for x in (-0.47, 0.47):
            ra.box("cable_brace", (0.05, 1.0, 0.05), (x, 0, z), steel)
    ra.box("cable_deck", (1.0, 1.0, 0.06), (0, 0, CABLE_TOP - 0.15), dark)
    ra.torus("cable_wheel", 0.42, 0.04, (0, 0, CABLE_TOP), red)
    for k in range(3):
        ra.box("cable_spoke", (0.84, 0.04, 0.03), (0, 0, CABLE_TOP), red, rotation=(0, 0, k * math.pi / 3))
    ra.cylinder("cable_hub", 0.08, 0.18, (0, 0, CABLE_TOP), dark, verts=12)
    ra.box("cable_hanger", (0.03, 0.03, 0.35), (0.42, 0, CABLE_TOP - 0.2), dark)
    ra.box("cable_gondola", (0.32, 0.26, 0.2), (0.42, 0, CABLE_TOP - 0.45), red, bevel=0.02)


MOUNTAIN = {
    # name: (canvas width, height, camera target height, builder); each stands on one tile.
    "drill": (112, 152, 0.9, build_drill),
    "heavy_drill": (112, 176, 1.15, build_heavy_drill),
    "quarry": (112, 120, 0.6, build_quarry),
    "crusher": (112, 136, 0.75, build_crusher),
    "stonemason": (112, 112, 0.5, build_stonemason),
    "foundry": (112, 168, 1.1, build_foundry),
}


def render_mountain(layout: dict, only=()):
    for name, (w, h, tz, build) in MOUNTAIN.items():
        if only and name not in only:
            continue
        random.seed(zlib.crc32(name.encode()))
        layout[name] = render_sprite(name, w, h, Vector((0, 0, tz)), crafted(build))
        ra.icon_from(Image.open(OUT / f"{name}.png").convert("RGBA"), ICONS / f"furniture_{name}.png")
    if not only or "cable_station" in only:
        random.seed(zlib.crc32(b"cable_station"))
        layout["cable_station"] = render_sprite("cable_station", 80, 160, Vector((0, 0, 1.15)), crafted(build_cable_station))
        ra.icon_from(Image.open(OUT / "cable_station.png").convert("RGBA"), ICONS / "item_logistics_cable_station.png")


# --- Coast -----------------------------------------------------------------------------------------

def fish(name, length, color, belly, at=(0, 0, 0), heading=0.0, mat=None):
    """A fish lying on its side: a long squashed body, a tail fin and a dark eye; `heading` turns it on the ground."""
    skin = mat or ra.plain(name, color, 0.25, 0.3, variation=0.2, scale=14, grime=0.1)
    under = ra.plain(name + "_belly", belly, 0.3, 0.2, variation=0.1, grime=0.05)
    c, s = math.cos(heading), math.sin(heading)
    x, y, z = at
    r = length * 0.5
    ra.sphere(name, r, (x, y, z + length * 0.09), skin, scale=(1, 0.22, 0.32), segments=20).rotation_euler = (0, 0, heading)
    ra.sphere(name + "_belly", r * 0.85, (x, y, z + length * 0.06), under, scale=(1, 0.2, 0.22), segments=16).rotation_euler = (0, 0, heading)
    ra.box(name + "_tail", (length * 0.2, length * 0.03, length * 0.24), (x - c * r * 1.05, y - s * r * 1.05, z + length * 0.09), skin,
           rotation=(0, 0, heading))
    ra.sphere(name + "_eye", length * 0.035, (x + c * r * 0.72 - s * length * 0.1, y + s * r * 0.72 + c * length * 0.1, z + length * 0.12),
              ra.plain("eye", (0.01, 0.01, 0.01), 0.1), segments=8)


def hull(name, length, beam, depth, at, paint, timber, heading=0.0):
    """A wooden boat's hull: a squashed half sphere with a painted band, open on top, and a few thwarts."""
    x, y, z = at
    h = ra.sphere(name, length / 2, (x, y, z + depth), timber, scale=(1, beam / length, depth / (length / 2) * 1.6), segments=24,
                  keep=lambda co: co.z <= 0.0)
    h.rotation_euler = (0, 0, heading)
    band = ra.sphere(name + "_band", length / 2 * 1.01, (x, y, z + depth), paint, scale=(1, beam / length, 0.12), segments=24,
                     keep=lambda co: co.z <= 0.0)
    band.rotation_euler = (0, 0, heading)
    c, s = math.cos(heading), math.sin(heading)
    for t in (-0.2, 0.15):
        ra.box(name + "_thwart", (0.05, beam * 0.85, 0.03), (x + c * t * length, y + s * t * length, z + depth * 0.85), timber,
               rotation=(0, 0, heading))
    return h


def slipway(timber, dark, width=1.5):
    """Planks laid down the shore into the water, on which a boat is pulled up."""
    water = water_mat("slip_water")
    ra.box("slip_water", (1.9, 0.9, 0.02), (0, 0.55, 0.01), water)
    for k in range(5):
        ra.box("slip_plank", (width, 0.16, 0.04), (0, -0.55 + k * 0.22, 0.03), timber if k % 2 else dark, bevel=0.01)


def build_fishing_boat():
    """A fishing cutter moored at a short jetty: a blue hull with a white wheelhouse, a mast with a net boom
    and floats, a crate of fish on the planks."""
    timber = ra.wood("boat_timber", (0.2, 0.12, 0.06))
    dark = ra.wood("boat_dark", (0.1, 0.06, 0.035))
    blue = ra.plain("boat_blue", (0.04, 0.12, 0.3), 0.4, variation=0.15)
    white = ra.plain("boat_white", (0.7, 0.7, 0.66), 0.5, variation=0.1)
    red = ra.plain("boat_red", (0.55, 0.06, 0.03), 0.5)
    slipway(timber, dark)
    hull("boat_hull", 1.7, 0.6, 0.32, (0, 0.35, 0.02), white, blue)
    ra.box("boat_house", (0.4, 0.38, 0.35), (-0.25, 0.35, 0.5), white, bevel=0.02)
    ra.box("boat_house_roof", (0.46, 0.44, 0.04), (-0.25, 0.35, 0.69), blue)
    ra.box("boat_window", (0.02, 0.26, 0.12), (-0.04, 0.35, 0.56), ra.emission("boat_window", (1.0, 0.8, 0.5), 1.5))
    ra.cylinder("boat_mast", 0.025, 1.2, (0.25, 0.35, 0.85), dark, verts=8)
    ra.cylinder("boat_boom", 0.018, 0.8, (0.55, 0.35, 0.75), dark, rotation=(0, math.radians(70), 0), verts=8)
    net = ra.plain("boat_net", (0.15, 0.2, 0.12), 0.9, variation=0.3, bump=0.8)
    ra.sphere("boat_net", 0.16, (0.55, 0.35, 0.35), net, scale=(1.2, 0.8, 0.6), segments=10)
    for k in range(4):
        ra.sphere("boat_float", 0.04, (0.35 + k * 0.1, 0.12, 0.3), red, segments=8)
    ra.box("boat_crate", (0.3, 0.22, 0.12), (0.4, -0.55, 0.11), timber, bevel=0.01)
    for k in range(3):
        fish(f"boat_fish{k}", 0.2, (0.35, 0.4, 0.45), (0.75, 0.75, 0.72), (0.32 + k * 0.08, -0.55, 0.15), 0.3 * k)


def build_rowing_boat():
    """A rowing boat pulled up on planks by the lake: varnished hull, two oars across it and a rod leaning on the bow."""
    timber = ra.wood("row_timber", (0.24, 0.14, 0.07))
    dark = ra.wood("row_dark", (0.1, 0.06, 0.035))
    green = ra.plain("row_green", (0.06, 0.2, 0.1), 0.5)
    slipway(timber, dark, 1.3)
    hull("row_hull", 1.4, 0.55, 0.22, (0, 0.2, 0.02), green, timber, heading=math.radians(15))
    for e in (-1, 1):
        ra.cylinder("row_oar", 0.02, 1.1, (0.05, 0.2 + e * 0.12, 0.3), dark, rotation=(0, math.radians(90), math.radians(15 + e * 8)), verts=8)
        ra.box("row_blade", (0.22, 0.08, 0.015), (0.62, 0.32 + e * 0.12, 0.3), dark, rotation=(0, 0, math.radians(15)))
    ra.cylinder("row_rod", 0.01, 1.0, (-0.45, -0.1, 0.45), dark, rotation=(math.radians(30), math.radians(-20), 0), verts=6)


def build_smokehouse():
    """A smokehouse: a dark tarred plank shed with a stone fire pit at its foot, smoke curling from a vent on
    the roof and fish hung on a rack in front."""
    tar = ra.wood("smoke_tar", (0.05, 0.035, 0.025))
    stone = rock("smoke_stone", (0.16, 0.15, 0.14))
    timber = ra.wood("smoke_timber", (0.18, 0.11, 0.05))
    smoke = ra.plain("smoke", (0.35, 0.35, 0.37), 0.9, variation=0.3, grime=0.0)
    fire = ra.emission("smoke_fire", (1.0, 0.45, 0.1), 6.0)
    ra.box("smoke_shed", (0.9, 0.8, 0.95), (0, 0.25, 0.48), tar, bevel=0.01)
    gable_roof("smoke_roof", 1.0, 0.9, 0.95, 1.3, timber, at=(0, 0.25))
    gable_ends("smoke_gable", 0.9, 0.8, 0.95, 1.3, tar, at=(0, 0.25))
    ra.box("smoke_vent", (0.2, 0.2, 0.18), (0, 0.25, 1.38), timber)
    for k in range(4):
        ra.sphere("smoke_puff", 0.1 + k * 0.035, (0.06 * k, 0.25 + 0.05 * k, 1.55 + k * 0.17), smoke, segments=10)
    ra.box("smoke_door", (0.35, 0.02, 0.6), (0, -0.16, 0.3), timber)
    pit = ra.cylinder("smoke_pit", 0.2, 0.12, (0.55, -0.45, 0.06), stone, verts=12)
    ra.displace(pit, 0.02, 0.2, 1)
    ra.sphere("smoke_glow", 0.1, (0.55, -0.45, 0.12), fire, scale=(1, 1, 0.5), segments=10)
    ra.box("smoke_rack", (0.7, 0.03, 0.03), (-0.3, -0.5, 0.65), timber)
    for x in (-0.62, 0.02):
        ra.box("smoke_post", (0.04, 0.04, 0.65), (x, -0.5, 0.33), timber)
    gold = ra.plain("smoke_fish", (0.45, 0.25, 0.06), 0.35, 0.2)
    for k in range(4):
        ra.sphere("smoke_hung", 0.13, (-0.52 + k * 0.15, -0.5, 0.48), gold, scale=(0.25, 0.12, 1), segments=10)


def build_cannery():
    """A fish cannery: a pale brick hall with a sawtooth roof, a steam stack, a conveyor of cans coming out of
    its side and a stack of crates."""
    brick = ra.plain("can_brick", (0.42, 0.32, 0.26), 0.85, variation=0.2, bump=0.4)
    steel = ra.rusty_metal("can_steel", (0.3, 0.32, 0.34), rust=0.2)
    tin = ra.plain("can_tin", (0.7, 0.72, 0.74), 0.25, 1.0, variation=0.1)
    label = ra.plain("can_label", (0.1, 0.25, 0.55), 0.5)
    timber = ra.wood("can_timber", (0.2, 0.12, 0.06))
    steam = ra.plain("can_steam", (0.7, 0.72, 0.75), 0.9, variation=0.2, grime=0.0)
    ra.box("can_hall", (1.4, 1.0, 0.8), (0, 0.2, 0.4), brick, bevel=0.01)
    for k in range(3):
        ra.box("can_tooth", (0.47, 1.05, 0.05), (-0.47 + k * 0.47, 0.2, 0.9), steel, rotation=(0, math.radians(-25), 0))
        ra.box("can_glass", (0.02, 1.0, 0.18), (-0.27 + k * 0.47, 0.2, 0.9), ra.emission("can_glass", (1.0, 0.85, 0.6), 1.2))
    ra.cylinder("can_stack", 0.08, 0.9, (0.5, 0.55, 1.2), steel, verts=14)
    for k in range(3):
        ra.sphere("can_puff", 0.1 + 0.04 * k, (0.5 + 0.05 * k, 0.6, 1.75 + 0.15 * k), steam, segments=10)
    ra.box("can_belt", (0.7, 0.2, 0.05), (0.85, -0.45, 0.3), ra.plain("can_rubber", (0.03, 0.03, 0.03), 0.7))
    for k in range(5):
        ra.cylinder("can", 0.04, 0.07, (0.6 + k * 0.12, -0.45, 0.36), tin, verts=12)
        ra.cylinder("can_label", 0.041, 0.035, (0.6 + k * 0.12, -0.45, 0.36), label, verts=12)
    for k in range(2):
        ra.box("can_crate", (0.28, 0.24, 0.18), (-0.55, -0.5, 0.09 + k * 0.19), timber, bevel=0.01)


def build_salt_pan():
    """Salt pans on the sea shore: shallow square basins of brine edged with planks, white salt drying in the
    nearest, a heap of it and a wooden rake."""
    timber = ra.wood("salt_timber", (0.2, 0.13, 0.07))
    brine = ra.plain("salt_brine", (0.18, 0.32, 0.38), 0.05, variation=0.2, grime=0.0)
    salt = ra.plain("salt_white", (0.85, 0.85, 0.82), 0.7, variation=0.1, bump=0.6)
    for i, (x, y) in enumerate(((-0.45, 0.4), (0.45, 0.4), (-0.45, -0.4), (0.45, -0.4))):
        ra.box("salt_basin", (0.8, 0.7, 0.03), (x, y, 0.015), salt if i == 2 else brine)
        for e in (-1, 1):
            ra.box("salt_edge", (0.84, 0.04, 0.07), (x, y + e * 0.37, 0.035), timber)
            ra.box("salt_edge", (0.04, 0.74, 0.07), (x + e * 0.42, y, 0.035), timber)
    pile = ra.sphere("salt_heap", 0.22, (0.45, -0.4, 0.04), salt, scale=(1, 1, 0.9), segments=16)
    ra.displace(pile, 0.03, 0.2, 1)
    ra.cylinder("salt_rake", 0.015, 0.9, (0.0, -0.05, 0.12), timber, rotation=(0, math.radians(80), math.radians(30)), verts=6)


def build_fish_farm():
    """A fish farm by the shore: two round net pens floating on the water, joined by a plank walkway, with a
    feed bin on the bank."""
    water = water_mat("farm_water")
    float_m = ra.plain("farm_float", (0.05, 0.05, 0.06), 0.4)
    net = ra.plain("farm_net", (0.12, 0.16, 0.14), 0.9, variation=0.3)
    timber = ra.wood("farm_timber", (0.2, 0.13, 0.07))
    yellow = ra.plain("farm_bin", (0.7, 0.5, 0.05), 0.5)
    ra.box("farm_water", (1.9, 1.3, 0.02), (0, 0.3, 0.01), water)
    for x in (-0.45, 0.45):
        ra.torus("farm_ring", 0.38, 0.04, (x, 0.35, 0.05), float_m)
        ra.torus("farm_rail", 0.38, 0.015, (x, 0.35, 0.22), float_m)
        for k in range(8):
            a = k / 8 * math.tau
            ra.box("farm_stanchion", (0.02, 0.02, 0.17), (x + math.cos(a) * 0.38, 0.35 + math.sin(a) * 0.38, 0.14), float_m)
        ra.cylinder("farm_net", 0.36, 0.02, (x, 0.35, 0.03), net, verts=24)
        for k in range(3):
            fish(f"farm_fish{x}{k}", 0.14, (0.5, 0.3, 0.3), (0.8, 0.6, 0.55),
                 (x + random.uniform(-0.2, 0.2), 0.35 + random.uniform(-0.2, 0.2), 0.03), random.random() * math.tau)
    ra.box("farm_walk", (0.5, 0.18, 0.04), (0, 0.35, 0.07), timber)
    ra.box("farm_pier", (0.18, 0.7, 0.04), (0, -0.1, 0.07), timber)
    ra.cylinder("farm_bin", 0.14, 0.35, (0.45, -0.55, 0.18), yellow, verts=16)
    ra.cylinder("farm_lid", 0.15, 0.03, (0.45, -0.55, 0.37), float_m, verts=16)


def build_shipyard():
    """A small shipyard: a hull in its ribs on a cradle of timbers sliding down to the water, a gantry with a
    block and tackle over it, and planks stacked by."""
    timber = ra.wood("yard_timber", (0.22, 0.13, 0.06))
    dark = ra.wood("yard_dark", (0.09, 0.055, 0.03))
    iron = ra.rusty_metal("yard_iron", (0.12, 0.12, 0.13), rust=0.4)
    slipway(timber, dark, 1.7)
    ra.box("yard_keel", (1.5, 0.08, 0.08), (0, 0.15, 0.12), dark)
    for k in range(7):
        x = -0.6 + k * 0.2
        r = 0.32 * math.sin(math.pi * (k + 1) / 8) + 0.06
        ra.torus("yard_rib", r, 0.02, (x, 0.15, 0.12 + r * 0.6), timber, rotation=(0, math.radians(90), 0)).scale = (1, 1, 0.5)
    for x in (-0.8, 0.8):
        for y in (-0.25, 0.55):
            ra.box("yard_post", (0.07, 0.07, 1.25), (x, y, 0.62), dark)
    for y in (-0.25, 0.55):
        ra.box("yard_beam", (1.7, 0.07, 0.07), (0, y, 1.25), dark)
    ra.box("yard_cross", (0.08, 0.86, 0.08), (0.2, 0.15, 1.3), iron)
    ra.box("yard_rope", (0.015, 0.015, 0.5), (0.2, 0.15, 1.0), ra.plain("yard_rope", (0.5, 0.42, 0.28), 0.9))
    ra.box("yard_block", (0.08, 0.06, 0.1), (0.2, 0.15, 0.72), iron)
    for k in range(3):
        ra.box("yard_plank", (0.9, 0.16, 0.035), (-0.3, -0.7, 0.02 + k * 0.04), timber, rotation=(0, 0, 0.04 * k))


def build_port():
    """A port: a stone quay with bollards along its edge, a crane leaning over the water, a stack of crates and a
    lamp post."""
    stone = ra.plain("port_stone", (0.24, 0.23, 0.22), 0.9, variation=0.2, bump=0.4)
    water = water_mat("port_water")
    iron = ra.rusty_metal("port_iron", (0.08, 0.08, 0.09), rust=0.3)
    yellow = ra.rusty_metal("port_yellow", (0.65, 0.42, 0.04), rust=0.25)
    timber = ra.wood("port_timber", (0.2, 0.12, 0.06))
    ra.box("port_water", (1.9, 0.7, 0.02), (0, 0.65, 0.01), water)
    ra.box("port_quay", (1.9, 1.3, 0.28), (0, -0.3, 0.14), stone, bevel=0.02)
    for x in (-0.7, 0.0, 0.7):
        ra.cylinder("port_bollard", 0.06, 0.14, (x, 0.28, 0.35), iron, verts=12)
        ra.cylinder("port_cap", 0.08, 0.03, (x, 0.28, 0.43), iron, verts=12)
    ra.box("port_crane_base", (0.35, 0.35, 0.3), (0.55, -0.3, 0.43), yellow)
    ra.cylinder("port_crane_mast", 0.06, 1.1, (0.55, -0.3, 1.1), yellow, verts=10)
    ra.cylinder("port_jib", 0.04, 1.0, (0.55, 0.1, 1.5), yellow, rotation=(math.radians(-60), 0, 0), verts=8)
    ra.box("port_hook_rope", (0.01, 0.01, 0.6), (0.55, 0.52, 1.45), iron)
    ra.box("port_hook_crate", (0.22, 0.22, 0.18), (0.55, 0.52, 1.08), timber, bevel=0.01)
    for k, (x, y, z) in enumerate(((-0.55, -0.45, 0.39), (-0.3, -0.45, 0.39), (-0.42, -0.45, 0.6))):
        ra.box("port_crate", (0.22, 0.22, 0.2), (x, y, z), timber if k != 2 else ra.rusty_metal("port_blue", (0.05, 0.15, 0.35), rust=0.2), bevel=0.01)
    ra.cylinder("port_lamp_post", 0.02, 0.9, (-0.8, -0.8, 0.73), iron, verts=8)
    ra.sphere("port_lamp", 0.05, (-0.8, -0.8, 1.2), ra.emission("port_lamp", (1.0, 0.8, 0.5), 5.0), segments=10)


def build_breakwater():
    """A breakwater: a long mound of grey boulders and concrete blocks running out into the water, foam on its
    seaward side."""
    water = water_mat("break_water")
    foam = ra.plain("break_foam", (0.75, 0.8, 0.85), 0.4, variation=0.2)
    concrete = ra.plain("break_concrete", (0.4, 0.39, 0.37), 0.9, variation=0.15)
    ra.box("break_water", (1.9, 1.3, 0.02), (0, 0.35, 0.01), water)
    for k in range(9):
        y = -0.65 + k * 0.17
        for x in (-0.15, 0.15):
            b = ra.sphere("break_rock", random.uniform(0.14, 0.2), (x + random.uniform(-0.05, 0.05), y, 0.08), rock("break_rock", (0.15, 0.145, 0.14)),
                          scale=(1, 1, 0.75), segments=10)
            ra.displace(b, 0.04, 0.3, 1)
    for k in range(3):
        ra.box("break_block", (0.22, 0.22, 0.2), (0, 0.1 + k * 0.25, 0.25), concrete, bevel=0.02, rotation=(0.2 * k, 0.3, 0.5 * k))
    for k in range(7):
        ra.sphere("break_foam", random.uniform(0.05, 0.09), (0.32 + random.uniform(-0.04, 0.04), 0.0 + k * 0.12, 0.04), foam,
                  scale=(1.3, 1, 0.4), segments=8)


def build_lighthouse():
    """A lighthouse: a tall white tower with red bands on a stone base, a glowing lantern room under a dark cap
    and a gallery rail."""
    white = ra.plain("light_white", (0.75, 0.74, 0.7), 0.6, variation=0.08)
    red = ra.plain("light_red", (0.55, 0.05, 0.03), 0.5, variation=0.1)
    stone = rock("light_stone", (0.16, 0.15, 0.14))
    dark = ra.rusty_metal("light_dark", (0.05, 0.06, 0.06), rust=0.2)
    glow = ra.emission("light_glow", (1.0, 0.9, 0.6), 12.0)
    base = ra.cylinder("light_base", 0.55, 0.3, (0, 0, 0.15), stone, verts=16)
    ra.displace(base, 0.02, 0.2, 1)
    ra.cylinder("light_tower", 0.4, 2.6, (0, 0, 1.6), white, radius2=0.26, verts=24)
    for z in (0.9, 1.8, 2.6):
        r = 0.4 - (z - 0.3) / 2.6 * 0.14
        ra.cylinder("light_band", r + 0.01, 0.3, (0, 0, z), red, radius2=r - 0.006, verts=24)
    ra.cylinder("light_gallery", 0.36, 0.05, (0, 0, 2.93), dark, verts=24)
    ra.torus("light_rail", 0.35, 0.012, (0, 0, 3.08), dark)
    ra.cylinder("light_lantern", 0.2, 0.32, (0, 0, 3.12), glow, verts=16)
    ra.cylinder("light_cap", 0.24, 0.2, (0, 0, 3.38), dark, radius2=0.04, verts=16)
    ra.box("light_door", (0.2, 0.02, 0.4), (0, -0.4, 0.5), dark)


def build_tidal_plant():
    """A tidal power plant: a concrete barrage running into the sea with two turbine housings under it, water
    churning white where it pours through, a control house and a transformer on top."""
    concrete = ra.plain("tidal_concrete", (0.36, 0.35, 0.33), 0.9, variation=0.15)
    steel = ra.rusty_metal("tidal_steel", (0.2, 0.22, 0.24), rust=0.25)
    green = ra.rusty_metal("tidal_green", (0.06, 0.17, 0.1), rust=0.2)
    water = water_mat("tidal_water")
    foam = ra.plain("tidal_foam", (0.75, 0.8, 0.85), 0.4, variation=0.2)
    porcelain = ra.plain("tidal_porcelain", (0.75, 0.72, 0.65), 0.3)
    ra.box("tidal_water", (1.9, 1.2, 0.02), (0, 0.4, 0.01), water)
    ra.box("tidal_dam", (0.6, 1.8, 0.45), (0, 0, 0.22), concrete, bevel=0.02)
    for y in (0.2, 0.6):
        ra.cylinder("tidal_turbine", 0.15, 0.7, (0, y, 0.15), steel, rotation=(0, math.radians(90), 0), verts=16)
        for side in (-1, 1):
            for k in range(4):
                ra.sphere("tidal_foam", random.uniform(0.05, 0.09), (side * (0.38 + k * 0.08), y + random.uniform(-0.08, 0.08), 0.04), foam,
                          scale=(1.3, 1, 0.4), segments=8)
    ra.box("tidal_house", (0.5, 0.55, 0.45), (0, -0.55, 0.67), concrete, bevel=0.02)
    ra.box("tidal_roof", (0.56, 0.6, 0.05), (0, -0.55, 0.92), steel)
    ra.box("tidal_window", (0.02, 0.3, 0.15), (0.26, -0.55, 0.72), ra.emission("tidal_window", (1.0, 0.8, 0.5), 2.0))
    ra.box("tidal_transformer", (0.3, 0.3, 0.3), (0, 0.0, 0.6), green, bevel=0.02)
    for x in (-0.08, 0.08):
        ra.cylinder("tidal_insulator", 0.035, 0.2, (x, 0.0, 0.85), porcelain, verts=10)


def flotsam(kind):
    """What the sea threw up on the beach: a bleached log with weed, a heap of kelp, or a crate and a bottle."""
    def build():
        weed = ra.plain("flot_weed", (0.06, 0.12, 0.04), 0.4, variation=0.3, bump=0.6)
        if kind == 0:
            log = ra.cylinder("flot_log", 0.12, 1.0, (0, 0, 0.1), ra.wood("flot_bleached", (0.35, 0.3, 0.24)),
                              rotation=(0, math.radians(90), math.radians(25)), verts=12)
            ra.displace(log, 0.02, 0.3, 1)
        if kind in (0, 1):
            for k in range(5 if kind else 3):
                s = ra.sphere("flot_weed", random.uniform(0.1, 0.18), (random.uniform(-0.35, 0.35), random.uniform(-0.25, 0.25), 0.03), weed,
                              scale=(1.4, 1, 0.3), segments=10)
                ra.displace(s, 0.03, 0.2, 1)
        if kind == 2:
            ra.box("flot_crate", (0.4, 0.32, 0.26), (-0.1, 0, 0.11), ra.wood("flot_crate", (0.25, 0.17, 0.09)), bevel=0.02,
                   rotation=(0.15, 0.1, 0.5))
            glass = ra.plain("flot_glass", (0.1, 0.3, 0.12), 0.05, variation=0.05, grime=0.1)
            ra.cylinder("flot_bottle", 0.05, 0.22, (0.32, -0.12, 0.05), glass, rotation=(0, math.radians(90), 0.6), verts=12)
            ra.sphere("flot_amber", 0.05, (0.15, -0.25, 0.03), ra.plain("flot_amber", (0.85, 0.4, 0.03), 0.1, variation=0.2), segments=10)
        return meshes()
    return build


def render_water_tile():
    """One tile of sea seen from above, squashed to the 45° view: dark blue with glints, seamless so the tiles meet."""
    scene = outdoor_scene(256, 256, Vector((0, 0, 0)), samples=48, pitch=math.radians(90))
    scene.render.film_transparent = False
    m = ra.Mat("sea")
    wave = m.node("ShaderNodeTexWave", wave_type="BANDS", bands_direction="X")
    wave.inputs["Scale"].default_value = 1.2
    wave.inputs["Distortion"].default_value = 4.0
    wave.inputs["Detail"].default_value = 3.0
    m.link(m.coord.outputs["Object"], wave.inputs["Vector"])
    col = m.ramp(wave.outputs["Fac"], [(0.0, (0.02, 0.07, 0.12)), (0.7, (0.035, 0.12, 0.19)), (1.0, (0.12, 0.25, 0.32))]).outputs["Color"]
    ra.box("sea", (24, 24, 0.02), (0, 0, -0.01), m.done(col, 0.15, 0.0, wave.outputs["Fac"], 0.4))
    ra.render(TMP / "water_big.png")
    tile = (round(TILE_M * PPM), round(TILE_M * PPM * math.sin(PITCH)))
    seamless(Image.open(TMP / "water_big.png").convert("RGBA")).resize(tile, Image.LANCZOS).save(OUT / "water.png", optimize=True)
    print("sprite water")
    return {"anchorX": tile[0] // 2, "anchorY": tile[1] // 2}


def seaward(build):
    """The water of these lies to the south of the shore, in front: the model, built with the water behind it,
    is mirrored north to south."""
    def make():
        build()
        for o in meshes():
            o.location.y = -o.location.y
            o.rotation_euler.x, o.rotation_euler.z = -o.rotation_euler.x, -o.rotation_euler.z
            o.scale.y = -o.scale.y
        return meshes()
    return make


COAST = {
    # name: (canvas width, height, camera target height, builder); each stands on one tile by the water.
    "fishing_boat": (128, 160, 0.6, build_fishing_boat),
    "rowing_boat": (112, 112, 0.25, build_rowing_boat),
    "smokehouse": (112, 160, 0.8, build_smokehouse),
    "cannery": (128, 160, 0.7, build_cannery),
    "salt_pan": (128, 104, 0.1, build_salt_pan),
    "fish_farm": (128, 112, 0.15, build_fish_farm),
    "shipyard": (128, 152, 0.6, build_shipyard),
    "port": (128, 160, 0.7, build_port),
    "breakwater": (128, 112, 0.15, build_breakwater),
    "lighthouse": (96, 224, 1.7, build_lighthouse),
    "tidal_plant": (128, 128, 0.4, build_tidal_plant),
}


SEAWARD = ("fishing_boat", "rowing_boat", "fish_farm", "shipyard", "port", "breakwater", "tidal_plant")


def render_coast(layout: dict, only=()):
    for name, (w, h, tz, build) in COAST.items():
        if only and name not in only:
            continue
        random.seed(zlib.crc32(name.encode()))
        make = seaward(build) if name in SEAWARD else crafted(build)
        layout[name] = render_sprite(name, w, h, Vector((0, 0, tz)), make, true_scale=True)
        icon = f"item_power_{name}" if name == "tidal_plant" else f"furniture_{name}"
        ra.icon_from(Image.open(OUT / f"{name}.png").convert("RGBA"), ICONS / f"{icon}.png")
    for k in range(3):
        name = f"flotsam_{k}"
        if only and name not in only:
            continue
        random.seed(zlib.crc32(name.encode()))
        layout[name] = render_sprite(name, 112, 80, Vector((0, 0, 0.05)), flotsam(k))
    if not only or "water" in only:
        layout["water"] = render_water_tile()


# --- Oil ------------------------------------------------------------------------------------------

def oil_mats():
    """The paint of the oil field: rusty steel, safety yellow, black crude and pipe grey."""
    return {
        "steel": ra.rusty_metal("oil_steel", (0.16, 0.16, 0.17), rust=0.35),
        "dark": ra.rusty_metal("oil_dark", (0.05, 0.05, 0.055), rust=0.2),
        "yellow": ra.plain("oil_yellow", (0.62, 0.42, 0.03), 0.45, 0.3, variation=0.2, grime=0.8),
        "red": ra.plain("oil_red", (0.5, 0.06, 0.03), 0.45, 0.3, variation=0.15, grime=0.7),
        "white": ra.plain("oil_white", (0.62, 0.62, 0.6), 0.5, 0.2, variation=0.1, grime=0.7),
        "crude": ra.plain("oil_crude", (0.008, 0.007, 0.006), 0.08, variation=0.05, grime=0.0),
        "concrete": ra.plain("oil_concrete", (0.3, 0.3, 0.29), 0.9, variation=0.15),
        "brick": ra.plain("oil_brick", (0.3, 0.11, 0.06), 0.9, variation=0.35, scale=10, bump=0.5),
        "copper": ra.plain("oil_copper", (0.65, 0.28, 0.12), 0.35, 0.9, variation=0.15),
        "pipe": ra.rusty_metal("oil_pipe", (0.3, 0.31, 0.32), rust=0.25),
        "glow": ra.emission("oil_glow", (1.0, 0.45, 0.08), 6.0),
        "lamp": ra.emission("oil_lamp", (0.3, 1.0, 0.25), 3.0),
        "window": ra.emission("oil_window", (1.0, 0.8, 0.5), 2.0),
    }


def flame(at, size=1.0):
    """A gas flare: an orange tongue of fire with a bright core."""
    ra.sphere("flare", 0.09 * size, Vector(at) + Vector((0, 0, 0.12 * size)), ra.emission("flare_outer", (1.0, 0.35, 0.05), 14.0),
              scale=(1, 1, 2.2), segments=12)
    ra.sphere("flare_core", 0.05 * size, Vector(at) + Vector((0, 0, 0.08 * size)), ra.emission("flare_core", (1.0, 0.85, 0.4), 25.0),
              scale=(1, 1, 1.8), segments=10)


def pipe_run(a, b, r, mat, name="pipe"):
    """A straight pipe between two points."""
    a, b = Vector(a), Vector(b)
    d = b - a
    obj = ra.cylinder(name, r, d.length, (a + b) / 2, mat, verts=12)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d.normalized())
    return obj


def build_pumpjack():
    """A pumpjack: a yellow walking beam rocking on an A-frame, its horse head over the wellhead, a crank
    with red counterweights driven by a motor, all on a concrete pad."""
    m = oil_mats()
    ra.box("pj_pad", (1.8, 0.8, 0.1), (0, 0, 0.05), m["concrete"], bevel=0.02)
    for y in (-0.2, 0.2):
        for x, a in ((-0.25, 18), (0.25, -18)):
            ra.box("pj_leg", (0.07, 0.07, 1.2), (x * 0.6, y, 0.65), m["steel"], rotation=(0, math.radians(a), 0))
    ra.box("pj_saddle", (0.2, 0.5, 0.08), (0, 0, 1.22), m["steel"])
    ra.box("pj_beam", (1.8, 0.12, 0.16), (0.05, 0, 1.33), m["yellow"], bevel=0.02, rotation=(0, math.radians(-6), 0))
    # The horse head over the well, at the west end.
    ra.box("pj_head", (0.18, 0.16, 0.5), (-0.88, 0, 1.25), m["yellow"], bevel=0.04, rotation=(0, math.radians(-6), 0))
    ra.cylinder("pj_rod", 0.015, 1.0, (-0.95, 0, 0.62), m["dark"], verts=8)
    ra.cylinder("pj_wellhead", 0.08, 0.25, (-0.95, 0, 0.22), m["red"], verts=12)
    pipe_run((-0.95, 0, 0.18), (-0.95, -0.38, 0.18), 0.04, m["pipe"])
    # The crank and counterweights at the east end.
    ra.box("pj_pitman", (0.06, 0.06, 0.75), (0.82, 0.12, 0.92), m["steel"], rotation=(0, math.radians(8), 0))
    for y in (-0.22, 0.22):
        ra.box("pj_weight", (0.42, 0.06, 0.32), (0.75, y, 0.55), m["red"], bevel=0.02, rotation=(0, math.radians(20), 0))
    ra.cylinder("pj_crank", 0.1, 0.5, (0.75, 0, 0.55), m["steel"], rotation=(math.radians(90), 0, 0), verts=14)
    ra.box("pj_gearbox", (0.36, 0.3, 0.3), (0.75, 0, 0.28), m["steel"], bevel=0.02)
    ra.box("pj_motor", (0.24, 0.2, 0.2), (0.75, -0.3, 0.2), ra.rusty_metal("pj_motor", (0.08, 0.2, 0.12), rust=0.2), bevel=0.02)
    ra.box("pj_puddle", (0.4, 0.3, 0.005), (-0.8, -0.15, 0.102), m["crude"])


def build_gas_well():
    """A gas wellhead: a red Christmas tree of valves and wheels on a gravel pad, a pipe to a little separator
    and a flare burning on a stack."""
    m = oil_mats()
    ra.box("gw_pad", (1.4, 1.0, 0.06), (0, 0, 0.03), rock("gw_gravel", (0.2, 0.19, 0.18)))
    ra.cylinder("gw_casing", 0.12, 0.3, (-0.2, 0, 0.21), m["steel"], verts=14)
    ra.cylinder("gw_tree", 0.07, 0.75, (-0.2, 0, 0.7), m["red"], verts=12)
    for z in (0.5, 0.8):
        ra.box("gw_valve", (0.36, 0.12, 0.12), (-0.2, 0, z), m["red"], bevel=0.02)
        for x in (-0.42, 0.02):
            ra.torus("gw_wheel", 0.07, 0.012, (x, 0, z), m["dark"], rotation=(0, math.radians(90), 0))
    ra.cylinder("gw_gauge", 0.05, 0.03, (-0.2, -0.08, 1.05), m["white"], rotation=(math.radians(90), 0, 0), verts=12)
    pipe_run((-0.2, 0, 0.4), (0.3, 0, 0.4), 0.035, m["pipe"])
    ra.cylinder("gw_separator", 0.14, 0.5, (0.35, 0, 0.3), m["white"], verts=16)
    pipe_run((0.35, 0.0, 0.4), (0.55, 0.3, 0.4), 0.025, m["pipe"])
    ra.cylinder("gw_stack", 0.04, 1.3, (0.55, 0.3, 0.7), m["steel"], verts=10)
    flame((0.55, 0.3, 1.35), 1.0)


def build_offshore_platform():
    """An offshore platform standing in the sea off the shore: steel legs in the water under a deck with a
    derrick, a crane, a block of quarters and a gas flare on a boom."""
    m = oil_mats()
    water = water_mat("plat_water")
    ra.box("plat_water", (2.0, 1.4, 0.02), (0, 0.45, 0.01), water)
    for x in (-0.55, 0.55):
        for y in (0.2, 0.8):
            ra.cylinder("plat_leg", 0.08, 0.7, (x, y, 0.35), m["yellow"], verts=12)
            ra.cylinder("plat_foam", 0.12, 0.02, (x, y, 0.025), ra.plain("plat_foam", (0.7, 0.75, 0.8), 0.4), verts=12)
    ra.box("plat_deck", (1.4, 0.9, 0.12), (0, 0.5, 0.76), m["steel"], bevel=0.02)
    ra.box("plat_quarters", (0.45, 0.45, 0.35), (-0.4, 0.4, 1.0), m["white"], bevel=0.02)
    ra.box("plat_window", (0.3, 0.02, 0.06), (-0.4, 0.17, 1.05), m["window"])
    ra.cylinder("plat_helipad", 0.25, 0.04, (-0.4, 0.4, 1.2), m["dark"], verts=20)
    # The derrick: a tapering lattice tower.
    for dx in (-1, 1):
        for dy in (-1, 1):
            pipe_run((0.25 + dx * 0.2, 0.55 + dy * 0.2, 0.82), (0.25 + dx * 0.05, 0.55 + dy * 0.05, 2.2), 0.018, m["red"], "plat_strut")
    for z, w in ((1.2, 0.15), (1.6, 0.11), (2.0, 0.07)):
        ra.box("plat_ring", (w * 2 + 0.04, w * 2 + 0.04, 0.025), (0.25, 0.55, z), m["red"])
    ra.cylinder("plat_crane", 0.05, 0.4, (0.55, 0.2, 1.0), m["yellow"], verts=10)
    pipe_run((0.55, 0.2, 1.2), (0.85, -0.1, 1.45), 0.02, m["yellow"], "plat_jib")
    pipe_run((-0.7, 0.75, 0.85), (-1.0, 1.0, 1.25), 0.02, m["steel"], "plat_boom")
    flame((-1.0, 1.0, 1.25), 1.1)
    # A walkway to the shore.
    ra.box("plat_gangway", (0.18, 0.5, 0.03), (0.1, -0.15, 0.62), m["steel"], rotation=(math.radians(-18), 0, 0))


def build_water_injector():
    """A water injection station: a blue pump house with a big triplex pump in front, a water tank beside it and
    a pipe going down into the ground."""
    m = oil_mats()
    blue = ra.rusty_metal("inj_blue", (0.05, 0.14, 0.32), rust=0.2)
    ra.box("inj_pad", (1.5, 1.0, 0.08), (0, 0, 0.04), m["concrete"])
    ra.box("inj_house", (0.6, 0.6, 0.6), (-0.4, 0.15, 0.38), ra.corrugated("inj_sheet", (0.3, 0.32, 0.35), 0.2))
    ra.box("inj_roof", (0.66, 0.66, 0.04), (-0.4, 0.15, 0.7), m["steel"])
    ra.box("inj_door", (0.2, 0.02, 0.35), (-0.4, -0.16, 0.26), m["dark"])
    ra.box("inj_pump", (0.45, 0.3, 0.25), (0.2, -0.15, 0.22), blue, bevel=0.03)
    for x in (0.08, 0.2, 0.32):
        ra.cylinder("inj_plunger", 0.045, 0.2, (x, -0.15, 0.44), m["steel"], verts=10)
    ra.cylinder("inj_tank", 0.25, 0.7, (0.45, 0.3, 0.43), blue, verts=24)
    pipe_run((0.2, -0.15, 0.2), (0.2, -0.45, 0.2), 0.04, m["pipe"])
    pipe_run((0.2, -0.45, 0.2), (0.2, -0.45, 0.0), 0.04, m["pipe"])
    ra.box("inj_lamp", (0.06, 0.02, 0.04), (0.2, -0.31, 0.3), m["lamp"])


def build_oil_separator():
    """An oil separator: a long white drum lying on saddles, with a skimmer pit of black oil in front and pipes."""
    m = oil_mats()
    ra.box("sep_pad", (1.4, 0.9, 0.06), (0, 0, 0.03), m["concrete"])
    ra.cylinder("sep_drum", 0.26, 1.0, (0, 0.15, 0.42), m["white"], rotation=(0, math.radians(90), 0), verts=24)
    for x in (-0.48, 0.48):
        ra.sphere("sep_end", 0.26, (x, 0.15, 0.42), m["white"], scale=(0.35, 1, 1), segments=16)
    for x in (-0.3, 0.3):
        ra.box("sep_saddle", (0.1, 0.4, 0.18), (x, 0.15, 0.14), m["steel"])
    ra.box("sep_pit", (0.8, 0.3, 0.04), (0, -0.28, 0.06), m["concrete"], bevel=0.01)
    ra.box("sep_oil", (0.72, 0.22, 0.01), (0, -0.28, 0.08), m["crude"])
    pipe_run((0.0, 0.15, 0.68), (0.0, 0.15, 0.85), 0.03, m["pipe"])
    pipe_run((0.0, 0.15, 0.85), (-0.5, 0.15, 0.85), 0.03, m["pipe"])
    ra.cylinder("sep_valve", 0.06, 0.05, (0, 0.15, 0.9), m["yellow"], verts=12)


def build_distillery():
    """A simple fired still: a brick firebox glowing under a riveted pot, a column with a condenser coil and a
    barrel catching the cut."""
    m = oil_mats()
    ra.box("dist_fire", (0.8, 0.7, 0.4), (-0.1, 0.1, 0.2), m["brick"], bevel=0.03)
    ra.box("dist_glow", (0.25, 0.03, 0.12), (-0.1, -0.26, 0.15), m["glow"])
    ra.cylinder("dist_pot", 0.3, 0.45, (-0.1, 0.1, 0.62), m["copper"], verts=24)
    ra.sphere("dist_dome", 0.3, (-0.1, 0.1, 0.85), m["copper"], scale=(1, 1, 0.5), segments=20)
    ra.cylinder("dist_column", 0.08, 0.9, (-0.1, 0.1, 1.3), m["copper"], verts=14)
    pipe_run((-0.1, 0.1, 1.7), (0.4, 0.1, 1.4), 0.03, m["copper"])
    for k in range(4):
        ra.torus("dist_coil", 0.12, 0.02, (0.45, 0.1, 0.65 + k * 0.15), m["copper"])
    ra.cylinder("dist_cooler", 0.15, 0.7, (0.45, 0.1, 0.85), ra.plain("dist_glass", (0.3, 0.4, 0.45), 0.1, variation=0.05), verts=16)
    ra.cylinder("dist_barrel", 0.16, 0.36, (0.45, -0.3, 0.18), ra.wood("dist_barrel", (0.2, 0.12, 0.06)), verts=16)
    ra.cylinder("dist_chimney", 0.06, 0.7, (-0.4, 0.35, 0.7), m["dark"], verts=10)


def build_refinery():
    """A refinery: two tall fractionating columns with ladders and platforms, a squat furnace with a stack,
    a spherical tank and a tangle of pipes on a concrete pad."""
    m = oil_mats()
    ra.box("ref_pad", (1.9, 1.3, 0.08), (0, 0.1, 0.04), m["concrete"])
    for x, h, r in ((-0.45, 2.6, 0.2), (0.0, 2.0, 0.15)):
        ra.cylinder("ref_column", r, h, (x, 0.3, 0.08 + h / 2), m["white"], verts=20)
        ra.sphere("ref_cap", r, (x, 0.3, 0.08 + h), m["white"], scale=(1, 1, 0.5), segments=14)
        for z in range(1, int(h / 0.6) + 1):
            ra.torus("ref_platform", r + 0.06, 0.012, (x, 0.3, 0.08 + z * 0.6), m["yellow"])
        ra.box("ref_ladder", (0.08, 0.02, h), (x, 0.3 - r - 0.04, 0.08 + h / 2), m["yellow"])
    ra.box("ref_furnace", (0.55, 0.45, 0.5), (0.55, 0.45, 0.33), m["brick"], bevel=0.02)
    ra.box("ref_furnace_glow", (0.2, 0.02, 0.08), (0.55, 0.22, 0.25), m["glow"])
    ra.cylinder("ref_stack", 0.07, 1.4, (0.7, 0.55, 1.25), m["red"], verts=12)
    ra.cylinder("ref_stack_top", 0.075, 0.12, (0.7, 0.55, 1.9), m["white"], verts=12)
    ra.sphere("ref_sphere", 0.3, (0.55, -0.25, 0.42), m["white"], segments=20)
    for x in (0.38, 0.72):
        ra.cylinder("ref_sphere_leg", 0.025, 0.4, (x, -0.25, 0.25), m["steel"], verts=8)
    for z, col in ((0.5, m["pipe"]), (0.7, m["yellow"]), (0.9, m["pipe"])):
        pipe_run((-0.45, 0.1, z), (0.55, 0.1, z), 0.03, col)
    pipe_run((-0.45, 0.1, 0.5), (-0.45, -0.4, 0.5), 0.03, m["pipe"])
    ra.box("ref_lamp", (0.04, 0.04, 0.04), (-0.45, 0.3, 2.75), ra.emission("ref_beacon", (1.0, 0.1, 0.05), 8.0))


def build_cracker():
    """A cracking unit: a tall reactor and a regenerator side by side, joined high up by a fat riser pipe,
    with cyclones on top and a flare."""
    m = oil_mats()
    ra.box("crk_pad", (1.8, 1.2, 0.08), (0, 0.1, 0.04), m["concrete"])
    ra.cylinder("crk_reactor", 0.28, 1.8, (-0.4, 0.3, 0.98), m["white"], verts=22)
    ra.cylinder("crk_reactor_top", 0.28, 0.3, (-0.4, 0.3, 2.03), m["white"], radius2=0.12, verts=22)
    ra.cylinder("crk_regen", 0.34, 1.3, (0.35, 0.3, 0.73), m["steel"], verts=22)
    ra.cylinder("crk_regen_top", 0.34, 0.25, (0.35, 0.3, 1.5), m["steel"], radius2=0.15, verts=22)
    pipe_run((-0.4, 0.3, 1.7), (0.35, 0.3, 1.25), 0.09, m["pipe"])
    pipe_run((-0.4, 0.3, 0.4), (0.35, 0.3, 0.4), 0.07, m["pipe"])
    for x in (-0.48, -0.32):
        ra.cylinder("crk_cyclone", 0.05, 0.3, (x, 0.3, 2.3), m["steel"], radius2=0.02, verts=10)
    ra.cylinder("crk_flare", 0.04, 1.8, (0.75, 0.6, 0.98), m["red"], verts=10)
    flame((0.75, 0.6, 1.9), 1.1)
    for k in range(3):
        ra.torus("crk_platform", 0.34, 0.012, (-0.4, 0.3, 0.6 + k * 0.5), m["yellow"])
    ra.box("crk_control", (0.4, 0.3, 0.3), (0.45, -0.3, 0.23), m["white"], bevel=0.02)
    ra.box("crk_window", (0.25, 0.02, 0.07), (0.45, -0.46, 0.28), m["window"])


def build_chemical_plant():
    """A chemical plant: a white process building with a sawtooth roof, two green reactor vessels with stirrer
    motors, a cooling tower letting off steam and pipe racks."""
    m = oil_mats()
    green = ra.rusty_metal("chem_green", (0.08, 0.28, 0.16), rust=0.15)
    ra.box("chem_pad", (1.9, 1.3, 0.08), (0, 0.1, 0.04), m["concrete"])
    ra.box("chem_hall", (0.9, 0.6, 0.55), (-0.4, 0.3, 0.355), m["white"], bevel=0.02)
    for k in range(3):
        ra.box("chem_saw", (0.3, 0.62, 0.04), (-0.7 + k * 0.3, 0.3, 0.7), m["steel"], rotation=(0, math.radians(25), 0))
    ra.box("chem_windows", (0.7, 0.02, 0.08), (-0.4, -0.01, 0.45), m["window"])
    for x in (0.35, 0.7):
        ra.cylinder("chem_vessel", 0.17, 0.6, (x, -0.2, 0.4), green, verts=18)
        ra.sphere("chem_vessel_top", 0.17, (x, -0.2, 0.7), green, scale=(1, 1, 0.45), segments=14)
        ra.box("chem_motor", (0.12, 0.12, 0.14), (x, -0.2, 0.84), m["steel"], bevel=0.01)
    ra.cylinder("chem_tower", 0.28, 0.9, (0.55, 0.45, 0.53), m["concrete"], radius2=0.2, verts=24)
    for k in range(4):
        ra.sphere("chem_steam", 0.12 + k * 0.03, (0.55 + k * 0.04, 0.45, 1.05 + k * 0.15),
                  ra.plain("chem_steam", (0.7, 0.72, 0.75), 0.9, variation=0.1), scale=(1, 1, 0.7), segments=10)
    for z in (0.62, 0.8):
        pipe_run((0.05, 0.05, z), (0.7, 0.05, z), 0.025, m["yellow"] if z > 0.7 else m["pipe"])


def build_gas_plant():
    """A gas power plant: a turbine hall with a long gas turbine showing through its open side, a tall exhaust
    stack, a transformer and the copper terminal the pole's wire comes to."""
    m = oil_mats()
    ra.box("gp_pad", (1.8, 1.1, 0.08), (0, 0.05, 0.04), m["concrete"])
    ra.box("gp_hall", (1.0, 0.7, 0.6), (-0.3, 0.2, 0.38), ra.corrugated("gp_sheet", (0.35, 0.37, 0.4), 0.15))
    ra.box("gp_roof", (1.06, 0.76, 0.05), (-0.3, 0.2, 0.7), m["steel"])
    ra.cylinder("gp_turbine", 0.14, 0.8, (-0.3, -0.18, 0.3), m["yellow"], rotation=(0, math.radians(90), 0), verts=18, radius2=0.2)
    ra.cylinder("gp_generator", 0.18, 0.3, (0.3, -0.18, 0.28), ra.rusty_metal("gp_gen", (0.08, 0.2, 0.12), rust=0.15),
                rotation=(0, math.radians(90), 0), verts=18)
    ra.cylinder("gp_stack", 0.12, 1.9, (-0.65, 0.4, 1.03), m["white"], verts=16)
    for z in (1.7, 1.9):
        ra.cylinder("gp_band", 0.125, 0.06, (-0.65, 0.4, z), m["red"], verts=16)
    ra.box("gp_transformer", (0.3, 0.3, 0.35), (0.55, 0.3, 0.255), ra.rusty_metal("gp_tr", (0.08, 0.2, 0.12), rust=0.2), bevel=0.02)
    ra.cylinder("gp_terminal", 0.04, 0.3, (0.6, 0.3, 0.58), m["copper"], verts=10)
    ra.sphere("gp_insulator", 0.05, (0.6, 0.3, 0.75), ra.plain("gp_porcelain", (0.75, 0.72, 0.65), 0.3), segments=10)
    pipe_run((-0.9, -0.3, 0.2), (-0.7, -0.3, 0.2), 0.04, m["yellow"])


def build_diesel_generator():
    """A diesel generator set: a green engine housing on a skid with louvres, a fuel tank under it, a short
    exhaust with a rain cap and the terminal for the pole's wire."""
    m = oil_mats()
    green = ra.rusty_metal("dg_green", (0.1, 0.25, 0.12), rust=0.2)
    ra.box("dg_skid", (1.3, 0.7, 0.12), (0, 0, 0.06), m["steel"])
    ra.box("dg_tank", (1.1, 0.55, 0.12), (0, 0, 0.18), m["dark"], bevel=0.02)
    ra.box("dg_body", (1.1, 0.55, 0.5), (0, 0, 0.5), green, bevel=0.03)
    for k in range(6):
        ra.box("dg_louvre", (0.02, 0.4, 0.03), (-0.45 + k * 0.06, -0.28, 0.5), m["dark"], rotation=(0, 0, math.radians(90)))
    ra.box("dg_panel", (0.2, 0.02, 0.18), (0.3, -0.28, 0.55), m["dark"])
    ra.box("dg_light", (0.05, 0.02, 0.03), (0.3, -0.295, 0.6), m["lamp"])
    ra.cylinder("dg_exhaust", 0.05, 0.4, (-0.35, 0.15, 0.95), m["dark"], verts=10)
    ra.box("dg_cap", (0.12, 0.12, 0.02), (-0.35, 0.15, 1.16), m["dark"], rotation=(math.radians(20), 0, 0))
    ra.cylinder("dg_terminal", 0.04, 0.25, (0.5, 0.15, 0.85), m["copper"], verts=10)
    ra.sphere("dg_insulator", 0.05, (0.5, 0.15, 1.0), ra.plain("dg_porcelain", (0.75, 0.72, 0.65), 0.3), segments=10)


def build_pump():
    """A pump on a pipe: a squat steel casing with a motor on top and flanges to the tiles behind and in front;
    the game shows what flows through it."""
    m = oil_mats()
    pump_paint = ra.rusty_metal("pump_blue", (0.05, 0.14, 0.32), rust=0.15)
    ra.box("pump_foot", (0.8, 0.8, 0.1), (0, 0, 0.05), m["steel"], bevel=0.03)
    ra.cylinder("pump_casing", 0.28, 0.3, (0, 0, 0.25), pump_paint, verts=20)
    ra.cylinder("pump_motor", 0.16, 0.3, (0, 0, 0.55), m["steel"], verts=16)
    ra.box("pump_lamp", (0.06, 0.02, 0.04), (0, -0.17, 0.55), m["lamp"])
    for y in (-0.42, 0.42):
        ra.cylinder("pump_flange", 0.12, 0.05, (0, y, 0.25), m["pipe"], rotation=(math.radians(90), 0, 0), verts=14)
        pipe_run((0, y * 0.6, 0.25), (0, y, 0.25), 0.08, m["pipe"])


def build_tank():
    """A storage tank: a white cylinder with a slightly domed roof, a stair winding up it and a gauge."""
    m = oil_mats()
    ra.cylinder("tank_ring", 0.85, 0.08, (0, 0, 0.04), m["concrete"], verts=40)
    ra.cylinder("tank_body", 0.78, 1.0, (0, 0, 0.58), m["white"], verts=40)
    ra.sphere("tank_roof", 0.78, (0, 0, 1.08), m["white"], scale=(1, 1, 0.15), segments=24)
    for k in range(10):
        a = math.radians(-120 + k * 14)
        ra.box("tank_step", (0.18, 0.08, 0.02), (0.84 * math.cos(a), 0.84 * math.sin(a), 0.15 + k * 0.095), m["steel"],
               rotation=(0, 0, a + math.pi / 2))
    ra.box("tank_gauge", (0.04, 0.02, 0.6), (0, -0.79, 0.6), m["dark"])
    ra.box("tank_band", (0.04, 0.025, 0.08), (0, -0.8, 0.75), m["red"])
    pipe_run((0.5, -0.5, 0.15), (0.75, -0.75, 0.15), 0.05, m["pipe"])


def pipe_straight(along_x=True, s=1.0, length=2.0):
    """A pipe the length of a tile on low supports, flanged at both ends so pipes on neighbouring tiles join up."""
    m = oil_mats()
    rot = (0, math.radians(90), 0) if along_x else (math.radians(90), 0, 0)

    def at(a, z):
        return Vector((a * s, 0, z * s)) if along_x else Vector((0, a * s, z * s))

    ra.cylinder("pipe_body", 0.16 * s, length * s, at(0, 0.3), m["pipe"], rotation=rot, verts=16)
    for a in (-length / 2 + 0.04, length / 2 - 0.04):
        ra.cylinder("pipe_flange", 0.2 * s, 0.06 * s, at(a, 0.3), m["steel"], rotation=rot, verts=16)
    for a in (-0.5, 0.5):
        ra.box("pipe_support", (0.12 * s, 0.4 * s, 0.14 * s) if along_x else (0.4 * s, 0.12 * s, 0.14 * s), at(a * length / 2, 0.07),
               m["steel"])
    ra.cylinder("pipe_band", 0.165 * s, 0.1 * s, at(0, 0.3), m["yellow"], rotation=rot, verts=16)


def pipe_bend(sides):
    """A pipe turning a corner between two sides of its tile, along a quarter circle like belt_curve."""
    m = oil_mats()
    (ax, ay), (bx, by) = SIDES[sides[0]], SIDES[sides[1]]
    centre = (ax + bx, ay + by)
    mid = math.atan2(-centre[1], -centre[0])
    a0, a1 = mid - math.pi / 4, mid + math.pi / 4
    n = 8
    for k in range(n):
        u0, u1 = a0 + (a1 - a0) * k / n, a0 + (a1 - a0) * (k + 1) / n
        p0 = (centre[0] + math.cos(u0), centre[1] + math.sin(u0), 0.3)
        p1 = (centre[0] + math.cos(u1), centre[1] + math.sin(u1), 0.3)
        pipe_run(p0, p1, 0.16, m["pipe"], "pipe_body")
        ra.sphere("pipe_joint", 0.16, p1, m["pipe"], segments=12)
    for u in (a0, a1):
        p = (centre[0] + math.cos(u), centre[1] + math.sin(u), 0.3)
        ra.sphere("pipe_flange", 0.2, p, m["steel"], scale=(1, 1, 1), segments=12)
    um = (a0 + a1) / 2
    ra.box("pipe_support", (0.3, 0.3, 0.14), (centre[0] + math.cos(um), centre[1] + math.sin(um), 0.07), m["steel"])


def road():
    """A tile of asphalt 2 m square, so roads on neighbouring tiles join: dark tar with a grain of chippings."""
    mat = ra.Mat("asphalt")
    fine = mat.noise(60.0, detail=8)
    coarse = mat.noise(6.0, detail=3)
    col = mat.ramp(fine.outputs["Fac"], [(0.35, (0.018, 0.018, 0.02)), (0.6, (0.05, 0.05, 0.052)), (0.75, (0.11, 0.105, 0.1))]).outputs["Color"]
    col = mat.mix(0.35, col, mat.ramp(coarse.outputs["Fac"], [(0.3, (0.75, 0.75, 0.75)), (0.7, (1.15, 1.15, 1.15))]).outputs["Color"], "MULTIPLY")
    ra.box("road", (2.0, 2.0, 0.03), (0, 0, 0.015), mat.done(col, 0.85, 0.0, fine.outputs["Fac"], 0.3))
    return meshes()


OIL = {
    # name: (canvas width, height, camera target height, builder); each stands on one tile.
    "pumpjack": (128, 144, 0.7, build_pumpjack),
    "gas_well": (112, 128, 0.55, build_gas_well),
    "offshore_platform": (144, 176, 1.0, build_offshore_platform),
    "water_injector": (112, 112, 0.4, build_water_injector),
    "oil_separator": (112, 96, 0.4, build_oil_separator),
    "distillery": (96, 144, 0.8, build_distillery),
    "refinery": (136, 208, 1.3, build_refinery),
    "cracker": (128, 176, 1.1, build_cracker),
    "chemical_plant": (136, 144, 0.6, build_chemical_plant),
    "tank": (112, 128, 0.6, build_tank),
}

# Generators, wired to the pole that reaches them: where the wires meet each.
OIL_POWER = {
    "gas_plant": (128, 176, 0.9, build_gas_plant, Vector((0.6, 0.3, 0.78))),
    "diesel_generator": (112, 112, 0.5, build_diesel_generator, Vector((0.5, 0.15, 1.03))),
}

# Pipes: the belt sprites' names with "_pipe", so the game lays them like belts.
PIPES = {
    "belt_ew_pipe": (72, 64, 0.1, lambda: pipe_straight(True)),
    "belt_ns_pipe": (72, 72, 0.1, lambda: pipe_straight(False)),
    **{f"belt_{c}_pipe": (72, 72, 0.1, lambda c=c: pipe_bend(c)) for c in ("ne", "es", "sw", "nw")},
    "pump": (64, 72, 0.3, build_pump),
}


def render_oil(layout: dict, only=()):
    for name, (w, h, tz, build) in OIL.items():
        if only and name not in only:
            continue
        random.seed(zlib.crc32(name.encode()))
        make = seaward(build) if name == "offshore_platform" else crafted(build)
        layout[name] = render_sprite(name, w, h, Vector((0, 0, tz)), make, true_scale=True)
        icon = "item_storage_tank" if name == "tank" else f"furniture_{name}"
        ra.icon_from(Image.open(OUT / f"{name}.png").convert("RGBA"), ICONS / f"{icon}.png")
    for name, (w, h, tz, build, wire) in OIL_POWER.items():
        if only and name not in only:
            continue
        random.seed(zlib.crc32(name.encode()))
        target = Vector((0, 0, tz))
        layout[name] = render_sprite(name, w, h, target, crafted(build), true_scale=True)
        layout[name]["wireX"], layout[name]["wireY"] = anchor(w, h, target, wire)
        ra.icon_from(Image.open(OUT / f"{name}.png").convert("RGBA"), ICONS / f"item_power_{name}.png")
    for name, (w, h, tz, build) in PIPES.items():
        if only and name not in only:
            continue
        random.seed(zlib.crc32(name.encode()))
        layout[name] = render_sprite(name, w, h, Vector((0, 0, tz)), crafted(build), true_scale=True)
    if not only or "road" in only:
        layout["road"] = render_sprite("road", 112, 96, Vector((0, 0, 0)), road)


# --- Desert ---------------------------------------------------------------------------------------

def desert_mats():
    """The paint of the desert industry: sun-bleached render, adobe, glass, galvanised steel and the solar blue."""
    return {
        "render": ra.plain("des_render", (0.42, 0.34, 0.24), 0.9, variation=0.2, scale=8, bump=0.3),
        "adobe": ra.plain("des_adobe", (0.36, 0.22, 0.11), 0.95, variation=0.3, scale=12, bump=0.5),
        "brick": ra.plain("des_brick", (0.3, 0.11, 0.06), 0.9, variation=0.35, scale=10, bump=0.5),
        "steel": ra.rusty_metal("des_steel", (0.32, 0.33, 0.34), rust=0.15),
        "dark": ra.rusty_metal("des_dark", (0.05, 0.05, 0.055), rust=0.15),
        "white": ra.plain("des_white", (0.65, 0.65, 0.62), 0.5, 0.2, variation=0.1, grime=0.6),
        "orange": ra.plain("des_orange", (0.65, 0.25, 0.03), 0.45, 0.3, variation=0.15, grime=0.6),
        "concrete": ra.plain("des_concrete", (0.32, 0.31, 0.29), 0.9, variation=0.15),
        "glass": ra.plain("des_glass", (0.12, 0.35, 0.22), 0.05, variation=0.1, grime=0.05),
        "cell": ra.plain("des_cell", (0.01, 0.03, 0.09), 0.15, 0.4, variation=0.08, grime=0.05),
        "mirror": ra.plain("des_mirror", (0.8, 0.82, 0.85), 0.03, 1.0, variation=0.02, grime=0.05),
        "copper": ra.plain("des_copper", (0.65, 0.28, 0.12), 0.35, 0.9, variation=0.15),
        "water": water_mat("des_water"),
        "reed": ra.plain("des_reed", (0.42, 0.33, 0.14), 0.85, variation=0.35, scale=20, bump=0.4),
        "glow": ra.emission("des_glow", (1.0, 0.45, 0.08), 6.0),
        "hot": ra.emission("des_hot", (1.0, 0.85, 0.5), 18.0),
        "lamp": ra.emission("des_lamp", (0.3, 1.0, 0.25), 3.0),
    }


def build_glassworks():
    """A glassworks: a domed brick furnace with a glowing mouth and a tall chimney, a bench of green bottles beside it."""
    m = desert_mats()
    ra.box("gw_floor", (1.7, 1.2, 0.06), (0, 0, 0.03), m["concrete"])
    dome = ra.sphere("gw_dome", 0.5, (-0.2, 0.05, 0.2), m["brick"], scale=(1, 1, 0.9), segments=24)
    ra.displace(dome, 0.01, 0.1, 1)
    ra.cylinder("gw_base", 0.52, 0.22, (-0.2, 0.05, 0.14), m["render"], verts=28)
    for a in (-0.6, 0.0, 0.6):
        ra.cylinder("gw_mouth", 0.08, 0.06, (-0.2 + math.sin(a) * 0.45, 0.05 - math.cos(a) * 0.45, 0.42), m["glow"],
                    rotation=(math.radians(90), 0, a), verts=16)
    ra.cylinder("gw_chimney", 0.1, 1.3, (-0.25, 0.4, 0.95), m["brick"], verts=14)
    ra.cylinder("gw_cap", 0.13, 0.05, (-0.25, 0.4, 1.6), m["dark"], verts=14)
    ra.box("gw_bench", (0.5, 0.35, 0.04), (0.55, -0.15, 0.4), ra.wood("gw_bench", (0.2, 0.12, 0.06)))
    for x in (0.4, 0.55):
        for y in (-0.3, 0.0):
            ra.box("gw_leg", (0.04, 0.04, 0.38), (x + 0.1, y, 0.2), m["dark"])
    for k in range(4):
        x, y = 0.38 + k * 0.1, -0.2 + (k % 2) * 0.1
        ra.cylinder("gw_bottle", 0.035, 0.14, (x, y, 0.49), m["glass"], verts=12)
        ra.cylinder("gw_neck", 0.013, 0.06, (x, y, 0.59), m["glass"], verts=8)
    ra.box("gw_panes", (0.3, 0.04, 0.4), (0.55, 0.3, 0.25), m["glass"], rotation=(math.radians(-10), 0, 0))


def build_arc_furnace():
    """An arc furnace: a squat steel vessel with a domed lid, three graphite electrodes rising through it on a mast,
    thick copper cables and a white-hot glow under the lid."""
    m = desert_mats()
    ra.box("af_pad", (1.6, 1.4, 0.08), (0, 0, 0.04), m["concrete"])
    ra.cylinder("af_vessel", 0.5, 0.5, (0, 0, 0.33), m["steel"], verts=28)
    ra.cylinder("af_band", 0.52, 0.06, (0, 0, 0.52), m["dark"], verts=28)
    ra.sphere("af_lid", 0.5, (0, 0, 0.58), m["dark"], scale=(1, 1, 0.35), segments=24)
    ra.torus("af_glow", 0.49, 0.025, (0, 0, 0.57), m["hot"])
    for k in range(3):
        a = k * math.tau / 3 + 0.4
        x, y = math.cos(a) * 0.18, math.sin(a) * 0.18
        ra.cylinder("af_electrode", 0.06, 0.9, (x, y, 1.05), ra.plain("af_graphite", (0.06, 0.06, 0.065), 0.4, 0.2), verts=12)
        ra.box("af_clamp", (0.16, 0.16, 0.08), (x, y, 1.35), m["copper"])
        pipe_run((x, y, 1.38), (0.75, 0.35 - k * 0.12, 1.1), 0.03, m["copper"], "af_cable")
    ra.box("af_mast", (0.12, 0.12, 1.5), (0.6, 0.45, 0.75), m["orange"])
    ra.box("af_arm", (0.7, 0.1, 0.1), (0.3, 0.3, 1.45), m["orange"], rotation=(0, 0, math.radians(-25)))
    ra.box("af_transformer", (0.4, 0.35, 0.45), (0.55, -0.4, 0.3), ra.rusty_metal("af_tr", (0.12, 0.2, 0.14), rust=0.1), bevel=0.02)
    ra.box("af_lamp", (0.05, 0.02, 0.05), (0.55, -0.58, 0.45), m["lamp"])


def build_water_well():
    """A deep water well: a pump head with a motor on a concrete ring, a pipe running to a small blue tank on legs."""
    m = desert_mats()
    blue = ra.rusty_metal("ww_blue", (0.05, 0.16, 0.4), rust=0.15)
    ra.cylinder("ww_ring", 0.35, 0.18, (-0.3, 0, 0.09), m["concrete"], verts=24)
    ra.cylinder("ww_hole", 0.27, 0.02, (-0.3, 0, 0.18), m["water"], verts=24)
    ra.box("ww_head", (0.3, 0.25, 0.3), (-0.3, 0, 0.35), blue, bevel=0.03)
    ra.cylinder("ww_motor", 0.1, 0.3, (-0.3, 0, 0.62), m["dark"], verts=14)
    ra.cylinder("ww_fan", 0.11, 0.04, (-0.3, 0, 0.79), m["steel"], verts=14)
    pipe_run((-0.15, 0, 0.35), (0.35, 0, 0.35), 0.035, m["steel"])
    pipe_run((0.35, 0, 0.35), (0.35, 0, 0.85), 0.035, m["steel"])
    for dx in (-0.15, 0.15):
        for dy in (-0.15, 0.15):
            ra.box("ww_leg", (0.04, 0.04, 0.7), (0.35 + dx, dy, 0.35), m["steel"])
    ra.cylinder("ww_tank", 0.25, 0.35, (0.35, 0, 0.88), blue, verts=24)
    ra.sphere("ww_top", 0.25, (0.35, 0, 1.05), blue, scale=(1, 1, 0.3), segments=20)


def build_desalinator():
    """A desalinator on the shore: an intake pipe out of the sea, a white plant of pressure vessels and a pile of salt."""
    m = desert_mats()
    ra.box("ds_sea", (1.8, 0.7, 0.02), (0, 0.55, 0.01), m["water"])
    ra.box("ds_pad", (1.6, 0.9, 0.08), (0, -0.2, 0.04), m["concrete"])
    pipe_run((-0.6, 0.85, 0.06), (-0.6, -0.05, 0.25), 0.05, m["steel"], "ds_intake")
    ra.box("ds_house", (0.6, 0.55, 0.5), (-0.35, -0.3, 0.33), m["white"], bevel=0.02)
    ra.box("ds_roof", (0.64, 0.6, 0.04), (-0.35, -0.3, 0.6), m["steel"])
    for k in range(4):
        ra.cylinder("ds_vessel", 0.06, 0.7, (0.15 + k * 0.15, -0.2, 0.2), m["white"], rotation=(0, math.radians(90), 0), verts=14)
        ra.cylinder("ds_vessel2", 0.06, 0.7, (0.15 + k * 0.15, -0.2, 0.38), m["white"], rotation=(0, math.radians(90), 0), verts=14)
    pipe_run((-0.05, -0.2, 0.3), (0.7, -0.2, 0.3), 0.025, m["steel"], "ds_header")
    ra.cylinder("ds_tank", 0.16, 0.45, (0.6, -0.5, 0.3), ra.rusty_metal("ds_blue", (0.05, 0.16, 0.4), rust=0.1), verts=20)
    salt = ra.sphere("ds_salt", 0.15, (0.15, -0.55, 0.06), ra.plain("ds_salt", (0.85, 0.82, 0.78), 0.6), scale=(1.3, 1, 0.6), segments=14)
    ra.displace(salt, 0.02, 0.2, 1)


def build_drying_yard():
    """A drying yard: rows of sun-dried mud bricks on sand under a light reed awning on poles."""
    m = desert_mats()
    ra.box("dy_sand", (1.8, 1.4, 0.03), (0, 0, 0.015), sand_mat())
    for r in range(3):
        for c in range(6):
            b = ra.box("dy_brick", (0.2, 0.1, 0.07), (-0.6 + c * 0.24, -0.45 + r * 0.25, 0.065), m["adobe"], bevel=0.01,
                       rotation=(0, 0, random.uniform(-0.08, 0.08)))
            ra.displace(b, 0.004, 0.1, 1)
    ra.box("dy_stack", (0.3, 0.22, 0.35), (0.6, 0.45, 0.2), m["adobe"], bevel=0.01)
    timber = ra.wood("dy_pole", (0.2, 0.13, 0.07))
    for x in (-0.75, 0.75):
        for y in (-0.55, 0.15):
            ra.cylinder("dy_pole", 0.03, 1.0, (x, y, 0.5), timber, verts=8)
    ra.box("dy_awning", (1.6, 0.8, 0.03), (0, -0.2, 1.0), m["reed"], rotation=(math.radians(6), 0, 0))
    ra.box("dy_mould", (0.4, 0.2, 0.06), (0.25, 0.45, 0.06), timber)


def build_cement_kiln():
    """A cement kiln: a long rotary drum sloping on piers, a burner glowing at its low end and a grey silo at the high one."""
    m = desert_mats()
    ra.box("ck_pad", (1.8, 1.2, 0.08), (0, 0, 0.04), m["concrete"])
    drum = ra.cylinder("ck_drum", 0.18, 1.4, (0, -0.1, 0.5), m["orange"], rotation=(0, math.radians(84), 0), verts=24)
    for x in (-0.4, 0.35):
        ra.box("ck_pier", (0.14, 0.3, 0.42 - x * 0.08), (x, -0.1, 0.2), m["concrete"])
        ra.torus("ck_tyre", 0.2, 0.03, (x, -0.1, 0.5 + x * 0.1), m["dark"], rotation=(0, math.radians(84), 0))
    ra.cylinder("ck_burner", 0.12, 0.08, (-0.72, -0.1, 0.43), m["glow"], rotation=(0, math.radians(84), 0), verts=16)
    ra.box("ck_hood", (0.3, 0.4, 0.5), (-0.8, -0.1, 0.33), m["brick"], bevel=0.02)
    ra.cylinder("ck_silo", 0.22, 0.9, (0.6, 0.35, 0.55), m["white"], verts=22)
    ra.cylinder("ck_cone", 0.22, 0.2, (0.6, 0.35, 0.1), m["white"], radius2=0.05, verts=22)
    ra.cylinder("ck_stack", 0.06, 0.9, (-0.85, 0.2, 0.8), m["steel"], verts=10)


def build_concrete_mixer():
    """A concrete mixer: a tilted orange drum with spiral ribs on a steel frame, a hopper and a chute."""
    m = desert_mats()
    ra.box("cm_pad", (1.4, 1.0, 0.06), (0, 0, 0.03), m["concrete"])
    for x in (-0.35, 0.35):
        ra.box("cm_frame", (0.08, 0.6, 0.08), (x, 0, 0.3), m["steel"])
        ra.box("cm_post", (0.08, 0.08, 0.55), (x, 0, 0.3), m["steel"])
    ra.cylinder("cm_drum", 0.3, 0.55, (0, 0, 0.62), m["orange"], rotation=(math.radians(60), 0, 0), verts=24, radius2=0.18)
    ra.cylinder("cm_mouth", 0.17, 0.12, (0, -0.28, 0.82), m["dark"], rotation=(math.radians(60), 0, 0), verts=20, radius2=0.14)
    for k in range(3):
        ra.torus("cm_rib", 0.29 - k * 0.03, 0.015, (0, 0.05 - k * 0.1, 0.58 + k * 0.06), m["orange"], rotation=(math.radians(60), 0, 0))
    ra.box("cm_motor", (0.25, 0.2, 0.2), (0.45, 0.25, 0.15), m["dark"], bevel=0.02)
    ra.box("cm_chute", (0.12, 0.4, 0.03), (0, -0.45, 0.3), m["steel"], rotation=(math.radians(-25), 0, 0))
    ra.box("cm_hopper", (0.3, 0.3, 0.25), (-0.45, 0.25, 0.25), m["steel"], bevel=0.02)


def build_reed_fence():
    """A reed fence: a row of bundled reeds lashed to two rails between posts, across the tile."""
    m = desert_mats()
    timber = ra.wood("rf_post", (0.2, 0.13, 0.07))
    for x in (-0.85, 0.0, 0.85):
        ra.cylinder("rf_post", 0.04, 0.9, (x, 0, 0.45), timber, verts=8)
    for z in (0.3, 0.7):
        ra.box("rf_rail", (1.8, 0.03, 0.03), (0, 0.04, z), timber)
    for k in range(34):
        x = -0.84 + k * 0.051
        h = random.uniform(0.85, 1.05)
        ra.cylinder("rf_reed", 0.024, h, (x, 0, h / 2), m["reed"], verts=6, rotation=(random.uniform(-0.04, 0.04), random.uniform(-0.04, 0.04), 0))


def build_solar_panel():
    """A solar panel: a dark blue array of cells in an aluminium frame, tilted to the sun on a steel stand."""
    m = desert_mats()
    tilt = math.radians(32)
    for x in (-0.6, 0.6):
        ra.box("sp_leg_front", (0.05, 0.05, 0.35), (x, -0.25, 0.18), m["steel"])
        ra.box("sp_leg_back", (0.05, 0.05, 0.8), (x, 0.25, 0.4), m["steel"])
    ra.box("sp_frame", (1.7, 1.05, 0.04), (0, 0, 0.58), m["steel"], rotation=(tilt, 0, 0))
    ra.box("sp_cells", (1.62, 0.98, 0.02), (0, -0.012, 0.6), m["cell"], rotation=(tilt, 0, 0))
    up = Vector((0, -math.sin(tilt), math.cos(tilt)))
    along = Vector((0, math.cos(tilt), math.sin(tilt)))
    for i in range(1, 6):
        ra.box("sp_line", (0.012, 0.97, 0.005), Vector((-0.81 + i * 0.27, 0, 0.6)) + up * 0.013, m["white"], rotation=(tilt, 0, 0))
    for j in range(1, 3):
        ra.box("sp_line", (1.6, 0.012, 0.005), Vector((0, 0, 0.6)) + along * (-0.49 + j * 0.327) + up * 0.013, m["white"], rotation=(tilt, 0, 0))
    ra.box("sp_box", (0.14, 0.08, 0.1), (0.6, 0.3, 0.2), m["dark"])


def build_solar_tower():
    """A solar tower on 3 × 3 tiles: a slim concrete tower with a white-hot receiver at the top, ringed by mirrors
    on stands turned to it."""
    m = desert_mats()
    ra.box("st_ground", (5.8, 5.8, 0.02), (0, 0, 0.01), sand_mat())
    ra.cylinder("st_tower", 0.3, 4.2, (0, 0.4, 2.1), m["concrete"], verts=20, radius2=0.22)
    ra.cylinder("st_receiver", 0.34, 0.5, (0, 0.4, 4.45), m["hot"], verts=20)
    ra.cylinder("st_crown", 0.4, 0.12, (0, 0.4, 4.76), m["dark"], verts=20)
    ra.box("st_house", (0.9, 0.7, 0.5), (0.9, 1.2, 0.25), m["white"], bevel=0.02)
    for ring, count in ((1.6, 10), (2.5, 16)):
        for k in range(count):
            a = k * math.tau / count + ring
            x, y = math.cos(a) * ring, 0.4 + math.sin(a) * ring
            if abs(x) > 2.7 or abs(y) > 2.7 or (x > 0.3 and y > 0.7 and x < 1.5 and y < 1.7):
                continue
            ra.cylinder("st_stand", 0.025, 0.4, (x, y, 0.2), m["steel"], verts=6)
            face = Vector((-x, 0.4 - y, 4.4 - 0.45)).normalized()
            mirror = ra.box("st_mirror", (0.5, 0.35, 0.02), (x, y, 0.45), m["mirror"])
            mirror.rotation_mode = "QUATERNION"
            mirror.rotation_quaternion = Vector((0, 0, 1)).rotation_difference((face + Vector((0, 0, 1))).normalized())


def build_battery():
    """A battery: a grey container of cells with a striped warning band, cooling vents and a green status lamp."""
    m = desert_mats()
    ra.box("bt_pad", (1.5, 0.9, 0.06), (0, 0, 0.03), m["concrete"])
    ra.box("bt_box", (1.3, 0.7, 0.7), (0, 0, 0.41), ra.corrugated("bt_sheet", (0.36, 0.38, 0.4), 0.1), bevel=0.02)
    for k in range(6):
        ra.box("bt_stripe", (0.1, 0.71, 0.08), (-0.55 + k * 0.22, 0, 0.7), m["orange"] if k % 2 else m["dark"])
    for k in range(4):
        ra.box("bt_vent", (0.18, 0.02, 0.12), (-0.45 + k * 0.3, -0.36, 0.4), m["dark"])
    ra.box("bt_lamp", (0.05, 0.02, 0.05), (0.55, -0.36, 0.6), m["lamp"])
    ra.box("bt_terminal", (0.12, 0.12, 0.1), (0.45, 0.2, 0.81), m["copper"])


def palm(height, lean, fronds, seed):
    """A date palm: a ringed trunk leaning a little, a crown of long arching fronds and bunches of dates under them."""
    random.seed(seed)
    trunk = ra.plain("palm_trunk", (0.16, 0.11, 0.06), 0.9, variation=0.35, scale=25, bump=0.7)
    leaves = foliage("palm_leaves", (0.06, 0.13, 0.03), 0.4)
    top = Vector((lean, lean * 0.3, height))
    segments = 9
    for i in range(segments):
        t0, t1 = i / segments, (i + 1) / segments
        a = Vector((lean * t0 ** 1.6, lean * 0.3 * t0 ** 1.6, height * t0))
        b = Vector((lean * t1 ** 1.6, lean * 0.3 * t1 ** 1.6, height * t1))
        ring = pipe_run(a, b, 0.16 - 0.04 * t0, trunk, "palm_ring")
        ring.scale = (1.0, 1.0, 1.0)
    for k in range(fronds):
        a = k * math.tau / fronds + random.uniform(-0.2, 0.2)
        droop = random.uniform(0.35, 0.75)
        for s in range(5):
            t = (s + 0.5) / 5
            r = 0.4 + t * 1.6
            p = top + Vector((math.cos(a) * r, math.sin(a) * r, 0.25 - droop * t * t * 2.2))
            leaf = ra.sphere("palm_frond", 0.3, p, leaves, scale=(1.4, 0.55, 0.12), segments=10)
            leaf.rotation_euler = (0, droop * t * 1.2, a)
    for k in range(3):
        a = k * math.tau / 3 + 0.5
        bunch = ra.sphere("palm_dates", 0.16, top + Vector((math.cos(a) * 0.22, math.sin(a) * 0.22, -0.35)),
                          ra.plain("palm_date", (0.35, 0.12, 0.03), 0.5, variation=0.3, scale=40, bump=0.8), scale=(1, 1, 1.4), segments=12)
        ra.displace(bunch, 0.04, 0.05, 1)
    return meshes()


DESERT = {
    # name: (canvas width, height, camera target height, builder); the solar tower stands on 3 × 3 tiles.
    "glassworks": (128, 144, 0.7, build_glassworks),
    "arc_furnace": (128, 144, 0.7, build_arc_furnace),
    "water_well": (112, 128, 0.5, build_water_well),
    "desalinator": (128, 112, 0.35, build_desalinator),
    "drying_yard": (128, 112, 0.45, build_drying_yard),
    "cement_kiln": (136, 128, 0.6, build_cement_kiln),
    "concrete_mixer": (112, 112, 0.45, build_concrete_mixer),
    "reed_fence": (128, 104, 0.45, build_reed_fence),
}

# Power from the sun, wired to the pole that reaches it: where the wires meet each.
DESERT_POWER = {
    "solar_panel": (128, 104, 0.4, build_solar_panel, Vector((0.6, 0.3, 0.25))),
    "solar_tower": (240, 304, 2.4, build_solar_tower, Vector((0.9, 1.2, 0.5))),
    "battery": (128, 104, 0.45, build_battery, Vector((0.45, 0.2, 0.86))),
}

PALMS = {
    "palm_0": (256, 320, 3.2, lambda: palm(5.2, 0.6, 9, 11)),
    "palm_1": (256, 288, 2.8, lambda: palm(4.4, -0.5, 8, 12)),
}


def render_desert(layout: dict, only=()):
    for name, (w, h, tz, build) in DESERT.items():
        if only and name not in only:
            continue
        random.seed(zlib.crc32(name.encode()))
        make = seaward(build) if name == "desalinator" else crafted(build)
        layout[name] = render_sprite(name, w, h, Vector((0, 0, tz)), make, true_scale=True)
        ra.icon_from(Image.open(OUT / f"{name}.png").convert("RGBA"), ICONS / f"furniture_{name}.png")
    for name, (w, h, tz, build, wire) in DESERT_POWER.items():
        if only and name not in only:
            continue
        random.seed(zlib.crc32(name.encode()))
        target = Vector((0, 0, tz))
        layout[name] = render_sprite(name, w, h, target, crafted(build), true_scale=True)
        layout[name]["wireX"], layout[name]["wireY"] = anchor(w, h, target, wire)
        ra.icon_from(Image.open(OUT / f"{name}.png").convert("RGBA"), ICONS / f"item_power_{name}.png")
    for name, (w, h, tz, build) in PALMS.items():
        if only and name not in only:
            continue
        layout[name] = render_sprite(name, w, h, Vector((0, 0, tz)), build)


def desert_icon_models():
    """Icons of what the desert makes and gives up."""
    def glass():
        pane = ra.plain("ic_glass", (0.12, 0.35, 0.22), 0.05, variation=0.1, grime=0.05)
        for k in range(3):
            ra.box("pane", (0.36, 0.26, 0.025), (k * 0.02, -k * 0.02, 0.02 + k * 0.03), pane, bevel=0.005, rotation=(0, 0, 0.15 * k))

    def window_pane():
        frame = ra.wood("ic_frame", (0.35, 0.22, 0.1))
        ra.box("frame", (0.34, 0.03, 0.42), (0, 0, 0.21), frame, bevel=0.01)
        ra.box("pane", (0.3, 0.035, 0.38), (0, 0, 0.21), ra.plain("ic_pane", (0.45, 0.6, 0.7), 0.03, 0.2, variation=0.05, grime=0.0))
        ra.box("bar", (0.02, 0.04, 0.38), (0, 0, 0.21), frame)

    def bottles():
        g = ra.plain("ic_bottle", (0.1, 0.32, 0.12), 0.05, variation=0.1, grime=0.05)
        for k, (x, y) in enumerate(((-0.1, 0.02), (0.1, 0.04), (0, -0.08))):
            ra.cylinder("bottle", 0.07, 0.24, (x, y, 0.12), g, verts=18)
            ra.cylinder("shoulder", 0.07, 0.06, (x, y, 0.27), g, radius2=0.025, verts=18)
            ra.cylinder("neck", 0.022, 0.07, (x, y, 0.33), g, verts=10)

    def mirror():
        frame = ra.plain("ic_mframe", (0.55, 0.38, 0.1), 0.35, 0.9)
        ra.cylinder("frame", 0.2, 0.03, (0, 0, 0.2), frame, rotation=(math.radians(70), 0, 0), verts=32)
        ra.cylinder("glass", 0.17, 0.035, (0, -0.005, 0.2), ra.plain("ic_mirror", (0.8, 0.82, 0.85), 0.03, 1.0, grime=0.0),
                    rotation=(math.radians(70), 0, 0), verts=32)

    def fiber():
        jacket = ra.plain("ic_fiber", (0.75, 0.35, 0.05), 0.5)
        for k in range(4):
            ra.torus("coil", 0.16 - k * 0.012, 0.018, (0, 0, 0.03 + k * 0.035), jacket)
        ra.sphere("tip", 0.02, (0.18, -0.05, 0.06), ra.emission("ic_light", (0.5, 0.9, 1.0), 8.0), segments=8)

    def silicon():
        mat = ra.plain("ic_silicon", (0.18, 0.2, 0.24), 0.25, 0.8, variation=0.2, bump=0.5)
        for k in range(4):
            a = k * 1.7
            c = ra.sphere("chunk", 0.08, (math.cos(a) * 0.1, math.sin(a) * 0.08, 0.06 + (k == 3) * 0.08), mat, scale=(1, 0.8, 0.7), segments=6)
            ra.displace(c, 0.02, 0.1, 1)

    def wafer():
        ra.cylinder("wafer", 0.2, 0.015, (0, 0, 0.02), ra.plain("ic_wafer", (0.2, 0.22, 0.35), 0.1, 0.9, variation=0.1, grime=0.0), verts=40)
        for i in range(-3, 4):
            ra.box("die", (0.3 * math.sqrt(max(0.0, 1 - (i / 4) ** 2)), 0.005, 0.004), (0, i * 0.05, 0.03), ra.plain("ic_die", (0.5, 0.45, 0.6), 0.2, 0.6))

    def water():
        blue = ra.plain("ic_jug", (0.15, 0.35, 0.65), 0.15, variation=0.05, grime=0.05)
        ra.cylinder("jug", 0.13, 0.3, (0, 0, 0.15), blue, verts=24)
        ra.cylinder("shoulder", 0.13, 0.06, (0, 0, 0.33), blue, radius2=0.05, verts=24)
        ra.cylinder("cap", 0.05, 0.04, (0, 0, 0.38), ra.plain("ic_cap", (0.1, 0.25, 0.6), 0.4), verts=14)
        ra.sphere("drop", 0.05, (0.17, -0.1, 0.06), ra.plain("ic_drop", (0.3, 0.6, 0.9), 0.05, grime=0.0), scale=(1, 1, 1.4), segments=12)

    def lump(name, color):
        def build():
            mat = ra.plain(name, color, 0.9, variation=0.25, scale=10, bump=0.6)
            c = ra.sphere("lump", 0.18, (0, 0, 0.08), mat, scale=(1.2, 1, 0.6), segments=16)
            ra.displace(c, 0.03, 0.15, 2)
        return build

    def adobe():
        mat = ra.plain("ic_adobe", (0.36, 0.22, 0.11), 0.95, variation=0.3, scale=12, bump=0.5)
        for k, (x, y, z) in enumerate(((-0.11, 0, 0.04), (0.11, 0, 0.04), (0, 0, 0.12))):
            ra.box("adobe", (0.21, 0.12, 0.08), (x, y, z), mat, bevel=0.01, rotation=(0, 0, 0.05 * k))

    def cement():
        cloth = ra.plain("ic_csack", (0.45, 0.44, 0.42), 0.95, variation=0.12, scale=12, bump=0.5)
        body = ra.sphere("sack", 0.17, (0, 0, 0.13), cloth, scale=(1.2, 0.9, 0.85), segments=20)
        ra.displace(body, 0.015, 0.2, 1)
        ra.box("label", (0.18, 0.01, 0.1), (0, -0.155, 0.13), ra.plain("ic_clabel", (0.7, 0.15, 0.08), 0.6))

    def concrete():
        mat = ra.plain("ic_concrete", (0.33, 0.32, 0.3), 0.9, variation=0.2, scale=18, bump=0.4)
        ra.box("block", (0.32, 0.2, 0.18), (0, 0, 0.09), mat, bevel=0.01)
        for x in (-0.07, 0.07):
            ra.box("hole", (0.08, 0.1, 0.005), (x, 0, 0.181), ra.plain("ic_hole", (0.06, 0.06, 0.06), 0.9))

    def dates():
        mat = ra.plain("ic_date", (0.33, 0.12, 0.03), 0.4, variation=0.3, bump=0.5)
        for k in range(9):
            a = k * 2.4
            r = 0.04 + (k % 3) * 0.05
            ra.sphere("date", 0.045, (math.cos(a) * r, math.sin(a) * r, 0.04 + (k > 6) * 0.05), mat, scale=(1, 1, 1.6), segments=10,
                      ).rotation_euler = (random.uniform(-1, 1), random.uniform(-1, 1), 0)
        ra.cylinder("stalk", 0.012, 0.3, (0, 0.05, 0.12), ra.plain("ic_stalk", (0.3, 0.22, 0.08), 0.8), rotation=(math.radians(70), 0, 0), verts=6)

    def ammonite():
        shell = ra.plain("ic_ammonite", (0.42, 0.33, 0.22), 0.6, variation=0.3, scale=14, bump=0.6)
        for k in range(16):
            t = k / 16
            a = t * math.tau * 2.2
            r = 0.03 + t * 0.16
            ra.sphere("whorl", 0.025 + t * 0.06, (math.cos(a) * r * 0.6, 0, 0.18 + math.sin(a) * r * 0.6), shell, segments=10)

    def coin():
        gold = ra.plain("ic_coin", (0.75, 0.52, 0.12), 0.3, 1.0, variation=0.2, bump=0.4)
        ra.cylinder("coin", 0.16, 0.03, (0, 0, 0.2), gold, rotation=(math.radians(70), 0, 0), verts=32)
        ra.torus("rim", 0.15, 0.012, (0, -0.012, 0.2), gold, rotation=(math.radians(70), 0, 0))
        ra.sphere("head", 0.06, (0, -0.02, 0.21), gold, scale=(0.8, 0.3, 1), segments=12)

    def bone():
        mat = ra.plain("ic_bone", (0.68, 0.6, 0.45), 0.7, variation=0.2, scale=20, bump=0.3)
        ra.cylinder("shaft", 0.045, 0.38, (0, 0, 0.06), mat, rotation=(0, math.radians(90), math.radians(25)), verts=14)
        for s in (-1, 1):
            for d in (-1, 1):
                ra.sphere("knob", 0.06, (s * 0.18 * math.cos(math.radians(25)) + d * 0.03, s * 0.18 * math.sin(math.radians(25)) - d * 0.04, 0.06),
                          mat, segments=12)

    return {
        "item_glass": glass, "item_window_pane": window_pane, "item_glass_bottles": bottles, "item_mirror": mirror,
        "item_optical_fiber": fiber, "item_silicon": silicon, "item_silicon_wafer": wafer, "item_water": water,
        "item_clay": lump("ic_clay", (0.35, 0.16, 0.08)), "item_adobe_bricks": adobe, "item_cement": cement, "item_concrete": concrete,
        "item_dates": dates, "item_ammonite": ammonite, "item_ancient_coin": coin, "item_dinosaur_bone": bone,
    }


# --- Glacier --------------------------------------------------------------------------------------

def glacier_mats():
    """The paint of the glacier: ice, snow, red polar timber and steel, the warm glow of windows in the cold."""
    return {
        "ice": ra.plain("gl_ice", (0.42, 0.62, 0.78), 0.12, variation=0.25, scale=5, grime=0.05, bump=0.4),
        "deep": ra.plain("gl_deep", (0.1, 0.25, 0.42), 0.1, variation=0.3, scale=6, grime=0.05, bump=0.3),
        "snow": ra.plain("gl_snow", (0.8, 0.82, 0.86), 0.7, variation=0.06, scale=20, grime=0.0, bump=0.4),
        "red": ra.plain("gl_red", (0.42, 0.04, 0.03), 0.6, variation=0.15, grime=0.4),
        "white": ra.plain("gl_white", (0.7, 0.71, 0.7), 0.45, 0.2, variation=0.08, grime=0.3),
        "steel": ra.rusty_metal("gl_steel", (0.32, 0.33, 0.35), rust=0.08),
        "dark": ra.rusty_metal("gl_dark", (0.04, 0.045, 0.05), rust=0.1),
        "timber": ra.wood("gl_timber", (0.22, 0.13, 0.06)),
        "concrete": ra.plain("gl_concrete", (0.3, 0.3, 0.3), 0.9, variation=0.15),
        "window": ra.emission("gl_window", (1.0, 0.68, 0.3), 5.0),
        "glow": ra.emission("gl_glow", (1.0, 0.4, 0.06), 6.0),
        "screen": ra.emission("gl_screen", (0.2, 0.7, 1.0), 4.0),
        "led": ra.emission("gl_led", (0.2, 1.0, 0.3), 5.0),
        "orange": ra.plain("gl_orange", (0.7, 0.22, 0.02), 0.45, 0.2, variation=0.1, grime=0.3),
        "fur": ra.plain("gl_fur", (0.35, 0.33, 0.3), 0.95, variation=0.3, scale=30, bump=0.6),
    }


def ice_block(size, seed):
    random.seed(seed)
    m = glacier_mats()
    main = ra.box("ice", (size, size * 0.8, size * 0.7), (0, 0, size * 0.3), m["ice"], rotation=(0.1, -0.08, random.uniform(0, 1)))
    ra.displace(main, size * 0.08, 0.6, 2)
    for _ in range(3):
        a = random.random() * math.tau
        s = ra.box("ice_shard", (size * 0.3, size * 0.25, size * 0.4), (math.cos(a) * size * 0.55, math.sin(a) * size * 0.45, size * 0.12),
                   m["ice"], rotation=(random.uniform(-0.4, 0.4), random.uniform(-0.4, 0.4), a))
        ra.displace(s, size * 0.04, 0.4, 1)
    ra.sphere("ice_snowcap", size * 0.45, (0, 0, size * 0.62), m["snow"], scale=(1.1, 0.9, 0.25), segments=14)
    return meshes()


def meteorite():
    m = glacier_mats()
    crater = ra.sphere("met_crater", 0.9, (0, 0, -0.05), m["snow"], scale=(1.2, 1, 0.18), segments=20)
    ra.displace(crater, 0.06, 0.4, 1)
    stone = ra.sphere("met_stone", 0.42, (0, 0, 0.32), ra.rusty_metal("met_iron", (0.06, 0.055, 0.05), rust=0.45, scale=8),
                      scale=(1.1, 0.9, 0.8), segments=16)
    ra.displace(stone, 0.12, 0.35, 2)
    for k in range(5):
        a = k * 1.3
        ra.box("met_crack", (0.25, 0.02, 0.02), (math.cos(a) * 0.3, math.sin(a) * 0.25, 0.3 + (k % 2) * 0.1), m["glow"],
               rotation=(0.3 * k, 0.5, a))
    return meshes()


def snowdrift(size):
    m = glacier_mats()
    d = ra.sphere("drift", size / 2, (0, 0, -size * 0.1), m["snow"], scale=(1.25, 0.95, 0.5), segments=24)
    ra.displace(d, size * 0.07, 0.5, 2)
    return meshes()


def crevasse_tile(bridged):
    """A tile of glacier split by a crevasse (2 m square, flat, laid on the ground like the road); bridged, with planks over it."""
    m = glacier_mats()
    ra.box("cv_lip", (2.0, 2.0, 0.02), (0, 0, 0.0), m["snow"])
    gap = ra.box("cv_gap", (2.05, 0.8, 0.03), (0, 0, 0.012), m["deep"], rotation=(0, 0, 0.08))
    ra.displace(gap, 0.08, 0.5, 2)
    ra.box("cv_dark", (2.05, 0.4, 0.035), (0, 0, 0.016), ra.plain("gl_abyss", (0.01, 0.03, 0.06), 0.3, grime=0.0), rotation=(0, 0, 0.08))
    if bridged:
        for k in range(5):
            ra.box("cv_plank", (0.32, 1.6, 0.06), (-0.7 + k * 0.35, 0, 0.05), m["timber"], bevel=0.01)
        for x in (-0.9, 0.9):
            ra.box("cv_beam", (0.1, 1.9, 0.08), (x, 0, 0.09), ra.wood("gl_beam", (0.14, 0.08, 0.04)))
    return meshes()


def blades(hub, radius, width, mat, spin=0.3):
    """Three blades turning about the y axis at `hub`, facing south."""
    for k in range(3):
        a = spin + k * math.tau / 3
        mid = hub + Vector((math.cos(a) * radius / 2, -0.05, math.sin(a) * radius / 2))
        ra.box("wt_blade", (radius, 0.04, width), mid, mat, rotation=(0, -a, 0), bevel=0.01)


def build_wind_turbine():
    """A small wind turbine: a white mast on a concrete pad, a nacelle and three long blades turning to the south."""
    m = glacier_mats()
    ra.box("wt_pad", (0.8, 0.8, 0.1), (0, 0, 0.05), m["concrete"])
    ra.cylinder("wt_mast", 0.09, 3.0, (0, 0, 1.55), m["white"], verts=16, radius2=0.06)
    ra.box("wt_nacelle", (0.22, 0.45, 0.22), (0, 0.05, 3.1), m["white"], bevel=0.04)
    ra.sphere("wt_hub", 0.1, (0, -0.2, 3.1), m["white"], segments=12)
    blades(Vector((0, -0.25, 3.1)), 1.1, 0.12, m["white"])
    ra.box("wt_stripe", (0.06, 0.02, 0.15), (0, -0.25, 2.55), m["red"])
    ra.box("wt_box", (0.2, 0.14, 0.24), (0.25, -0.2, 0.22), m["dark"])


def build_large_wind_turbine():
    """A large wind turbine on 3 × 3 tiles: a tall tapered tower, a big nacelle and blades of 3 m, with a red tip on each."""
    m = glacier_mats()
    ra.box("lw_ground", (5.6, 5.6, 0.02), (0, 0, 0.01), m["snow"])
    ra.cylinder("lw_base", 0.9, 0.3, (0, 0.3, 0.15), m["concrete"], verts=24)
    ra.cylinder("lw_tower", 0.32, 6.6, (0, 0.3, 3.6), m["white"], verts=24, radius2=0.18)
    ra.box("lw_nacelle", (0.5, 1.1, 0.5), (0, 0.45, 7.0), m["white"], bevel=0.08)
    ra.sphere("lw_hub", 0.22, (0, -0.15, 7.0), m["white"], scale=(1, 1.4, 1), segments=14)
    blades(Vector((0, -0.25, 7.0)), 3.1, 0.25, m["white"], spin=0.9)
    for k in range(3):
        a = 0.9 + k * math.tau / 3
        ra.box("lw_tip", (0.4, 0.05, 0.2), Vector((0, -0.3, 7.0)) + Vector((math.cos(a) * 2.9, 0, math.sin(a) * 2.9)), m["red"], rotation=(0, -a, 0))
    ra.box("lw_house", (1.0, 0.7, 0.7), (1.4, -0.8, 0.35), m["white"], bevel=0.03)
    ra.box("lw_door", (0.3, 0.02, 0.5), (1.4, -1.16, 0.3), m["dark"])
    ra.light("POINT", (0, 0.45, 7.35), 5, (1, 0.1, 0.05), size=0.05)
    ra.sphere("lw_beacon", 0.06, (0, 0.45, 7.3), ra.emission("gl_beacon", (1, 0.1, 0.05), 20.0), segments=8)


def build_heater():
    """A heater: a squat iron stove with a glowing grate and a tall flue, a heap of coal at its side."""
    m = glacier_mats()
    ra.box("ht_pad", (1.1, 0.9, 0.06), (0, 0, 0.03), m["concrete"])
    ra.cylinder("ht_body", 0.35, 0.7, (0, 0, 0.41), m["dark"], verts=20)
    ra.cylinder("ht_top", 0.38, 0.05, (0, 0, 0.78), m["steel"], verts=20)
    ra.box("ht_grate", (0.3, 0.04, 0.18), (0, -0.34, 0.3), m["glow"])
    for k in range(3):
        ra.box("ht_bar", (0.02, 0.05, 0.2), (-0.1 + k * 0.1, -0.36, 0.3), m["dark"])
    ra.cylinder("ht_flue", 0.07, 1.2, (0.1, 0.1, 1.38), m["steel"], verts=12)
    ra.cylinder("ht_cap", 0.12, 0.05, (0.1, 0.1, 2.0), m["dark"], verts=12, radius2=0.04)
    coal = ra.plain("gl_coal", (0.02, 0.02, 0.02), 0.6, variation=0.3, bump=0.8)
    for k in range(5):
        ra.sphere("ht_coal", 0.08, (0.4 + (k % 3) * 0.06, -0.15 + k * 0.05, 0.08 + (k > 2) * 0.06), coal, segments=6)


def build_ice_melter():
    """An ice melter: a steel vat on a brick fire, blocks of ice in a hopper on top and a tap of water at its side."""
    m = glacier_mats()
    ra.box("im_fire", (1.0, 0.8, 0.35), (0, 0, 0.175), ra.plain("gl_brick", (0.3, 0.11, 0.06), 0.9, variation=0.35, scale=10, bump=0.5))
    ra.box("im_mouth", (0.3, 0.02, 0.15), (0, -0.41, 0.15), m["glow"])
    ra.cylinder("im_vat", 0.38, 0.5, (0, 0, 0.6), m["steel"], verts=24)
    ra.cylinder("im_hopper", 0.3, 0.25, (0, 0, 0.97), m["dark"], verts=4, radius2=0.42)
    for k in range(4):
        ra.box("im_ice", (0.16, 0.16, 0.14), (-0.12 + (k % 2) * 0.22, -0.1 + (k // 2) * 0.2, 1.12), m["ice"], rotation=(0.2, 0.1, k))
    ra.cylinder("im_tap", 0.04, 0.3, (0.45, -0.1, 0.45), m["steel"], rotation=(0, math.radians(90), 0), verts=10)
    ra.cylinder("im_bucket", 0.1, 0.16, (0.6, -0.1, 0.08), ra.plain("gl_bucket", (0.15, 0.3, 0.6), 0.4), verts=14)


def build_cold_store():
    """A cold store: an insulated white box with a heavy door, a frosted condenser on the roof and ice blocks stacked by it."""
    m = glacier_mats()
    ra.box("cs_floor", (1.6, 1.2, 0.06), (0, 0, 0.03), m["concrete"])
    ra.box("cs_box", (1.3, 0.9, 0.95), (0, 0.1, 0.52), ra.corrugated("cs_sheet", (0.62, 0.64, 0.66), 0.05), bevel=0.03)
    ra.box("cs_door", (0.45, 0.04, 0.75), (-0.2, -0.36, 0.45), m["white"], bevel=0.02)
    ra.box("cs_handle", (0.04, 0.05, 0.2), (0.0, -0.39, 0.45), m["dark"])
    ra.box("cs_condenser", (0.5, 0.4, 0.25), (0.25, 0.2, 1.12), m["steel"])
    ra.cylinder("cs_fan", 0.15, 0.03, (0.25, 0.2, 1.26), m["dark"], verts=16)
    ra.box("cs_frost", (1.32, 0.92, 0.04), (0, 0.1, 1.0), m["snow"])
    for k in range(3):
        ra.box("cs_ice", (0.2, 0.2, 0.18), (0.55, -0.35 + k * 0.02, 0.15 + k * 0.18), m["ice"], rotation=(0, 0, 0.2 * k))


def build_server_room():
    """A server room: a container with rows of racks lit blue and green behind glass, and cooling fins along its roof."""
    m = glacier_mats()
    ra.box("sr_pad", (1.6, 1.0, 0.06), (0, 0, 0.03), m["concrete"])
    ra.box("sr_box", (1.4, 0.8, 0.9), (0, 0.05, 0.51), ra.corrugated("sr_sheet", (0.12, 0.16, 0.22), 0.05), bevel=0.02)
    ra.box("sr_glass", (1.0, 0.02, 0.6), (-0.1, -0.36, 0.5), ra.plain("gl_glass", (0.05, 0.1, 0.15), 0.05, grime=0.05))
    for k in range(4):
        ra.box("sr_rack", (0.18, 0.02, 0.52), (-0.48 + k * 0.25, -0.37, 0.5), m["dark"])
        for j in range(5):
            ra.box("sr_led", (0.12, 0.01, 0.015), (-0.48 + k * 0.25, -0.385, 0.3 + j * 0.1), m["screen"] if (j + k) % 3 else m["led"])
    for k in range(6):
        ra.box("sr_fin", (0.03, 0.6, 0.15), (-0.55 + k * 0.22, 0.05, 1.03), m["steel"])
    ra.box("sr_ice", (0.3, 0.3, 0.25), (0.6, -0.3, 0.19), m["ice"], rotation=(0, 0, 0.3))


def build_ice_core_drill():
    """An ice core drill: a red derrick over a hole in the ice, a winch drum and long cylinders of core laid in a rack."""
    m = glacier_mats()
    ra.cylinder("cd_hole", 0.18, 0.03, (0, 0, 0.015), ra.plain("gl_abyss2", (0.01, 0.03, 0.06), 0.3, grime=0.0), verts=16)
    for a in (0.6, 2.6, 4.6):
        ra.box("cd_leg", (0.05, 0.05, 1.7), (math.cos(a) * 0.35, math.sin(a) * 0.35, 0.8), m["red"],
               rotation=(math.sin(a) * 0.2, -math.cos(a) * 0.2, 0))
    ra.box("cd_head", (0.25, 0.25, 0.15), (0, 0, 1.65), m["red"])
    ra.cylinder("cd_rod", 0.05, 1.4, (0, 0, 0.9), m["steel"], verts=10)
    ra.cylinder("cd_drum", 0.15, 0.35, (0.55, 0.1, 0.22), m["dark"], rotation=(math.radians(90), 0, 0), verts=16)
    ra.box("cd_engine", (0.3, 0.3, 0.25), (0.55, 0.45, 0.15), m["orange"], bevel=0.02)
    ra.box("cd_rack", (0.9, 0.3, 0.05), (-0.3, -0.5, 0.15), m["timber"])
    for k in range(3):
        ra.cylinder("cd_core", 0.05, 0.8, (-0.3, -0.58 + k * 0.08, 0.22), m["ice"], rotation=(0, math.radians(90), 0), verts=12)


def build_polar_station():
    """A polar research station: a red hut on stilts above the snow, a lit window, a weather mast with cups turning and a dish."""
    m = glacier_mats()
    for x in (-0.5, 0.5):
        for y in (-0.3, 0.3):
            ra.box("ps_stilt", (0.08, 0.08, 0.4), (x, y, 0.2), m["steel"])
    ra.box("ps_hut", (1.3, 0.8, 0.65), (0, 0, 0.73), m["red"], bevel=0.04)
    ra.box("ps_roof", (1.36, 0.86, 0.06), (0, 0, 1.08), m["white"])
    for x in (-0.35, 0.2):
        ra.box("ps_window", (0.25, 0.02, 0.2), (x, -0.41, 0.8), m["window"])
    ra.box("ps_stairs", (0.3, 0.4, 0.05), (0.5, -0.6, 0.2), m["steel"], rotation=(0.6, 0, 0))
    ra.cylinder("ps_mast", 0.025, 1.0, (-0.5, 0.2, 1.6), m["steel"], verts=8)
    for k in range(3):
        a = k * math.tau / 3
        ra.sphere("ps_cup", 0.05, (-0.5 + math.cos(a) * 0.15, 0.2 + math.sin(a) * 0.15, 2.05), m["white"], segments=8)
    ra.sphere("ps_dish", 0.25, (0.4, 0.2, 1.3), m["white"], scale=(1, 0.35, 1), segments=16)


def build_ice_hotel():
    """An ice hotel on 3 × 3 tiles: domes and walls of blocks of ice lit warm from within, a vaulted gate and torches."""
    m = glacier_mats()
    ra.box("ih_ground", (5.6, 5.6, 0.02), (0, 0, 0.01), m["snow"])
    hall = ra.sphere("ih_hall", 1.6, (0, 0.6, 0.0), m["ice"], scale=(1.2, 1, 0.9), segments=28)
    ra.displace(hall, 0.04, 0.4, 1)
    for x in (-1.9, 1.9):
        dome = ra.sphere("ih_dome", 0.9, (x, 0.2, 0.0), m["ice"], segments=24)
        ra.displace(dome, 0.03, 0.4, 1)
        ra.box("ih_window", (0.25, 0.02, 0.25), (x, -0.68, 0.45), m["window"])
    ra.cylinder("ih_gate", 0.45, 0.8, (0, -1.1, 0.0), m["ice"], rotation=(math.radians(90), 0, 0), verts=20)
    ra.box("ih_door", (0.5, 0.02, 0.5), (0, -1.51, 0.25), m["window"])
    for k in range(8):
        ra.box("ih_block", (0.5, 0.25, 0.25), (-2.2 + k * 0.62, -1.8, 0.13), m["ice"], bevel=0.02)
    for x in (-0.7, 0.7):
        ra.cylinder("ih_torch", 0.03, 0.8, (x, -1.6, 0.4), m["timber"], verts=8)
        ra.sphere("ih_flame", 0.07, (x, -1.6, 0.85), m["glow"], scale=(1, 1, 1.5), segments=8)
        ra.light("POINT", (x, -1.7, 0.95), 15, (1.0, 0.6, 0.3), size=0.1)
    ra.light("POINT", (0, 0.6, 0.6), 60, (1.0, 0.65, 0.35), size=0.5)


def build_viewpoint():
    """A viewpoint: a timber deck on posts with a railing, a coin telescope and a bench, for watching the aurora."""
    m = glacier_mats()
    for x in (-0.55, 0.55):
        for y in (-0.4, 0.4):
            ra.box("vp_post", (0.08, 0.08, 0.6), (x, y, 0.3), m["timber"])
    ra.box("vp_deck", (1.3, 1.0, 0.06), (0, 0, 0.62), m["timber"])
    for x in (-0.6, 0.6):
        ra.box("vp_rail", (0.04, 1.0, 0.04), (x, 0, 0.95), m["timber"])
    ra.box("vp_rail", (1.24, 0.04, 0.04), (0, -0.48, 0.95), m["timber"])
    for x in (-0.6, -0.2, 0.2, 0.6):
        ra.box("vp_baluster", (0.03, 0.03, 0.32), (x, -0.48, 0.79), m["timber"])
    ra.cylinder("vp_scope_post", 0.03, 0.4, (0.3, -0.2, 0.85), m["dark"], verts=8)
    ra.cylinder("vp_scope", 0.05, 0.3, (0.3, -0.25, 1.08), m["steel"], rotation=(math.radians(70), 0, 0), verts=12)
    ra.box("vp_bench", (0.6, 0.2, 0.05), (-0.25, 0.25, 0.85), m["red"])
    ra.box("vp_stairs", (0.35, 0.5, 0.05), (0.75, 0.15, 0.32), m["timber"], rotation=(0, 0.7, 0))


def build_dog_kennel():
    """A dog kennel: a timber kennel and a sled loaded with a bundle, with two grey husky shapes lying in the snow."""
    m = glacier_mats()
    ra.box("dk_house", (0.6, 0.5, 0.4), (-0.4, 0.2, 0.2), m["timber"], bevel=0.02)
    gable_roof("dk_roof", 0.7, 0.6, 0.4, 0.62, m["red"], at=(-0.4, 0.2))
    ra.box("dk_door", (0.2, 0.02, 0.25), (-0.4, -0.06, 0.13), m["dark"])
    for y in (-0.15, 0.15):
        ra.box("dk_runner", (1.0, 0.04, 0.03), (0.35, y - 0.25, 0.03), m["dark"])
    ra.box("dk_bed", (0.8, 0.34, 0.04), (0.35, -0.25, 0.14), m["timber"])
    ra.box("dk_load", (0.5, 0.28, 0.2), (0.3, -0.25, 0.26), ra.plain("gl_canvas", (0.35, 0.3, 0.18), 0.9), bevel=0.04)
    for x, y in ((0.1, -0.7), (0.6, -0.65)):
        ra.sphere("dk_dog", 0.14, (x, y, 0.1), m["fur"], scale=(1.6, 0.8, 0.7), segments=12)
        ra.sphere("dk_head", 0.08, (x + 0.2, y - 0.02, 0.16), m["fur"], segments=10)


def build_snowmobile_garage():
    """A snowmobile garage: a corrugated shed with an open door and an orange snowmobile with skis in front of it."""
    m = glacier_mats()
    ra.box("sg_floor", (1.6, 1.3, 0.04), (0, 0, 0.02), m["concrete"])
    ra.box("sg_shed", (1.4, 0.8, 0.8), (0, 0.25, 0.42), ra.corrugated("sg_sheet", (0.25, 0.27, 0.3), 0.2), bevel=0.02)
    ra.box("sg_door", (0.8, 0.02, 0.6), (0, -0.16, 0.32), m["dark"])
    ra.box("sg_body", (0.65, 0.3, 0.2), (0.1, -0.5, 0.22), m["orange"], bevel=0.05)
    ra.box("sg_seat", (0.3, 0.22, 0.08), (0.2, -0.5, 0.35), m["dark"], bevel=0.02)
    ra.box("sg_screen", (0.05, 0.25, 0.12), (-0.12, -0.5, 0.38), ra.plain("gl_glass2", (0.1, 0.15, 0.2), 0.05, grime=0.05), rotation=(0, -0.5, 0))
    for y in (-0.62, -0.38):
        ra.box("sg_ski", (0.55, 0.05, 0.02), (-0.15, y, 0.04), m["dark"])
    ra.box("sg_track", (0.4, 0.25, 0.1), (0.25, -0.5, 0.07), m["dark"])
    ra.cylinder("sg_can", 0.08, 0.22, (0.6, -0.1, 0.13), m["red"], verts=12)


def build_track_foundation():
    """A track foundation: a long concrete sleeper bed on piles driven into the ice, with a section of steel rail laid over it."""
    m = glacier_mats()
    for x in (-0.7, 0.0, 0.7):
        ra.cylinder("tf_pile", 0.1, 0.4, (x, 0, 0.12), m["steel"], verts=10)
    ra.box("tf_slab", (1.9, 0.9, 0.15), (0, 0, 0.3), m["concrete"], bevel=0.02)
    for k in range(6):
        ra.box("tf_sleeper", (0.12, 0.8, 0.06), (-0.8 + k * 0.32, 0, 0.41), m["timber"])
    for y in (-0.22, 0.22):
        ra.box("tf_rail", (1.9, 0.05, 0.07), (0, y, 0.47), m["steel"])
    ra.box("tf_sign", (0.25, 0.03, 0.18), (0.8, -0.5, 0.55), m["orange"])
    ra.cylinder("tf_sign_post", 0.02, 0.4, (0.8, -0.5, 0.3), m["dark"], verts=6)


GLACIER_NATURE = {
    "ice_block_0": (160, 144, 0.6, lambda: ice_block(1.9, 21)),
    "ice_block_1": (160, 144, 0.5, lambda: ice_block(1.6, 22)),
    "meteorite_0": (160, 128, 0.35, meteorite),
    "snowdrift_0": (160, 112, 0.3, lambda: snowdrift(2.5)),
    "snowdrift_1": (160, 112, 0.3, lambda: snowdrift(2.1)),
}

GLACIER = {
    # name: (canvas width, height, camera target height, builder); the ice hotel stands on 3 × 3 tiles.
    "ice_melter": (112, 128, 0.55, build_ice_melter),
    "cold_store": (128, 128, 0.55, build_cold_store),
    "server_room": (128, 128, 0.5, build_server_room),
    "ice_core_drill": (128, 152, 0.8, build_ice_core_drill),
    "polar_station": (128, 160, 0.9, build_polar_station),
    "ice_hotel": (256, 224, 0.8, build_ice_hotel),
    "viewpoint": (112, 128, 0.6, build_viewpoint),
    "dog_kennel": (128, 104, 0.3, build_dog_kennel),
    "snowmobile_garage": (128, 112, 0.4, build_snowmobile_garage),
    "track_foundation": (136, 96, 0.3, build_track_foundation),
}

GLACIER_POWER = {
    "wind_turbine": (128, 272, 1.8, build_wind_turbine, Vector((0.25, -0.2, 0.3))),
    "large_wind_turbine": (288, 544, 3.8, build_large_wind_turbine, Vector((1.4, -0.8, 0.7))),
    "heater": (112, 144, 0.7, build_heater, Vector((0.3, 0.1, 0.6))),
}


def render_glacier(layout: dict, only=()):
    for name, (w, h, tz, build) in GLACIER_NATURE.items():
        if only and name not in only:
            continue
        random.seed(zlib.crc32(name.encode()))
        layout[name] = render_sprite(name, w, h, Vector((0, 0, tz)), build)
    for name, bridged in (("crevasse", False), ("bridge", True)):
        if only and name not in only:
            continue
        random.seed(zlib.crc32(name.encode()))
        layout[name] = render_sprite(name, 112, 96, Vector((0, 0, 0)), lambda b=bridged: crevasse_tile(b))
    for name, (w, h, tz, build) in GLACIER.items():
        if only and name not in only:
            continue
        random.seed(zlib.crc32(name.encode()))
        layout[name] = render_sprite(name, w, h, Vector((0, 0, tz)), crafted(build), true_scale=True)
        ra.icon_from(Image.open(OUT / f"{name}.png").convert("RGBA"), ICONS / f"furniture_{name}.png")
    for name, (w, h, tz, build, wire) in GLACIER_POWER.items():
        if only and name not in only:
            continue
        random.seed(zlib.crc32(name.encode()))
        target = Vector((0, 0, tz))
        layout[name] = render_sprite(name, w, h, target, crafted(build), true_scale=True)
        layout[name]["wireX"], layout[name]["wireY"] = anchor(w, h, target, wire)
        ra.icon_from(Image.open(OUT / f"{name}.png").convert("RGBA"), ICONS / f"item_power_{name}.png")


def glacier_icon_models():
    """Icons of what the glacier gives up and makes."""
    def ice():
        mat = ra.plain("ic_ice", (0.42, 0.62, 0.78), 0.12, variation=0.25, scale=5, grime=0.05, bump=0.4)
        for k, (x, y, z) in enumerate(((-0.1, 0, 0.08), (0.1, 0.03, 0.08), (0, -0.02, 0.22))):
            c = ra.box("cube", (0.17, 0.17, 0.15), (x, y, z), mat, bevel=0.02, rotation=(0.1 * k, 0.05, 0.3 * k))
            ra.displace(c, 0.01, 0.2, 1)

    def metal_lump(name, color, glow=False):
        def build():
            mat = ra.rusty_metal(name, color, rust=0.3, scale=8)
            c = ra.sphere("lump", 0.17, (0, 0, 0.12), mat, scale=(1.2, 1, 0.8), segments=14)
            ra.displace(c, 0.05, 0.2, 2)
            if glow:
                ra.sphere("sheen", 0.05, (0.08, -0.12, 0.2), ra.plain("ic_irid", (0.75, 0.78, 0.85), 0.1, 1.0, grime=0.0), segments=10)
        return build

    def iridium():
        mat = ra.plain("ic_iridium", (0.72, 0.75, 0.8), 0.15, 1.0, variation=0.1, grime=0.1)
        ra.box("bar", (0.34, 0.14, 0.09), (0, 0, 0.05), mat, bevel=0.025)
        ra.box("bar2", (0.34, 0.14, 0.09), (0.02, 0.03, 0.14), mat, bevel=0.025, rotation=(0, 0, 0.3))

    def pickaxe():
        head = ra.rusty_metal("ic_mpick", (0.08, 0.07, 0.06), rust=0.5, scale=8)
        ra.cylinder("handle", 0.022, 0.5, (0, 0, 0.2), ra.wood("ic_mhandle", (0.25, 0.15, 0.07)), rotation=(0, math.radians(30), 0), verts=10)
        ra.box("head", (0.42, 0.06, 0.06), (0.12, 0, 0.42), head, rotation=(0, math.radians(30), 0), bevel=0.02)
        ra.box("glow", (0.12, 0.065, 0.015), (0.14, 0, 0.44), ra.emission("ic_mglow", (1.0, 0.4, 0.06), 4.0), rotation=(0, math.radians(30), 0))

    def frozen(color):
        def build():
            fish("ic_ffish", 0.42, color, (0.7, 0.68, 0.62), at=(0, 0, 0.07))
            frost = ra.plain("ic_frost", (0.6, 0.75, 0.88), 0.15, variation=0.2, grime=0.0)
            for k in range(4):
                ra.box("cube", (0.09, 0.09, 0.08), (-0.18 + k * 0.12, 0.12 - (k % 2) * 0.25, 0.04), frost, bevel=0.01, rotation=(0, 0, 0.4 * k))
        return build

    def ice_cream():
        cone = ra.plain("ic_cone", (0.55, 0.32, 0.1), 0.8, variation=0.2, scale=30, bump=0.6)
        ra.cylinder("cone", 0.01, 0.28, (0, 0, 0.14), cone, radius2=0.09, verts=16)
        ra.sphere("scoop", 0.1, (0, 0, 0.32), ra.plain("ic_vanilla", (0.85, 0.75, 0.5), 0.6, grime=0.0), segments=16)
        ra.sphere("scoop2", 0.08, (0.02, 0, 0.43), ra.plain("ic_pink", (0.8, 0.35, 0.45), 0.6, grime=0.0), segments=16)

    def chip():
        ra.box("chip", (0.3, 0.3, 0.04), (0, 0, 0.03), ra.plain("ic_chip", (0.04, 0.05, 0.06), 0.4))
        for k in range(6):
            for s in (-1, 1):
                ra.box("pin", (0.025, 0.06, 0.01), (-0.12 + k * 0.048, s * 0.17, 0.02), ra.plain("ic_pin", (0.7, 0.55, 0.2), 0.3, 1.0))
        ra.box("core", (0.12, 0.12, 0.01), (0, 0, 0.055), ra.emission("ic_core_glow", (0.2, 0.7, 1.0), 4.0))

    def ice_core():
        mat = ra.plain("ic_icecore", (0.5, 0.68, 0.82), 0.1, variation=0.2, grime=0.05)
        ra.cylinder("core", 0.07, 0.42, (0, 0, 0.08), mat, rotation=(0, math.radians(90), math.radians(20)), verts=16)
        for k in range(4):
            ra.cylinder("layer", 0.072, 0.012, (-0.15 + k * 0.1, 0, 0.08), ra.plain("ic_layer", (0.3, 0.35, 0.4), 0.3),
                        rotation=(0, math.radians(90), math.radians(20)), verts=16)

    def notes():
        paper = ra.plain("ic_paper", (0.75, 0.73, 0.68), 0.8, grime=0.1)
        for k in range(3):
            ra.box("sheet", (0.3, 0.38, 0.01), (k * 0.02, -k * 0.015, 0.01 + k * 0.012), paper, rotation=(0, 0, 0.1 * k))
        for j in range(5):
            ra.box("line", (0.22, 0.012, 0.003), (0.04, 0.12 - j * 0.06, 0.05), ra.plain("ic_ink", (0.05, 0.1, 0.3), 0.5))
        ra.box("graph", (0.12, 0.012, 0.004), (0.06, -0.15, 0.052), ra.plain("ic_red_ink", (0.6, 0.05, 0.03), 0.5), rotation=(0, 0, 0.5))

    def takings():
        gold = ra.plain("ic_tcoin", (0.75, 0.52, 0.12), 0.3, 1.0, variation=0.2, bump=0.4)
        for k in range(4):
            ra.cylinder("coin", 0.12, 0.025, (0.02 * k, 0, 0.013 + k * 0.027), gold, verts=28)
        ra.box("ticket", (0.2, 0.1, 0.005), (0.15, -0.12, 0.02), ra.plain("ic_ticket", (0.15, 0.35, 0.6), 0.6), rotation=(0, 0, 0.4))

    return {
        "item_ice": ice, "item_meteoric_iron": metal_lump("ic_metiron", (0.12, 0.1, 0.09)), "item_iridium": iridium,
        "item_tool_meteorite_pickaxe": pickaxe, "item_frozen_fish": frozen((0.25, 0.27, 0.22)),
        "item_frozen_salmon": frozen((0.55, 0.25, 0.18)), "item_ice_cream": ice_cream, "item_computing_power": chip,
        "item_ice_core": ice_core, "item_research_data": notes, "item_tourist_takings": takings,
    }


# --- City -----------------------------------------------------------------------------------------

def city_mats():
    """The paint of the city: plaster, brick, concrete and glass, shop awnings and lit windows."""
    return {
        "plaster": ra.plain("ct_plaster", (0.55, 0.5, 0.42), 0.8, variation=0.12, scale=8, grime=0.4),
        "brick": ra.plain("ct_brick", (0.3, 0.09, 0.05), 0.85, variation=0.35, scale=14, bump=0.5),
        "concrete": ra.plain("ct_concrete", (0.32, 0.32, 0.31), 0.9, variation=0.15),
        "glass": ra.plain("ct_glass", (0.05, 0.1, 0.14), 0.05, 0.3, variation=0.05, grime=0.1),
        "steel": ra.rusty_metal("ct_steel", (0.3, 0.31, 0.33), rust=0.08),
        "dark": ra.rusty_metal("ct_dark", (0.04, 0.045, 0.05), rust=0.1),
        "blue": ra.plain("ct_blue", (0.05, 0.15, 0.4), 0.5, 0.2, variation=0.1, grime=0.3),
        "red": ra.plain("ct_red", (0.45, 0.05, 0.04), 0.6, variation=0.15, grime=0.3),
        "green": ra.plain("ct_green", (0.08, 0.3, 0.12), 0.6, variation=0.15, grime=0.3),
        "yellow": ra.plain("ct_yellow", (0.7, 0.5, 0.05), 0.5, variation=0.1, grime=0.3),
        "white": ra.plain("ct_white", (0.72, 0.72, 0.7), 0.45, 0.2, variation=0.08, grime=0.3),
        "window": ra.emission("ct_window", (1.0, 0.72, 0.38), 3.0),
        "sign": ra.emission("ct_sign", (0.3, 0.8, 1.0), 4.0),
        "timber": ra.wood("ct_timber", (0.22, 0.13, 0.06)),
        "asphalt": ra.plain("ct_asphalt", (0.05, 0.05, 0.055), 0.9, variation=0.2),
    }


def windows(prefix, x0, x1, y, z0, z1, cols, rows, m, lit=0.5):
    """A grid of windows on the front of a building (facing −y at `y`), some of them lit."""
    for c in range(cols):
        for r in range(rows):
            x = x0 + (x1 - x0) * (c + 0.5) / cols
            z = z0 + (z1 - z0) * (r + 0.5) / rows
            ra.box(prefix, ((x1 - x0) / cols * 0.6, 0.02, (z1 - z0) / rows * 0.55), (x, y, z),
                   m["window"] if random.random() < lit else m["glass"])


def build_assembly_hall():
    """An assembly hall on 3 × 3 tiles: a long saw-tooth roofed shed of brick and steel, roller doors, a loading dock with a car on it."""
    m = city_mats()
    ra.box("ah_pad", (5.8, 5.8, 0.06), (0, 0, 0.03), m["concrete"])
    ra.box("ah_hall", (5.0, 3.8, 2.2), (0, 0.6, 1.16), m["brick"], bevel=0.03)
    for k in range(5):
        x = -2.0 + k * 1.0
        ra.mesh_from("ah_tooth", [(x - 0.5, -1.3, 2.26), (x + 0.5, -1.3, 2.26), (x + 0.5, 2.5, 2.26), (x - 0.5, 2.5, 2.26),
                                  (x + 0.5, -1.3, 2.9), (x + 0.5, 2.5, 2.9)],
                     [(0, 1, 4), (3, 5, 2), (0, 4, 5, 3), (1, 2, 5, 4), (0, 3, 2, 1)], m["steel"])
        ra.box("ah_skylight", (0.02, 3.7, 0.55), (x + 0.48, 0.6, 2.58), m["window"] if k % 2 else m["glass"])
    for x in (-1.5, 0.0, 1.5):
        ra.box("ah_door", (1.0, 0.04, 1.3), (x, -1.32, 0.71), ra.corrugated("ah_roller", (0.3, 0.32, 0.36), 0.1))
    ra.box("ah_band", (5.02, 0.04, 0.25), (0, -1.33, 1.6), m["blue"])
    ra.box("ah_dock", (2.0, 1.2, 0.3), (-1.4, -2.0, 0.15), m["concrete"])
    ra.box("ah_car", (0.9, 0.45, 0.28), (-1.4, -2.0, 0.48), m["red"], bevel=0.08)
    ra.box("ah_cabin", (0.5, 0.4, 0.2), (-1.45, -2.0, 0.7), m["glass"], bevel=0.05)
    for x in (-1.75, -1.05):
        for y in (-2.22, -1.78):
            ra.cylinder("ah_wheel", 0.1, 0.06, (x, y, 0.38), m["dark"], rotation=(math.radians(90), 0, 0), verts=14)
    for k in range(3):
        ra.box("ah_crate", (0.4, 0.4, 0.35), (1.2 + k * 0.45, -2.1, 0.24), m["timber"], bevel=0.02)
    ra.cylinder("ah_stack", 0.18, 1.6, (2.2, 2.0, 3.0), m["steel"], verts=16)


def build_multistorey_factory():
    """A multi-storey factory: a narrow tower of concrete floors with ribbon windows lit inside, a goods lift up its side and roof fans."""
    m = city_mats()
    ra.box("mf_pad", (1.7, 1.5, 0.05), (0, 0, 0.025), m["concrete"])
    for k in range(5):
        ra.box("mf_floor", (1.4, 1.1, 0.08), (0, 0.1, 0.1 + k * 0.62), m["concrete"])
        ra.box("mf_ribbon", (1.36, 1.06, 0.5), (0, 0.1, 0.4 + k * 0.62), m["glass"])
        windows("mf_lit", -0.65, 0.65, -0.45, 0.18 + k * 0.62, 0.66 + k * 0.62, 5, 1, m, lit=0.6)
    ra.box("mf_roof", (1.44, 1.14, 0.1), (0, 0.1, 3.2), m["concrete"])
    ra.box("mf_lift", (0.3, 0.3, 3.3), (0.82, 0.1, 1.65), m["yellow"])
    for k in range(2):
        ra.cylinder("mf_fan", 0.18, 0.15, (-0.35 + k * 0.6, 0.25, 3.33), m["steel"], verts=16)
    ra.box("mf_sign", (0.8, 0.03, 0.18), (0, -0.47, 3.05), m["sign"])


def build_shop():
    """A corner shop: a brick front with a big lit shop window, a striped awning, crates of goods outside and a sign."""
    m = city_mats()
    ra.box("sh_pavement", (1.7, 1.4, 0.05), (0, 0, 0.025), m["concrete"])
    ra.box("sh_house", (1.4, 1.0, 1.5), (0, 0.15, 0.8), m["plaster"], bevel=0.02)
    ra.box("sh_window", (0.8, 0.02, 0.6), (-0.2, -0.36, 0.55), m["window"])
    ra.box("sh_door", (0.3, 0.02, 0.7), (0.45, -0.36, 0.4), m["dark"])
    for k in range(6):
        ra.box("sh_stripe", (0.24, 0.35, 0.03), (-0.6 + k * 0.24, -0.5, 1.02), m["red"] if k % 2 else m["white"], rotation=(-0.4, 0, 0))
    ra.box("sh_sign", (1.0, 0.04, 0.2), (0, -0.37, 1.35), m["green"])
    ra.box("sh_sign_text", (0.7, 0.01, 0.08), (0, -0.395, 1.35), m["window"])
    for k, color in enumerate(("red", "yellow", "green")):
        ra.box("sh_crate", (0.25, 0.2, 0.15), (-0.5 + k * 0.28, -0.6, 0.12), m["timber"], bevel=0.01)
        ra.sphere("sh_fruit", 0.09, (-0.5 + k * 0.28, -0.6, 0.22), m[color], scale=(1.2, 0.9, 0.5), segments=10)
    windows("sh_upper", -0.6, 0.6, -0.36, 1.05, 1.5, 3, 1, m, lit=0.4)


def build_high_bay():
    """A high-bay warehouse: a tall, windowless block of blue cladding with a stacker crane rail on top and a loading door."""
    m = city_mats()
    ra.box("hb_pad", (1.6, 1.4, 0.05), (0, 0, 0.025), m["concrete"])
    ra.box("hb_block", (1.3, 1.1, 2.8), (0, 0.1, 1.45), ra.corrugated("hb_sheet", (0.08, 0.18, 0.4), 0.05), bevel=0.02)
    ra.box("hb_door", (0.6, 0.03, 0.7), (0, -0.46, 0.4), ra.corrugated("hb_roller", (0.3, 0.32, 0.36), 0.1))
    for k in range(4):
        ra.box("hb_band", (1.32, 0.02, 0.04), (0, -0.46, 1.0 + k * 0.5), m["white"])
    ra.box("hb_rail", (1.4, 0.06, 0.06), (0, 0.1, 2.92), m["yellow"])
    ra.box("hb_pallet", (0.4, 0.4, 0.3), (0.5, -0.6, 0.2), m["timber"])


def build_city_sorter():
    """A municipal sorting plant: a green shed with a conveyor climbing from a heap of rubbish, coloured bins for what comes out."""
    m = city_mats()
    ra.box("cs2_pad", (1.7, 1.4, 0.05), (0, 0, 0.025), m["concrete"])
    ra.box("cs2_shed", (1.0, 0.9, 1.0), (0.25, 0.2, 0.55), ra.corrugated("cs2_sheet", (0.1, 0.28, 0.12), 0.2), bevel=0.02)
    ra.box("cs2_belt", (0.9, 0.25, 0.04), (-0.4, -0.05, 0.55), m["dark"], rotation=(0, -0.6, 0))
    heap = ra.sphere("cs2_heap", 0.3, (-0.65, -0.1, 0.05), ra.plain("cs2_trash", (0.2, 0.18, 0.14), 0.9, variation=0.6, scale=20),
                     scale=(1, 0.9, 0.6), segments=14)
    ra.displace(heap, 0.06, 0.2, 2)
    for k, color in enumerate(("blue", "yellow", "green", "red")):
        ra.box("cs2_bin", (0.22, 0.22, 0.3), (-0.3 + k * 0.28, -0.55, 0.2), m[color], bevel=0.02)


def build_freight_terminal():
    """A freight terminal: a long platform roof on steel columns over stacked shipping containers and a gantry crane."""
    m = city_mats()
    ra.box("ft_pad", (1.9, 1.5, 0.05), (0, 0, 0.025), m["concrete"])
    for x in (-0.8, 0.8):
        for y in (-0.55, 0.55):
            ra.box("ft_leg", (0.08, 0.08, 1.6), (x, y, 0.8), m["yellow"])
    ra.box("ft_beam", (1.8, 0.1, 0.12), (0, -0.55, 1.62), m["yellow"])
    ra.box("ft_beam", (1.8, 0.1, 0.12), (0, 0.55, 1.62), m["yellow"])
    ra.box("ft_trolley", (0.25, 1.2, 0.15), (0.2, 0, 1.55), m["dark"])
    ra.cylinder("ft_cable", 0.015, 0.6, (0.2, 0, 1.2), m["dark"], verts=6)
    colors = ("red", "blue", "green", "yellow")
    for k in range(3):
        for j in range(2):
            ra.box("ft_box", (0.7, 0.3, 0.3), (-0.4 + j * 0.85, -0.3 + k * 0.32, 0.2), ra.corrugated(f"ft_c{k}{j}",
                   ra_color(m, colors[(k + j) % 4]), 0.2))
    ra.box("ft_box", (0.7, 0.3, 0.3), (-0.4, 0.02, 0.51), ra.corrugated("ft_top", (0.5, 0.25, 0.05), 0.2))


def ra_color(m, name):
    return {"red": (0.45, 0.06, 0.04), "blue": (0.06, 0.18, 0.42), "green": (0.08, 0.32, 0.12), "yellow": (0.7, 0.5, 0.05)}[name]


def build_company_hq():
    """Company headquarters: a glass office tower with a stone foot, a lit logo on top and a flag at the door."""
    m = city_mats()
    marble = ra.plain("hq_marble", (0.7, 0.68, 0.64), 0.25, variation=0.2, scale=6, grime=0.1, bump=0.2)
    ra.box("hq_plaza", (1.8, 1.6, 0.05), (0, 0, 0.025), marble)
    ra.box("hq_foot", (1.4, 1.2, 0.6), (0, 0.1, 0.35), marble, bevel=0.02)
    ra.box("hq_tower", (1.1, 0.9, 3.0), (0, 0.15, 2.15), m["glass"])
    for k in range(10):
        ra.box("hq_floor", (1.12, 0.92, 0.03), (0, 0.15, 0.7 + k * 0.3), m["steel"])
    windows("hq_lit", -0.5, 0.5, -0.31, 0.7, 3.6, 4, 10, m, lit=0.35)
    ra.box("hq_logo", (0.6, 0.04, 0.25), (0, -0.32, 3.45), m["sign"])
    ra.box("hq_door", (0.4, 0.02, 0.4), (0, -0.51, 0.25), m["window"])
    ra.cylinder("hq_pole", 0.02, 1.0, (0.6, -0.6, 0.5), m["steel"], verts=8)
    ra.box("hq_flag", (0.3, 0.01, 0.18), (0.75, -0.6, 0.88), m["blue"])


def build_design_office():
    """A design office: a tidy two-storey office with tall windows, drawing boards seen inside and a rolled blueprint sign."""
    m = city_mats()
    ra.box("do_pavement", (1.6, 1.3, 0.05), (0, 0, 0.025), m["concrete"])
    ra.box("do_house", (1.3, 0.9, 1.6), (0, 0.15, 0.85), m["white"], bevel=0.02)
    windows("do_win", -0.6, 0.6, -0.31, 0.2, 1.55, 4, 2, m, lit=0.7)
    ra.box("do_roof", (1.36, 0.96, 0.08), (0, 0.15, 1.69), m["dark"])
    ra.cylinder("do_roll", 0.08, 0.7, (0, -0.4, 1.85), ra.plain("do_blueprint", (0.08, 0.2, 0.55), 0.6), rotation=(0, math.radians(90), 0), verts=14)
    ra.box("do_door", (0.3, 0.02, 0.5), (0.45, -0.31, 0.3), m["blue"])


def build_laboratory():
    """A laboratory: a white block with a row of fume hood chimneys on the roof, blue-lit windows and gas bottles by the wall."""
    m = city_mats()
    ra.box("lb_pad", (1.6, 1.3, 0.05), (0, 0, 0.025), m["concrete"])
    ra.box("lb_block", (1.3, 0.9, 1.1), (0, 0.15, 0.6), m["white"], bevel=0.02)
    for k in range(4):
        ra.box("lb_win", (0.22, 0.02, 0.35), (-0.45 + k * 0.3, -0.31, 0.65), m["sign"] if k % 2 else m["glass"])
    for k in range(3):
        ra.cylinder("lb_chimney", 0.06, 0.4, (-0.4 + k * 0.4, 0.35, 1.35), m["steel"], verts=12)
    ra.sphere("lb_dome", 0.25, (0.35, 0.0, 1.15), m["white"], scale=(1, 1, 0.7), segments=16)
    for k in range(3):
        ra.cylinder("lb_bottle", 0.06, 0.4, (-0.6 + k * 0.14, -0.45, 0.22), m["green"] if k % 2 else m["blue"], verts=12)


def build_service_workshop():
    """A service workshop: a brick garage with a raised door, a car on a lift inside, tyres stacked and a toolbox outside."""
    m = city_mats()
    ra.box("sw_pad", (1.7, 1.4, 0.05), (0, 0, 0.025), m["concrete"])
    ra.box("sw_back", (1.4, 0.9, 1.1), (0, 0.25, 0.6), m["brick"], bevel=0.02)
    ra.box("sw_opening", (0.9, 0.02, 0.7), (-0.15, -0.21, 0.4), m["window"])
    ra.box("sw_roller", (0.9, 0.04, 0.2), (-0.15, -0.22, 0.85), ra.corrugated("sw_roll", (0.3, 0.32, 0.36), 0.1))
    ra.box("sw_sign", (1.0, 0.03, 0.15), (0, -0.22, 1.05), m["red"])
    for k in range(3):
        ra.cylinder("sw_tyre", 0.15, 0.08, (0.55, -0.45, 0.06 + k * 0.09), m["dark"], verts=18)
    ra.box("sw_toolbox", (0.25, 0.15, 0.2), (-0.6, -0.5, 0.12), m["red"], bevel=0.02)



def build_tailor():
    """A tailor's workshop: a plaster shop with a striped awning, a shop window with a dressed mannequin,
    a pair of scissors over the door and rolls of cloth stacked outside."""
    m = city_mats()
    ra.box("tl_pavement", (1.6, 1.3, 0.05), (0, 0, 0.025), m["concrete"])
    ra.box("tl_house", (1.3, 0.9, 1.3), (0, 0.15, 0.7), m["plaster"], bevel=0.02)
    ra.box("tl_roof", (1.38, 0.98, 0.1), (0, 0.15, 1.4), m["brick"])
    ra.box("tl_sign", (0.9, 0.03, 0.16), (-0.1, -0.32, 1.22), m["blue"])
    ra.box("tl_sign_text", (0.7, 0.01, 0.05), (-0.1, -0.34, 1.22), m["window"])
    ra.box("tl_window", (0.6, 0.02, 0.55), (-0.25, -0.31, 0.5), m["glass"])
    ra.box("tl_window_glow", (0.56, 0.01, 0.5), (-0.25, -0.3, 0.5), ra.emission("tl_glow", (1.0, 0.8, 0.55), 1.2))
    # The mannequin in the window, in a navy jacket.
    navy = ra.plain("tl_suit", (0.04, 0.06, 0.16), 0.7)
    ra.cylinder("tl_body", 0.09, 0.3, (-0.25, -0.24, 0.55), navy, radius2=0.07, verts=16)
    ra.sphere("tl_head", 0.05, (-0.25, -0.24, 0.76), ra.plain("tl_dummy", (0.6, 0.5, 0.38), 0.6), segments=12)
    ra.cylinder("tl_stand", 0.012, 0.25, (-0.25, -0.24, 0.27), m["steel"], verts=8)
    ra.box("tl_door", (0.3, 0.02, 0.6), (0.4, -0.31, 0.35), m["timber"])
    # A striped awning over the window and the door.
    for k in range(8):
        ra.box("tl_awning", (0.15, 0.3, 0.02), (-0.53 + k * 0.15, -0.42, 0.93), m["red"] if k % 2 else m["white"],
               rotation=(math.radians(-22), 0, 0))
    # The sign: open scissors.
    gold = m["yellow"]
    for side in (-1, 1):
        ra.box("tl_blade", (0.03, 0.02, 0.32), (0.4, -0.36, 1.12), gold, rotation=(0, math.radians(side * 22), 0))
        ra.cylinder("tl_ring", 0.045, 0.015, (0.4 + side * 0.07, -0.36, 0.98), gold, rotation=(math.radians(90), 0, 0), verts=12)
    # Rolls of cloth by the wall.
    for k, colour in enumerate(((0.45, 0.06, 0.05), (0.08, 0.2, 0.4), (0.5, 0.42, 0.25))):
        ra.cylinder("tl_cloth", 0.06, 0.32, (-0.62 + k * 0.13, -0.5, 0.21), ra.plain(f"tl_cloth{k}", colour, 0.9), verts=14)


CITY = {
    # name: (canvas width, height, camera target height, builder); the assembly hall stands on 3 × 3 tiles.
    "assembly_hall": (256, 240, 1.0, build_assembly_hall),
    "multistorey_factory": (128, 224, 1.6, build_multistorey_factory),
    "shop": (128, 144, 0.7, build_shop),
    "high_bay": (128, 200, 1.4, build_high_bay),
    "city_sorter": (128, 128, 0.5, build_city_sorter),
    "freight_terminal": (144, 144, 0.7, build_freight_terminal),
    "company_hq": (128, 240, 1.8, build_company_hq),
    "design_office": (128, 152, 0.8, build_design_office),
    "laboratory": (128, 136, 0.6, build_laboratory),
    "service_workshop": (128, 128, 0.5, build_service_workshop),
    "tailor": (128, 144, 0.7, build_tailor),
}


def render_city(layout: dict, only=()):
    for name, (w, h, tz, build) in CITY.items():
        if only and name not in only:
            continue
        random.seed(zlib.crc32(name.encode()))
        layout[name] = render_sprite(name, w, h, Vector((0, 0, tz)), crafted(build), true_scale=True)
        icon = "item_storage_high_bay" if name == "high_bay" else f"furniture_{name}"
        ra.icon_from(Image.open(OUT / f"{name}.png").convert("RGBA"), ICONS / f"{icon}.png")


def city_icon_models():
    """Icons of what cities assemble and want."""
    def board():
        ra.box("pcb", (0.4, 0.3, 0.02), (0, 0, 0.02), ra.plain("ic_pcb", (0.02, 0.22, 0.08), 0.5))
        for k in range(3):
            ra.box("chip", (0.08, 0.08, 0.03), (-0.1 + k * 0.1, 0.05, 0.045), ra.plain("ic_pcb_chip", (0.03, 0.03, 0.035), 0.4))
        for k in range(6):
            ra.box("trace", (0.3, 0.008, 0.004), (0, -0.1 + k * 0.025, 0.032), ra.plain("ic_trace", (0.7, 0.55, 0.2), 0.3, 1.0))
        ra.cylinder("cap", 0.025, 0.06, (0.14, -0.08, 0.06), ra.plain("ic_cap", (0.1, 0.2, 0.5), 0.4), verts=12)

    def motor():
        steel = ra.rusty_metal("ic_motor", (0.3, 0.32, 0.35), rust=0.05)
        ra.cylinder("body", 0.13, 0.3, (0, 0, 0.14), steel, rotation=(0, math.radians(90), 0), verts=24)
        for k in range(6):
            ra.box("fin", (0.26, 0.01, 0.3), (0, 0, 0.14), steel, rotation=(k * math.pi / 6, 0, 0))
        ra.cylinder("shaft", 0.025, 0.12, (0.2, 0, 0.14), steel, rotation=(0, math.radians(90), 0), verts=10)
        ra.box("box", (0.1, 0.08, 0.06), (0, 0, 0.29), ra.plain("ic_motor_box", (0.05, 0.15, 0.4), 0.5))

    def bicycle():
        frame = ra.plain("ic_bike", (0.5, 0.05, 0.04), 0.4, 0.3)
        for x in (-0.17, 0.17):
            ra.cylinder("wheel", 0.12, 0.02, (x, 0, 0.13), ra.plain("ic_tyre", (0.02, 0.02, 0.02), 0.8), rotation=(math.radians(90), 0, 0), verts=24)
        ra.cylinder("tube", 0.012, 0.36, (0, 0, 0.18), frame, rotation=(0, math.radians(90), 0), verts=8)
        ra.cylinder("tube2", 0.012, 0.2, (-0.05, 0, 0.22), frame, rotation=(0, math.radians(45), 0), verts=8)
        ra.box("seat", (0.08, 0.03, 0.02), (-0.08, 0, 0.3), ra.plain("ic_seat", (0.05, 0.04, 0.03), 0.7))
        ra.box("bar", (0.02, 0.12, 0.02), (0.13, 0, 0.3), frame)

    def radio():
        ra.box("case", (0.36, 0.14, 0.22), (0, 0, 0.12), ra.wood("ic_radio_wood", (0.3, 0.16, 0.07)), bevel=0.02)
        ra.cylinder("speaker", 0.06, 0.01, (-0.08, -0.07, 0.12), ra.plain("ic_grill", (0.6, 0.55, 0.45), 0.8), rotation=(math.radians(90), 0, 0), verts=20)
        ra.box("dial", (0.12, 0.01, 0.05), (0.09, -0.07, 0.15), ra.emission("ic_dial", (1.0, 0.7, 0.3), 3.0))
        ra.cylinder("knob", 0.02, 0.02, (0.09, -0.075, 0.07), ra.plain("ic_knob", (0.05, 0.05, 0.05), 0.5), rotation=(math.radians(90), 0, 0), verts=12)
        ra.cylinder("aerial", 0.005, 0.25, (0.14, 0.03, 0.33), ra.plain("ic_aerial", (0.6, 0.6, 0.62), 0.2, 1.0), rotation=(0, 0.4, 0), verts=6)

    def washing_machine():
        ra.box("case", (0.3, 0.28, 0.36), (0, 0, 0.18), ra.plain("ic_wm", (0.75, 0.75, 0.74), 0.35), bevel=0.02)
        ra.cylinder("door", 0.09, 0.02, (0, -0.14, 0.16), ra.plain("ic_wm_door", (0.25, 0.3, 0.35), 0.1, 0.5), rotation=(math.radians(90), 0, 0), verts=24)
        ra.box("panel", (0.28, 0.01, 0.05), (0, -0.14, 0.32), ra.plain("ic_wm_panel", (0.2, 0.2, 0.22), 0.4))

    def car():
        paint = ra.plain("ic_car", (0.5, 0.04, 0.03), 0.25, 0.4, variation=0.05)
        ra.box("body", (0.44, 0.2, 0.1), (0, 0, 0.1), paint, bevel=0.04)
        ra.box("cabin", (0.22, 0.18, 0.08), (-0.02, 0, 0.19), ra.plain("ic_car_glass", (0.05, 0.08, 0.12), 0.05, 0.3), bevel=0.03)
        for x in (-0.14, 0.14):
            for y in (-0.1, 0.1):
                ra.cylinder("wheel", 0.05, 0.04, (x, y, 0.05), ra.plain("ic_car_tyre", (0.02, 0.02, 0.02), 0.8), rotation=(math.radians(90), 0, 0), verts=16)
        ra.box("light", (0.01, 0.04, 0.02), (0.22, -0.06, 0.11), ra.emission("ic_car_light", (1.0, 0.9, 0.6), 3.0))

    def blueprint():
        paper = ra.plain("ic_bp", (0.08, 0.2, 0.55), 0.6)
        ra.box("sheet", (0.4, 0.3, 0.005), (0, 0, 0.01), paper)
        lines = ra.plain("ic_bp_line", (0.8, 0.85, 0.9), 0.5)
        for k in range(4):
            ra.box("line", (0.3, 0.006, 0.002), (0, -0.09 + k * 0.06, 0.015), lines)
        ra.box("frame", (0.006, 0.18, 0.002), (0.05, 0, 0.016), lines)
        ra.cylinder("roll", 0.035, 0.32, (0, 0.15, 0.04), paper, rotation=(0, math.radians(90), 0), verts=14)

    return {
        "item_circuit_board": board, "item_electric_motor": motor, "item_bicycle": bicycle, "item_radio": radio,
        "item_washing_machine": washing_machine, "item_car": car, "item_blueprint": blueprint,
    }


# --- Forest ----------------------------------------------------------------------------------------

def spruce(height, width, color):
    """A spruce: narrow and dark, with many drooping tiers down to the ground."""
    ra.cylinder("trunk", 0.15, height * 0.3, (0, 0, height * 0.15), bark())
    leaves = foliage("spruce_needles", color, 0.3)
    tiers = 7
    for i in range(tiers):
        t = i / tiers
        r = width * (1 - t * 0.85) / 2
        z = height * (0.08 + t * 0.8)
        cone = ra.cylinder("tier", r, height * 0.24, (0, 0, z + height * 0.1), leaves, radius2=0.02, verts=14)
        ra.displace(cone, 0.08, 0.4, 2)
    return meshes()


def birch(height, width, color):
    """A birch: a slender white trunk with black marks and a light, airy crown."""
    white = ra.plain("birch_bark", (0.75, 0.73, 0.68), 0.6, variation=0.15, scale=20)
    black = ra.plain("birch_mark", (0.04, 0.04, 0.04), 0.7)
    ra.cylinder("trunk", 0.12, height * 0.7, (0, 0, height * 0.35), white)
    for k in range(6):
        ra.box("mark", (0.1, 0.02, 0.04), (0, -0.115, 0.4 + k * height * 0.1), black, rotation=(0, 0, random.uniform(-0.6, 0.6)))
    leaves = foliage("birch_leaves", color, 0.4)
    for _ in range(7):
        off = Vector((random.uniform(-0.5, 0.5), random.uniform(-0.5, 0.5), random.uniform(-0.2, 0.5))) * width * 0.4
        s = ra.sphere("crown", width * random.uniform(0.2, 0.27), Vector((0, 0, height * 0.72)) + off, leaves, scale=(1, 1, 1.3), segments=14)
        ra.displace(s, 0.2, 0.3, 2)
    return meshes()


def oak(height, width, color):
    """An oak: a thick, short trunk and a wide, heavy crown."""
    ra.cylinder("trunk", 0.32, height * 0.45, (0, 0, height * 0.22), bark(), radius2=0.24)
    for a in (0.6, 2.4, 4.2):
        ra.cylinder("bough", 0.1, 1.2, (math.cos(a) * 0.4, math.sin(a) * 0.4, height * 0.5), bark(),
                    rotation=(math.cos(a) * 0.7, math.sin(a) * 0.7, 0), verts=10)
    leaves = foliage("oak_leaves", color, 0.4)
    for _ in range(8):
        off = Vector((random.uniform(-0.6, 0.6), random.uniform(-0.6, 0.6), random.uniform(-0.2, 0.3))) * width * 0.42
        s = ra.sphere("crown", width * random.uniform(0.26, 0.32), Vector((0, 0, height * 0.68)) + off, leaves, scale=(1.1, 1.1, 0.8), segments=16)
        ra.displace(s, 0.3, 0.35, 2)
    return meshes()


def linden(height, width, color):
    """A linden in flower: a round, dense crown sprinkled with pale yellow blossom."""
    ra.cylinder("trunk", 0.2, height * 0.5, (0, 0, height * 0.25), bark())
    leaves = foliage("linden_leaves", color, 0.35)
    blossom = ra.plain("linden_blossom", (0.85, 0.8, 0.35), 0.5, variation=0.2)
    centre = Vector((0, 0, height * 0.66))
    s = ra.sphere("crown", width * 0.48, centre, leaves, scale=(1, 1, 1.05), segments=20)
    ra.displace(s, 0.3, 0.35, 2)
    for _ in range(40):
        a, b = random.uniform(0, math.tau), random.uniform(-0.2, 1.2)
        d = Vector((math.cos(a) * math.cos(b), math.sin(a) * math.cos(b), math.sin(b))) * width * 0.5
        ra.sphere("bloom", 0.07, centre + d, blossom, segments=6)
    return meshes()


def mushrooms(count, seed):
    """Mushrooms on the forest floor: brown and red caps among moss."""
    random.seed(seed)
    moss = foliage("moss", (0.05, 0.1, 0.03), 0.4)
    ra.sphere("moss", 0.5, (0, 0, -0.03), moss, scale=(1, 0.8, 0.12), segments=14)
    stem = ra.plain("mush_stem", (0.8, 0.76, 0.65), 0.6)
    caps = [ra.plain("mush_cap_brown", (0.32, 0.17, 0.06), 0.5, variation=0.25), ra.plain("mush_cap_red", (0.6, 0.06, 0.03), 0.4)]
    for k in range(count):
        a = k / count * math.tau + random.uniform(-0.3, 0.3)
        r = random.uniform(0.1, 0.32)
        h = random.uniform(0.12, 0.22)
        x, y = math.cos(a) * r, math.sin(a) * r * 0.8
        ra.cylinder("stem", 0.035, h, (x, y, h / 2), stem, verts=10)
        ra.sphere("cap", random.uniform(0.08, 0.12), (x, y, h), caps[1 if k == 0 and seed % 2 else 0], scale=(1, 1, 0.55),
                  segments=14, keep=lambda co: co.z >= -0.01)
    return meshes()


FOREST_NATURE = {
    # name: (canvas width, height, camera target height, builder)
    "spruce_0": (224, 320, 2.9, lambda: spruce(7.0, 2.4, (0.03, 0.08, 0.045))),
    "spruce_1": (224, 288, 2.6, lambda: spruce(6.2, 2.2, (0.035, 0.09, 0.05))),
    "birch_0": (224, 288, 2.6, lambda: birch(5.8, 2.4, (0.16, 0.24, 0.06))),
    "birch_1": (224, 272, 2.4, lambda: birch(5.2, 2.2, (0.18, 0.26, 0.07))),
    "oak_0": (288, 272, 2.2, lambda: oak(5.0, 3.6, (0.07, 0.12, 0.03))),
    "oak_1": (288, 256, 2.0, lambda: oak(4.6, 3.3, (0.08, 0.13, 0.035))),
    "linden_0": (256, 272, 2.3, lambda: linden(5.2, 3.0, (0.09, 0.16, 0.04))),
    "linden_1": (256, 256, 2.1, lambda: linden(4.8, 2.8, (0.1, 0.17, 0.045))),
    "mushrooms_0": (96, 80, 0.15, lambda: mushrooms(4, 1)),
    "mushrooms_1": (96, 80, 0.15, lambda: mushrooms(3, 2)),
}


def forest_mats():
    return {
        "timber": ra.wood("fo_timber", (0.28, 0.17, 0.08)),
        "dark_timber": ra.wood("fo_dark_timber", (0.14, 0.08, 0.04)),
        "planks": ra.wood("fo_planks", (0.4, 0.27, 0.13)),
        "roof": ra.plain("fo_roof", (0.18, 0.08, 0.05), 0.8, variation=0.2, scale=12, bump=0.4),
        "shingle": ra.plain("fo_shingle", (0.12, 0.1, 0.08), 0.85, variation=0.25, scale=16, bump=0.5),
        "brick": ra.plain("fo_brick", (0.36, 0.13, 0.07), 0.9, variation=0.35, scale=10, bump=0.5),
        "red": ra.plain("fo_red", (0.55, 0.05, 0.03), 0.45, variation=0.1),
        "white": ra.plain("fo_white", (0.78, 0.76, 0.7), 0.6),
        "iron": ra.rusty_metal("fo_iron", (0.12, 0.12, 0.13), rust=0.3),
        "earth": soil_mat(),
        "paper": ra.plain("fo_paper", (0.82, 0.8, 0.74), 0.7, variation=0.05),
        "honey": ra.plain("fo_honey", (0.75, 0.42, 0.04), 0.2, variation=0.1),
        "window": ra.emission("fo_window", (1.0, 0.75, 0.4), 1.6),
        "glass": ra.plain("fo_glass", (0.08, 0.12, 0.16), 0.1, 0.4),
        "tar": ra.plain("fo_tar", (0.015, 0.012, 0.01), 0.15, variation=0.1),
        "smoke": ra.plain("fo_smoke", (0.35, 0.34, 0.33), 0.9, variation=0.2),
        "ember": ra.emission("fo_ember", (1.0, 0.35, 0.06), 4.0),
    }


def log_pile(at, count, mat, r=0.08, length=0.6):
    x0, y0 = at
    for k in range(count):
        row = 0 if k < (count + 1) // 2 else 1
        i = k if row == 0 else k - (count + 1) // 2
        ra.cylinder("log", r, length, (x0 + (i - count / 4) * r * 2.1 + row * r, y0, r + row * r * 1.8), mat, rotation=(math.radians(90), 0, 0), verts=10)


def build_paper_mill():
    """A paper mill: a long brick hall with a tall chimney, a water tank, and rolls of paper waiting outside."""
    m = forest_mats()
    ra.box("pm_pad", (1.8, 1.5, 0.05), (0, 0, 0.025), ra.concrete_floor())
    ra.box("pm_hall", (1.5, 0.9, 0.9), (0, 0.15, 0.5), m["brick"], bevel=0.02)
    gable_roof("pm_roof", 1.5, 0.9, 0.95, 1.3, m["roof"], at=(0, 0.15))
    for x in (-0.45, 0.0, 0.45):
        ra.box("pm_window", (0.25, 0.02, 0.3), (x, -0.31, 0.55), m["window"])
    ra.cylinder("pm_chimney", 0.11, 1.6, (0.6, 0.4, 1.25), m["brick"], verts=14)
    ra.cylinder("pm_tank", 0.22, 0.6, (-0.7, 0.45, 0.35), m["iron"], verts=20)
    for k in range(3):
        ra.cylinder("pm_roll", 0.13, 0.35, (-0.45 + k * 0.3, -0.55, 0.13), m["paper"], rotation=(0, math.radians(90), 0), verts=20)


def build_carpentry():
    """A carpenter's shop: a timber shed open at the front, a bench with a chair being made, planks stacked at its side."""
    m = forest_mats()
    ra.box("cp_floor", (1.5, 1.2, 0.06), (0, 0, 0.03), m["planks"])
    for x in (-0.65, 0.65):
        for y in (-0.5, 0.5):
            ra.box("cp_post", (0.08, 0.08, 1.0), (x, y, 0.53), m["timber"])
    ra.box("cp_back", (1.38, 0.05, 0.95), (0, 0.5, 0.53), m["timber"])
    gable_roof("cp_roof", 1.4, 1.1, 1.03, 1.4, m["shingle"])
    ra.box("cp_bench", (0.8, 0.35, 0.05), (0, 0.2, 0.42), m["dark_timber"])
    for x in (-0.35, 0.35):
        ra.box("cp_leg", (0.05, 0.3, 0.38), (x, 0.2, 0.22), m["dark_timber"])
    # A chair on the floor in front.
    ra.box("cp_seat", (0.25, 0.25, 0.03), (0.3, -0.25, 0.25), m["planks"])
    ra.box("cp_chair_back", (0.25, 0.03, 0.3), (0.3, -0.14, 0.4), m["planks"])
    for dx in (-0.1, 0.1):
        for dy in (-0.1, 0.1):
            ra.box("cp_chair_leg", (0.03, 0.03, 0.24), (0.3 + dx, -0.25 + dy, 0.12), m["planks"])
    for k in range(4):
        ra.box("cp_stack", (0.2, 0.9, 0.04), (-0.85, 0, 0.05 + k * 0.05), m["planks"])


def build_charcoal_kiln():
    """A charcoal kiln: a mound of earth over stacked wood, smoking from its top, with logs and sacks of charcoal by it."""
    m = forest_mats()
    mound = ra.sphere("ck_mound", 0.7, (0, 0.1, 0.0), m["earth"], scale=(1, 1, 0.75), segments=24, keep=lambda co: co.z >= -0.01)
    ra.displace(mound, 0.05, 0.3, 1)
    ra.cylinder("ck_vent", 0.06, 0.06, (0, 0.1, 0.53), m["ember"], verts=10)
    for k in range(3):
        ra.sphere("ck_smoke", 0.12 + k * 0.05, (0.05 * k, 0.1, 0.65 + k * 0.22), m["smoke"], segments=10)
    log_pile((-0.6, -0.5), 5, bark(), r=0.07, length=0.5)
    for k in range(2):
        ra.sphere("ck_sack", 0.13, (0.45 + k * 0.25, -0.55, 0.12), ra.plain("ck_burlap", (0.3, 0.24, 0.14), 0.9, bump=0.4),
                  scale=(1, 0.8, 1), segments=12)


def build_tar_kiln():
    """A tar kiln: a squat brick oven with a fire under it, a pipe dripping into barrels of tar."""
    m = forest_mats()
    ra.box("tk_pad", (1.5, 1.3, 0.05), (0, 0, 0.025), ra.concrete_floor())
    ra.cylinder("tk_oven", 0.5, 0.8, (0, 0.15, 0.45), m["brick"], radius2=0.38, verts=24)
    ra.sphere("tk_dome", 0.38, (0, 0.15, 0.85), m["brick"], scale=(1, 1, 0.6), segments=18)
    ra.box("tk_firedoor", (0.25, 0.04, 0.18), (0, -0.33, 0.2), m["iron"])
    ra.box("tk_glow", (0.18, 0.03, 0.06), (0, -0.35, 0.18), m["ember"])
    ra.cylinder("tk_pipe", 0.04, 0.6, (0.45, -0.1, 0.4), m["iron"], rotation=(0, math.radians(70), 0), verts=10)
    for k in range(2):
        ra.cylinder("tk_barrel", 0.15, 0.38, (0.6 + k * 0.08, -0.45 + k * 0.33, 0.2), m["dark_timber"], verts=18)
        ra.cylinder("tk_tar", 0.13, 0.02, (0.6 + k * 0.08, -0.45 + k * 0.33, 0.39), m["tar"], verts=18)


def build_beehive():
    """A beehive: a stack of painted wooden boxes on a stand, a sloping lid, bees' landing board and a few bees about."""
    m = forest_mats()
    ra.box("bh_stand", (0.55, 0.5, 0.2), (0, 0, 0.1), m["dark_timber"])
    colours = [(0.75, 0.6, 0.15), (0.2, 0.4, 0.55), (0.75, 0.6, 0.15)]
    for k, c in enumerate(colours):
        ra.box("bh_box", (0.5, 0.45, 0.2), (0, 0, 0.3 + k * 0.21), ra.plain(f"bh_paint{k}", c, 0.6, variation=0.2), bevel=0.01)
    ra.box("bh_lid", (0.6, 0.55, 0.06), (0, 0, 0.96), m["roof"], rotation=(math.radians(6), 0, 0))
    ra.box("bh_board", (0.3, 0.1, 0.02), (0, -0.27, 0.22), m["planks"])
    bee = ra.plain("bh_bee", (0.6, 0.45, 0.02), 0.4)
    for k in range(5):
        ra.sphere("bh_bee", 0.02, (random.uniform(-0.3, 0.3), -0.35 - random.uniform(0, 0.2), 0.3 + random.uniform(0, 0.5)), bee, segments=6)


def build_fire_watchtower():
    """A fire watchtower: four tall timber legs braced across, a ladder, and a cabin with windows all round on top."""
    m = forest_mats()
    top = 2.6
    for x in (-0.3, 0.3):
        for y in (-0.3, 0.3):
            ra.box("wt_leg", (0.07, 0.07, top), (x * (1 + 0.15), y * (1 + 0.15), top / 2), m["timber"])
    for z in (0.7, 1.4, 2.1):
        for along in (0, 1):
            ra.box("wt_brace", (0.75 if along == 0 else 0.05, 0.05 if along == 0 else 0.75, 0.05), (0, 0, z), m["timber"])
            ra.box("wt_brace2", (0.75 if along == 0 else 0.05, 0.05 if along == 0 else 0.75, 0.05),
                   (0, 0.35 if along == 0 else 0, z) if along == 0 else (0.35, 0, z), m["timber"])
    ra.box("wt_floor", (0.85, 0.85, 0.06), (0, 0, top), m["planks"])
    ra.box("wt_cabin", (0.75, 0.75, 0.45), (0, 0, top + 0.25), m["planks"])
    for side in ((0, -0.38), (0.38, 0), (0, 0.38), (-0.38, 0)):
        ra.box("wt_window", (0.5 if side[1] else 0.02, 0.02 if side[1] else 0.5, 0.2), (side[0], side[1], top + 0.32), m["glass"])
    gable_roof("wt_roof", 0.75, 0.75, top + 0.48, top + 0.75, m["shingle"])
    for k in range(8):
        ra.box("wt_rung", (0.25, 0.03, 0.03), (0, -0.5, 0.2 + k * 0.3), m["timber"])
    ra.box("wt_flag", (0.15, 0.01, 0.1), (0.08, 0.0, top + 0.95), m["red"])
    ra.cylinder("wt_pole", 0.01, 0.35, (0, 0, top + 0.85), m["iron"], verts=6)


def build_fire_station():
    """A forest fire station: a red brick depot with a big garage door, a fire engine peeking out and a hose-drying tower."""
    m = forest_mats()
    ra.box("fs_pad", (1.7, 1.5, 0.05), (0, 0, 0.025), ra.concrete_floor())
    ra.box("fs_hall", (1.2, 1.0, 0.9), (-0.15, 0.15, 0.5), m["brick"], bevel=0.02)
    gable_roof("fs_roof", 1.2, 1.0, 0.95, 1.25, m["roof"], at=(-0.15, 0.15))
    ra.box("fs_door", (0.7, 0.02, 0.6), (-0.15, -0.36, 0.35), ra.corrugated("fs_roller", (0.55, 0.06, 0.04), 0.05))
    ra.box("fs_engine", (0.55, 0.3, 0.28), (-0.15, -0.55, 0.2), m["red"], bevel=0.03)
    ra.box("fs_cab_glass", (0.2, 0.31, 0.1), (0.05, -0.55, 0.32), m["glass"])
    for x in (-0.33, 0.03):
        ra.cylinder("fs_wheel", 0.07, 0.32, (x, -0.55, 0.07), ra.plain("fs_tyre", (0.02, 0.02, 0.02), 0.8), rotation=(math.radians(90), 0, 0), verts=14)
    ra.box("fs_tower", (0.35, 0.35, 1.7), (0.6, 0.35, 0.9), m["brick"], bevel=0.01)
    gable_roof("fs_tower_roof", 0.35, 0.35, 1.75, 1.95, m["roof"], at=(0.6, 0.35))
    ra.box("fs_sign", (0.5, 0.02, 0.12), (-0.15, -0.36, 0.8), m["white"])


FOREST = {
    # name: (canvas width, height, camera target height, builder); each stands on one tile.
    "paper_mill": (144, 176, 0.9, build_paper_mill),
    "carpentry": (128, 136, 0.6, build_carpentry),
    "charcoal_kiln": (128, 128, 0.4, build_charcoal_kiln),
    "tar_kiln": (128, 128, 0.5, build_tar_kiln),
    "beehive": (80, 96, 0.5, build_beehive),
    "fire_watchtower": (96, 224, 1.6, build_fire_watchtower),
    "fire_station": (144, 176, 0.9, build_fire_station),
}


def render_forest(layout: dict, only=()):
    for name, (w, h, tz, build) in FOREST_NATURE.items():
        if only and name not in only:
            continue
        random.seed(zlib.crc32(name.encode()))
        layout[name] = render_sprite(name, w, h, Vector((0, 0, tz)), build)
    for name, (w, h, tz, build) in FOREST.items():
        if only and name not in only:
            continue
        random.seed(zlib.crc32(name.encode()))
        layout[name] = render_sprite(name, w, h, Vector((0, 0, tz)), crafted(build), true_scale=True)
        ra.icon_from(Image.open(OUT / f"{name}.png").convert("RGBA"), ICONS / f"furniture_{name}.png")


def forest_icon_models():
    """Icons of what the forest gives and what is made of it."""
    def sapling_of(color, white=False):
        def build():
            ball = ra.sphere("ball", 0.13, (0, 0, 0.05), soil_mat(), scale=(1, 1, 0.75), segments=16)
            ra.displace(ball, 0.015, 0.2, 1)
            stem = ra.plain("ic_birch_stem", (0.8, 0.78, 0.72), 0.6) if white else bark()
            ra.cylinder("stem", 0.014, 0.3, (0, 0, 0.2), stem, verts=6)
            leaves = foliage("ic_sapling_leaves", color, 0.35)
            for k in range(4):
                a = k / 4 * math.tau
                ra.sphere("leaf", 0.07, (math.cos(a) * 0.06, math.sin(a) * 0.06, 0.3 + (k % 2) * 0.05), leaves, scale=(1, 0.6, 0.4), segments=10)
        return build

    def spruce_sapling():
        ball = ra.sphere("ball", 0.13, (0, 0, 0.05), soil_mat(), scale=(1, 1, 0.75), segments=16)
        ra.displace(ball, 0.015, 0.2, 1)
        needles = foliage("ic_spruce", (0.03, 0.09, 0.05), 0.3)
        for i in range(4):
            t = i / 4
            ra.cylinder("tier", 0.11 * (1 - t * 0.7), 0.12, (0, 0, 0.15 + t * 0.1), needles, radius2=0.01, verts=12)

    def logs(color):
        def build():
            bark_m = ra.plain("ic_oak_bark", (0.1, 0.07, 0.05), 0.9, variation=0.4, scale=30, bump=0.6)
            cut = ra.wood("ic_oak_cut", color)
            for x, z in ((-0.1, 0.07), (0.1, 0.07), (0.0, 0.2)):
                ra.cylinder("log", 0.09, 0.45, (x, 0, z), bark_m, rotation=(math.radians(90), 0, 0))
                for y in (-0.226, 0.226):
                    ra.cylinder("end", 0.085, 0.005, (x, y, z), cut, rotation=(math.radians(90), 0, 0))
        return build

    def jar_of(color, lid=(0.65, 0.5, 0.1)):
        def build():
            glass = ra.plain("ic_jar_glass", (0.7, 0.75, 0.78), 0.05, variation=0.05, grime=0.1)
            ra.cylinder("jar", 0.13, 0.28, (0, 0, 0.14), glass, verts=24)
            ra.cylinder("fill", 0.12, 0.24, (0, 0, 0.13), ra.plain("ic_jar_fill", color, 0.2, variation=0.1), verts=24)
            ra.cylinder("lid", 0.12, 0.05, (0, 0, 0.3), ra.plain("ic_jar_lid", lid, 0.4, 0.5), verts=24)
        return build

    def bottle_of(color):
        def build():
            glass = ra.plain("ic_bottle", color, 0.08, variation=0.05, grime=0.1)
            ra.cylinder("bottle", 0.08, 0.28, (0, 0, 0.14), glass, verts=20)
            ra.cylinder("shoulder", 0.08, 0.08, (0, 0, 0.32), glass, radius2=0.03, verts=20)
            ra.cylinder("neck", 0.03, 0.08, (0, 0, 0.4), glass, verts=12)
            ra.cylinder("cork", 0.032, 0.05, (0, 0, 0.46), ra.wood("ic_cork", (0.45, 0.32, 0.18)), verts=12)
        return build

    def bowl_of(color, bits):
        def build():
            ceramic = ra.plain("ic_bowl", (0.75, 0.72, 0.65), 0.3, variation=0.05)
            ra.sphere("bowl", 0.22, (0, 0, 0.2), ceramic, scale=(1, 1, 0.75), segments=28, keep=lambda co: co.z <= 0.01)
            ra.cylinder("soup", 0.2, 0.02, (0, 0, 0.19), ra.plain("ic_soup", color, 0.2, variation=0.1), verts=28)
            m = ra.plain("ic_bit", bits, 0.6)
            for _ in range(10):
                a, r = random.random() * math.tau, random.uniform(0, 0.14)
                ra.sphere("bit", 0.025, (math.cos(a) * r, math.sin(a) * r, 0.205), m, scale=(1.3, 1, 0.5), segments=8)
        return build

    def heap_of(color, size, count, flat=1.0):
        def build():
            m = ra.plain("ic_heap", color, 0.4, variation=0.3)
            for i in range(count):
                a, r = random.uniform(0, math.tau), random.uniform(0, 0.15)
                ra.sphere("bit", size * random.uniform(0.8, 1.2), (math.cos(a) * r, math.sin(a) * r, size + (i % 3) * size * 0.8), m,
                          scale=(1, 1, flat), segments=10)
        return build

    def mushroom_icon():
        stem = ra.plain("ic_mush_stem", (0.8, 0.76, 0.65), 0.6)
        cap = ra.plain("ic_mush_cap", (0.35, 0.18, 0.06), 0.5, variation=0.25)
        for x, h, r in ((-0.08, 0.2, 0.12), (0.1, 0.14, 0.09)):
            ra.cylinder("stem", 0.04, h, (x, 0, h / 2), stem, verts=12)
            ra.sphere("cap", r, (x, 0, h), cap, scale=(1, 1, 0.55), segments=16, keep=lambda co: co.z >= -0.01)

    def herbs():
        leaves = foliage("ic_herbs", (0.12, 0.3, 0.08), 0.3)
        string = ra.plain("ic_string", (0.6, 0.5, 0.3), 0.8)
        for k in range(5):
            ra.cylinder("stalk", 0.008, 0.35, (math.cos(k) * 0.03, 0, 0.18), leaves, rotation=(0, (k - 2) * 0.15, 0), verts=6)
            ra.sphere("leaf", 0.05, ((k - 2) * 0.05, 0, 0.33), leaves, scale=(1, 0.5, 1.4), segments=8)
        ra.cylinder("tie", 0.035, 0.03, (0, 0, 0.12), string, verts=10)

    def paper_stack():
        m = ra.plain("ic_paper", (0.85, 0.84, 0.8), 0.7, variation=0.04)
        for k in range(6):
            ra.box("sheet", (0.36, 0.28, 0.012), (random.uniform(-0.01, 0.01), 0, 0.01 + k * 0.014), m, rotation=(0, 0, random.uniform(-0.05, 0.05)))
        ra.box("band", (0.04, 0.29, 0.1), (0, 0, 0.045), ra.plain("ic_band", (0.6, 0.1, 0.06), 0.6))

    def cardboard():
        m = ra.plain("ic_cardboard", (0.5, 0.35, 0.18), 0.85, variation=0.1, bump=0.2)
        ra.box("box", (0.36, 0.28, 0.24), (0, 0, 0.12), m, bevel=0.01)
        ra.box("tape", (0.37, 0.05, 0.005), (0, 0, 0.243), ra.plain("ic_tape", (0.75, 0.62, 0.35), 0.3))

    def pulp():
        ra.cylinder("tub", 0.17, 0.2, (0, 0, 0.1), ra.rusty_metal("ic_tub", (0.4, 0.42, 0.45), rust=0.1), verts=24)
        mush = ra.sphere("pulp", 0.16, (0, 0, 0.19), ra.plain("ic_pulp", (0.7, 0.68, 0.6), 0.9, bump=0.5), scale=(1, 1, 0.4), segments=16)
        ra.displace(mush, 0.02, 0.1, 1)

    def chair():
        m = ra.wood("ic_chair", (0.35, 0.2, 0.09))
        ra.box("seat", (0.26, 0.26, 0.03), (0, 0, 0.22), m)
        ra.box("back", (0.26, 0.03, 0.26), (0, 0.12, 0.37), m)
        for dx in (-0.11, 0.11):
            for dy in (-0.11, 0.11):
                ra.box("leg", (0.03, 0.03, 0.22), (dx, dy, 0.11), m)

    def table():
        m = ra.wood("ic_table", (0.35, 0.2, 0.09))
        ra.box("top", (0.42, 0.3, 0.03), (0, 0, 0.24), m, bevel=0.005)
        for dx in (-0.18, 0.18):
            for dy in (-0.12, 0.12):
                ra.box("leg", (0.035, 0.035, 0.23), (dx, dy, 0.115), m)

    def wardrobe():
        m = ra.wood("ic_wardrobe", (0.3, 0.17, 0.08))
        ra.box("body", (0.3, 0.18, 0.46), (0, 0, 0.23), m, bevel=0.01)
        ra.box("split", (0.005, 0.185, 0.4), (0, 0, 0.24), ra.wood("ic_wardrobe_dark", (0.12, 0.07, 0.03)))
        for x in (-0.03, 0.03):
            ra.sphere("knob", 0.012, (x, -0.095, 0.25), ra.plain("ic_brass", (0.6, 0.42, 0.12), 0.35, 0.9), segments=8)

    def dresser():
        m = ra.wood("ic_dresser", (0.4, 0.25, 0.1))
        ra.box("body", (0.42, 0.24, 0.3), (0, 0, 0.17), m, bevel=0.01)
        for k in range(3):
            ra.box("drawer", (0.38, 0.01, 0.07), (0, -0.122, 0.07 + k * 0.09), ra.wood("ic_drawer", (0.3, 0.18, 0.07)))
            ra.sphere("knob", 0.012, (0, -0.13, 0.07 + k * 0.09), ra.plain("ic_brass2", (0.6, 0.42, 0.12), 0.35, 0.9), segments=8)
        for dx in (-0.18, 0.18):
            ra.box("foot", (0.04, 0.04, 0.03), (dx, 0, 0.015), m)

    def charcoal():
        m = ra.plain("ic_charcoal", (0.02, 0.018, 0.016), 0.5, variation=0.4, bump=0.9)
        for k in range(5):
            ra.box("chunk", (0.14, 0.07, 0.07), (random.uniform(-0.1, 0.1), random.uniform(-0.08, 0.08), 0.04 + (k % 2) * 0.06), m,
                   bevel=0.01, rotation=(0, 0, random.uniform(0, 3)))

    def wax():
        m = ra.plain("ic_wax", (0.8, 0.65, 0.25), 0.4, variation=0.1)
        ra.box("block", (0.3, 0.2, 0.12), (0, 0, 0.06), m, bevel=0.02)
        for k in range(4):
            ra.box("cell", (0.05, 0.05, 0.01), (-0.08 + k * 0.055, 0, 0.122), ra.plain("ic_wax_cell", (0.7, 0.5, 0.15), 0.4))

    def candles():
        m = ra.plain("ic_candle", (0.85, 0.78, 0.55), 0.4)
        for x, h in ((-0.07, 0.34), (0.07, 0.26)):
            ra.cylinder("candle", 0.04, h, (x, 0, h / 2), m, verts=14)
            ra.sphere("flame", 0.02, (x, 0, h + 0.03), ra.emission("ic_flame", (1.0, 0.65, 0.2), 6.0), scale=(1, 1, 1.8), segments=8)

    def gingerbread():
        m = ra.plain("ic_ginger", (0.36, 0.18, 0.06), 0.7, variation=0.15, bump=0.2)
        icing = ra.plain("ic_icing", (0.9, 0.88, 0.85), 0.4)
        ra.cylinder("cookie", 0.15, 0.04, (0, 0, 0.02), m, verts=24)
        ra.torus("icing", 0.12, 0.008, (0, 0, 0.042), icing)

    def pierogi():
        plate = ra.plain("ic_plate", (0.8, 0.78, 0.72), 0.3, variation=0.05)
        ra.cylinder("plate", 0.24, 0.02, (0, 0, 0.01), plate, verts=28)
        dough = ra.plain("ic_dough", (0.85, 0.78, 0.6), 0.6)
        for k in range(4):
            a = k / 4 * math.tau
            ra.sphere("pieróg", 0.08, (math.cos(a) * 0.1, math.sin(a) * 0.1, 0.04), dough, scale=(1.3, 0.7, 0.45), segments=12)
        ra.sphere("berries", 0.03, (0, 0, 0.05), ra.plain("ic_berry", (0.08, 0.05, 0.2), 0.3), segments=8)

    def tea():
        cup = ra.plain("ic_cup", (0.8, 0.78, 0.72), 0.3)
        ra.cylinder("cup", 0.12, 0.16, (0, 0, 0.08), cup, radius2=0.1, verts=24)
        ra.cylinder("tea", 0.11, 0.01, (0, 0, 0.155), ra.plain("ic_tea", (0.45, 0.3, 0.05), 0.1), verts=24)
        ra.torus("handle", 0.05, 0.012, (0.13, 0, 0.09), cup, rotation=(math.radians(90), 0, 0))

    def spray():
        can = ra.plain("ic_spray", (0.15, 0.45, 0.15), 0.4, 0.3)
        ra.cylinder("can", 0.08, 0.32, (0, 0, 0.16), can, verts=20)
        ra.cylinder("top", 0.06, 0.05, (0, 0, 0.34), ra.plain("ic_spray_top", (0.85, 0.85, 0.82), 0.4), verts=16)
        ra.box("label", (0.01, 0.12, 0.12), (-0.08, 0, 0.16), ra.plain("ic_spray_label", (0.8, 0.7, 0.1), 0.5))

    def barrel_of(top):
        def build():
            m = ra.wood("ic_barrel", (0.2, 0.11, 0.05))
            ra.cylinder("barrel", 0.15, 0.36, (0, 0, 0.18), m, verts=20)
            for z in (0.06, 0.3):
                ra.cylinder("hoop", 0.155, 0.02, (0, 0, z), ra.rusty_metal("ic_hoop", (0.15, 0.15, 0.16), rust=0.3), verts=20)
            ra.cylinder("top", 0.14, 0.01, (0, 0, 0.36), ra.plain("ic_barrel_top", top, 0.1), verts=20)
        return build

    def rosin():
        m = ra.plain("ic_rosin", (0.6, 0.3, 0.04), 0.15, variation=0.2)
        for k in range(3):
            s = ra.box("lump", (0.12, 0.1, 0.08), (-0.1 + k * 0.1, (k % 2) * 0.05, 0.05), m, bevel=0.02, rotation=(0, 0, k))
            ra.displace(s, 0.01, 0.2, 1)

    def resin():
        m = ra.plain("ic_resin", (0.7, 0.4, 0.05), 0.1, variation=0.2)
        ra.sphere("drop", 0.12, (0, 0, 0.12), m, scale=(1, 1, 1.2), segments=16)
        ra.cylinder("tip", 0.1, 0.12, (0, 0, 0.25), m, radius2=0.01, verts=16)

    return {
        "item_sapling_spruce": spruce_sapling,
        "item_sapling_birch": sapling_of((0.2, 0.32, 0.08), white=True),
        "item_sapling_oak": sapling_of((0.1, 0.2, 0.05)),
        "item_sapling_linden": sapling_of((0.14, 0.26, 0.06)),
        "item_oak_wood": logs((0.42, 0.28, 0.12)),
        "item_resin": resin, "item_pulp": pulp, "item_paper": paper_stack, "item_cardboard": cardboard,
        "item_chair": chair, "item_table": table, "item_wardrobe": wardrobe, "item_oak_dresser": dresser,
        "item_charcoal": charcoal, "item_mushrooms": mushroom_icon,
        "item_berries": heap_of((0.08, 0.05, 0.22), 0.035, 18),
        "item_herbs": herbs,
        "item_mushroom_soup": bowl_of((0.45, 0.32, 0.18), (0.3, 0.17, 0.07)),
        "item_berry_pierogi": pierogi,
        "item_herbal_tea": tea,
        "item_honey": jar_of((0.75, 0.42, 0.04)),
        "item_wax": wax, "item_gingerbread": gingerbread, "item_candles": candles,
        "item_tar": barrel_of((0.015, 0.012, 0.01)),
        "item_turpentine": bottle_of((0.6, 0.55, 0.3)),
        "item_rosin": rosin,
        "item_insecticide": spray,
    }


# --- Power ----------------------------------------------------------------------------------------

def build_generator():
    """A small steam generator: a riveted boiler lying on a brick firebox with a glowing door, a
    chimney, a flywheel turning the dynamo at its side and a copper terminal for the pole's wire."""
    brick = ra.plain("gen_brick", (0.3, 0.11, 0.06), 0.9, variation=0.35, scale=10, bump=0.5)
    iron = ra.rusty_metal("gen_iron", (0.1, 0.1, 0.11), rust=0.35)
    boiler = ra.rusty_metal("gen_boiler", (0.13, 0.2, 0.15), rust=0.3)
    brass = ra.plain("gen_brass", (0.6, 0.42, 0.12), 0.35, 0.9, variation=0.15)
    copper = ra.plain("gen_copper", (0.65, 0.28, 0.12), 0.35, 0.9, variation=0.15)
    ra.box("firebox", (1.3, 0.9, 0.45), (0, 0, 0.225), brick, bevel=0.03)
    ra.box("door", (0.3, 0.04, 0.24), (-0.3, -0.46, 0.22), iron, bevel=0.01)
    ra.box("glow", (0.22, 0.03, 0.06), (-0.3, -0.48, 0.2), ra.emission("gen_ember", (1.0, 0.35, 0.06), 4.5))
    ra.cylinder("boiler", 0.34, 1.2, (0, 0.02, 0.8), boiler, rotation=(0, math.radians(90), 0), verts=28)
    for x in (-0.5, 0.0, 0.5):
        ra.cylinder("band", 0.355, 0.05, (x, 0.02, 0.8), iron, rotation=(0, math.radians(90), 0), verts=28)
    ra.cylinder("chimney", 0.09, 0.8, (-0.4, 0.15, 1.45), iron, verts=12)
    ra.cylinder("chimney_cap", 0.13, 0.05, (-0.4, 0.15, 1.86), iron, verts=12)
    ra.cylinder("dome", 0.12, 0.14, (0.15, 0.02, 1.18), brass, verts=16)
    ra.cylinder("gauge", 0.06, 0.03, (0.35, -0.33, 0.95), brass, rotation=(math.radians(90), 0, 0), verts=16)
    # The dynamo at the east end, driven by a spoked flywheel.
    ra.cylinder("dynamo", 0.2, 0.32, (0.78, 0.0, 0.42), ra.rusty_metal("gen_dynamo", (0.25, 0.08, 0.05), rust=0.2),
                rotation=(0, math.radians(90), 0), verts=20)
    ra.cylinder("flywheel", 0.36, 0.06, (0.62, -0.32, 0.45), iron, rotation=(math.radians(90), 0, 0), verts=28)
    ra.cylinder("hub", 0.07, 0.1, (0.62, -0.32, 0.45), brass, rotation=(math.radians(90), 0, 0), verts=12)
    for k in range(4):
        ra.box("spoke", (0.62, 0.03, 0.04), (0.62, -0.34, 0.45), iron, rotation=(0, k * math.pi / 4, 0))
    ra.cylinder("terminal", 0.04, 0.22, (0.85, 0.2, 0.75), copper, verts=10)
    ra.sphere("insulator", 0.05, (0.85, 0.2, 0.88), ra.plain("gen_porcelain", (0.75, 0.72, 0.65), 0.3), segments=10)


POLE_TOP = 2.4


def build_pole():
    """A wooden power pole with a cross-arm and two porcelain insulators the wires hang from."""
    timber = ra.wood("pole_timber", (0.2, 0.12, 0.06))
    porcelain = ra.plain("pole_porcelain", (0.78, 0.75, 0.68), 0.25, variation=0.1)
    ra.cylinder("pole", 0.08, POLE_TOP, (0, 0, POLE_TOP / 2), timber, verts=10)
    ra.box("arm", (0.9, 0.09, 0.09), (0, 0, POLE_TOP - 0.18), timber, bevel=0.01)
    for x in (-0.36, 0.36):
        ra.cylinder("insulator", 0.045, 0.12, (x, 0, POLE_TOP - 0.07), porcelain, verts=10)
    for x, a in ((0.18, 40), (-0.18, -40)):
        ra.box("strut", (0.04, 0.04, 0.5), (x, 0, POLE_TOP - 0.38), timber, rotation=(0, math.radians(a), 0))
    ra.box("plate", (0.12, 0.02, 0.16), (0, -0.09, 1.2), ra.plain("pole_plate", (0.75, 0.6, 0.05), 0.5))


POWER = {
    # name: (canvas width, height, camera target height, builder, where the wires meet it); each stands on one tile.
    "generator": (128, 128, 0.7, build_generator, Vector((0.85, 0.2, 0.9))),
    "pole": (64, 128, POLE_TOP / 2, build_pole, Vector((0, 0, POLE_TOP - 0.05))),
    "water_wheel": (128, 144, 0.75, build_water_wheel, Vector((0.7, 0.05, 0.9))),
    "hydro_plant": (128, 160, 0.85, build_hydro_plant, Vector((0.4, 0.3, 1.45))),
}


def render_power(layout: dict, only=()):
    for name, (w, h, tz, build, wire) in POWER.items():
        if only and name not in only:
            continue
        random.seed(zlib.crc32(name.encode()))
        target = Vector((0, 0, tz))
        layout[name] = render_sprite(name, w, h, target, crafted(build))
        layout[name]["wireX"], layout[name]["wireY"] = anchor(w, h, target, wire)
        ra.icon_from(Image.open(OUT / f"{name}.png").convert("RGBA"), ICONS / f"item_power_{name}.png")


# --- Icons ------------------------------------------------------------------------------------------

def icon_models():
    def axe():
        handle = ra.wood("handle", (0.25, 0.15, 0.07))
        ra.cylinder("handle", 0.022, 0.5, (0, 0, 0.04), handle, rotation=(0, math.radians(90), math.radians(20)))
        head = ra.rusty_metal("head", (0.35, 0.35, 0.37), rust=0.2)
        ra.box("head", (0.07, 0.03, 0.16), (0.2, 0.07, 0.08), head, bevel=0.01, rotation=(0, 0, math.radians(20)))
        ra.box("edge", (0.03, 0.032, 0.2), (0.24, 0.085, 0.08), ra.plain("edge", (0.7, 0.7, 0.72), 0.2, 1.0, grime=0.1),
               rotation=(0, 0, math.radians(20)))

    def chainsaw():
        # Lying on its side: an orange motor housing, a black handle loop over it, and the long
        # guide bar with its chain pointing to the right.
        orange = ra.plain("saw_body", (0.75, 0.22, 0.02), 0.45, variation=0.15, grime=0.4)
        black = ra.plain("saw_black", (0.03, 0.03, 0.035), 0.55, grime=0.3)
        bar = ra.plain("saw_bar", (0.55, 0.56, 0.58), 0.3, 1.0, grime=0.3)
        turn = (0, 0, math.radians(15))
        ra.box("saw_body", (0.2, 0.13, 0.12), (-0.12, 0, 0.07), orange, bevel=0.025, rotation=turn)
        ra.box("saw_cover", (0.1, 0.135, 0.06), (-0.17, -0.013, 0.12), black, bevel=0.015, rotation=turn)
        ra.torus("saw_handle", 0.07, 0.014, (-0.1, 0.03, 0.17), black, rotation=(math.radians(90), 0, math.radians(15)))
        ra.box("saw_grip", (0.08, 0.035, 0.035), (-0.27, -0.04, 0.07), black, bevel=0.012, rotation=turn)
        ra.box("saw_bar", (0.36, 0.022, 0.065), (0.15, 0.072, 0.07), bar, bevel=0.025, rotation=turn)
        ra.box("saw_chain", (0.37, 0.026, 0.012), (0.15, 0.072, 0.105), black, bevel=0.004, rotation=turn)
        ra.box("saw_chain_low", (0.37, 0.026, 0.012), (0.15, 0.072, 0.035), black, bevel=0.004, rotation=turn)

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

    def pick(color, metallic_rust=0.2):
        def build():
            ra.cylinder("handle", 0.022, 0.5, (0, -0.02, 0.04), ra.wood("handle", (0.25, 0.15, 0.07)),
                        rotation=(0, math.radians(90), math.radians(-60)))
            head = ra.rusty_metal("head", color, rust=metallic_rust)
            ra.cylinder("pick", 0.028, 0.5, (0.13, 0.2, 0.06), head, radius2=0.008,
                        rotation=(0, math.radians(90), math.radians(30)))
        return build

    def crystals(color, roughness=0.15, count=6):
        def build():
            m = ra.plain("crystal", color, roughness, 0.0, variation=0.2, grime=0.1)
            base = rock("crystal_rock", (0.12, 0.11, 0.1))
            b = ra.sphere("crystal_rock", 0.15, (0, 0, 0.0), base, scale=(1.3, 1, 0.5), segments=12)
            ra.displace(b, 0.03, 0.15, 1)
            for i in range(count):
                a = i / count * math.tau
                tilt = (math.cos(a) * 0.4, math.sin(a) * 0.4, 0)
                ra.cylinder("crystal", 0.035, 0.22, (math.cos(a) * 0.06, math.sin(a) * 0.05, 0.12), m, radius2=0.005,
                            rotation=(tilt[1], -tilt[0], 0), verts=6)
            ra.cylinder("crystal", 0.045, 0.28, (0, 0, 0.16), m, radius2=0.006, verts=6)
        return build

    def gravel(color, specks):
        def build():
            mat = rock("gravel", color)
            m = ra.plain("speck", specks, 0.35, 0.6)
            for i in range(22):
                a = random.random() * math.tau
                r = random.uniform(0, 0.16)
                ra.sphere("gravel", random.uniform(0.035, 0.055), (math.cos(a) * r, math.sin(a) * r * 0.8, 0.03 + (0.16 - r) * 0.5),
                          mat if i % 3 else m, segments=6)
        return build

    def blocks(color, size=(0.14, 0.12, 0.1), roughness=0.85):
        def build():
            m = ra.plain("block", color, roughness, variation=0.2, bump=0.3)
            for x, y, z in ((-0.08, 0, 0.05), (0.08, 0, 0.05), (0, 0, 0.15)):
                ra.box("block", size, (x, y, z), m, bevel=0.008)
        return build

    def slabs():
        m = ra.plain("marble", (0.78, 0.77, 0.75), 0.25, variation=0.3, scale=3.0, grime=0.15)
        for k in range(3):
            ra.box("slab", (0.34, 0.22, 0.03), (0, 0, 0.02 + k * 0.035), m, bevel=0.004, rotation=(0, 0, k * 0.08))

    def bricks():
        m = ra.plain("brick", (0.4, 0.12, 0.06), 0.9, variation=0.35, scale=10, bump=0.4)
        for row in range(3):
            for k in range(2):
                ra.box("brick", (0.22, 0.1, 0.07), (0, -0.06 + k * 0.12, 0.04 + row * 0.075), m, bevel=0.005,
                       rotation=(0, 0, math.pi / 2 if row % 2 else 0))

    def dynamite():
        red = ra.plain("dyn_red", (0.5, 0.04, 0.03), 0.6)
        fuse = ra.plain("dyn_fuse", (0.6, 0.55, 0.45), 0.9)
        tape = ra.plain("dyn_tape", (0.05, 0.05, 0.05), 0.5)
        for i, (x, z) in enumerate(((-0.06, 0.05), (0.06, 0.05), (0.0, 0.15))):
            ra.cylinder("dyn", 0.055, 0.34, (x, 0, z), red, rotation=(math.radians(90), 0, math.radians(20)), verts=16)
        ra.cylinder("dyn_tape", 0.13, 0.04, (0, 0, 0.09), tape, rotation=(math.radians(90), 0, math.radians(20)), verts=16)
        ra.cylinder("dyn_fuse", 0.008, 0.18, (-0.08, 0.2, 0.2), fuse, rotation=(math.radians(50), 0, math.radians(20)), verts=6)
        ra.sphere("dyn_spark", 0.025, (-0.11, 0.27, 0.27), ra.emission("spark", (1.0, 0.7, 0.2), 8.0), segments=8)

    def mine_support():
        timber = ra.wood("support", (0.2, 0.12, 0.06))
        steel = ra.rusty_metal("support_steel", (0.2, 0.2, 0.22), rust=0.3)
        for x in (-0.12, 0.12):
            ra.box("post", (0.05, 0.05, 0.3), (x, 0, 0.15), timber)
        ra.box("cap", (0.34, 0.06, 0.06), (0, 0, 0.32), timber)
        for x in (-0.12, 0.12):
            ra.box("bracket", (0.07, 0.07, 0.03), (x, 0, 0.29), steel)

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

    def hoe():
        ra.cylinder("handle", 0.02, 0.55, (-0.04, 0, 0.04), ra.wood("handle", (0.25, 0.15, 0.07)),
                    rotation=(0, math.radians(90), math.radians(-35)))
        blade = ra.rusty_metal("blade", (0.3, 0.31, 0.33), rust=0.4)
        ra.box("blade", (0.05, 0.16, 0.12), (0.22, -0.17, 0.06), blade, bevel=0.01, rotation=(0, 0, math.radians(-35)))

    def wheat_sheaf():
        stalk = ra.plain("stalk", (0.45, 0.34, 0.1), 0.7)
        ear = ra.plain("ear", (0.6, 0.44, 0.13), 0.6, variation=0.25)
        for i in range(9):
            a = (i - 4) * 0.09
            ra.cylinder("stalk", 0.013, 0.42, (a * 0.4, 0, 0.0), stalk, rotation=(0, math.radians(90) + a, 0), verts=6)
            ra.sphere("ear", 0.034, (0.25, a * 0.3, 0.0), ear, scale=(2.6, 1, 1), segments=8)
        ra.cylinder("band", 0.03, 0.03, (-0.02, 0, 0), ra.plain("band", (0.3, 0.12, 0.05), 0.6), rotation=(0, math.radians(90), 0))

    def carrots():
        root = ra.plain("root", (0.65, 0.2, 0.02), 0.5)
        tops = foliage("tops", (0.08, 0.2, 0.05), 0.3)
        for i in range(3):
            y = (i - 1) * 0.08
            ra.cylinder("root", 0.035, 0.3, (0.0, y, 0.03), root, radius2=0.005, rotation=(0, math.radians(90), 0.1 * (i - 1)))
            ra.sphere("top", 0.05, (-0.18, y, 0.04), tops, scale=(1.6, 1, 0.6), segments=8)

    def cabbage_head():
        leaves = foliage("cabbage", (0.14, 0.28, 0.09), 0.25)
        head = ra.sphere("head", 0.15, (0, 0, 0.12), leaves, scale=(1, 1, 0.9), segments=20)
        ra.displace(head, 0.015, 0.06, 2)
        for k in range(5):
            a = k / 5 * math.tau
            ra.sphere("outer", 0.1, (math.cos(a) * 0.12, math.sin(a) * 0.12, 0.06), leaves, scale=(1.3, 1.3, 0.45), segments=10)

    def corn_cob():
        ra.sphere("cob", 0.06, (0, 0, 0.06), ra.plain("kernels", (0.7, 0.5, 0.06), 0.4, variation=0.2, bump=0.6),
                  scale=(3.2, 1, 1), segments=16)
        husk = foliage("husk", (0.25, 0.3, 0.1), 0.2)
        for side in (-1, 1):
            ra.box("husk", (0.3, 0.06, 0.01), (-0.12, side * 0.06, 0.07), husk, rotation=(0, 0, side * 0.25))

    def potatoes():
        skin = ra.plain("skin", (0.35, 0.24, 0.12), 0.8, variation=0.25, bump=0.4)
        for i, (x, y) in enumerate(((-0.08, 0), (0.08, 0.03), (0, -0.09), (0.02, 0.1))):
            p = ra.sphere("potato", 0.07, (x, y, 0.05), skin, scale=(1.3, 1, 0.85), segments=12)
            ra.displace(p, 0.01, 0.05, 1)

    def sunflower_head():
        ra.cylinder("petals", 0.2, 0.02, (0, 0, 0.03), ra.plain("petals", (0.9, 0.6, 0.03), 0.5), verts=20)
        for k in range(16):
            a = k / 16 * math.tau
            ra.sphere("petal", 0.05, (math.cos(a) * 0.2, math.sin(a) * 0.2, 0.03), ra.plain("petal", (0.95, 0.65, 0.04), 0.5),
                      scale=(2, 0.8, 0.2), segments=6).rotation_euler = (0, 0, a)
        ra.cylinder("disc", 0.13, 0.04, (0, 0, 0.05), ra.plain("disc", (0.08, 0.04, 0.015), 0.8, bump=0.8), verts=20)

    def coal():
        m = ra.plain("coal", (0.012, 0.012, 0.014), 0.3, variation=0.5, bump=0.8)
        for i in range(6):
            a = i / 6 * math.tau
            s = ra.sphere("lump", random.uniform(0.06, 0.1), (math.cos(a) * 0.12, math.sin(a) * 0.1, 0.06), m, segments=8)
            ra.displace(s, 0.035, 0.2, 1)

    def sapling():
        ball = ra.sphere("ball", 0.13, (0, 0, 0.05), soil_mat(), scale=(1, 1, 0.75), segments=16)
        ra.displace(ball, 0.015, 0.2, 1)
        ra.cylinder("stem", 0.012, 0.3, (0, 0, 0.2), bark(), verts=6)
        needles = foliage("needles", (0.08, 0.2, 0.07), 0.3)
        for i in range(3):
            t = i / 3
            cone = ra.cylinder("tier", 0.13 * (1 - t * 0.6), 0.14, (0, 0, 0.17 + t * 0.12), needles, radius2=0.01, verts=12)
            ra.displace(cone, 0.015, 0.4, 1)

    def planks():
        fresh = ra.wood("planks", (0.3, 0.19, 0.09))
        for k in range(4):
            ra.box("plank", (0.5, 0.12, 0.03), (0, (k % 2) * 0.02 - 0.06 + (k // 2) * 0.13, 0.016 + (k % 2) * 0.031), fresh,
                   rotation=(0, 0, math.radians(15)))

    def beams():
        fresh = ra.wood("beams", (0.24, 0.15, 0.07))
        for x, z in ((-0.07, 0.04), (0.07, 0.04), (0.0, 0.12)):
            ra.box("beam", (0.5, 0.12, 0.08), (0, x, z), fresh, bevel=0.006, rotation=(0, 0, math.radians(15)))

    def pellets():
        mat = ra.plain("pellet", (0.2, 0.12, 0.05), 0.85, variation=0.25, bump=0.5)
        for i in range(110):
            a, r = random.uniform(0, math.tau), random.uniform(0, 1) ** 0.7 * 0.15
            at = (math.cos(a) * r, math.sin(a) * r * 0.9, 0.012 + max(0.0, 0.12 - r * 0.55) * random.uniform(0.5, 1.0))
            ra.cylinder("pellet", 0.012, 0.05, at, mat, verts=8,
                        rotation=(random.uniform(0, 3), random.uniform(0, 3), random.uniform(0, 3)))

    def plywood():
        face = ra.wood("plywood", (0.34, 0.24, 0.12))
        edge = ra.plain("plywood_edge", (0.22, 0.14, 0.06), 0.8, variation=0.3, scale=30)
        for k in range(3):
            at = (0.02 * k - 0.02, 0.015 * k, 0.014 + k * 0.03)
            ra.box("ply_edge", (0.44, 0.34, 0.026), at, edge, rotation=(0, 0, math.radians(12 + k * 4)))
            ra.box("ply_face", (0.444, 0.344, 0.004), (at[0], at[1], at[2] + 0.014), face, rotation=(0, 0, math.radians(12 + k * 4)))

    def ingots(color, roughness=0.3):
        def build():
            m = ra.plain("ingot", color, roughness, 1.0, variation=0.12, grime=0.35)
            # A trapezoid bar, wider at the bottom, as cast in a mould.
            v = [(-0.12, -0.055, 0), (0.12, -0.055, 0), (0.12, 0.055, 0), (-0.12, 0.055, 0),
                 (-0.1, -0.038, 0.06), (0.1, -0.038, 0.06), (0.1, 0.038, 0.06), (-0.1, 0.038, 0.06)]
            f = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
            for i, (x, y, z, turn) in enumerate(((0, -0.065, 0, 0), (0, 0.065, 0, 0), (0, 0, 0.06, math.pi / 2))):
                bar = ra.mesh_from("ingot", [(vx, vy, vz) for vx, vy, vz in v], f, m)
                bar.location = (x, y, z)
                bar.rotation_euler = (0, 0, turn + random.uniform(-0.05, 0.05))
                bevel = bar.modifiers.new("bevel", "BEVEL")
                bevel.width = 0.006
                bevel.segments = 2
        return build

    def nails():
        steel = ra.rusty_metal("nail", (0.2, 0.2, 0.21), rust=0.15)
        for i in range(9):
            a = random.uniform(-0.6, 0.6) + (0.3 if i % 2 else -0.2)
            d = Vector((math.cos(a), math.sin(a), 0))
            at = Vector((random.uniform(-0.1, 0.1), random.uniform(-0.1, 0.1), 0.012 + 0.016 * (i // 3)))
            ra.cylinder("shank", 0.014, 0.3, at, steel, rotation=(0, math.radians(90), a), verts=8, radius2=0.004)
            ra.cylinder("head", 0.032, 0.012, at - d * 0.15, steel, rotation=(0, math.radians(90), a), verts=16)

    def sand():
        d = ra.sphere("pile", 0.22, (0, 0, -0.04), sand_mat(), scale=(1, 1, 0.75), segments=24)
        ra.displace(d, 0.02, 0.2, 2)

    def sack(color, tie=(0.35, 0.25, 0.12)):
        def build():
            cloth = ra.plain("sack", color, 0.95, variation=0.12, scale=12, bump=0.5)
            body = ra.sphere("sack", 0.17, (0, 0, 0.15), cloth, scale=(1, 0.9, 1.15), segments=20)
            ra.displace(body, 0.015, 0.2, 1)
            ra.cylinder("neck", 0.06, 0.12, (0, 0, 0.36), cloth, radius2=0.09, verts=16)
            ra.cylinder("tie", 0.065, 0.025, (0, 0, 0.33), ra.plain("tie", tie, 0.8), verts=16)
            # Flour spilt in front of the sack.
            pile = ra.sphere("spill", 0.09, (0.1, -0.16, -0.02), ra.plain("powder", color, 0.95, variation=0.05), scale=(1.3, 1, 0.4), segments=12)
            ra.displace(pile, 0.01, 0.1, 1)
        return build

    def oil_bottle():
        glass = ra.plain("bottle", (0.75, 0.5, 0.06), 0.08, variation=0.05, grime=0.1)
        ra.cylinder("bottle", 0.09, 0.3, (0, 0, 0.15), glass, verts=24)
        ra.cylinder("shoulder", 0.09, 0.08, (0, 0, 0.34), glass, radius2=0.03, verts=24)
        ra.cylinder("neck", 0.03, 0.08, (0, 0, 0.42), glass, verts=16)
        ra.cylinder("cork", 0.032, 0.05, (0, 0, 0.48), ra.wood("cork", (0.45, 0.32, 0.18)), verts=16)
        ra.cylinder("label", 0.092, 0.1, (0, 0, 0.14), ra.plain("label", (0.85, 0.8, 0.6), 0.8), verts=24)
        ra.sphere("seed", 0.03, (0.0, -0.09, 0.14), ra.plain("petal", (0.95, 0.65, 0.04), 0.5), scale=(1, 0.3, 1), segments=8)

    def jar():
        # Pale kraut packed to the top, seen through glass: rims of glass at the bottom and neck.
        glass = ra.plain("jar", (0.55, 0.6, 0.5), 0.05, variation=0.05, grime=0.05)
        ra.cylinder("kraut", 0.13, 0.28, (0, 0, 0.15), ra.plain("kraut", (0.72, 0.7, 0.42), 0.5, variation=0.25, bump=0.8), verts=24)
        for z in (0.015, 0.29):
            ra.cylinder("rim", 0.135, 0.03, (0, 0, z), glass, verts=24)
        ra.cylinder("lid", 0.12, 0.05, (0, 0, 0.32), ra.rusty_metal("lid", (0.4, 0.08, 0.05), rust=0.1), verts=24)

    def loaf(color, scale=(1.6, 1, 0.75), scored=True):
        def build():
            crust = ra.plain("crust", color, 0.6, variation=0.2, bump=0.5)
            l = ra.sphere("loaf", 0.15, (0, 0, 0.09), crust, scale=scale, segments=24)
            ra.displace(l, 0.01, 0.1, 1)
            if scored:
                cut = ra.plain("cut", tuple(min(1, c * 1.8) for c in color), 0.8)
                for k in range(3):
                    ra.box("score", (0.03, 0.18, 0.02), (-0.1 + k * 0.1, 0, 0.2), cut, rotation=(0.2, 0, math.radians(30)))
        return build

    def corn_bread():
        crumb = ra.plain("cornbread", (0.75, 0.5, 0.1), 0.7, variation=0.2, bump=0.6)
        top = ra.plain("cornbread_top", (0.55, 0.3, 0.05), 0.6, variation=0.2, bump=0.4)
        for i, (x, y) in enumerate(((-0.1, 0), (0.1, 0.02))):
            ra.box("piece", (0.18, 0.18, 0.1), (x, y, 0.05), crumb, bevel=0.01, rotation=(0, 0, 0.15 * i))
            ra.box("top", (0.18, 0.18, 0.02), (x, y, 0.105), top, bevel=0.01, rotation=(0, 0, 0.15 * i))

    def carrot_cake():
        sponge = ra.plain("sponge", (0.45, 0.22, 0.07), 0.7, variation=0.2, bump=0.5)
        icing = ra.plain("icing", (0.9, 0.86, 0.78), 0.4, variation=0.05)
        ra.cylinder("cake", 0.2, 0.14, (0, 0, 0.07), sponge, verts=32)
        ra.cylinder("icing", 0.205, 0.04, (0, 0, 0.155), icing, verts=32)
        ra.cylinder("plate", 0.25, 0.015, (0, 0, -0.005), ra.plain("plate", (0.85, 0.85, 0.85), 0.3), verts=32)
        carrot = ra.plain("carrot", (0.75, 0.25, 0.02), 0.5)
        for k in range(6):
            a = k / 6 * math.tau
            ra.cylinder("deco", 0.015, 0.06, (math.cos(a) * 0.13, math.sin(a) * 0.13, 0.19), carrot, radius2=0.003,
                        rotation=(0, math.radians(90), a), verts=8)

    def fries():
        paper = ra.plain("cone", (0.75, 0.12, 0.08), 0.6)
        ra.cylinder("cone", 0.16, 0.24, (0, 0, 0.12), paper, radius2=0.06, rotation=(0, 0, 0), verts=24).rotation_euler = (math.pi, 0, 0)
        potato = ra.plain("fry", (0.85, 0.62, 0.18), 0.5, variation=0.15)
        for k in range(16):
            a = random.random() * math.tau
            r = random.uniform(0, 0.1)
            ra.box("fry", (0.03, 0.03, 0.22), (math.cos(a) * r, math.sin(a) * r, 0.26), potato, bevel=0.005,
                   rotation=(random.uniform(-0.3, 0.3), random.uniform(-0.3, 0.3), random.random()))

    def bowl(color, chunks):
        def build():
            ceramic = ra.plain("bowl", (0.75, 0.72, 0.65), 0.3, variation=0.05)
            ra.sphere("bowl", 0.22, (0, 0, 0.2), ceramic, scale=(1, 1, 0.75), segments=32, keep=lambda co: co.z <= 0.01)
            ra.cylinder("soup", 0.2, 0.02, (0, 0, 0.19), ra.plain("soup", color, 0.2, variation=0.1), verts=32)
            for c, n in chunks:
                m = ra.plain("chunk", c, 0.6)
                for _ in range(n):
                    a = random.random() * math.tau
                    r = random.uniform(0, 0.14)
                    ra.box("chunk", (0.04, 0.04, 0.03), (math.cos(a) * r, math.sin(a) * r, 0.205), m, bevel=0.008,
                           rotation=(0, 0, random.random() * 3))
        return build

    def one_fish(color, belly, length=0.46):
        def build():
            fish("fish", length, color, belly, (0, 0, 0), math.radians(20))
        return build

    def pair(color, belly, mat=None):
        def build():
            skin = mat() if mat else None
            for k, (x, y) in enumerate(((-0.02, 0.06), (0.03, -0.07))):
                fish(f"fish{k}", 0.4, color, belly, (x, y, k * 0.05), math.radians(15 + k * 10), skin)
        return build

    def fishing_rod():
        dark = ra.plain("rod", (0.05, 0.05, 0.06), 0.3)
        ra.cylinder("rod", 0.012, 0.6, (0, 0, 0.05), dark, radius2=0.004, rotation=(0, math.radians(90), math.radians(30)))
        ra.cylinder("grip", 0.02, 0.14, (-0.2, -0.12, 0.05), ra.wood("cork", (0.45, 0.32, 0.18)), rotation=(0, math.radians(90), math.radians(30)))
        ra.cylinder("reel", 0.045, 0.03, (-0.12, -0.1, 0.03), ra.plain("reel", (0.6, 0.6, 0.62), 0.3, 1.0), rotation=(math.radians(90), 0, math.radians(30)))
        ra.sphere("float", 0.03, (0.18, -0.12, 0.03), ra.plain("float", (0.85, 0.1, 0.05), 0.4), segments=10)
        ra.box("line", (0.003, 0.003, 0.3), (0.2, 0.0, 0.08), ra.plain("line", (0.8, 0.8, 0.8), 0.3), rotation=(math.radians(80), 0, math.radians(30)))

    def mussels():
        shell = ra.plain("mussel", (0.03, 0.04, 0.08), 0.25, variation=0.3)
        inside = ra.plain("mussel_meat", (0.85, 0.5, 0.2), 0.5)
        for i in range(5):
            a = i / 5 * math.tau
            x, y = math.cos(a) * 0.12, math.sin(a) * 0.1
            s = ra.sphere("mussel", 0.09, (x, y, 0.04), shell, scale=(1, 0.5, 0.35), segments=14)
            s.rotation_euler = (0, 0, a)
            if i % 2:
                ra.sphere("meat", 0.05, (x, y, 0.07), inside, scale=(1, 0.5, 0.3), segments=10)

    def seaweed():
        weed = ra.plain("weed", (0.08, 0.16, 0.05), 0.35, variation=0.3, bump=0.6)
        for i in range(7):
            a = random.random() * math.tau
            s = ra.sphere("weed", random.uniform(0.08, 0.13), (math.cos(a) * 0.1, math.sin(a) * 0.1, 0.04 + i * 0.012), weed,
                          scale=(1.6, 0.7, 0.25), segments=10)
            s.rotation_euler = (0, 0, a)
            ra.displace(s, 0.02, 0.15, 1)

    def amber():
        m = ra.plain("amber", (0.85, 0.4, 0.03), 0.05, variation=0.25, grime=0.0)
        for i, (x, y, r) in enumerate(((0, 0, 0.12), (0.13, -0.06, 0.07), (-0.12, -0.08, 0.06))):
            s = ra.sphere("amber", r, (x, y, r * 0.6), m, scale=(1.2, 1, 0.8), segments=12)
            ra.displace(s, r * 0.15, 0.3, 1)

    def slab_of(color):
        def build():
            board = ra.wood("board", (0.3, 0.2, 0.1))
            ra.box("board", (0.46, 0.3, 0.04), (0, 0, 0.02), board, bevel=0.01)
            flesh = ra.plain("slab", color, 0.35, variation=0.2, scale=20, bump=0.4)
            for k in range(3):
                ra.box("slice", (0.12, 0.22, 0.03), (-0.13 + k * 0.13, 0, 0.055 + k * 0.004), flesh, bevel=0.012, rotation=(0, -0.25, 0))
        return build

    def jar_of(color):
        def build():
            glass = ra.plain("jar", (0.55, 0.6, 0.5), 0.05, variation=0.05, grime=0.05)
            ra.cylinder("brine", 0.13, 0.28, (0, 0, 0.15), ra.plain("brine", (0.7, 0.68, 0.5), 0.2, variation=0.1), verts=24)
            for k in range(3):
                ra.sphere("roll", 0.05, (math.cos(k * 2.1) * 0.08, -0.1, 0.08 + k * 0.08), ra.plain("herring", color, 0.3, 0.3),
                          scale=(1.4, 0.6, 0.8), segments=10)
            for z in (0.015, 0.29):
                ra.cylinder("rim", 0.135, 0.03, (0, 0, z), glass, verts=24)
            ra.cylinder("lid", 0.12, 0.05, (0, 0, 0.32), ra.rusty_metal("lid", (0.1, 0.2, 0.4), rust=0.1), verts=24)
        return build

    def oil_bottle_of(color):
        def build():
            glass = ra.plain("bottle", color, 0.08, variation=0.05, grime=0.1)
            ra.cylinder("bottle", 0.09, 0.3, (0, 0, 0.15), glass, verts=24)
            ra.cylinder("shoulder", 0.09, 0.08, (0, 0, 0.34), glass, radius2=0.03, verts=24)
            ra.cylinder("neck", 0.03, 0.08, (0, 0, 0.42), glass, verts=16)
            ra.cylinder("cork", 0.032, 0.05, (0, 0, 0.48), ra.wood("cork", (0.45, 0.32, 0.18)), verts=16)
            ra.cylinder("label", 0.092, 0.1, (0, 0, 0.14), ra.plain("label", (0.2, 0.35, 0.55), 0.8), verts=24)
        return build

    def canned_fish():
        tin = ra.plain("tin", (0.7, 0.72, 0.74), 0.25, 1.0, variation=0.1)
        label = ra.plain("label", (0.1, 0.25, 0.55), 0.5)
        ra.box("can", (0.36, 0.22, 0.08), (0, 0, 0.04), tin, bevel=0.03)
        ra.box("label", (0.37, 0.2, 0.05), (0, 0, 0.035), label, bevel=0.02)
        ra.torus("pull", 0.04, 0.008, (0.1, 0, 0.085), tin)
        fish("can_fish", 0.16, (0.55, 0.6, 0.65), (0.8, 0.8, 0.78), (-0.05, 0, 0.08), 0.0)

    def fried_carp():
        plate = ra.plain("plate", (0.8, 0.78, 0.72), 0.3, variation=0.05)
        ra.cylinder("plate", 0.25, 0.025, (0, 0, 0.012), plate, verts=32)
        fish("carp", 0.36, (0.45, 0.25, 0.06), (0.6, 0.38, 0.1), (0, 0, 0.025), math.radians(15),
             ra.plain("crust", (0.45, 0.25, 0.06), 0.6, variation=0.25, bump=0.6))
        ra.sphere("lemon", 0.04, (0.15, -0.12, 0.04), ra.plain("lemon", (0.85, 0.75, 0.05), 0.4), scale=(1, 1, 0.5), segments=10)

    def drum(color, band=(0.6, 0.6, 0.6)):
        def build():
            paint = ra.rusty_metal("drum", color, rust=0.25)
            ra.cylinder("drum", 0.15, 0.4, (0, 0, 0.2), paint, verts=28)
            for z in (0.13, 0.27):
                ra.cylinder("drum_rib", 0.155, 0.02, (0, 0, z), paint, verts=28)
            ra.cylinder("drum_band", 0.152, 0.07, (0, 0, 0.2), ra.plain("drum_band", band, 0.5), verts=28)
            ra.cylinder("drum_bung", 0.025, 0.02, (0.07, 0, 0.405), ra.plain("bung", (0.3, 0.3, 0.3), 0.4, 0.8), verts=10)
        return build

    def cylinder_of(color):
        def build():
            paint = ra.plain("gas_cyl", color, 0.4, 0.3, variation=0.1, grime=0.4)
            ra.cylinder("gas_body", 0.1, 0.42, (0, 0, 0.21), paint, verts=24)
            ra.sphere("gas_top", 0.1, (0, 0, 0.42), paint, scale=(1, 1, 0.6), segments=16)
            ra.cylinder("gas_valve", 0.03, 0.08, (0, 0, 0.5), ra.plain("brass", (0.6, 0.42, 0.12), 0.35, 0.9), verts=10)
            ra.torus("gas_guard", 0.06, 0.012, (0, 0, 0.55), ra.plain("guard", (0.1, 0.1, 0.1), 0.5, 0.6))
        return build

    def jerrycan(color):
        def build():
            paint = ra.plain("can", color, 0.4, 0.4, variation=0.12, grime=0.5)
            ra.box("can_body", (0.3, 0.13, 0.38), (0, 0, 0.19), paint, bevel=0.03)
            ra.box("can_x", (0.24, 0.135, 0.02), (0, 0, 0.19), paint, rotation=(0, math.radians(50), 0))
            ra.box("can_x2", (0.24, 0.135, 0.02), (0, 0, 0.19), paint, rotation=(0, math.radians(-50), 0))
            for x in (-0.06, 0.02, 0.1):
                ra.box("can_handle", (0.04, 0.05, 0.06), (x, 0, 0.41), paint, bevel=0.01)
            ra.cylinder("can_spout", 0.03, 0.06, (-0.11, 0, 0.42), ra.plain("cap", (0.1, 0.1, 0.1), 0.5), verts=12)
        return build

    def asphalt():
        mat = ra.plain("asphalt", (0.02, 0.02, 0.022), 0.85, variation=0.25, scale=30, bump=0.8)
        for k in range(3):
            b = ra.box("asphalt", (0.2, 0.16, 0.07), (-0.1 + k * 0.1, (k % 2) * 0.08 - 0.04, 0.035 + (k == 1) * 0.06), mat, bevel=0.02,
                       rotation=(0, 0, random.uniform(-0.4, 0.4)))
            ra.displace(b, 0.01, 0.2, 1)

    def plastic():
        tray = ra.plain("plastic_bag", (0.65, 0.7, 0.75), 0.25, variation=0.05)
        ra.sphere("bag", 0.17, (0, 0, 0.12), tray, scale=(1, 0.8, 0.75), segments=20)
        for i in range(40):
            a, r = random.uniform(0, math.tau), random.uniform(0, 1) ** 0.7 * 0.13
            ra.sphere("granule", 0.018, (r * math.cos(a), r * math.sin(a) * 0.8, 0.23 + random.uniform(0, 0.03)),
                      ra.plain(f"granule{i % 3}", [(0.85, 0.85, 0.82), (0.15, 0.35, 0.7), (0.75, 0.15, 0.1)][i % 3], 0.3), segments=8)

    def rubber():
        black = ra.plain("rubber", (0.025, 0.025, 0.027), 0.7, variation=0.1, bump=0.2)
        for k, (x, z) in enumerate(((-0.09, 0.07), (0.09, 0.07), (0, 0.2))):
            ra.box("bale", (0.17, 0.2, 0.12), (x, 0, z), black, bevel=0.03)

    def gasket():
        black = ra.plain("gasket", (0.03, 0.03, 0.032), 0.6, variation=0.1)
        copper = ra.plain("gasket_ring", (0.65, 0.28, 0.12), 0.3, 0.9)
        ra.torus("gasket", 0.14, 0.035, (-0.05, 0, 0.035), black)
        ra.torus("gasket_ring", 0.1, 0.02, (0.12, 0.05, 0.06), copper, rotation=(math.radians(20), 0, 0))

    def road_tile():
        mat = ra.plain("road", (0.03, 0.03, 0.032), 0.85, variation=0.25, scale=30, bump=0.6)
        ra.box("road", (0.5, 0.5, 0.04), (0, 0, 0.02), mat, bevel=0.01)
        ra.box("road_line", (0.06, 0.2, 0.005), (0, 0, 0.042), ra.plain("road_line", (0.8, 0.75, 0.6), 0.6))

    return {
        "item_tool_fishing_rod": fishing_rod,
        "item_crude_oil": drum((0.02, 0.02, 0.022), (0.55, 0.4, 0.05)),
        "item_natural_gas": cylinder_of((0.6, 0.45, 0.04)),
        "item_gasoline": jerrycan((0.55, 0.06, 0.03)),
        "item_diesel": jerrycan((0.1, 0.3, 0.1)),
        "item_kerosene": oil_bottle_of((0.2, 0.35, 0.55)),
        "item_asphalt": asphalt,
        "item_plastic": plastic,
        "item_synthetic_rubber": rubber,
        "item_fertilizer": sack((0.25, 0.45, 0.2)),
        "item_gasket": gasket,
        "item_logistics_pipe": lambda: pipe_straight(True, 0.22, 1.8),
        "item_logistics_pump": lambda: (pipe_straight(False, 0.4, 2.0), build_pump()),
        "item_logistics_road": road_tile,

        "item_herring": pair((0.35, 0.42, 0.5), (0.8, 0.82, 0.82)),
        "item_cod": one_fish((0.35, 0.3, 0.18), (0.8, 0.78, 0.7)),
        "item_carp": one_fish((0.4, 0.3, 0.08), (0.75, 0.6, 0.25)),
        "item_pike": one_fish((0.15, 0.25, 0.08), (0.7, 0.7, 0.5), 0.52),
        "item_salmon": one_fish((0.3, 0.33, 0.38), (0.85, 0.5, 0.4)),
        "item_mussels": mussels,
        "item_seaweed": seaweed,
        "item_amber": amber,
        "item_smoked_fish": pair((0.45, 0.25, 0.06), (0.6, 0.38, 0.1), lambda: ra.plain("smoked", (0.45, 0.25, 0.06), 0.35, 0.2)),
        "item_smoked_salmon": slab_of((0.85, 0.35, 0.18)),
        "item_salted_herring": jar_of((0.55, 0.6, 0.62)),
        "item_canned_fish": canned_fish,
        "item_fish_meal": sack((0.55, 0.45, 0.3)),
        "item_fish_oil": oil_bottle_of((0.6, 0.45, 0.08)),
        "item_fried_carp": fried_carp,
        "item_fish_soup": bowl((0.75, 0.6, 0.35), [((0.9, 0.88, 0.8), 8), ((0.75, 0.25, 0.02), 4), ((0.8, 0.7, 0.4), 4)]),
        "item_flour": sack((0.85, 0.83, 0.78)),
        "item_corn_flour": sack((0.85, 0.65, 0.2)),
        "item_sunflower_oil": oil_bottle,
        "item_sauerkraut": jar,
        "item_bread": loaf((0.42, 0.22, 0.07)),
        "item_corn_bread": corn_bread,
        "item_carrot_cake": carrot_cake,
        "item_fries": fries,
        "item_vegetable_soup": bowl((0.6, 0.35, 0.08), [((0.75, 0.25, 0.02), 6), ((0.8, 0.7, 0.4), 6), ((0.2, 0.4, 0.1), 4)]),
        "item_bigos": bowl((0.3, 0.18, 0.06), [((0.65, 0.6, 0.3), 12), ((0.35, 0.12, 0.08), 6)]),
        "item_tool_axe": axe, "item_tool_shovel": shovel, "item_tool_pickaxe": pickaxe, "item_tool_hoe": hoe,
        "item_tool_chainsaw": chainsaw,
        "item_wheat": wheat_sheaf, "item_carrot": carrots, "item_cabbage": cabbage_head, "item_corn": corn_cob,
        "item_potato": potatoes, "item_sunflower": sunflower_head,
        "item_wood": wood, "item_stone": stones((0.2, 0.19, 0.18)), "item_sand": sand, "item_coal": coal,
        "item_sapling": sapling,
        "item_planks": planks, "item_beams": beams, "item_wood_pellets": pellets, "item_plywood": plywood,
        "item_iron_ore": stones((0.18, 0.09, 0.05), (0.4, 0.4, 0.42)),
        "item_copper_ore": stones((0.14, 0.13, 0.12), (0.75, 0.35, 0.12)),
        "item_tin_ore": stones((0.08, 0.06, 0.05), (0.62, 0.62, 0.58)),
        "item_silver_ore": stones((0.11, 0.11, 0.12), (0.85, 0.86, 0.9)),
        "item_gold_ore": stones((0.1, 0.09, 0.08), (1.0, 0.82, 0.18)),
        "item_iron_ingot": ingots((0.12, 0.12, 0.13), 0.6),
        "item_copper_ingot": ingots((0.45, 0.16, 0.06), 0.4),
        "item_tin_ingot": ingots((0.28, 0.29, 0.27), 0.5),
        "item_silver_ingot": ingots((0.5, 0.52, 0.56), 0.3),
        "item_gold_ingot": ingots((0.6, 0.36, 0.06), 0.3),
        "item_nails": nails,
        "item_tool_bronze_pickaxe": pick((0.55, 0.32, 0.1), 0.15),
        "item_tool_steel_pickaxe": pick((0.5, 0.52, 0.56), 0.05),
        "item_sulfur": crystals((0.85, 0.72, 0.08), 0.4),
        "item_salt": crystals((0.85, 0.78, 0.78), 0.35),
        "item_quartz": crystals((0.75, 0.78, 0.82), 0.05),
        "item_marble": blocks((0.78, 0.77, 0.75), (0.14, 0.12, 0.1), 0.3),
        "item_crushed_iron_ore": gravel((0.18, 0.09, 0.05), (0.4, 0.4, 0.42)),
        "item_crushed_copper_ore": gravel((0.14, 0.13, 0.12), (0.75, 0.35, 0.12)),
        "item_crushed_tin_ore": gravel((0.08, 0.06, 0.05), (0.62, 0.62, 0.58)),
        "item_bronze_ingot": ingots((0.5, 0.28, 0.08), 0.35),
        "item_steel_ingot": ingots((0.32, 0.34, 0.37), 0.25),
        "item_stone_blocks": blocks((0.34, 0.32, 0.3)),
        "item_marble_slabs": slabs,
        "item_bricks": bricks,
        "item_dynamite": dynamite,
        "item_mine_support": mine_support,
        "item_logistics_belt": lambda: belt_frame(0.26, True, 1.6),
        "item_logistics_inserter": lambda: inserter(0.4, arm=True),
        "item_logistics_fast_belt": lambda: belt_frame(0.26, True, 1.6, tier="fast"),
        "item_logistics_express_belt": lambda: belt_frame(0.26, True, 1.6, tier="express"),
        "item_logistics_fast_inserter": lambda: inserter(0.4, arm=True, tier="fast"),
        "item_logistics_express_inserter": lambda: inserter(0.4, arm=True, tier="express"),
        "item_logistics_splitter": lambda: (belt_frame(0.4, True, 1.6), belt_frame(0.4, False, 1.6), splitter(0.6)),
        "item_storage_wooden_chest": lambda: wooden_chest(0.38),
        "item_storage_iron_chest": lambda: iron_chest(0.36),
        "item_storage_wood_pile": lambda: wood_pile(0.3),
        "item_storage_heap": lambda: heap(0.28),
        "item_storage_grain_silo": lambda: grain_silo(0.17),
    }


def render_icons(only=()):
    ICONS.mkdir(parents=True, exist_ok=True)
    for name, build in {**icon_models(), **desert_icon_models(), **glacier_icon_models(), **city_icon_models(), **forest_icon_models()}.items():
        if only and name not in only:
            continue
        random.seed(zlib.crc32(name.encode()))
        ra.icon_scene()
        build()
        ra.render(TMP / f"{name}.png")
        ra.icon_from(Image.open(TMP / f"{name}.png").convert("RGBA"), ICONS / f"{name}.png")
        print("icon", name)


if __name__ == "__main__":
    args = sys.argv[1:] or ["floors", "nature", "station", "rail", "trains", "farming", "forestry", "mine", "crafting", "processing", "forestry_industry", "power", "mountain", "coast", "oil", "desert", "glacier", "city", "forest", "office", "logistics", "icons"]
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
    if "trains" in args:
        render_trains(layout)
    if "farming" in args:
        render_farming(layout)
    if "forestry" in args:
        render_forestry(layout)
    if "station" in args:
        render_station(layout)
    if "mine" in args:
        render_mine(layout)
    if "crafting" in args or any(a in CRAFTING for a in args):
        # Names of crafting sprites render just those.
        render_crafting(layout, [a for a in args if a in CRAFTING])
    if "processing" in args:
        render_processing(layout)
    if "forestry_industry" in args or any(a in FORESTRY_INDUSTRY for a in args):
        # Names of forestry industry sprites render just those.
        render_forestry_industry(layout, [a for a in args if a in FORESTRY_INDUSTRY])
    if "office" in args:
        render_office(layout)
    if "power" in args or any(a in POWER for a in args):
        # Names of power sprites render just those.
        render_power(layout, [a for a in args if a in POWER])
    if "mountain" in args or any(a in MOUNTAIN or a == "cable_station" for a in args):
        # Names of mountain industry sprites render just those.
        render_mountain(layout, [a for a in args if a in MOUNTAIN or a == "cable_station"])
    if "coast" in args or any(a in COAST or a.startswith("flotsam_") or a == "water" for a in args):
        # Names of coast sprites render just those.
        render_coast(layout, [a for a in args if a in COAST or a.startswith("flotsam_") or a == "water"])
    if "oil" in args or any(a in OIL or a in OIL_POWER or a in PIPES or a == "road" for a in args):
        # Names of oil sprites render just those.
        render_oil(layout, [a for a in args if a in OIL or a in OIL_POWER or a in PIPES or a == "road"])
    if "desert" in args or any(a in DESERT or a in DESERT_POWER or a in PALMS for a in args):
        # Names of desert sprites render just those.
        render_desert(layout, [a for a in args if a in DESERT or a in DESERT_POWER or a in PALMS])
    glacier = {**GLACIER_NATURE, **GLACIER, **GLACIER_POWER, "crevasse": 0, "bridge": 0}
    if "glacier" in args or any(a in glacier for a in args):
        # Names of glacier sprites render just those.
        render_glacier(layout, [a for a in args if a in glacier])
    if "city" in args or any(a in CITY for a in args):
        # Names of city sprites render just those.
        render_city(layout, [a for a in args if a in CITY])
    forest = {**FOREST_NATURE, **FOREST}
    if "forest" in args or any(a in forest for a in args):
        # Names of forest sprites render just those.
        render_forest(layout, [a for a in args if a in forest])
    if "logistics" in args or any(a in LOGISTICS for a in args):
        # Names of logistics sprites render just those.
        render_logistics(layout, [a for a in args if a in LOGISTICS])
    # "item_<id>" arguments render just those icons.
    if "icons" in args or any(a.startswith("item_") for a in args):
        render_icons([a for a in args if a.startswith("item_")])
    layout_file.write_text(json.dumps(layout, indent=1))
