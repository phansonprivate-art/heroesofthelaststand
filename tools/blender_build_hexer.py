"""Abgrund-Hexer: Tripo-Modell (daemon_hexer.glb) auf das KayKit-Skelett übertragen (Gegner „abyss_hexer“).

Phasen (jede mit --preview <ordner> als Bild prüfbar):
  1 mesh      Tripo-Netz laden, Texturnähte verschweißen, Stab und schwebende Splitter abtrennen, Größe/Ausrichtung
  2 skeleton  KayKit-Skelett (Rig_Medium) auf die Proportionen des Modells einpassen
  3 weights   Gewichte (automatisch, nachgearbeitet), Ruhepose-Test
  4 staff     Stab als eigene Waffe an den Handslot
  5 export    GLB nach assets/models/enemies_custom/AbyssHexer.glb

Blender-Raum: vorn = -Y, oben = +Z, linke Seite der Figur = +X (wie bei den Helden).

Aufruf (Blender 5.2, ohne Oberfläche):
  blender.exe --background --python tools/blender_build_hexer.py -- [--stage mesh] [--preview <ordner>] [--src <glb>]
"""
import math
import os
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import blender_build_dragon as bd   # Vorschau (setup_render, look), Aufräumhilfen

PROJECT = bd.PROJECT
V = Vector
STAGES = ["mesh", "skeleton", "weights", "staff", "export"]
SRC_DEFAULT = "C:/Users/phant/Downloads/daemon_hexer.glb"
HEIGHT = 2.1                 ## Gesamthöhe inklusive Hörner in Metern (Helden: Kopf ~2,0)
WELD = 0.0005                ## Verschweißen der Texturnähte (Modell ist 1 m hoch)
log = lambda msg: print("[hexer] %s" % msg, flush=True)


def islands(bm):
    """Zusammenhängende Teile als Listen von Punkten, größte zuerst."""
    seen, out = set(), []
    bm.verts.ensure_lookup_table()
    for v in bm.verts:
        if v.index in seen:
            continue
        stack, part = [v], []
        while stack:
            x = stack.pop()
            if x.index in seen:
                continue
            seen.add(x.index)
            part.append(x)
            stack.extend(e.other_vert(x) for e in x.link_edges)
        out.append(part)
    out.sort(key=len, reverse=True)
    return out


def bbox(verts):
    lo = V([min(v.co[i] for v in verts) for i in range(3)])
    hi = V([max(v.co[i] for v in verts) for i in range(3)])
    return lo, hi


# --- Phase 1: Netz -------------------------------------------------------------------------------------

def stage_mesh(ctx):
    bpy.ops.import_scene.gltf(filepath=ctx["src"])
    body = next(o for o in bpy.context.scene.objects if o.type == "MESH")
    for o in [o for o in bpy.context.scene.objects if o is not body]:
        bpy.data.objects.remove(o, do_unlink=True)   # RootNode u. ä.
    body.parent = None
    body.matrix_world = Matrix.Identity(4)
    body.name = "Hexer"
    bpy.context.view_layer.objects.active = body
    bm = bmesh.new()
    bm.from_mesh(body.data)
    before = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=WELD)
    parts = islands(bm)
    log("Punkte %d -> %d, Teile: %d" % (before, len(bm.verts), len(parts)))
    for i, p in enumerate(parts[:6]):
        lo, hi = bbox(p)
        log("  Teil %2d: %5d Punkte  x %.3f..%.3f  y %.3f..%.3f  z %.3f..%.3f" % (i, len(p), lo.x, hi.x, lo.y, hi.y, lo.z, hi.z))
    ctx["parts_bm"] = bm
    ctx["parts"] = parts
    ctx["body"] = body
    classify_parts(ctx)


def classify_parts(ctx):
    """Körper = größtes Teil plus alles, was am Körper klebt; Stab und Splitter = Rest rechts von der Figur oder
    schwebend. Die Zuordnung steht in ctx['staff_verts'] / ctx['keep']; ob sie stimmt, zeigt die Vorschau."""
    parts = ctx["parts"]
    lo0, hi0 = bbox(parts[0])
    ctx["keep"], ctx["staff"] = [], []
    for i, p in enumerate(parts):
        lo, hi = bbox(p)
        centre = (lo + hi) * 0.5
        # Stab: Teile, die überwiegend auf der linken Seite der Figur (+X) außerhalb des Rumpfes liegen
        outside = centre.x > 0.14 or (len(p) < 40 and centre.x > 0.07)   # rechts vom Rumpf (Figur-links = +X): Stab, Krone, Splitter
        (ctx["staff"] if (i > 0 and outside) else ctx["keep"]).append(i)
    log("Körper-Teile: %s, Stab/Splitter: %s" % (ctx["keep"], ctx["staff"]))


