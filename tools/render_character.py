#!/usr/bin/env python3
"""Renders the player characters into client/art/character/ with Blender (Cycles).

The body, the clothes and the hair are metaballs: soft shapes that melt into one smooth surface,
hung from a small rig so the character can turn and walk. The game tints grey renders with the
colours picked in the editor (see client/ui/character_tint.gdshader), so one render per hair and
shirt style serves every palette. Faces, beards and the clothes made in town tailor shops are
rendered as separate layers with the body as a holdout: drawn over the body they hide just what
they would hide in 3D.

Needs the Blender Python module and Pillow (see tools/render_art.py):
    .venv-art/bin/python tools/render_character.py [base] [layers] [icons] [preview] [only=<layer>...]
"""
import json
import math
import random
import sys
from pathlib import Path

import render_art as ra  # noqa: I001  (imports bpy first)
import bpy
from mathutils import Euler, Matrix, Vector
from PIL import Image

ART = ra.ART
TMP = ra.TMP
OUT = ART / "character"

HAIR_STYLES = 6
SHIRT_STYLES = 3
FACE_STYLES = 4
# Facial hair: 0 = none, then a moustache, a goatee and a full beard.
BEARD_STYLES = 4

# The editor and the HUD show a portrait from the front; on the plots and in the garage the
# character is seen from above like everything else, in four directions with a two-step walk.
PORTRAIT_RES = (192, 480)
PORTRAIT_WIDTH_M = 0.8
PORTRAIT_PITCH = math.radians(10)
FRAME_RES = (96, 168)
DIRECTIONS = {"down": 0.0, "left": -math.pi / 2, "right": math.pi / 2, "up": math.pi}
POSES = ("idle", "step_a", "step_b")

random.seed(11)


# --- Metaballs ----------------------------------------------------------------------------------

# With the threshold at 0.6 the surface of a lone ball lies at this fraction of its radius.
VISIBLE = 0.575


class Rig:
    """Empties the body parts hang from, so the character can turn and swing its arms and legs."""

    PIVOTS = {"leg_l": (-0.09, 0.01, 0.93), "leg_r": (0.09, 0.01, 0.93),
              "arm_l": (-0.19, 0.0, 1.42), "arm_r": (0.19, 0.0, 1.42), "head": (0.0, 0.0, 1.52)}

    def __init__(self):
        self.root = self._empty("root", Vector((0, 0, 0)), None)
        self.pivots = {"root": self.root}
        for name, at in self.PIVOTS.items():
            self.pivots[name] = self._empty(name, Vector(at), self.root)

    @staticmethod
    def _empty(name, at, parent):
        e = bpy.data.objects.new(name, None)
        e.location = at
        e.parent = parent
        ra.link(e)
        return e

    def attach(self, obj, part="root"):
        """Hangs an object built in world space from a pivot, keeping where it is."""
        pivot = self.pivots[part]
        obj.parent = pivot
        world = pivot.location if pivot is self.root else pivot.location + self.root.location
        obj.matrix_parent_inverse = Matrix.Translation(-world)
        return obj

    def pose(self, direction=0.0, pose="idle", head_tilt=0.0):
        self.root.rotation_euler = (0, 0, direction)
        swing = {"idle": 0.0, "step_a": 1.0, "step_b": -1.0}[pose]
        self.pivots["leg_l"].rotation_euler = (math.radians(18) * swing, 0, 0)
        self.pivots["leg_r"].rotation_euler = (-math.radians(18) * swing, 0, 0)
        self.pivots["arm_l"].rotation_euler = (-math.radians(16) * swing, 0, math.radians(-3))
        self.pivots["arm_r"].rotation_euler = (math.radians(16) * swing, 0, math.radians(3))
        self.pivots["head"].rotation_euler = (head_tilt, 0, 0)


class Blob:
    """Elements of one metaball object hung from a pivot of the rig. Objects whose names start
    with the same family name melt into one surface, so a sleeve on the arm's pivot joins the
    shirt on the body's."""

    def __init__(self, rig, family, mat, part="root", resolution=0.006):
        mb = bpy.data.metaballs.new(family)
        mb.resolution = resolution * 2
        mb.render_resolution = resolution
        mb.threshold = 0.6
        mb.materials.append(mat)
        self.mb = mb
        self.obj = rig.attach(ra.link(bpy.data.objects.new(family, mb)), part)

    def _new(self, kind, at, radius, negative=False, stiffness=2.0):
        e = self.mb.elements.new(type=kind)
        e.co = at
        e.radius = radius / VISIBLE
        e.use_negative = negative
        e.stiffness = stiffness
        return e

    def ball(self, at, r, negative=False, stiffness=2.0):
        self._new("BALL", at, r, negative, stiffness)
        return self

    def ellipsoid(self, at, half, rotation=(0, 0, 0), negative=False, stiffness=2.0):
        biggest = max(half)
        e = self._new("ELLIPSOID", at, biggest, negative, stiffness)
        e.size_x, e.size_y, e.size_z = (h / biggest for h in half)
        e.rotation = Euler(rotation).to_quaternion()
        return self

    def capsule(self, a, b, r, stiffness=2.0):
        """A rounded rod of radius r between two points."""
        a, b = Vector(a), Vector(b)
        e = self._new("CAPSULE", (a + b) / 2, r, stiffness=stiffness)
        e.size_x = (b - a).length / 2
        e.rotation = Vector((1, 0, 0)).rotation_difference(b - a)
        return self


def sides():
    return ((-1, "l"), (1, "r"))


# --- Materials ----------------------------------------------------------------------------------

def tint_mat(name, roughness=0.6, bump=0.1, scale=40.0, sheen=0.0, sss=0.0, lo=0.62, hi=0.75):
    """Light grey base that the game tints with the colour chosen in the editor."""
    m = ra.Mat(name)
    n = m.noise(scale)
    col = m.ramp(n.outputs["Fac"], [(0.3, (lo, lo, lo)), (0.7, (hi, hi, hi))]).outputs["Color"]
    col = m.grime(col, 0.45, 0.06)
    mat = m.done(col, roughness, 0.0, n.outputs["Fac"], bump)
    if sheen:
        ra._input(m.bsdf, "Sheen Weight").default_value = sheen
    if sss:
        ra._input(m.bsdf, "Subsurface Weight").default_value = sss
        ra._input(m.bsdf, "Subsurface Scale").default_value = 0.012
        ra._input(m.bsdf, "Subsurface Radius").default_value = (1.0, 0.35, 0.2)
    return mat


def weave_mat(name, roughness=0.85, scale=260.0, lo=0.6, hi=0.74, strength=0.25):
    """Grey cloth with a fine woven bump, tinted by the game."""
    m = ra.Mat(name)
    n = m.noise(14.0)
    col = m.ramp(n.outputs["Fac"], [(0.3, (lo, lo, lo)), (0.7, (hi, hi, hi))]).outputs["Color"]
    col = m.grime(col, 0.55, 0.05)
    weave = m.node("ShaderNodeTexWave", wave_type="BANDS", bands_direction="DIAGONAL")
    weave.inputs["Scale"].default_value = scale
    weave.inputs["Distortion"].default_value = 1.5
    m.link(m.coord.outputs["Object"], weave.inputs["Vector"])
    mat = m.done(col, roughness, 0.0, weave.outputs["Fac"], strength)
    ra._input(m.bsdf, "Sheen Weight").default_value = 0.35
    return mat


def hair_mat(name="hair", lo=0.55, hi=0.8):
    """Strands running down the head: stretched noise as bump and as light and dark streaks."""
    m = ra.Mat(name)
    mapping = m.node("ShaderNodeMapping")
    m.link(m.coord.outputs["Object"], mapping.inputs["Vector"])
    ra._input(mapping, "Scale").default_value = (90.0, 90.0, 6.0)
    streak = m.node("ShaderNodeTexNoise", Detail=8.0, Roughness=0.7)
    streak.inputs["Scale"].default_value = 1.0
    m.link(mapping.outputs["Vector"], streak.inputs["Vector"])
    col = m.ramp(streak.outputs["Fac"], [(0.35, (lo, lo, lo)), (0.65, (hi, hi, hi))]).outputs["Color"]
    col = m.grime(col, 0.6, 0.04)
    mat = m.done(col, 0.5, 0.0, streak.outputs["Fac"], 0.5)
    return mat


