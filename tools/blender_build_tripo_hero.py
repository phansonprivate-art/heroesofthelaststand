"""Tripo-Figuren als Helden-Modelle: allgemeine Fassung des Hexer-Ablaufs (tools/blender_build_hexer.py).

Jede Figur hat einen Eintrag in CHARACTERS (Quelle, Ziel, Höhe, Spiegeln, Waffe, Gelenke). Der Ablauf:
  1 mesh      Netz laden, Nähte verschweißen, Waffe abtrennen (Stab) bzw. merken (Klingen), Größe/Ausrichtung
  2 skeleton  KayKit-Skelett (Rig_Medium) auf die Gelenke der Figur setzen
  3 weights   Gewichte in der Haltung der Figur, dann Arme in T-Pose; Klingen fest an der Hand
  4 export    GLB mit allen KayKit-Animationen

Aufruf (Blender 5.2, ohne Oberfläche):
  blender.exe --background --python tools/blender_build_tripo_hero.py -- --char zauberer [--stage mesh] [--preview <ordner>]
Mit --stage mesh --preview entstehen Rasterbilder (10 cm), an denen die Gelenke abgelesen werden.
"""
import math
import os
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import blender_build_dragon as bd
import blender_build_hexer as h

V = Vector
STAGES = ["mesh", "skeleton", "weights", "export"]
DOWNLOADS = "C:/Users/phant/Downloads/character/"
log = lambda msg: print("[tripo-held] %s" % msg, flush=True)

# Gelenke nach Ausrichtung (x = Figur-links, y = hinten, z = oben, Füße auf 0), aus den Rasterbildern abgelesen.
CHARACTERS = {
    "zauberer": {
        "src": DOWNLOADS + "Zauberer.glb",
        "out": "assets/models/heroes_custom/ArcanistTripo.glb",
        "height": 2.0, "mirror": False, "weapon": "staff",
        "shift_x": 0.21,   # der weite Umhang verschiebt die Mitte aus den Beinen: Rumpf auf x = 0 rücken
        "joints": {"hips": (0.0, 0.0, 1.04), "spine": (0.0, 0.0, 1.19), "chest": (0.02, 0.0, 1.36), "neck": (0.04, 0.0, 1.56),
                   "top": (0.08, 0.0, 1.93), "upperleg": (0.10, 0.0, 0.98)},
        "legs": {"l": {"lowerleg": (0.29, 0.0, 0.56), "foot": (0.48, 0.03, 0.13), "ball": (0.50, -0.08, 0.04), "toe": (0.50, -0.18, 0.04)},
                 "r": {"lowerleg": (-0.25, 0.0, 0.56), "foot": (-0.40, 0.03, 0.13), "ball": (-0.42, -0.08, 0.04), "toe": (-0.42, -0.18, 0.04)}},
        "arms": {"l": [(0.28, 0.0, 1.58), (0.47, -0.12, 1.41), (0.61, -0.27, 1.51), (0.65, -0.29, 1.52), None],
                 "r": [(-0.22, 0.0, 1.60), (-0.37, -0.12, 1.41), (-0.43, -0.25, 1.37), (-0.46, -0.28, 1.36), None]},
        "hand_length": {"l": 0.17, "r": 0.10},
    },
    "krieger": {
        "src": DOWNLOADS + "fantasy knight 3d model.glb",
        "out": "assets/models/heroes_custom/GuardianTripo.glb",
        "height": 2.0, "mirror": False, "weapon": "held", "shift_x": 0.08,
        "joints": {"hips": (0.0, 0.0, 1.06), "spine": (0.0, 0.0, 1.23), "chest": (0.0, 0.0, 1.41), "neck": (0.0, 0.0, 1.66),
                   "top": (0.0, 0.0, 1.95), "upperleg": (0.12, 0.0, 1.00)},
        "legs": {"l": {"lowerleg": (0.23, 0.0, 0.64), "foot": (0.37, 0.03, 0.12), "ball": (0.38, -0.08, 0.04), "toe": (0.38, -0.18, 0.04)},
                 "r": {"lowerleg": (-0.24, 0.0, 0.64), "foot": (-0.29, 0.03, 0.12), "ball": (-0.30, -0.08, 0.04), "toe": (-0.30, -0.18, 0.04)}},
        "arms": {"l": [(0.27, 0.05, 1.55), (0.36, -0.05, 1.27), (0.38, -0.20, 1.05), (0.38, -0.26, 0.98), None],
                 "r": [(-0.23, 0.05, 1.55), (-0.31, 0.12, 1.27), (-0.31, 0.25, 1.05), (-0.32, 0.28, 0.96), None]},
        "hand_length": {"l": 0.12, "r": 0.12},
        # Waffen fest an eine Hand: Bereich (min, max) in den Koordinaten nach dem Ausrichten
        "held": [{"bone": "hand.l", "box": ((0.15, -1.2, 0.42), (1.2, -0.40, 1.36))},    # Schild vor dem linken Arm (Kniepanzer liegen weiter hinten)
                 {"bone": "hand.r", "box": ((-1.2, -1.2, 0.30), (-0.42, 1.2, 1.10))}],   # Schwert rechts unten
    },
    "assassine": {
        "src": DOWNLOADS + "assassin character 3d model.glb",
        "out": "assets/models/heroes_custom/ShadowTripo.glb",
        "height": 2.0, "mirror": False, "weapon": "blades", "shift_x": 0.0,
        "joints": {"hips": (0.0, 0.0, 1.08), "spine": (0.0, 0.0, 1.23), "chest": (0.0, 0.0, 1.36), "neck": (0.0, 0.0, 1.56),
                   "top": (0.0, 0.0, 1.95), "upperleg": (0.09, 0.0, 1.03)},
        "legs": {"l": {"lowerleg": (0.11, 0.0, 0.53), "foot": (0.11, 0.03, 0.15), "ball": (0.11, -0.08, 0.04), "toe": (0.11, -0.18, 0.04)},
                 "r": {"lowerleg": (-0.11, 0.0, 0.53), "foot": (-0.11, 0.03, 0.15), "ball": (-0.11, -0.08, 0.04), "toe": (-0.11, -0.18, 0.04)}},
        "arms": {"l": [(0.22, 0.0, 1.47), (0.33, 0.0, 1.21), (0.37, -0.02, 0.99), (0.37, -0.02, 0.95), None],
                 "r": [(-0.22, 0.0, 1.47), (-0.33, 0.0, 1.21), (-0.37, -0.02, 0.99), (-0.37, -0.02, 0.95), None]},
        "hand_length": {"l": 0.12, "r": 0.12},
    },
}


