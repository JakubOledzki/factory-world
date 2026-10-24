#!/usr/bin/env python3
"""Renders the art of plots (the land a player owns) with Blender into client/art/plot/, and the
icons of tools and raw materials into client/art/icons/.

Same studio as tools/render_art.py (it reuses its helpers), same 45° view from above, but at a
smaller scale: a tile of a plot is 2 × 2 m on screen, 64 × 45 px, at 32 px per metre.

    .venv-art/bin/python tools/render_plot_art.py [floors] [nature] [station] [rail] [farming] [forestry] [mine] [crafting] [processing] [logistics] [icons | item_<id>...]

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


CRAFTING = {
    # Objects a player puts on a plot, built like the garage's furniture; the furnace a bit larger
    # so it reads at the plot's scale. name: (canvas width, height, camera target height, builder).
    "workbench": (144, 128, 0.6, crafted(lambda: ra.build_workbench(None, Vector((0, 0, 0))))),
    "furnace": (96, 112, 0.6, crafted(lambda: ra.build_furnace(None, Vector((0, 0, 0)), 1.4))),
    "anvil": (96, 96, 0.5, crafted(lambda: ra.build_anvil(None, Vector((0, 0, 0)), 1.7))),
}


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


def render_crafting(layout: dict, only=()):
    for name, (w, h, tz, build) in CRAFTING.items():
        if only and name not in only:
            continue
        random.seed(zlib.crc32(name.encode()))
        layout[name] = render_sprite(name, w, h, Vector((0, 0, tz)), build)


# --- Logistics --------------------------------------------------------------------------------------

def belt_frame(s=1.0, along_x=True, length=2.0):
    """A conveyor belt the length of a tile, so belts on neighbouring tiles join up: a dark rubber
    band between two yellow side rails on short legs. The game draws the moving stripes and items."""
    paint = ra.plain("belt_paint", (0.5, 0.33, 0.03), 0.5, 0.4, variation=0.2, grime=0.8)
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


def belt_curve(sides):
    """A belt turning a corner between two sides of its tile: the band and rails bent round the
    tile's corner between those sides, like belt_frame laid in a quarter circle."""
    paint = ra.plain("belt_paint", (0.5, 0.33, 0.03), 0.5, 0.4, variation=0.2, grime=0.8)
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


def inserter(s=1.0, arm=False):
    """The base of an inserter: a steel foot and a yellow turret; the game draws the arm swinging
    from the tile behind it to the tile in front. With `arm` (for its icon) the arm is modelled too."""
    paint = ra.plain("inserter_paint", (0.55, 0.36, 0.03), 0.45, 0.4, variation=0.2, grime=0.7)
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

    return {
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
        "item_logistics_belt": lambda: belt_frame(0.26, True, 1.6),
        "item_logistics_inserter": lambda: inserter(0.4, arm=True),
        "item_logistics_splitter": lambda: (belt_frame(0.4, True, 1.6), belt_frame(0.4, False, 1.6), splitter(0.6)),
        "item_storage_wooden_chest": lambda: wooden_chest(0.38),
        "item_storage_iron_chest": lambda: iron_chest(0.36),
        "item_storage_wood_pile": lambda: wood_pile(0.3),
        "item_storage_heap": lambda: heap(0.28),
        "item_storage_grain_silo": lambda: grain_silo(0.17),
    }


def render_icons(only=()):
    ICONS.mkdir(parents=True, exist_ok=True)
    for name, build in icon_models().items():
        if only and name not in only:
            continue
        random.seed(zlib.crc32(name.encode()))
        ra.icon_scene()
        build()
        ra.render(TMP / f"{name}.png")
        ra.icon_from(Image.open(TMP / f"{name}.png").convert("RGBA"), ICONS / f"{name}.png")
        print("icon", name)


if __name__ == "__main__":
    args = sys.argv[1:] or ["floors", "nature", "station", "rail", "farming", "forestry", "mine", "crafting", "processing", "logistics", "icons"]
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
    if "logistics" in args or any(a in LOGISTICS for a in args):
        # Names of logistics sprites render just those.
        render_logistics(layout, [a for a in args if a in LOGISTICS])
    # "item_<id>" arguments render just those icons.
    if "icons" in args or any(a.startswith("item_") for a in args):
        render_icons([a for a in args if a.startswith("item_")])
    layout_file.write_text(json.dumps(layout, indent=1))
