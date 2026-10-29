"""Helden mit realistischen Proportionen (Assassine, Krieger, Magier) auf dem gestreckten KayKit-Skelett.

Das KayKit-Skelett wird nur in den Knochenabständen gestreckt (alle Drehachsen bleiben gleich). So passen
weiterhin alle Animationen: die im Modell gespeicherten passt Blender beim Export an die neue Ruhepose an, die
Zusatz-Bibliotheken rechnet CharacterVisual zur Laufzeit um (Positionsspuren relativ zur Ruhepose).

Phasen (jede mit --preview als Bild prüfbar):
  1 skeleton  KayKit-Figur laden, alte Meshes entfernen, Skelett strecken, Lage der Original-Waffen merken
  2 body      Körper (Metaballs -> Voxel-Remesh), automatisch gewichtet
  3 outfit    Ausrüstung je Held (Schalen aus Hautbereichen, Röhren, Ringe, Waffen)
  4 texture   Leder, Stoff, Metall, Gold, Säume, Leuchten (gebacken)
  5 export    GLB nach assets/models/heroes_custom/<Shadow|Guardian|Arcanist>.glb

Blender-Raum: vorn = -Y, oben = +Z, linke Seite der Figur = +X.

Aufruf (Blender 5.2, ohne Oberfläche):
  blender.exe --background --python tools/blender_build_realistic_heroes.py -- --hero shadow|guardian|arcanist
      [--stage body] [--preview <ordner>] [--out <glb>]
"""
import math
import os
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector
from mathutils.kdtree import KDTree

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import blender_build_dragon as bd   # Baukasten: Metaballs, Voxel-Vereinigung, Röhren, Backen, Vorschau

PROJECT = bd.PROJECT
V = Vector
UP, FWD, LEFT = bd.UP, bd.FWD, bd.LEFT
STAGES = ["skeleton", "body", "outfit", "texture", "export"]
HERO = {}   ## Bauplan des gerade gebauten Helden (aus HEROES, unten)
log = lambda msg: print("[%s] %s" % (HERO.get("id", "heroes"), msg), flush=True)

# Streckfaktor des Abstands Elternknochen-Ansatz -> Knochen-Ansatz (Richtung bleibt). Nicht genannte: 1.0.
# Einzelne Helden können Werte überschreiben (HEROES[..]["offset"], z. B. breitere Schultern beim Krieger).
OFFSET_SCALE = {
    "hips": 2.18, "spine": 1.35, "chest": 0.80, "head": 1.12,
    "upperarm": 1.18, "lowerarm": 1.50, "wrist": 1.20, "hand": 0.90, "handslot": 0.90,
    "upperleg": 0.75, "lowerleg": 2.00, "foot": 2.85, "toes": 0.60,
}


def base_name(name):
    return name.split(".")[0]


def scale_of(name):
    """Streckfaktor eines Knochens für den aktuellen Helden (None = nicht gestreckt)."""
    key = base_name(name)
    return HERO.get("offset", {}).get(key, OFFSET_SCALE.get(key))


# --- Phase 1: Skelett ----------------------------------------------------------------------------------

def stretch_skeleton(arm):
    """Knochenansätze rekursiv neu setzen: Abstand zum Eltern-Ansatz x Faktor; Länge = Faktor des ersten Kindes."""
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    ebs = arm.data.edit_bones
    old = {b.name: (b.head.copy(), b.tail.copy(), b.roll) for b in ebs}
    new_head = {}

    def place_bone(name):
        b = ebs[name]
        h, t, _ = old[name]
        if b.parent is None or scale_of(name) is None:
            if b.parent is None:
                new_head[name] = h.copy()
            else:   # IK-Hilfsknochen u. ä.: Lage relativ zum Elternknochen beibehalten
                ph = old[b.parent.name][0]
                new_head[name] = new_head[b.parent.name] + (h - ph)
        else:
            ph = old[b.parent.name][0]
            new_head[name] = new_head[b.parent.name] + (h - ph) * scale_of(name)
        for c in b.children:
            place_bone(c.name)

    for b in ebs:
        if b.parent is None:
            place_bone(b.name)
    for b in ebs:
        h, t, roll = old[b.name]
        kids = [c for c in b.children if scale_of(c.name) is not None]
        k = scale_of(kids[0].name) if kids else 1.0
        use_connect = b.use_connect
        b.use_connect = False
        b.head = new_head[b.name]
        b.tail = new_head[b.name] + (t - h) * k
        b.roll = roll
        b.use_connect = use_connect and (b.parent is not None and (b.parent.tail - b.head).length < 1e-4)
    bpy.ops.object.mode_set(mode="OBJECT")


def scale_action_locations(arm):
    """Positionsschlüssel (relativ zur Ruhepose) im Verhältnis der Knochenstreckung skalieren: senkt sich die Hüfte
    bei KayKit um 0,3, sind es beim doppelt so langen Bein 0,65 – sonst schwebt der Körper z. B. im Tod über dem Boden."""
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
            bone = fc.data_path.split('"')[1]
            factor = scale_of(bone)
            if factor is None or bone not in arm.data.bones:
                continue
            for kp in fc.keyframe_points:
                kp.co.y *= factor
                kp.handle_left.y *= factor
                kp.handle_right.y *= factor
            count += 1
    log("Positionsspuren skaliert: %d" % count)


def joint(arm, name):
    return arm.matrix_world @ arm.data.bones[name].head_local


def knife_axes(arm):
    """Achsen der Original-Messer im Handslot-Raum (Klinge = am weitesten vom Griff entfernter Punkt, Breite quer
    dazu): die Angriffsanimationen sind auf diese Griffhaltung ausgelegt."""
    out = {}
    for name in ("Knife", "Knife_Offhand"):
        obj = bpy.data.objects.get(name)
        if obj is None:
            continue
        slot = obj.parent_bone or ("handslot.r" if name == "Knife" else "handslot.l")
        bone = arm.data.bones[slot]
        rest = arm.matrix_world @ bone.matrix_local
        pts = [obj.matrix_world @ v.co for v in obj.data.vertices]
        grip = rest.translation
        tip = max(pts, key=lambda p: (p - grip).length)
        axis = (tip - grip).normalized()
        width = max(pts, key=lambda p: ((p - grip) - axis * (p - grip).dot(axis)).length)
        side = ((width - grip) - axis * (width - grip).dot(axis)).normalized()
        inv = rest.to_3x3().inverted()
        out[slot] = (inv @ axis, inv @ side)
    return out


def weapon_frames(arm, names):
    """Lage der Original-Waffen relativ zu ihrem Handslot (Matrix + Maße im eigenen Mesh-Raum). Eigene Waffen werden
    in genau diesem Rahmen gebaut, damit sie in den Angriffsanimationen richtig in der Hand liegen."""
    out = {}
    for name in names:
        obj = bpy.data.objects.get(name)
        if obj is None or not obj.parent_bone:
            log("WARNUNG: Waffe %s fehlt" % name)
            continue
        rest = arm.matrix_world @ arm.data.bones[obj.parent_bone].matrix_local
        co = [v.co for v in obj.data.vertices]
        out[name] = {"slot": obj.parent_bone, "m_local": rest.inverted() @ obj.matrix_world,
                     "min": V([min(c[i] for c in co) for i in range(3)]), "max": V([max(c[i] for c in co) for i in range(3)])}
    return out


def weapon_axes(ctx, name, scale=1.0):
    """Griffpunkt und Achsen einer Original-Waffe nach dem Strecken: lang = vom Griff zur Spitze, mitte = Breite,
    dünn = Dicke. Längen mit scale verkleinert (KayKit-Waffen sind für Chibi-Figuren riesig)."""
    w = ctx["weapons"][name]
    origin, rot = bone_frame(ctx["arm"], w["slot"])
    world = Matrix.Translation(origin) @ rot.to_4x4() @ w["m_local"]
    grip = w["m_local"].inverted() @ V((0, 0, 0))          # Handslot-Ursprung im Mesh-Raum der Waffe
    basis = world.to_3x3()
    unit = [(basis @ V([1.0 if k == i else 0.0 for k in range(3)])).length for i in range(3)]   # Objekt-Skalierung je Achse
    dims = [(w["max"][i] - w["min"][i]) * unit[i] for i in range(3)]
    order = sorted(range(3), key=lambda i: dims[i])          # dünn, mitte, lang (in Weltmaß)
    thin, mid, long_ = order
    axis = lambda i: (basis @ V([1.0 if k == i else 0.0 for k in range(3)])).normalized()
    to_max = (w["max"][long_] - grip[long_]) * unit[long_]
    to_min = (grip[long_] - w["min"][long_]) * unit[long_]
    sign = 1.0 if to_max >= to_min else -1.0
    center = (w["min"] + w["max"]) * 0.5
    return {"slot": w["slot"], "origin": origin, "long": axis(long_) * sign, "mid": axis(mid), "thin": axis(thin),
            "far": max(to_max, to_min) * scale, "near": min(to_max, to_min) * scale,
            "width": dims[mid] * scale, "depth": dims[thin] * scale, "center": world @ center}


def idle_rotation(arm, bone):
    """Drehung, die die Stehanimation (Bild 0) auf einen Knochen gegenüber der Ruhepose anwendet."""
    arm.animation_data_create()
    arm.animation_data.action = bpy.data.actions.get("Idle")
    bpy.context.scene.frame_set(0)
    bpy.context.view_layer.update()
    pose = arm.matrix_world @ arm.pose.bones[bone].matrix
    rest = arm.matrix_world @ arm.data.bones[bone].matrix_local
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    return (pose @ rest.inverted()).to_3x3()


def stage_skeleton(ctx):
    bpy.ops.import_scene.gltf(filepath=os.path.join(PROJECT, HERO["source"]))
    arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
    # Der Import hängt eine Animation an: Waffen erst in der Ruhepose vermessen
    if arm.animation_data:
        arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    ctx["knives"] = knife_axes(arm)
    ctx["weapons"] = weapon_frames(arm, HERO.get("weapons", []))
    for o in [o for o in bpy.context.scene.objects if o.type != "ARMATURE"]:
        bpy.data.objects.remove(o, do_unlink=True)
    stretch_skeleton(arm)
    scale_action_locations(arm)
    ctx["arm"] = arm
    for n in ("hips", "upperleg.l", "lowerleg.l", "foot.l", "toes.l", "chest", "upperarm.l", "lowerarm.l", "hand.l", "head"):
        log("%-11s %s" % (n, tuple(round(c, 3) for c in joint(arm, n))))


