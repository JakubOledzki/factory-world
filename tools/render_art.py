#!/usr/bin/env python3
"""Renders the game's art with Blender (Cycles) into client/art/.

Every model is built from code here, like a tiny procedural 3D studio, so the whole look
can be tweaked and re-rendered at once. Sprites are seen from above at 45°, in the style of
pre-rendered 3D games.

Needs the Blender Python module and Pillow:
    uv venv -p 3.13 .venv-art && VIRTUAL_ENV=.venv-art uv pip install bpy==5.2.2 pillow
    .venv-art/bin/python tools/render_art.py [garage] [character] [items]
"""
import json
import math
import random
import sys
from pathlib import Path

import bpy  # noqa: I001  (bpy must come first: it makes bmesh importable)
import bmesh
from mathutils import Vector
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "client" / "art"
TMP = Path("/tmp/fw-render")

# The game screen is 1280×720; the garage is drawn at 96 px per metre.
SCREEN_W, SCREEN_H = 1280, 720
PPM = 96
PITCH = math.radians(45)

random.seed(7)


# --- Scene helpers ------------------------------------------------------------------------

def reset() -> bpy.types.Scene:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 96
    scene.cycles.use_denoising = True
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    world = bpy.data.worlds.new("world")
    scene.world = world
    world.use_nodes = True
    return scene


def set_world(color, strength=1.0) -> None:
    bg = bpy.context.scene.world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (*color, 1)
    bg.inputs["Strength"].default_value = strength


def camera(scene, target: Vector, width_m: float, res: tuple[int, int], pitch=PITCH) -> bpy.types.Object:
    """Orthographic camera looking north (+Y) and down at `pitch` from the horizon."""
    data = bpy.data.cameras.new("camera")
    data.type = "ORTHO"
    data.ortho_scale = width_m
    data.clip_end = 200
    cam = bpy.data.objects.new("camera", data)
    scene.collection.objects.link(cam)
    direction = Vector((0, math.cos(pitch), -math.sin(pitch)))
    cam.location = target - direction * 40
    cam.rotation_euler = (math.pi / 2 - pitch, 0, 0)
    scene.camera = cam
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.resolution_percentage = 100
    return cam


def light(kind, location, energy, color=(1, 1, 1), size=0.2, rotation=(0, 0, 0), spot=None):
    data = bpy.data.lights.new(kind, kind)
    data.energy = energy
    data.color = color
    if kind == "AREA":
        data.size = size
    elif kind == "SUN":
        data.angle = size
    else:
        data.shadow_soft_size = size
    if spot:
        data.spot_size = spot
        data.spot_blend = 0.6
    obj = bpy.data.objects.new(kind, data)
    obj.location = location
    obj.rotation_euler = rotation
    bpy.context.scene.collection.objects.link(obj)
    return obj