def split_staff(ctx):
    bm = ctx["parts_bm"]
    parts = ctx["parts"]
    staff_verts = [v for i in ctx["staff"] for v in parts[i]]
    keep = [v for i in ctx["keep"] for v in parts[i]]
    # Stab in ein eigenes Netz kopieren, dann aus dem Körper löschen
    staff_bm = bm.copy()
    staff_set = {v.index for v in staff_verts}
    bmesh.ops.delete(staff_bm, geom=[v for v in staff_bm.verts if v.index not in staff_set], context="VERTS")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.index in staff_set], context="VERTS")
    bm.to_mesh(ctx["body"].data)
    me = bpy.data.meshes.new("StaffCut")
    staff_bm.to_mesh(me)
    staff = bpy.data.objects.new("StaffCut", me)
    bpy.context.scene.collection.objects.link(staff)
    for m in ctx["body"].data.materials:
        me.materials.append(m)
    ctx["staff_obj"] = staff
    log("Körper: %d Flächen, Stab/Splitter: %d Flächen" % (len(ctx["body"].data.polygons), len(me.polygons)))


def fit_to_height(ctx):
    """Größe auf HEIGHT, Füße auf z = 0, Mitte auf x = y = 0 (Rumpf, ohne den ausgestellten Stab)."""
    body = ctx["body"]
    co = [v.co for v in body.data.vertices]
    lo = V([min(c[i] for c in co) for i in range(3)])
    hi = V([max(c[i] for c in co) for i in range(3)])
    k = HEIGHT / (hi.z - lo.z)
    # Mitte aus Beinen und Hufen (der Rumpf-Umriss reicht mit dem ausgestellten Arm zu weit nach einer Seite)
    legs = [c for c in co if lo.z + 0.15 * (hi.z - lo.z) < c.z < lo.z + 0.45 * (hi.z - lo.z)]
    feet = [c for c in co if c.z < lo.z + 0.08 * (hi.z - lo.z)]
    cx = sum(c.x for c in legs) / len(legs)
    cy = sum(c.y for c in feet) / len(feet)
    for obj in (body, ctx.get("staff_obj")):
        if obj is None:
            continue
        for v in obj.data.vertices:
            v.co = V((-(v.co.x - cx) * k, (v.co.y - cy) * k, (v.co.z - lo.z) * k))   # gespiegelt: Stab-Hand wird die rechte (-X)
        bm2 = bmesh.new()
        bm2.from_mesh(obj.data)
        bmesh.ops.reverse_faces(bm2, faces=bm2.faces)   # Spiegeln dreht die Flächen um
        bm2.to_mesh(obj.data)
        bm2.free()
        obj.data.update()
    log("Maßstab %.3f; Körper %.2f x %.2f x %.2f m" % (k, (hi.x - lo.x) * k, (hi.y - lo.y) * k, (hi.z - lo.z) * k))


# --- Phase 2: Skelett ----------------------------------------------------------------------------------

KAYKIT = "assets/models/heroes/Mage.glb"   ## Rig_Medium mit allen KayKit-Animationen

# Gelenke des Modells (nach Spiegeln und Mitten; x = Figur-links, y = hinten, z = oben), aus Rasterbildern abgelesen.
# Arme stehen in der Haltung des Modells (A-Pose / Stab-Arm gebeugt) und werden später in T-Pose gebracht.
JOINTS = {
    "hips": (0.0, 0.05, 0.80), "spine": (0.0, 0.05, 0.97), "chest": (0.0, 0.05, 1.17), "neck": (0.0, 0.03, 1.55),
    "top": (0.0, 0.0, 1.93),
    "upperleg": (0.15, 0.05, 0.90),
}
LEGS = {   # Knie, Knöchel, Ballen, Zehenspitze je Seite (Füße stehen auseinander; Werte werden verfeinert)
    "l": {"lowerleg": (0.22, 0.0, 0.53), "foot": (0.28, 0.04, 0.19), "ball": (0.29, -0.07, 0.05), "toe": (0.29, -0.17, 0.05)},
    "r": {"lowerleg": (-0.23, 0.0, 0.53), "foot": (-0.30, 0.04, 0.19), "ball": (-0.31, -0.07, 0.05), "toe": (-0.31, -0.17, 0.05)},
}
ARMS = {   # Schulter, Ellbogen, Handgelenk, Hand, Fingerspitze (links = +X; die rechte ist die Stab-Hand, gebeugt)
    "l": [(0.26, 0.02, 1.43), (0.29, 0.05, 1.19), (0.34, 0.05, 0.90), (0.345, 0.05, 0.86), None],
    "r": [(-0.26, 0.02, 1.43), (-0.43, 0.0, 1.22), (-0.62, -0.25, 1.03), (-0.65, -0.28, 1.02), None],   # Fingerspitze: nach dem Verfeinern
}
ARM_BONES = ("upperarm", "lowerarm", "wrist", "hand")
HAND_LENGTH = {"l": 0.21, "r": 0.15}   # offene Hand links, Faust rechts


