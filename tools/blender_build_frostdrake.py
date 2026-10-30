"""Frostdrache: Tripo-Modell (blue dragon.glb, eigener Entwurf des Spielers) auf das Skelett des Glutdrachen übertragen.

Vom Glutdrachen (assets/models/enemies_custom/EmberDrake.glb) kommen Knochennamen, Ausrichtung der Knochen und die
9 Animationen; die Längen der Knochen kommen vom Frostdrachen. So passen die Animationen, ohne den kompakten Körper
in die Länge zu ziehen.

Ablauf:
  1 mesh      Tripo-Netz laden, Texturnähte verschweißen, Maßstab (Blick nach -Y wie alle Modelle)
  2 skeleton  Glutdrachen-Skelett laden; Hilfsskelett auf die Gelenke des Frostdrachen (Werte unten, an Rasterbildern
              abgelesen)
  3 weights   Gewichte mit dem Hilfsskelett in der Haltung des Frostdrachen; dann jeden Knochen in die Ausrichtung des
              Glutdrachen drehen (Netz folgt), Ergebnis ist die neue Ruhepose; Spielskelett = Glutdrachen-Ausrichtung
              mit den Frostdrachen-Längen
  4 export    GLB nach assets/models/enemies_custom/FrostDrake.glb (mit allen Animationen)

Läuft ohne Oberfläche (blender.exe --background --python tools/blender_build_frostdrake.py -- [--stage weights]
[--preview <ordner>]) oder im offenen Blender über die Live-Verbindung (tools/blender_live.js): dann in einer eigenen
Szene „Frostdrache“, ohne die Szene des Spielers anzufassen.
"""
import os
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

V = Vector
PROJECT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SRC_DEFAULT = "C:/Users/phant/Downloads/blue dragon.glb"
EMBER = os.path.join(PROJECT, "assets", "models", "enemies_custom", "EmberDrake.glb")
OUT_DEFAULT = os.path.join(PROJECT, "assets", "models", "enemies_custom", "FrostDrake.glb")
SCALE = 3.0                  ## Tripo-Modell ist 1 m hoch; Schulterhöhe dann wie beim Glutdrachen (~1,3 m)
WELD = 0.0015                ## Texturnähte verschweißen (nach dem Skalieren)
STAGES = ["mesh", "skeleton", "weights", "export"]
log = lambda msg: print("[frostdrache] %s" % msg, flush=True)

# Gelenke des Frostdrachen (Meter, nach dem Skalieren; x = Drachen-links, y = hinten, z = oben): (Kopf, Ende)
BODY = {
    "hips": ((0, 0.75, 1.12), (0, 0.30, 1.35)),
    "spine": ((0, 0.30, 1.35), (0, -0.05, 1.45)),
    "chest": ((0, -0.05, 1.45), (0, -0.27, 1.62)),
    "neck1": ((0, -0.27, 1.64), (0, -0.42, 1.98)),
    "neck2": ((0, -0.42, 1.98), (0, -0.62, 2.20)),
    "neck3": ((0, -0.62, 2.20), (0, -0.92, 2.22)),
    "head": ((0, -0.92, 2.22), (0, -1.38, 1.98)),
    "jaw": ((0, -1.02, 1.95), (0, -1.32, 1.66)),
}
TAIL = [(0, 0.75, 1.12), (0, 0.88, 1.04), (0, 1.0, 0.99), (0, 1.12, 0.97), (0, 1.22, 1.0), (0, 1.31, 1.07), (0, 1.39, 1.17),
        (0, 1.46, 1.30)]