def render(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.context.scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def link(obj, collection=None):
    (collection or bpy.context.scene.collection).objects.link(obj)
    return obj


def collection(name: str) -> bpy.types.Collection:
    c = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(c)
    return c


# --- Meshes -------------------------------------------------------------------------------

def mesh_from(name, verts, faces, mat=None, coll=None):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    obj = bpy.data.objects.new(name, me)
    if mat:
        obj.data.materials.append(mat)
    return link(obj, coll)


def box(name, size, location, mat=None, coll=None, bevel=0.0, rotation=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    obj.location = location
    obj.rotation_euler = rotation
    if mat:
        obj.data.materials.append(mat)
    if bevel > 0:
        mod = obj.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 3
        mod.limit_method = "NONE"
    return link(obj, coll)


def cylinder(name, radius, depth, location, mat=None, coll=None, rotation=(0, 0, 0), verts=32, bevel=0.0, radius2=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=verts, radius1=radius,
                          radius2=radius if radius2 is None else radius2, depth=depth)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    obj = bpy.data.objects.new(name, me)
    obj.location = location
    obj.rotation_euler = rotation
    if mat:
        obj.data.materials.append(mat)
    if bevel > 0:
        mod = obj.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = "ANGLE"
    return link(obj, coll)


def sphere(name, radius, location, mat=None, coll=None, scale=(1, 1, 1), segments=32, keep=None):
    """UV sphere; `keep(co)` can drop vertices to cut it, e.g. into a hair cap."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=segments // 2, radius=radius)
    if keep:
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not keep(v.co)], context="VERTS")
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    obj = bpy.data.objects.new(name, me)
    obj.location = location
    obj.scale = scale
    if mat:
        obj.data.materials.append(mat)
    if keep:
        solid = obj.modifiers.new("solid", "SOLIDIFY")
        solid.thickness = 0.02
    return link(obj, coll)


def torus(name, major, minor, location, mat=None, coll=None, rotation=(0, 0, 0)):
    bm = bmesh.new()
    seg, ring = 40, 16
    verts = []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        for j in range(ring):
            b = 2 * math.pi * j / ring
            r = major + minor * math.cos(b)
            verts.append(bm.verts.new((r * math.cos(a), r * math.sin(a), minor * math.sin(b))))
    for i in range(seg):
        for j in range(ring):
            a = verts[i * ring + j]
            b = verts[((i + 1) % seg) * ring + j]
            c = verts[((i + 1) % seg) * ring + (j + 1) % ring]
            d = verts[i * ring + (j + 1) % ring]
            bm.faces.new((a, b, c, d))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    obj = bpy.data.objects.new(name, me)
    obj.location = location
    obj.rotation_euler = rotation
    if mat:
        obj.data.materials.append(mat)
    return link(obj, coll)


def displace(obj, strength=0.05, scale=0.3, subdiv=2):
    sub = obj.modifiers.new("sub", "SUBSURF")
    sub.levels = sub.render_levels = subdiv
    tex = bpy.data.textures.new(obj.name + "_n", "CLOUDS")
    tex.noise_scale = scale
    mod = obj.modifiers.new("disp", "DISPLACE")
    mod.texture = tex
    mod.strength = strength
    return obj


# --- Materials ----------------------------------------------------------------------------

def _input(node, name, kind=None):
    for s in node.inputs:
        if s.name == name and (kind is None or s.type == kind):
            return s
    raise KeyError(name)


def _output(node, name, kind=None):
    for s in node.outputs:
        if s.name == name and (kind is None or s.type == kind):
            return s
    raise KeyError(name)


class Mat:
    """Small builder for procedural Principled materials with grime and wear."""

    def __init__(self, name):
        self.m = bpy.data.materials.new(name)
        self.m.use_nodes = True
        self.nt = self.m.node_tree
        self.bsdf = self.nt.nodes["Principled BSDF"]
        self.coord = self.nt.nodes.new("ShaderNodeTexCoord")

    def node(self, kind, **values):
        n = self.nt.nodes.new(kind)
        for k, v in values.items():
            if hasattr(n, k):
                setattr(n, k, v)
            else:
                n.inputs[k].default_value = v
        return n

    def link(self, a, b):
        self.nt.links.new(a, b)

    def noise(self, scale, detail=6.0, coord="Object", roughness=0.6):
        n = self.node("ShaderNodeTexNoise", Scale=scale, Detail=detail, Roughness=roughness)
        self.link(self.coord.outputs[coord], n.inputs["Vector"])
        return n

    def ramp(self, value_socket, stops):
        r = self.node("ShaderNodeValToRGB")
        els = r.color_ramp.elements
        while len(els) > len(stops):
            els.remove(els[-1])
        while len(els) < len(stops):
            els.new(0.5)
        for el, (pos, col) in zip(els, stops):
            el.position = pos
            el.color = (*col, 1) if len(col) == 3 else col
        self.link(value_socket, r.inputs["Fac"])
        return r

    def mix(self, fac, a, b, blend="MIX"):
        m = self.node("ShaderNodeMix", data_type="RGBA", blend_type=blend)
        if isinstance(fac, float):
            _input(m, "Factor", "VALUE").default_value = fac
        else:
            self.link(fac, _input(m, "Factor", "VALUE"))
        for name, v in (("A", a), ("B", b)):
            sock = _input(m, name, "RGBA")
            if isinstance(v, tuple):
                sock.default_value = (*v, 1)
            else:
                self.link(v, sock)
        return _output(m, "Result", "RGBA")

    def done(self, color, roughness=0.6, metallic=0.0, bump=None, bump_strength=0.2):
        if isinstance(color, tuple):
            self.bsdf.inputs["Base Color"].default_value = (*color, 1)
        else:
            self.link(color, self.bsdf.inputs["Base Color"])
        if isinstance(roughness, float):
            self.bsdf.inputs["Roughness"].default_value = roughness
        else:
            self.link(roughness, self.bsdf.inputs["Roughness"])
        self.bsdf.inputs["Metallic"].default_value = metallic
        if bump is not None:
            b = self.node("ShaderNodeBump", Strength=bump_strength, Distance=0.02)
            self.link(bump, b.inputs["Height"])
            self.link(b.outputs["Normal"], self.bsdf.inputs["Normal"])
        return self.m

    def grime(self, color_socket, amount=0.7, distance=0.25):
        """Darkens creases and corners with ambient occlusion."""
        ao = self.node("ShaderNodeAmbientOcclusion", samples=8)
        ao.inputs["Distance"].default_value = distance
        dark = self.ramp(ao.outputs["AO"], [(0.0, (0.02, 0.018, 0.015)), (1.0, (1, 1, 1))])
        return self.mix(amount, color_socket, dark.outputs["Color"], "MULTIPLY")


def plain(name, color, roughness=0.6, metallic=0.0, variation=0.15, scale=6.0, grime=0.6, bump=0.15):
    m = Mat(name)
    n = m.noise(scale)
    lo = tuple(c * (1 - variation) for c in color)
    hi = tuple(min(1.0, c * (1 + variation)) for c in color)
    col = m.ramp(n.outputs["Fac"], [(0.3, lo), (0.7, hi)]).outputs["Color"]
    col = m.grime(col, grime)
    return m.done(col, roughness, metallic, n.outputs["Fac"], bump)


def rusty_metal(name, color, rust=0.35, scale=3.0):
    m = Mat(name)
    n = m.noise(scale, detail=10)
    fine = m.noise(40.0)
    base = m.ramp(fine.outputs["Fac"], [(0.3, tuple(c * 0.8 for c in color)), (0.7, color)]).outputs["Color"]
    mask = m.ramp(n.outputs["Fac"], [(1.0 - rust - 0.05, (0, 0, 0)), (1.0 - rust + 0.05, (1, 1, 1))]).outputs["Color"]
    rust_col = m.ramp(fine.outputs["Fac"], [(0.3, (0.09, 0.04, 0.02)), (0.7, (0.2, 0.09, 0.04))]).outputs["Color"]
    col = m.grime(m.mix(mask, base, rust_col), 0.8)
    rough = m.ramp(n.outputs["Fac"], [(0.4, (0.35, 0.35, 0.35)), (0.7, (0.8, 0.8, 0.8))]).outputs["Color"]
    m.link(rough, m.bsdf.inputs["Roughness"])
    m.bsdf.inputs["Metallic"].default_value = 0.7
    b = m.node("ShaderNodeBump", Strength=0.3, Distance=0.01)
    m.link(fine.outputs["Fac"], b.inputs["Height"])
    m.link(b.outputs["Normal"], m.bsdf.inputs["Normal"])
    m.link(col, m.bsdf.inputs["Base Color"])
    return m.m


def concrete_floor():
    m = Mat("floor")
    big = m.noise(0.8, detail=4)
    fine = m.noise(30.0, detail=8)
    col = m.ramp(fine.outputs["Fac"], [(0.35, (0.085, 0.085, 0.09)), (0.65, (0.16, 0.155, 0.15))]).outputs["Color"]
    # Oil stains: large dark glossy blotches.
    stain = m.ramp(big.outputs["Fac"], [(0.58, (0, 0, 0)), (0.66, (1, 1, 1))]).outputs["Color"]
    col = m.mix(stain, col, (0.02, 0.018, 0.016))
    # Slab joints.
    brick = m.node("ShaderNodeTexBrick", offset=0.0)
    brick.inputs["Scale"].default_value = 1.0
    brick.inputs["Mortar Size"].default_value = 0.005
    brick.inputs["Brick Width"].default_value = 2.0
    brick.inputs["Row Height"].default_value = 2.0
    brick.inputs["Color1"].default_value = (1, 1, 1, 1)
    brick.inputs["Color2"].default_value = (1, 1, 1, 1)
    brick.inputs["Mortar"].default_value = (0.45, 0.45, 0.45, 1)
    m.link(m.coord.outputs["Object"], brick.inputs["Vector"])
    col = m.mix(1.0, col, brick.outputs["Color"], "MULTIPLY")
    col = m.grime(col, 0.9, 0.6)
    rough = m.ramp(big.outputs["Fac"], [(0.58, (0.85, 0.85, 0.85)), (0.66, (0.2, 0.2, 0.2))]).outputs["Color"]
    m.link(rough, m.bsdf.inputs["Roughness"])
    b = m.node("ShaderNodeBump", Strength=0.25, Distance=0.02)
    m.link(fine.outputs["Fac"], b.inputs["Height"])
    m.link(b.outputs["Normal"], m.bsdf.inputs["Normal"])
    m.link(col, m.bsdf.inputs["Base Color"])
    return m.m


def block_wall():
    m = Mat("wall")
    brick = m.node("ShaderNodeTexBrick", offset=0.5)
    brick.inputs["Scale"].default_value = 1.0
    brick.inputs["Mortar Size"].default_value = 0.012
    brick.inputs["Brick Width"].default_value = 0.4
    brick.inputs["Row Height"].default_value = 0.2
    brick.inputs["Color1"].default_value = (0.13, 0.125, 0.12, 1)
    brick.inputs["Color2"].default_value = (0.09, 0.088, 0.085, 1)
    brick.inputs["Mortar"].default_value = (0.04, 0.04, 0.04, 1)
    mapping = m.node("ShaderNodeMapping")
    m.link(m.coord.outputs["Object"], mapping.inputs["Vector"])
    _input(mapping, "Rotation").default_value = (math.pi / 2, 0, 0)
    m.link(mapping.outputs["Vector"], brick.inputs["Vector"])
    fine = m.noise(25.0)
    col = m.mix(0.35, brick.outputs["Color"], m.ramp(fine.outputs["Fac"], [(0.3, (0.5, 0.5, 0.5)), (0.7, (1, 1, 1))]).outputs["Color"], "MULTIPLY")
    # Damp stains creeping up from the floor.
    sep = m.node("ShaderNodeSeparateXYZ")
    m.link(m.coord.outputs["Object"], sep.inputs["Vector"])
    damp_noise = m.noise(2.0)
    add = m.node("ShaderNodeMath", operation="ADD")
    m.link(sep.outputs["Z"], add.inputs[0])
    mul = m.node("ShaderNodeMath", operation="MULTIPLY")
    m.link(damp_noise.outputs["Fac"], mul.inputs[0])
    mul.inputs[1].default_value = 0.6
    m.link(mul.outputs[0], add.inputs[1])
    damp = m.ramp(add.outputs[0], [(0.4, (0.25, 0.22, 0.2)), (1.3, (1, 1, 1))]).outputs["Color"]
    col = m.mix(1.0, col, damp, "MULTIPLY")
    col = m.grime(col, 0.8, 0.4)
    m.link(col, m.bsdf.inputs["Base Color"])
    m.bsdf.inputs["Roughness"].default_value = 0.9
    b = m.node("ShaderNodeBump", Strength=0.4, Distance=0.02)
    m.link(brick.outputs["Fac"], b.inputs["Height"])
    m.link(b.outputs["Normal"], m.bsdf.inputs["Normal"])
    return m.m


def wood(name="wood", color=(0.16, 0.09, 0.05)):
    m = Mat(name)
    wave = m.node("ShaderNodeTexWave", wave_type="BANDS", bands_direction="X")
    wave.inputs["Scale"].default_value = 3.0
    wave.inputs["Distortion"].default_value = 6.0
    wave.inputs["Detail"].default_value = 4.0
    m.link(m.coord.outputs["Object"], wave.inputs["Vector"])
    col = m.ramp(wave.outputs["Fac"], [(0.2, tuple(c * 0.6 for c in color)), (0.8, color)]).outputs["Color"]
    col = m.grime(col, 0.8)
    return m.done(col, 0.7, 0.0, wave.outputs["Fac"], 0.1)


def corrugated(name, color, rust=0.3):
    m = rusty_metal(name, color, rust)
    nt = m.node_tree
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.wave_type = "BANDS"
    wave.bands_direction = "Z"
    wave.wave_profile = "SIN"
    wave.inputs["Scale"].default_value = 6.0
    coord = nt.nodes.new("ShaderNodeTexCoord")
    nt.links.new(coord.outputs["Object"], wave.inputs["Vector"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.8
    bump.inputs["Distance"].default_value = 0.03
    nt.links.new(wave.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], nt.nodes["Principled BSDF"].inputs["Normal"])
    return m


def emission(name, color, strength):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.remove(nt.nodes["Principled BSDF"])
    e = nt.nodes.new("ShaderNodeEmission")
    e.inputs["Color"].default_value = (*color, 1)
    e.inputs["Strength"].default_value = strength
    nt.links.new(e.outputs[0], nt.nodes["Material Output"].inputs["Surface"])
    return m


# --- Sprites --------------------------------------------------------------------------------

def crop(path: Path, out: Path, pad=2) -> dict:
    """Crops a full-screen render to its visible pixels; returns where it sits on screen."""
    img = Image.open(path)
    bbox = img.getchannel("A").point(lambda a: 255 if a > 3 else 0).getbbox()
    x0, y0, x1, y1 = bbox
    x0, y0 = max(0, x0 - pad), max(0, y0 - pad)
    x1, y1 = min(img.width, x1 + pad), min(img.height, y1 + pad)
    img.crop((x0, y0, x1, y1)).save(out, optimize=True)
    return {"x": x0, "y": y0, "w": x1 - x0, "h": y1 - y0}


def vignette(img: Image.Image, strength=0.55) -> Image.Image:
    w, h = img.size
    mask = Image.new("L", (w, h), 0)
    px = mask.load()
    for y in range(0, h, 4):
        for x in range(0, w, 4):
            dx, dy = (x - w * 0.36) / (w * 0.6), (y - h * 0.5) / (h * 0.65)
            v = int(255 * min(1.0, (dx * dx + dy * dy) ** 1.2 * strength))
            for yy in range(y, min(y + 4, h)):
                for xx in range(x, min(x + 4, w)):
                    px[xx, yy] = v
    mask = mask.filter(ImageFilter.GaussianBlur(20))
    dark = Image.new("RGBA", (w, h), (4, 4, 6, 255))
    return Image.composite(dark, img, mask)


# --- The garage ---------------------------------------------------------------------------------

ROOM_W, ROOM_D, WALL_H, WALL_T = 8.0, 6.0, 2.8, 0.3
FRONT_H = 0.45
# Where on screen the room's centre sits: the right part of the screen is the side panel.
ROOM_SCREEN_X = 450

BIN_AT = Vector((2.5, 3.9, 0))
PLAYER_AT = Vector((3.7, 3.2, 0))


def garage_camera(scene):
    width = SCREEN_W / PPM
    target_v = 3.25  # vertical screen position (m) of the screen centre, measured along the view
    shift_x = (SCREEN_W / 2 - ROOM_SCREEN_X) / PPM
    target = Vector((ROOM_W / 2 + shift_x, target_v / math.sin(PITCH) - 0.05, 0))
    return camera(scene, target, width, (SCREEN_W, SCREEN_H))


def screen_pos(scene, world: Vector) -> tuple[float, float]:
    from bpy_extras.object_utils import world_to_camera_view
    co = world_to_camera_view(scene, scene.camera, world)
    return co.x * SCREEN_W, (1 - co.y) * SCREEN_H


def build_garage(coll_room, coll_bin):
    floor_m = concrete_floor()
    wall_m = block_wall()
    cap_m = plain("wall_cap", (0.05, 0.05, 0.055), 0.9, variation=0.3)
    ground_m = plain("asphalt", (0.035, 0.035, 0.04), 0.95, variation=0.4, scale=20, bump=0.4)

    box("ground", (40, 40, 0.1), (ROOM_W / 2, ROOM_D / 2, -0.06), ground_m, coll_room)
    box("floor", (ROOM_W, ROOM_D, 0.02), (ROOM_W / 2, ROOM_D / 2, -0.01), floor_m, coll_room)

    # Back wall full height; side walls step down towards the cut-away front wall.
    def wall(name, x0, x1, y0, y1, h0, h1):
        """Wall block with height h0 at y0 and h1 at y1, plus a dark cap on top."""
        v = [(x0, y0, 0), (x1, y0, 0), (x1, y1, 0), (x0, y1, 0),
             (x0, y0, h0), (x1, y0, h0), (x1, y1, h1), (x0, y1, h1)]
        f = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
        mesh_from(name, v, f, wall_m, coll_room)
        mesh_from(name + "_cap", [(x0 - 0.01, y0 - 0.01, h0), (x1 + 0.01, y0 - 0.01, h0), (x1 + 0.01, y1 + 0.01, h1),
                                  (x0 - 0.01, y1 + 0.01, h1), (x0 - 0.01, y0 - 0.01, h0 + 0.04), (x1 + 0.01, y0 - 0.01, h0 + 0.04),
                                  (x1 + 0.01, y1 + 0.01, h1 + 0.04), (x0 - 0.01, y1 + 0.01, h1 + 0.04)], f, cap_m, coll_room)

    wall("wall_back", -WALL_T, ROOM_W + WALL_T, ROOM_D, ROOM_D + WALL_T, WALL_H, WALL_H)
    wall("wall_left", -WALL_T, 0, -WALL_T, ROOM_D, FRONT_H, WALL_H)
    wall("wall_right", ROOM_W, ROOM_W + WALL_T, -WALL_T, ROOM_D, FRONT_H, WALL_H)
    wall("wall_front", 0, ROOM_W, -WALL_T, 0, FRONT_H, FRONT_H)

    # Roller door in the back wall.
    door_m = corrugated("door", (0.2, 0.22, 0.24), rust=0.3)
    frame_m = rusty_metal("frame", (0.12, 0.12, 0.13), 0.5)
    box("door", (2.8, 0.06, 2.3), (1.9, ROOM_D - 0.02, 1.15), door_m, coll_room)
    box("door_box", (3.1, 0.35, 0.35), (1.9, ROOM_D - 0.15, 2.45), frame_m, coll_room, bevel=0.02)
    for x in (0.45, 3.35):
        box("door_rail", (0.12, 0.12, 2.3), (x, ROOM_D - 0.06, 1.15), frame_m, coll_room, bevel=0.01)
    box("door_handle", (0.3, 0.06, 0.05), (1.9, ROOM_D - 0.07, 0.25), frame_m, coll_room, bevel=0.01)

    # Small dirty window with cold light behind it.
    box("window_frame", (1.1, 0.12, 0.7), (6.3, ROOM_D - 0.02, 1.85), frame_m, coll_room, bevel=0.02)
    glass = Mat("window_glass")
    n = glass.noise(6.0)
    glass_col = glass.ramp(n.outputs["Fac"], [(0.3, (0.05, 0.09, 0.12)), (0.7, (0.18, 0.24, 0.28))]).outputs["Color"]
    em = glass.node("ShaderNodeEmission", Strength=1.2)
    glass.link(glass_col, em.inputs["Color"])
    glass.link(em.outputs[0], glass.nt.nodes["Material Output"].inputs["Surface"])
    box("window_glass", (0.95, 0.05, 0.55), (6.3, ROOM_D - 0.09, 1.85), glass.m, coll_room)
    box("window_bar", (0.04, 0.06, 0.55), (6.3, ROOM_D - 0.11, 1.85), frame_m, coll_room)
    box("window_bar2", (0.95, 0.06, 0.04), (6.3, ROOM_D - 0.11, 1.85), frame_m, coll_room)

    # Workbench under the window with a vice, a toolbox and junk.
    wood_m = wood()
    steel = rusty_metal("steel", (0.18, 0.18, 0.19), 0.3)
    box("bench_top", (2.4, 0.8, 0.08), (6.3, ROOM_D - 0.45, 0.9), wood_m, coll_room, bevel=0.01)
    for x in (5.2, 7.4):
        for y in (ROOM_D - 0.8, ROOM_D - 0.12):
            box("bench_leg", (0.08, 0.08, 0.86), (x, y, 0.43), steel, coll_room, bevel=0.005)
    box("bench_shelf", (2.3, 0.7, 0.04), (6.3, ROOM_D - 0.45, 0.25), wood_m, coll_room)
    red = rusty_metal("toolbox", (0.35, 0.04, 0.03), 0.3)
    box("toolbox", (0.55, 0.26, 0.24), (6.9, ROOM_D - 0.45, 1.06), red, coll_room, bevel=0.02)
    box("toolbox_lid", (0.57, 0.27, 0.04), (6.9, ROOM_D - 0.45, 1.19), red, coll_room, bevel=0.01)
    box("vice", (0.2, 0.25, 0.16), (5.5, ROOM_D - 0.75, 1.02), steel, coll_room, bevel=0.02)
    cylinder("can", 0.06, 0.16, (6.1, ROOM_D - 0.3, 1.02), plain("can", (0.4, 0.3, 0.05), 0.4, 0.5), coll_room)
    cylinder("can2", 0.05, 0.12, (6.25, ROOM_D - 0.55, 1.0), plain("can2", (0.1, 0.15, 0.3), 0.4, 0.5), coll_room)
    for i in range(4):
        box("part", (0.08 + random.random() * 0.1, 0.06, 0.03), (5.8 + random.random() * 0.4, ROOM_D - 0.5 - random.random() * 0.2, 0.96),
            steel, coll_room, rotation=(0, 0, random.random() * 3))
    # Pegboard with tools on the wall above the bench.
    board = plain("pegboard", (0.12, 0.09, 0.06), 0.9)
    box("pegboard", (1.0, 0.03, 0.6), (5.25, ROOM_D - 0.02, 1.55), board, coll_room)
    for i in range(5):
        box("tool", (0.04, 0.03, 0.25 + 0.1 * random.random()), (4.9 + i * 0.18, ROOM_D - 0.05, 1.55), steel, coll_room,
            rotation=(0, random.uniform(-0.2, 0.2), 0))

    # Steel shelving along the left wall with boxes and canisters.
    shelf_m = rusty_metal("shelf", (0.15, 0.16, 0.17), 0.4)
    cardboard = plain("cardboard", (0.28, 0.18, 0.09), 0.85, variation=0.25)
    for z in (0.05, 0.6, 1.15, 1.7):
        box("shelf_board", (0.6, 2.2, 0.04), (0.35, 2.9, z), shelf_m, coll_room)
    for y in (1.85, 3.95):
        for x in (0.07, 0.63):
            box("shelf_post", (0.05, 0.05, 1.8), (x, y, 0.9), shelf_m, coll_room)
    for z in (0.07, 0.62, 1.17, 1.72):
        y = 2.0
        while y < 3.8:
            w = random.uniform(0.3, 0.55)
            h = random.uniform(0.2, 0.42)
            if random.random() < 0.8:
                box("box", (0.45, w * 0.9, h), (0.34, y + w / 2, z + h / 2), cardboard, coll_room, bevel=0.01,
                    rotation=(0, 0, random.uniform(-0.08, 0.08)))
            y += w

    # Barrels, tyres and junk on the right.
    barrel_m = rusty_metal("barrel", (0.05, 0.12, 0.25), 0.5)
    barrel2_m = rusty_metal("barrel2", (0.3, 0.07, 0.04), 0.6)
    for (x, y, m) in ((7.45, 2.6, barrel_m), (7.4, 1.85, barrel2_m)):
        cylinder("barrel", 0.3, 0.9, (x, y, 0.45), m, coll_room, bevel=0.01)
        for z in (0.3, 0.6):
            torus("rib", 0.3, 0.015, (x, y, z), m, coll_room)
        cylinder("lid", 0.27, 0.01, (x, y, 0.905), m, coll_room)
    rubber = plain("rubber", (0.025, 0.025, 0.025), 0.75, variation=0.3, scale=30, bump=0.5)
    for i in range(3):
        torus("tyre", 0.27, 0.11, (6.6, 1.0, 0.11 + i * 0.22), rubber, coll_room)
    torus("tyre", 0.27, 0.11, (5.9, 0.75, 0.11), rubber, coll_room, rotation=(0, 0, 0))

    # Scattered paper and a stain near the door.
    paper = plain("paper", (0.26, 0.25, 0.22), 0.9, variation=0.2)
    for i in range(8):
        box("scrap", (random.uniform(0.1, 0.25), random.uniform(0.1, 0.2), 0.005),
            (random.uniform(0.9, 5.0), random.uniform(0.6, 5.2), 0.004), paper, coll_room,
            rotation=(0, 0, random.random() * 3))
    cable = plain("cable", (0.02, 0.02, 0.02), 0.5)
    pts = [(4.5, ROOM_D - 0.05, 1.2), (4.3, ROOM_D - 0.3, 0.02), (3.8, 4.8, 0.02), (3.4, 4.6, 0.02)]
    for a, b in zip(pts, pts[1:]):
        va, vb = Vector(a), Vector(b)
        mid = (va + vb) / 2
        d = vb - va
        c = cylinder("cable", 0.012, d.length, mid, cable, coll_room, verts=8)
        c.rotation_mode = "QUATERNION"
        c.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d)

    # Pipes along the back wall, a fuse box and other clutter.
    pipe_m = rusty_metal("pipe", (0.2, 0.2, 0.21), 0.4)
    rot_x = (0, math.pi / 2, 0)
    cylinder("pipe", 0.06, ROOM_W, (ROOM_W / 2, ROOM_D - 0.12, 2.5), pipe_m, coll_room, rotation=rot_x)
    cylinder("pipe2", 0.035, ROOM_W, (ROOM_W / 2, ROOM_D - 0.1, 2.32), pipe_m, coll_room, rotation=rot_x)
    cylinder("pipe_down", 0.06, 2.5, (ROOM_W - 0.15, ROOM_D - 0.12, 1.25), pipe_m, coll_room)
    for x in (1.0, 3.5, 6.0):
        box("pipe_clamp", (0.06, 0.16, 0.16), (x, ROOM_D - 0.1, 2.5), steel, coll_room, bevel=0.01)
    fuse_m = plain("fuse", (0.3, 0.3, 0.27), 0.5, 0.3)
    box("fuse_box", (0.4, 0.15, 0.5), (4.3, ROOM_D - 0.08, 1.5), fuse_m, coll_room, bevel=0.02)
    box("fuse_sign", (0.12, 0.01, 0.1), (4.3, ROOM_D - 0.16, 1.62), plain("sign", (0.7, 0.5, 0.0), 0.5), coll_room)
    pallet_m = wood("pallet", (0.2, 0.13, 0.07))
    for i in range(5):
        box("pallet_board", (1.0, 0.13, 0.03), (1.6, 0.55 + i * 0.19, 0.13), pallet_m, coll_room, bevel=0.005)
    for y in (0.55, 0.93, 1.31):
        box("pallet_block", (1.0, 0.1, 0.1), (1.6, y, 0.05), pallet_m, coll_room)
    gas = rusty_metal("gas", (0.35, 0.05, 0.03), 0.3)
    cylinder("gas", 0.14, 0.6, (4.75, ROOM_D - 0.35, 0.3), gas, coll_room, bevel=0.01)
    sphere("gas_top", 0.14, (4.75, ROOM_D - 0.35, 0.6), gas, coll_room, scale=(1, 1, 0.6))
    cylinder("gas_valve", 0.03, 0.12, (4.75, ROOM_D - 0.35, 0.72), steel, coll_room)
    battery = plain("battery", (0.03, 0.03, 0.035), 0.5)
    box("battery", (0.3, 0.18, 0.2), (2.0, 1.0, 0.28), battery, coll_room, bevel=0.01, rotation=(0, 0, 0.3))

    # Bare bulb hanging from the ceiling (only its glow is visible).
    lamp = light("POINT", (4.0, 3.4, 2.6), 220, (1.0, 0.72, 0.42), size=0.08)
    light("AREA", (6.3, ROOM_D - 0.4, 1.9), 25, (0.55, 0.7, 1.0), size=0.8, rotation=(math.radians(-70), 0, 0))
    light("AREA", (4.0, 3.0, 8.0), 30, (0.5, 0.6, 0.8), size=10)
    # Faint cold fill from the open front, so the faces turned to the camera are not black.
    light("AREA", (4.0, -4.0, 3.0), 120, (0.55, 0.62, 0.8), size=6, rotation=(math.radians(60), 0, 0))

    # The trash bin and the bags beside it.
    build_bin(coll_bin, BIN_AT)
    return lamp


def build_bin(coll, at: Vector):
    """A big wheelie bin with its lid thrown open and bags of trash inside and around it."""
    green = plain("bin", (0.035, 0.11, 0.05), 0.5, variation=0.25, grime=0.85, bump=0.2)
    lid_m = plain("bin_lid", (0.03, 0.09, 0.04), 0.45, variation=0.2, grime=0.7)
    rubber = plain("wheel", (0.02, 0.02, 0.02), 0.8)
    steel = rusty_metal("bin_axle", (0.2, 0.2, 0.2), 0.4)
    bag_m = plain("bag", (0.012, 0.012, 0.014), 0.25, variation=0.5, scale=4, bump=0.6)
    w0, d0, w1, d1, h = 0.29, 0.3, 0.36, 0.38, 1.05
    v = [(-w0, -d0, 0.05), (w0, -d0, 0.05), (w0, d0, 0.05), (-w0, d0, 0.05),
         (-w1, -d1, h), (w1, -d1, h), (w1, d1, h), (-w1, d1, h)]
    # Open box: no top face, thickened so the inside is visible.
    f = [(0, 1, 2, 3), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
    body = mesh_from("bin", [(x + at.x, y + at.y, z) for x, y, z in v], f, green, coll)
    solid = body.modifiers.new("solid", "SOLIDIFY")
    solid.thickness = 0.03
    bevel = body.modifiers.new("bevel", "BEVEL")
    bevel.width = 0.02
    bevel.segments = 3
    for z in (0.35, 0.75):
        t = z / h
        box("bin_rib", (2 * (w0 + (w1 - w0) * t) + 0.04, 2 * (d0 + (d1 - d0) * t) + 0.04, 0.04),
            at + Vector((0, 0, z)), green, coll, bevel=0.015)
    box("bin_rim", (2 * w1 + 0.06, 2 * d1 + 0.06, 0.05), at + Vector((0, 0, h)), lid_m, coll, bevel=0.015)
    # The lid hangs open behind the bin.
    box("bin_lid", (2 * w1 + 0.08, 0.05, 2 * d1 + 0.08), at + Vector((0, d1 + 0.07, h - d1 + 0.02)), lid_m, coll,
        bevel=0.02, rotation=(math.radians(-8), 0, 0))
    box("bin_handle", (0.5, 0.05, 0.05), at + Vector((0, d1 + 0.12, h - 0.05)), steel, coll, bevel=0.015)
    # Recycling sticker on the front.
    box("bin_sticker", (0.3, 0.01, 0.22), at + Vector((0, -d1 + 0.04, 0.72)), plain("sticker", (0.75, 0.55, 0.05), 0.5, grime=0.4),
        coll, rotation=(math.radians(-4), 0, 0))
    box("bin_sticker_mark", (0.12, 0.012, 0.12), at + Vector((0, -d1 + 0.035, 0.72)), plain("mark", (0.02, 0.03, 0.02), 0.5),
        coll, rotation=(math.radians(-4), 0, math.radians(45)))
    for x in (-0.25, 0.25):
        cylinder("bin_wheel", 0.11, 0.07, at + Vector((x, d0 + 0.05, 0.11)), rubber, coll, rotation=(0, math.pi / 2, 0))
    cylinder("bin_axle", 0.02, 0.6, at + Vector((0, d0 + 0.05, 0.11)), steel, coll, rotation=(0, math.pi / 2, 0))
    # Bags inside, poking out of the top, and more on the floor.
    for (dx, dy, r) in ((-0.12, -0.08, 0.2), (0.14, 0.06, 0.19), (0.0, 0.12, 0.17)):
        displace(sphere("bin_trash", r, at + Vector((dx, dy, h - 0.05)), bag_m, coll, scale=(1, 1, 0.8)), 0.06, 0.15)
    for (dx, dy, r) in ((-0.62, -0.15, 0.24), (-0.45, -0.55, 0.2), (0.55, -0.4, 0.22)):
        bag = sphere("bag", r, at + Vector((dx, dy, r * 0.8)), bag_m, coll, scale=(1, 1, 0.85))
        displace(bag, 0.07, 0.15)
        cylinder("bag_knot", 0.035, 0.11, at + Vector((dx, dy, r * 1.6)), bag_m, coll, radius2=0.01)


def render_garage():
    scene = reset()
    scene.cycles.samples = 160
    set_world((0.012, 0.014, 0.018), 1.0)
    room = collection("room")
    bin_coll = collection("bin")
    build_garage(room, bin_coll)
    garage_camera(scene)

    out = ART / "garage"
    out.mkdir(parents=True, exist_ok=True)
    layout = {}

    # 1. The whole room, bin included, as the background.
    scene.render.film_transparent = False
    render(TMP / "garage_full.png")
    vignette(Image.open(TMP / "garage_full.png").convert("RGBA")).convert("RGB").save(out / "background.jpg", quality=92)

    # 2. The bin alone (everything else cut out), for the hover highlight and click area.
    scene.render.film_transparent = True
    for obj in room.objects:
        obj.is_holdout = True
    render(TMP / "garage_bin.png")
    layout["bin"] = crop(TMP / "garage_bin.png", out / "bin.png")
    for obj in room.objects:
        obj.is_holdout = False

    # Where the player stands, in screen pixels (feet).
    x, y = screen_pos(scene, PLAYER_AT)
    layout["player"] = {"x": round(x), "y": round(y)}
    layout["pixelsPerMetre"] = PPM
    (out / "layout.json").write_text(json.dumps(layout, indent=1))
    print("garage", layout)


# --- Character ------------------------------------------------------------------------------

HAIR_STYLES = 6
SHIRT_STYLES = 3
CHAR_RES = (128, 240)
CHAR_WIDTH_M = 0.8


def tint_mat(name, roughness=0.6, bump=0.1, scale=40.0, sheen=False):
    """Light grey base that the game tints with the colour chosen in the editor."""
    m = Mat(name)
    n = m.noise(scale)
    col = m.ramp(n.outputs["Fac"], [(0.3, (0.62, 0.62, 0.62)), (0.7, (0.75, 0.75, 0.75))]).outputs["Color"]
    col = m.grime(col, 0.5, 0.08)
    mat = m.done(col, roughness, 0.0, n.outputs["Fac"], bump)
    if sheen:
        _input(m.bsdf, "Sheen Weight").default_value = 0.4
    return mat


def build_character():
    """Returns ({layer: [objects]}, shirt variants, hair variants, bare skin per shirt), facing the camera (-Y)."""
    skin = tint_mat("skin", 0.5, 0.02, 60)
    cloth = tint_mat("cloth", 0.85, 0.25, 90, sheen=True)
    pants_m = tint_mat("denim", 0.85, 0.3, 120)
    shoe_m = tint_mat("shoe", 0.45, 0.1, 30)
    hair_m = tint_mat("hair", 0.45, 0.6, 200)
    eye = plain("eye", (0.01, 0.01, 0.01), 0.2, variation=0.0, grime=0.0)
    mouth = plain("mouth", (0.25, 0.08, 0.07), 0.5, variation=0.0, grime=0.0)
    belt = plain("belt", (0.04, 0.03, 0.025), 0.5, grime=0.3)
    buckle = plain("buckle", (0.6, 0.55, 0.4), 0.3, 1.0, grime=0.2)

    L = {"skin": [], "pants": [], "shoes": [], "detail": []}
    # Skin that only some shirts show (the tank top's bare shoulders), by shirt style.
    bare = {style: [] for style in range(SHIRT_STYLES)}
    for side in (-1, 1):
        x = side * 0.09
        L["shoes"].append(box("shoe", (0.11, 0.22, 0.08), (x, -0.03, 0.04), shoe_m, bevel=0.035))
        L["pants"].append(cylinder("leg", 0.068, 0.84, (x, 0, 0.5), pants_m, radius2=0.08))
    L["pants"].append(sphere("hips", 1.0, (0, 0, 0.94), pants_m, scale=(0.17, 0.115, 0.13)))
    L["detail"].append(cylinder("belt", 1.0, 0.04, (0, 0, 1.0), belt, verts=32))
    L["detail"][-1].scale = (0.175, 0.12, 1)
    L["detail"].append(box("buckle", (0.05, 0.02, 0.035), (0, -0.12, 1.0), buckle, bevel=0.005))
    L["skin"].append(cylinder("neck", 0.05, 0.14, (0, 0, 1.52), skin))
    L["skin"].append(sphere("head", 0.12, (0, 0, 1.67), skin, scale=(0.92, 0.98, 1.08)))
    L["skin"].append(sphere("nose", 0.02, (0, -0.115, 1.655), skin))
    L["detail"].append(box("mouth", (0.04, 0.01, 0.008), (0, -0.108, 1.615), mouth))
    for side in (-1, 1):
        L["skin"].append(sphere("ear", 0.028, (side * 0.11, 0, 1.67), skin, scale=(0.5, 1, 1.2)))
        L["detail"].append(sphere("eye", 0.015, (side * 0.042, -0.104, 1.69), eye))
        # Arms hang along the body, slightly away from it.
        L["skin"].append(cylinder("arm", 0.042, 0.52, (side * 0.215, 0, 1.17), skin, rotation=(0, side * 0.1, 0), radius2=0.05))
        L["skin"].append(sphere("hand", 0.045, (side * 0.24, -0.01, 0.88), skin, scale=(0.8, 1, 1.15)))

    shirts = []
    for style in range(SHIRT_STYLES):
        # Torso: a tapered, slightly flattened cylinder, wider at the shoulders.
        top = 0.17 if style == 1 else 0.19
        torso = cylinder("torso", 0.16, 0.5, (0, 0, 1.24), cloth, radius2=top, verts=40)
        torso.scale = (1, 0.66, 1)
        bevel = torso.modifiers.new("bevel", "BEVEL")
        bevel.width = 0.05
        bevel.segments = 4
        objs = [torso, sphere("chest", 1.0, (0, -0.02, 1.32), cloth, scale=(top * 0.95, 0.12, 0.14))]
        for side in (-1, 1):
            shoulder = Vector((side * 0.19, 0, 1.43))
            if style == 1:  # Tank top: bare shoulders, straps.
                bare[style].append(sphere("shoulder", 0.055, shoulder, skin))
                objs.append(box("strap", (0.05, 0.2, 0.05), (side * 0.1, 0, 1.47), cloth, bevel=0.02))
            else:
                objs.append(sphere("shoulder", 0.064, shoulder, cloth))
            if style == 0:  # T-shirt sleeves.
                objs.append(cylinder("sleeve", 0.058, 0.2, (side * 0.2, 0, 1.34), cloth, rotation=(0, side * 0.1, 0), radius2=0.062))
            elif style == 2:  # Hoodie: long sleeves.
                objs.append(cylinder("sleeve", 0.054, 0.5, (side * 0.215, 0, 1.17), cloth, rotation=(0, side * 0.1, 0), radius2=0.062))
        if style == 2:
            objs.append(sphere("hood", 1.0, (0, 0.07, 1.5), cloth, scale=(0.14, 0.08, 0.07)))
            objs.append(box("pocket", (0.2, 0.03, 0.09), (0, -0.105, 1.1), cloth, bevel=0.02))
        shirts.append(objs)

    def cap(co):
        return co.z > -0.02 or co.y > 0.02

    hairs = [[]]
    head = Vector((0, 0, 1.67))
    for style in range(1, HAIR_STYLES):
        objs = [sphere("hair", 0.128, head + Vector((0, 0.01, 0.012)), hair_m, scale=(0.95, 1.0, 1.08), keep=cap)]
        if style == 2:  # Spiky.
            for i in range(9):
                a = i / 9 * 2 * math.pi
                d = Vector((math.cos(a) * 0.065, math.sin(a) * 0.065 + 0.01, 0.115))
                c = cylinder("spike", 0.032, 0.09, head + d, hair_m, radius2=0.0, verts=8)
                c.rotation_euler = (-d.y * 4, d.x * 4, 0)
                objs.append(c)
        elif style == 3:  # Long.
            objs.append(box("long", (0.24, 0.1, 0.32), head + Vector((0, 0.065, -0.15)), hair_m, bevel=0.045))
            for side in (-1, 1):
                objs.append(box("lock", (0.05, 0.09, 0.28), head + Vector((side * 0.11, 0.0, -0.12)), hair_m, bevel=0.022))
        elif style == 4:  # Ponytail.
            objs.append(sphere("tie", 0.04, head + Vector((0, 0.13, 0.03)), hair_m))
            objs.append(cylinder("tail", 0.042, 0.26, head + Vector((0, 0.16, -0.1)), hair_m, radius2=0.014,
                                 rotation=(math.radians(-15), 0, 0)))
        elif style == 5:  # Curly.
            for i in range(26):
                a, b = random.random() * 2 * math.pi, random.uniform(0.0, 1.3)
                d = Vector((math.cos(a) * math.sin(b), math.sin(a) * math.sin(b) + 0.02, math.cos(b))) * 0.13
                if d.y < -0.055 and d.z < 0.055:
                    continue
                objs.append(sphere("curl", 0.042, head + d, hair_m, segments=12))
        hairs.append(objs)
    return L, shirts, hairs, bare


# Mask colours: which tint each pixel takes. Two images with three channels each.
MASKS = {
    "a": {"skin": (1, 0, 0), "shirt": (0, 1, 0), "pants": (0, 0, 1)},
    "b": {"hair": (1, 0, 0), "shoes": (0, 1, 0), "detail": (0, 0, 1)},
}


def render_character():
    """Per hair and shirt style: one grey shading image and two masks saying which pixels
    are skin, shirt, pants, hair, shoes or untinted detail. A shader in the game tints them,
    which avoids seams between separately rendered layers."""
    scene = reset()
    scene.cycles.samples = 64
    set_world((0.25, 0.27, 0.3), 0.6)
    L, shirts, hairs, bare = build_character()
    cam = camera(scene, Vector((0, 0, 0.86)), CHAR_WIDTH_M, CHAR_RES)
    cam.data.sensor_fit = "HORIZONTAL"
    light("SUN", (0, 0, 5), 3.5, (1.0, 0.95, 0.88), size=0.3, rotation=(math.radians(40), math.radians(-25), math.radians(-20)))
    light("SUN", (0, 0, 5), 1.2, (0.6, 0.7, 1.0), size=0.5, rotation=(math.radians(60), math.radians(40), math.radians(150)))
    light("AREA", (0, 1.5, 2.2), 60, (1, 1, 1), size=1.5, rotation=(math.radians(-50), 0, 0))
    catcher = box("catcher", (4, 4, 0.01), (0, 0, -0.005))
    catcher.is_shadow_catcher = True

    all_shirt = [o for s in shirts for o in s] + [o for objs in bare.values() for o in objs]
    all_hair = [o for h in hairs for o in h]
    out = ART / "character"
    out.mkdir(parents=True, exist_ok=True)
    for old in out.glob("*.png"):
        old.unlink()

    def show(objs, visible):
        for o in objs:
            o.hide_render = not visible

    # Shadow: the body is invisible to the camera but still casts a shadow on the catcher.
    show(all_shirt, False)
    show(all_hair, False)
    show(shirts[0] + hairs[1], True)
    meshes = [o for o in scene.objects if o.type == "MESH" and o is not catcher]
    lights = [o for o in scene.objects if o.type == "LIGHT"]
    for o in meshes:
        o.visible_camera = False
    # A light from almost straight above, like the garage bulb, keeps the shadow inside the frame.
    for o in lights:
        o.hide_render = True
    overhead = light("SUN", (0, 0, 5), 4.0, size=0.25, rotation=(math.radians(12), math.radians(8), 0))
    render(out / "shadow.png")
    overhead.hide_render = True
    for o in lights:
        o.hide_render = False
    for o in meshes:
        o.visible_camera = True
    catcher.hide_render = True

    # Flat emission materials for the masks; originals are kept to swap back.
    originals = {o: list(o.data.materials) for o in meshes}
    flat = {}

    def mask_mode(layers, channel_colors):
        for name, objs in layers.items():
            colour = channel_colors.get(name, (0, 0, 0))
            key = tuple(colour)
            if key not in flat:
                flat[key] = emission(f"mask{key}", colour, 1.0)
            for o in objs:
                o.data.materials.clear()
                o.data.materials.append(flat[key])

    def shade_mode():
        for o, mats in originals.items():
            o.data.materials.clear()
            for m in mats:
                o.data.materials.append(m)

    for h in range(HAIR_STYLES):
        for s in range(SHIRT_STYLES):
            show(all_shirt, False)
            show(all_hair, False)
            show(shirts[s] + hairs[h] + bare[s], True)
            layers = {"skin": L["skin"] + bare[s], "pants": L["pants"], "shoes": L["shoes"], "detail": L["detail"],
                      "shirt": shirts[s], "hair": hairs[h]}
            shade_mode()
            scene.view_settings.view_transform = "AgX"
            scene.view_settings.look = "AgX - Medium High Contrast"
            scene.cycles.samples = 64
            scene.cycles.use_denoising = True
            render(out / f"h{h}_s{s}.png")
            scene.view_settings.view_transform = "Standard"
            scene.view_settings.look = "None"
            scene.cycles.samples = 16
            scene.cycles.use_denoising = False
            for name, colours in MASKS.items():
                mask_mode(layers, colours)
                render(out / f"h{h}_s{s}_mask_{name}.png")
    shade_mode()

    meta = {"width": CHAR_RES[0], "height": CHAR_RES[1], "pixelsPerMetre": CHAR_RES[0] / CHAR_WIDTH_M}
    # Feet position in the image, so the game can stand the character on the floor.
    from bpy_extras.object_utils import world_to_camera_view
    feet = world_to_camera_view(scene, cam, Vector((0, 0, 0)))
    meta["feetX"] = round(feet.x * CHAR_RES[0])
    meta["feetY"] = round((1 - feet.y) * CHAR_RES[1])
    (out / "meta.json").write_text(json.dumps(meta, indent=1))
    print("character", meta)


# --- Item icons ---------------------------------------------------------------------------------

def icon_scene():
    scene = reset()
    scene.cycles.samples = 64
    set_world((0.3, 0.32, 0.36), 0.8)
    camera(scene, Vector((0, 0, 0.12)), 0.62, (128, 128), pitch=math.radians(50))
    light("SUN", (0, 0, 5), 4.0, (1, 0.96, 0.9), size=0.2, rotation=(math.radians(35), math.radians(-30), math.radians(-25)))
    light("AREA", (0, 1.0, 1.0), 40, (0.7, 0.8, 1.0), size=1.0, rotation=(math.radians(-60), 0, 0))
    return scene


def item_models():
    """Each builder makes one item roughly 0.5 m across, centred on the origin."""

    def trash():
        bag = plain("bag", (0.015, 0.015, 0.018), 0.25, variation=0.5, scale=4, bump=0.6)
        displace(sphere("bag", 0.2, (0, 0, 0.17), bag, scale=(1, 1, 0.9)), 0.06, 0.15)
        cylinder("knot", 0.035, 0.12, (0, 0, 0.38), bag, radius2=0.01)
        cylinder("tie", 0.04, 0.03, (0, 0, 0.33), plain("tie", (0.6, 0.45, 0.05), 0.5))

    def paper():
        m = plain("paper", (0.62, 0.6, 0.55), 0.9, variation=0.12, scale=30)
        m2 = plain("paper2", (0.5, 0.48, 0.44), 0.9, variation=0.12, scale=30)
        for i in range(7):
            box("sheet", (0.4, 0.3, 0.025), (random.uniform(-0.01, 0.01), random.uniform(-0.01, 0.01), 0.02 + i * 0.03),
                m if i % 2 else m2, rotation=(0, 0, random.uniform(-0.1, 0.1)))
        string = plain("string", (0.35, 0.25, 0.12), 0.8)
        box("string", (0.42, 0.015, 0.24), (0, 0, 0.12), string)
        box("string2", (0.015, 0.32, 0.24), (0, 0, 0.12), string)

    def aluminium():
        m = plain("alu", (0.75, 0.76, 0.78), 0.25, 1.0, variation=0.1, grime=0.3)
        red = plain("label", (0.6, 0.05, 0.05), 0.3, 0.6, grime=0.3)
        for i, (x, y) in enumerate(((-0.1, 0.0), (0.12, 0.05))):
            can = cylinder("can", 0.1, 0.32, (x * 1.3, y, 0.1), m if i else red, rotation=(math.pi / 2, 0, i * 1.2))
            displace(can, 0.035, 0.12, 1)

    def copper():
        m = plain("copper", (0.75, 0.33, 0.14), 0.3, 1.0, variation=0.15, grime=0.4)
        for i in range(6):
            torus("coil", 0.17 - i * 0.004, 0.018, (0, 0, 0.02 + i * 0.03), m)
        cylinder("wire", 0.015, 0.25, (0.2, -0.05, 0.1), m, rotation=(0.6, 0.9, 0))

    def plastic():
        m = Mat("pet")
        m.bsdf.inputs["Base Color"].default_value = (0.3, 0.6, 0.9, 1)
        _input(m.bsdf, "Transmission Weight").default_value = 0.8
        m.bsdf.inputs["Roughness"].default_value = 0.15
        cap = plain("cap", (0.05, 0.25, 0.6), 0.4)
        label = plain("label", (0.85, 0.85, 0.9), 0.5)
        # Lying bottle along a direction in the ground plane: body, label, neck, cap.
        angle = 0.5
        axis = Vector((-math.sin(angle), math.cos(angle), 0))
        rot = (math.pi / 2, 0, angle)
        cylinder("bottle", 0.09, 0.3, axis * -0.03 + Vector((0, 0, 0.09)), m.m, rotation=rot)
        cylinder("label", 0.092, 0.12, axis * -0.03 + Vector((0, 0, 0.09)), label, rotation=rot)
        cylinder("neck", 0.035, 0.1, axis * -0.23 + Vector((0, 0, 0.09)), m.m, radius2=0.09, rotation=rot)
        cylinder("cap", 0.04, 0.05, axis * -0.3 + Vector((0, 0, 0.09)), cap, rotation=rot)

    def glass():
        m = Mat("glass")
        m.bsdf.inputs["Base Color"].default_value = (0.1, 0.4, 0.15, 1)
        _input(m.bsdf, "Transmission Weight").default_value = 0.6
        m.bsdf.inputs["Roughness"].default_value = 0.05
        for i in range(7):
            a = i / 7 * 2 * math.pi
            r = random.uniform(0.05, 0.16)
            v = [(0, 0, 0), (random.uniform(0.14, 0.24), 0, 0), (random.uniform(0.04, 0.18), random.uniform(0.1, 0.2), 0)]
            v += [(x, y, 0.02) for (x, y, _) in v]
            f = [(0, 1, 2), (3, 5, 4), (0, 3, 4, 1), (1, 4, 5, 2), (2, 5, 3, 0)]
            o = mesh_from("shard", v, f, m.m)
            o.location = (math.cos(a) * r - 0.05, math.sin(a) * r - 0.03, 0.02 + random.random() * 0.04)
            o.rotation_euler = (random.uniform(-0.4, 0.4), random.uniform(-0.4, 0.4), random.random() * 6)

    def coin():
        gold = plain("gold", (0.65, 0.3, 0.03), 0.3, 1.0, variation=0.1, grime=0.6)
        cylinder("coin", 0.22, 0.06, (0, 0, 0.03), gold, bevel=0.01, verts=48)
        torus("rim", 0.19, 0.012, (0, 0, 0.06), gold)
        box("mark", (0.05, 0.16, 0.02), (0, 0, 0.065), gold, bevel=0.01)

    return {"item_trash": trash, "item_waste_paper": paper, "item_waste_aluminium": aluminium,
            "item_waste_copper": copper, "item_waste_plastic": plastic, "item_waste_glass": glass, "coin": coin}


def render_items():
    out = ART / "icons"
    out.mkdir(parents=True, exist_ok=True)
    for name, build in item_models().items():
        icon_scene()
        build()
        render(TMP / f"{name}.png")
        img = Image.open(TMP / f"{name}.png").convert("RGBA")
        # Fill the icon: crop to the object, centre it on a square with a small margin.
        img = img.crop(img.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox())
        side = int(max(img.size) * 1.08)
        square = Image.new("RGBA", (side, side))
        square.paste(img, ((side - img.width) // 2, (side - img.height) // 2))
        square.resize((64, 64), Image.LANCZOS).save(out / f"{name}.png", optimize=True)
        print("icon", name)


if __name__ == "__main__":
    args = sys.argv[1:] or ["garage", "character", "items"]
    TMP.mkdir(parents=True, exist_ok=True)
    if "garage" in args:
        render_garage()
    if "character" in args:
        render_character()
    if "items" in args:
        render_items()
