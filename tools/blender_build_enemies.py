"""Eigene Gegnermodelle für Phase 4, in Blender gebaut (gleiches Verfahren wie tools/blender_build_heroes.py).

Grundlage ist das KayKit-Skelett "Skeleton_Warrior" mit allen 95 Animationen (inkl. Zaubern, Beschwören, Spott).
Dessen Körperteile werden entfernt und durch eigene, starr an Knochen gebundene Teile ersetzt:

  Seer         Knochenseher – Skelett in Kapuzenrobe, Stab mit grüner Leuchtkugel
  GraveKnight  Grabritter – Skelett in rostiger Rüstung, Topfhelm mit Hörnern, Hackschwert und Schild
  Colossus     Knochenkoloss – massiger Knochenriese mit Dornen, Fesseln und Knochenkeule
  Morvath      Morvath, der Totenbeschwörer – Lich mit Knochenkrone, offener Robe, Seelenlicht in der Brust, Schädelstab

Waffen zeigen wie bei KayKit in der Ruhepose aus der Hand nach vorn (+Z).

Aufruf (Blender 5.2, ohne Oberfläche, eine Figur je Prozess oder alle):
  blender.exe --background --python tools/blender_build_enemies.py [-- seer grave_knight colossus morvath]
"""
import os
import sys

import bpy
from mathutils import Vector

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import blender_build_heroes as bh   # Baukasten (Rig, Materialien, Koordinaten)

OUT_DIR = os.path.join(bh.PROJECT, "assets", "models", "enemies_custom")
SOURCE = "assets/models/enemies/Skeleton_Warrior.glb"
V = Vector


# --- gemeinsames Skelett ------------------------------------------------------------------------------

def skeleton_base(r, bone="bone", dark="socket", eye="eye", ribs=True, limb=1.0, skull=(0.84, 0.78, 0.80)):
    """Knochenkörper: Becken, Wirbelsäule, Brustkorb (optional), dünne Gliedmaßen mit Gelenkkugeln, Schädel mit Kiefer.
    limb skaliert die Knochenstärke (Koloss: kräftiger). Gibt Schädelmitte und Vorderseite zurück."""
    r.box("hips", (0, 0.47, 0), (0.44, 0.16, 0.28), bone, bevel=0.05)
    r.limb("spine", r.j("hips") + V((0, 0.12, 0)), r.j("chest"), 0.10 * limb, bone)
    if ribs:
        r.box("chest", (0, 1.00, -0.03), (0.46, 0.40, 0.28), dark, bevel=0.06)
        for i, y in enumerate((0.86, 0.97, 1.08)):
            r.box("chest", (0, y, 0), (0.60 - 0.05 * abs(i - 1), 0.065 * limb, 0.40), bone, bevel=0.025)
        r.box("chest", (0, 0.97, 0.20), (0.08, 0.32, 0.05), bone, bevel=0.02)
    r.box("chest", (0, 1.19, 0), (0.70, 0.08 * limb, 0.20), bone, bevel=0.03)
    for side, s in (("l", 1), ("r", -1)):
        ua, la, wr, hd = (r.j(n + side) for n in ("upperarm.", "lowerarm.", "wrist.", "hand."))
        r.sphere("upperarm." + side, ua, 0.09 * limb, bone)
        r.limb("upperarm." + side, ua, la, 0.10 * limb, bone)
        r.sphere("lowerarm." + side, la, 0.075 * limb, bone)
        r.limb("lowerarm." + side, la, wr, 0.09 * limb, bone)
        r.box("hand." + side, hd + V((s * 0.05, -0.02, 0)), (0.16 * limb, 0.18 * limb, 0.18 * limb), bone, bevel=0.04)
        ul, ll, ft = (r.j(n + side) for n in ("upperleg.", "lowerleg.", "foot."))
        r.limb("upperleg." + side, ul, ll, 0.11 * limb, bone, pad_start=0.03)
        r.sphere("lowerleg." + side, ll, 0.08 * limb, bone)
        r.limb("lowerleg." + side, ll, ft, 0.10 * limb, bone)
        bh.boots(r, side, bone, (0.18 * limb, 0.10, 0.30))
    hc = r.j("head") + V((0, 0.44, 0.02))
    front = hc.z + skull[2] * 0.5
    r.box("head", hc, skull, bone, bevel=0.16, seg=3, group="Head")
    for s in (1, -1):
        r.box("head", (s * 0.17, hc.y - 0.02, front - 0.01), (0.21, 0.21, 0.06), dark, bevel=0.04, group="Head")
        r.box("head", (s * 0.17, hc.y - 0.02, front + 0.015), (0.09, 0.09, 0.04), eye, bevel=0.01, group="Head")
    r.box("head", (0, hc.y - 0.17, front - 0.005), (0.08, 0.08, 0.05), dark, rot=(0, 0, 45), group="Head")
    r.box("head", (0, hc.y - 0.40, hc.z + 0.10), (0.54, 0.16, 0.52), bone, bevel=0.05, group="Head")   # Kiefer
    for i in range(5):
        r.box("head", (-0.16 + i * 0.08, hc.y - 0.29, front - 0.04), (0.055, 0.07, 0.04), "teeth", group="Head")
    return hc, front