SIDE = {   # linke Seite (+X); die rechte wird gespiegelt
    "f_upper": ((0.39, -0.28, 1.35), (0.55, -0.50, 0.95)),
    "f_lower": ((0.55, -0.50, 0.95), (0.68, -0.78, 0.62)),
    "f_foot": ((0.68, -0.78, 0.62), (0.72, -1.00, 0.40)),
    "h_thigh": ((0.30, 0.62, 1.05), (0.40, 0.36, 0.60)),
    "h_shin": ((0.40, 0.36, 0.60), (0.44, 0.60, 0.27)),
    "h_meta": ((0.44, 0.60, 0.27), (0.45, 0.28, 0.11)),
    "h_toe": ((0.45, 0.28, 0.11), (0.45, -0.10, 0.05)),
    "w_upper": ((0.28, 0.05, 1.75), (0.50, 0.12, 2.25)),
    "w_fore": ((0.50, 0.12, 2.25), (0.66, 0.38, 2.58)),
    "w_f1": ((0.66, 0.38, 2.58), (1.35, 0.84, 0.25)),   # Flügelfinger fächern von der Handwurzel nach unten
    "w_f2": ((0.66, 0.38, 2.58), (1.12, 0.95, 0.55)),
    "w_f3": ((0.66, 0.38, 2.58), (0.85, 1.00, 0.85)),
    "w_f4": ((0.66, 0.38, 2.58), (0.55, 0.85, 1.20)),
}


def joints():
    """Alle Knochen: Name -> (Kopf, Ende) als Vektoren."""
    out = {n: (V(h), V(t)) for n, (h, t) in BODY.items()}
    for i in range(len(TAIL) - 1):
        out["tail%d" % (i + 1)] = (V(TAIL[i]), V(TAIL[i + 1]))
    for n, (h, t) in SIDE.items():
        out[n + ".L"] = (V(h), V(t))
        out[n + ".R"] = (V((-h[0], h[1], h[2])), V((-t[0], t[1], t[2])))
    return out


# --- Umgebung (ohne Oberfläche oder im offenen Blender) ------------------------------------------------

def ui_override():
    """Fenster und 3D-Ansicht für Operatoren, wenn Blender offen ist (Live-Verbindung); sonst leer."""
    wm = bpy.context.window_manager
    for win in wm.windows:
        for area in win.screen.areas:
            if area.type == "VIEW_3D":
                region = next(r for r in area.regions if r.type == "WINDOW")
                return {"window": win, "area": area, "region": region}
    return {}


def op(fn, **kwargs):
    with bpy.context.temp_override(**ui_override()):
        return fn(**kwargs)


def fresh_scene():
    if bpy.app.background:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        return bpy.context.scene
    old = bpy.data.scenes.get("Frostdrache")
    if old is not None:   # alte Fassung samt Inhalt weg (nur diese Szene)
        for o in list(old.objects):
            bpy.data.objects.remove(o, do_unlink=True)
        bpy.data.scenes.remove(old)
    sc = bpy.data.scenes.new("Frostdrache")
    for win in bpy.context.window_manager.windows:
        win.scene = sc
    return sc


def import_glb(path):
    before = set(bpy.data.objects)
    op(bpy.ops.import_scene.gltf, filepath=path)
    return [o for o in bpy.data.objects if o not in before]


def select_only(*objs, active=None):
    bpy.context.view_layer.update()   # gelöschte Objekte sonst noch als leere Einträge in der Ansichtsebene
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active or objs[-1]


# --- Phase 1: Netz -------------------------------------------------------------------------------------

def stage_mesh(ctx):
    new = import_glb(ctx["src"])
    body = next(o for o in new if o.type == "MESH")
    for o in new:
        if o is not body:
            bpy.data.objects.remove(o, do_unlink=True)
    body.parent = None
    body.matrix_world = Matrix.Identity(4)
    body.name = "FrostDrake"
    bm = bmesh.new()
    bm.from_mesh(body.data)
    for v in bm.verts:
        v.co *= SCALE
    before = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=WELD)
    bm.to_mesh(body.data)
    bm.free()
    body.data.update()
    ctx["body"] = body
    log("Netz: %d -> %d Punkte, %d Flächen, %.2f x %.2f x %.2f m" % (before, len(body.data.vertices), len(body.data.polygons),
                                                                     *body.dimensions))


# --- Phase 2: Skelett ----------------------------------------------------------------------------------

