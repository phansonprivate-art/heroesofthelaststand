"""Baut eigene Low-Poly-Helden (Guardian, Shadow, Arcanist) auf dem vorhandenen KayKit-Skelett,
damit alle bestehenden Animationen (Basis + die per CharacterVisual.add_animation_libraries
gegraftete "kk"-Bibliothek) unveraendert funktionieren.

Vorgehen pro Held: Original-GLB importieren (liefert das exakte Skelett, alle Animationen und die
Handwaffen), alte Koerper-Meshes sowie Helm/Hut/Cape loeschen, neuen Koerper samt Gesicht,
Kopfbedeckung und Umhang aus Primitiven bauen, jedes Teil starr an genau einen Knochen binden,
die Teile zu zwei Meshes (Koerper, Kopf) zusammenfassen und als neues GLB exportieren.

Entworfen wird im Spiel-/glTF-Raum: Y oben, +Z = Blickrichtung der Figur, Einheiten wie das Rig
(Boden y=0, Kopfgelenk y~1.24). Blender selbst arbeitet mit Z oben.

Aufruf (ein Held pro Prozess, damit sich nichts zwischen den Laeufen vermischt):
    blender.exe --background --python tools/blender_build_heroes.py -- guardian
Ausgabe: assets/models/heroes_custom/<Guardian|Shadow|Arcanist>.glb
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

PROJECT = r"C:\Claude\Gaming\heroes-of-the-last-stand"
OUT_DIR = os.path.join(PROJECT, "assets", "models", "heroes_custom")

# Spiel (x, y, z) -> Blender (x, -z, y)
TO_BLENDER = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))
TO_GAME = TO_BLENDER.inverted()

try:
    bpy.ops.preferences.addon_enable(module="io_scene_gltf2")
except Exception:
    pass


def log(msg):
    print("[build_heroes] %s" % msg)


def B(v):
    return TO_BLENDER @ Vector(v)


def G(v):
    return TO_GAME @ Vector(v)


def rot_blender(euler_deg):
    """Rotation im Spielraum (XYZ-Euler in Grad) -> Quaternion im Blender-Raum."""
    rg = Euler([math.radians(a) for a in euler_deg], "XYZ").to_matrix()
    return (TO_BLENDER @ rg @ TO_GAME).to_quaternion()


def srgb_to_linear(c):
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def hexrgb(h):
    h = h.lstrip("#")
    return (int(h[0:2], 16) / 255.0, int(h[2:4], 16) / 255.0, int(h[4:6], 16) / 255.0)


def material(name, color, roughness=0.6, metallic=0.0, emission=None, strength=1.0):
    """Farben werden als sRGB angegeben (wie im Farbwaehler) und linear gespeichert, wie glTF es erwartet."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*srgb_to_linear(color), 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission is not None:
        for key in ("Emission Color", "Emission"):
            if key in bsdf.inputs:
                bsdf.inputs[key].default_value = (*srgb_to_linear(emission), 1.0)
                break
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = strength
    return mat


def bevel_mesh(obj, amount, segments):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.bevel(bm, geom=list(bm.edges) + list(bm.verts), offset=amount, segments=segments,
                    profile=0.5, affect="EDGES", clamp_overlap=True)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