def refine_joints(ctx, rounds=4, radius=0.1, slab=0.06, max_shift=0.09):
    """Abgelesene Gelenke zur Mitte der Netzpunkte in ihrer Umgebung ziehen (Querschnitt des Gliedes): Arme entlang
    ihrer Richtung, Beine in x/y auf ihrer Höhe. Rüstungsplatten sitzen meist symmetrisch ums Glied, die Mitte stimmt."""
    pts = [V(v.co) for v in ctx["body"].data.vertices]
    moved = []

    def centroid(p, axis, free):
        near = [q for q in pts if (q - p).length < radius and abs((q - p).dot(axis)) < slab]
        if len(near) < 12:
            return p
        c = sum(near, V()) / len(near)
        c = p + V([(c - p)[i] if free[i] else 0.0 for i in range(3)])
        return p + (c - p).normalized() * min((c - p).length, max_shift) if (c - p).length > 1e-6 else p

    for side in ("l", "r"):
        arm = [V(p) if p else V() for p in ARMS[side]]
        arm[4] = arm[3] + (arm[3] - arm[2]).normalized() * HAND_LENGTH[side]
        for _ in range(rounds):
            for i in (1, 2, 3):
                axis = (arm[i + 1] - arm[i - 1]).normalized()
                arm[i] = centroid(arm[i], axis, (True, True, True))
        ARMS[side] = [tuple(p) for p in arm[:4]] + [None]
        moved.append("%s %s" % (side, [tuple(round(c, 2) for c in p) for p in arm[1:4]]))
    for side in ("l", "r"):
        for name in ("lowerleg", "foot"):
            p = V(LEGS[side][name])
            for _ in range(rounds):
                p = centroid(p, V((0, 0, 1)), (True, False, False))   # nur x: Rüstungsplatten verschieben die Mitte nach vorn
            LEGS[side][name] = (p.x, 0.03 if name == "lowerleg" else 0.07, p.z)
            moved.append("%s.%s %s" % (name, side, tuple(round(c, 2) for c in p)))
        foot = V(LEGS[side]["foot"])
        LEGS[side]["ball"] = (foot.x + 0.01, -0.06, 0.05)   # Huf zeigt nach vorn
        LEGS[side]["toe"] = (foot.x + 0.01, -0.16, 0.05)
    log("verfeinert: " + "; ".join(moved))


def arm_points(side, tpose):
    """Gelenkpunkte eines Arms: in der Haltung des Modells oder (gleiche Segmentlängen) waagerecht in T-Pose."""
    pts = [V(p) if p else None for p in ARMS[side]]
    pts[4] = pts[3] + (pts[3] - pts[2]).normalized() * HAND_LENGTH[side]
    if not tpose:
        return pts
    s = 1.0 if side == "l" else -1.0
    out = [pts[0]]
    for a, b in zip(pts, pts[1:]):
        out.append(out[-1] + V((s * (b - a).length, 0.0, 0.0)))
    return out


def place_rig(ctx, tpose):
    """KayKit-Skelett laden und auf die Gelenke des Modells setzen. tpose=True: so, wie es ins Spiel kommt (Arme
    waagerecht wie in der KayKit-Ruhepose, damit alle Animationen stimmen); False: Hilfsskelett in der Haltung des
    Modells, nur zum Berechnen der Gewichte."""
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(PROJECT, KAYKIT))
    new = [o for o in bpy.context.scene.objects if o not in before]
    arm = next(o for o in new if o.type == "ARMATURE")
    for o in new:
        if o.type != "ARMATURE":
            bpy.data.objects.remove(o, do_unlink=True)   # Mage-Mesh und Waffen
    if arm.animation_data:
        arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    bpy.context.view_layer.objects.active = arm
    ctx.setdefault("kaykit_hips_z", arm.data.bones["hips"].head_local.z)
    bpy.ops.object.mode_set(mode="EDIT")
    ebs = arm.data.edit_bones
    old = {b.name: (b.head.copy(), b.tail.copy(), b.roll) for b in ebs}
    J = lambda n: V(JOINTS[n])
    mid = lambda a, b: (a + b) * 0.5
    seg = {   # Name -> (Kopf, Ende) der Körperknochen
        "hips": (J("hips"), J("spine")), "spine": (J("spine"), J("chest")), "chest": (J("chest"), J("neck")),
        "head": (J("neck") + V((0, -0.03, 0.01)), J("top")),
    }
    for side, s in (("l", 1.0), ("r", -1.0)):
        up = V((s * JOINTS["upperleg"][0], JOINTS["upperleg"][1], JOINTS["upperleg"][2]))
        lo_, ft, ba, to = (V(LEGS[side][n]) for n in ("lowerleg", "foot", "ball", "toe"))
        seg["upperleg." + side] = (up, lo_)
        seg["lowerleg." + side] = (lo_, ft)
        seg["foot." + side] = (ft, ba)
        seg["toes." + side] = (ba, to)
        pts = arm_points(side, tpose)
        for i, name in enumerate(ARM_BONES):
            seg["%s.%s" % (name, side)] = (pts[i], pts[i + 1])
        # Handslot: Lage relativ zur Hand wie bei KayKit (Griffpunkt etwas unter der Handachse), mit der Handlänge skaliert
        h_old = old["hand." + side]
        hand_k = (pts[4] - pts[3]).length / (h_old[1] - h_old[0]).length
        hs = old["handslot." + side]
        axis = (pts[4] - pts[3]).normalized()
        seg["handslot." + side] = (pts[3] + axis * (HAND_LENGTH[side] * 0.45), None)   # Mitte der Faust: dort sitzt der Stab
    new_head = {}

    def place(name):
        b = ebs[name]
        h, t, _ = old[name]
        if name in seg:
            new_head[name] = seg[name][0].copy()
        elif b.parent is None:
            new_head[name] = h.copy()
        else:   # Hilfsknochen (IK, Rollen): Lage relativ zum Elternknochen wie bei KayKit
            new_head[name] = new_head[b.parent.name] + (h - old[b.parent.name][0])
        for c in b.children:
            place(c.name)

    for b in ebs:
        if b.parent is None:
            place(b.name)
    for b in ebs:
        h, t, roll = old[b.name]
        use_connect = b.use_connect
        b.use_connect = False
        b.head = new_head[b.name]
        if b.name in seg and seg[b.name][1] is not None:
            b.tail = seg[b.name][1]
        else:
            b.tail = new_head[b.name] + (t - h) * (1.5 if b.name.startswith("handslot") else 1.0)
        b.roll = roll
        b.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    for b in arm.data.bones:
        b.use_deform = not b.name.startswith(NON_DEFORM)
    return arm