def colour_mat(name, color, roughness=0.7, metallic=0.0, bump=0.15, scale=40.0, sheen=0.0, variation=0.12):
    """A material of its own colour for the clothes from the tailor's, which the game draws as they are."""
    m = ra.Mat(name)
    n = m.noise(scale)
    lo = tuple(c * (1 - variation) for c in color)
    hi = tuple(min(1.0, c * (1 + variation)) for c in color)
    col = m.ramp(n.outputs["Fac"], [(0.3, lo), (0.7, hi)]).outputs["Color"]
    col = m.grime(col, 0.5, 0.05)
    mat = m.done(col, roughness, metallic, n.outputs["Fac"], bump)
    if sheen:
        ra._input(m.bsdf, "Sheen Weight").default_value = sheen
    return mat


def cloth_mat(name, color, scale=260.0, roughness=0.85, strength=0.3):
    """Woven cloth of its own colour."""
    m = ra.Mat(name)
    n = m.noise(10.0)
    lo = tuple(c * 0.85 for c in color)
    col = m.ramp(n.outputs["Fac"], [(0.3, lo), (0.7, color)]).outputs["Color"]
    col = m.grime(col, 0.55, 0.05)
    weave = m.node("ShaderNodeTexWave", wave_type="BANDS", bands_direction="DIAGONAL")
    weave.inputs["Scale"].default_value = scale
    m.link(m.coord.outputs["Object"], weave.inputs["Vector"])
    mat = m.done(col, roughness, 0.0, weave.outputs["Fac"], strength)
    ra._input(m.bsdf, "Sheen Weight").default_value = 0.3
    return mat


def check_mat(name, a, b, scale=14.0):
    """Flannel: a check of two colours with darker crossings, fuzzy."""
    m = ra.Mat(name)
    sep = m.node("ShaderNodeSeparateXYZ")
    m.link(m.coord.outputs["Object"], sep.inputs["Vector"])
    stripes = []
    for axis in ("X", "Z"):
        mul = m.node("ShaderNodeMath", operation="MULTIPLY")
        m.link(sep.outputs[axis], mul.inputs[0])
        mul.inputs[1].default_value = scale
        frac = m.node("ShaderNodeMath", operation="FRACT")
        m.link(mul.outputs[0], frac.inputs[0])
        step = m.node("ShaderNodeMath", operation="GREATER_THAN")
        m.link(frac.outputs[0], step.inputs[0])
        step.inputs[1].default_value = 0.5
        stripes.append(step)
    both = m.node("ShaderNodeMath", operation="MULTIPLY")
    m.link(stripes[0].outputs[0], both.inputs[0])
    m.link(stripes[1].outputs[0], both.inputs[1])
    either = m.node("ShaderNodeMath", operation="MAXIMUM")
    m.link(stripes[0].outputs[0], either.inputs[0])
    m.link(stripes[1].outputs[0], either.inputs[1])
    base = m.mix(either.outputs[0], a, b)
    dark = tuple(c * 0.45 for c in b)
    col = m.mix(both.outputs[0], base, dark)
    col = m.grime(col, 0.55, 0.05)
    fuzz = m.noise(300.0)
    mat = m.done(col, 0.9, 0.0, fuzz.outputs["Fac"], 0.25)
    ra._input(m.bsdf, "Sheen Weight").default_value = 0.15
    return mat


def straw_mat(name="straw"):
    m = ra.Mat(name)
    weave = m.node("ShaderNodeTexWave", wave_type="RINGS", rings_direction="Z")
    weave.inputs["Scale"].default_value = 60.0
    weave.inputs["Distortion"].default_value = 2.0
    m.link(m.coord.outputs["Object"], weave.inputs["Vector"])
    col = m.ramp(weave.outputs["Fac"], [(0.2, (0.42, 0.3, 0.12)), (0.8, (0.72, 0.58, 0.3))]).outputs["Color"]
    col = m.grime(col, 0.5, 0.05)
    return m.done(col, 0.8, 0.0, weave.outputs["Fac"], 0.5)


def emission(name, color, strength=1.0):
    return ra.emission(name, color, strength)


# --- The body -----------------------------------------------------------------------------------

def inflate(half, d):
    return tuple(h + d for h in half)


class Body:
    """The character's shapes in metres, standing at the origin facing the camera (-Y), 1.78 m
    tall. Clothes reuse them a bit bigger, so they follow the body."""

    HEAD = Vector((0, 0.008, 1.655))

    def __init__(self, rig):
        self.rig = rig

    def torso(self, blob, d=0.0, chest=True, waist=True, pelvis=True, shoulders=True, hem=None):
        if chest:
            blob.ellipsoid((0, 0.008, 1.33), inflate((0.138, 0.088, 0.14), d))
            blob.ellipsoid((0, -0.012, 1.385), inflate((0.112, 0.07, 0.07), d))
        if waist:
            blob.ellipsoid((0, 0.012, 1.17), inflate((0.118, 0.078, 0.12), d))
        if pelvis:
            blob.ellipsoid((0, 0.016, 0.99), inflate((0.135, 0.088, 0.1), d))
        if hem is not None:
            blob.ellipsoid((0, 0.014, hem), inflate((0.128, 0.086, 0.05), d))
        if shoulders:
            for s, _ in sides():
                blob.ball((s * 0.155, 0.004, 1.412), 0.046 + d)
        return blob

    def neck(self, blob, d=0.0):
        return blob.capsule((0, 0.012, 1.44), (0, 0.006, 1.535), 0.04 + d)

    def collar(self, blob, d=0.0):
        return blob.capsule((0, 0.012, 1.43), (0, 0.01, 1.468), 0.05 + d)

    def head(self, blob):
        h = self.HEAD
        blob.ellipsoid(h, (0.079, 0.095, 0.102))                                       # skull
        blob.ellipsoid(h + Vector((0, -0.028, -0.062)), (0.064, 0.066, 0.07))            # face and jaw
        blob.ball(h + Vector((0, -0.072, -0.106)), 0.025)                               # chin
        for s, _ in sides():
            blob.ball(h + Vector((s * 0.042, -0.062, -0.033)), 0.028)                   # cheekbones
            blob.ellipsoid(h + Vector((s * 0.074, 0.006, -0.026)), (0.012, 0.021, 0.027), (0, s * 0.12, 0))  # ears
            blob.ball(h + Vector((s * 0.031, -0.095, -0.002)), 0.0125, negative=True)  # eye sockets
        blob.ellipsoid(h + Vector((0, -0.09, -0.022)), (0.01, 0.018, 0.026), (math.radians(-18), 0, 0))  # bridge of the nose
        blob.ball(h + Vector((0, -0.102, -0.042)), 0.0115)                              # tip of the nose
        for s, _ in sides():
            blob.ball(h + Vector((s * 0.011, -0.095, -0.046)), 0.0085)                  # nostrils
        return blob

    def arm(self, blob, s, d=0.0, upper=True, lower=True, hand=True, upper_to=1.0):
        shoulder = Vector((s * 0.18, 0.004, 1.395))
        elbow = Vector((s * 0.205, 0.012, 1.148))
        wrist = Vector((s * 0.218, -0.012, 0.9))
        if upper:
            blob.capsule(shoulder, shoulder.lerp(elbow, upper_to), 0.036 + d)
            blob.ellipsoid(shoulder.lerp(elbow, 0.35 * upper_to), inflate((0.038, 0.04, 0.07), d))  # biceps
        if lower:
            blob.capsule(elbow, wrist, 0.029 + d)
            blob.ellipsoid(elbow.lerp(wrist, 0.25), inflate((0.034, 0.034, 0.07), d))
        if hand:
            blob.ellipsoid(wrist + Vector((0, -0.006, -0.068)), (0.02, 0.041, 0.056), (0, 0, s * 0.15))
            blob.capsule(wrist + Vector((s * -0.008, -0.034, -0.03)), wrist + Vector((s * -0.012, -0.05, -0.062)), 0.011)  # thumb
        return blob

    def leg(self, blob, s, d=0.0, thigh=True, calf=True, ankle=True, calf_to=1.0):
        hip = Vector((s * 0.088, 0.012, 0.93))
        knee = Vector((s * 0.096, 0.004, 0.52))
        ankle_at = Vector((s * 0.098, 0.016, 0.1))
        if thigh:
            blob.capsule(hip, knee, 0.054 + d)
            blob.ellipsoid(hip.lerp(knee, 0.28), inflate((0.06, 0.062, 0.12), d))
            blob.ball(knee + Vector((0, -0.008, 0)), 0.04 + d)
        if calf:
            blob.capsule(knee, knee.lerp(ankle_at, calf_to), 0.036 + d)
            blob.ellipsoid(knee.lerp(ankle_at, 0.3) + Vector((0, 0.012, 0)), inflate((0.04, 0.043, 0.09), d))
        if ankle:
            blob.ball(ankle_at, 0.033 + d)
        return blob

    def foot(self, blob, s, d=0.0, height=1.0):
        at = Vector((s * 0.098, -0.034, 0.042 * height))
        blob.ellipsoid(at, (0.046 + d, 0.118 + d, 0.042 * height + d))
        blob.ball(Vector((s * 0.098, 0.03, 0.06)), 0.045 + d)
        return blob