class Rig:
    """Baukasten: erzeugt Teile im Spielraum und bindet jedes starr an einen Knochen."""

    def __init__(self, armature, prefix):
        self.arm = armature
        self.prefix = prefix
        self.mats = {}
        self.parts = {"Body": [], "Head": []}

    def j(self, bone):
        return G(self.arm.matrix_world @ self.arm.data.bones[bone].head_local)

    def mat(self, key, color, **kw):
        self.mats[key] = material("%s_%s" % (self.prefix, key), color, **kw)

    def _finish(self, obj, bone, mat, bevel, seg, group, apply=True):
        if apply:
            bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        obj.data.materials.clear()
        obj.data.materials.append(self.mats[mat])
        if bevel > 0.0:
            bevel_mesh(obj, bevel, seg)
        vg = obj.vertex_groups.new(name=bone)
        vg.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
        mod = obj.modifiers.new(name="Armature", type="ARMATURE")
        mod.object = self.arm
        obj.parent = self.arm
        obj.matrix_parent_inverse = self.arm.matrix_world.inverted()
        self.parts[group].append(obj)
        return obj

    def box(self, bone, center, size, mat, rot=None, bevel=0.0, seg=1, group="Body"):
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=B(center))
        obj = bpy.context.object
        obj.scale = (size[0], size[2], size[1])   # Spiel (Breite, Hoehe, Tiefe) -> Blender (x, y, z)
        if rot is not None:
            obj.rotation_mode = "QUATERNION"
            obj.rotation_quaternion = rot_blender(rot)
        return self._finish(obj, bone, mat, bevel, seg, group)

    def sphere(self, bone, center, radius, mat, scale=(1.0, 1.0, 1.0), subdiv=1, group="Body"):
        bpy.ops.mesh.primitive_ico_sphere_add(radius=1.0, subdivisions=subdiv, location=B(center))
        obj = bpy.context.object
        obj.scale = (radius * scale[0], radius * scale[2], radius * scale[1])
        return self._finish(obj, bone, mat, 0.0, 1, group)

    def cone(self, bone, center, r_bottom, r_top, height, mat, rot=None, verts=12, group="Body"):
        # Blenders Kegel steht entlang Blender-Z, also Spiel-Y (oben)
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r_bottom, radius2=r_top, depth=height, location=B(center))
        obj = bpy.context.object
        if rot is not None:
            obj.rotation_mode = "QUATERNION"
            obj.rotation_quaternion = rot_blender(rot)
        return self._finish(obj, bone, mat, 0.0, 1, group)

    def slab(self, bone, top_c, bot_c, top_w, bot_w, thick, mat, width_axis="x", group="Body"):
        """Trapezförmige Platte (Umhang, Helmkamm): Breite entlang width_axis, oben/unten verschieden breit."""
        w_dir = Vector((1, 0, 0)) if width_axis == "x" else Vector((0, 0, 1))
        t_dir = Vector((0, 0, 1)) if width_axis == "x" else Vector((1, 0, 0))
        pts = []
        for c, w in ((Vector(top_c), top_w), (Vector(bot_c), bot_w)):
            for sw in (-1, 1):
                for st in (-1, 1):
                    pts.append(B(c + w_dir * (sw * w * 0.5) + t_dir * (st * thick * 0.5)))
        mesh = bpy.data.meshes.new("slab")
        bm = bmesh.new()
        v = [bm.verts.new(p) for p in pts]
        for f in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
            bm.faces.new([v[i] for i in f])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new("slab", mesh)
        bpy.context.collection.objects.link(obj)
        return self._finish(obj, bone, mat, 0.0, 1, group, apply=False)

    def _segment(self, p_from, p_to, pad_start, pad_end):
        a, b = B(p_from), B(p_to)
        d = (b - a).normalized()
        a = a - d * pad_start
        b = b + d * pad_end
        return (a + b) * 0.5, (b - a).length, d

    def limb(self, bone, p_from, p_to, thick, mat, pad_start=0.0, pad_end=0.0, bevel=0.0, group="Body"):
        """Quader zwischen zwei Gelenken; kuerzester Drehweg haelt die Flaechen an den Weltachsen ausgerichtet."""
        center, length, d = self._segment(p_from, p_to, pad_start, pad_end)
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=center)
        obj = bpy.context.object
        obj.scale = (thick, length, thick)
        obj.rotation_mode = "QUATERNION"
        obj.rotation_quaternion = Vector((0, 1, 0)).rotation_difference(d)
        return self._finish(obj, bone, mat, bevel, 1, group)

    def limb_cone(self, bone, p_from, p_to, r_start, r_end, mat, pad_start=0.0, pad_end=0.0, verts=8, group="Body"):
        center, length, d = self._segment(p_from, p_to, pad_start, pad_end)
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r_start, radius2=r_end, depth=length, location=center)
        obj = bpy.context.object
        obj.rotation_mode = "QUATERNION"
        obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d)
        return self._finish(obj, bone, mat, 0.0, 1, group)

    def join_all(self):
        for group, objs in self.parts.items():
            if not objs:
                continue
            bpy.ops.object.select_all(action="DESELECT")
            for o in objs:
                o.select_set(True)
            bpy.context.view_layer.objects.active = objs[0]
            bpy.ops.object.join()
            joined = bpy.context.view_layer.objects.active
            joined.name = "%s_%s" % (self.prefix, group)
            joined.data.name = joined.name
            log("%s: %d Teile, %d Vertices, %d Materialien" % (joined.name, len(objs), len(joined.data.vertices), len(joined.data.materials)))