NON_DEFORM = ("root", "control", "IK", "kneeIK", "heelIK", "elbowIK", "handIK", "handslot")


def stage_skeleton(ctx):
    refine_joints(ctx)
    ctx["pose_rig"] = place_rig(ctx, tpose=False)
    ctx["pose_rig"].name = "PoseRig"
    ctx["arm"] = place_rig(ctx, tpose=True)
    ctx["arm"].name = "Rig"
    for n in ("hips", "upperleg.l", "lowerleg.l", "foot.l", "chest", "upperarm.l", "lowerarm.l", "hand.l", "upperarm.r", "lowerarm.r", "hand.r", "head"):
        j = ctx["arm"].matrix_world @ ctx["arm"].data.bones[n].head_local
        log("%-11s (%.2f %.2f %.2f)" % (n, j.x, j.y, j.z))


# --- Phase 3: Gewichte ---------------------------------------------------------------------------------

def select_only(*objs, active=None):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active or objs[-1]


def nearest_bone_fix(body, arm):
    """Punkte ohne Gewicht (z. B. lose Teile, bei denen die Wärmeberechnung scheitert): zum nächsten Knochen."""
    segs = [(b.name, arm.matrix_world @ b.head_local, arm.matrix_world @ b.tail_local) for b in arm.data.bones if b.use_deform]
    fixed = 0
    for v in body.data.vertices:
        if any(g.weight > 0.0 for g in v.groups):
            continue
        best, name = 1e9, None
        for n, h, t in segs:
            d = t - h
            k = max(0.0, min(1.0, (v.co - h).dot(d) / max(d.dot(d), 1e-9)))
            dist = (h + d * k - v.co).length
            if dist < best:
                best, name = dist, n
        body.vertex_groups[name].add([v.index], 1.0, "REPLACE")
        fixed += 1
    return fixed


def clean_weights(body, limit=4):
    bpy.ops.object.mode_set(mode="OBJECT")
    select_only(body)
    bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=limit)
    bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)


def pose_arms_to_t(ctx):
    """Arme des Hilfsskeletts waagerecht stellen (Länge je Segment bleibt); Schulterpunkte bleiben stehen. Die rechte
    Hand wird zusätzlich um die Unterarmachse gedreht, so dass der Stab (durch die Faust) in T-Pose nach vorn (-Y) zeigt:
    so liegt der KayKit-Stab in der Ruhepose, und die Animationen erwarten ihn dort. Gibt die Bewegung der rechten
    Hand zurück (für den Stab)."""
    rig = ctx["pose_rig"]
    hand_move = None
    for side, s in (("l", 1.0), ("r", -1.0)):
        target = V((s, 0.0, 0.0))
        head = None
        for name in ARM_BONES:
            b = rig.data.bones["%s.%s" % (name, side)]
            pb = rig.pose.bones[b.name]
            rest = rig.matrix_world @ b.matrix_local
            rest_dir = (b.tail_local - b.head_local).normalized()
            q = rest_dir.rotation_difference(target)
            head = (rig.matrix_world @ b.head_local) if head is None else head
            roll = Matrix.Identity(4)
            if name == "hand" and side == "r" and ctx.get("staff_axis") is not None:
                a = q @ ctx["staff_axis"]
                alpha = math.atan2(a.z, a.y)
                roll = Matrix.Rotation(math.pi - alpha, 4, "X")   # Staffachse (y, z) -> -Y
            m = Matrix.Translation(head) @ roll @ q.to_matrix().to_4x4() @ rest.to_3x3().to_4x4()
            pb.matrix = m
            bpy.context.view_layer.update()
            if name == "hand" and side == "r":
                hand_move = m @ rest.inverted()
            head = head + target * b.length
    return hand_move