# --- Phase 2: Körper ---------------------------------------------------------------------------------

NON_DEFORM = ("root", "control", "IK", "kneeIK", "heelIK", "elbowIK", "handIK", "handslot")


class Meta(bd.Meta):
    """Metaballs ohne die Drachen-Absenkung (alle Punkte sind schon Weltkoordinaten)."""

    def ball(self, p, radius, chain=False, placed=True):
        return super().ball(p, radius, chain=chain, placed=True)

    def chain(self, points, radii, spacing=0.5, placed=True):
        return super().chain(points, radii, spacing=spacing, placed=True)


def build_body(arm, torso=1.0, limbs=1.0):
    """Athletischer Grundkörper. torso/limbs skalieren Rumpfbreite bzw. Dicke von Armen und Beinen (Krieger kräftiger)."""
    J = lambda n: joint(arm, n)
    m = Meta("BodyMeta", resolution=0.012)
    t, L = torso, limbs
    # Becken, Bauch, Brustkorb (Rücken = +Y)
    m.ball((0, 0.015, 0.97), 0.11 * t)
    for s in (1, -1):
        m.ball((0.065 * s * t, 0.0, 0.95), 0.092 * t)
        m.ball((0.06 * s * t, 0.045, 0.91), 0.07 * t)           # Gesäß
        m.chain([(0.065 * s * t, 0.005, 1.0), (0.068 * s * t, 0.008, 1.14), (0.075 * s * t, 0.0, 1.27)],
                [0.085 * t, 0.08 * t, 0.09 * t])                # Flanke
    m.chain([(0, 0.01, 1.0), (0, 0.022, 1.13), (0, 0.01, 1.26)], [0.1 * t, 0.088 * t, 0.104 * t])
    m.ball((0, 0.008, 1.32), 0.11 * t)
    for s in (1, -1):
        m.ball((0.07 * s * t, 0.005, 1.30), 0.1 * t)
        m.ball((0.085 * s * t, -0.02, 1.43), 0.095 * t)         # Brustmuskel
        m.ball((0.095 * s * t, 0.03, 1.50), 0.095 * t)          # Trapez / Schulterblatt
        m.ball((0.19 * s * t, 0.0, 1.565), 0.08 * t)
    m.ball((0, 0.0, 1.45), 0.125 * t)
    # Hals und Kopf
    m.chain([(0, 0.005, 1.58), (0, 0.0, 1.70), (0, -0.005, 1.76)], [0.065, 0.054, 0.05])
    m.ball((0, 0.012, 1.88), 0.105)
    m.ball((0, -0.035, 1.80), 0.07)
    m.ball((0, -0.068, 1.765), 0.038)
    m.ball((0, -0.095, 1.83), 0.02)                     # Nase
    for side, s in (("l", 1), ("r", -1)):
        sh, el, wr, hd = J("upperarm." + side), J("lowerarm." + side), J("wrist." + side), J("hand." + side)
        m.ball(sh, 0.078 * L)                           # Deltamuskel
        m.chain([sh, sh.lerp(el, 0.45), el], [0.058 * L, 0.052 * L, 0.043 * L])
        m.chain([el, el.lerp(wr, 0.3), wr], [0.043 * L, 0.042 * L, 0.032 * L])
        palm = hd + V((0.045 * s, 0.0, -0.005))
        m.chain([wr, hd, palm], [0.032, 0.036, 0.042])
        m.chain([palm, palm + V((0.06 * s, -0.005, -0.02)), palm + V((0.085 * s, -0.01, -0.05))], [0.032, 0.028, 0.022])
        m.ball(palm + V((0.01 * s, -0.04, -0.01)), 0.022)   # Daumen
        ul, ll, ft, to = J("upperleg." + side), J("lowerleg." + side), J("foot." + side), J("toes." + side)
        m.chain([ul, ul.lerp(ll, 0.35), ll], [0.084 * L, 0.078 * L, 0.056 * L])
        m.ball(ul.lerp(ll, 0.28) + V((0.005 * s, -0.02, 0.0)), 0.074 * L)
        m.chain([ll, ll.lerp(ft, 0.3) + V((0, 0.02, 0)), ft], [0.058 * L, 0.06 * L, 0.042 * L])
        m.chain([ft + V((0, 0.03, -0.045)), ft, V((to.x, to.y, 0.045)), V((to.x, to.y - 0.13, 0.04))], [0.042, 0.045, 0.042, 0.033])
    return m.obj


def stage_body(ctx):
    arm = ctx["arm"]
    body = bd.unify(HERO["prefix"] + "Body", [build_body(arm, **HERO.get("body", {}))], voxel=0.007, smooth_iter=3,
                    target_faces=16000)
    for b in arm.data.bones:
        b.use_deform = not b.name.startswith(NON_DEFORM)
    for o in bpy.context.scene.objects:
        o.select_set(False)
    body.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    for b in arm.data.bones:   # Handslots tragen die Dolche, sollen aber nicht am Körper ziehen
        if b.name.startswith("handslot"):
            b.use_deform = True
    missing = sum(1 for v in body.data.vertices if not v.groups)
    ctx["body"] = body
    log("Körper: %d Flächen, Höhe %.2f, ohne Gewicht: %d" % (len(body.data.polygons), body.dimensions.z, missing))


# --- Phase 3: Ausrüstung -----------------------------------------------------------------------------
# Jedes Teil bekommt je Punkt "reg" (Werkstoff) und "trim" (1 am Saum) sowie "treg" (Werkstoff des Saums).

REG = {"skin": 0, "cloth": 1, "leather": 2, "brown": 3, "red": 4, "steel": 5, "iron": 6, "eye": 7, "hood": 8,
       "gold": 9, "plate": 10, "blue": 11, "beard": 12, "eye_blue": 13, "crystal": 14, "wood": 15}
REG_N = 16      ## Anzahl der Werkstoffnummern (Stufen in den Farbverläufen)
REG_COLOR = {   # sRGB
    0: "#c4937a", 1: "#1c1a1e", 2: "#2b2324", 3: "#553524", 4: "#9a1616", 5: "#cdd3dc", 6: "#3a383d", 7: "#ff4a1c", 8: "#211e24",
    9: "#d2a23c", 10: "#2c4c8e", 11: "#22397a", 12: "#e4e1da", 13: "#7fd0ff", 14: "#c8f0ff", 15: "#5b3b24",
}
REG_ROUGH = {0: 0.6, 1: 0.88, 2: 0.55, 3: 0.62, 4: 0.82, 5: 0.3, 6: 0.42, 7: 0.4, 8: 0.9,
             9: 0.3, 10: 0.38, 11: 0.85, 12: 0.92, 13: 0.4, 14: 0.08, 15: 0.7}
REG_METAL = {5: 0.55, 6: 0.85, 9: 1.0, 10: 0.7}   ## Stahl nur halb metallisch: voll metallisch spiegelt er in Godot den dunklen Hintergrund und wirkt schwarz
REG_EMIT = {7: "#ff1006", 13: "#2f9bff", 14: "#7fd6ff"}          ## leuchtende Werkstoffe (Augen, Kristall)
CLOTH_REGS = (1, 4, 8, 11, 12)
LEATHER_REGS = (2, 3, 15)


def set_attrs(obj, reg, treg=None, trim=None):
    me = obj.data
    for name in ("reg", "treg", "trim"):
        if name not in me.attributes:
            me.attributes.new(name, "FLOAT", "POINT")
    r, t, tr = me.attributes["reg"].data, me.attributes["treg"].data, me.attributes["trim"].data
    for i in range(len(me.vertices)):
        r[i].value = reg
        t[i].value = reg if treg is None else treg
        tr[i].value = 0.0 if trim is None else trim[i]


def boundary_distance(bm):
    """Abstand jedes Punkts zum offenen Rand entlang der Kanten (Dijkstra light)."""
    import heapq
    dist = {v: (0.0 if any(e.is_boundary for e in v.link_edges) else 1e9) for v in bm.verts}
    heap = [(0.0, v.index, v) for v, d in dist.items() if d == 0.0]
    heapq.heapify(heap)
    while heap:
        d, _, v = heapq.heappop(heap)
        if d > dist[v]:
            continue
        for e in v.link_edges:
            o = e.other_vert(v)
            nd = d + e.calc_length()
            if nd < dist[o]:
                dist[o] = nd
                heapq.heappush(heap, (nd, o.index, o))
    return dist


def remove_islands(bm, min_faces):
    """Splitter (zusammenhängende Flächengruppen unter min_faces) entfernen."""
    seen = set()
    drop = []
    for f in bm.faces:
        if f in seen:
            continue
        island, stack = [], [f]
        seen.add(f)
        while stack:
            g = stack.pop()
            island.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h not in seen:
                        seen.add(h)
                        stack.append(h)
        if len(island) < min_faces:
            drop += island
    if drop:
        bmesh.ops.delete(bm, geom=drop, context="FACES")


def relax_boundary(bm, iterations=8, factor=0.5):
    """Offene Ränder glätten: jeder Randpunkt rückt zur Mitte seiner beiden Randnachbarn (gerade Säume statt Zacken)."""
    for _ in range(iterations):
        moves = {}
        for v in bm.verts:
            nb = [e.other_vert(v) for e in v.link_edges if e.is_boundary]
            if len(nb) == 2:
                moves[v] = v.co.lerp((nb[0].co + nb[1].co) * 0.5, factor)
        for v, co in moves.items():
            v.co = co


def new_skinned(name, me, arm, groups):
    obj = bd.link(bpy.data.objects.new(name, me))
    for g in groups:
        obj.vertex_groups.new(name=g)
    obj.modifiers.new("Armature", "ARMATURE").object = arm
    obj.parent = arm
    for p in me.polygons:
        p.use_smooth = True
    return obj


def solidify(obj, thickness, offset=-1.0):
    mod = obj.modifiers.new("Solidify", "SOLIDIFY")
    mod.thickness = thickness
    mod.offset = offset
    mod.use_rim = True
    mod.use_even_offset = False      # gleichmäßige Dicke erzeugt an scharfen Ecken lange Spitzen
    obj.modifiers.move(len(obj.modifiers) - 1, 0)   # vor die Armature
    arm_mod = [m for m in obj.modifiers if m.type == "ARMATURE"]
    for m in arm_mod:
        m.show_viewport = False
    me = bd.mesh_from_evaluated(obj, obj.name)
    for m in arm_mod:
        m.show_viewport = True
    obj.modifiers.remove(mod)
    old = obj.data
    obj.data = me
    bpy.data.meshes.remove(old)