def face_materials(r, skin):
    r.mat("skin", skin, roughness=0.65)
    r.mat("skin_dark", tuple(c * 0.86 for c in skin), roughness=0.7)
    r.mat("eye", (0.09, 0.08, 0.12), roughness=0.3)
    r.mat("white", (1.0, 1.0, 1.0), roughness=0.3)
    r.mat("mouth", (0.48, 0.18, 0.17), roughness=0.6)
    r.mat("blush", (0.98, 0.62, 0.60), roughness=0.7)
    r.mat("brow", (0.30, 0.20, 0.14), roughness=0.8)


def chibi_face(r, front, eye_y, eye_dx=0.19, eye_size=(0.13, 0.19), eye_mat="eye", highlight=True,
               brow_angle=10.0, brow_dy=0.15, brow_size=(0.20, 0.05), brow_mat="brow",
               nose=True, mouth=True, blush=True):
    """Grosse Chibi-Augen mit Glanzpunkt, Brauen (positiver Winkel = entschlossen, negativ = freundlich)."""
    for s in (1, -1):
        r.box("head", (s * eye_dx, eye_y, front), (eye_size[0], eye_size[1], 0.06), eye_mat, bevel=0.02, group="Head")
        if highlight:
            r.box("head", (s * eye_dx - 0.03, eye_y + 0.045, front + 0.03), (0.045, 0.045, 0.02), "white", group="Head")
        r.box("head", (s * (eye_dx + 0.01), eye_y + brow_dy, front + 0.01), (brow_size[0], brow_size[1], 0.05),
              brow_mat, rot=(0, 0, s * brow_angle), bevel=0.01, group="Head")
        if blush:
            r.box("head", (s * 0.31, eye_y - 0.14, front), (0.12, 0.05, 0.02), "blush", group="Head")
    if nose:
        r.box("head", (0, eye_y - 0.09, front + 0.02), (0.08, 0.07, 0.06), "skin_dark", bevel=0.015, group="Head")
    if mouth:
        r.box("head", (0, eye_y - 0.22, front), (0.15, 0.035, 0.04), "mouth", group="Head")


def boots(r, side, mat, size=(0.26, 0.18, 0.42)):
    ft = r.j("foot." + side)
    r.box("foot." + side, (ft.x, size[1] * 0.5, 0.08), size, mat, bevel=0.05)