def stage_skeleton(ctx):
    new = import_glb(EMBER)
    rig = next(o for o in new if o.type == "ARMATURE")
    for o in new:
        if o is not rig:
            bpy.data.objects.remove(o, do_unlink=True)   # Glutdrachen-Netze
    if rig.animation_data:
        rig.animation_data.action = None
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    rig.name = "FrostRig"
    ctx["rig"] = rig
    # Ausrichtung jedes Glutdrachen-Knochens (Armaturraum) merken
    ctx["ember_rot"] = {b.name: b.matrix_local.to_3x3() for b in rig.data.bones}
    ctx["ember_head"] = {b.name: b.head_local.copy() for b in rig.data.bones}
    # Hilfsskelett: Kopie, Knochen auf die Gelenke des Frostdrachen; Ausrichtung = kleinste Drehung aus der des
    # Glutdrachen (so verdreht sich beim späteren Umstellen kein Glied um die eigene Achse)
    helper = rig.copy()
    helper.data = rig.data.copy()
    helper.animation_data_clear()
    helper.name = "FrostHelper"
    bpy.context.scene.collection.objects.link(helper)
    J = joints()
    select_only(helper)
    op(bpy.ops.object.mode_set, mode="EDIT")
    ebs = helper.data.edit_bones
    for eb in ebs:
        eb.use_connect = False
    rest = {}
    for name, (h, t) in J.items():
        eb = ebs[name]
        r_e = ctx["ember_rot"][name]
        q = (r_e @ V((0, 1, 0))).rotation_difference((t - h).normalized()).to_matrix()
        eb.matrix = Matrix.Translation(h) @ (q @ r_e).to_4x4()
        eb.length = (t - h).length
        rest[name] = Matrix.Translation(h) @ (q @ r_e).to_4x4()
    op(bpy.ops.object.mode_set, mode="OBJECT")
    ctx["helper"] = helper
    ctx["helper_rest"] = rest
    log("Hilfsskelett: %d Knochen gesetzt" % len(J))


# --- Phase 3: Gewichte und neue Ruhepose ---------------------------------------------------------------

def nearest_bone_fix(body, arm):
    segs = [(b.name, b.head_local, b.tail_local) for b in arm.data.bones if b.use_deform and b.name != "root"]
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


def stage_weights(ctx):
    body, helper, rig = ctx["body"], ctx["helper"], ctx["rig"]
    helper.data.bones["root"].use_deform = False   # Wurzel am Boden zieht nicht am Netz
    select_only(body, helper, active=helper)
    op(bpy.ops.object.parent_set, type="ARMATURE_AUTO")
    missing = sum(1 for v in body.data.vertices if not any(g.weight > 0.0 for g in v.groups))
    log("Wärmegewichte: %d Gruppen, ohne Gewicht %d, nachgetragen %d" % (len(body.vertex_groups), missing,
                                                                       nearest_bone_fix(body, helper)))
    select_only(body)
    op(bpy.ops.object.vertex_group_limit_total, group_select_mode="ALL", limit=4)
    op(bpy.ops.object.vertex_group_normalize_all, group_select_mode="ALL", lock_active=False)
    # Jeden Knochen (Eltern zuerst) in die Ausrichtung des Glutdrachen drehen; Kinder bleiben starr am Elternteil
    rest = ctx["helper_rest"]
    motion, new_head = {}, {}
    order = []

    def walk(b):
        order.append(b.name)
        for c in b.children:
            walk(c)

    for b in helper.data.bones:
        if b.parent is None:
            walk(b)
    for name in order:
        b = helper.data.bones[name]
        if name not in rest:
            motion[name] = Matrix.Identity(4)
            new_head[name] = b.head_local.copy()
            continue
        head = rest[name].translation
        if b.parent is not None and b.parent.name in motion:
            head = motion[b.parent.name] @ head
        m = Matrix.Translation(head) @ ctx["ember_rot"][name].to_4x4()
        helper.pose.bones[name].matrix = m
        bpy.context.view_layer.update()
        motion[name] = m @ rest[name].inverted()
        new_head[name] = head
    dg = bpy.context.evaluated_depsgraph_get()
    ev = body.evaluated_get(dg).to_mesh()
    coords = [v.co.copy() for v in ev.vertices]
    body.evaluated_get(dg).to_mesh_clear()
    for v, c in zip(body.data.vertices, coords):
        v.co = c
    body.data.update()
    for m in list(body.modifiers):
        body.modifiers.remove(m)
    body.parent = None
    body.matrix_world = Matrix.Identity(4)
    lengths = {n: helper.data.bones[n].length for n in rest}
    bpy.data.objects.remove(helper, do_unlink=True)
    # Spielskelett: Glutdrachen-Ausrichtung, Frostdrachen-Längen und -Lage
    select_only(rig)
    op(bpy.ops.object.mode_set, mode="EDIT")
    ebs = rig.data.edit_bones
    for eb in ebs:
        eb.use_connect = False
    for name in rest:
        eb = ebs[name]
        eb.matrix = Matrix.Translation(new_head[name]) @ ctx["ember_rot"][name].to_4x4()
        eb.length = lengths[name]
    op(bpy.ops.object.mode_set, mode="OBJECT")
    mod = body.modifiers.new("Armature", "ARMATURE")
    mod.object = rig
    body.parent = rig
    scale_locations(ctx)
    log("Netz in neuer Ruhepose am Spielskelett: %.2f x %.2f x %.2f m" % tuple(body.dimensions))


