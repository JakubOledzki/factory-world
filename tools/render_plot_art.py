#!/usr/bin/env python3
"""Renders the art of plots (the land a player owns) with Blender into client/art/plot/, and the
icons of tools and raw materials into client/art/icons/.

Same studio as tools/render_art.py (it reuses its helpers), same 45° view from above, but at a
smaller scale: a tile of a plot is 2 × 2 m on screen, 64 × 45 px, at 32 px per metre.

    .venv-art/bin/python tools/render_plot_art.py [floors] [nature] [station] [rail] [farming] [forestry] [mine] [icons | item_<id>...]

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

    def sand():
        d = ra.sphere("pile", 0.22, (0, 0, -0.04), sand_mat(), scale=(1, 1, 0.75), segments=24)
        ra.displace(d, 0.02, 0.2, 2)

    return {
        "item_tool_axe": axe, "item_tool_shovel": shovel, "item_tool_pickaxe": pickaxe, "item_tool_hoe": hoe,
        "item_wheat": wheat_sheaf, "item_carrot": carrots, "item_cabbage": cabbage_head, "item_corn": corn_cob,
        "item_potato": potatoes, "item_sunflower": sunflower_head,
        "item_wood": wood, "item_stone": stones((0.2, 0.19, 0.18)), "item_sand": sand, "item_coal": coal,
        "item_sapling": sapling,
        "item_iron_ore": stones((0.18, 0.09, 0.05), (0.4, 0.4, 0.42)),
        "item_copper_ore": stones((0.14, 0.13, 0.12), (0.75, 0.35, 0.12)),
        "item_bronze_ore": stones((0.13, 0.11, 0.09), (0.45, 0.3, 0.14)),
        "item_silver_ore": stones((0.11, 0.11, 0.12), (0.85, 0.86, 0.9)),
        "item_gold_ore": stones((0.1, 0.09, 0.08), (1.0, 0.82, 0.18)),
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
    args = sys.argv[1:] or ["floors", "nature", "station", "rail", "farming", "forestry", "mine", "icons"]
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
    # "item_<id>" arguments render just those icons.
    if "icons" in args or any(a.startswith("item_") for a in args):
        render_icons([a for a in args if a.startswith("item_")])
    layout_file.write_text(json.dumps(layout, indent=1))
