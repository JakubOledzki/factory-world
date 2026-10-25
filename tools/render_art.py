#!/usr/bin/env python3
"""Renders the game's art with Blender (Cycles) into client/art/.

Every model is built from code here, like a tiny procedural 3D studio, so the whole look
can be tweaked and re-rendered at once. Sprites are seen from above at 45°, in the style of
pre-rendered 3D games.

Needs the Blender Python module and Pillow:
    uv venv -p 3.13 .venv-art && VIRTUAL_ENV=.venv-art uv pip install bpy==5.2.2 pillow
    .venv-art/bin/python tools/render_art.py [garage] [character] [items] [furniture_<kind>...]
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

def vignette(img: Image.Image, strength=0.55) -> Image.Image:
    w, h = img.size
    mask = Image.new("L", (w, h), 0)
    px = mask.load()
    for y in range(0, h, 4):
        for x in range(0, w, 4):
            dx, dy = (x - w * 0.5) / (w * 0.6), (y - h * 0.5) / (h * 0.65)
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
# Where on screen the room's centre sits.
ROOM_SCREEN_X = 640

PLAYER_AT = Vector((4.0, 2.6, 0))

# Furniture the player can move: centres (metres) of the starter layout (the server's
# GarageLayout, in 0.5 m cells). Each one is rendered alone at that spot, so the lighting matches
# the room it starts in, turned by 0-3 quarter turns anticlockwise.
FURNITURE_AT = {
    "furniture_trash_bin": (3.0, 4.5),
    "furniture_workbench": (6.25, 5.5),
    "furniture_gas_cylinder": (4.75, 5.75),
    "furniture_shelf": (1.5, 2.75),
    "furniture_barrel_blue": (7.75, 2.75),
    "furniture_barrel_red": (7.75, 1.75),
    "furniture_tyres": (6.5, 1.0),
    "furniture_pallet": (1.5, 1.0),
    # Not in the starter layout: rendered on free floor in the middle of the room.
    "furniture_sorting_machine": (3.75, 2.0),
    "furniture_furnace": (5.0, 2.5),
    "furniture_anvil": (5.0, 2.25),
    "furniture_wardrobe": (5.75, 3.25),
}
ROTATIONS = 4


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


def build_room(coll_room):
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

    # Pegboard with tools on the wall.
    steel = rusty_metal("steel_wall", (0.18, 0.18, 0.19), 0.3)
    board = plain("pegboard", (0.12, 0.09, 0.06), 0.9)
    box("pegboard", (1.0, 0.03, 0.6), (5.25, ROOM_D - 0.02, 1.55), board, coll_room)
    for i in range(5):
        box("tool", (0.04, 0.03, 0.25 + 0.1 * random.random()), (4.9 + i * 0.18, ROOM_D - 0.05, 1.55), steel, coll_room,
            rotation=(0, random.uniform(-0.2, 0.2), 0))

    # Scattered paper and a cable on the floor.
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

    # Pipes along the back wall, a fuse box.
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


def garage_lights():
    """Bare bulb hanging from the ceiling, cold light from the window and the open front."""
    lights = [light("POINT", (4.0, 3.4, 2.6), 220, (1.0, 0.72, 0.42), size=0.08),
              light("AREA", (6.3, ROOM_D - 0.4, 1.9), 25, (0.55, 0.7, 1.0), size=0.8, rotation=(math.radians(-70), 0, 0)),
              light("AREA", (4.0, 3.0, 8.0), 30, (0.5, 0.6, 0.8), size=10),
              # Faint cold fill from the open front, so the faces turned to the camera are not black.
              light("AREA", (4.0, -4.0, 3.0), 120, (0.55, 0.62, 0.8), size=6, rotation=(math.radians(60), 0, 0))]
    return lights


# Each builder makes one piece of furniture standing on the floor around `at`.

def build_workbench(coll, at: Vector):
    """Workbench with a vice, a toolbox and junk on top."""
    wood_m = wood()
    steel = rusty_metal("steel", (0.18, 0.18, 0.19), 0.3)
    box("bench_top", (2.4, 0.8, 0.08), at + Vector((0, 0, 0.9)), wood_m, coll, bevel=0.01)
    for x in (-1.1, 1.1):
        for y in (-0.33, 0.33):
            box("bench_leg", (0.08, 0.08, 0.86), at + Vector((x, y, 0.43)), steel, coll, bevel=0.005)
    box("bench_shelf", (2.3, 0.7, 0.04), at + Vector((0, 0, 0.25)), wood_m, coll)
    red = rusty_metal("toolbox", (0.35, 0.04, 0.03), 0.3)
    box("toolbox", (0.55, 0.26, 0.24), at + Vector((0.6, 0.05, 1.06)), red, coll, bevel=0.02)
    box("toolbox_lid", (0.57, 0.27, 0.04), at + Vector((0.6, 0.05, 1.19)), red, coll, bevel=0.01)
    box("vice", (0.2, 0.25, 0.16), at + Vector((-0.8, -0.25, 1.02)), steel, coll, bevel=0.02)
    cylinder("can", 0.06, 0.16, at + Vector((-0.2, 0.2, 1.02)), plain("can", (0.4, 0.3, 0.05), 0.4, 0.5), coll)
    cylinder("can2", 0.05, 0.12, at + Vector((-0.05, -0.05, 1.0)), plain("can2", (0.1, 0.15, 0.3), 0.4, 0.5), coll)
    for i in range(4):
        box("part", (0.08 + random.random() * 0.1, 0.06, 0.03), at + Vector((-0.5 + random.random() * 0.4, -0.15 + random.random() * 0.2, 0.96)),
            steel, coll, rotation=(0, 0, random.random() * 3))
    # A box of scrap on the lower shelf.
    box("bench_crate", (0.5, 0.4, 0.22), at + Vector((-0.6, 0, 0.38)), plain("cardboard", (0.28, 0.18, 0.09), 0.85, variation=0.25), coll, bevel=0.01)


def build_shelf(coll, at: Vector):
    """Steel shelving with cardboard boxes, open towards the camera."""
    shelf_m = rusty_metal("shelf", (0.15, 0.16, 0.17), 0.4)
    cardboard = plain("cardboard", (0.28, 0.18, 0.09), 0.85, variation=0.25)
    for z in (0.05, 0.6, 1.15, 1.7):
        box("shelf_board", (2.0, 0.5, 0.04), at + Vector((0, 0, z)), shelf_m, coll)
    for x in (-0.97, 0.97):
        for y in (-0.23, 0.23):
            box("shelf_post", (0.05, 0.05, 1.8), at + Vector((x, y, 0.9)), shelf_m, coll)
    for z in (0.07, 0.62, 1.17):
        x = -0.92
        while x < 0.75:
            w = random.uniform(0.3, 0.5)
            h = random.uniform(0.2, 0.42)
            if random.random() < 0.8:
                box("box", (w * 0.9, 0.4, h), at + Vector((x + w / 2, 0.02, z + h / 2)), cardboard, coll, bevel=0.01,
                    rotation=(0, 0, random.uniform(-0.08, 0.08)))
            x += w


def build_barrel(coll, at: Vector, color):
    m = rusty_metal(f"barrel{color}", color, 0.5)
    cylinder("barrel", 0.235, 0.85, at + Vector((0, 0, 0.425)), m, coll, bevel=0.01)
    for z in (0.28, 0.57):
        torus("rib", 0.235, 0.013, at + Vector((0, 0, z)), m, coll)
    cylinder("lid", 0.21, 0.01, at + Vector((0, 0, 0.855)), m, coll)
    cylinder("cap", 0.035, 0.02, at + Vector((0.1, -0.07, 0.865)), m, coll)


def build_tyres(coll, at: Vector):
    rubber = plain("rubber", (0.025, 0.025, 0.025), 0.75, variation=0.3, scale=30, bump=0.5)
    for i in range(3):
        torus("tyre", 0.26, 0.11, at + Vector((0.01 * i, -0.01 * i, 0.11 + i * 0.22)), rubber, coll)
    rim = rusty_metal("rim", (0.2, 0.2, 0.21), 0.4)
    cylinder("rim", 0.17, 0.12, at + Vector((0.02, -0.02, 0.6)), rim, coll)


def build_pallet(coll, at: Vector):
    pallet_m = wood("pallet", (0.2, 0.13, 0.07))
    for i in range(6):
        box("pallet_board", (0.98, 0.12, 0.03), at + Vector((0, -0.4 + i * 0.16, 0.13)), pallet_m, coll, bevel=0.005)
    for x in (-0.44, 0, 0.44):
        box("pallet_block", (0.1, 0.94, 0.1), at + Vector((x, 0, 0.05)), pallet_m, coll)
    cardboard = plain("cardboard_p", (0.28, 0.18, 0.09), 0.85, variation=0.25)
    box("pallet_box", (0.5, 0.4, 0.35), at + Vector((-0.25, 0.1, 0.32)), cardboard, coll, bevel=0.01, rotation=(0, 0, 0.1))
    box("pallet_box2", (0.35, 0.3, 0.25), at + Vector((0.22, -0.15, 0.27)), cardboard, coll, bevel=0.01, rotation=(0, 0, -0.2))


def build_wardrobe(coll, at: Vector):
    """A tall wooden wardrobe for sets of clothes: two doors and a drawer at the bottom, a coat
    hanging on a hook at its side."""
    oak = wood("wardrobe", (0.3, 0.17, 0.08))
    dark = wood("wardrobe_trim", (0.17, 0.09, 0.04))
    brass = plain("wardrobe_brass", (0.55, 0.38, 0.12), 0.35, metallic=1.0, variation=0.1, grime=0.3)
    w, d, h = 1.3, 0.46, 1.95
    box("wardrobe_body", (w, d, h), at + Vector((0, 0, h / 2 + 0.06)), oak, coll, bevel=0.01)
    box("wardrobe_crown", (w + 0.06, d + 0.05, 0.06), at + Vector((0, 0, h + 0.09)), dark, coll, bevel=0.01)
    box("wardrobe_plinth", (w - 0.04, d - 0.04, 0.06), at + Vector((0, 0, 0.03)), dark, coll)
    front = -d / 2 - 0.008
    for x in (-w / 4, w / 4):
        box("wardrobe_door", (w / 2 - 0.05, 0.016, h - 0.42), at + Vector((x, front, 0.42 + (h - 0.42) / 2 + 0.04)), oak, coll, bevel=0.006)
        box("wardrobe_panel", (w / 2 - 0.2, 0.012, h - 0.75), at + Vector((x, front - 0.008, 0.6 + (h - 0.75) / 2)), dark, coll, bevel=0.004)
        cylinder("wardrobe_knob", 0.018, 0.04, at + Vector((x * 0.12, front - 0.03, 1.1)), brass, coll, rotation=(math.pi / 2, 0, 0))
    box("wardrobe_drawer", (w - 0.08, 0.016, 0.26), at + Vector((0, front, 0.23)), oak, coll, bevel=0.006)
    box("wardrobe_pull", (0.22, 0.03, 0.025), at + Vector((0, front - 0.025, 0.25)), brass, coll, bevel=0.006)
    # A coat on a hook at the side.
    coat = plain("wardrobe_coat", (0.05, 0.08, 0.12), 0.9, variation=0.25, grime=0.4)
    cylinder("wardrobe_hook", 0.012, 0.08, at + Vector((w / 2 + 0.04, -0.05, 1.75)), brass, coll, rotation=(0, math.pi / 2, 0))
    box("wardrobe_coat", (0.08, 0.36, 0.85), at + Vector((w / 2 + 0.06, -0.05, 1.3)), coat, coll, bevel=0.03)


def build_gas(coll, at: Vector):
    gas = rusty_metal("gas", (0.35, 0.05, 0.03), 0.3)
    steel = rusty_metal("gas_valve", (0.18, 0.18, 0.19), 0.3)
    cylinder("gas", 0.14, 0.6, at + Vector((0, 0, 0.3)), gas, coll, bevel=0.01)
    sphere("gas_top", 0.14, at + Vector((0, 0, 0.6)), gas, coll, scale=(1, 1, 0.6))
    cylinder("gas_valve", 0.03, 0.12, at + Vector((0, 0, 0.72)), steel, coll)


def build_bin(coll, at: Vector):
    """A big wheelie bin with its lid thrown open and bags of trash inside."""
    green = plain("bin", (0.035, 0.11, 0.05), 0.5, variation=0.25, grime=0.85, bump=0.2)
    lid_m = plain("bin_lid", (0.03, 0.09, 0.04), 0.45, variation=0.2, grime=0.7)
    rubber = plain("wheel", (0.02, 0.02, 0.02), 0.8)
    steel = rusty_metal("bin_axle", (0.2, 0.2, 0.2), 0.4)
    bag_m = plain("bag", (0.012, 0.012, 0.014), 0.25, variation=0.5, scale=4, bump=0.6)
    w0, d0, w1, d1, h = 0.27, 0.26, 0.33, 0.32, 1.0
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
    for z in (0.35, 0.72):
        t = z / h
        box("bin_rib", (2 * (w0 + (w1 - w0) * t) + 0.04, 2 * (d0 + (d1 - d0) * t) + 0.04, 0.04),
            at + Vector((0, 0, z)), green, coll, bevel=0.015)
    box("bin_rim", (2 * w1 + 0.06, 2 * d1 + 0.06, 0.05), at + Vector((0, 0, h)), lid_m, coll, bevel=0.015)
    # The lid hangs open behind the bin.
    box("bin_lid", (2 * w1 + 0.08, 0.05, 2 * d1 + 0.08), at + Vector((0, d1 + 0.07, h - d1 + 0.02)), lid_m, coll,
        bevel=0.02, rotation=(math.radians(-8), 0, 0))
    box("bin_handle", (0.5, 0.05, 0.05), at + Vector((0, d1 + 0.12, h - 0.05)), steel, coll, bevel=0.015)
    # Recycling sticker on the front.
    box("bin_sticker", (0.3, 0.01, 0.22), at + Vector((0, -d1 + 0.04, 0.68)), plain("sticker", (0.75, 0.55, 0.05), 0.5, grime=0.4),
        coll, rotation=(math.radians(-4), 0, 0))
    box("bin_sticker_mark", (0.12, 0.012, 0.12), at + Vector((0, -d1 + 0.035, 0.68)), plain("mark", (0.02, 0.03, 0.02), 0.5),
        coll, rotation=(math.radians(-4), 0, math.radians(45)))
    for x in (-0.23, 0.23):
        cylinder("bin_wheel", 0.1, 0.07, at + Vector((x, d0 + 0.05, 0.1)), rubber, coll, rotation=(0, math.pi / 2, 0))
    cylinder("bin_axle", 0.02, 0.55, at + Vector((0, d0 + 0.05, 0.1)), steel, coll, rotation=(0, math.pi / 2, 0))
    # Bags inside, poking out of the top.
    for (dx, dy, r) in ((-0.11, -0.07, 0.18), (0.13, 0.05, 0.17), (0.0, 0.11, 0.15)):
        displace(sphere("bin_trash", r, at + Vector((dx, dy, h - 0.05)), bag_m, coll, scale=(1, 1, 0.8)), 0.06, 0.15)


def build_sorting_machine(coll, at: Vector):
    """A boxy automatic sorter: a hopper on top, a conveyor coming out on the right and a control
    panel with lamps on the front."""
    body_m = rusty_metal("machine", (0.45, 0.32, 0.03), 0.35)
    steel = rusty_metal("machine_steel", (0.18, 0.18, 0.19), 0.3)
    rubber = plain("belt", (0.02, 0.02, 0.022), 0.8, variation=0.3, scale=30, bump=0.4)
    panel_m = plain("machine_panel", (0.12, 0.12, 0.13), 0.5, 0.4)
    o = at + Vector((-0.2, 0.05, 0))
    box("machine_body", (1.0, 0.8, 0.85), o + Vector((0, 0, 0.47)), body_m, coll, bevel=0.03)
    box("machine_base", (1.06, 0.86, 0.06), o + Vector((0, 0, 0.03)), steel, coll, bevel=0.01)
    # Hopper: a funnel open at the top, with trash bags in it.
    v = [(-0.3, -0.24, 0), (0.3, -0.24, 0), (0.3, 0.24, 0), (-0.3, 0.24, 0),
         (-0.46, -0.36, 0.38), (0.46, -0.36, 0.38), (0.46, 0.36, 0.38), (-0.46, 0.36, 0.38)]
    f = [(0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
    hopper = mesh_from("machine_hopper", [(x + o.x, y + o.y, z + 0.9) for x, y, z in v], f, steel, coll)
    solid = hopper.modifiers.new("solid", "SOLIDIFY")
    solid.thickness = 0.03
    bag_m = plain("machine_bag", (0.012, 0.012, 0.014), 0.25, variation=0.5, scale=4, bump=0.6)
    displace(sphere("machine_trash", 0.17, o + Vector((0.05, 0.02, 1.12)), bag_m, coll, scale=(1, 1, 0.7)), 0.05, 0.15)
    # Conveyor carrying sorted waste out to the right.
    belt_at = o + Vector((0.78, -0.1, 0.55))
    box("machine_belt", (0.56, 0.36, 0.05), belt_at, rubber, coll, bevel=0.01)
    for dx in (-0.26, 0.26):
        cylinder("machine_roller", 0.04, 0.4, belt_at + Vector((dx, 0, 0)), steel, coll, rotation=(math.pi / 2, 0, 0))
    for dx in (-0.2, 0.22):
        for dy in (-0.15, 0.15):
            box("machine_leg", (0.04, 0.04, 0.53), belt_at + Vector((dx, dy, -0.29)), steel, coll)
    for i, colour in enumerate(((0.5, 0.48, 0.42), (0.6, 0.3, 0.1), (0.3, 0.5, 0.75))):
        box("machine_piece", (0.08, 0.06, 0.04), belt_at + Vector((-0.12 + i * 0.14, -0.04 + 0.04 * i, 0.05)),
            plain(f"machine_piece{i}", colour, 0.4, 0.5), coll, rotation=(0, 0, i))
    # Control panel with lamps, and a vent pipe at the back.
    box("machine_panel", (0.34, 0.04, 0.26), o + Vector((-0.22, -0.42, 0.62)), panel_m, coll, bevel=0.01)
    for i, colour in enumerate(((0.1, 1.0, 0.2), (1.0, 0.6, 0.05), (1.0, 0.1, 0.05))):
        sphere("machine_lamp", 0.022, o + Vector((-0.32 + i * 0.1, -0.445, 0.68)), emission(f"lamp{i}", colour, 6.0), coll)
    box("machine_button", (0.07, 0.03, 0.05), o + Vector((-0.22, -0.445, 0.55)), plain("button", (0.5, 0.03, 0.02), 0.4), coll, bevel=0.01)
    cylinder("machine_vent", 0.07, 0.5, o + Vector((0.32, 0.3, 1.1)), steel, coll)
    box("machine_stripe", (1.01, 0.81, 0.08), o + Vector((0, 0, 0.12)), plain("stripe", (0.05, 0.05, 0.05), 0.6), coll)


def build_furnace(coll, at: Vector, size=1.0):
    """A stone furnace about 0.9 m across: rough blocks laid in courses around a firebox with an
    arched mouth facing the camera, glowing coals inside and a short chimney at the back."""
    s = size
    stone = plain("furnace_stone", (0.2, 0.18, 0.16), 0.9, variation=0.35, scale=8, bump=0.5)
    dark = plain("furnace_soot", (0.02, 0.018, 0.017), 0.95, variation=0.3, bump=0.4)
    rnd = random.Random(11)
    # Four courses of blocks around the firebox, leaving the mouth open at the front.
    courses, block_h = 4, 0.17
    for k in range(courses):
        z = 0.06 + block_h * (k + 0.5)
        inset = 0.02 * k
        for side in range(4):
            count = 3
            for i in range(count):
                t = (i + 0.5) / count - 0.5
                along = t * (0.86 - inset * 2)
                if side == 0 and k < 2 and i == 1:
                    continue  # The mouth.
                pos = {0: (along, -0.42 + inset), 1: (0.42 - inset, along), 2: (-along, 0.42 - inset), 3: (-0.42 + inset, -along)}[side]
                dims = (0.29 + rnd.uniform(-0.03, 0.02), 0.16, block_h - 0.012) if side in (0, 2) else (0.16, 0.29 + rnd.uniform(-0.03, 0.02), block_h - 0.012)
                b = box("furnace_block", tuple(d * s for d in dims), at + Vector((pos[0] * s, pos[1] * s, z * s)), stone, coll, bevel=0.025 * s,
                        rotation=(0, 0, rnd.uniform(-0.04, 0.04)))
                displace(b, 0.012 * s, 0.08, 1)
    # Base slab, soot-blackened floor of the firebox and a lintel over the mouth.
    box("furnace_base", (0.96 * s, 0.96 * s, 0.06 * s), at + Vector((0, 0, 0.03 * s)), stone, coll, bevel=0.01 * s)
    box("furnace_inside", (0.6 * s, 0.6 * s, 0.4 * s), at + Vector((0, 0.02 * s, 0.26 * s)), dark, coll)
    box("furnace_lintel", (0.42 * s, 0.18 * s, 0.09 * s), at + Vector((0, -0.42 * s, 0.43 * s)), stone, coll, bevel=0.02 * s)
    # Coals glowing in the mouth.
    ember = emission("furnace_ember", (1.0, 0.32, 0.05), 4.0)
    coal_m = plain("furnace_coal", (0.015, 0.014, 0.014), 0.4, variation=0.5, bump=0.8)
    for i in range(7):
        x, y = rnd.uniform(-0.13, 0.13), rnd.uniform(-0.36, -0.2)
        sphere("furnace_coal", 0.045 * s, at + Vector((x * s, y * s, 0.1 * s)), ember if i % 2 else coal_m, coll, segments=8)
    # A flat top of slabs and a chimney.
    box("furnace_top", (0.82 * s, 0.82 * s, 0.07 * s), at + Vector((0, 0, (0.06 + block_h * courses + 0.035) * s)), stone, coll, bevel=0.02 * s)
    chimney_z = 0.06 + block_h * courses + 0.07
    for k in range(3):
        c = box("furnace_chimney", (0.26 * s, 0.26 * s, 0.11 * s), at + Vector((0.12 * s, 0.18 * s, (chimney_z + 0.055 + 0.115 * k) * s)), stone, coll,
                bevel=0.02 * s, rotation=(0, 0, rnd.uniform(-0.08, 0.08)))
        displace(c, 0.01 * s, 0.08, 1)
    box("furnace_flue", (0.14 * s, 0.14 * s, 0.02 * s), at + Vector((0.12 * s, 0.18 * s, (chimney_z + 0.35) * s)), dark, coll)


def build_anvil(coll, at: Vector, size=1.0):
    """A blacksmith's anvil on an oak stump: a dark steel body with a polished face, a horn to the
    left and a heel to the right, and a hammer leaning on the stump."""
    s = size
    rnd = random.Random(7)
    oak = wood("anvil_oak", (0.13, 0.075, 0.04))
    rings = wood("anvil_rings", (0.3, 0.19, 0.1))
    steel = rusty_metal("anvil_steel", (0.07, 0.07, 0.075), 0.15)
    face = plain("anvil_face", (0.55, 0.56, 0.58), 0.25, 1.0, variation=0.1, grime=0.2)
    stump = cylinder("anvil_stump", 0.23 * s, 0.42 * s, at + Vector((0, 0, 0.21 * s)), oak, coll, verts=20)
    displace(stump, 0.012 * s, 0.2, 1)
    cylinder("anvil_stump_top", 0.215 * s, 0.01 * s, at + Vector((0, 0, 0.42 * s)), rings, coll, verts=20)
    box("anvil_foot", (0.34 * s, 0.22 * s, 0.06 * s), at + Vector((0, 0, 0.455 * s)), steel, coll, bevel=0.012 * s)
    box("anvil_waist", (0.2 * s, 0.13 * s, 0.12 * s), at + Vector((0, 0, 0.545 * s)), steel, coll, bevel=0.01 * s)
    box("anvil_body", (0.44 * s, 0.17 * s, 0.09 * s), at + Vector((0.02 * s, 0, 0.65 * s)), steel, coll, bevel=0.012 * s)
    box("anvil_face", (0.42 * s, 0.15 * s, 0.012 * s), at + Vector((0.02 * s, 0, 0.7 * s)), face, coll, bevel=0.004 * s)
    cylinder("anvil_horn", 0.075 * s, 0.24 * s, at + Vector((-0.31 * s, 0, 0.67 * s)), steel, coll,
             rotation=(0, -math.pi / 2, 0), verts=20, radius2=0.008 * s)
    box("anvil_heel", (0.08 * s, 0.12 * s, 0.07 * s), at + Vector((0.27 * s, 0, 0.66 * s)), steel, coll, bevel=0.01 * s)
    # A hammer leaning on the stump, its head on the floor.
    tilt = math.radians(68)
    handle = wood("anvil_handle", (0.28, 0.17, 0.08))
    hx, hy = 0.3 * s, -0.12 * s
    cylinder("hammer_handle", 0.014 * s, 0.36 * s, at + Vector((hx - 0.03 * s, hy, 0.2 * s)), handle, coll,
             rotation=(0, -(math.pi / 2 - tilt), rnd.uniform(-0.1, 0.1)), verts=10)
    box("hammer_head", (0.06 * s, 0.05 * s, 0.13 * s), at + Vector((hx + 0.04 * s, hy, 0.04 * s)), steel, coll, bevel=0.008 * s)


FURNITURE_BUILDERS = {
    "furniture_furnace": build_furnace,
    "furniture_anvil": build_anvil,
    "furniture_sorting_machine": build_sorting_machine,
    "furniture_trash_bin": build_bin,
    "furniture_workbench": build_workbench,
    "furniture_gas_cylinder": build_gas,
    "furniture_shelf": build_shelf,
    "furniture_barrel_blue": lambda c, at: build_barrel(c, at, (0.05, 0.12, 0.25)),
    "furniture_barrel_red": lambda c, at: build_barrel(c, at, (0.3, 0.07, 0.04)),
    "furniture_tyres": build_tyres,
    "furniture_pallet": build_pallet,
    "furniture_wardrobe": build_wardrobe,
}


def screen_bounds(scene, objs, margin=24) -> tuple[int, int, int, int]:
    """Pixel rectangle (x0, y0, x1, y1) covering the objects' bounding boxes on screen."""
    bpy.context.view_layer.update()
    xs, ys = [], []
    for o in objs:
        for corner in o.bound_box:
            x, y = screen_pos(scene, o.matrix_world @ Vector(corner))
            xs.append(x)
            ys.append(y)
    return (max(0, int(min(xs)) - margin), max(0, int(min(ys)) - margin),
            min(SCREEN_W, int(max(xs)) + margin), min(SCREEN_H, int(max(ys)) + margin))


