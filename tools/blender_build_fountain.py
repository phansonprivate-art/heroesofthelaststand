"""Brunnen der Erholung (Issue #2): achteckiges Steinbecken mit leuchtendem Wasser, schlanker Säule, oberer Schale
und schwebendem Kristall. Alles per Drehprofil (Lathe) gebaut, Stein mit gebackener Textur (Quader, Körnung,
Umgebungsverdeckung), Wasser, Runenband und Kristall leuchten. Der Kristall ist ein eigenes Objekt "Crystal",
damit ihn das Spiel langsam drehen kann.

Aufruf (Blender 5.2, ohne Oberfläche):
  blender.exe --background --python tools/blender_build_fountain.py -- [--preview <ordner>]
Ausgabe: assets/models/environment_custom/RecoveryFountain.glb
"""
import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import blender_build_dragon as bd   # Baukasten: Backen, Bilder, Vorschau

OUT = os.path.join(bd.PROJECT, "assets", "models", "environment_custom", "RecoveryFountain.glb")
V = Vector
log = lambda msg: print("[fountain] %s" % msg, flush=True)

# Drehprofile (Radius, Höhe), von der Achse unten über außen nach innen oben
BASIN = [(0.0, 0.0), (1.28, 0.0), (1.33, 0.06), (1.27, 0.12), (1.25, 0.46), (1.36, 0.5), (1.36, 0.6), (1.14, 0.6),
         (1.1, 0.52), (0.0, 0.52)]
PEDESTAL = [(0.0, 0.5), (0.34, 0.5), (0.3, 0.58), (0.22, 0.64), (0.17, 0.72), (0.15, 0.98), (0.2, 1.06), (0.26, 1.1),
            (0.0, 1.1)]
BOWL = [(0.0, 1.06), (0.16, 1.08), (0.46, 1.2), (0.62, 1.3), (0.64, 1.37), (0.58, 1.39), (0.52, 1.34), (0.0, 1.33)]
SPIRE = [(0.0, 1.3), (0.11, 1.33), (0.08, 1.42), (0.05, 1.56), (0.09, 1.6), (0.0, 1.61)]
RUNE_BAND = [(1.255, 0.27), (1.262, 0.29), (1.262, 0.33), (1.255, 0.35)]   # offenes Band am Becken