# --- Phase 1: Netz ----------------------------------------------------------------------------------

def classify_staff(ctx, cfg):
    """Stab = langes dünnes Teil plus alles, was dicht an seiner Achse liegt (Kristall, Ringe). Die Hand, die den
    Stab umgreift, liegt weiter von der Achse weg und bleibt am Körper."""
    import numpy as np
    parts = ctx["parts"]
    tall = max(range(1, len(parts)), key=lambda i: (h.bbox(parts[i])[1].z - h.bbox(parts[i])[0].z) / max(1e-6,
               max(h.bbox(parts[i])[1].x - h.bbox(parts[i])[0].x, h.bbox(parts[i])[1].y - h.bbox(parts[i])[0].y)))
    pts = np.array([v.co[:] for v in parts[tall]])
    z0, z1 = pts[:, 2].min(), pts[:, 2].max()
    shaft = pts[(pts[:, 2] > z0 + 0.15 * (z1 - z0)) & (pts[:, 2] < z0 + 0.6 * (z1 - z0))]   # ohne Kopf und Spitze
    centre = shaft.mean(0)
    axis = np.linalg.svd(shaft - centre, full_matrices=False)[2][0]
    radius = float(np.percentile(np.linalg.norm(np.cross(shaft - centre, axis), axis=1), 90)) * 2.0
    staff = [tall]
    for i, p in enumerate(parts):
        if i in (0, tall):
            continue
        q = np.array([v.co[:] for v in p])
        dist = np.linalg.norm(np.cross(q - centre, axis), axis=1)
        top = q[:, 2].min() > z0 + 0.75 * (z1 - z0)   # Teile am Stabkopf (Kristall, Zacken) dürfen weiter abstehen
        if float(dist.max()) < radius * 1.5 or (top and float(dist.max()) < radius * 6.0):
            staff.append(i)
    ctx["staff"] = staff
    ctx["keep"] = [i for i in range(len(parts)) if i not in staff]
    log("Stab: Teile %s (Achsradius %.3f), Körper: %d Teile" % (staff, radius, len(ctx["keep"])))


def fit(ctx, cfg):
    """Größe auf cfg.height, Füße auf z = 0, Mitte aus Beinen/Füßen; optional spiegeln (Waffenhand = rechts, -X)."""
    body = ctx["body"]
    co = [v.co for v in body.data.vertices]
    lo = V([min(c[i] for c in co) for i in range(3)])
    hi = V([max(c[i] for c in co) for i in range(3)])
    k = cfg["height"] / (hi.z - lo.z)
    legs = [c for c in co if lo.z + 0.1 * (hi.z - lo.z) < c.z < lo.z + 0.35 * (hi.z - lo.z)]
    feet = [c for c in co if c.z < lo.z + 0.06 * (hi.z - lo.z)]
    cx = sum(c.x for c in legs) / len(legs)
    cy = sum(c.y for c in feet) / len(feet)
    sx = -1.0 if cfg["mirror"] else 1.0
    for obj in (body, ctx.get("staff_obj")):
        if obj is None:
            continue
        for v in obj.data.vertices:
            v.co = V((sx * (v.co.x - cx) * k + cfg.get("shift_x", 0.0), (v.co.y - cy) * k, (v.co.z - lo.z) * k))
        if cfg["mirror"]:
            bm2 = bmesh.new()
            bm2.from_mesh(obj.data)
            bmesh.ops.reverse_faces(bm2, faces=bm2.faces)
            bm2.to_mesh(obj.data)
            bm2.free()
        obj.data.update()
    log("Maßstab %.3f; Körper %.2f x %.2f x %.2f m" % (k, (hi.x - lo.x) * k, (hi.y - lo.y) * k, (hi.z - lo.z) * k))