def build_base(rig):
    """The body every style shares and the parts that differ: shirts and hair styles.
    Returns ({layer: [objects]}, shirts by style, hairs by style)."""
    body = Body(rig)
    skin = tint_mat("skin", 0.48, 0.03, 70, sss=0.25, lo=0.66, hi=0.74)
    shirt_m = weave_mat("cotton")
    hoodie_m = weave_mat("fleece", 0.95, 140, strength=0.15)
    denim = weave_mat("denim", 0.8, 300, lo=0.58, hi=0.72, strength=0.4)
    shoe_m = tint_mat("leather", 0.38, 0.12, 30)
    sole = ra.plain("sole", (0.03, 0.028, 0.026), 0.6, variation=0.1, grime=0.3)
    belt = ra.plain("belt", (0.035, 0.025, 0.02), 0.45, grime=0.3)
    buckle = ra.plain("buckle", (0.6, 0.55, 0.42), 0.25, 1.0, grime=0.2)
    hair_m = hair_mat()
    a = rig.attach

    L = {"skin": [], "pants": [], "shoes": [], "detail": []}
    trunk = Blob(rig, "Skin", skin)
    body.torso(trunk)
    body.neck(trunk)
    L["skin"].append(trunk.obj)
    L["skin"].append(body.head(Blob(rig, "Skin", skin, "head")).obj)
    for s, side in sides():
        L["skin"].append(body.arm(Blob(rig, "Skin", skin, "arm_" + side), s).obj)
        L["skin"].append(body.leg(Blob(rig, "Skin", skin, "leg_" + side), s).obj)

    # Jeans from the waist down, with a belt and the hems over the shoes.
    hips = Blob(rig, "Jeans", denim)
    hips.ellipsoid((0, 0.016, 1.0), (0.143, 0.096, 0.105))
    L["pants"].append(hips.obj)
    for s, side in sides():
        leg = body.leg(Blob(rig, "Jeans", denim, "leg_" + side), s, d=0.009, ankle=False, calf_to=0.97)
        leg.ball(Vector((s * 0.098, 0.014, 0.115)), 0.044)
        L["pants"].append(leg.obj)
        shoe = body.foot(Blob(rig, "Shoe", shoe_m, "leg_" + side), s, d=0.008)
        L["shoes"].append(shoe.obj)
        L["detail"].append(a(ra.box("sole", (0.11, 0.26, 0.022), (s * 0.098, -0.03, 0.011), sole, bevel=0.008), "leg_" + side))
    ring = ra.cylinder("belt", 1.0, 0.034, (0, 0.016, 1.045), belt, verts=40)
    ring.scale = (0.168, 0.113, 1)
    L["detail"].append(a(ring))
    L["detail"].append(a(ra.box("buckle", (0.044, 0.012, 0.03), (0, -0.098, 1.045), buckle, bevel=0.004)))

    shirts = []
    for style in range(SHIRT_STYLES):
        family = f"Shirt{style}"
        mat = hoodie_m if style == 2 else shirt_m
        d = 0.016 if style == 2 else 0.008
        trunk = body.torso(Blob(rig, family, mat), d, pelvis=False, shoulders=style != 1, hem=1.08 if style != 2 else 1.03)
        if style != 1:
            body.collar(trunk, d * 0.5)
        objs = [trunk.obj]
        for s, side in sides():
            arm = Blob(rig, family, mat, "arm_" + side)
            if style == 0:
                body.arm(arm, s, d, lower=False, hand=False, upper_to=0.48)
            elif style == 1:
                trunk.capsule((s * 0.095, -0.07, 1.445), (s * 0.095, 0.07, 1.445), 0.018)
            else:
                body.arm(arm, s, d, hand=False)
                arm.ball(Vector((s * 0.218, -0.012, 0.915)), 0.038)
            objs.append(arm.obj)
        if style == 2:
            trunk.ellipsoid((0, 0.075, 1.49), (0.115, 0.06, 0.065))   # hood
            objs.append(a(ra.box("pocket", (0.19, 0.02, 0.09), (0, -0.092, 1.13), mat, bevel=0.012)))
            cord = ra.plain("cord", (0.7, 0.7, 0.68), 0.6)
            for s, _ in sides():
                objs.append(a(ra.cylinder("cord", 0.005, 0.12, (s * 0.03, -0.102, 1.38), cord)))
        shirts.append(objs)

    def cut(blob):
        # The hairline: the face and the neck stay bare, the ears too.
        h = Body.HEAD
        blob.ellipsoid(h + Vector((0, -0.085, -0.05)), (0.096, 0.072, 0.094), negative=True)
        for s, _ in sides():
            blob.ball(h + Vector((s * 0.085, 0.0, -0.035)), 0.03, negative=True)
        return blob

    hairs = [[]]
    h = Body.HEAD
    for style in range(1, HAIR_STYLES):
        family = f"Hair{style}"
        hair = Blob(rig, family, hair_m, "head", resolution=0.004)
        objs = [hair.obj]
        thick = 0.006 if style in (1, 2) else 0.012
        hair.ellipsoid(h + Vector((0, 0.006, 0.016)), (0.08 + thick, 0.098 + thick, 0.096 + thick))
        hair.ellipsoid(h + Vector((0, 0.04, -0.04)), (0.072 + thick, 0.07, 0.07))   # back of the head
        if style == 2:  # Spiky: tufts standing up, combed to the front.
            for i in range(11):
                ang = i / 11 * 2 * math.pi
                base = h + Vector((math.cos(ang) * 0.05, math.sin(ang) * 0.06 + 0.005, 0.085))
                tip = base + Vector((math.cos(ang) * 0.02, math.sin(ang) * 0.02 - 0.012, 0.045))
                hair.capsule(base, tip, 0.016, stiffness=3.0)
        elif style == 3:  # Long: down to the shoulders, a parting and locks at the sides.
            hair.ellipsoid(h + Vector((0, 0.06, -0.14)), (0.09, 0.05, 0.13))
            for s, _ in sides():
                hair.ellipsoid(h + Vector((s * 0.078, 0.004, -0.1)), (0.022, 0.05, 0.1), (0.1, 0, 0))
        elif style == 4:  # Ponytail.
            hair.ball(h + Vector((0, 0.1, 0.0)), 0.026)
            hair.capsule(h + Vector((0, 0.118, -0.01)), h + Vector((0, 0.14, -0.15)), 0.024)
            hair.ball(h + Vector((0, 0.135, -0.19)), 0.014)
        elif style == 5:  # Curly: curls all over, a big rounded volume.
            for _ in range(46):
                ang, b = random.random() * 2 * math.pi, random.uniform(0.0, 1.55)
                d = Vector((math.cos(ang) * math.sin(b) * 0.098, math.sin(ang) * math.sin(b) * 0.112 + 0.012, math.cos(b) * 0.112))
                if d.y < -0.06 and d.z < 0.04:
                    continue
                hair.ball(h + d, random.uniform(0.022, 0.03), stiffness=2.5)
        if style == 1:  # Short: a quiff brushed up and to the side.
            hair.ellipsoid(h + Vector((0.012, -0.055, 0.078)), (0.058, 0.04, 0.026), (0.35, 0, -0.15))
        cut(hair)
        hairs.append(objs)
    return L, shirts, hairs