def bone_materials(r, bone_col=(0.88, 0.85, 0.76), eye_col="#7dff9a", eye_glow="#3dff6a", strength=3.0):
    r.mat("bone", bone_col, roughness=0.75)
    r.mat("teeth", (0.95, 0.93, 0.86), roughness=0.6)
    r.mat("socket", (0.07, 0.07, 0.09), roughness=0.9)
    r.mat("eye", bh.hexrgb(eye_col), roughness=0.4, emission=bh.hexrgb(eye_glow), strength=strength)


IDLE_ACTION = {"name": "Idle_Combat"}   ## Stehanimation der gerade gebauten Figur (wie in enemies.json)


def hand_axis(r, slot="handslot.r", world_dir=(0.0, 1.0, 0.0)):
    """Richtung in der Ruhepose (Spielraum), die in der Stehanimation der Figur nach world_dir zeigt. Waffen entlang
    dieser Achse stehen beim Stehen aufrecht – unabhängig davon, wie die Hand in der Animation gedreht ist."""
    arm = r.arm
    action = bpy.data.actions[IDLE_ACTION["name"]]
    arm.animation_data_create()
    arm.animation_data.action = action
    bpy.context.scene.frame_set(0)
    bpy.context.view_layer.update()
    pose = arm.matrix_world @ arm.pose.bones[slot].matrix
    rest = arm.matrix_world @ arm.data.bones[slot].matrix_local
    arm.animation_data.action = None
    bpy.context.view_layer.update()
    to_pose = (pose @ rest.inverted()).to_3x3()
    d_blender = to_pose.inverted() @ bh.B(V(world_dir))
    return bh.G(d_blender).normalized()


def weapon_frame(r, slot="handslot.r"):
    """Griffpunkt und Achsen einer Hand: up = Waffenachse (steht beim Stehen aufrecht), side = quer dazu."""
    up = hand_axis(r, slot)
    side = up.cross(V((0, 0, 1)))
    if side.length < 0.1:
        side = up.cross(V((1, 0, 0)))
    return r.j(slot), up, side.normalized()


def bar(r, bone, p_from, p_to, width, thick, mat, bevel=0.0):
    """Flacher Balken zwischen zwei Punkten (Klinge, Parierstange) – wie Rig.limb, aber mit eigener Breite."""
    center, length, d = r._segment(p_from, p_to, 0.0, 0.0)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=center)
    obj = bpy.context.object
    obj.scale = (width, length, thick)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = V((0, 1, 0)).rotation_difference(d)
    return r._finish(obj, bone, mat, bevel, 1, "Body")