def build_guardian(r):
    """Stärke/Tank: breiter Plattenpanzer, Helm mit Wangenschutz und Federbusch, blauer Umhang."""
    r.mat("steel", (0.72, 0.75, 0.80), roughness=0.32, metallic=0.75)
    r.mat("steel_dark", (0.46, 0.49, 0.56), roughness=0.4, metallic=0.7)
    r.mat("blue", hexrgb("#5aa9ff"), roughness=0.45, metallic=0.15)
    r.mat("cape", (0.16, 0.33, 0.66), roughness=0.85)
    r.mat("cloth", (0.18, 0.27, 0.50), roughness=0.85)
    r.mat("leather", (0.45, 0.30, 0.18), roughness=0.75)
    r.mat("gold", (0.98, 0.78, 0.34), roughness=0.3, metallic=0.85)
    face_materials(r, (0.96, 0.78, 0.64))

    r.box("hips", (0, 0.50, 0), (0.74, 0.30, 0.60), "cloth", bevel=0.05)
    r.box("hips", (0, 0.48, 0.31), (0.42, 0.24, 0.05), "steel", bevel=0.015)
    r.box("hips", (0, 0.66, 0), (0.80, 0.10, 0.66), "leather", bevel=0.02)
    r.box("hips", (0, 0.66, 0.34), (0.16, 0.12, 0.04), "gold", bevel=0.01)
    r.box("chest", (0, 0.98, 0), (0.84, 0.66, 0.66), "steel", bevel=0.10, seg=2)
    r.box("chest", (0, 1.02, 0.335), (0.20, 0.20, 0.05), "blue", rot=(0, 0, 45), bevel=0.01)
    r.box("chest", (0, 1.02, 0.36), (0.07, 0.07, 0.04), "gold")
    r.box("chest", (0, 1.33, 0), (0.58, 0.10, 0.54), "steel_dark", bevel=0.03)
    r.slab("chest", (0, 1.30, -0.32), (0, 0.30, -0.47), 0.72, 0.94, 0.05, "cape")
    r.slab("chest", (0, 0.38, -0.458), (0, 0.29, -0.472), 0.925, 0.95, 0.06, "blue")
    for s in (1, -1):
        r.sphere("chest", (s * 0.27, 1.28, 0.29), 0.06, "gold")

    for side, s in (("l", 1), ("r", -1)):
        ua, la, wr, hd = (r.j(n + side) for n in ("upperarm.", "lowerarm.", "wrist.", "hand."))
        d = (hd - la).normalized()
        r.box("upperarm." + side, (s * 0.42, 1.24, 0), (0.36, 0.24, 0.44), "steel", bevel=0.08, seg=2)
        r.box("upperarm." + side, (s * 0.43, 1.12, 0), (0.38, 0.06, 0.46), "blue", bevel=0.015)
        r.limb("upperarm." + side, ua, la, 0.24, "cloth", pad_end=0.04)
        r.sphere("lowerarm." + side, la, 0.14, "steel_dark")
        r.limb("lowerarm." + side, la, wr, 0.27, "steel", pad_start=0.02, pad_end=0.02, bevel=0.04)
        r.limb("lowerarm." + side, wr - d * 0.03, wr + d * 0.02, 0.30, "blue")
        r.box("hand." + side, hd + Vector((s * 0.06, -0.02, 0)), (0.20, 0.24, 0.24), "steel_dark", bevel=0.05)
        ul, ll, ft = (r.j(n + side) for n in ("upperleg.", "lowerleg.", "foot."))
        r.limb("upperleg." + side, ul, ll, 0.26, "cloth", pad_start=0.04, pad_end=0.02)
        r.sphere("lowerleg." + side, ll + Vector((0, 0, 0.04)), 0.15, "steel")
        r.limb("lowerleg." + side, ll, ft, 0.25, "steel", pad_start=0.02, pad_end=0.02, bevel=0.03)
        boots(r, side, "steel_dark", (0.28, 0.20, 0.44))

    hc = r.j("head") + Vector((0, 0.48, 0.03))
    front = hc.z + 0.44
    r.box("head", hc, (0.95, 0.90, 0.88), "skin", bevel=0.14, seg=3, group="Head")
    chibi_face(r, front, hc.y - 0.10, brow_angle=12.0)
    # Helm: eine Schale um Oberkopf, Seiten und Hinterkopf (das Gesicht ragt vorn heraus), Stirnplatte, Nasenschutz
    r.box("head", (0, hc.y + 0.14, hc.z - 0.09), (1.08, 0.80, 0.94), "steel", bevel=0.16, seg=2, group="Head")
    r.box("head", (0, hc.y + 0.20, hc.z - 0.08), (1.10, 0.06, 0.96), "blue", bevel=0.02, group="Head")
    r.box("head", (0, hc.y + 0.31, front), (1.04, 0.22, 0.12), "steel", bevel=0.04, group="Head")
    r.box("head", (0, hc.y + 0.21, front + 0.065), (1.0, 0.05, 0.02), "blue", group="Head")
    r.box("head", (0, hc.y + 0.06, front + 0.035), (0.08, 0.28, 0.06), "steel_dark", bevel=0.01, group="Head")
    r.slab("head", (0, hc.y + 0.74, hc.z - 0.12), (0, hc.y + 0.46, hc.z - 0.04), 0.78, 0.52, 0.09, "blue", width_axis="z", group="Head")