def shell(ctx, name, select, offset, thickness=0.0, reg="leather", treg="red", trim_width=0.018, offset_fn=None):
    """Teil aus einem Hautbereich des Körpers: Flächen auswählen, entlang der Normalen abheben, Dicke geben.
    Die Gewichte kommen 1:1 vom Körper; der Saum (trim) ist ein Band am offenen Rand.
    offset_fn(co) ersetzt den festen Abstand (z. B. Glockenärmel, die zum Handgelenk weiter werden)."""
    body = ctx["body"]
    bm = bmesh.new()
    bm.from_mesh(body.data)
    keep = {f for f in bm.faces if all(select(v.co, v.normal) for v in f.verts)}
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f not in keep], context="FACES")
    remove_islands(bm, min_faces=30)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    relax_boundary(bm)
    for v in bm.verts:
        v.co += v.normal * (offset_fn(v.co) if offset_fn else offset)
    dist = boundary_distance(bm)
    trim = [bd.smoothstep(trim_width, trim_width * 0.6, dist[v]) for v in bm.verts]
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = new_skinned(name, me, ctx["arm"], [g.name for g in body.vertex_groups])
    set_attrs(obj, REG[reg], REG[treg], trim)
    if thickness > 0.0:
        solidify(obj, thickness)
    ctx.setdefault("pieces", []).append(obj)
    return obj


def copy_weights(obj, body):
    """Gewichte je Punkt vom nächstgelegenen Körperpunkt übernehmen (für frei gebaute Teile wie die Kapuze)."""
    kd = KDTree(len(body.data.vertices))
    for v in body.data.vertices:
        kd.insert(v.co, v.index)
    kd.balance()
    names = {g.index: g.name for g in body.vertex_groups}
    for g in body.vertex_groups:
        if g.name not in obj.vertex_groups:
            obj.vertex_groups.new(name=g.name)
    for v in obj.data.vertices:
        hits = kd.find_n(v.co, 4)
        acc = {}
        for co, idx, dist in hits:
            w = 1.0 / max(dist, 1e-4) ** 2
            for g in body.data.vertices[idx].groups:
                acc[names[g.group]] = acc.get(names[g.group], 0.0) + g.weight * w
        total = sum(acc.values()) or 1.0
        for n, w in acc.items():
            if w / total > 0.01:
                obj.vertex_groups[n].add([v.index], w / total, "REPLACE")


def parts_object(ctx, parts, reg):
    obj = parts.finish()
    obj.modifiers.new("Armature", "ARMATURE").object = ctx["arm"]
    obj.parent = ctx["arm"]
    set_attrs(obj, REG[reg])
    ctx.setdefault("pieces", []).append(obj)
    return obj


def bone_frame(arm, name):
    m = arm.matrix_world @ arm.data.bones[name].matrix_local
    return m.translation, m.to_3x3()


def build_hood(ctx):
    m = Meta("HoodMeta", resolution=0.012)
    m.ball((0, 0.025, 1.885), 0.125)
    m.ball((0, 0.065, 1.84), 0.115)
    m.chain([(0, 0.09, 1.94), (0, 0.15, 1.965), (0, 0.205, 1.925)], [0.07, 0.045, 0.018], spacing=0.4)   # Zipfel hinten
    for s in (1, -1):
        m.ball((0.08 * s, -0.005, 1.82), 0.094)
        m.chain([(0.06 * s, 0.03, 1.70), (0.14 * s, 0.03, 1.645), (0.21 * s, 0.01, 1.615)], [0.075, 0.07, 0.055])  # Überwurf
    m.chain([(0, 0.085, 1.72), (0, 0.10, 1.64)], [0.085, 0.075])                         # Rücken
    m.ball((0, -0.03, 1.70), 0.06)                                                         # Kragen vorn
    hood_from_meta(ctx, m.obj, (0.085, 0.12, 1.83), "hood", "red")


def hood_from_meta(ctx, meta_obj, opening, reg, treg, name="Hood"):
    """Kapuze aus Metaballs: vereinen, Gesichtsöffnung (Ellipse: halbe Breite, halbe Höhe, Mitte z) ausschneiden,
    Rand glätten, Saum markieren, Gewichte vom Körper, Stoffdicke."""
    ox, oz, cz = opening
    hood = bd.unify(name, [meta_obj], voxel=0.008, smooth_iter=3, target_faces=6000)
    bm = bmesh.new()
    bm.from_mesh(hood.data)
    cut = [v for v in bm.verts if v.co.y < -0.0 and (v.co.x / ox) ** 2 + ((v.co.z - cz) / oz) ** 2 < 1.0]
    bmesh.ops.delete(bm, geom=cut, context="VERTS")
    relax_boundary(bm)
    dist = boundary_distance(bm)
    trim = [bd.smoothstep(0.022, 0.012, dist[v]) for v in bm.verts]
    bm.to_mesh(hood.data)
    bm.free()
    hood.modifiers.new("Armature", "ARMATURE").object = ctx["arm"]
    hood.parent = ctx["arm"]
    copy_weights(hood, ctx["body"])
    set_attrs(hood, REG[reg], REG[treg], trim)
    solidify(hood, 0.012)
    ctx.setdefault("pieces", []).append(hood)
    return hood


SHADOW_TABARDS = ((-1, -0.115, -0.15, 0.17, 0.44), (1, 0.12, 0.16, 0.2, 0.40))


def build_tabards(ctx, panels=SHADOW_TABARDS, reg="red", treg="cloth", top_z=1.0, name="Tabards"):
    """Lendentücher/Wappenrock vorn und hinten: oben am Becken, unten zwischen den Oberschenkeln gemischt.
    panels: (Seite -1 vorn/+1 hinten, y oben, y unten, Breite, Länge)."""
    arm = ctx["arm"]
    groups = [g.name for g in ctx["body"].vertex_groups]
    bm = bmesh.new()
    deform = bm.verts.layers.deform.verify()
    gi = {g: i for i, g in enumerate(groups)}
    trims = []
    for sgn, top_y, bot_y, width, length in panels:
        rows = []
        nx, nz = 6, 10
        for j in range(nz + 1):
            t = j / nz
            row = []
            for i in range(nx + 1):
                a = i / nx - 0.5
                w = width * (1.0 - 0.15 * t)
                x = a * w
                y = bd.lerp(top_y, bot_y, t) + sgn * 0.02 * (1.0 - (2 * a) ** 2)
                z = top_z - length * t
                v = bm.verts.new((x, y, z))
                v[deform][gi["hips"]] = 1.0 - 0.6 * t
                v[deform][gi["upperleg.l"]] = 0.6 * t * (0.5 + a)
                v[deform][gi["upperleg.r"]] = 0.6 * t * (0.5 - a)
                trims.append(1.0 if (j == nz or i in (0, nx)) else (0.6 if (j == nz - 1 or i in (1, nx - 1)) else 0.0))
                row.append(v)
            rows.append(row)
        for j in range(nz):
            for i in range(nx):
                quad = [rows[j][i], rows[j][i + 1], rows[j + 1][i + 1], rows[j + 1][i]]
                bm.faces.new(quad if sgn < 0 else list(reversed(quad)))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = new_skinned(name, me, arm, groups)
    set_attrs(obj, REG[reg], REG[treg], trims)
    solidify(obj, 0.012, offset=0.0)
    ctx.setdefault("pieces", []).append(obj)


def build_scarf_tails(ctx):
    arm = ctx["arm"]
    groups = [g.name for g in ctx["body"].vertex_groups]
    bm = bmesh.new()
    deform = bm.verts.layers.deform.verify()
    gi = {g: i for i, g in enumerate(groups)}
    trims = []
    for s in (1, -1):
        rows = []
        for j in range(9):
            t = j / 8
            c = V((0.035 * s + 0.03 * s * t, 0.14 + 0.05 * t, 1.66 - 0.34 * t))
            w = 0.05 * (1.0 - 0.3 * t)
            row = []
            for i in range(3):
                v = bm.verts.new(c + V(((i - 1) * w, 0, 0)))
                v[deform][gi["chest"]] = 1.0 - 0.5 * t
                v[deform][gi["spine"]] = 0.5 * t
                trims.append(1.0 if i != 1 or j == 8 else 0.0)
                row.append(v)
            rows.append(row)
        for j in range(8):
            for i in range(2):
                bm.faces.new([rows[j][i], rows[j + 1][i], rows[j + 1][i + 1], rows[j][i + 1]])
    me = bpy.data.meshes.new("ScarfTails")
    bm.to_mesh(me)
    bm.free()
    obj = new_skinned("ScarfTails", me, arm, groups)
    set_attrs(obj, REG["red"], REG["red"], [0.0] * len(me.vertices))
    solidify(obj, 0.008, offset=0.0)
    ctx.setdefault("pieces", []).append(obj)


def build_daggers(ctx):
    """Zwei lange, gebogene Dolche: Griff mit Lederwicklung, Parierstange, Klinge mit Schwung zur Schneide."""
    arm = ctx["arm"]
    steel, iron, brown = bd.Parts("DaggerBlades"), bd.Parts("DaggerGuards"), bd.Parts("DaggerGrips")
    for slot in ("handslot.r", "handslot.l"):
        if slot not in ctx["knives"]:
            continue
        origin, rot = bone_frame(arm, slot)
        axis_l, side_l = ctx["knives"][slot]
        axis, side = (rot @ axis_l).normalized(), (rot @ side_l).normalized()
        flat = axis.cross(side).normalized()
        p = lambda a, b=0.0: origin + axis * a + side * b
        brown.tube([p(-0.065), p(0.065)], [0.017, 0.017], slot, palette="horn", verts=8, ridges=0.12)
        iron.tube([p(-0.085), p(-0.065)], [0.021, 0.018], slot, palette="horn", verts=8)          # Knauf
        iron.tube([p(0.07, -0.07), p(0.07, 0.0), p(0.075, 0.075)], [0.012, 0.016, 0.0], slot, palette="horn", verts=6,
                  flat=0.7, flat_axis=axis)                                                       # Parierstange
        n = 9
        pts, radii = [], []
        for k in range(n + 1):
            t = k / n
            pts.append(p(0.08 + 0.42 * t, 0.075 * t * t))                                         # Schwung zur Schneide
            radii.append(0.026 * (1.0 - 0.75 * t ** 1.6) if k < n else 0.0)
        steel.tube(pts, radii, slot, palette="horn", verts=8, flat=0.16, flat_axis=flat)
    parts_object(ctx, steel, "steel")
    parts_object(ctx, iron, "iron")
    parts_object(ctx, brown, "brown")