# --- Faces, beards and clothes: layers over the body ---------------------------------------------

# Rows of each face style: eyes (spacing, size, lids), brows (thickness, arch, tilt, height) and
# the mouth (width, lips, smile). 0 = even, 1 = strong, 2 = soft, 3 = weathered.
FACES = [
    {"eye": (0.031, 1.0, 0.0), "brow": (0.006, 0.004, 0.0, 0.0), "mouth": (0.022, 0.006, 0.002)},
    {"eye": (0.032, 0.9, 0.25), "brow": (0.009, 0.0, 0.08, -0.004), "mouth": (0.026, 0.005, -0.001)},
    {"eye": (0.03, 1.12, -0.1), "brow": (0.005, 0.008, -0.06, 0.003), "mouth": (0.019, 0.008, 0.005)},
    {"eye": (0.032, 0.88, 0.4), "brow": (0.01, 0.002, 0.12, -0.006), "mouth": (0.024, 0.004, -0.003)},
]


def build_face(rig, style, mats):
    """Eyes, brows and lips of a face style. Returns {layer: [objects]}."""
    f = FACES[style]
    h = Body.HEAD
    a = rig.attach
    L = {"skin": [], "eyes": [], "hair": [], "detail": []}
    spacing, size, lids = f["eye"]
    for s, _ in sides():
        eye = h + Vector((s * spacing, -0.084, -0.002))
        r = 0.0112 * size
        L["detail"].append(a(ra.sphere("eye", r, eye, mats["white"], segments=24), "head"))
        L["eyes"].append(a(ra.sphere("iris", r * 0.66, eye + Vector((0, -r * 0.76, 0)), mats["iris"],
                                     scale=(1, 0.45, 1), segments=20), "head"))
        L["detail"].append(a(ra.sphere("pupil", r * 0.26, eye + Vector((0, -r * 1.03, 0)), mats["pupil"],
                                       scale=(1, 0.4, 1), segments=16), "head"))
        # Lids: skin shells over the top and the bottom of the eye, the upper one lower with heavier lids.
        upper = ra.sphere("lid", r * 1.14, eye, mats["lid"], segments=24,
                          keep=lambda co, lids=lids, r=r: co.z > r * (0.12 - lids * 0.4))
        upper.modifiers["solid"].thickness = 0.0016
        upper.rotation_euler = (math.radians(-14), 0, 0)
        lower = ra.sphere("lid", r * 1.1, eye, mats["lid"], segments=24, keep=lambda co, r=r: co.z < -r * 0.5)
        lower.modifiers["solid"].thickness = 0.0014
        L["skin"] += [a(upper, "head"), a(lower, "head")]
        brow_t, arch, tilt, lift = f["brow"]
        brow = Blob(rig, f"Brow{style}", mats["brow"], "head", resolution=0.0025)
        inner = h + Vector((s * (spacing - 0.017), -0.093, 0.023 + lift - tilt * 0.06))
        top = h + Vector((s * (spacing + 0.002), -0.094, 0.029 + lift + arch))
        outer = h + Vector((s * (spacing + 0.021), -0.084, 0.022 + lift + tilt * 0.06))
        brow.capsule(inner, top, brow_t * 0.6).capsule(top, outer, brow_t * 0.48)
        L["hair"].append(brow.obj)
    width, lip, smile = f["mouth"]
    mouth = h + Vector((0, -0.097, -0.07))
    lips = Blob(rig, f"Lips{style}", mats["lips"], "head", resolution=0.0018)
    lips.ellipsoid(mouth + Vector((0, 0, 0.0042)), (width, 0.008, lip * 0.62), (math.radians(-10), 0, 0))     # upper lip
    lips.ellipsoid(mouth + Vector((0, 0.001, -0.0052)), (width * 0.86, 0.009, lip * 0.78), (math.radians(12), 0, 0))  # lower lip
    for s, _ in sides():
        lips.ball(mouth + Vector((s * width * 0.95, 0.006, smile)), lip * 0.45)
    L["skin"].append(lips.obj)
    line = ra.box("mouth", (width * 1.7, 0.004, 0.0018), mouth + Vector((0, -0.006, -0.0005)), mats["mouth"])
    L["detail"].append(a(line, "head"))
    if style == 3:  # Lines of a weathered face: under the eyes and from the nose.
        for s, _ in sides():
            line = Blob(rig, "Wrinkle", mats["lines"], "head", resolution=0.002)
            line.capsule(h + Vector((s * 0.022, -0.096, -0.02)), h + Vector((s * 0.04, -0.091, -0.016)), 0.0025)
            line.capsule(h + Vector((s * 0.018, -0.1, -0.05)), h + Vector((s * 0.03, -0.094, -0.074)), 0.0025)
            L["skin"].append(line.obj)
    return L


def jaw_point(ang, z, out=0.0):
    """A point on the face and jaw, `ang` round from the chin (0) to the ears (±90°), at height `z`
    above the head's centre, `out` metres outside the skin."""
    h = Body.HEAD
    cz, rz = -0.062, 0.07
    k = math.sqrt(max(0.05, 1 - ((z - cz) / rz) ** 2))
    rx, ry = 0.064 * k + out, 0.066 * k + out
    return h + Vector((math.sin(ang) * rx, -0.028 - math.cos(ang) * ry, z))


def build_beard(rig, style, mat):
    """Facial hair over the face: a moustache, a goatee or a full beard. The goatee and the beard
    are the jaw a little bigger, cut back where the skin stays bare; drawn over the head, which is
    a holdout, only what stands out of the skin shows."""
    h = Body.HEAD
    beard = Blob(rig, f"Beard{style}", mat, "head", resolution=0.003)
    for s, _ in sides():  # Every beard has the moustache, over the upper lip.
        beard.ellipsoid(h + Vector((s * 0.012, -0.103, -0.061)), (0.014, 0.007, 0.006), (0, s * 0.35, s * -0.25), stiffness=2.5)
    if style == 2:  # The goatee: on the chin and under the lower lip.
        beard.ball(h + Vector((0, -0.074, -0.108)), 0.032)
        beard.ellipsoid(h + Vector((0, -0.098, -0.088)), (0.009, 0.008, 0.009))
        beard.ellipsoid(h + Vector((0, -0.04, -0.03)), (0.09, 0.08, 0.06), negative=True)
    if style == 3:  # The full beard covers the jaw up to the ears.
        beard.ellipsoid(h + Vector((0, -0.028, -0.066)), (0.073, 0.075, 0.075))
        beard.ball(h + Vector((0, -0.074, -0.11)), 0.034)
        for s, _ in sides():
            beard.ball(h + Vector((s * 0.045, -0.058, -0.045)), 0.03)
        beard.ellipsoid(h + Vector((0, -0.075, -0.002)), (0.056, 0.08, 0.052), negative=True)    # the upper face stays bare
        beard.ellipsoid(h + Vector((0, -0.104, -0.072)), (0.017, 0.02, 0.007), negative=True)  # and the lips
        beard.ellipsoid(h + Vector((0, 0.06, 0.0)), (0.1, 0.06, 0.12), negative=True)          # and the back of the head
    return {"hair": [beard.obj]}