def build_shadow(r):
    """Beweglichkeit/Schurke: schlanke Lederkleidung, Kapuze mit Futter, Maske, leuchtende Augen."""
    r.mat("leather", (0.25, 0.22, 0.24), roughness=0.6)
    r.mat("leather_dark", (0.14, 0.13, 0.16), roughness=0.65)
    r.mat("cloth", (0.34, 0.21, 0.48), roughness=0.85)
    r.mat("accent", hexrgb("#b67cff"), roughness=0.5)
    r.mat("strap", (0.46, 0.31, 0.20), roughness=0.75)
    r.mat("silver", (0.82, 0.84, 0.90), roughness=0.3, metallic=0.85)
    r.mat("eye_glow", hexrgb("#c48dff"), roughness=0.4, emission=hexrgb("#9d4dff"), strength=2.0)
    face_materials(r, (0.92, 0.74, 0.61))

    r.box("hips", (0, 0.50, 0), (0.64, 0.30, 0.52), "cloth", bevel=0.05)
    r.box("hips", (0, 0.65, 0), (0.68, 0.08, 0.56), "accent", bevel=0.02)
    r.box("hips", (0, 0.65, 0.29), (0.10, 0.10, 0.04), "silver")
    r.box("hips", (0.27, 0.54, 0.22), (0.16, 0.16, 0.12), "strap", bevel=0.03)
    r.box("chest", (0, 0.97, 0), (0.70, 0.66, 0.56), "leather", bevel=0.08, seg=2)
    r.box("chest", (0, 0.98, 0.285), (0.12, 0.92, 0.05), "strap", rot=(0, 0, 35))
    r.box("chest", (0.0, 0.98, 0.31), (0.09, 0.09, 0.04), "silver", rot=(0, 0, 35))
    r.box("chest", (0, 1.26, -0.02), (0.84, 0.28, 0.66), "cloth", bevel=0.09, seg=2)
    r.slab("chest", (0, 1.22, -0.29), (0, 0.60, -0.38), 0.62, 0.78, 0.05, "cloth")
    r.slab("chest", (0, 0.66, -0.371), (0, 0.59, -0.381), 0.765, 0.785, 0.06, "accent")

    for side, s in (("l", 1), ("r", -1)):
        ua, la, wr, hd = (r.j(n + side) for n in ("upperarm.", "lowerarm.", "wrist.", "hand."))
        d = (hd - la).normalized()
        r.limb("upperarm." + side, ua, la, 0.21, "cloth", pad_end=0.04)
        r.limb("lowerarm." + side, la, wr, 0.23, "leather_dark", pad_start=0.03, pad_end=0.02, bevel=0.03)
        r.limb("lowerarm." + side, wr - d * 0.03, wr + d * 0.02, 0.25, "accent")
        r.box("hand." + side, hd + Vector((s * 0.05, -0.02, 0)), (0.18, 0.20, 0.20), "leather_dark", bevel=0.05)
        ul, ll, ft = (r.j(n + side) for n in ("upperleg.", "lowerleg.", "foot."))
        r.limb("upperleg." + side, ul, ll, 0.23, "cloth", pad_start=0.04, pad_end=0.05)
        r.limb("lowerleg." + side, ll, ft, 0.22, "leather_dark", pad_start=0.03, pad_end=0.02, bevel=0.03)
        mid = (ll + ft) * 0.5
        r.limb("lowerleg." + side, mid + Vector((0, 0.025, 0)), mid - Vector((0, 0.025, 0)), 0.24, "strap")
        boots(r, side, "leather_dark", (0.24, 0.17, 0.40))

    hc = r.j("head") + Vector((0, 0.47, 0.03))
    front = hc.z + 0.43
    r.box("head", hc, (0.92, 0.88, 0.86), "skin", bevel=0.14, seg=3, group="Head")
    chibi_face(r, front, hc.y - 0.06, eye_size=(0.15, 0.11), eye_mat="eye_glow", highlight=False,
               brow_angle=16.0, brow_dy=0.12, brow_mat="leather_dark", nose=False, mouth=False, blush=False)
    r.box("head", (0, hc.y - 0.30, front - 0.08), (0.96, 0.36, 0.26), "leather_dark", bevel=0.04, group="Head")
    # Kapuze: stark gerundet, das Gesicht ragt vorn knapp heraus, hinten ein spitzer Zipfel
    r.box("head", (0, hc.y + 0.08, hc.z - 0.10), (1.06, 1.02, 1.00), "cloth", bevel=0.26, seg=3, group="Head")
    r.slab("head", (0, hc.y + 0.20, hc.z - 0.53), (0, hc.y - 0.62, hc.z - 0.66), 0.56, 0.08, 0.09, "cloth", group="Head")