def stage_weights(ctx):
    body, prig, rig = ctx["body"], ctx["pose_rig"], ctx["arm"]
    for b in prig.data.bones:
        b.use_deform = not b.name.startswith(NON_DEFORM)
    select_only(body, prig, active=prig)
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    missing = sum(1 for v in body.data.vertices if not any(g.weight > 0.0 for g in v.groups))
    log("Wärmegewichte: %d Gruppen, ohne Gewicht: %d" % (len(body.vertex_groups), missing))
    log("nachgetragen: %d Punkte" % nearest_bone_fix(body, prig))
    clean_weights(body)
    # Arme in T-Pose: Netz mit dem Hilfsskelett verformen und das Ergebnis festhalten
    prepare_staff(ctx)
    hand_move = pose_arms_to_t(ctx)
    dg = bpy.context.evaluated_depsgraph_get()
    ev = body.evaluated_get(dg).to_mesh()
    new_co = [v.co.copy() for v in ev.vertices]
    for v, c in zip(body.data.vertices, new_co):
        v.co = c
    body.evaluated_get(dg).to_mesh_clear()
    body.data.update()
    for m in list(body.modifiers):
        body.modifiers.remove(m)
    body.parent = None
    body.matrix_world = Matrix.Identity(4)
    bpy.data.objects.remove(prig, do_unlink=True)
    ctx["pose_rig"] = None
    # an das Spielskelett (T-Pose) hängen: gleiche Knochennamen, Gewichte bleiben
    mod = body.modifiers.new("Armature", "ARMATURE")
    mod.object = rig
    body.parent = rig
    for b in rig.data.bones:
        b.use_deform = not b.name.startswith(NON_DEFORM)
    for b in rig.data.bones:
        if b.name.startswith("handslot"):
            b.use_deform = True
    attach_staff(ctx, hand_move)
    log("Netz in T-Pose am Spielskelett, Höhe %.2f, Armspannweite %.2f" % (
        body.dimensions.z, max(v.co.x for v in body.data.vertices) - min(v.co.x for v in body.data.vertices)))


def prepare_staff(ctx):
    """Achse des Stabs (Schaft unter dem Ring, von unten nach oben) und Griffpunkt in der Haltung des Modells."""
    import numpy as np
    staff = ctx["staff_obj"]
    shaft = np.array([v.co[:] for v in staff.data.vertices if v.co.z < 1.2])
    centre = shaft.mean(0)
    axis = np.linalg.svd(shaft - centre, full_matrices=False)[2][0]
    if axis[2] < 0:
        axis = -axis
    a = V(axis.tolist())
    pts = arm_points("r", False)
    fist = pts[3] + (pts[4] - pts[3]) * 0.45
    c = V(centre.tolist())
    ctx["staff_axis"] = a.normalized()
    ctx["staff_grip"] = c + a.normalized() * (fist - c).dot(a.normalized())   # Punkt der Staffachse nächst der Faust
    log("Stabachse (%.2f %.2f %.2f), Griff (%.2f %.2f %.2f)" % (a.x, a.y, a.z, ctx["staff_grip"].x, ctx["staff_grip"].y, ctx["staff_grip"].z))


def attach_staff(ctx, hand_move):
    """Stab mit der Hand bewegen, dann um den Griffpunkt nach vorn (-Y) richten, in die Faust legen und an handslot.r hängen."""
    staff, rig = ctx["staff_obj"], ctx["arm"]
    ts = hand_move.to_3x3()
    grip = hand_move @ ctx["staff_grip"]
    axis = ts @ ctx["staff_axis"]
    rc = axis.rotation_difference(V((0.0, -1.0, 0.0))).to_matrix()
    fist = rig.matrix_world @ rig.data.bones["handslot.r"].head_local
    log("Stab neigt sich nach der Drehung um %.1f Grad aus der Achse" % math.degrees(axis.angle(V((0.0, -1.0, 0.0)))))
    for v in staff.data.vertices:
        v.co = fist + rc @ ((hand_move @ v.co) - grip)
    staff.data.update()
    staff.name = "Staff"
    vg = staff.vertex_groups.new(name="handslot.r")
    vg.add([v.index for v in staff.data.vertices], 1.0, "REPLACE")
    mod = staff.modifiers.new("Armature", "ARMATURE")
    mod.object = rig
    staff.parent = rig


def scale_hips_location(ctx):
    """Positionsspuren der Hüfte (relativ zur Ruhepose) mit der Hüfthöhe skalieren, sonst schwebt/sinkt die Figur."""
    arm = ctx["arm"]
    factor = arm.data.bones["hips"].head_local.z / ctx["kaykit_hips_z"]
    count = 0
    for act in bpy.data.actions:
        bags = []
        for layer in getattr(act, "layers", []):
            for strip in layer.strips:
                bags += list(getattr(strip, "channelbags", []))
        curves = [fc for bag in bags for fc in bag.fcurves] if bags else list(getattr(act, "fcurves", []))
        for fc in curves:
            if fc.data_path == 'pose.bones["hips"].location':
                for kp in fc.keyframe_points:
                    kp.co.y *= factor
                    kp.handle_left.y *= factor
                    kp.handle_right.y *= factor
                count += 1
    log("Hüftspuren skaliert (x%.2f): %d" % (factor, count))


TEST_POSES = (("Idle", 10), ("Walking_A", 8), ("Running_A", 6), ("Spellcast_Shoot", 14), ("Death_A", 40))
SLAM_FRAMES = (0, 8, 16, 27, 31, 38)


def render_poses(ctx, folder):
    arm = ctx["arm"]
    arm.animation_data_create()
    cam = bd.setup_render(res=(700, 900), samples=24)
    cam.data.lens = 70
    mat = bd.clay("Clay", (0.30, 0.27, 0.26))
    for obj in (ctx["body"], ctx.get("staff_obj")):
        if obj is not None:
            obj.data.materials.clear()
            obj.data.materials.append(mat)
    for name, frame in TEST_POSES:
        act = bpy.data.actions.get(name)
        if act is None:
            log("Animation %s fehlt" % name)
            continue
        arm.animation_data.action = act
        bpy.context.scene.frame_set(frame)
        bpy.context.view_layer.update()
        for view in ("front", "side"):
            pos, target = VIEWS[view]
            bd.look(cam, pos, target)
            bpy.context.scene.render.filepath = os.path.join(folder, "hexer_pose_%s_%s.png" % (name, view))
            bpy.ops.render.render(write_still=True)