def blade_weights(ctx):
    """Klingen (unterhalb des Handgelenks, außerhalb der Beine) ganz an die Hand hängen, sonst ziehen die
    Oberschenkel sie mit. Wird nach den Wärmegewichten, vor dem Wechsel in die T-Pose aufgerufen."""
    body = ctx["body"]
    groups = {g.name: g for g in body.vertex_groups}
    moved = 0
    for side, s in (("l", 1.0), ("r", -1.0)):
        wrist = V(h.ARMS[side][2])
        hand = groups.get("hand." + side)
        if hand is None:
            continue
        for v in body.data.vertices:
            c = v.co
            if s * c.x > abs(wrist.x) - 0.06 and c.z < wrist.z + 0.02 and c.z > wrist.z - 0.55:
                for g in list(v.groups):
                    body.vertex_groups[g.group].remove([v.index])
                hand.add([v.index], 1.0, "REPLACE")
                moved += 1
    log("Klingen an die Hände gehängt: %d Punkte" % moved)


def held_weights(ctx, cfg):
    """Waffen (Schwert, Schild) über Bereiche ganz an eine Hand hängen, damit sie sich nicht mit Beinen oder Rumpf
    verbiegen. Wird nach den Wärmegewichten, vor dem Wechsel in die T-Pose aufgerufen.
    Jedes zusammenhängende Netzteil, das zu einem guten Teil im Bereich liegt, kommt ganz an die Hand – sonst folgen
    Griff oder Klingenende, die außerhalb des Bereichs liegen, dem Unterarm und die Waffe knickt. Teile, die mehr als
    ein Viertel der Figur ausmachen (Körper), werden nie ganz übernommen; dort zählt nur der Bereich."""
    body = ctx["body"]
    bm = bmesh.new()
    bm.from_mesh(body.data)
    parts = [[v.index for v in p] for p in h.islands(bm)]
    bm.free()
    total = len(body.data.vertices)
    for rule in cfg["held"]:
        lo, hi = V(rule["box"][0]), V(rule["box"][1])
        group = body.vertex_groups.get(rule["bone"])
        inside = {v.index for v in body.data.vertices if all(lo[i] <= v.co[i] <= hi[i] for i in range(3))}
        idx = set(inside)
        whole = 0
        for p in parts:
            hits = sum(1 for i in p if i in inside)
            if hits and len(p) < total * 0.25 and hits >= len(p) * float(rule.get("part_share", 0.3)):
                idx.update(p)
                whole += 1
        idx = sorted(idx)
        for i in idx:
            for g in list(body.data.vertices[i].groups):
                body.vertex_groups[g.group].remove([i])
        group.add(idx, 1.0, "REPLACE")
        log("%s: %d Punkte fest an der Hand (%d Teile ganz)" % (rule["bone"], len(idx), whole))


# --- Vorschau ---------------------------------------------------------------------------------------

