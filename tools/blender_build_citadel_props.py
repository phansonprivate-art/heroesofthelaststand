"""Modelle der Karte „Zitadelle des Lichts“ (Issue #4), alle per Skript: Brücke, Zitadellenturm, Torhaus mit
Fallgitter, Wachturm mit Kristall, Portalbogen, Start-Plattform, Schrein, Händlerhaus, Bäume, Felsen, Klippen,
Abgrund-Kristalle. Steinteile mit gebackener Quadertextur (wie der Brunnen), Rest mit Farbmaterialien.

Blender-Raum: Ursprung = Mitte am Boden, „vorn“ (Lane-/Blickrichtung) = -Y (glTF +Z).
Objekte mit festen Namen (Crystal, Portcullis, Flame) steuert das Spiel (drehen, ausblenden).

Aufruf (Blender 5.2, ohne Oberfläche):
  blender.exe --background --python tools/blender_build_citadel_props.py -- [nur <name> ...] [--preview <ordner>]
Ausgabe: assets/models/environment_custom/<Name>.glb
"""
import math
import os
import random
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import blender_build_dragon as bd
import blender_build_fountain as bf

OUT_DIR = os.path.join(bd.PROJECT, "assets", "models", "environment_custom")
V = Vector
log = lambda msg: print("[citadel] %s" % msg, flush=True)


# --- Bausteine ------------------------------------------------------------------------------------------

def mesh_obj(name, bm, smooth=False):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = smooth
    return bd.link(bpy.data.objects.new(name, me))


def box(bm, center, size, rot_z=0.0, rot=None):
    res = bmesh.ops.create_cube(bm, size=1.0)
    turn = rot if rot is not None else Matrix.Rotation(rot_z, 4, "Z")
    m = Matrix.Translation(V(center)) @ turn @ Matrix.Diagonal((*size, 1.0))
    bmesh.ops.transform(bm, matrix=m, verts=res["verts"])
    return res["verts"]


def cone(bm, center, r1, r2, depth, segs=8, rot=None):
    res = bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r1, radius2=r2, depth=depth)
    m = Matrix.Translation(V(center)) @ (rot if rot is not None else Matrix.Identity(4))
    bmesh.ops.transform(bm, matrix=m, verts=res["verts"])
    return res["verts"]


def ico(bm, center, radius, scale=(1, 1, 1), subdiv=1, jitter=0.0, rng=None):
    res = bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=radius)
    for v in res["verts"]:
        if jitter and rng is not None:
            v.co *= 1.0 + rng.uniform(-jitter, jitter)
        v.co = V((v.co.x * scale[0], v.co.y * scale[1], v.co.z * scale[2])) + V(center)
    return res["verts"]