# --- Phase 4b: eigene Animationen (Staff_Slam, Hexer_Idle) ----------------------------------------------
# Die Posen werden über Zielpunkte gesetzt: Rumpf neigen, Beine und rechter Arm per Zwei-Knochen-IK, der Stab
# (Achse = Handslot -Y in der Ruhepose) wird in die gewünschte Richtung gedreht. Jede Pose bekommt Schlüssel.

KEYED = ["hips", "spine", "chest", "head"] + ["%s.%s" % (n, s) for s in ("l", "r") for n in
                                               ("upperarm", "lowerarm", "wrist", "hand", "upperleg", "lowerleg", "foot", "toes")]
STAFF_BELOW_GRIP = 1.0      ## Stablänge unter der Faust (Meter): so hoch liegt die Faust über dem Boden, wenn er aufgesetzt ist


def _rest(rig, name):
    return rig.matrix_world @ rig.data.bones[name].matrix_local


def _lean(rig, name, degrees, axis="X"):
    """Knochen um eine Weltachse neigen (Drehung um seinen Kopf; Ruhepose aller Rumpfknochen steht senkrecht)."""
    pb = rig.pose.bones[name]
    r3 = _rest(rig, name).to_3x3()
    rw = Matrix.Rotation(math.radians(degrees), 3, axis)
    pb.rotation_mode = "QUATERNION"
    pb.rotation_quaternion = (r3.inverted() @ rw @ r3).to_quaternion()


def _place(rig, name, head, direction):
    """Knochen mit Kopf an head in Richtung direction (kleinste Drehung aus der Ruhepose)."""
    b = rig.data.bones[name]
    rest_dir = (b.tail_local - b.head_local).normalized()
    q = rest_dir.rotation_difference(V(direction).normalized())
    rig.pose.bones[name].matrix = Matrix.Translation(head) @ q.to_matrix().to_4x4() @ _rest(rig, name).to_3x3().to_4x4()
    bpy.context.view_layer.update()


def two_bone(rig, upper, lower, root, target, pole):
    """Zwei-Knochen-IK: gibt (Gelenk, Ende) zurück. Länge der Knochen aus dem Skelett, pole = Richtung, in die das Gelenk knickt."""
    l1, l2 = rig.data.bones[upper].length, rig.data.bones[lower].length
    d = (target - root)
    dist = min(max(d.length, abs(l1 - l2) + 1e-4), l1 + l2 - 1e-4)
    u = d.normalized()
    a = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
    h = math.sqrt(max(l1 * l1 - a * a, 0.0))
    p = V(pole)
    perp = (p - u * p.dot(u)).normalized()
    joint = root + u * a + perp * h
    return joint, root + u * dist


def pose_right_arm(rig, fist, staff_dir, hand_hint, pole):
    """Rechter Arm: Faust an fist, Stab in staff_dir. Die Handachse steht senkrecht zum Stab (wie in der Ruhepose)."""
    s_dir = V(staff_dir).normalized()
    base = V(hand_hint)
    d_h = (base - s_dir * base.dot(s_dir)).normalized()           # Handachse (Handgelenk -> Faust)
    wrist_len = rig.data.bones["wrist.r"].length
    hand_len = rig.data.bones["hand.r"].length
    wrist = fist - d_h * (wrist_len + hand_len * 0.45)
    shoulder = rig.pose.bones["upperarm.r"].head.copy()
    elbow, wrist = two_bone(rig, "upperarm.r", "lowerarm.r", shoulder, wrist, pole)
    _place(rig, "upperarm.r", shoulder, elbow - shoulder)
    _place(rig, "lowerarm.r", elbow, wrist - elbow)
    _place(rig, "wrist.r", wrist, d_h)
    # Hand: Ruheachsen (y = -X, Stab = -Y) auf (d_h, s_dir) drehen
    y_rest, s_rest = V((-1.0, 0.0, 0.0)), V((0.0, -1.0, 0.0))
    frame_rest = Matrix((y_rest, s_rest, y_rest.cross(s_rest))).transposed()
    frame_new = Matrix((d_h, s_dir, d_h.cross(s_dir))).transposed()
    r_world = frame_new @ frame_rest.inverted()
    head = wrist + d_h * wrist_len
    rig.pose.bones["hand.r"].matrix = Matrix.Translation(head) @ r_world.to_4x4() @ _rest(rig, "hand.r").to_3x3().to_4x4()
    bpy.context.view_layer.update()


def pose_left_arm(rig, swing=0.0):
    """Linker Arm entspannt, in der gemessenen Haltung des Modells (Hand hängt neben dem Körper); swing in Grad nach vorn."""
    pts = [V(p) if p else None for p in ARMS["l"]]
    pts[4] = pts[3] + (pts[3] - pts[2]).normalized() * HAND_LENGTH["l"]
    tilt = Matrix.Rotation(math.radians(swing), 3, "X")
    head = rig.pose.bones["upperarm.l"].head.copy()
    for i, name in enumerate(("upperarm.l", "lowerarm.l", "wrist.l", "hand.l")):
        direction = tilt @ (pts[i + 1] - pts[i])
        _place(rig, name, head, direction)
        head = head + direction.normalized() * rig.data.bones[name].length