def build_metal_details(ctx):
    """Nieten auf Schulter und Brust, Stacheln auf den Armschienen, Gürtelschnalle."""
    arm = ctx["arm"]
    J = lambda n: joint(arm, n)
    iron = bd.Parts("Rivets")
    for side, s in (("l", 1), ("r", -1)):
        el, wr = J("lowerarm." + side), J("wrist." + side)
        for t in (0.35, 0.55, 0.75):
            b = el.lerp(wr, t) + V((0, 0.0, 0.047))
            iron.tube([b, b + V((0.0, 0.012, 0.045))], [0.012, 0.0], "lowerarm." + side, palette="horn", verts=6)
        sh = J("upperarm." + side)
        for k in range(3):
            a = math.radians(-40 + 40 * k)
            c = sh + V((0.03 * s, math.sin(a) * 0.07, 0.115 - abs(math.sin(a)) * 0.02))
            iron.tube([c, c + V((0.0, 0.0, 0.012))], [0.009, 0.0], "upperarm." + side, palette="horn", verts=6)
    iron.tube([V((0, -0.135, 1.0)), V((0, -0.15, 1.0))], [0.03, 0.028], "hips", palette="horn", verts=4)   # Schnalle
    parts_object(ctx, iron, "iron")


def surface_bvh(objects):
    """BVH über mehrere Meshes in Ruhepose (zum Aufsetzen von Teilen auf die Oberfläche)."""
    from mathutils.bvhtree import BVHTree
    verts, polys = [], []
    for o in objects:
        off = len(verts)
        verts += [v.co.copy() for v in o.data.vertices]
        polys += [tuple(i + off for i in p.vertices) for p in o.data.polygons]
    return BVHTree.FromPolygons(verts, polys)


def on_surface(bvh, p, direction, lift):
    """Punkt p entlang direction auf die Oberfläche legen (Strahl von außen), lift = Abstand darüber."""
    d = V(direction).normalized()
    hit, _, _, _ = bvh.ray_cast(V(p) - d * 1.0, d)
    return (hit - d * lift) if hit is not None else V(p)


def build_straps(ctx):
    """Kreuzgurt über Brust und Rücken (braunes Leder), auf die Rüstung gelegt."""
    bvh = surface_bvh([ctx["body"]] + [o for o in ctx["pieces"] if o.name.startswith(("ChestArmor", "Sash", "Belt"))])
    br = bd.Parts("Straps")
    for sgn, path in ((-1, [(0.17, 1.53), (0.07, 1.38), (-0.06, 1.22), (-0.13, 1.08)]),
                      (1, [(0.17, 1.53), (0.05, 1.35), (-0.08, 1.18), (-0.13, 1.08)])):
        pts = [on_surface(bvh, (x, 0.0, z), (0, -sgn, 0), 0.007) for x, z in path]
        br.tube(pts, [0.016] * 4, {"chest": 0.6, "spine": 0.4}, palette="horn", verts=6, flat=0.35, flat_axis=FWD)
    parts_object(ctx, br, "brown")


def limb_ring(ctx, parts, bone, child, t, half_width=0.012, thick=0.006, gap=0.014):
    """Lederriemen als Ring um ein Glied: Radius aus dem Körper gemessen (größter Abstand zur Gliedachse)."""
    arm = ctx["arm"]
    a, b = joint(arm, bone), joint(arm, child)
    c = a.lerp(b, t)
    ring_around(ctx, parts, c, (b - a).normalized(), bone, half_width, thick, gap, side=1.0 if c.x > 0 else -1.0)


def ring_around(ctx, parts, c, axis, bone, half_width=0.012, thick=0.006, gap=0.014, side=None, meshes=None):
    """Ring entlang der Kontur der Körperoberfläche um die Achse durch c (side: nur Punkte dieser Körperseite;
    meshes: andere Oberflächen als Maß, z. B. der Rock statt des Körpers)."""
    axis = V(axis).normalized()
    u = axis.orthogonal().normalized()
    w = axis.cross(u)
    n = 20
    radius = [0.0] * n                       # Kontur: größter Abstand je Richtungssektor (Wade hinten, Schienbein vorn)
    for v in (pv for o in (meshes or [ctx["body"]]) for pv in o.data.vertices):
        d = v.co - c
        if abs(d.dot(axis)) < 0.012 and (side is None or v.co.x * side > 0):
            radial = d - axis * d.dot(axis)
            k = int(round(math.atan2(radial.dot(w), radial.dot(u)) / (2 * math.pi) * n)) % n
            radius[k] = max(radius[k], radial.length)
    filled = [r for r in radius if r > 0.0]
    mean = sum(filled) / max(1, len(filled))
    radius = [r if r > 0.0 else mean for r in radius]
    radius = [(radius[k - 1] + 2 * radius[k] + radius[(k + 1) % n]) / 4 + gap for k in range(n)]
    pts = [c + (u * math.cos(2 * math.pi * k / n) + w * math.sin(2 * math.pi * k / n)) * radius[k % n] for k in range(n + 1)]
    parts.tube(pts, [thick] * 21, bone, palette="horn", verts=6, flat=half_width / thick, flat_axis=axis, cap=False)


def build_eyes(ctx, reg="eye", z=1.848, dx=0.034):
    """Glühende Augen knapp vor der Gesichtsoberfläche (zwischen Kapuze und Maske)."""
    bvh = surface_bvh([ctx["body"]])
    bm = bmesh.new()
    for s in (1, -1):
        c = on_surface(bvh, (dx * s, 0.0, z), (0, 1, 0), 0.001)
        res = bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=6, radius=0.013)
        bmesh.ops.scale(bm, vec=(1.35, 0.5, 0.7), verts=res["verts"])
        bmesh.ops.translate(bm, vec=c, verts=res["verts"])
    me = bpy.data.meshes.new("Eyes")
    bm.to_mesh(me)
    bm.free()
    obj = new_skinned("Eyes", me, ctx["arm"], ["head"])
    obj.vertex_groups["head"].add(list(range(len(me.vertices))), 1.0, "REPLACE")
    set_attrs(obj, REG[reg])
    ctx.setdefault("pieces", []).append(obj)


def stage_outfit(ctx):
    HERO["outfit"](ctx)
    log("Ausrüstung: %d Teile" % len(ctx["pieces"]))


def outfit_shadow(ctx):
    """Assassine: Kapuze, rote Maske, Lederrüstung, Schulterplatten, Armschienen, Lendentücher, gebogene Dolche."""
    arm = ctx["arm"]
    J = lambda n: joint(arm, n)
    sh_l, sh_r = J("upperarm.l"), J("upperarm.r")
    torso = lambda c, n: 1.08 < c.z < 1.585 and abs(c.x) < 0.205
    shell(ctx, "ChestArmor", torso, 0.012, 0.012, "leather", "red")
    shell(ctx, "Sash", lambda c, n: 1.02 < c.z < 1.095 and abs(c.x) < 0.2, 0.024, 0.016, "red", "red")
    shell(ctx, "Belt", lambda c, n: 0.965 < c.z < 1.02 and abs(c.x) < 0.2, 0.03, 0.018, "brown", "iron", trim_width=0.008)
    for sh, s in ((sh_l, 1), (sh_r, -1)):   # Schulterplatten in drei Lagen
        for k, (r, off) in enumerate(((0.13, 0.022), (0.105, 0.036), (0.08, 0.05))):
            c = sh + V((0.035 * s * k, 0.0, 0.0))
            shell(ctx, "Pauldron%d" % k, lambda co, n, c=c, r=r: (co - c).length < r and n.z > 0.15 and co.z > c.z - 0.02,
                  off, 0.012, "leather", "red", trim_width=0.014)
    for side, s in (("l", 1), ("r", -1)):
        el, wr, hd = J("lowerarm." + side), J("wrist." + side), J("hand." + side)
        lo, hi = el.x + (wr.x - el.x) * 0.22, wr.x + 0.01 * s
        shell(ctx, "Bracer", lambda c, n, lo=lo, hi=hi, s=s: min(lo, hi) < c.x < max(lo, hi) and c.x * s > 0, 0.01, 0.01, "leather", "red")
        ll, ft = J("lowerleg." + side), J("foot." + side)
        shell(ctx, "Boot", lambda c, n, ll=ll, s=s: c.z < ll.z - 0.12 and c.x * s > 0 and abs(c.x) < 0.3, 0.012, 0.012, "leather", "brown")
        shell(ctx, "KneeGuard", lambda c, n, ll=ll, s=s: (c - (ll + V((0, -0.05, 0)))).length < 0.075 and n.y < -0.2,
              0.03, 0.012, "iron", "leather", trim_width=0.01)
    straps = bd.Parts("LegStraps")
    for side in ("l", "r"):
        for t in (0.45, 0.62):
            limb_ring(ctx, straps, "upperleg." + side, "lowerleg." + side, t)
        limb_ring(ctx, straps, "lowerleg." + side, "foot." + side, 0.36, half_width=0.016, gap=0.02)   # Stiefelrand
    parts_object(ctx, straps, "brown")
    head = lambda c, n: (c.z > 1.6 and c.z < 1.835 and c.y < 0.02 and abs(c.x) < 0.14) or (1.62 < c.z < 1.74 and abs(c.x) < 0.09)
    shell(ctx, "Mask", head, 0.009, 0.006, "red", "red")
    build_hood(ctx)
    build_tabards(ctx)
    build_scarf_tails(ctx)
    build_straps(ctx)
    build_metal_details(ctx)
    build_daggers(ctx)
    build_eyes(ctx)
    paint_body_regions(ctx, "cloth", "leather")


def paint_body_regions(ctx, base, hands, face=None):
    """Grundkörper einfärben: base (Unteranzug), hands (Handschuhe/Haut), face (sichtbares Gesicht, sonst wie base)."""
    set_attrs(ctx["body"], REG[base])
    me = ctx["body"].data
    reg = me.attributes["reg"].data
    hx = abs(joint(ctx["arm"], "wrist.l").x)
    for v in me.vertices:
        c = v.co
        if abs(c.x) > hx - 0.01:
            reg[v.index].value = REG[hands]
        elif face and c.z > 1.72 and c.y < 0.0 and abs(c.x) < 0.1:
            reg[v.index].value = REG[face]