def build_arcanist(r):
    """Intelligenz/Magier: Robe mit Saum, Glockenärmel, weißer Bart, Spitzhut mit geknickter Spitze."""
    r.mat("robe", (0.27, 0.24, 0.55), roughness=0.8)
    r.mat("robe_dark", (0.17, 0.15, 0.38), roughness=0.85)
    r.mat("accent", hexrgb("#ff9a4a"), roughness=0.5)
    r.mat("gold", (0.98, 0.78, 0.34), roughness=0.3, metallic=0.85)
    r.mat("leather", (0.45, 0.30, 0.19), roughness=0.75)
    r.mat("beard", (0.95, 0.95, 0.97), roughness=0.95)
    face_materials(r, (0.95, 0.77, 0.64))

    r.cone("hips", (0, 0.46, 0), 0.48, 0.38, 0.44, "robe", verts=10)
    r.cone("hips", (0, 0.27, 0), 0.495, 0.488, 0.06, "accent", verts=10)
    r.box("hips", (0, 0.69, 0), (0.78, 0.09, 0.64), "leather", bevel=0.02)
    r.box("hips", (0, 0.69, 0.33), (0.14, 0.12, 0.04), "gold", bevel=0.01)
    r.box("chest", (0, 0.99, 0), (0.76, 0.66, 0.60), "robe", bevel=0.10, seg=2)
    r.box("chest", (0, 0.98, 0.30), (0.14, 0.62, 0.04), "accent")
    r.box("chest", (0, 1.32, 0), (0.62, 0.12, 0.56), "accent", bevel=0.04)

    for side, s in (("l", 1), ("r", -1)):
        ua, la, hd = (r.j(n + side) for n in ("upperarm.", "lowerarm.", "hand."))
        d = (hd - la).normalized()
        r.limb("upperarm." + side, ua, la, 0.24, "robe", pad_end=0.03)
        r.limb_cone("lowerarm." + side, la, hd, 0.14, 0.22, "robe", pad_start=0.02)
        r.limb_cone("lowerarm." + side, hd - d * 0.03, hd + d * 0.015, 0.235, 0.235, "accent")
        r.box("hand." + side, hd + Vector((s * 0.07, -0.02, 0)), (0.19, 0.21, 0.21), "skin", bevel=0.05)
        ll, ft = r.j("lowerleg." + side), r.j("foot." + side)
        r.limb("lowerleg." + side, ll, ft, 0.20, "leather", pad_start=0.03, pad_end=0.02, bevel=0.03)
        boots(r, side, "leather", (0.24, 0.17, 0.38))

    hc = r.j("head") + Vector((0, 0.47, 0.03))
    front = hc.z + 0.43
    eye_y = hc.y - 0.06
    r.box("head", hc, (0.94, 0.88, 0.86), "skin", bevel=0.14, seg=3, group="Head")
    chibi_face(r, front, eye_y, brow_angle=-12.0, brow_size=(0.24, 0.08), brow_mat="beard", mouth=False)
    r.box("head", (0, eye_y - 0.20, front + 0.03), (0.46, 0.10, 0.12), "beard", bevel=0.04, group="Head")
    r.box("head", (0, hc.y - 0.52, front - 0.12), (0.74, 0.60, 0.34), "beard", bevel=0.12, seg=2, group="Head")
    r.cone("head", (0, hc.y - 0.92, front - 0.14), 0.03, 0.26, 0.24, "beard", verts=8, group="Head")
    r.box("head", (0, hc.y - 0.04, hc.z - 0.24), (1.0, 0.70, 0.46), "beard", bevel=0.12, seg=2, group="Head")
    hat_z = hc.z - 0.02
    r.cone("head", (0, hc.y + 0.40, hat_z), 0.80, 0.74, 0.06, "robe_dark", verts=16, group="Head")
    r.cone("head", (0, hc.y + 0.73, hat_z), 0.50, 0.24, 0.60, "robe", group="Head")
    r.cone("head", (0, hc.y + 0.49, hat_z), 0.515, 0.49, 0.11, "accent", group="Head")
    r.box("head", (0, hc.y + 0.49, hat_z + 0.505), (0.10, 0.10, 0.04), "gold", rot=(0, 0, 45), group="Head")
    r.cone("head", (0, hc.y + 1.17, hat_z - 0.12), 0.245, 0.02, 0.46, "robe", rot=(-35, 0, 0), group="Head")