def staff(r, length_back, length_front, mat, thick=0.07):
    """Stab in der rechten Hand entlang der Waffenachse. Gibt Spitze und Achse zurück."""
    hs, up, _side = weapon_frame(r)
    r.limb("handslot.r", hs - up * length_back, hs + up * length_front, thick, mat, bevel=0.015)
    return hs + up * length_front, up


# --- Knochenseher -------------------------------------------------------------------------------------

def build_seer(r):
    """Fernkämpfer: Skelett in zerschlissener Kapuzenrobe, Stab mit grüner Leuchtkugel."""
    bone_materials(r)
    r.mat("robe", bh.hexrgb("#2b4743"), roughness=0.85)
    r.mat("robe_dark", bh.hexrgb("#182a2b"), roughness=0.9)
    r.mat("trim", bh.hexrgb("#7dff9a"), roughness=0.5, emission=bh.hexrgb("#2fd860"), strength=0.8)
    r.mat("wood", (0.33, 0.22, 0.14), roughness=0.8)
    r.mat("bronze", (0.62, 0.46, 0.24), roughness=0.4, metallic=0.7)
    r.mat("orb", bh.hexrgb("#a6ffb8"), roughness=0.2, emission=bh.hexrgb("#3dff6a"), strength=4.0)
    hc, front = skeleton_base(r, ribs=False)
    # Robe: Rock bis zu den Schienbeinen, Oberteil, Schulterumhang, Gürtel
    r.cone("hips", (0, 0.42, 0), 0.40, 0.30, 0.52, "robe", verts=10)
    r.cone("hips", (0, 0.18, 0), 0.41, 0.40, 0.05, "trim", verts=10)
    for i in range(5):   # zerschlissener Saum: Zacken
        a = -0.32 + i * 0.16
        r.box("hips", (a, 0.13, 0.30), (0.10, 0.12, 0.05), "robe_dark", rot=(0, 0, 12 * (1 if i % 2 else -1)))
    r.box("chest", (0, 0.98, 0), (0.62, 0.54, 0.46), "robe", bevel=0.08, seg=2)
    r.box("chest", (0, 0.98, 0.235), (0.10, 0.50, 0.03), "trim")
    r.box("chest", (0, 1.22, -0.02), (0.84, 0.20, 0.64), "robe_dark", bevel=0.07, seg=2)
    r.box("hips", (0, 0.66, 0), (0.66, 0.07, 0.50), "wood", bevel=0.02)
    for side, s in (("l", 1), ("r", -1)):
        ua, la, hd = (r.j(n + side) for n in ("upperarm.", "lowerarm.", "hand."))
        r.limb("upperarm." + side, ua, la, 0.20, "robe", pad_end=0.03)
        r.limb_cone("lowerarm." + side, la, hd - (hd - la).normalized() * 0.04, 0.12, 0.19, "robe")
    # Kapuze: das Schädelgesicht schaut vorn heraus, spitzer Zipfel nach hinten
    r.box("head", (0, hc.y + 0.10, hc.z - 0.10), (1.00, 0.98, 0.96), "robe_dark", bevel=0.26, seg=3, group="Head")
    r.box("head", (0, hc.y + 0.36, front - 0.06), (0.86, 0.10, 0.10), "trim", bevel=0.03, group="Head")
    r.slab("head", (0, hc.y + 0.24, hc.z - 0.52), (0, hc.y - 0.55, hc.z - 0.64), 0.52, 0.08, 0.09, "robe_dark", group="Head")
    # Stab mit Krallenkopf und Leuchtkugel
    tip, up = staff(r, 0.55, 0.85, "wood")
    r.sphere("handslot.r", tip + up * 0.12, 0.12, "orb", subdiv=2)
    s1 = up.cross(V((0, 0, 1))).normalized()
    s2 = up.cross(s1).normalized()
    for s in (s1, -s1, s2):
        r.limb("handslot.r", tip + s * 0.03, tip + s * 0.11 + up * 0.22, 0.03, "bronze")


# --- Grabritter ---------------------------------------------------------------------------------------