def scale_locations(ctx):
    """Positionsspuren (relativ zur Ruhepose) mit dem Abstand zum Elternknochen skalieren (wie CharacterVisual)."""
    rig = ctx["rig"]
    factor = {}
    for b in rig.data.bones:
        old = ctx["ember_head"][b.name] - (ctx["ember_head"][b.parent.name] if b.parent else V())
        new = b.head_local - (b.parent.head_local if b.parent else V())
        factor[b.name] = new.length / old.length if old.length > 0.05 else 1.0
    count = 0
    for act in bpy.data.actions:
        bags = []
        for layer in getattr(act, "layers", []):
            for strip in layer.strips:
                bags += list(getattr(strip, "channelbags", []))
        curves = [fc for bag in bags for fc in bag.fcurves] if bags else list(getattr(act, "fcurves", []))
        for fc in curves:
            if not fc.data_path.endswith(".location") or '"' not in fc.data_path:
                continue
            k = factor.get(fc.data_path.split('"')[1], 1.0)
            for kp in fc.keyframe_points:
                kp.co.y *= k
                kp.handle_left.y *= k
                kp.handle_right.y *= k
            count += 1
    log("Positionsspuren skaliert: %d (Hüfte x%.2f)" % (count, factor.get("hips", 1.0)))


# --- Phase 4: Export -----------------------------------------------------------------------------------

def stage_export(ctx):
    rig = ctx["rig"]
    rig.animation_data_create()
    rig.animation_data.action = None
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    out = ctx["out"]
    os.makedirs(os.path.dirname(out), exist_ok=True)
    select_only(ctx["body"], rig, active=rig)
    op(bpy.ops.export_scene.gltf, filepath=out, export_format="GLB", use_selection=True, export_animations=True,
       export_animation_mode="ACTIONS", export_skins=True, export_def_bones=False, export_yup=True,
       export_image_format="JPEG", export_jpeg_quality=90)
    log("exportiert -> %s (%.1f MB)" % (out, os.path.getsize(out) / 1e6))


# --- Vorschau ------------------------------------------------------------------------------------------

def show_helper(ctx, folder):
    """Hilfsskelett als leuchtende Stäbe über dem halb durchsichtigen Drachen (Front, Seite, oben)."""
    helper = ctx["helper"]
    sc = bpy.context.scene
    mat = bpy.data.materials.new("BoneGlow")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.remove(nt.nodes["Principled BSDF"])
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs[0].default_value = (1.0, 0.3, 0.1, 1.0)
    em.inputs[1].default_value = 5.0
    nt.links.new(em.outputs[0], nt.nodes["Material Output"].inputs[0])
    bones = []
    for b in helper.data.bones:
        if b.name == "root":
            continue
        h, t = b.head_local, b.tail_local
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.035, radius2=0.012, depth=(t - h).length)
        bmesh.ops.translate(bm, verts=bm.verts, vec=V((0, 0, (t - h).length * 0.5)))
        me = bpy.data.meshes.new("b")
        bm.to_mesh(me)
        o = bpy.data.objects.new("bone_" + b.name, me)
        o.rotation_euler = (t - h).to_track_quat("Z", "Y").to_euler()
        o.location = h
        o.data.materials.append(mat)
        sc.collection.objects.link(o)
        bones.append(o)
    glass = bpy.data.materials.new("Glass")
    glass.use_nodes = True
    glass.node_tree.nodes["Principled BSDF"].inputs["Alpha"].default_value = 0.25
    glass.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.4, 0.55, 0.8, 1.0)
    body = ctx["body"]
    original = list(body.data.materials)
    body.data.materials.clear()
    body.data.materials.append(glass)
    render_views(folder, "frost_skeleton", ortho=3.4)
    body.data.materials.clear()
    for m in original:
        body.data.materials.append(m)
    for o in bones:
        bpy.data.objects.remove(o, do_unlink=True)