def pose_legs(rig):
    """Beine mit festen Füßen: Hüfte darf sich bewegen, Knie knicken nach vorn."""
    for s in ("l", "r"):
        hip = rig.pose.bones["upperleg." + s].head.copy()
        ankle = _rest(rig, "foot." + s).translation
        knee, ankle = two_bone(rig, "upperleg." + s, "lowerleg." + s, hip, ankle, (0.0, -1.0, 0.0))
        _place(rig, "upperleg." + s, hip, knee - hip)
        _place(rig, "lowerleg." + s, knee, ankle - knee)
        for n in ("foot." + s, "toes." + s):
            rig.pose.bones[n].matrix = _rest(rig, n)
        bpy.context.view_layer.update()


def key_pose(rig, frame, spec):
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    hips = rig.pose.bones["hips"]
    hips.location = _rest(rig, "hips").to_3x3().inverted() @ V((0.0, spec.get("hips_y", 0.0), -spec.get("crouch", 0.0)))
    _lean(rig, "spine", spec.get("lean", 0.0) * 0.5)
    _lean(rig, "chest", spec.get("lean", 0.0) * 0.5)
    _lean(rig, "head", spec.get("head", 0.0))
    bpy.context.view_layer.update()
    pose_legs(rig)
    pose_right_arm(rig, V(spec["fist"]), spec["staff"], spec.get("hint", (-0.5, -0.85, 0.0)), spec.get("pole", (0.0, 0.5, -0.8)))
    pose_left_arm(rig, spec.get("left_swing", 0.0))
    for name in KEYED:
        pb = rig.pose.bones[name]
        pb.rotation_mode = "QUATERNION"
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        if name == "hips":
            pb.keyframe_insert("location", frame=frame)


READY = {"fist": (-0.46, -0.30, STAFF_BELOW_GRIP + 0.02), "staff": (0.0, 0.0, 1.0), "left_swing": 0.0}
# Staff_Slam: aufrecht stehen -> Stab nach hinten hochreißen -> auf den Boden stoßen (Wucht) -> Rückfedern
SLAM = [
    (0, dict(READY)),
    (8, {"fist": (-0.40, -0.05, 1.45), "staff": (0.0, 0.25, 0.97), "lean": -6, "crouch": 0.04, "head": -4, "left_swing": -12}),
    (16, {"fist": (-0.30, 0.18, 2.12), "staff": (0.0, 0.7, 0.71), "lean": -16, "crouch": 0.0, "head": -12, "left_swing": -26,
          "hint": (-0.7, 0.1, 0.0), "pole": (-0.3, 0.2, -0.9)}),
    (19, {"fist": (-0.30, 0.20, 2.17), "staff": (0.0, 0.75, 0.66), "lean": -19, "crouch": 0.0, "head": -14, "left_swing": -30,
          "hint": (-0.7, 0.1, 0.0), "pole": (-0.3, 0.2, -0.9)}),
    (27, {"fist": (-0.40, -0.52, STAFF_BELOW_GRIP + 0.03), "staff": (0.0, -0.12, 0.99), "lean": 20, "crouch": 0.17, "head": 14,
          "left_swing": 22, "hips_y": -0.06}),
    (31, {"fist": (-0.40, -0.55, STAFF_BELOW_GRIP + 0.03), "staff": (0.0, -0.10, 0.99), "lean": 16, "crouch": 0.13, "head": 10,
          "left_swing": 16, "hips_y": -0.04}),
    (45, dict(READY)),
]
IDLE = [(0, dict(READY, lean=0.0)), (30, dict(READY, lean=2.5, head=1.5, left_swing=2.0)), (60, dict(READY, lean=0.0))]


def make_action(rig, name, keys):
    act = bpy.data.actions.new(name)
    rig.animation_data_create()
    rig.animation_data.action = act
    for frame, spec in keys:
        key_pose(rig, frame, spec)
    act.use_fake_user = True
    for fc in act.fcurves if hasattr(act, "fcurves") else []:
        for kp in fc.keyframe_points:
            kp.interpolation = "BEZIER"
    log("Animation %s: %d Posen" % (name, len(keys)))
    return act


def stage_staff(ctx):
    """Phase 4: eigene Animationen auf dem fertigen Modell erzeugen."""
    rig = ctx["arm"]
    make_action(rig, "Hexer_Idle", IDLE)
    make_action(rig, "Staff_Slam", SLAM)
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    rig.animation_data.action = None


# --- Phase 5: Export -----------------------------------------------------------------------------------

def stage_export(ctx):
    rig = ctx["arm"]
    # Der zweite KayKit-Import (Spielskelett) hat Duplikate mit Endung .001 angelegt: weg damit
    for act in [a for a in bpy.data.actions if a.name.endswith(".001")]:
        bpy.data.actions.remove(act)
    rig.animation_data_create()
    rig.animation_data.action = None
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    out = ctx["out"]   # Haut und Stab behalten die Tripo-Textur
    os.makedirs(os.path.dirname(out), exist_ok=True)
    for o in bpy.context.scene.objects:
        o.select_set(False)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=False, export_animations=True,
                              export_animation_mode="ACTIONS", export_skins=True, export_def_bones=False, export_yup=True,
                              export_image_format="JPEG", export_jpeg_quality=90)
    log("exportiert -> %s (%.1f MB, %d Animationen)" % (out, os.path.getsize(out) / 1e6, len(bpy.data.actions)))