def build_grave_knight(r):
    """Elite: Skelett in rostiger Rüstung, Topfhelm mit Sehschlitz (rot glühend) und Hörnern, Hackschwert, Rundschild."""
    bone_materials(r, eye_col="#ff6a4a", eye_glow="#ff2a10", strength=4.0)
    r.mat("iron", bh.hexrgb("#7a8290"), roughness=0.4, metallic=0.65)
    r.mat("iron_dark", bh.hexrgb("#454a54"), roughness=0.45, metallic=0.6)
    r.mat("rust", bh.hexrgb("#8a4e2b"), roughness=0.8, metallic=0.3)
    r.mat("tabard", bh.hexrgb("#5e1b20"), roughness=0.85)
    r.mat("horn", (0.82, 0.78, 0.66), roughness=0.6)
    r.mat("leather", (0.30, 0.20, 0.13), roughness=0.8)
    hc, front = skeleton_base(r, ribs=False)
    # Rumpf: Brustpanzer mit Rostkante, Kettenrock, Wappenrock
    r.box("chest", (0, 0.99, 0), (0.72, 0.60, 0.54), "iron", bevel=0.10, seg=2)
    r.box("chest", (0, 0.74, 0), (0.74, 0.08, 0.56), "rust", bevel=0.02)
    r.box("chest", (0, 1.05, 0.275), (0.24, 0.24, 0.04), "iron_dark", rot=(0, 0, 45), bevel=0.01)
    r.box("hips", (0, 0.50, 0), (0.62, 0.30, 0.48), "iron_dark", bevel=0.05)
    r.slab("hips", (0, 0.66, 0.26), (0, 0.16, 0.30), 0.34, 0.28, 0.04, "tabard")
    r.slab("hips", (0, 0.66, -0.25), (0, 0.20, -0.30), 0.40, 0.32, 0.04, "tabard")
    for side, s in (("l", 1), ("r", -1)):
        ua, la, wr, hd = (r.j(n + side) for n in ("upperarm.", "lowerarm.", "wrist.", "hand."))
        # Schulterpanzer mit Dornen
        r.box("upperarm." + side, (s * 0.40, 1.24, 0), (0.40, 0.26, 0.48), "iron", bevel=0.08, seg=2)
        r.box("upperarm." + side, (s * 0.41, 1.11, 0), (0.42, 0.06, 0.50), "rust", bevel=0.015)
        for dz in (-0.12, 0.12):
            r.cone("upperarm." + side, (s * 0.44, 1.44, dz), 0.06, 0.0, 0.22, "iron_dark", verts=6)
        r.limb("lowerarm." + side, la, wr, 0.22, "iron", pad_start=0.03, bevel=0.03)
        r.box("hand." + side, hd + V((s * 0.05, -0.02, 0)), (0.20, 0.22, 0.22), "iron_dark", bevel=0.05)
        ll, ft = r.j("lowerleg." + side), r.j("foot." + side)
        r.limb("lowerleg." + side, ll, ft, 0.22, "iron", pad_start=0.02, bevel=0.03)
        bh.boots(r, side, "iron_dark", (0.26, 0.18, 0.40))
    # Topfhelm über dem ganzen Schädel, Sehschlitz mit glühenden Augen, Hörner
    r.box("head", (0, hc.y + 0.02, hc.z), (0.96, 0.92, 0.92), "iron", bevel=0.14, seg=2, group="Head")
    r.box("head", (0, hc.y - 0.02, hc.z + 0.465), (0.80, 0.11, 0.04), "socket", group="Head")
    for s in (1, -1):
        r.box("head", (s * 0.17, hc.y - 0.02, hc.z + 0.485), (0.12, 0.07, 0.03), "eye", group="Head")
        r.cone("head", (s * 0.56, hc.y + 0.30, hc.z), 0.10, 0.02, 0.50, "horn", rot=(0, 0, -s * 55), verts=8, group="Head")
    r.box("head", (0, hc.y + 0.47, hc.z), (0.14, 0.10, 0.90), "rust", bevel=0.02, group="Head")
    r.box("head", (0, hc.y - 0.30, hc.z + 0.46), (0.06, 0.22, 0.04), "iron_dark", group="Head")
    # Hackschwert (rechts): Griff, Parierstange, breite Klinge mit Rostschneide
    hs, up, side = weapon_frame(r)
    r.limb("handslot.r", hs - up * 0.18, hs + up * 0.12, 0.07, "leather")
    bar(r, "handslot.r", hs + up * 0.12 - side * 0.18, hs + up * 0.12 + side * 0.18, 0.08, 0.07, "iron_dark")
    bar(r, "handslot.r", hs + up * 0.15, hs + up * 1.05, 0.22, 0.045, "iron", bevel=0.01)
    # Rundschild (links): Scheibe, deren Vorderseite beim Stehen nach außen zeigt, mit Rostbuckel
    hl = r.j("handslot.l")
    out = hand_axis(r, "handslot.l", world_dir=(1.0, 0.0, 0.0))
    r.limb_cone("handslot.l", hl + out * 0.04, hl + out * 0.12, 0.34, 0.34, "iron", verts=12)
    r.limb_cone("handslot.l", hl + out * 0.12, hl + out * 0.19, 0.12, 0.05, "rust", verts=8)