# The clothes tailors make in town: slot, then a builder of the garment over the body. Keep in step
# with Items.Clothes on the server.
def clothes(rig):
    body = Body(rig)
    a = rig.attach
    h = Body.HEAD

    def helmet():
        shell = colour_mat("helmet", (0.75, 0.52, 0.04), 0.3, bump=0.05, scale=8)
        dome = ra.sphere("dome", 0.112, h + Vector((0, 0.006, 0.018)), shell, scale=(0.9, 1.04, 0.9),
                         keep=lambda co: co.z > -0.012)
        dome.modifiers["solid"].thickness = 0.008
        brim = ra.cylinder("brim", 0.1, 0.008, h + Vector((0, 0.008, 0.008)), shell, verts=40)
        brim.scale = (1.0, 1.24, 1)
        ridge = ra.box("ridge", (0.018, 0.17, 0.02), h + Vector((0, 0.006, 0.11)), shell, bevel=0.008)
        lamp = ra.cylinder("lamp", 0.018, 0.024, h + Vector((0, -0.105, 0.058)), ra.plain("lamp", (0.05, 0.05, 0.05), 0.4),
                           rotation=(math.pi / 2, 0, 0))
        lens = ra.cylinder("lens", 0.014, 0.004, h + Vector((0, -0.118, 0.058)), emission("light", (1.0, 0.92, 0.7), 6.0),
                           rotation=(math.pi / 2, 0, 0))
        return [a(o, "head") for o in (dome, brim, ridge, lamp, lens)]

    def sou_wester():
        oil = colour_mat("oilskin_hat", (0.78, 0.6, 0.06), 0.35, bump=0.2, scale=25)
        crown = ra.sphere("crown", 0.118, h + Vector((0, 0.008, 0.012)), oil, scale=(0.96, 1.06, 1.0), keep=lambda co: co.z > -0.02)
        crown.modifiers["solid"].thickness = 0.006
        brim = ra.cylinder("brim", 0.15, 0.04, h + Vector((0, 0.04, -0.012)), oil, radius2=0.1, verts=48,
                           rotation=(math.radians(-16), 0, 0))
        brim.scale = (0.95, 1.2, 1)
        brim.modifiers.new("solid", "SOLIDIFY").thickness = 0.004
        return [a(o, "head") for o in (crown, brim)]

    def straw_hat():
        straw = straw_mat()
        band = cloth_mat("band", (0.25, 0.04, 0.03))
        crown = ra.cylinder("crown", 0.083, 0.08, h + Vector((0, 0.008, 0.07)), straw, radius2=0.075, verts=40, bevel=0.01)
        crown.scale = (0.98, 1.1, 1)
        brim = ra.cylinder("brim", 0.19, 0.008, h + Vector((0, 0.008, 0.034)), straw, radius2=0.18, verts=48)
        ribbon = ra.cylinder("ribbon", 0.0845, 0.022, h + Vector((0, 0.008, 0.045)), band, verts=40)
        ribbon.scale = (0.98, 1.1, 1)
        return [a(o, "head") for o in (crown, brim, ribbon)]

    def beanie():
        wool = cloth_mat("beanie", (0.5, 0.12, 0.04), 160, 0.95, 0.6)
        cap = Blob(rig, "Beanie", wool, "head", resolution=0.004)
        cap.ellipsoid(h + Vector((0, 0.008, 0.03)), (0.097, 0.114, 0.104))
        cap.ellipsoid(h + Vector((0, 0.008, 0.0)), (0.101, 0.118, 0.032))     # the turned-up rim
        cap.ellipsoid(h + Vector((0, -0.07, -0.08)), (0.1, 0.07, 0.075), negative=True)
        cap.ellipsoid(h + Vector((0, 0.0, -0.09)), (0.12, 0.13, 0.07), negative=True)
        return [cap.obj]

    def jacket(family, mat, d=0.02, hem=0.98, collar=True):
        trunk = body.torso(Blob(rig, family, mat), d, pelvis=False, hem=hem)
        trunk.ellipsoid((0, 0.014, (hem + 1.17) / 2), inflate((0.13, 0.088, 0.07), d))
        if collar:
            trunk.capsule((0, 0.03, 1.45), (0, 0.012, 1.5), 0.056)
            trunk.ellipsoid((0, -0.03, 1.49), (0.05, 0.05, 0.035), negative=True)
        objs = [trunk.obj]
        for s, side in sides():
            arm = body.arm(Blob(rig, family, mat, "arm_" + side), s, d * 0.6, hand=False)
            arm.ball(Vector((s * 0.218, -0.012, 0.925)), 0.038)
            objs.append(arm.obj)
        return objs

    def rod(name, p, q, r, mat, part="root"):
        p, q = Vector(p), Vector(q)
        c = ra.cylinder(name, r, (q - p).length, (p + q) / 2, mat, verts=12)
        c.rotation_euler = Vector((0, 0, 1)).rotation_difference(q - p).to_euler()
        return a(c, part)

    def panel(name, mat, rows, steps=10, thickness=0.006):
        """A sheet bent round the front of the body: rows of (height, half the angle it spans in degrees,
        radius across, radius front to back[, the angle of its middle])."""
        verts, faces = [], []
        for z, half, rx, ry, *mid in rows:
            for j in range(-steps, steps + 1):
                ang = math.radians(half * j / steps + (mid[0] if mid else 0))
                verts.append((math.sin(ang) * rx, 0.014 - math.cos(ang) * ry, z))
        n = 2 * steps + 1
        for i in range(len(rows) - 1):
            for j in range(n - 1):
                faces.append((i * n + j, i * n + j + 1, (i + 1) * n + j + 1, (i + 1) * n + j))
        obj = ra.mesh_from(name, verts, faces, mat)
        for poly in obj.data.polygons:
            poly.use_smooth = True
        solid = obj.modifiers.new("solid", "SOLIDIFY")
        solid.thickness = thickness
        sub = obj.modifiers.new("sub", "SUBSURF")
        sub.levels = sub.render_levels = 2
        return a(obj)

    def flannel():
        objs = jacket("Flannel", check_mat("flannel", (0.55, 0.06, 0.04), (0.04, 0.035, 0.035)), 0.02, hem=1.0)
        button = ra.plain("button", (0.05, 0.04, 0.03), 0.4)
        for i in range(5):
            objs.append(a(ra.sphere("button", 0.007, (0, -0.104 + (0.006 if i == 4 else 0), 1.1 + i * 0.075), button, scale=(1, 0.5, 1))))
        return objs

    def apron():
        leather = colour_mat("apron", (0.2, 0.09, 0.04), 0.55, bump=0.35, scale=12)
        strap = colour_mat("strap", (0.08, 0.05, 0.03), 0.5)
        objs = [panel("apron", leather, [(1.42, 28, 0.12, 0.1), (1.3, 36, 0.155, 0.112), (1.15, 52, 0.142, 0.104),
                                         (1.0, 60, 0.158, 0.118), (0.85, 60, 0.17, 0.122), (0.64, 56, 0.17, 0.122)], thickness=0.007)]
        for s, _ in sides():
            objs.append(rod("strap", (s * 0.055, -0.098, 1.42), (s * 0.06, 0.03, 1.47), 0.006, strap))
            objs.append(rod("tie", (s * 0.14, -0.05, 1.13), (s * 0.1, 0.09, 1.12), 0.006, strap))
        pocket = colour_mat("apron_pocket", (0.16, 0.07, 0.03), 0.6, bump=0.35, scale=12)
        objs.append(a(ra.box("pocket", (0.14, 0.012, 0.09), (0, -0.128, 1.02), pocket, bevel=0.006)))
        return objs

    def oilskin():
        coat = colour_mat("oilskin", (0.8, 0.6, 0.05), 0.3, bump=0.25, scale=25)
        objs = jacket("Oilskin", coat, 0.024, hem=0.98)
        skirt = ra.cylinder("skirt", 0.2, 0.42, (0, 0.014, 0.81), coat, radius2=0.158, verts=40)
        skirt.scale = (1, 0.74, 1)
        objs.append(a(skirt))
        clasp = ra.plain("clasp", (0.1, 0.1, 0.1), 0.4, 1.0)
        for i in range(4):
            objs.append(a(ra.box("clasp", (0.03, 0.01, 0.008), (0, -0.112 - (0.03 if i == 0 else 0), 0.86 + i * 0.15), clasp, bevel=0.003)))
        return objs

    def suit_jacket():
        navy = cloth_mat("suit", (0.03, 0.04, 0.08), 320, 0.75, 0.15)
        objs = jacket("Suit", navy, 0.022, hem=0.96, collar=False)
        white = cloth_mat("shirt_white", (0.8, 0.8, 0.78))
        tie = cloth_mat("tie", (0.4, 0.04, 0.05), 200, 0.5)
        objs.append(panel("shirt", white, [(1.475, 36, 0.05, 0.068), (1.4, 22, 0.126, 0.134), (1.22, 4, 0.124, 0.13)], 4, 0.003))
        objs.append(panel("tie", tie, [(1.45, 5, 0.054, 0.074), (1.4, 5, 0.126, 0.137), (1.2, 7, 0.124, 0.133), (1.17, 1, 0.124, 0.131)], 2, 0.003))
        lapel = cloth_mat("lapel", (0.012, 0.016, 0.04), 320, 0.4, 0.1)
        for s, _ in sides():
            objs.append(panel("lapel", lapel, [(1.47, 9, 0.064, 0.078, s * 36), (1.4, 8, 0.126, 0.137, s * 23), (1.22, 4, 0.124, 0.133, s * 7)], 2, 0.005))
        button = ra.plain("button", (0.02, 0.02, 0.02), 0.3)
        for i in range(2):
            objs.append(a(ra.sphere("button", 0.008, (0, -0.104, 1.08 + i * 0.08), button, scale=(1, 0.5, 1))))
        return objs

    def trousers(family, mat, d=0.018, bib=False, pads=None):
        hips = Blob(rig, family, mat)
        hips.ellipsoid((0, 0.016, 1.01), (0.143 + d, 0.096 + d, 0.1))
        hips.ellipsoid((0, 0.016, 0.91), (0.085 + d, 0.08 + d, 0.06))      # the crotch
        if bib:
            hips.ellipsoid((0, -0.06, 1.2), (0.12, 0.04, 0.15))
            hips.ellipsoid((0, 0.08, 1.15), (0.12, 0.04, 0.1))
        objs = [hips.obj]
        for s, side in sides():
            leg = body.leg(Blob(rig, family, mat, "leg_" + side), s, d=d, ankle=False, calf_to=0.97)
            leg.ball(Vector((s * 0.098, 0.014, 0.12)), 0.044 + d)
            objs.append(leg.obj)
            if pads:
                objs.append(a(ra.sphere("pad", 0.045, (s * 0.096, -0.038 - d, 0.53), pads, scale=(1, 0.4, 1.15)), "leg_" + side))
        return objs

    def overalls():
        denim = cloth_mat("overalls", (0.12, 0.2, 0.36), 280, 0.85, 0.4)
        brass = ra.plain("brass", (0.6, 0.45, 0.15), 0.3, 1.0)
        objs = trousers("Overalls", denim, 0.02, bib=True)
        for s, _ in sides():
            objs.append(rod("strap", (s * 0.07, -0.085, 1.33), (s * 0.085, 0.0, 1.452), 0.012, denim))
            objs.append(rod("strap", (s * 0.085, 0.0, 1.452), (s * 0.06, 0.09, 1.25), 0.012, denim))
            objs.append(a(ra.box("buckle", (0.024, 0.008, 0.02), (s * 0.07, -0.092, 1.32), brass, bevel=0.003)))
        objs.append(a(ra.box("pocket", (0.09, 0.012, 0.07), (0, -0.104, 1.22), denim, bevel=0.008)))
        return objs

    def work_trousers():
        canvas = cloth_mat("canvas", (0.24, 0.22, 0.14), 220, 0.9, 0.45)
        pad = colour_mat("pad", (0.04, 0.04, 0.04), 0.5, bump=0.3)
        return trousers("Work", canvas, 0.02, pads=pad)

    def suit_trousers():
        return trousers("SuitPants", cloth_mat("suit_pants", (0.03, 0.04, 0.08), 320, 0.75, 0.15), 0.014)

    def boots(family, mat, top=0.42, d=0.016, sole_mat=None, laces=None, glossy=False):
        objs = []
        for s, side in sides():
            boot = body.foot(Blob(rig, family, mat, "leg_" + side), s, d=d, height=1.15)
            if top > 0.12:
                knee = Vector((s * 0.096, 0.004, 0.52))
                ankle = Vector((s * 0.098, 0.016, 0.1))
                boot.capsule(ankle, ankle.lerp(knee, (top - 0.1) / 0.42), 0.052 + d)
            if top > 0.3:  # Round the calf, so the trousers do not show through at the back.
                boot.ellipsoid(knee.lerp(ankle, 0.3) + Vector((0, 0.012, 0)), inflate((0.04, 0.043, 0.09), d + 0.008))
            objs.append(boot.obj)
            sole = ra.box("sole", (0.118, 0.272, 0.03), (s * 0.098, -0.032, 0.015), sole_mat or mat, bevel=0.01)
            objs.append(a(sole, "leg_" + side))
            if laces:
                for i in range(4):
                    objs.append(a(ra.box("lace", (0.04, 0.006, 0.006), (s * 0.098, -0.06 + i * 0.022, 0.085 + i * 0.022), laces,
                                         rotation=(math.radians(-50), 0, 0)), "leg_" + side))
        return objs

    def rubber_boots():
        rubber = colour_mat("rubber", (0.07, 0.2, 0.07), 0.25, bump=0.05, scale=6)
        return boots("Wellies", rubber, top=0.44, d=0.022)

    def work_boots():
        leather = colour_mat("boot_leather", (0.22, 0.11, 0.04), 0.5, bump=0.3, scale=18)
        sole = ra.plain("lug", (0.03, 0.025, 0.02), 0.7, bump=0.5)
        laces = ra.plain("laces", (0.5, 0.42, 0.25), 0.6)
        return boots("Boots", leather, top=0.18, d=0.02, sole_mat=sole, laces=laces)

    def dress_shoes():
        black = colour_mat("patent", (0.012, 0.011, 0.01), 0.12, bump=0.02, scale=6)
        return boots("Oxfords", black, top=0.0, d=0.01)

    return {
        "clothes_miner_helmet": ("head", helmet),
        "clothes_sou_wester": ("head", sou_wester),
        "clothes_straw_hat": ("head", straw_hat),
        "clothes_beanie": ("head", beanie),
        "clothes_flannel_jacket": ("body", flannel),
        "clothes_smith_apron": ("body", apron),
        "clothes_oilskin": ("body", oilskin),
        "clothes_suit_jacket": ("body", suit_jacket),
        "clothes_overalls": ("legs", overalls),
        "clothes_work_trousers": ("legs", work_trousers),
        "clothes_suit_trousers": ("legs", suit_trousers),
        "clothes_rubber_boots": ("feet", rubber_boots),
        "clothes_work_boots": ("feet", work_boots),
        "clothes_dress_shoes": ("feet", dress_shoes),
    }