HEROES = {
    "guardian": {
        "source": "assets/models/heroes/Knight.glb",
        "remove": ["Knight_Body", "Knight_Head", "Knight_ArmLeft", "Knight_ArmRight", "Knight_LegLeft", "Knight_LegRight",
                   "Knight_Helmet", "Knight_Cape"],
        "prefix": "Guardian",
        "build": build_guardian,
    },
    "shadow": {
        "source": "assets/models/heroes/Rogue_Hooded.glb",
        "remove": ["Rogue_Body", "Rogue_Head_Hooded", "Rogue_ArmLeft", "Rogue_ArmRight", "Rogue_LegLeft", "Rogue_LegRight",
                   "Rogue_Cape"],
        "prefix": "Shadow",
        "build": build_shadow,
    },
    "arcanist": {
        "source": "assets/models/heroes/Mage.glb",
        "remove": ["Mage_Body", "Mage_Head", "Mage_ArmLeft", "Mage_ArmRight", "Mage_LegLeft", "Mage_LegRight",
                   "Mage_Hat", "Mage_Cape"],
        "prefix": "Arcanist",
        "build": build_arcanist,
    },
}


def build_hero(hero_id):
    cfg = HEROES[hero_id]
    log("=== %s ===" % hero_id)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    # Die KayKit-Animationen sind mit 30 fps erstellt; bei Blenders Standard (24 fps) wuerden sie beim
    # Export neu abgetastet und um einen Bruchteil eines Frames kuerzer.
    bpy.context.scene.render.fps = 30
    bpy.context.scene.render.fps_base = 1.0
    bpy.ops.import_scene.gltf(filepath=os.path.join(PROJECT, cfg["source"]))
    armature = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
    r = Rig(armature, cfg["prefix"])
    log("Huefte (Spielraum): %s, Zehen links: %s" % (tuple(round(v, 3) for v in r.j("hips")), tuple(round(v, 3) for v in r.j("toes.l"))))

    for name in cfg["remove"]:
        obj = bpy.data.objects.get(name)
        if obj is None:
            log("WARNUNG: zu entfernendes Objekt fehlt: %s" % name)
            continue
        bpy.data.objects.remove(obj, do_unlink=True)

    cfg["build"](r)
    r.join_all()

    os.makedirs(OUT_DIR, exist_ok=True)
    out_path = os.path.join(OUT_DIR, cfg["prefix"] + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format="GLB",
        use_selection=False,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_skins=True,
        export_def_bones=False,
        export_yup=True,
    )
    log("exportiert -> %s" % out_path)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for hero_id in (argv or list(HEROES.keys())):
        build_hero(hero_id)
    log("fertig.")


if __name__ == "__main__":   # beim Import (z. B. aus blender_build_enemies.py) nichts bauen
    main()