# --- Knochenkoloss ------------------------------------------------------------------------------------

def build_colossus(r):
    """Mini-Boss: massiger Knochenriese, breiter Brustkorb, Dornen auf Schultern und Rücken, Fesseln, Knochenkeule."""
    bone_materials(r, bone_col=(0.84, 0.79, 0.66), eye_col="#ffb35a", eye_glow="#ff7a10", strength=4.0)
    r.mat("bone_dark", (0.62, 0.56, 0.44), roughness=0.8)
    r.mat("iron", bh.hexrgb("#3c3f45"), roughness=0.5, metallic=0.7)
    r.mat("cloth", bh.hexrgb("#4a3424"), roughness=0.9)
    hc, front = skeleton_base(r, limb=1.8, skull=(0.86, 0.72, 0.78))
    # breiter Brustkorb über dem Grundkorb, Rückendornen, Lendenschurz
    r.box("chest", (0, 1.02, -0.03), (0.86, 0.56, 0.52), "socket", bevel=0.08)
    for i, y in enumerate((0.84, 0.97, 1.10)):
        r.box("chest", (0, y, 0), (0.94 - 0.06 * abs(i - 1), 0.10, 0.58), "bone", bevel=0.04)
    r.box("chest", (0, 0.97, 0.29), (0.12, 0.38, 0.06), "bone", bevel=0.02)
    r.box("chest", (0, 1.02, -0.29), (0.20, 0.62, 0.06), "bone", bevel=0.03)   # Wirbelsäule am Rücken
    for i, y in enumerate((0.92, 1.10, 1.28)):
        r.cone("chest", (0, y, -0.34), 0.08, 0.0, 0.32, "bone_dark", rot=(-70, 0, 0), verts=6)
    r.slab("hips", (0, 0.56, 0.18), (0, 0.18, 0.24), 0.40, 0.30, 0.05, "cloth")
    r.slab("hips", (0, 0.56, -0.17), (0, 0.22, -0.22), 0.44, 0.34, 0.05, "cloth")
    for side, s in (("l", 1), ("r", -1)):
        la, wr = r.j("lowerarm." + side), r.j("wrist." + side)
        # Schulterknochen mit Dornen, massige Unterarme, Eisenfessel
        r.box("upperarm." + side, (s * 0.42, 1.26, 0), (0.42, 0.24, 0.42), "bone", bevel=0.10, seg=2)
        for dz in (-0.12, 0.12):
            r.cone("upperarm." + side, (s * 0.50, 1.46, dz), 0.07, 0.0, 0.30, "bone_dark", rot=(0, 0, -s * 20), verts=6)
        r.limb("lowerarm." + side, la, wr, 0.26, "bone", pad_start=0.02, bevel=0.05)
        r.limb("lowerarm." + side, wr - (wr - la).normalized() * 0.10, wr, 0.30, "iron", bevel=0.02)
    # kleine Hörner auf dem Schädel, Stirnwulst
    for s in (1, -1):
        r.cone("head", (s * 0.30, hc.y + 0.42, hc.z), 0.08, 0.0, 0.28, "bone_dark", rot=(0, 0, -s * 30), verts=6, group="Head")
    r.box("head", (0, hc.y + 0.14, front - 0.02), (0.78, 0.10, 0.08), "bone_dark", bevel=0.03, group="Head")
    # Knochenkeule: dicker Schaft, Knauf mit Dornen
    tip, up = staff(r, 0.25, 0.85, "bone_dark", thick=0.14)
    knob = tip + up * 0.14
    r.limb("handslot.r", tip, tip + up * 0.36, 0.34, "bone", bevel=0.08)
    s1 = up.cross(V((0, 0, 1))).normalized()
    s2 = up.cross(s1).normalized()
    for d in (s1, -s1, s2, -s2, up):
        base = knob + d * (0.16 if d != up else 0.22)
        r.limb_cone("handslot.r", base, base + d * 0.18, 0.05, 0.0, "bone_dark", verts=6)