# --- Rendering ----------------------------------------------------------------------------------

# Mask colours: which tint each pixel takes. Two images with three channels each.
MASKS = {
    "a": {"skin": (1, 0, 0), "shirt": (0, 1, 0), "pants": (0, 0, 1)},
    "b": {"hair": (1, 0, 0), "shoes": (0, 1, 0), "detail": (0, 0, 1)},
}
# The face layer's iris takes the colour in the shirt's place.
LAYER_CHANNELS = {"eyes": "shirt"}


class Studio:
    """The scene, its cameras and lights, and switching objects between shading, masks and holdout."""

    def __init__(self):
        scene = ra.reset()
        ra.set_world((0.25, 0.27, 0.3), 0.6)
        self.scene = scene
        self.rig = Rig()
        self.portrait_cam = ra.camera(scene, Vector((0, 0, 0.98)), PORTRAIT_WIDTH_M, PORTRAIT_RES, pitch=PORTRAIT_PITCH)
        self.portrait_cam.data.sensor_fit = "HORIZONTAL"
        self.walk_cam = ra.camera(scene, Vector((0, 0, 0.81)), FRAME_RES[0] / ra.PPM, FRAME_RES)
        self.walk_cam.data.sensor_fit = "HORIZONTAL"
        ra.light("SUN", (0, 0, 5), 3.4, (1.0, 0.95, 0.88), size=0.25, rotation=(math.radians(40), math.radians(-25), math.radians(-20)))
        ra.light("SUN", (0, 0, 5), 1.1, (0.6, 0.7, 1.0), size=0.5, rotation=(math.radians(60), math.radians(40), math.radians(150)))
        ra.light("AREA", (0, 1.5, 2.2), 60, (1, 1, 1), size=1.5, rotation=(math.radians(-50), 0, 0))
        ra.light("AREA", (0.6, -1.2, 1.7), 25, (1.0, 0.92, 0.85), size=0.8, rotation=(math.radians(55), 0, math.radians(25)))
        self.catcher = ra.box("catcher", (4, 4, 0.01), (0, 0, -0.005))
        self.catcher.is_shadow_catcher = True
        self.originals = {}
        self.flat = {}

    def use(self, cam, res):
        self.scene.camera = cam
        self.scene.render.resolution_x, self.scene.render.resolution_y = res

    def remember(self, objs):
        for o in objs:
            if o.type in ("MESH", "META") and o not in self.originals:
                self.originals[o] = list(o.data.materials)

    @staticmethod
    def show(objs, visible):
        for o in objs:
            o.hide_render = not visible

    @staticmethod
    def holdout(objs, on):
        for o in objs:
            o.is_holdout = on

    def mask_mode(self, layers, channel_colors):
        for name, objs in layers.items():
            colour = channel_colors.get(LAYER_CHANNELS.get(name, name), (0, 0, 0))
            key = tuple(colour)
            if key not in self.flat:
                self.flat[key] = emission(f"mask{key}", colour, 1.0)
            for o in objs:
                if o.type in ("MESH", "META"):
                    o.data.materials.clear()
                    o.data.materials.append(self.flat[key])
        self.scene.view_settings.view_transform = "Standard"
        self.scene.view_settings.look = "None"
        self.scene.cycles.samples = 12
        self.scene.cycles.use_denoising = False

    def shade_mode(self, samples=48):
        for o, mats in self.originals.items():
            o.data.materials.clear()
            for m in mats:
                o.data.materials.append(m)
        self.scene.view_settings.view_transform = "AgX"
        self.scene.view_settings.look = "AgX - Medium High Contrast"
        self.scene.cycles.samples = samples
        self.scene.cycles.use_denoising = True

    def sheet(self, path_portrait: Path, path_walk: Path):
        """Renders the portrait and the walk atlas (rows: directions, columns: poses)."""
        self.use(self.portrait_cam, PORTRAIT_RES)
        self.rig.pose()
        ra.render(path_portrait)
        self.use(self.walk_cam, FRAME_RES)
        fw, fh = FRAME_RES
        atlas = Image.new("RGBA", (fw * len(POSES), fh * len(DIRECTIONS)))
        for row, angle in enumerate(DIRECTIONS.values()):
            for col, pose in enumerate(POSES):
                self.rig.pose(angle, pose, head_tilt=-0.12)
                ra.render(TMP / "frame.png")
                atlas.paste(Image.open(TMP / "frame.png").convert("RGBA"), (col * fw, row * fh))
        path_walk.parent.mkdir(parents=True, exist_ok=True)
        atlas.save(path_walk, optimize=True)

    def masked(self, name, layers, masks=True):
        """The shading images of whatever is shown, and with `masks` the two mask images."""
        for mode in ("", "_mask_a", "_mask_b") if masks else ("",):
            if mode:
                self.mask_mode(layers, MASKS[mode[-1]])
            else:
                self.shade_mode()
            self.sheet(OUT / "portrait" / f"{name}{mode}.png", OUT / "walk" / f"{name}{mode}.png")
        self.shade_mode()