def color_mat(name, hex_color, rough=0.8, metal=0.0, emit=None, strength=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*bd.hex_lin(hex_color), 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emit:
        bsdf.inputs["Emission Color"].default_value = (*bd.hex_lin(emit), 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    return mat


def stone(obj, name, tint="#9aa1ad", size=1024):
    """Gebackene Steinquader-Textur (aus dem Brunnen-Bauplan) mit eigener Grundfarbe."""
    import numpy as np
    bd.unwrap(obj, margin=0.004)
    bd.setup_bake_engine()
    mat = bf.stone_bake_material()
    nt = mat.node_tree
    for n in nt.nodes:   # Grundfarbe tauschen (Mix-Knoten mit Farbe B)
        if n.bl_idname == "ShaderNodeMix" and n.data_type == "RGBA" and not n.inputs[7].is_linked:
            n.inputs[7].default_value = (*bd.hex_lin(tint), 1.0)
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    albedo, normal = bd.new_image(name + "_albedo", size), bd.new_image(name + "_normal", size, non_color=True)
    ao = bd.new_image(name + "_ao", size, non_color=True)
    bd.bake(obj, mat, albedo, "DIFFUSE", pass_filter={"COLOR"})
    bd.bake(obj, mat, normal, "NORMAL", normal_space="TANGENT")
    bd.bake(obj, mat, ao, "AO", samples=32)
    alb = bd.pixels(albedo)
    alb[..., :3] *= 0.45 + 0.55 * np.clip(bd.pixels(ao)[..., :1], 0, 1)
    bd.set_pixels(albedo, alb)
    bd.save_image(albedo)
    bd.save_image(normal)
    obj.data.materials.clear()
    obj.data.materials.append(bd.final_material(name, albedo, normal, roughness=0.85))


def export(name):
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=False, export_yup=True)
    log("%s -> %s" % (name, path))


def battlements(bm, radius, z, count, size=(0.45, 0.35, 0.45)):
    for k in range(count):
        a = 2 * math.pi * k / count
        box(bm, (radius * math.cos(a), radius * math.sin(a), z + size[2] / 2), size, a)


# --- Bauwerke -------------------------------------------------------------------------------------------

def build_bridge():
    """Steinbrücke: Fahrbahn 8 m breit, 11 m lang (entlang -Y), Brüstungen mit Pfosten, Bogen darunter."""
    bm = bmesh.new()
    box(bm, (0, 0, -0.1), (8.0, 11.0, 0.44))                     # Fahrbahn (Oberkante knapp über dem Boden)
    for s in (-1, 1):
        box(bm, (s * 4.25, 0, 0.35), (0.5, 11.0, 0.7))           # Brüstung
        for y in (-5.2, -2.6, 0.0, 2.6, 5.2):
            box(bm, (s * 4.25, y, 0.55), (0.7, 0.7, 1.1))       # Pfosten
        for k in range(9):                                        # Bogen unter der Fahrbahn (Seitenansicht)
            a = math.pi * k / 8
            box(bm, (s * 3.6, -math.cos(a) * 3.8, -0.4 - math.sin(a) * 1.3), (0.6, 1.0, 0.9))
    obj = mesh_obj("Bridge", bm)
    stone(obj, "Bridge", "#a29a8c")
    export("Bridge")


def build_citadel_tower():
    """Runder Mauerturm (Ecke des Zitadellenrings): Zinnen und eine Feuerschale obendrauf."""
    prof = [(0, 0), (2.0, 0), (1.9, 0.6), (1.75, 5.6), (2.05, 5.8), (2.05, 6.3), (0, 6.3)]
    body = bf.lathe("TowerBody", prof, 12, False)
    bm = bmesh.new()
    battlements(bm, 1.85, 6.3, 10)
    merl = mesh_obj("TowerMerlons", bm)
    stone_obj = bd.join([body, merl], "CitadelTower")
    stone(stone_obj, "CitadelTower", "#b9b4a8")
    bowl = bf.lathe("Brazier", [(0, 6.3), (0.25, 6.3), (0.55, 6.85), (0.45, 6.9), (0, 6.75)], 10, True)
    bowl.data.materials.append(color_mat("Iron", "#2b2a2e", 0.5, 0.8))
    bm = bmesh.new()
    cone(bm, (0, 0, 7.25), 0.38, 0.0, 0.9, 7)
    flame = mesh_obj("Flame", bm, True)
    flame.data.materials.append(color_mat("Flame", "#ffb347", 0.6, 0.0, "#ff8a1c", 6.0))
    export("CitadelTower")


def build_gatehouse():
    """Torhaus wie im Konzeptbild: zwei quadratische Tortürme (Mitte ±4,29 m entlang X) mit Zinnen, dazwischen die
    Tormauer mit Rundbogen und Fallgitter (eigenes Objekt „Portcullis“: bricht ein, wenn das Torhaus fällt).
    Front (Feindseite) = -Y."""
    bm = bmesh.new()
    tower_x, tower_w, tower_h = 4.29, 3.2, 7.0
    for s in (-1, 1):
        cx = s * tower_x
        box(bm, (cx, 0, 0.3), (tower_w + 0.4, tower_w + 0.4, 0.6))                 # Sockel
        box(bm, (cx, 0, tower_h / 2), (tower_w, tower_w, tower_h))
        box(bm, (cx, 0, tower_h + 0.15), (tower_w + 0.3, tower_w + 0.3, 0.3))      # Kranz
        for k in range(4):                                                           # Zinnen rundum
            off = -tower_w / 2 + 0.3 + k * (tower_w - 0.6) / 3
            for x, y in ((cx + off, -tower_w / 2), (cx + off, tower_w / 2), (cx - tower_w / 2, off), (cx + tower_w / 2, off)):
                box(bm, (x, y, tower_h + 0.6), (0.55, 0.55, 0.6))
    gate_w, gate_h, wall_h, depth = 2 * tower_x - tower_w, 3.4, 5.6, 2.4
    open_w = gate_w - 1.0
    for s in (-1, 1):                                                                # Pfeiler neben der Öffnung
        box(bm, (s * (open_w / 2 + 0.25), 0, wall_h / 2), (0.5, depth, wall_h))
    box(bm, (0, 0, (wall_h + gate_h + 1.0) / 2), (gate_w, depth, wall_h - gate_h - 1.0))
    r = open_w / 2
    for k in range(10):                                                              # Zwickel zwischen Bogen und Sturz
        x = -r + (k + 0.5) * open_w / 10
        z0 = gate_h + math.sqrt(max(0.0, 1.0 - (x / r) ** 2)) * 1.0
        box(bm, (x, 0, (z0 + gate_h + 1.05) / 2), (open_w / 10 + 0.02, depth, gate_h + 1.05 - z0 + 0.02))
    for k in range(11):                                                              # Bogensteine, der Kurve nach gedreht
        a = math.pi * k / 10
        tx, tz = math.sin(a) * r, math.cos(a) * 1.0
        box(bm, (-math.cos(a) * r, 0, gate_h + math.sin(a) * 1.0), (0.6, depth + 0.2, 0.5),
            rot=Matrix.Rotation(math.atan2(-tz, tx), 4, "Y"))
    for y in (-depth / 2 + 0.22, depth / 2 - 0.22):                                  # Zinnen der Tormauer
        for k in range(5):
            box(bm, (-gate_w / 2 + 0.45 + k * (gate_w - 0.9) / 4, y, wall_h + 0.3), (0.55, 0.44, 0.6))
    obj = mesh_obj("Gatehouse", bm)
    stone(obj, "Gatehouse", "#a9a69e")
    bm = bmesh.new()
    for k in range(6):                                                               # Fallgitter
        x = -open_w / 2 + 0.35 + k * (open_w - 0.7) / 5
        box(bm, (x, -0.5, gate_h / 2 + 0.3), (0.12, 0.12, gate_h + 0.6))
        cone(bm, (x, -0.5, 0.15), 0.08, 0.0, 0.3, 4, Matrix.Rotation(math.pi, 4, "X"))
    for z in (0.6, 1.5, 2.4, 3.3):
        box(bm, (0, -0.5, z), (open_w - 0.4, 0.1, 0.12))
    grid = mesh_obj("Portcullis", bm)
    grid.data.materials.append(color_mat("Iron", "#2b2a2e", 0.45, 0.85))
    bm = bmesh.new()
    for s in (-1, 1):                                                                # rote Banner an den Turmfronten
        box(bm, (s * tower_x, -tower_w / 2 - 0.05, 4.4), (1.3, 0.05, 2.8))
    banner = mesh_obj("GateBanners", bm)
    banner.data.materials.append(color_mat("Banner", "#a3262a", 0.85))
    bm = bmesh.new()
    for s in (-1, 1):                                                                # Schießscharten
        for z in (2.2, 5.8):
            box(bm, (s * tower_x, -tower_w / 2 - 0.02, z), (0.22, 0.05, 0.8))
    slits = mesh_obj("Slits", bm)
    slits.data.materials.append(color_mat("Dark", "#141214", 0.9))
    export("Gatehouse")


def build_guard_tower():
    """Wachturm an den Lanes: schlanker Steinturm, offene Plattform mit Feuerschale, darüber eine schwebende Glut
    („Crystal“: dreht sich im Spiel und ist die Schussquelle) – orange wie die Türme im Konzeptbild."""
    prof = [(0, 0), (1.6, 0), (1.55, 0.5), (1.25, 1.0), (1.05, 4.6), (1.5, 4.9), (1.5, 5.3), (0, 5.3)]
    body = bf.lathe("GuardBody", prof, 10, False)
    bm = bmesh.new()
    battlements(bm, 1.35, 5.3, 8, (0.4, 0.3, 0.4))
    for k in range(4):                                            # Stützpfeiler am Fuß
        a = math.pi / 4 + k * math.pi / 2
        box(bm, (1.45 * math.cos(a), 1.45 * math.sin(a), 0.7), (0.45, 0.45, 1.4), a)
    merl = mesh_obj("GuardMerlons", bm)
    st = bd.join([body, merl], "GuardTower")
    stone(st, "GuardTower", "#aeb3bd")
    bm = bmesh.new()
    top, bot = bm.verts.new((0, 0, 7.0)), bm.verts.new((0, 0, 5.9))
    ring = [bm.verts.new((0.32 * math.cos(a), 0.32 * math.sin(a), 6.45)) for a in [2 * math.pi * k / 6 for k in range(6)]]
    for k in range(6):
        bm.faces.new((ring[k], ring[(k + 1) % 6], top))
        bm.faces.new((ring[(k + 1) % 6], ring[k], bot))
    crystal = mesh_obj("Crystal", bm)
    crystal.data.materials.append(color_mat("TowerEmber", "#ffc070", 0.3, 0.0, "#ff7a1c", 6.0))
    bowl = bf.lathe("EmberBowl", [(0, 5.3), (0.3, 5.3), (0.7, 5.75), (0.6, 5.8), (0, 5.65)], 10, True)
    bowl.data.materials.append(color_mat("Iron", "#2b2a2e", 0.5, 0.8))
    export("GuardTower")


def build_portal():
    """Portalbogen aus dunklem Vulkangestein: Steinkreis (Ø 6 m) auf Stufen; der Wirbel kommt im Spiel dazu."""
    bm = bmesh.new()
    for k in range(22):                                            # Ringsteine, entlang des Kreises gedreht
        a = 2 * math.pi * k / 22
        x, z = math.cos(a) * 3.0, 3.2 + math.sin(a) * 3.0
        if z < 1.0:
            continue
        box(bm, (x, 0, z), (0.92, 1.1, 0.85), rot=Matrix.Rotation(-(a + math.pi / 2), 4, "Y"))
    for k in range(0, 22, 2):                                      # dornige Spitzen außen am Ring
        a = 2 * math.pi * k / 22
        if math.sin(a) < -0.2:
            continue
        cone(bm, (math.cos(a) * 3.75, 0, 3.2 + math.sin(a) * 3.75), 0.28, 0.0, 0.9, 5,
             Matrix.Rotation(-(a - math.pi / 2), 4, "Y"))
    for s in (-1, 1):
        box(bm, (s * 3.0, 0, 0.6), (1.4, 1.6, 1.2))               # Sockel links/rechts
    box(bm, (0, 0, 0.15), (8.0, 3.0, 0.3))                         # Stufe
    obj = mesh_obj("Portal", bm)
    stone(obj, "Portal", "#4a3640")
    bm = bmesh.new()
    rng = random.Random(4)
    for k in range(5):                                             # glühende Splitter am Fuß
        a = rng.uniform(0, 2 * math.pi)
        cone(bm, (math.cos(a) * 3.6, math.sin(a) * 1.4, 0.5), 0.25, 0.0, 1.2, 5, Matrix.Rotation(rng.uniform(-0.4, 0.4), 4, "X"))
    shards = mesh_obj("PortalShards", bm)
    shards.data.materials.append(color_mat("PortalShard", "#3a1830", 0.3, 0.0, "#c048ff", 3.0))
    export("Portal")


def build_hero_pad():
    pad = bf.lathe("HeroPad", [(0, 0), (1.3, 0), (1.35, 0.08), (1.25, 0.16), (0, 0.16)], 16, False)
    stone(pad, "HeroPad", "#b9c0cc", 512)
    rune = bf.lathe("PadRune", [(1.0, 0.165), (1.08, 0.17), (1.08, 0.18), (1.0, 0.175)], 32, True)
    rune.data.materials.append(color_mat("PadRune", "#9fd8ff", 0.3, 0.0, "#4fb6ff", 3.0))
    disc = bf.lathe("PadDisc", [(0, 0.162), (0.98, 0.162), (0.98, 0.166), (0, 0.166)], 32, True)   # blaue Scheibe wie im Bild
    disc.data.materials.append(color_mat("PadBlue", "#24519e", 0.5, 0.0, "#1f4fb0", 0.6))
    bm = bmesh.new()                                                  # Schwert-Emblem
    box(bm, (0, -0.15, 0.172), (0.16, 1.05, 0.012))                     # Klinge
    cone(bm, (0, -0.74, 0.172), 0.08, 0.0, 0.25, 4, Matrix.Rotation(math.pi / 2, 4, "X"))
    box(bm, (0, 0.4, 0.172), (0.62, 0.11, 0.012))                       # Parierstange
    box(bm, (0, 0.6, 0.172), (0.11, 0.32, 0.012))                       # Griff
    box(bm, (0, 0.8, 0.172), (0.18, 0.12, 0.012))                       # Knauf
    sword = mesh_obj("PadSword", bm)
    sword.data.materials.append(color_mat("PadSword", "#eef6ff", 0.3, 0.0, "#cfe6ff", 2.2))
    export("HeroPad")


def build_shrine():
    """Schrein am Flussufer: Steinsockel, Runenband, schwebender grüner Kristall („Crystal“)."""
    base = bf.lathe("ShrineBase", [(0, 0), (1.1, 0), (1.05, 0.25), (0.6, 0.4), (0.45, 1.1), (0.7, 1.3), (0, 1.3)], 8, False)
    stone(base, "Shrine", "#9fa79a", 512)
    rune = bf.lathe("ShrineRune", [(0.462, 0.7), (0.47, 0.72), (0.47, 0.82), (0.462, 0.84)], 8, False)
    rune.data.materials.append(color_mat("ShrineRune", "#bfffd8", 0.3, 0.0, "#5dffa8", 2.5))
    bm = bmesh.new()
    top, bot = bm.verts.new((0, 0, 2.45)), bm.verts.new((0, 0, 1.55))
    ring = [bm.verts.new((0.26 * math.cos(a), 0.26 * math.sin(a), 2.0)) for a in [2 * math.pi * k / 6 for k in range(6)]]
    for k in range(6):
        bm.faces.new((ring[k], ring[(k + 1) % 6], top))
        bm.faces.new((ring[(k + 1) % 6], ring[k], bot))
    crystal = mesh_obj("Crystal", bm)
    crystal.data.materials.append(color_mat("ShrineCrystal", "#c8ffe0", 0.05, 0.0, "#5dffa8", 4.0))
    export("Shrine")


def build_shop():
    """Händlerposten: Steinsockel, Fachwerkhaus mit Satteldach, gestreifte Markise über der Theke (Front = -Y)."""
    bm = bmesh.new()
    box(bm, (0, 0, 0.25), (6.0, 4.6, 0.5))
    base = mesh_obj("ShopBase", bm)
    stone(base, "ShopBase", "#a7a296", 512)
    bm = bmesh.new()
    box(bm, (0, 0.3, 1.9), (5.2, 3.4, 2.8))
    walls = mesh_obj("ShopWalls", bm)
    walls.data.materials.append(color_mat("Plaster", "#d9cdb3", 0.9))
    bm = bmesh.new()
    for x in (-2.55, -0.9, 0.9, 2.55):                            # Fachwerkbalken
        box(bm, (x, -1.42, 1.9), (0.22, 0.12, 2.8))
    box(bm, (0, -1.42, 3.25), (5.3, 0.14, 0.22))
    box(bm, (0, -2.2, 1.0), (4.2, 0.6, 1.0))                       # Theke
    for x in (-2.0, 2.0):
        box(bm, (x, -2.6, 1.6), (0.15, 0.15, 2.2))                 # Markisenpfosten
    timber = mesh_obj("ShopTimber", bm)
    timber.data.materials.append(color_mat("Timber", "#5a3a22", 0.8))
    bm = bmesh.new()
    verts = [bm.verts.new(p) for p in [(-2.9, -1.6, 3.3), (2.9, -1.6, 3.3), (2.9, 2.2, 3.3), (-2.9, 2.2, 3.3),
                                       (-2.9, 0.3, 4.9), (2.9, 0.3, 4.9)]]
    for f in [(0, 1, 5, 4), (2, 3, 4, 5), (0, 4, 3), (1, 2, 5), (0, 3, 2, 1)]:
        bm.faces.new([verts[i] for i in f])
    roof = mesh_obj("ShopRoof", bm)
    roof.data.materials.append(color_mat("Roof", "#7a2b22", 0.85))
    bm = bmesh.new()
    for k in range(6):                                             # gestreifte Markise
        x = -2.1 + k * 0.84
        box(bm, (x + 0.21, -2.6, 2.75), (0.42, 1.3, 0.06))
    awning_a = mesh_obj("AwningA", bm)
    awning_a.data.materials.append(color_mat("AwningRed", "#b8352a", 0.9))
    bm = bmesh.new()
    for k in range(6):
        x = -2.1 + k * 0.84
        box(bm, (x + 0.63, -2.6, 2.75), (0.42, 1.3, 0.06))
    awning_b = mesh_obj("AwningB", bm)
    awning_b.data.materials.append(color_mat("AwningCream", "#efe2c4", 0.9))
    export("ShopHouse")


# --- Natur ----------------------------------------------------------------------------------------------

def build_trees():
    rng = random.Random(7)
    # Nadelbaum: Stamm und drei Kegel
    bm = bmesh.new()
    cone(bm, (0, 0, 1.0), 0.28, 0.2, 2.0, 7)
    trunk = mesh_obj("Trunk", bm)
    trunk.data.materials.append(color_mat("Bark", "#4e3423", 0.9))
    bm = bmesh.new()
    for z, r, h in ((2.4, 2.2, 2.6), (3.8, 1.7, 2.3), (5.0, 1.15, 2.0)):
        cone(bm, (0, 0, z), r, 0.15, h, 9)
    leaves = mesh_obj("Needles", bm)
    leaves.data.materials.append(color_mat("Needles", "#1f4520", 0.85))   # dunkel wie der Dschungel im Bild
    export("TreePine")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    # Laubbaum: Stamm mit Ästen und Kronenballen
    bm = bmesh.new()
    cone(bm, (0, 0, 1.3), 0.36, 0.24, 2.6, 7)
    for a in (0.5, 2.6, 4.4):
        cone(bm, (math.cos(a) * 0.5, math.sin(a) * 0.5, 2.6), 0.14, 0.08, 1.4, 5,
             Matrix.Rotation(0.7, 4, V((-math.sin(a), math.cos(a), 0))))
    trunk = mesh_obj("Trunk", bm)
    trunk.data.materials.append(color_mat("Bark", "#5a3d27", 0.9))
    bm = bmesh.new()
    for c, r in (((0, 0, 4.0), 1.8), ((1.1, 0.4, 3.5), 1.3), ((-1.0, -0.5, 3.6), 1.3), ((0.2, -1.0, 3.3), 1.1), ((-0.3, 0.9, 4.4), 1.2)):
        ico(bm, c, r, (1, 1, 0.85), 1, 0.12, rng)
    crown = mesh_obj("Crown", bm)
    crown.data.materials.append(color_mat("Leaves", "#2c5a22", 0.85))
    export("TreeOak")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    # Toter Baum (Abgrund): verdrehter Stamm mit kahlen Ästen
    bm = bmesh.new()
    cone(bm, (0, 0, 1.6), 0.32, 0.12, 3.2, 6, Matrix.Rotation(0.12, 4, "X"))
    for a, tilt, z, length in ((0.3, 0.9, 2.2, 1.6), (2.2, 1.0, 2.7, 1.3), (4.1, 0.8, 1.9, 1.5), (5.3, 1.1, 3.0, 1.0)):
        axis = V((-math.sin(a), math.cos(a), 0))
        cone(bm, (math.cos(a) * 0.45, math.sin(a) * 0.45, z + 0.3), 0.1, 0.02, length, 5, Matrix.Rotation(tilt, 4, axis))
    dead = mesh_obj("DeadTree", bm)
    dead.data.materials.append(color_mat("DeadBark", "#2a2326", 0.95))
    export("TreeDead")


def build_rocks():
    rng = random.Random(11)
    bm = bmesh.new()
    ico(bm, (0, 0, 0.5), 1.0, (1.3, 1.0, 0.75), 1, 0.22, rng)
    ico(bm, (0.9, 0.5, 0.3), 0.55, (1, 1, 0.8), 1, 0.25, rng)
    rock = mesh_obj("Rock", bm)
    rock.data.materials.append(color_mat("Rock", "#7c7a76", 0.9))
    export("Rock")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bm = bmesh.new()   # Klippenfels: hoch und breit für den Kartenrand
    for k in range(4):
        ico(bm, (k * 1.8 - 2.7, rng.uniform(-0.4, 0.4), 1.6 + rng.uniform(-0.3, 0.5)), 1.6, (1.0, 1.0, 1.6), 1, 0.25, rng)
    cliff = mesh_obj("Cliff", bm)
    cliff.data.materials.append(color_mat("CliffRock", "#6c6a68", 0.9))
    export("Cliff")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bm = bmesh.new()   # Abgrund-Kristalle: dunkle Spitzen mit glühendem Kern
    for k in range(5):
        a = k * 1.3
        cone(bm, (math.cos(a) * 0.6, math.sin(a) * 0.6, 0.9), 0.35, 0.0, 1.8 + 0.4 * (k % 2), 5,
             Matrix.Rotation(0.35, 4, V((-math.sin(a), math.cos(a), 0))))
    spikes = mesh_obj("AbyssSpikes", bm)
    spikes.data.materials.append(color_mat("AbyssCrystal", "#251420", 0.25, 0.0, "#ff4a1c", 1.6))
    export("AbyssSpikes")


# --- Weitere Bauten und Kulisse nach dem Konzeptbild ----------------------------------------------------

def build_barracks():
    """Kaserne (bildet später eigene Diener aus): langes Fachwerkhaus auf Steinsockel, rotes Satteldach mit
    Schornstein, Tor in der Front (-Y), Waffenständer, Fässer und ein rotes Banner."""
    bm = bmesh.new()
    box(bm, (0, 0, 0.3), (7.8, 5.4, 0.6))
    box(bm, (2.6, 1.0, 4.4), (0.7, 0.7, 2.2))                                   # Schornstein
    base = mesh_obj("BarracksStone", bm)
    stone(base, "BarracksStone", "#9d998f", 512)
    bm = bmesh.new()
    box(bm, (0, 0, 1.95), (7.0, 4.6, 2.7))
    walls = mesh_obj("BarracksWalls", bm)
    walls.data.materials.append(color_mat("Plaster", "#d6c9ae", 0.9))
    bm = bmesh.new()
    for x in (-3.45, -1.75, 0.0, 1.75, 3.45):                                    # Fachwerk vorn und hinten
        for y in (-2.32, 2.32):
            box(bm, (x, y, 1.95), (0.22, 0.12, 2.7))
    for y in (-2.32, 2.32):
        box(bm, (0, y, 3.2), (7.1, 0.14, 0.22))
        box(bm, (0, y, 0.7), (7.1, 0.14, 0.2))
    for s in (-1, 1):                                                            # Fachwerk an den Giebeln
        box(bm, (s * 3.52, 0, 1.95), (0.12, 0.22, 2.7))
    box(bm, (0, -2.4, 1.35), (1.6, 0.1, 2.3))                                    # Tor
    for x in (-2.6, -1.0):                                                       # Waffenständer: Pfosten und Speere
        box(bm, (x, -3.1, 0.9), (0.12, 0.12, 1.4))
    box(bm, (-1.8, -3.1, 1.45), (1.7, 0.1, 0.1))
    for k in range(4):
        box(bm, (-2.3 + k * 0.33, -3.12, 1.25), (0.05, 0.05, 2.1))
    timber = mesh_obj("BarracksTimber", bm)
    timber.data.materials.append(color_mat("Timber", "#5a3a22", 0.8))
    bm = bmesh.new()
    verts = [bm.verts.new(p) for p in [(-3.9, -2.75, 3.25), (3.9, -2.75, 3.25), (3.9, 2.75, 3.25), (-3.9, 2.75, 3.25),
                                       (-3.9, 0.0, 5.3), (3.9, 0.0, 5.3)]]
    for f in [(0, 1, 5, 4), (2, 3, 4, 5), (0, 4, 3), (1, 2, 5), (0, 3, 2, 1)]:
        bm.faces.new([verts[i] for i in f])
    roof = mesh_obj("BarracksRoof", bm)
    roof.data.materials.append(color_mat("Roof", "#8a2d22", 0.85))
    bm = bmesh.new()
    for x, y in ((2.4, -3.0), (2.95, -3.2), (2.65, -3.65)):                      # Fässer
        cone(bm, (x, y, 0.45), 0.32, 0.32, 0.9, 8)
    barrels = mesh_obj("Barrels", bm)
    barrels.data.materials.append(color_mat("BarrelWood", "#6b4527", 0.85))
    bm = bmesh.new()
    box(bm, (-4.3, -1.6, 2.4), (0.1, 0.1, 4.8))                                  # Bannermast mit rotem Banner
    box(bm, (-4.3, -2.05, 3.8), (0.05, 0.9, 1.6))
    flag = mesh_obj("BarracksBanner", bm)
    flag.data.materials.append(color_mat("Banner", "#a3262a", 0.85))
    export("Barracks")


def build_ruins():
    """Ruinen im Dschungel: abgebrochene Säulen (eine umgestürzt), ein Mauerrest mit gezackter Kante, ein halber
    Bogen und Schutt – bemooster grauer Stein."""
    rng = random.Random(21)
    bm = bmesh.new()
    for (x, y), h in (((-1.8, -1.2), 3.4), ((-1.8, 1.4), 2.1), ((1.6, 1.6), 1.2), ((2.2, -1.0), 0.7)):
        cone(bm, (x, y, h / 2), 0.42, 0.38, h, 10)
        box(bm, (x, y, 0.15), (1.0, 1.0, 0.3))                                   # Sockel
        if h > 2.0:
            box(bm, (x, y, h + 0.12), (0.95, 0.95, 0.25), rng.uniform(0, 0.4))   # Kapitell
    cone(bm, (0.6, -2.4, 0.38), 0.4, 0.4, 3.0, 10, Matrix.Rotation(math.pi / 2, 4, "Y") @ Matrix.Rotation(0.3, 4, "X"))
    for k in range(6):                                                           # Mauerrest mit gezackter Oberkante
        h = [2.6, 2.2, 1.6, 2.0, 1.1, 0.6][k]
        box(bm, (-1.0 + k * 0.6, 3.0, h / 2), (0.62, 0.7, h))
    for k in range(5):                                                           # halber Bogen auf einem Pfeiler
        a = math.pi * k / 8
        box(bm, (3.2 - math.cos(a) * 1.4, -2.8, 2.6 + math.sin(a) * 1.4), (0.5, 0.6, 0.45),
            rot=Matrix.Rotation(-a + math.pi / 2, 4, "Y"))
    box(bm, (1.8, -2.8, 1.3), (0.6, 0.7, 2.6))
    for _ in range(14):                                                          # Schutt
        box(bm, (rng.uniform(-3, 3.5), rng.uniform(-3, 3), 0.15), (rng.uniform(0.3, 0.7), rng.uniform(0.3, 0.6), rng.uniform(0.2, 0.4)),
            rng.uniform(0, math.pi))
    obj = mesh_obj("Ruins", bm)
    stone(obj, "Ruins", "#8d9487", 1024)
    export("Ruins")


def build_mountain():
    """Berg für den Nordrand: gezackter Felsstock (~14 m breit, ~13 m hoch) aus gestreckten Felsbrocken."""
    rng = random.Random(5)
    bm = bmesh.new()
    ico(bm, (0, 0, 5.5), 4.2, (1.0, 0.9, 2.0), 2, 0.22, rng)                   # Hauptgipfel
    for x, y, r, h in ((-4.2, 1.0, 3.0, 1.4), (4.0, -0.8, 3.2, 1.5), (-1.8, -3.2, 2.6, 1.2), (2.2, 3.0, 2.4, 1.3), (-5.5, -2.0, 2.0, 0.9),
                       (5.6, 2.2, 2.1, 0.9)):
        ico(bm, (x, y, r * h * 0.9), r, (1.0, 1.0, h * 1.3), 1, 0.25, rng)
    obj = mesh_obj("Mountain", bm)
    obj.data.materials.append(color_mat("MountainRock", "#7a7772", 0.92))
    bm = bmesh.new()                                                             # helle Kanten am Gipfel (Schnee-/Kalkstreifen)
    ico(bm, (0.3, -0.2, 11.2), 1.5, (1.0, 0.9, 1.0), 1, 0.3, rng)
    cap = mesh_obj("MountainCap", bm)
    cap.data.materials.append(color_mat("MountainCap", "#b9b6ae", 0.9))
    export("Mountain")


def build_abyss_rock():
    """Felsnadeln am Abgrund: Gruppe schwarzer Basaltspitzen mit glühenden Splittern am Fuß."""
    rng = random.Random(9)
    bm = bmesh.new()
    ico(bm, (0, 0, 0.6), 1.8, (1.2, 1.0, 0.6), 1, 0.25, rng)
    for k in range(5):
        a = k * 1.25 + rng.uniform(-0.2, 0.2)
        h = rng.uniform(3.0, 6.0)
        tilt = Matrix.Rotation(rng.uniform(0.1, 0.35), 4, V((-math.sin(a), math.cos(a), 0)))
        cone(bm, (math.cos(a) * 1.0, math.sin(a) * 1.0, h / 2), rng.uniform(0.7, 1.1), 0.08, h, 6, tilt)
    obj = mesh_obj("AbyssRock", bm)
    obj.data.materials.append(color_mat("Basalt", "#221a20", 0.85))
    bm = bmesh.new()
    for k in range(4):
        a = rng.uniform(0, 2 * math.pi)
        cone(bm, (math.cos(a) * 1.9, math.sin(a) * 1.6, 0.35), 0.18, 0.0, 0.8, 5, Matrix.Rotation(rng.uniform(-0.5, 0.5), 4, "X"))
    shards = mesh_obj("AbyssGlow", bm)
    shards.data.materials.append(color_mat("AbyssGlow", "#3a1410", 0.3, 0.0, "#ff4a1c", 2.4))
    export("AbyssRock")


def build_void_crystals():
    """Violette Kristallgruppe im Abgrund (oben links im Bild): hohe, leuchtende Spitzen."""
    rng = random.Random(13)
    bm = bmesh.new()
    for k in range(7):
        a = k * 0.9 + rng.uniform(-0.2, 0.2)
        d = 0.0 if k == 0 else rng.uniform(0.6, 1.3)
        h = rng.uniform(3.5, 5.5) if k == 0 else rng.uniform(1.6, 3.6)
        tilt = Matrix.Rotation(0.0 if k == 0 else rng.uniform(0.2, 0.5), 4, V((-math.sin(a), math.cos(a), 0)))
        cone(bm, (math.cos(a) * d, math.sin(a) * d, h / 2), rng.uniform(0.3, 0.5), 0.04, h, 6, tilt)
    obj = mesh_obj("VoidCrystals", bm)
    obj.data.materials.append(color_mat("VoidCrystal", "#4a1a6e", 0.15, 0.0, "#a24dff", 3.0))
    export("VoidCrystals")


def build_stone_wall():
    """Niedrige Steinmauer (3,5 m lang entlang X, 1,5 m hoch) mit Abdecksteinen – reihbar für die Wälle im Bild."""
    rng = random.Random(17)
    bm = bmesh.new()
    box(bm, (0, 0, 0.6), (3.5, 0.8, 1.2))
    box(bm, (0, 0, 1.3), (3.6, 0.95, 0.22))
    for k in range(4):                                                           # unregelmäßige Decksteine
        box(bm, (-1.35 + k * 0.9, rng.uniform(-0.05, 0.05), 1.48), (0.8, 0.85, rng.uniform(0.12, 0.2)), rng.uniform(-0.05, 0.05))
    obj = mesh_obj("StoneWall", bm)
    stone(obj, "StoneWall", "#9d9a92", 512)
    export("StoneWall")


def build_citadel_wall():
    """Zitadellenmauer (4 m lang entlang X, ~4,6 m hoch) mit Sockel, Wehrgang und Zinnen vorn und hinten."""
    bm = bmesh.new()
    box(bm, (0, 0, 0.3), (4.0, 1.8, 0.6))
    box(bm, (0, 0, 2.2), (4.0, 1.4, 3.8))
    box(bm, (0, 0, 4.15), (4.0, 1.55, 0.2))
    for y in (-0.55, 0.55):
        for k in range(4):
            box(bm, (-1.5 + k * 1.0, y, 4.55), (0.55, 0.35, 0.6))
    obj = mesh_obj("CitadelWall", bm)
    stone(obj, "CitadelWall", "#aaa69c", 512)
    export("CitadelWall")


BUILDERS = {
    "Bridge": build_bridge, "CitadelTower": build_citadel_tower, "Gatehouse": build_gatehouse,
    "GuardTower": build_guard_tower, "Portal": build_portal, "HeroPad": build_hero_pad, "Shrine": build_shrine,
    "ShopHouse": build_shop, "Trees": build_trees, "Rocks": build_rocks, "Barracks": build_barracks,
    "Ruins": build_ruins, "Mountain": build_mountain, "AbyssRock": build_abyss_rock, "VoidCrystals": build_void_crystals,
    "StoneWall": build_stone_wall, "CitadelWall": build_citadel_wall,
}


def preview(folder):
    """Alle Modelle nebeneinander laden und als ein Übersichtsbild rendern."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    rows = [(16.0, [("Bridge", 9), ("Gatehouse", 12.5), ("Barracks", 9), ("ShopHouse", 7), ("Ruins", 8)]),
            (3.0, [("CitadelWall", 4.5), ("StoneWall", 4), ("CitadelTower", 4.5), ("GuardTower", 3.8), ("Shrine", 2.6),
                   ("HeroPad", 3), ("Portal", 8.5), ("Mountain", 14)]),
            (-10.0, [("TreePine", 4.6), ("TreeOak", 4.6), ("TreeDead", 3.6), ("Rock", 3.2), ("Cliff", 8.5),
                     ("AbyssSpikes", 3), ("AbyssRock", 5.5), ("VoidCrystals", 4)])]
    for y, items in rows:
        x = -(sum(w for _, w in items) + 1.0 * (len(items) - 1)) / 2
        for name, width in items:
            before = set(bpy.data.objects)
            bpy.ops.import_scene.gltf(filepath=os.path.join(OUT_DIR, name + ".glb"))
            for o in bpy.data.objects:
                if o not in before and o.parent is None:
                    o.location += V((x + width / 2, y, 0))
            x += width + 1.0
    cam = bd.setup_render(res=(2000, 1300), samples=32)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 64.0
    bd.look(cam, (0.0, -70.0, 44.0), (0.0, 4.0, 1.5))
    bpy.context.scene.render.filepath = os.path.join(folder, "citadel_props.png")
    bpy.ops.render.render(write_still=True)
    log("Vorschau -> %s" % bpy.context.scene.render.filepath)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    folder = argv[argv.index("--preview") + 1] if "--preview" in argv else None
    only = [a for a in argv if a in BUILDERS]
    for name, fn in BUILDERS.items():
        if only and name not in only:
            continue
        bpy.ops.wm.read_factory_settings(use_empty=True)
        fn()
    if folder:
        preview(folder)


if __name__ == "__main__":
    main()