def setup_render(sc):
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = 1000, 800
    if sc.world is None:
        w = bpy.data.worlds.new("FrostWorld")
        w.use_nodes = True
        w.node_tree.nodes["Background"].inputs[0].default_value = (0.45, 0.5, 0.56, 1)
        sc.world = w
    if not any(o.type == "LIGHT" for o in sc.objects):
        lt = bpy.data.lights.new("FrostSun", "SUN")
        lt.energy = 3.5
        lo = bpy.data.objects.new("FrostSun", lt)
        sc.collection.objects.link(lo)
        lo.rotation_euler = (0.8, 0.2, 0.6)
    if sc.camera is None:
        cam = bpy.data.objects.new("FrostCam", bpy.data.cameras.new("FrostCam"))
        sc.collection.objects.link(cam)
        sc.camera = cam
    return sc.camera


def render_views(folder, tag, ortho=3.4, views=None):
    sc = bpy.context.scene
    cam = setup_render(sc)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = ortho
    views = views or {"front": (0, -6, 1.4), "side": (6, 0, 1.4), "top": (0, -0.01, 7)}
    for name, pos in views.items():
        target = V((0, 0, 1.4)) if name != "top" else V((0, 0, 0))
        cam.location = pos
        cam.rotation_euler = (target - V(pos)).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = os.path.join(folder, "%s_%s.png" % (tag, name))
        op(bpy.ops.render.render, write_still=True)


POSES = (("Idle", 20), ("Walk", 8), ("Attack_Bite", 12), ("Fire_Breath", 24), ("Roar", 24), ("Fly", 6), ("Death", 47))


def render_poses(ctx, folder):
    rig = ctx["rig"]
    sc = bpy.context.scene
    cam = setup_render(sc)
    cam.data.type = "PERSP"
    cam.data.lens = 40
    rig.animation_data_create()
    for name, frame in POSES:
        act = bpy.data.actions.get(name)
        if act is None:
            continue
        rig.animation_data.action = act
        sc.frame_set(frame)
        bpy.context.view_layer.update()
        cam.location = V((-6.5, -7.5, 4.2))
        cam.rotation_euler = (V((0, 0, 1.3)) - cam.location).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = os.path.join(folder, "frost_pose_%s.png" % name)
        op(bpy.ops.render.render, write_still=True)
    rig.animation_data.action = None


# --- Ablauf --------------------------------------------------------------------------------------------

def run(stage="export", preview=None, src=SRC_DEFAULT, out=OUT_DEFAULT):
    ctx = {"src": src, "out": out}
    fresh_scene()
    # Im offenen Blender: alles im Kontext des Fensters (das jetzt die neue Szene zeigt), sonst landen Importe in der
    # Szene, die der Aufrufer gerade hatte
    with bpy.context.temp_override(**ui_override()):
        bpy.context.scene.render.fps = 24
        for name in STAGES[: STAGES.index(stage) + 1]:
            log("--- Phase %s ---" % name)
            globals()["stage_" + name](ctx)
        if preview:
            if stage == "skeleton":
                show_helper(ctx, preview)
            elif stage in ("weights", "export"):
                render_poses(ctx, preview)
            else:
                render_views(preview, "frost_mesh")
    log("fertig.")
    return ctx


if __name__ == "__main__" and bpy.app.background:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    run(stage=argv[argv.index("--stage") + 1] if "--stage" in argv else "export",
        preview=argv[argv.index("--preview") + 1] if "--preview" in argv else None)