def face_mats():
    return {
        "white": ra.plain("eye_white", (0.8, 0.79, 0.76), 0.15, variation=0.0, grime=0.0, bump=0.0),
        "iris": tint_mat("iris", 0.1, 0.05, 300, lo=0.55, hi=0.75),
        "pupil": ra.plain("pupil", (0.01, 0.01, 0.01), 0.05, variation=0.0, grime=0.0, bump=0.0),
        "lid": tint_mat("lid", 0.5, 0.02, 70, sss=0.2, lo=0.6, hi=0.66),
        "lips": tint_mat("lips", 0.35, 0.02, 90, sss=0.3, lo=0.5, hi=0.56),
        "mouth": ra.plain("mouth", (0.08, 0.02, 0.02), 0.6, variation=0.0, grime=0.0, bump=0.0),
        "lines": tint_mat("lines", 0.6, 0.0, 70, lo=0.45, hi=0.5),
        "brow": hair_mat("brow", 0.5, 0.7),
    }


def clear_out(*subs):
    for sub in subs:
        (OUT / sub).mkdir(parents=True, exist_ok=True)


def render_base(studio, L, shirts, hairs):
    """Per hair and shirt style: grey shading images and two masks saying which pixels are skin,
    shirt, pants, hair, shoes or untinted detail."""
    all_shirt = [o for s in shirts for o in s]
    all_hair = [o for h in hairs for o in h]
    for sub in ("portrait", "walk"):
        (OUT / sub).mkdir(parents=True, exist_ok=True)
        for old in (OUT / sub).glob("h*_s*.png"):
            old.unlink()
    for h in range(HAIR_STYLES):
        for s in range(SHIRT_STYLES):
            studio.show(all_shirt + all_hair, False)
            studio.show(shirts[s] + hairs[h], True)
            layers = {"skin": L["skin"], "pants": L["pants"], "shoes": L["shoes"], "detail": L["detail"],
                      "shirt": shirts[s], "hair": hairs[h]}
            studio.masked(f"h{h}_s{s}", layers)
            print("character", f"h{h}_s{s}", flush=True)


def render_shadow(studio, body_objs):
    """The body is invisible to the camera but still casts a shadow on the catcher, lit from
    almost straight above like the garage bulb, which keeps the shadow inside the frame."""
    studio.use(studio.walk_cam, FRAME_RES)
    studio.rig.pose()
    lights = [o for o in studio.scene.objects if o.type == "LIGHT"]
    for o in body_objs:
        o.visible_camera = False
    for o in lights:
        o.hide_render = True
    overhead = ra.light("SUN", (0, 0, 5), 4.0, size=0.25, rotation=(math.radians(10), math.radians(6), 0))
    studio.catcher.hide_render = False
    ra.render(OUT / "shadow.png")
    overhead.hide_render = True
    for o in lights:
        o.hide_render = False
    for o in body_objs:
        o.visible_camera = True
    studio.catcher.hide_render = True


def main(args):
    TMP.mkdir(parents=True, exist_ok=True)
    clear_out("", "portrait", "walk")
    only = [a.split("=", 1)[1] for a in args if a.startswith("only=")]
    studio = Studio()
    rig = studio.rig
    L, shirts, hairs = build_base(rig)
    base = [o for objs in L.values() for o in objs]
    all_shirt = [o for s in shirts for o in s]
    all_hair = [o for h in hairs for o in h]
    studio.remember(base + all_shirt + all_hair)

    mats = face_mats()
    faces = [build_face(rig, f, mats) for f in range(FACE_STYLES)]
    beard_m = hair_mat("beard", 0.5, 0.75)
    beards = [None] + [build_beard(rig, b, beard_m) for b in range(1, BEARD_STYLES)]
    garments = {item: (slot, build()) for item, (slot, build) in clothes(rig).items()}
    layer_objs = ([o for f in faces for objs in f.values() for o in objs]
                  + [o for b in beards[1:] for objs in b.values() for o in objs]
                  + [o for _, objs in garments.values() for o in objs])
    studio.remember(layer_objs)

    if "preview" in args:
        render_preview(studio, L, shirts, hairs, faces, beards, garments, args)
        return

    studio.show(layer_objs, False)
    studio.catcher.hide_render = True
    if "base" in args:
        # The face is always a layer of its own, so the base head has none.
        render_shadow_and_base(studio, L, shirts, hairs, base)

    if "layers" in args:
        holdout = L["skin"] + L["pants"] + L["shoes"] + L["detail"]
        studio.show(all_shirt + all_hair, False)
        studio.show(holdout, True)
        studio.holdout(holdout, True)
        jobs = []
        for f in range(FACE_STYLES):
            jobs.append((f"face{f}", faces[f], True))
        for b in range(1, BEARD_STYLES):
            jobs.append((f"beard{b}", beards[b], True))
        for item, (_, objs) in garments.items():
            jobs.append((item, {"detail": objs}, False))
        for name, layers, masks in jobs:
            if only and name not in only:
                continue
            objs = [o for v in layers.values() for o in v]
            studio.show(objs, True)
            studio.masked(name, layers, masks)
            studio.show(objs, False)
            print("layer", name, flush=True)
        studio.holdout(holdout, False)

    if "icons" in args:
        render_icons(studio, garments)

    write_meta(studio, garments)