# --- Morvath ------------------------------------------------------------------------------------------

def build_morvath(r):
    """Endboss: Lich mit Knochenkrone, hohem Kragen, offener Robe (Rippen mit Seelenlicht), Schulterplatten, Schädelstab."""
    bone_materials(r, bone_col=(0.86, 0.86, 0.78), eye_col="#b6ffc4", eye_glow="#3dff6a", strength=6.0)
    r.mat("robe", bh.hexrgb("#2c1a3c"), roughness=0.8)
    r.mat("robe_dark", bh.hexrgb("#170e22"), roughness=0.85)
    r.mat("trim", bh.hexrgb("#7dff9a"), roughness=0.5, emission=bh.hexrgb("#2fd860"), strength=1.2)
    r.mat("gold", (0.80, 0.62, 0.24), roughness=0.35, metallic=0.85)
    r.mat("soul", bh.hexrgb("#9dffb0"), roughness=0.2, emission=bh.hexrgb("#3dff6a"), strength=5.0)
    r.mat("wood", (0.22, 0.16, 0.12), roughness=0.8)
    hc, front = skeleton_base(r, ribs=True)
    r.sphere("chest", (0, 1.00, 0.02), 0.13, "soul", subdiv=2)   # Seelenlicht im Brustkorb
    # Robe: langer Rock, offene Front (Rippen sichtbar), Kragen, Schulterplatten
    r.cone("hips", (0, 0.40, 0), 0.50, 0.32, 0.60, "robe", verts=12)
    r.cone("hips", (0, 0.12, 0), 0.51, 0.50, 0.05, "trim", verts=12)
    r.box("hips", (0, 0.66, 0), (0.64, 0.08, 0.48), "gold", bevel=0.02)
    for s in (1, -1):
        r.box("chest", (s * 0.27, 0.98, 0), (0.18, 0.62, 0.50), "robe", bevel=0.05)   # offene Robe: Seitenbahnen
        r.box("chest", (s * 0.19, 0.98, 0.24), (0.03, 0.60, 0.03), "trim")
    r.box("chest", (0, 0.98, -0.16), (0.64, 0.62, 0.20), "robe", bevel=0.05)
    r.slab("chest", (0, 1.55, -0.28), (0, 1.15, -0.24), 0.84, 0.64, 0.07, "robe_dark")      # hoher Kragen
    r.slab("chest", (0, 1.22, -0.27), (0, 0.22, -0.40), 0.62, 0.78, 0.05, "robe_dark")      # Umhang
    for side, s in (("l", 1), ("r", -1)):
        ua, la, hd = (r.j(n + side) for n in ("upperarm.", "lowerarm.", "hand."))
        r.box("upperarm." + side, (s * 0.40, 1.24, 0), (0.38, 0.18, 0.46), "gold", bevel=0.06, seg=2)
        for dz in (-0.14, 0.0, 0.14):
            r.cone("upperarm." + side, (s * 0.46, 1.40, dz), 0.05, 0.0, 0.24, "bone", rot=(0, 0, -s * 25), verts=6)
        r.limb("upperarm." + side, ua, la, 0.20, "robe", pad_end=0.03)
        r.limb_cone("lowerarm." + side, la, hd - (hd - la).normalized() * 0.04, 0.12, 0.22, "robe")
        r.limb_cone("lowerarm." + side, hd - (hd - la).normalized() * 0.07, hd - (hd - la).normalized() * 0.03, 0.225, 0.225, "trim")
    # Knochenkrone: Reif mit Zacken
    import math
    r.cone("head", (0, hc.y + 0.40, hc.z), 0.46, 0.46, 0.10, "gold", verts=16, group="Head")
    for i in range(7):
        a = math.radians(-90 + (i - 3) * 30)
        pos = (0.40 * math.cos(a + math.pi), hc.y + 0.55, hc.z + 0.40 * math.sin(-a - math.pi / 2 + math.pi))
        h = 0.40 if i == 3 else (0.30 if i in (2, 4) else 0.22)
        r.cone("head", (0.42 * math.sin(math.radians((i - 3) * 30)), hc.y + 0.44 + h * 0.5, hc.z + 0.42 * math.cos(math.radians((i - 3) * 30))),
               0.06, 0.0, h, "bone", verts=6, group="Head")
    r.box("head", (0, hc.y + 0.43, hc.z + 0.47), (0.10, 0.10, 0.04), "soul", rot=(0, 0, 45), group="Head")
    # Schädelstab: langer Schaft, Schädel, grüne Flamme
    tip, up = staff(r, 0.70, 1.10, "wood", thick=0.08)
    r.limb("handslot.r", tip, tip + up * 0.26, 0.26, "bone", bevel=0.07)                 # Schädel auf dem Stab
    r.sphere("handslot.r", tip + up * 0.42, 0.12, "soul", subdiv=2)
    r.limb_cone("handslot.r", tip + up * 0.48, tip + up * 0.78, 0.09, 0.0, "soul", verts=8)   # grüne Flamme