def region_preview_material():
    """Vorschau ohne Backen: Werkstoff je Punkt als Farbe, Saum in Saumfarbe."""
    mat = bpy.data.materials.new("RegionPreview")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")

    reg, treg, trim = attr(nt, "reg", (-900, 0)), attr(nt, "treg", (-900, -300)), attr(nt, "trim", (-900, -600))
    col = bd.mix_col(nt, region_ramp(nt, reg, REG_COLOR, "#000000", (-700, 0)),
                     region_ramp(nt, treg, REG_COLOR, "#000000", (-700, -300)), trim, (-300, 0))
    nt.links.new(col, bsdf.inputs["Base Color"])
    nt.links.new(region_ramp(nt, reg, REG_EMIT, "#000000", (-700, -500)), bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 2.0
    bsdf.inputs["Roughness"].default_value = 0.6
    mat.use_backface_culling = False
    return mat


# --- Phase 4: Texturen -------------------------------------------------------------------------------


def attr(nt, name, loc):
    a = nt.nodes.new("ShaderNodeAttribute")
    a.attribute_name = name
    a.location = loc
    return a.outputs["Fac"]


def region_ramp(nt, value, table, default, loc):
    """Werkstoff-Nummer (0..REG_N-1) -> Farbe oder Grauwert, stufig (keine Übergänge zwischen Werkstoffen)."""
    div = bd.math_node(nt, "DIVIDE", loc, value, float(REG_N))
    node = nt.nodes.new("ShaderNodeValToRGB")
    node.location = (loc[0] + 200, loc[1])
    node.color_ramp.interpolation = "CONSTANT"
    els = node.color_ramp.elements

    def rgba(i):
        v = table.get(i, default)
        if isinstance(v, str):
            return (*bd.hex_lin(v), 1.0)
        return (v, v, v, 1.0)

    els[0].position, els[0].color = 0.0, rgba(0)
    els[1].position, els[1].color = 0.999, rgba(REG_N - 1)
    for i in range(1, REG_N):
        el = els.new((i - 0.5) / REG_N)
        el.color = rgba(i)
    nt.links.new(div, node.inputs[0])
    return node.outputs[0]


def mask_of(nt, value, ids, loc):
    out = None
    for k, i in enumerate(ids):
        m = nt.nodes.new("ShaderNodeMath")
        m.operation = "COMPARE"
        m.location = (loc[0], loc[1] - 60 * k)
        nt.links.new(value, m.inputs[0])
        m.inputs[1].default_value = float(i)
        m.inputs[2].default_value = 0.5
        out = m.outputs[0] if out is None else bd.math_node(nt, "ADD", (loc[0] + 150, loc[1] - 60 * k), out, m.outputs[0])
    return out


def bake_material():
    """Prozedurales Material nur zum Backen: Werkstofffarben, Säume, Lederkorn, Stoffkörnung, Prägung, Glanzwerte."""
    mat = bpy.data.materials.new(HERO["prefix"] + "Bake")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    reg, treg, trim = attr(nt, "reg", (-2200, 400)), attr(nt, "treg", (-2200, 200)), attr(nt, "trim", (-2200, 0))
    trim_mask = bd.smooth_range(nt, trim, 0.42, 0.58, (-2000, 0))
    groove = bd.math_node(nt, "SUBTRACT", (-1800, -150), 1.0,
                          bd.smooth_range(nt, bd.math_node(nt, "ABSOLUTE", (-2000, -150),
                                                           bd.math_node(nt, "SUBTRACT", (-2100, -150), trim, 0.5)),
                                          0.0, 0.1, (-1900, -150)))
    # Werkstoff an diesem Punkt: im Saum der Saum-Werkstoff
    in_trim = bd.math_node(nt, "GREATER_THAN", (-1900, 300), trim_mask, 0.5)   # hart umschalten: Nummern nie mischen
    here_v = bd.math_node(nt, "ADD", (-1650, 300), reg, bd.math_node(nt, "MULTIPLY", (-1750, 300), in_trim,
                                                                   bd.math_node(nt, "SUBTRACT", (-1850, 350), treg, reg)))
    base = bd.mix_col(nt, region_ramp(nt, reg, REG_COLOR, "#000000", (-1800, 600)),
                      region_ramp(nt, treg, REG_COLOR, "#000000", (-1800, 800)), trim_mask, (-1400, 650))
    coord = nt.nodes.new("ShaderNodeTexCoord")
    coord.location = (-2200, -400)
    fine = nt.nodes.new("ShaderNodeTexNoise")
    fine.location = (-1900, -400)
    fine.inputs["Scale"].default_value = 110.0
    fine.inputs["Detail"].default_value = 8.0
    nt.links.new(coord.outputs["Object"], fine.inputs["Vector"])
    big = nt.nodes.new("ShaderNodeTexNoise")
    big.location = (-1900, -650)
    big.inputs["Scale"].default_value = 7.0
    big.inputs["Detail"].default_value = 3.0
    nt.links.new(coord.outputs["Object"], big.inputs["Vector"])
    cloth = mask_of(nt, here_v, CLOTH_REGS, (-1500, -1200))
    leather = mask_of(nt, here_v, LEATHER_REGS, (-1500, -1500))
    metal_m = mask_of(nt, here_v, (5, 6, 9, 10), (-1500, -1800))
    centered = lambda s, loc: bd.math_node(nt, "SUBTRACT", loc, s, 0.5)
    mult = bd.math_node(nt, "ADD", (-1200, -500), 1.0, bd.math_node(nt, "MULTIPLY", (-1300, -500), centered(big.outputs["Fac"], (-1400, -500)), 0.35))
    m2 = bd.math_node(nt, "ADD", (-1200, -700), 1.0, bd.math_node(nt, "MULTIPLY", (-1300, -700),
                                                                  bd.math_node(nt, "MULTIPLY", (-1400, -700), centered(fine.outputs["Fac"], (-1500, -700)), 0.55), leather))
    m3 = bd.math_node(nt, "ADD", (-1200, -900), 1.0, bd.math_node(nt, "MULTIPLY", (-1300, -900),
                                                                  bd.math_node(nt, "MULTIPLY", (-1400, -900), centered(fine.outputs["Fac"], (-1500, -900)), 0.22), cloth))
    m4 = bd.math_node(nt, "SUBTRACT", (-1200, -1100), 1.0, bd.math_node(nt, "MULTIPLY", (-1300, -1100), groove, 0.55))
    shade = bd.math_node(nt, "MULTIPLY", (-1000, -700), bd.math_node(nt, "MULTIPLY", (-1100, -600), mult, m2),
                         bd.math_node(nt, "MULTIPLY", (-1100, -800), m3, m4))
    col = bd.mix_col(nt, (0, 0, 0, 1), base, shade, (-800, 400))
    nt.links.new(col, bsdf.inputs["Base Color"])
    # Relief: Korn, Gewebe, erhabener Saum mit Rille
    h = bd.math_node(nt, "ADD", (-800, -500), bd.math_node(nt, "MULTIPLY", (-900, -450), fine.outputs["Fac"], leather),
                     bd.math_node(nt, "MULTIPLY", (-900, -550), fine.outputs["Fac"], bd.math_node(nt, "MULTIPLY", (-1000, -550), cloth, 0.3)))
    h = bd.math_node(nt, "ADD", (-750, -550), h, bd.math_node(nt, "MULTIPLY", (-850, -600), big.outputs["Fac"],
                                                               bd.math_node(nt, "MULTIPLY", (-950, -650), metal_m, 0.25)))   # gehämmert
    h = bd.math_node(nt, "ADD", (-700, -600), h, bd.math_node(nt, "MULTIPLY", (-800, -650), trim_mask, 0.5))
    h = bd.math_node(nt, "SUBTRACT", (-600, -650), h, bd.math_node(nt, "MULTIPLY", (-700, -700), groove, 0.6))
    bump = nt.nodes.new("ShaderNodeBump")
    bump.location = (-400, -600)
    bump.inputs["Strength"].default_value = 0.8
    bump.inputs["Distance"].default_value = 0.003
    nt.links.new(h, bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    nt.links.new(region_ramp(nt, here_v, REG_EMIT, "#000000", (-600, -900)), bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 1.0
    # Glanzwerte als Farbe: G = Rauheit, B = Metall (für den Extra-Bake)
    rough = region_ramp(nt, here_v, REG_ROUGH, 0.6, (-600, -1300))
    metal = region_ramp(nt, here_v, REG_METAL, 0.0, (-600, -1500))
    comb = nt.nodes.new("ShaderNodeCombineColor")
    comb.location = (-200, -1400)
    comb.inputs[0].default_value = 1.0
    nt.links.new(rough, comb.inputs[1])
    nt.links.new(metal, comb.inputs[2])
    mat["orm_socket"] = comb.name
    return mat


def regions_per_face(obj):
    """Werkstoffnummern je Fläche festlegen (Mehrheit ihrer Punkte): über ein Dreieck gemischte Nummern würden sonst
    durch fremde Werkstoffe laufen (Haut 0 -> Stoff 11 streift das rote Augenleuchten 7)."""
    from collections import Counter
    me = obj.data
    for name in ("reg", "treg"):
        point = [d.value for d in me.attributes[name].data]
        me.attributes.remove(me.attributes[name])
        corner = me.attributes.new(name, "FLOAT", "CORNER")
        for poly in me.polygons:
            value = Counter(round(point[v]) for v in poly.vertices).most_common(1)[0][0]
            for li in poly.loop_indices:
                corner.data[li].value = value


def stage_texture(ctx):
    import numpy as np
    pieces = ctx.pop("pieces")
    px = HERO["prefix"]
    body = bd.join([ctx["body"]] + pieces, px + "_Body")
    regions_per_face(body)
    ctx["body"] = body
    bd.unwrap(body, margin=0.002)
    bd.setup_bake_engine()
    mat = bake_material()
    body.data.materials.clear()
    body.data.materials.append(mat)
    size = 2048
    albedo = bd.new_image(px + "_albedo", size)
    normal = bd.new_image(px + "_normal", size, non_color=True)
    ao = bd.new_image(px + "_ao", size, non_color=True)
    orm = bd.new_image(px + "_orm", 1024, non_color=True)
    emit = bd.new_image(px + "_emission", 1024)
    bd.bake(body, mat, albedo, "DIFFUSE", pass_filter={"COLOR"})
    bd.bake(body, mat, normal, "NORMAL", normal_space="TANGENT")
    bd.bake(body, mat, emit, "EMIT")
    bd.bake(body, mat, ao, "AO", samples=48)
    # Glanzwerte: Kombi-Farbe vorübergehend als Leuchten ausgeben und backen
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    em_link = bsdf.inputs["Emission Color"].links[0]
    em_src = em_link.from_socket
    nt.links.remove(em_link)
    nt.links.new(nt.nodes[mat["orm_socket"]].outputs[0], bsdf.inputs["Emission Color"])
    bd.bake(body, mat, orm, "EMIT")
    nt.links.new(em_src, bsdf.inputs["Emission Color"])
    alb = bd.pixels(albedo)
    occ = bd.pixels(ao)[..., :1]
    alb[..., :3] *= 0.38 + 0.62 * np.clip(occ, 0, 1) ** 1.15
    bd.set_pixels(albedo, alb)
    for img in (albedo, normal, orm, emit):
        bd.save_image(img)
    final = bd.final_material(px, albedo, normal, emit, emission_strength=HERO.get("emission", 2.5), roughness=0.6,
                              double_sided=True)
    fnt = final.node_tree
    fb = fnt.nodes.get("Principled BSDF")
    t = fnt.nodes.new("ShaderNodeTexImage")
    t.image = orm
    sep = fnt.nodes.new("ShaderNodeSeparateColor")
    fnt.links.new(t.outputs["Color"], sep.inputs[0])
    fnt.links.new(sep.outputs[1], fb.inputs["Roughness"])
    fnt.links.new(sep.outputs[2], fb.inputs["Metallic"])
    body.data.materials.clear()
    body.data.materials.append(final)
    log("Texturen fertig: %d Flächen in einem Mesh" % len(body.data.polygons))


# --- Phase 5: Export ---------------------------------------------------------------------------------

def stage_export(ctx):
    arm = ctx["arm"]
    arm.animation_data_create()
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    out = ctx["out"]
    os.makedirs(os.path.dirname(out), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=False, export_animations=True,
                              export_animation_mode="ACTIONS", export_skins=True, export_def_bones=False, export_yup=True)
    log("exportiert -> %s (%.1f MB, %d Animationen)" % (out, os.path.getsize(out) / 1e6, len(bpy.data.actions)))


# --- Ablauf --------------------------------------------------------------------------------------------

VIEWS = {
    "front": ((-1.6, -4.6, 1.5), (0.0, 0.0, 1.05)),
    "side": ((-4.8, -0.4, 1.3), (0.0, 0.0, 1.0)),
    "back": ((1.8, 4.4, 1.6), (0.0, 0.0, 1.05)),
    "face": ((-0.45, -1.3, 1.85), (0.0, 0.0, 1.72)),
}


def render(folder, tag, views=("front", "side", "back", "face"), res=(900, 1100)):
    scene = bpy.context.scene
    cam = scene.camera
    scene.render.resolution_x, scene.render.resolution_y = res
    cam.data.lens = 60
    os.makedirs(folder, exist_ok=True)
    for view in views:
        bd.look(cam, *VIEWS[view])
        scene.render.filepath = os.path.join(folder, "%s_%s.png" % (tag, view))
        bpy.ops.render.render(write_still=True)
        log("Vorschau -> %s" % scene.render.filepath)


def show_bones(arm):
    """Für die Skelett-Vorschau: dünne Stäbe für jeden verformenden Knochen."""
    bm = bmesh.new()
    for b in arm.data.bones:
        if b.name.startswith(("control", "IK", "kneeIK", "heelIK", "elbowIK", "handIK", "root")):
            continue
        h, t = arm.matrix_world @ b.head_local, arm.matrix_world @ b.tail_local
        d = t - h
        if d.length < 1e-4:
            continue
        res = bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.02, radius2=0.008, depth=d.length)
        rot = V((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
        bmesh.ops.transform(bm, matrix=Matrix.Translation((h + t) / 2) @ rot, verts=res["verts"])
    me = bpy.data.meshes.new("BonePreview")
    bm.to_mesh(me)
    bm.free()
    bd.link(bpy.data.objects.new("BonePreview", me))


# --- Gemeinsame Bausteine für Krieger und Magier -------------------------------------------------------

def grid_piece(ctx, name, nu, nv, point, weights, trim, reg, treg, closed_u=False, thickness=0.01):
    """Stofffläche aus einem Gitter (Umhang, Rock, Schild): point(u, v) -> Ort, weights(u, v, ort) -> {Knochen: Gewicht},
    trim(i, j) -> Saumanteil 0..1. closed_u schließt das Gitter zu einem Ring (Rock)."""
    groups = [g.name for g in ctx["body"].vertex_groups]
    for extra in ("handslot.l", "handslot.r"):
        if extra not in groups:
            groups.append(extra)
    gi = {g: i for i, g in enumerate(groups)}
    bm = bmesh.new()
    deform = bm.verts.layers.deform.verify()
    cols = nu if closed_u else nu + 1
    rows, trims = [], []
    for j in range(nv + 1):
        row = []
        for i in range(cols):
            u, v = i / nu, j / nv
            co = point(u, v)
            vert = bm.verts.new(co)
            ws = weights(u, v, co)
            total = sum(ws.values()) or 1.0
            for b, w in ws.items():
                if w > 1e-4:
                    vert[deform][gi[b]] = w / total
            trims.append(trim(i, j))
            row.append(vert)
        rows.append(row)
    for j in range(nv):
        for i in range(nu):
            bm.faces.new((rows[j][i], rows[j][(i + 1) % cols], rows[j + 1][(i + 1) % cols], rows[j + 1][i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = new_skinned(name, me, ctx["arm"], groups)
    set_attrs(obj, REG[reg], REG[treg], trims)
    if thickness > 0.0:
        solidify(obj, thickness, offset=0.0)
    ctx.setdefault("pieces", []).append(obj)
    return obj


def rigid_meta(ctx, name, meta_obj, bone, reg, voxel=0.007, faces=5000, weights=None):
    """Metaball-Teil vereinen und starr an einen Knochen hängen (Helm) – oder mit weights(co) -> {Knochen: Gewicht}."""
    obj = bd.unify(name, [meta_obj], voxel=voxel, smooth_iter=3, target_faces=faces)
    groups = [g.name for g in ctx["body"].vertex_groups]
    for g in groups:
        obj.vertex_groups.new(name=g)
    for v in obj.data.vertices:
        for b, w in (weights(v.co) if weights else {bone: 1.0}).items():
            if w > 1e-4:
                obj.vertex_groups[b].add([v.index], w, "REPLACE")
    obj.modifiers.new("Armature", "ARMATURE").object = ctx["arm"]
    obj.parent = ctx["arm"]
    set_attrs(obj, REG[reg])
    ctx.setdefault("pieces", []).append(obj)
    return obj


def contour_xy(ctx, z, n, gap, meshes=None):
    """Radius der Körperoberfläche je Richtung (Winkel in der XY-Ebene) auf Höhe z, geglättet, plus Abstand."""
    radius = [0.0] * n
    for v in (pv for o in (meshes or [ctx["body"]]) for pv in o.data.vertices):
        if abs(v.co.z - z) < 0.015:
            k = int(round(math.atan2(v.co.y, v.co.x) / (2 * math.pi) * n)) % n
            radius[k] = max(radius[k], V((v.co.x, v.co.y)).length)
    filled = [r for r in radius if r > 0.0]
    mean = sum(filled) / max(1, len(filled))
    radius = [r if r > 0.0 else mean for r in radius]
    return [(radius[k - 1] + 2 * radius[k] + radius[(k + 1) % n]) / 4 + gap for k in range(n)]


def edge_trim(nu, nv, sides=("left", "right", "bottom")):
    """Saum an den Gitterrändern (ganz außen 1, eine Reihe weiter innen 0,5)."""
    def f(i, j):
        d = []
        if "left" in sides:
            d.append(i)
        if "right" in sides:
            d.append(nu - i)
        if "bottom" in sides:
            d.append(nv - j)
        if "top" in sides:
            d.append(j)
        m = min(d) if d else 9
        return 1.0 if m == 0 else (0.5 if m == 1 else 0.0)
    return f


# --- Krieger -------------------------------------------------------------------------------------------

def build_helmet(ctx):
    """Topfhelm: Kuppel, Gesichtsplatte, Wangen, Nackenschutz; Sehschlitz in T-Form, Goldkamm und Goldränder."""
    m = Meta("HelmMeta", resolution=0.01)
    m.chain([(0, 0.005, 1.84), (0, 0.01, 1.92)], [0.124, 0.11])
    m.ball((0, 0.045, 1.85), 0.114)
    m.ball((0, -0.04, 1.83), 0.102)
    m.ball((0, -0.05, 1.77), 0.082)
    for s in (1, -1):
        m.ball((0.072 * s, -0.025, 1.79), 0.077)
    m.ball((0, 0.06, 1.765), 0.092)
    helm = rigid_meta(ctx, "Helm", m.obj, "head", "plate")
    bvh = surface_bvh([helm])
    front = lambda x, z, lift=0.002: on_surface(bvh, (x, 0.0, z), (0, 1, 0), lift)
    dark, gold = bd.Parts("Visor"), bd.Parts("HelmGold")
    xs = [-0.078 + 0.156 * k / 10 for k in range(11)]
    dark.tube([front(x, 1.848) for x in xs], [0.011] * 11, "head", verts=6, flat=0.3, flat_axis=FWD)
    dark.tube([front(0.0, 1.84 - 0.05 * k / 4) for k in range(5)], [0.006] * 5, "head", verts=6, flat=0.4, flat_axis=FWD)
    for z in (1.873, 1.822):
        gold.tube([front(x * 1.08, z, 0.003) for x in xs], [0.006] * 11, "head", verts=6, flat=0.5, flat_axis=FWD)
    crest = [on_surface(bvh, (0.0, -0.10 + 0.21 * k / 12, 2.3), (0, 0, -1), 0.006) for k in range(13)]
    gold.tube(crest, [0.016] * 13, "head", verts=8, flat=0.4, flat_axis=LEFT)
    for s in (1, -1):   # Nieten an den Schläfen
        c = on_surface(bvh, (0.0, -0.01, 1.86), (-s, 0, 0), 0.0)
        gold.tube([c, c + V((0.012 * s, 0, 0))], [0.012, 0.0], "head", verts=8)
    parts_object(ctx, dark, "cloth")
    parts_object(ctx, gold, "gold")


def build_sword(ctx, name="1H_Sword", scale=0.62):
    """Langschwert in der Griffachse des KayKit-Schwerts: blaue Wicklung, goldene Parierstange und Knauf."""
    w = weapon_axes(ctx, name, scale)
    o, L, M, T, slot = w["origin"], w["long"], w["mid"], w["thin"], w["slot"]
    p = lambda a, b=0.0: o + L * a + M * b
    grip, gold, steel = bd.Parts("SwordGrip"), bd.Parts("SwordGold"), bd.Parts("SwordBlade")
    grip.tube([p(-0.1), p(0.09)], [0.019, 0.019], slot, verts=8, ridges=0.1)
    gold.tube([p(-0.14), p(-0.115), p(-0.095)], [0.024, 0.031, 0.02], slot, verts=10)                   # Knauf
    gold.tube([p(0.1, -0.15), p(0.1, -0.075), p(0.1, 0.0), p(0.1, 0.075), p(0.1, 0.15)],
              [0.013, 0.017, 0.022, 0.017, 0.013], slot, verts=8, flat=0.6, flat_axis=L)                 # Parierstange
    blade = max(0.7, w["far"] - 0.12)
    ts = (0.0, 0.25, 0.5, 0.75, 0.93, 1.0)
    steel.tube([p(0.11 + blade * t) for t in ts], [0.052, 0.05, 0.046, 0.04, 0.024, 0.0], slot, verts=8, flat=0.16, flat_axis=T)
    log("Schwert: Klinge %.2f m" % blade)
    parts_object(ctx, grip, "blue")
    parts_object(ctx, gold, "gold")
    parts_object(ctx, steel, "steel")


def build_shield(ctx, name="Round_Shield", width=0.56, height=0.74):
    """Wappenschild (Dreiecksform) in der Lage des KayKit-Schilds: blau emailliert, Goldrand, eigener Sonnenstern."""
    w = weapon_axes(ctx, name)
    c, T, slot = w["center"], w["thin"], w["slot"]
    face = T if (c - w["origin"]).dot(T) >= 0 else -T                      # Schauseite: weg von der Hand
    turn = idle_rotation(ctx["arm"], slot)                                 # "oben" = oben in der Stehanimation
    up = max((w["long"], -w["long"], w["mid"], -w["mid"]), key=lambda a: (turn @ a).dot(UP))
    side = face.cross(up).normalized()
    c = c + face * 0.02

    def hw(v):   # halbe Breite: oben gerade, unten zur Spitze gerundet
        return width * 0.5 if v > 0.15 else width * 0.5 * math.sqrt(max(0.0, 1.0 - ((0.15 - v) / 1.15) ** 2))

    def surf(u, v):
        return c + side * (u * hw(v)) + up * (v * height * 0.5) + face * (0.05 * (1 - u * u) * (1 - 0.35 * v * v))

    nu, nv = 14, 18
    grid_piece(ctx, "Shield", nu, nv, lambda u, v: surf(2 * u - 1, 1 - 2 * v), lambda u, v, co: {slot: 1.0},
               edge_trim(nu, nv, ("left", "right", "bottom", "top")), "plate", "gold", thickness=0.024)
    gold = bd.Parts("ShieldEmblem")
    center = surf(0.0, 0.12) + face * 0.014
    gold.tube([center - face * 0.008, center + face * 0.004], [0.055, 0.05], slot, verts=16)          # Mittelscheibe
    for k in range(8):   # achtstrahliger Sonnenstern
        a = 2 * math.pi * k / 8
        d = (side * math.cos(a) + up * math.sin(a)).normalized()
        length = 0.2 if k % 2 == 0 else 0.13
        tip = surf(math.cos(a) * length / (width * 0.5), 0.12 + math.sin(a) * length / (height * 0.5)) + face * 0.012
        gold.tube([center + d * 0.04, tip], [0.022, 0.0], slot, verts=6, flat=0.35, flat_axis=face)
    parts_object(ctx, gold, "gold")


def build_cape(ctx, color="blue", trim="gold", top=1.6, bottom=0.5):
    """Umhang hinter den Schultern: oben an der Brust, unten an Wirbelsäule und Becken."""
    def point(u, v):
        x = (u - 0.5) * bd.lerp(0.40, 0.64, v)
        y = bd.lerp(0.19, 0.31, v) + 0.035 * math.sin(math.pi * u) * v
        return V((x, y, bd.lerp(top, bottom, v)))

    def weights(u, v, co):
        return {"chest": 1.0 - bd.smoothstep(0.0, 0.45, v), "spine": math.sin(math.pi * min(1.0, v * 1.3)) * 0.8,
                "hips": bd.smoothstep(0.35, 1.0, v)}

    grid_piece(ctx, "Cape", 10, 16, point, weights, edge_trim(10, 16), color, trim, thickness=0.01)


def outfit_guardian(ctx):
    """Krieger: blau-goldene Plattenrüstung, Topfhelm, große Schulterplatten, Wappenrock, Umhang, Schwert und Schild."""
    arm = ctx["arm"]
    J = lambda n: joint(arm, n)
    tx = J("upperarm.l").x - 0.05
    shell(ctx, "Breastplate", lambda c, n: 1.1 < c.z < 1.6 and abs(c.x) < tx, 0.03, 0.016, "plate", "gold", 0.022)
    shell(ctx, "Fauld1", lambda c, n: 1.045 < c.z < 1.11 and abs(c.x) < tx, 0.036, 0.014, "plate", "gold", 0.012)
    shell(ctx, "Fauld2", lambda c, n: 0.995 < c.z < 1.055 and abs(c.x) < tx, 0.04, 0.014, "plate", "gold", 0.012)
    shell(ctx, "Belt", lambda c, n: 0.955 < c.z < 1.0 and abs(c.x) < tx, 0.046, 0.016, "brown", "gold", 0.006)
    shell(ctx, "Gorget", lambda c, n: 1.56 < c.z < 1.72 and abs(c.x) < 0.13, 0.03, 0.014, "plate", "gold", 0.014)
    for side, s in (("l", 1), ("r", -1)):
        sh, el, wr = J("upperarm." + side), J("lowerarm." + side), J("wrist." + side)
        for k, (r, off) in enumerate(((0.2, 0.045), (0.16, 0.066), (0.12, 0.087))):   # Schulterplatten in drei Lagen
            c = sh + V((0.03 * s * k, 0.0, 0.012 * k))
            shell(ctx, "Pauldron%d" % k, lambda co, n, c=c, r=r: (co - c).length < r and n.z > 0.0 and co.z > c.z - 0.06,
                  off, 0.016, "plate", "gold", 0.018)
        lo, hi = sh.x + (el.x - sh.x) * 0.35, el.x - (el.x - sh.x) * 0.08
        shell(ctx, "Rerebrace", lambda c, n, lo=lo, hi=hi: min(lo, hi) < c.x < max(lo, hi), 0.022, 0.012, "plate", "gold", 0.012)
        shell(ctx, "Couter", lambda c, n, el=el: (c - el).length < 0.075, 0.034, 0.012, "plate", "gold", 0.014)
        lo, hi = el.x + (wr.x - el.x) * 0.15, wr.x
        shell(ctx, "Vambrace", lambda c, n, lo=lo, hi=hi: min(lo, hi) < c.x < max(lo, hi), 0.022, 0.012, "plate", "gold", 0.014)
        shell(ctx, "Gauntlet", lambda c, n, wr=wr, s=s: abs(c.x) > abs(wr.x) - 0.005 and c.x * s > 0, 0.012, 0.008, "steel", "gold", 0.008)
        ll = J("lowerleg." + side)
        shell(ctx, "Tasset", lambda c, n, s=s: 0.80 < c.z < 0.97 and c.x * s > 0.04 and n.y < 0.35 and abs(c.x) < 0.32,
              0.036, 0.014, "plate", "gold", 0.016)
        shell(ctx, "Cuisse", lambda c, n, ll=ll, s=s: ll.z + 0.07 < c.z < 0.80 and c.x * s > 0 and n.y < 0.15 and abs(c.x) < 0.32,
              0.024, 0.012, "plate", "gold", 0.014)
        shell(ctx, "Poleyn", lambda c, n, ll=ll: (c - (ll + V((0, -0.055, 0)))).length < 0.085 and n.y < -0.1,
              0.04, 0.014, "plate", "gold", 0.016)
        shell(ctx, "Greave", lambda c, n, ll=ll, s=s: 0.12 < c.z < ll.z - 0.07 and c.x * s > 0 and abs(c.x) < 0.32,
              0.022, 0.012, "plate", "gold", 0.014)
        shell(ctx, "Sabaton", lambda c, n, s=s: c.z < 0.13 and c.x * s > 0 and abs(c.x) < 0.32, 0.016, 0.01, "steel", "gold", 0.01)
    build_tabards(ctx, ((-1, -0.2, -0.24, 0.22, 0.5), (1, 0.2, 0.25, 0.26, 0.46)), "blue", "gold", top_z=0.985, name="Tabard")
    build_cape(ctx)
    build_helmet(ctx)
    gold = bd.Parts("Buckle")
    gold.tube([V((0, -0.17, 0.978)), V((0, -0.19, 0.978))], [0.032, 0.03], "hips", verts=4)
    parts_object(ctx, gold, "gold")
    build_sword(ctx)
    build_shield(ctx)
    paint_body_regions(ctx, "iron", "steel")


# --- Magier --------------------------------------------------------------------------------------------

def build_beard(ctx):
    """Langer weißer Bart mit Schnurrbart; oben am Kopf, die Spitze folgt teilweise der Brust."""
    m = Meta("BeardMeta", resolution=0.008)
    m.chain([(0, -0.082, 1.79), (0, -0.108, 1.70), (0, -0.118, 1.59), (0, -0.112, 1.48), (0, -0.10, 1.39)],
            [0.056, 0.07, 0.064, 0.045, 0.018])
    for s in (1, -1):
        m.chain([(0.065 * s, -0.055, 1.81), (0.055 * s, -0.085, 1.73), (0.03 * s, -0.105, 1.64)], [0.045, 0.05, 0.045])
        m.chain([(0.0, -0.112, 1.80), (0.04 * s, -0.11, 1.795), (0.07 * s, -0.098, 1.775), (0.08 * s, -0.09, 1.74)],
                [0.017, 0.016, 0.013, 0.008], spacing=0.4)                                      # Schnurrbart
    rigid_meta(ctx, "Beard", m.obj, "head", "beard", voxel=0.006, faces=6000,
               weights=lambda co: {"head": bd.smoothstep(1.42, 1.70, co.z), "chest": 1.0 - bd.smoothstep(1.42, 1.70, co.z)})


def build_face_details(ctx):
    """Kräftige Nase und buschige weiße Augenbrauen."""
    skin, hair = bd.Parts("Nose"), bd.Parts("Brows")
    skin.tube([V((0, -0.092, 1.872)), V((0, -0.112, 1.84)), V((0, -0.124, 1.815)), V((0, -0.118, 1.805))],
              [0.013, 0.019, 0.018, 0.0], "head", verts=10)
    for s in (1, -1):
        hair.tube([V((0.014 * s, -0.1, 1.874)), V((0.04 * s, -0.098, 1.882)), V((0.068 * s, -0.086, 1.884))],
                  [0.011, 0.012, 0.0], "head", verts=6, flat=0.55, flat_axis=UP)
    parts_object(ctx, skin, "skin")
    parts_object(ctx, hair, "beard")


def build_mage_hood(ctx):
    m = Meta("MageHoodMeta", resolution=0.012)
    m.ball((0, 0.03, 1.89), 0.132)
    m.ball((0, 0.07, 1.84), 0.122)
    m.chain([(0, 0.09, 1.96), (0, 0.18, 1.99), (0, 0.27, 1.93), (0, 0.31, 1.84)], [0.075, 0.05, 0.03, 0.014], spacing=0.4)
    for s in (1, -1):
        m.ball((0.088 * s, -0.005, 1.81), 0.1)
        m.chain([(0.07 * s, 0.03, 1.69), (0.16 * s, 0.03, 1.64), (0.245 * s, 0.01, 1.6)], [0.085, 0.08, 0.065])   # Überwurf
    m.chain([(0, 0.09, 1.72), (0, 0.11, 1.60)], [0.095, 0.085])
    hood_from_meta(ctx, m.obj, (0.1, 0.17, 1.80), "blue", "gold", name="MageHood")


def build_skirt(ctx, top=1.02, hem=0.07, rx=0.34, ry=0.30):
    """Langer Robenrock: oben an der Taillenkontur, unten weit ausgestellt. Oben am Becken, darunter zwischen den
    Beinen gemischt – vorn und hinten hängt er wie Stoff zwischen beiden Beinen."""
    n = 40
    r_top = contour_xy(ctx, top, n, 0.03)
    nv = 16

    def point(u, v):
        a = 2 * math.pi * u
        k = int(round(u * n)) % n
        hem_r = 1.0 / math.sqrt((math.cos(a) / rx) ** 2 + (math.sin(a) / ry) ** 2)
        r = bd.lerp(r_top[k], hem_r, v ** 0.85)
        return V((math.cos(a) * r, math.sin(a) * r + 0.03 * v, bd.lerp(top, hem, v)))

    def weights(u, v, co):
        wh = max(0.0, 1.0 - 1.7 * v)
        s = min(1.0, max(0.0, 0.5 + co.x / 0.28))
        low = bd.smoothstep(0.45, 0.85, v)
        rest = 1.0 - wh
        return {"hips": wh, "upperleg.l": rest * s * (1 - low), "upperleg.r": rest * (1 - s) * (1 - low),
                "lowerleg.l": rest * s * low, "lowerleg.r": rest * (1 - s) * low}

    front = int(n * 0.75)   # vorn (y < 0) liegt bei 270°

    def trim(i, j):
        if j >= nv - 1:
            return 1.0 if j == nv else 0.6
        return 1.0 if i == front else (0.5 if abs(i - front) == 1 else 0.0)

    return grid_piece(ctx, "Skirt", n, nv, point, weights, trim, "blue", "gold", closed_u=True, thickness=0.012)


def build_staff(ctx, name="2H_Staff", scale=0.9):
    """Knorriger Holzstab mit Goldbändern; oben eine Gabel aus drei Zinken, die einen leuchtenden Kristall halten."""
    w = weapon_axes(ctx, name, scale)
    o, L, M, T, slot = w["origin"], w["long"], w["mid"], w["thin"], w["slot"]
    far, near = w["far"] * 0.9, min(0.3, w["near"])   # hinten kurz: das Original ragte durch den Körper
    log("Stab: oben %.2f m, unten %.2f m" % (far, near))
    p = lambda a, b=0.0, c=0.0: o + L * a + M * b + T * c
    wood, gold, crystal = bd.Parts("StaffWood"), bd.Parts("StaffGold"), bd.Parts("StaffCrystal")
    ts = [k / 16 for k in range(17)]
    wood.tube([p(-near + (far - 0.2 + near) * t, 0.006 * math.sin(t * 19), 0.006 * math.cos(t * 13)) for t in ts],
              [0.022 + 0.004 * math.sin(t * 31) for t in ts], slot, verts=8)
    for a in (-near, -0.13, 0.13, far - 0.24):
        gold.tube([p(a - 0.018), p(a + 0.018)], [0.027, 0.027], slot, verts=10)
    gold.tube([p(-near - 0.03), p(-near)], [0.0, 0.026], slot, verts=8)                    # Spitze unten
    head = far - 0.08
    for k in range(3):   # Gabel
        a = 2 * math.pi * k / 3
        d = M * math.cos(a) + T * math.sin(a)
        pts = [p(far - 0.22) + d * 0.015, p(far - 0.16) + d * 0.055, p(head) + d * 0.06, p(far + 0.02) + d * 0.03]
        gold.tube(pts, [0.012, 0.011, 0.009, 0.0], slot, verts=6)
    crystal.tube([p(head - 0.075), p(head), p(head + 0.075)], [0.0, 0.034, 0.0], slot, verts=6)   # Doppelspitze
    parts_object(ctx, wood, "wood")
    parts_object(ctx, gold, "gold")
    parts_object(ctx, crystal, "crystal")


def outfit_arcanist(ctx):
    """Magier: blaue Kapuzenrobe mit Goldsaum, Glockenärmel, langer weißer Bart, blau glühende Augen, Kristallstab."""
    arm = ctx["arm"]
    J = lambda n: joint(arm, n)
    tx = J("upperarm.l").x - 0.045
    shell(ctx, "RobeTop", lambda c, n: 0.99 < c.z < 1.63 and abs(c.x) < tx, 0.016, 0.01, "blue", "gold", 0.02)
    for side, s in (("l", 1), ("r", -1)):
        el, wr = J("lowerarm." + side), J("wrist." + side)
        e, w_ = abs(el.x), abs(wr.x)
        shell(ctx, "Sleeve", lambda c, n, s=s, w_=w_: 0.19 < abs(c.x) < w_ + 0.005 and c.x * s > 0, 0.0, 0.01, "blue", "gold", 0.02,
              offset_fn=lambda co, e=e, w_=w_: 0.016 + 0.075 * bd.smoothstep(e, w_, abs(co.x)))
        shell(ctx, "Boot", lambda c, n, s=s: c.z < 0.11 and c.x * s > 0 and abs(c.x) < 0.3, 0.012, 0.01, "brown", "brown", 0.006)
    skirt = build_skirt(ctx)
    belt = bd.Parts("Belt")
    ring_around(ctx, belt, V((0, 0.0, 1.0)), UP, {"hips": 1.0}, half_width=0.022, thick=0.009, gap=0.008, meshes=[skirt])
    belt.tube([V((0.05, -0.2, 0.99)), V((0.06, -0.21, 0.9)), V((0.05, -0.2, 0.8))], [0.012, 0.011, 0.0], "hips", verts=6)
    parts_object(ctx, belt, "gold")
    pouch = bd.Parts("Pouch")
    pouch.tube([V((0.16, -0.13, 0.97)), V((0.17, -0.14, 0.9)), V((0.16, -0.135, 0.86))], [0.035, 0.04, 0.0], "hips", verts=8,
               flat=0.6, flat_axis=FWD)
    parts_object(ctx, pouch, "brown")
    build_mage_hood(ctx)
    build_beard(ctx)
    build_face_details(ctx)
    build_eyes(ctx, reg="eye_blue", z=1.85, dx=0.033)
    build_staff(ctx)
    paint_body_regions(ctx, "blue", "skin", face="skin")


HEROES = {
    "shadow": {"source": "assets/models/heroes/Rogue_Hooded.glb", "prefix": "Shadow", "outfit": outfit_shadow,
               "weapons": []},
    "guardian": {"source": "assets/models/heroes/Knight.glb", "prefix": "Guardian", "outfit": outfit_guardian,
                 "weapons": ["1H_Sword", "Round_Shield"], "offset": {"upperarm": 1.3}, "body": {"torso": 1.15, "limbs": 1.18},
                 "emission": 2.0},
    "arcanist": {"source": "assets/models/heroes/Mage.glb", "prefix": "Arcanist", "outfit": outfit_arcanist,
                 "weapons": ["2H_Staff"], "body": {"torso": 0.95, "limbs": 0.92}, "emission": 3.0},
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    stage = argv[argv.index("--stage") + 1] if "--stage" in argv else STAGES[-1]
    preview = argv[argv.index("--preview") + 1] if "--preview" in argv else None
    hero_id = argv[argv.index("--hero") + 1] if "--hero" in argv else "shadow"
    HERO.clear()
    HERO.update(HEROES[hero_id], id=hero_id)
    default_out = os.path.join(PROJECT, "assets", "models", "heroes_custom", HERO["prefix"] + ".glb")
    ctx = {"out": argv[argv.index("--out") + 1] if "--out" in argv else default_out}
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 30          # KayKit-Animationen sind mit 30 fps erstellt
    bpy.context.scene.render.fps_base = 1.0
    for name in STAGES[: STAGES.index(stage) + 1]:
        fn = globals().get("stage_" + name)
        if fn is None:
            log("Phase %s noch nicht gebaut" % name)
            break
        log("--- Phase %s ---" % name)
        fn(ctx)
    if preview:
        bd.setup_render(samples=40)
        if stage == "skeleton":
            show_bones(ctx["arm"])
        mat = region_preview_material() if stage == "outfit" else bd.clay("Clay", (0.30, 0.27, 0.26))
        for obj in bpy.context.scene.objects:
            if obj.type == "MESH" and obj.name != "Ground" and not obj.data.materials:
                obj.data.materials.append(mat)
        arm = ctx["arm"]
        arm.animation_data_create()
        arm.animation_data.action = None
        for pb in arm.pose.bones:
            pb.matrix_basis = Matrix.Identity(4)
        render(preview, stage)
        if stage != "skeleton" and "Idle" in bpy.data.actions:   # dieselbe Figur in der KayKit-Stehpose
            arm.animation_data.action = bpy.data.actions["Idle"]
            bpy.context.scene.frame_set(10)
            render(preview, stage + "_idle", ("front", "side"))
    log("fertig.")


if __name__ == "__main__":
    main()