def render_border(scene, rect, path: Path) -> None:
    """Renders only `rect` of the screen; the rest of the image stays transparent."""
    x0, y0, x1, y1 = rect
    scene.render.use_border = True
    scene.render.use_crop_to_border = False
    scene.render.border_min_x, scene.render.border_max_x = x0 / SCREEN_W, x1 / SCREEN_W
    scene.render.border_min_y, scene.render.border_max_y = 1 - y1 / SCREEN_H, 1 - y0 / SCREEN_H
    render(path)
    scene.render.use_border = False


def icon_from(sprite: Image.Image, out: Path, size=64) -> None:
    """Fills an icon with the object: crops to it and centres it on a square with a small margin."""
    img = sprite.crop(sprite.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox())
    side = int(max(img.size) * 1.08)
    square = Image.new("RGBA", (side, side))
    square.paste(img, ((side - img.width) // 2, (side - img.height) // 2))
    square.resize((size, size), Image.LANCZOS).save(out, optimize=True)


def render_furniture(scene, coll, kind, turn, at, lights, catcher, shadow_sun, out: Path, icons: Path) -> dict:
    """Renders one turn of a piece of furniture and its shadow; returns where the centre of its
    footprint is in the sprite."""
    objs = [o for o in coll.objects if o.type == "MESH"]
    rect = screen_bounds(scene, objs)
    name = f"{kind}_r{turn}"

    # The object itself, lit by the room's lights.
    catcher.hide_render = True
    shadow_sun.hide_render = True
    for lt in lights:
        lt.hide_render = False
    for o in objs:
        o.visible_camera = True
    render_border(scene, rect, TMP / f"{name}.png")

    # Its shadow alone: invisible to the camera but still casting onto the catcher.
    catcher.hide_render = False
    shadow_sun.hide_render = False
    for lt in lights:
        lt.hide_render = True
    for o in objs:
        o.visible_camera = False
    sx0, sy0, sx1, sy1 = rect
    render_border(scene, (max(0, sx0 - 40), max(0, sy0 - 40), min(SCREEN_W, sx1 + 40), min(SCREEN_H, sy1 + 40)),
                  TMP / f"{name}_shadow.png")

    # Same crop for both, so they share an anchor.
    sprite = Image.open(TMP / f"{name}.png").convert("RGBA")
    shadow = Image.open(TMP / f"{name}_shadow.png").convert("RGBA")
    a = sprite.getchannel("A").point(lambda v: 255 if v > 3 else 0).getbbox()
    b = shadow.getchannel("A").point(lambda v: 255 if v > 6 else 0).getbbox() or a
    box_ = (max(0, min(a[0], b[0]) - 2), max(0, min(a[1], b[1]) - 2),
            min(SCREEN_W, max(a[2], b[2]) + 2), min(SCREEN_H, max(a[3], b[3]) + 2))
    sprite.crop(box_).save(out / f"{name}.png", optimize=True)
    shadow.crop(box_).save(out / f"{name}_shadow.png", optimize=True)
    if turn == 0:
        icon_from(sprite, icons / f"{kind}.png")
    fx, fy = screen_pos(scene, at)
    return {"anchorX": round(fx - box_[0]), "anchorY": round(fy - box_[1])}


def render_garage(only=None):
    """The empty room as the background, then every piece of furniture as its own sprite with
    a separate soft shadow, so the game can move it around the floor."""
    scene = reset()
    scene.cycles.samples = 160
    set_world((0.012, 0.014, 0.018), 1.0)
    room = collection("room")
    build_room(room)
    lights = garage_lights()
    garage_camera(scene)

    out = ART / "garage"
    out.mkdir(parents=True, exist_ok=True)
    icons = ART / "icons"
    layout_path = out / "layout.json"
    layout = json.loads(layout_path.read_text()) if only and layout_path.exists() else {"objects": {}}

    if not only:
        scene.render.film_transparent = False
        render(TMP / "garage_full.png")
        vignette(Image.open(TMP / "garage_full.png").convert("RGBA")).convert("RGB").save(out / "background.jpg", quality=92)

    # The room stays out of the furniture renders: it would only block light and catch shadows.
    for obj in room.objects:
        obj.hide_render = True
    scene.render.film_transparent = True
    scene.cycles.samples = 96
    catcher = box("catcher", (40, 40, 0.01), (ROOM_W / 2, ROOM_D / 2, -0.005))
    catcher.is_shadow_catcher = True
    # Shadows come from almost straight above, so they look right wherever the object is moved.
    shadow_sun = light("SUN", (0, 0, 5), 4.0, size=0.35, rotation=(math.radians(10), math.radians(6), 0))

    from mathutils import Matrix
    for kind, (x, y) in FURNITURE_AT.items():
        if only and kind not in only:
            continue
        coll = collection(kind)
        at = Vector((x, y, 0))
        FURNITURE_BUILDERS[kind](coll, at)
        # Everything hangs from a pivot in the middle of the footprint, which turns the piece.
        pivot = bpy.data.objects.new(kind + "_pivot", None)
        pivot.location = at
        link(pivot, coll)
        for o in coll.objects:
            if o is not pivot:
                o.parent = pivot
                o.matrix_parent_inverse = Matrix.Translation(-at)
        anchors = []
        for turn in range(ROTATIONS):
            pivot.rotation_euler = (0, 0, turn * math.pi / 2)
            anchors.append(render_furniture(scene, coll, kind, turn, at, lights, catcher, shadow_sun, out, icons))
        layout["objects"][kind] = anchors
        bpy.data.collections.remove(coll)
        print("furniture", kind, anchors, flush=True)

    # How world metres map to screen pixels: screen = origin + x * axisX + y * axisY + z * axisZ.
    ox, oy = screen_pos(scene, Vector((0, 0, 0)))
    axes = {}
    for name, v in (("axisX", (1, 0, 0)), ("axisY", (0, 1, 0)), ("axisZ", (0, 0, 1))):
        px, py = screen_pos(scene, Vector(v))
        axes[name] = [round(px - ox, 4), round(py - oy, 4)]
    layout["projection"] = {"origin": [round(ox, 2), round(oy, 2)], **axes}
    layout["room"] = {"width": ROOM_W, "depth": ROOM_D}
    layout["player"] = {"x": PLAYER_AT.x, "y": PLAYER_AT.y}
    layout["pixelsPerMetre"] = PPM
    layout_path.write_text(json.dumps(layout, indent=1))
    print("garage", layout)


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
        icon_from(Image.open(TMP / f"{name}.png").convert("RGBA"), out / f"{name}.png")
        print("icon", name)


if __name__ == "__main__":
    args = sys.argv[1:] or ["garage", "character", "items"]
    TMP.mkdir(parents=True, exist_ok=True)
    if "garage" in args:
        render_garage()
    elif kinds := [a for a in args if a.startswith("furniture_")]:
        render_garage(only=kinds)
    if "character" in args:
        # The characters have a script of their own; this keeps the old command working.
        import render_character
        render_character.main(["base", "layers", "icons"])
    if "items" in args:
        render_items()