ENEMIES = {
    "seer": {"prefix": "Seer", "build": build_seer, "idle": "Idle_Combat"},
    "grave_knight": {"prefix": "GraveKnight", "build": build_grave_knight, "idle": "Idle_Combat"},
    "colossus": {"prefix": "Colossus", "build": build_colossus, "idle": "Idle_Combat"},
    "morvath": {"prefix": "Morvath", "build": build_morvath, "idle": "Idle"},
}


def build_enemy(enemy_id):
    cfg = ENEMIES[enemy_id]
    bh.log("=== %s ===" % enemy_id)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 30   # KayKit-Animationen sind mit 30 fps erstellt
    bpy.context.scene.render.fps_base = 1.0
    bpy.ops.import_scene.gltf(filepath=os.path.join(bh.PROJECT, SOURCE))
    armature = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
    for obj in [o for o in bpy.context.scene.objects if o.type == "MESH" and o.name.startswith("Skeleton_Warrior_")]:
        bpy.data.objects.remove(obj, do_unlink=True)
    r = bh.Rig(armature, cfg["prefix"])
    IDLE_ACTION["name"] = cfg["idle"]
    cfg["build"](r)
    r.join_all()
    os.makedirs(OUT_DIR, exist_ok=True)
    out_path = os.path.join(OUT_DIR, cfg["prefix"] + ".glb")
    bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB", use_selection=False, export_animations=True,
                              export_animation_mode="ACTIONS", export_skins=True, export_def_bones=False, export_yup=True)
    bh.log("exportiert -> %s" % out_path)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for enemy_id in (argv or list(ENEMIES.keys())):
        build_enemy(enemy_id)
    bh.log("fertig.")


if __name__ == "__main__":
    main()