def render_slam(ctx, folder):
    rig = ctx["arm"]
    cam = bd.setup_render(res=(600, 800), samples=20)
    cam.data.lens = 60
    mat = bd.clay("Clay", (0.30, 0.27, 0.26))
    for obj in (ctx["body"], ctx["staff_obj"]):
        obj.data.materials.clear()
        obj.data.materials.append(mat)
    rig.animation_data.action = bpy.data.actions["Staff_Slam"]
    for f in SLAM_FRAMES:
        bpy.context.scene.frame_set(f)
        bpy.context.view_layer.update()
        for view in ("front", "side"):
            pos, target = VIEWS[view]
            bd.look(cam, pos, target)
            bpy.context.scene.render.filepath = os.path.join(folder, "hexer_slam_%02d_%s.png" % (f, view))
            bpy.ops.render.render(write_still=True)


# --- Vorschau ------------------------------------------------------------------------------------------

def show_bones(arm, color, radius=0.012):
    """Knochen als dünne Zylinder (Cycles zeigt keine Armaturen). Körper wird dafür durchsichtig gemacht."""
    mat = bpy.data.materials.new("Bone" + arm.name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.remove(nt.nodes["Principled BSDF"])
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs[0].default_value = color
    em.inputs[1].default_value = 4.0
    nt.links.new(em.outputs[0], nt.nodes["Material Output"].inputs[0])
    for b in arm.data.bones:
        if not b.use_deform and not b.name.startswith("handslot"):
            continue
        h, t = arm.matrix_world @ b.head_local, arm.matrix_world @ b.tail_local
        if (t - h).length < 1e-4:
            continue
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=radius, radius2=radius * 0.3, depth=(t - h).length)
        bmesh.ops.translate(bm, verts=bm.verts, vec=V((0, 0, (t - h).length * 0.5)))
        me = bpy.data.meshes.new("b")
        bm.to_mesh(me)
        o = bpy.data.objects.new("bone_" + b.name, me)
        o.rotation_euler = (t - h).to_track_quat("Z", "Y").to_euler()
        o.location = h
        o.data.materials.append(mat)
        bpy.context.scene.collection.objects.link(o)


def glass_body(ctx, alpha=0.28):
    mat = bpy.data.materials.new("BodyGlass")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.5, 0.55, 0.65, 1)
    bsdf.inputs["Alpha"].default_value = alpha
    ctx["body"].data.materials.clear()
    ctx["body"].data.materials.append(mat)


VIEWS = {
    "front": ((0.0, -6.5, 1.15), (0.0, 0.0, 1.05)),
    "side": ((-6.5, 0.0, 1.15), (0.0, 0.0, 1.05)),
    "back": ((0.0, 6.5, 1.15), (0.0, 0.0, 1.05)),
}


def render(folder, tag, views=("front", "side"), res=(900, 1150)):
    cam = bd.setup_render(res=res, samples=32)
    cam.data.lens = 85
    for name in views:
        pos, target = VIEWS[name]
        bd.look(cam, pos, target)
        bpy.context.scene.render.filepath = os.path.join(folder, "hexer_%s_%s.png" % (tag, name))
        bpy.ops.render.render(write_still=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    stage = argv[argv.index("--stage") + 1] if "--stage" in argv else STAGES[-1]
    preview = argv[argv.index("--preview") + 1] if "--preview" in argv else None
    ctx = {"src": argv[argv.index("--src") + 1] if "--src" in argv else SRC_DEFAULT,
           "out": argv[argv.index("--out") + 1] if "--out" in argv else os.path.join(PROJECT, "assets", "models", "enemies_custom", "AbyssHexer.glb")}
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 30
    bpy.context.scene.render.fps_base = 1.0
    stage_mesh(ctx)
    split_staff(ctx)
    fit_to_height(ctx)
    if STAGES.index(stage) >= 1:
        stage_skeleton(ctx)
    if STAGES.index(stage) >= 2:
        stage_weights(ctx)
        scale_hips_location(ctx)
    if STAGES.index(stage) >= 3:
        stage_staff(ctx)
    if STAGES.index(stage) >= 4:
        stage_export(ctx)
    if preview:
        ctx["staff_obj"].hide_render = STAGES.index(stage) < 3   # bis zur Stab-Phase: Körper allein
        if stage == "skeleton":
            glass_body(ctx)
            show_bones(ctx["pose_rig"], (1.0, 0.25, 0.1, 1.0))   # rot: Hilfsskelett in der Haltung des Modells
            show_bones(ctx["arm"], (0.2, 1.0, 0.3, 1.0), 0.008)   # grün: Skelett im Spiel (T-Pose)
        if stage == "weights":
            render_poses(ctx, preview)
        elif stage == "staff":
            render_slam(ctx, preview)
        else:
            render(preview, stage, ("front", "side"))
    log("fertig.")


if __name__ == "__main__":
    main()