def lathe(name, profile, segments, smooth, closed=True):
    """Drehkörper aus einem Profil; Punkte mit Radius 0 werden zu einem Achspunkt."""
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        if r < 1e-6:
            rings.append([bm.verts.new((0.0, 0.0, z))])
            continue
        off = math.pi / segments   # Achteck mit flacher Vorderseite
        rings.append([bm.verts.new((r * math.cos(2 * math.pi * k / segments + off), r * math.sin(2 * math.pi * k / segments + off), z))
                      for k in range(segments)])
    for a, b in zip(rings, rings[1:]):
        for k in range(segments):
            k2 = (k + 1) % segments
            if len(a) == 1 and len(b) == 1:
                continue
            if len(a) == 1:
                bm.faces.new((a[0], b[k2], b[k]))
            elif len(b) == 1:
                bm.faces.new((a[k], a[k2], b[0]))
            else:
                bm.faces.new((a[k], a[k2], b[k2], b[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = smooth
    return bd.link(bpy.data.objects.new(name, me))


def disc(name, radius, z, segments):
    bm = bmesh.new()
    bmesh.ops.create_circle(bm, cap_ends=True, segments=segments, radius=radius)
    bmesh.ops.translate(bm, vec=(0, 0, z), verts=bm.verts)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return bd.link(bpy.data.objects.new(name, me))


def crystal():
    bm = bmesh.new()
    top, bottom = bm.verts.new((0, 0, 0.26)), bm.verts.new((0, 0, -0.2))
    ring = [bm.verts.new((0.12 * math.cos(a), 0.12 * math.sin(a), 0.0)) for a in [2 * math.pi * k / 6 for k in range(6)]]
    for k in range(6):
        bm.faces.new((ring[k], ring[(k + 1) % 6], top))
        bm.faces.new((ring[(k + 1) % 6], ring[k], bottom))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("Crystal")
    bm.to_mesh(me)
    bm.free()
    obj = bd.link(bpy.data.objects.new("Crystal", me))
    obj.location = (0, 0, 1.86)
    return obj


def stone_bake_material():
    """Stein: Quaderfugen (Voronoi-Kanten, waagerecht gestreckt), Körnung, leichte Farbwechsel; nur zum Backen."""
    mat = bpy.data.materials.new("StoneBake")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    coord = nt.nodes.new("ShaderNodeTexCoord")
    stretch = nt.nodes.new("ShaderNodeMapping")
    stretch.inputs["Scale"].default_value = (1.0, 1.0, 2.2)          # Quader breiter als hoch
    nt.links.new(coord.outputs["Object"], stretch.inputs["Vector"])
    edge = nt.nodes.new("ShaderNodeTexVoronoi")
    edge.feature = "DISTANCE_TO_EDGE"
    edge.inputs["Scale"].default_value = 4.0
    nt.links.new(stretch.outputs["Vector"], edge.inputs["Vector"])
    cell = nt.nodes.new("ShaderNodeTexVoronoi")
    cell.inputs["Scale"].default_value = 4.0
    nt.links.new(stretch.outputs["Vector"], cell.inputs["Vector"])
    grain = nt.nodes.new("ShaderNodeTexNoise")
    grain.inputs["Scale"].default_value = 60.0
    grain.inputs["Detail"].default_value = 8.0
    nt.links.new(coord.outputs["Object"], grain.inputs["Vector"])
    joint = bd.smooth_range(nt, edge.outputs["Distance"], 0.0, 0.05, (0, 0))
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(cell.outputs["Color"], sep.inputs[0])
    tone = bd.math_node(nt, "ADD", (0, 0), 0.82, bd.math_node(nt, "MULTIPLY", (0, 0), sep.outputs[0], 0.3))
    shade = bd.math_node(nt, "MULTIPLY", (0, 0), tone, bd.math_node(nt, "ADD", (0, 0), 0.35, bd.math_node(nt, "MULTIPLY", (0, 0), joint, 0.65)))
    shade = bd.math_node(nt, "MULTIPLY", (0, 0), shade, bd.math_node(nt, "ADD", (0, 0), 0.85, bd.math_node(nt, "MULTIPLY", (0, 0), grain.outputs["Fac"], 0.3)))
    col = bd.mix_col(nt, (0, 0, 0, 1), (*bd.hex_lin("#9aa1ad"), 1.0), shade, (0, 0))
    nt.links.new(col, bsdf.inputs["Base Color"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Distance"].default_value = 0.01
    nt.links.new(bd.math_node(nt, "ADD", (0, 0), joint, bd.math_node(nt, "MULTIPLY", (0, 0), grain.outputs["Fac"], 0.25)), bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def glow_material(name, base, emit, strength, rough=0.15):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*bd.hex_lin(base), 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Emission Color"].default_value = (*bd.hex_lin(emit), 1.0)
    bsdf.inputs["Emission Strength"].default_value = strength
    return mat


def build():
    parts = [lathe("Basin", BASIN, 8, False), lathe("Pedestal", PEDESTAL, 8, False), lathe("Bowl", BOWL, 16, True),
             lathe("Spire", SPIRE, 8, False)]
    stone = bd.join(parts, "FountainStone")
    bd.unwrap(stone, margin=0.004)
    bd.setup_bake_engine()
    bake_mat = stone_bake_material()
    stone.data.materials.append(bake_mat)
    albedo, normal = bd.new_image("Fountain_stone_albedo", 1024), bd.new_image("Fountain_stone_normal", 1024, non_color=True)
    ao = bd.new_image("Fountain_stone_ao", 1024, non_color=True)
    bd.bake(stone, bake_mat, albedo, "DIFFUSE", pass_filter={"COLOR"})
    bd.bake(stone, bake_mat, normal, "NORMAL", normal_space="TANGENT")
    bd.bake(stone, bake_mat, ao, "AO", samples=48)
    import numpy as np
    alb = bd.pixels(albedo)
    alb[..., :3] *= 0.45 + 0.55 * np.clip(bd.pixels(ao)[..., :1], 0, 1)
    bd.set_pixels(albedo, alb)
    for img in (albedo, normal):
        bd.save_image(img)
    stone.data.materials.clear()
    stone.data.materials.append(bd.final_material("FountainStone", albedo, normal, roughness=0.85))
    water = bd.join([disc("WaterLow", 1.12, 0.545, 32), disc("WaterHigh", 0.54, 1.355, 24)], "FountainWater")
    water.data.materials.append(glow_material("FountainWater", "#1f7fb8", "#3cc8ff", 1.6, rough=0.05))
    runes = lathe("FountainRunes", RUNE_BAND, 8, False)
    runes.data.materials.append(glow_material("FountainRunes", "#9fe8ff", "#59d8ff", 2.5))
    gem = crystal()
    gem.data.materials.append(glow_material("FountainCrystal", "#c8f2ff", "#7fe0ff", 4.0, rough=0.05))
    log("Brunnen gebaut: Stein %d Flächen" % len(stone.data.polygons))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    bpy.ops.wm.read_factory_settings(use_empty=True)
    build()
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=False, export_yup=True)
    log("exportiert -> %s" % OUT)
    if "--preview" in argv:
        folder = argv[argv.index("--preview") + 1]
        cam = bd.setup_render(res=(900, 760), samples=48)
        cam.data.lens = 50
        for name, pos in (("front", (2.6, -4.2, 2.2)), ("top", (1.0, -1.6, 4.4))):
            bd.look(cam, pos, (0.0, 0.0, 0.85))
            bpy.context.scene.render.filepath = os.path.join(folder, "fountain_%s.png" % name)
            bpy.ops.render.render(write_still=True)
            log("Vorschau -> %s" % bpy.context.scene.render.filepath)


if __name__ == "__main__":
    main()