def render_grid(ctx, folder, tag):
    """Front- und Seitenbild mit 10-cm-Raster in den Koordinaten des Ablaufs (zum Ablesen der Gelenke)."""
    cam = bd.setup_render(res=(1000, 1250), samples=16)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 2.3

    def line(name, size, color):
        me = bpy.data.meshes.new(name)
        b = bmesh.new()
        bmesh.ops.create_cube(b, size=1.0)
        for v in b.verts:
            v.co = V((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
        b.to_mesh(me)
        o = bpy.data.objects.new(name, me)
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        n = m.node_tree.nodes
        n.remove(n["Principled BSDF"])
        e = n.new("ShaderNodeEmission")
        e.inputs[0].default_value = color
        e.inputs[1].default_value = 3
        m.node_tree.links.new(e.outputs[0], n["Material Output"].inputs[0])
        me.materials.append(m)
        bpy.context.scene.collection.objects.link(o)
        return o

    rows = [(line("h%d" % i, (2.4, 0.002, 0.005 if i % 5 == 0 else 0.002), (1, .2, .2, 1) if i % 5 == 0 else (1, 1, .2, 1)), i * 0.1)
            for i in range(0, 22)]
    cols = [(line("v%d" % i, (0.005 if i % 5 == 0 else 0.002, 0.002, 2.4), (.2, 1, .2, 1) if i % 5 == 0 else (.2, .8, 1, 1)), i * 0.1)
            for i in range(-10, 11)]
    for view in ("front", "side"):
        for o, z in rows:
            o.location = (0, -1.0, z) if view == "front" else (-1.0, 0, z)
            o.rotation_euler = (0, 0, 0 if view == "front" else math.pi / 2)
        for o, x in cols:
            o.location = (x, -1.0, 1.0) if view == "front" else (-1.0, x, 1.0)
            o.rotation_euler = (0, 0, 0 if view == "front" else math.pi / 2)
        pos = (0, -6, 1.0) if view == "front" else (-6, 0, 1.0)
        bd.look(cam, pos, (0, 0, 1.0))
        bpy.context.scene.render.filepath = os.path.join(folder, "%s_%s_%s.png" % (tag, "grid", view))
        bpy.ops.render.render(write_still=True)


def render_previews(ctx, folder, tag, stage):
    if stage == "skeleton":
        h.glass_body(ctx)
        h.show_bones(ctx["pose_rig"], (1.0, 0.25, 0.1, 1.0))
        h.show_bones(ctx["arm"], (0.2, 1.0, 0.3, 1.0), 0.008)
        cam = bd.setup_render(res=(900, 1150), samples=24)
        cam.data.lens = 85
        for name in ("front", "side"):
            pos, target = h.VIEWS[name]
            bd.look(cam, pos, target)
            bpy.context.scene.render.filepath = os.path.join(folder, "%s_skeleton_%s.png" % (tag, name))
            bpy.ops.render.render(write_still=True)
    elif stage in ("weights", "export"):
        arm = ctx["arm"]
        arm.animation_data_create()
        cam = bd.setup_render(res=(600, 800), samples=24)
        cam.data.lens = 70
        for name, frame in POSES:
            act = bpy.data.actions.get(name)
            if act is None:
                log("Animation %s fehlt" % name)
                continue
            arm.animation_data.action = act
            bpy.context.scene.frame_set(frame)
            bpy.context.view_layer.update()
            pos, target = h.VIEWS["front"]
            bd.look(cam, (pos[0] + 2.5, pos[1], pos[2]), target)
            bpy.context.scene.render.filepath = os.path.join(folder, "%s_pose_%s.png" % (tag, name))
            bpy.ops.render.render(write_still=True)


POSES = (("Idle", 10), ("Running_A", 6), ("Spellcast_Shoot", 14), ("Dualwield_Melee_Attack_Chop", 12), ("Death_A", 40))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opt = lambda k, d=None: argv[argv.index(k) + 1] if k in argv else d
    name = opt("--char", "zauberer")
    cfg = CHARACTERS[name]
    stage = opt("--stage", STAGES[-1])
    preview = opt("--preview")
    ctx = {"src": opt("--src", cfg["src"]), "out": os.path.join(h.PROJECT, cfg["out"])}
    h.HEIGHT = cfg["height"]
    h.JOINTS = {k: tuple(v) for k, v in cfg["joints"].items()}
    h.LEGS = {s: dict(v) for s, v in cfg["legs"].items()}
    h.ARMS = {s: list(v) for s, v in cfg["arms"].items()}
    h.HAND_LENGTH = dict(cfg["hand_length"])
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 30
    bpy.context.scene.render.fps_base = 1.0
    h.stage_mesh(ctx)          # lädt, verschweißt, zerlegt (die Hexer-Zuordnung wird gleich ersetzt)
    if cfg["weapon"] == "staff":
        classify_staff(ctx, cfg)
        h.split_staff(ctx)
    else:
        ctx["staff_obj"] = None
        ctx["parts_bm"].to_mesh(ctx["body"].data)
        # Haken nach den Wärmegewichten: Klingen bzw. Waffen ganz an die Hände
        h.prepare_staff = (lambda c: held_weights(c, cfg)) if cfg["weapon"] == "held" else (lambda c: blade_weights(c))
        h.attach_staff = lambda c, m: None
    ctx["body"].name = name.capitalize()
    fit(ctx, cfg)
    if preview and stage == "mesh":
        render_grid(ctx, preview, name)
    if STAGES.index(stage) >= 1:
        h.stage_skeleton(ctx)
    if STAGES.index(stage) >= 2:
        h.stage_weights(ctx)
        h.scale_hips_location(ctx)
    if STAGES.index(stage) >= 3:
        h.stage_export(ctx)
    if preview and stage != "mesh":
        if ctx.get("staff_obj") is not None:
            ctx["staff_obj"].hide_render = stage == "skeleton"
        render_previews(ctx, preview, name, stage)
    log("fertig.")


if __name__ == "__main__":
    main()