def render_icons(studio, garments):
    """Inventory icons of the clothes: each garment alone, turned a little towards the light."""
    studio.shade_mode()
    studio.use(studio.portrait_cam, (PORTRAIT_RES[0] * 2, PORTRAIT_RES[1] * 2))
    every = [o for _, objs in garments.values() for o in objs]
    shown = [o for o in studio.scene.objects if o.type in ("MESH", "META") and not o.hide_render and o not in every]
    studio.show(shown, False)
    for item, (_, objs) in garments.items():
        studio.show(every, False)
        studio.show(objs, True)
        studio.rig.pose(-0.45)
        ra.render(TMP / "icon.png")
        ra.icon_from(Image.open(TMP / "icon.png").convert("RGBA"), ra.ART / "icons" / f"item_{item}.png")
        print("icon", item, flush=True)
    studio.show(every, False)
    studio.show(shown, True)
    studio.rig.pose()


def render_shadow_and_base(studio, L, shirts, hairs, body_objs):
    studio.show([o for s in shirts for o in s] + [o for h in hairs for o in h], False)
    studio.show(shirts[0] + hairs[1], True)
    render_shadow(studio, body_objs + shirts[0] + hairs[1])
    render_base(studio, L, shirts, hairs)


def write_meta(studio, garments):
    from bpy_extras.object_utils import world_to_camera_view

    def feet(cam, res):
        studio.use(cam, res)  # The projection depends on the image's aspect ratio.
        f = world_to_camera_view(studio.scene, cam, Vector((0, 0, 0)))
        return round(f.x * res[0]), round((1 - f.y) * res[1])

    px, py = feet(studio.portrait_cam, PORTRAIT_RES)
    wx, wy = feet(studio.walk_cam, FRAME_RES)
    fw, fh = FRAME_RES
    meta = {
        "portrait": {"width": PORTRAIT_RES[0], "height": PORTRAIT_RES[1], "feetX": px, "feetY": py,
                     "pixelsPerMetre": PORTRAIT_RES[0] / PORTRAIT_WIDTH_M},
        "walk": {"frameWidth": fw, "frameHeight": fh, "feetX": wx, "feetY": wy, "pixelsPerMetre": ra.PPM,
                 "directions": list(DIRECTIONS), "poses": list(POSES)},
        "faces": FACE_STYLES,
        "beards": BEARD_STYLES,
        "clothes": {item: slot for item, (slot, _) in garments.items()},
    }
    (OUT / "meta.json").write_text(json.dumps(meta, indent=1))
    print("character", meta)


def tint_preview(obj, color):
    """Multiplies an object's grey base colour by a tint, as the game's shader does."""
    if obj.type not in ("MESH", "META") or not obj.data.materials:
        return
    mat = obj.data.materials[0].copy()
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    sock = bsdf.inputs["Base Color"]
    if not sock.links:
        return
    src = sock.links[0].from_socket
    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    ra._input(mul, "Factor", "VALUE").default_value = 1.0
    nt.links.new(src, ra._input(mul, "A", "RGBA"))
    ra._input(mul, "B", "RGBA").default_value = (*(c * 1.35 for c in color), 1)
    nt.links.new(ra._output(mul, "Result", "RGBA"), sock)
    obj.data.materials.clear()
    obj.data.materials.append(mat)


def render_preview(studio, L, shirts, hairs, faces, beards, garments, args):
    """A few big renders to look at while changing the models: front, side and back."""
    scene = studio.scene
    out = TMP / "preview"
    out.mkdir(parents=True, exist_ok=True)
    every = [o for objs in L.values() for o in objs] + [o for s in shirts for o in s] + [o for h in hairs for o in h]
    every += [o for f in faces for objs in f.values() for o in objs]
    every += [o for b in beards[1:] for objs in b.values() for o in objs]
    every += [o for _, objs in garments.values() for o in objs]
    studio.catcher.hide_render = True
    studio.shade_mode(32)
    # The game's tints, roughly, so the preview shows colours.
    tints = {"skin": (0.62, 0.42, 0.3), "pants": (0.2, 0.3, 0.55), "shoes": (0.25, 0.15, 0.08), "hair": (0.35, 0.2, 0.1),
             "shirt": (0.75, 0.2, 0.15), "eyes": (0.25, 0.45, 0.6)}
    groups = {"skin": L["skin"], "pants": L["pants"], "shoes": L["shoes"], "hair": [o for h in hairs for o in h],
              "shirt": [o for s in shirts for o in s]}
    for f in faces:
        for k, objs in f.items():
            groups.setdefault(k, []).extend(objs)
    for b in beards[1:]:
        groups["hair"].extend(b["hair"])
    for name, objs in groups.items():
        if name in tints:
            for o in objs:
                tint_preview(o, tints[name])
    picks = [a.split("=", 1)[1].split(",") for a in args if a.startswith("look=")] or [["h1", "s0", "f0", "b0"]]
    for n, pick in enumerate(picks):
        studio.show(every, False)
        shown = [o for objs in L.values() for o in objs]
        for p in pick:
            if p[0] == "h":
                shown += hairs[int(p[1:])]
            elif p[0] == "s":
                shown += shirts[int(p[1:])]
            elif p[0] == "f":
                shown += [o for objs in faces[int(p[1:])].values() for o in objs]
            elif p[0] == "b" and int(p[1:]) > 0:
                shown += [o for objs in beards[int(p[1:])].values() for o in objs]
            elif p in garments:
                shown += garments[p][1]
        studio.show(shown, True)
        cam = studio.portrait_cam
        studio.use(cam, (PORTRAIT_RES[0] * 2, PORTRAIT_RES[1] * 2))
        sheet = Image.new("RGBA", (PORTRAIT_RES[0] * 2 * 3, PORTRAIT_RES[1] * 2), (60, 64, 70, 255))
        for i, angle in enumerate((0.0, math.pi / 2, math.pi)):
            studio.rig.pose(angle)
            ra.render(TMP / "p.png")
            img = Image.open(TMP / "p.png").convert("RGBA")
            sheet.alpha_composite(img, (i * PORTRAIT_RES[0] * 2, 0))
        sheet.save(out / f"look{n}.png")
        # Head close-up.
        cam.data.ortho_scale = 0.26
        loc = cam.location.copy()
        cam.location = loc + Vector((0, 0, 0.64))
        studio.use(cam, (400, 400))
        studio.rig.pose()
        ra.render(out / f"head{n}.png")
        cam.data.ortho_scale = PORTRAIT_WIDTH_M
        cam.location = loc
        studio.use(studio.walk_cam, (FRAME_RES[0] * 2, FRAME_RES[1] * 2))
        strip = Image.new("RGBA", (FRAME_RES[0] * 2 * 4, FRAME_RES[1] * 2), (60, 64, 70, 255))
        for i, angle in enumerate(DIRECTIONS.values()):
            studio.rig.pose(angle, "step_a", head_tilt=-0.12)
            ra.render(TMP / "w.png")
            strip.alpha_composite(Image.open(TMP / "w.png").convert("RGBA"), (i * FRAME_RES[0] * 2, 0))
        strip.save(out / f"walk{n}.png")
        print("preview", n, pick, flush=True)


if __name__ == "__main__":
    main(sys.argv[1:] or ["base", "layers"])
