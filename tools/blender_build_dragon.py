"""Glutdrache – eigener Drache, komplett per Skript in Blender gebaut (eigenes Skelett, eigene Animationen).

Aufbau in Phasen (jede Phase kann mit --preview als Bild gerendert werden):
  1 body      Rumpf, Hals, Schwanz, Beine (Metaballs) und Kopf (Querschnitt-Loft) -> ein geschlossenes Mesh
  2 details   Unterkiefer, Zähne, Hörner, Rückenstacheln, Krallen, Augen
  3 wings     Flügelknochen und Flughaut
  4 rig       Skelett und Gewichtung
  5 texture   Schuppen, Bauchplatten, Glut, Flughaut-Adern (in Bilder gebacken)
  6 anim      Animationen
  7 export    GLB nach assets/models/enemies_custom/EmberDrake.glb

Blender-Raum: vorn = -Y, oben = +Z, linke Seite des Drachen = +X (wie bei den Helden).

Aufruf (Blender 5.2, ohne Oberfläche):
  blender.exe --background --python tools/blender_build_dragon.py -- [--stage body] [--preview <ordner>]
"""
import math
import os
import random
import sys

import bpy
import bmesh
from mathutils import Matrix, Quaternion, Vector
from mathutils.bvhtree import BVHTree

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(PROJECT, "assets", "models", "enemies_custom", "EmberDrake.glb")
FPS = 30
V = Vector
UP = V((0.0, 0.0, 1.0))
FWD = V((0.0, -1.0, 0.0))
LEFT = V((1.0, 0.0, 0.0))
MB_SURFACE = 0.574      # Oberfläche einer einzelnen Metaball-Kugel liegt bei 0,574 x Radius (gemessen)
MB_CHAIN = 1.22         # Kugelketten mit Abstand 0,5 x R blähen um ~22 % auf (gemessen)
STAGES = ["body", "details", "wings", "rig", "texture", "anim", "export"]
rng = random.Random(11)


def log(msg):
    print("[dragon] %s" % msg, flush=True)


def link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


def lerp(a, b, t):
    return a + (b - a) * t


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3.0 - 2.0 * t)


def polyline_sample(points, t):
    """Punkt bei Anteil t (0..1) der Bogenlänge einer Polylinie."""
    lengths = [(points[i + 1] - points[i]).length for i in range(len(points) - 1)]
    total = sum(lengths)
    d = t * total
    for i, seg in enumerate(lengths):
        if d <= seg or i == len(lengths) - 1:
            return points[i].lerp(points[i + 1], min(1.0, d / seg if seg > 0 else 0.0))
        d -= seg
    return points[-1].copy()


def mesh_from_evaluated(obj, name):
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
    me.name = name
    return me


BODY_DROP = 0.15


def place(p):
    """Alle Entwurfskoordinaten laufen hier durch: senkt den Rumpf ab und staucht die Beine (gedrungener Stand).
    Füße (z < 0,3) bleiben, alles über 1,25 m sinkt um BODY_DROP."""
    p = V(p)
    return V((p.x, p.y, p.z - BODY_DROP * smoothstep(0.3, 1.25, p.z)))


# --- Kopf-Koordinaten ---------------------------------------------------------------------------------
# Ursprung am Kiefergelenk auf Höhe der Mundlinie, Schnauze leicht nach unten geneigt.

HEAD_O = V((0.0, -2.04, 2.56))
HEAD_SCALE = 1.4
_TILT = math.radians(10.0)
HEAD_F = V((0.0, -math.cos(_TILT), -math.sin(_TILT)))
HEAD_U = V((0.0, -math.sin(_TILT), math.cos(_TILT)))


def head_pt(s, x, z):
    """Kopfraum (s nach vorn, x nach links, z nach oben; vor der Skalierung) -> Blender-Raum."""
    return place(HEAD_O + (HEAD_F * s + LEFT * x + HEAD_U * z) * HEAD_SCALE)


# Oberkopf: (s, halbe Breite, Höhe über Mundlinie, Tiefe unter Mundlinie) – breiter Schädel, kräftige Schnauze
UPPER_HEAD = [
    (-0.14, 0.20, 0.24, 0.12), (0.00, 0.25, 0.28, 0.11), (0.12, 0.27, 0.28, 0.07), (0.25, 0.235, 0.23, 0.045),
    (0.38, 0.19, 0.18, 0.035), (0.52, 0.165, 0.15, 0.03), (0.64, 0.15, 0.135, 0.03), (0.74, 0.135, 0.115, 0.028),
    (0.80, 0.105, 0.09, 0.022), (0.835, 0.05, 0.05, 0.015),
]
# Unterkiefer: liegt unter dem Oberkopf, schmaler; oben die Mundfläche, unten das kräftige Kinn
JAW = [
    (-0.06, 0.20, 0.02, 0.21), (0.10, 0.205, 0.02, 0.20), (0.26, 0.18, 0.02, 0.155), (0.42, 0.155, 0.02, 0.12),
    (0.58, 0.135, 0.02, 0.095), (0.70, 0.115, 0.02, 0.08), (0.78, 0.08, 0.015, 0.06), (0.81, 0.035, 0.01, 0.03),
]


def loft(name, stations, n_top=2.6, n_bottom=4.0, ridge=0.0, ring=24):
    """Röhre aus Superellipsen-Querschnitten im Kopfraum; Enden geschlossen."""
    bm = bmesh.new()
    rings = []
    for s, w, top, bot in stations:
        verts = []
        for k in range(ring):
            a = 2.0 * math.pi * k / ring
            c, sn = math.cos(a), math.sin(a)
            n = n_top if sn >= 0.0 else n_bottom
            x = w * math.copysign(abs(c) ** (2.0 / n), c)
            h = top if sn >= 0.0 else bot
            z = h * math.copysign(abs(sn) ** (2.0 / n), sn)
            if sn > 0.0 and ridge > 0.0:
                z += top * ridge * math.exp(-((x / max(w, 1e-4)) / 0.28) ** 2)
            verts.append(bm.verts.new(head_pt(s, x, z)))
        rings.append(verts)
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(ring):
            bm.faces.new((r0[k], r0[(k + 1) % ring], r1[(k + 1) % ring], r1[k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return link(bpy.data.objects.new(name, me))


class Meta:
    """Metaball-Baukasten: Angaben sind Oberflächenradien in Metern."""

    def __init__(self, name, resolution=0.03):
        self.mb = bpy.data.metaballs.new(name)
        self.mb.resolution = resolution
        self.mb.render_resolution = resolution
        self.obj = link(bpy.data.objects.new(name, self.mb))

    def ball(self, p, radius, chain=False, placed=False):
        e = self.mb.elements.new()
        e.type = "BALL"
        e.co = V(p) if placed else place(p)
        e.radius = radius / (MB_SURFACE * (MB_CHAIN if chain else 1.0))
        return e

    def chain(self, points, radii, spacing=0.5, placed=False):
        """Kugelkette entlang einer Polylinie mit verlaufendem Radius (verjüngte Röhre)."""
        points = [V(p) for p in points]
        lengths = [(points[i + 1] - points[i]).length for i in range(len(points) - 1)]
        for i, seg in enumerate(lengths):
            r0, r1 = radii[i], radii[i + 1]
            t = 0.0
            while t < seg:
                f = t / seg
                r = lerp(r0, r1, f)
                self.ball(points[i].lerp(points[i + 1], f), r, chain=True, placed=placed)
                t += max(0.01, spacing * r)
        self.ball(points[-1], radii[-1], chain=True, placed=placed)


def mirror(p):
    return V((-p[0], p[1], p[2]))


# --- Phase 1: Körperform ------------------------------------------------------------------------------

# Wirbelsäule vom Hals hinter dem Kopf bis zur Schwanzspitze: (y, z, Oberflächenradius)
SPINE = [
    (-2.00, 2.50, 0.29), (-1.86, 2.38, 0.31), (-1.68, 2.20, 0.34), (-1.46, 1.98, 0.38), (-1.20, 1.78, 0.45),
    (-0.85, 1.64, 0.54), (-0.45, 1.58, 0.56), (-0.05, 1.52, 0.52), (0.35, 1.44, 0.47), (0.75, 1.30, 0.39),
    (1.25, 1.13, 0.31), (1.75, 0.97, 0.25), (2.25, 0.82, 0.195), (2.75, 0.68, 0.15), (3.25, 0.56, 0.11),
    (3.70, 0.48, 0.075), (4.05, 0.43, 0.045),
]
# tiefe, breite Brust und Bauch: Kiel unter der Wirbelsäule und zwei Rippenflanken
KEEL = [(-1.32, 1.58, 0.30), (-1.05, 1.40, 0.40), (-0.70, 1.30, 0.44), (-0.30, 1.30, 0.42), (0.10, 1.34, 0.36), (0.45, 1.33, 0.28)]
FLANK = [(-1.05, 1.52, 0.34), (-0.70, 1.45, 0.40), (-0.30, 1.43, 0.38), (0.10, 1.43, 0.32)]

FRONT_LEG = [((0.50, -1.00, 1.34), 0.24), ((0.62, -1.06, 0.80), 0.165), ((0.62, -1.18, 0.30), 0.11), ((0.64, -1.27, 0.13), 0.12)]
HIND_LEG = [((0.50, 0.38, 1.24), 0.33), ((0.68, 0.00, 0.80), 0.20), ((0.68, 0.50, 0.40), 0.115), ((0.68, 0.36, 0.13), 0.11)]
# Zehen: (Ansatz, Spitze) relativ zum Fußballen; Krallen kommen in Phase 2
FRONT_TOES = [((-0.10, -0.06, 0.0), (-0.16, -0.30, -0.08)), ((0.0, -0.08, 0.0), (0.0, -0.34, -0.08)),
              ((0.10, -0.06, 0.0), (0.16, -0.30, -0.08))]
HIND_TOES = [((-0.11, -0.07, 0.0), (-0.18, -0.34, -0.08)), ((0.0, -0.09, 0.0), (0.0, -0.38, -0.08)),
             ((0.11, -0.07, 0.0), (0.18, -0.34, -0.08))]


def build_body_parts():
    meta = Meta("BodyMeta")
    meta.chain([(0.0, y, z) for y, z, _ in SPINE], [r for _, _, r in SPINE])
    meta.chain([(0.0, y, z) for y, z, _ in KEEL], [r for _, _, r in KEEL])
    for side in (1.0, -1.0):
        sx = lambda p: V((p[0] * side, p[1], p[2]))
        meta.chain([sx((0.24, y, z)) for y, z, _ in FLANK], [r for _, _, r in FLANK])
        meta.ball(sx((0.40, -0.98, 1.50)), 0.33)                     # Schultermuskel
        meta.ball(sx((0.28, -1.28, 1.80)), 0.22)                     # Nackenansatz
        meta.ball(sx((0.42, 0.33, 1.27)), 0.40)                      # Oberschenkel / Keule
        meta.ball(sx((0.53, 0.10, 0.98)), 0.25)
        meta.chain([sx(p) for p, _ in FRONT_LEG], [r for _, r in FRONT_LEG], spacing=0.4)
        meta.chain([sx(p) for p, _ in HIND_LEG], [r for _, r in HIND_LEG], spacing=0.4)
        meta.ball(sx((0.62, -0.93, 0.96)), 0.17)                     # Unterarmmuskel
        meta.ball(sx((0.66, 0.22, 0.62)), 0.15)                      # Wade
        for leg, toes, r_toe in ((FRONT_LEG, FRONT_TOES, 0.062), (HIND_LEG, HIND_TOES, 0.068)):
            ball = V(leg[-1][0])
            for base, tip in toes:
                a = ball + V(base)
                b = ball + V(tip)
                meta.chain([sx(a), sx(a.lerp(b, 0.55) + V((0, 0, 0.025))), sx(b)], [r_toe, r_toe * 0.85, r_toe * 0.6], spacing=0.4)
    # Kopfdetails: schwere Brauenwülste, Jochbögen, Nüstern, Hinterkopf
    for side in (1.0, -1.0):
        meta.chain([head_pt(0.12, 0.165 * side, 0.20), head_pt(0.26, 0.16 * side, 0.19), head_pt(0.38, 0.13 * side, 0.15),
                    head_pt(0.48, 0.10 * side, 0.12)], [r * HEAD_SCALE for r in (0.05, 0.048, 0.035, 0.022)], spacing=0.4, placed=True)
        meta.chain([head_pt(0.02, 0.24 * side, 0.02), head_pt(0.22, 0.21 * side, 0.03)], [0.07 * HEAD_SCALE, 0.04 * HEAD_SCALE],
                   spacing=0.4, placed=True)
        meta.ball(head_pt(0.76, 0.075 * side, 0.095), 0.045 * HEAD_SCALE, placed=True)
    meta.chain([head_pt(-0.12, 0.0, 0.18), head_pt(0.03, 0.0, 0.22)], [0.13 * HEAD_SCALE, 0.09 * HEAD_SCALE], spacing=0.4, placed=True)
    head = loft("UpperHead", UPPER_HEAD, ridge=0.07)
    return meta.obj, head


def unify(name, objects, voxel=0.018, smooth_iter=4, target_faces=None):
    """Mehrere geschlossene Teile -> ein geschlossenes, gleichmäßiges Mesh (Voxel-Remesh)."""
    parts = []
    for obj in objects:
        me = mesh_from_evaluated(obj, obj.name + "_m")
        parts.append(me)
    bm = bmesh.new()
    for me in parts:
        bm.from_mesh(me)
    joined = bpy.data.meshes.new(name + "_joined")
    bm.to_mesh(joined)
    bm.free()
    tmp = link(bpy.data.objects.new(name + "_tmp", joined))
    rm = tmp.modifiers.new("Remesh", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = voxel
    rm.adaptivity = 0.0
    sm = tmp.modifiers.new("Smooth", "LAPLACIANSMOOTH")
    sm.iterations = smooth_iter
    sm.lambda_factor = 0.6
    sm.use_volume_preserve = True
    if target_faces:
        dec = tmp.modifiers.new("Decimate", "DECIMATE")
        dec.ratio = 1.0
    me = mesh_from_evaluated(tmp, name)
    if target_faces and len(me.polygons) > target_faces:
        dec.ratio = target_faces / len(me.polygons)
        bpy.data.meshes.remove(me)
        me = mesh_from_evaluated(tmp, name)
    for obj in objects:
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.objects.remove(tmp, do_unlink=True)
    obj = link(bpy.data.objects.new(name, me))
    for p in me.polygons:
        p.use_smooth = True
    return obj


def stage_body(ctx):
    meta, head = build_body_parts()
    body = unify("DragonBody", [meta, head], target_faces=24000)
    log("Körper: %d Flächen, Maße %s" % (len(body.data.polygons), tuple(round(d, 2) for d in body.dimensions)))
    ctx["body"] = body


# --- Flügelpunkte (linke Seite, Entwurfskoordinaten; ausgebreitet in der Ruhepose) -------------------
# S Schulter, E Ellbogen, W Handgelenk, T1..T4 Fingerspitzen (vorn -> hinten), B1/B2 Ansatz der Flughaut am Rumpf

WING = {
    "S": (0.30, -0.90, 1.92), "E": (1.30, -0.55, 2.50), "W": (2.45, -1.02, 2.86),
    "T1": (4.25, -0.62, 2.62), "T2": (4.00, 0.38, 2.30), "T3": (3.25, 1.12, 1.98), "T4": (2.15, 1.42, 1.72),
    "B1": (0.40, -0.20, 1.70), "B2": (0.42, 0.55, 1.55),
}
FINGERS = ["T1", "T2", "T3", "T4"]


def wing_pt(key, side=1.0):
    x, y, z = WING[key]
    return place((x * side, y, z))


def wing_bones(side, suf):
    bones = [("w_upper" + suf, wing_pt("S", side), wing_pt("E", side), "chest"),
             ("w_fore" + suf, wing_pt("E", side), wing_pt("W", side), "w_upper" + suf)]
    for i, key in enumerate(FINGERS):
        bones.append(("w_f%d%s" % (i + 1, suf), wing_pt("W", side), wing_pt(key, side), "w_fore" + suf))
    return bones


# --- Skelett-Tabelle (wird ab Phase 2 für die Zuordnung der Teile gebraucht) ---------------------------
# (Name, Ansatz, Ende, Eltern) – Entwurfskoordinaten laufen durch place(); Kopfknochen kommen aus head_pt.

def bone_table():
    P = place
    bones = [
        ("root", V((0, 0, 0)), V((0, 0.4, 0)), None),
        ("hips", P((0, 0.45, 1.42)), P((0, -0.05, 1.52)), "root"),
        ("spine", P((0, -0.05, 1.52)), P((0, -0.60, 1.58)), "hips"),
        ("chest", P((0, -0.60, 1.58)), P((0, -1.20, 1.78)), "spine"),
        ("neck1", P((0, -1.20, 1.78)), P((0, -1.46, 1.98)), "chest"),
        ("neck2", P((0, -1.46, 1.98)), P((0, -1.68, 2.20)), "neck1"),
        ("neck3", P((0, -1.68, 2.20)), P((0, -1.98, 2.50)), "neck2"),
        ("head", P((0, -1.98, 2.50)), head_pt(0.80, 0.0, 0.12), "neck3"),
        ("jaw", head_pt(0.0, 0.0, -0.02), head_pt(0.78, 0.0, -0.06), "head"),
    ]
    tail = [(0.45, 1.42), (1.00, 1.26), (1.55, 1.08), (2.10, 0.90), (2.65, 0.72), (3.20, 0.58), (3.70, 0.48), (4.05, 0.43)]
    parent = "hips"
    for i in range(len(tail) - 1):
        name = "tail%d" % (i + 1)
        bones.append((name, P((0, *tail[i])), P((0, *tail[i + 1])), parent))
        parent = name
    for side, suf in ((1.0, ".L"), (-1.0, ".R")):
        s = lambda x, y, z: P((x * side, y, z))
        bones += [
            ("f_upper" + suf, s(0.50, -1.00, 1.34), s(0.62, -1.06, 0.80), "chest"),
            ("f_lower" + suf, s(0.62, -1.06, 0.80), s(0.62, -1.18, 0.30), "f_upper" + suf),
            ("f_foot" + suf, s(0.62, -1.18, 0.30), s(0.64, -1.50, 0.06), "f_lower" + suf),
            ("h_thigh" + suf, s(0.50, 0.38, 1.24), s(0.68, 0.00, 0.80), "hips"),
            ("h_shin" + suf, s(0.68, 0.00, 0.80), s(0.68, 0.50, 0.40), "h_thigh" + suf),
            ("h_meta" + suf, s(0.68, 0.50, 0.40), s(0.68, 0.36, 0.13), "h_shin" + suf),
            ("h_toe" + suf, s(0.68, 0.36, 0.13), s(0.68, 0.00, 0.05), "h_meta" + suf),
        ]
        bones += wing_bones(side, suf)
    return bones


SPINE_CHAIN = ["head", "neck3", "neck2", "neck1", "chest", "spine", "hips"] + ["tail%d" % i for i in range(1, 8)]


def seg_distance(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (a + ab * t - p).length, t


def nearest_bone(p, names, table=None):
    table = table or {b[0]: b for b in bone_table()}
    return min(names, key=lambda n: seg_distance(p, table[n][1], table[n][2])[0])


# --- Phase 2: Details --------------------------------------------------------------------------------

# Spalten der Horn-Textur (u-Bereich): jedes Teil bekommt seinen Farbverlauf von Ansatz (v=0) bis Spitze (v=1)
PALETTE = {"horn": 0.0, "tooth": 0.25, "claw": 0.5, "wingbone": 0.75}


class Parts:
    """Sammelt starre Teile in einem Mesh: Röhren (Hörner, Krallen ...), UVs für die Horn-Textur, Knochengruppe je Teil."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.verify()
        self.deform = self.bm.verts.layers.deform.verify()
        self.groups = []

    def _assign(self, verts, weights):
        """weights: {Knochenname: Gewicht}"""
        for bone, w in weights.items():
            if bone not in self.groups:
                self.groups.append(bone)
        for v in verts:
            for bone, w in weights.items():
                v[self.deform][self.groups.index(bone)] = w

    def _face(self, verts, uvs):
        f = self.bm.faces.new(verts)
        for loop, uv in zip(f.loops, uvs):
            loop[self.uv].uv = uv
        return f

    def tube(self, pts, radii, bone, palette="horn", verts=8, flat=1.0, flat_axis=None, ridges=0.0, cap=True):
        pts = [V(p) for p in pts]
        n = len(pts)
        lengths = [0.0]
        for i in range(1, n):
            lengths.append(lengths[-1] + (pts[i] - pts[i - 1]).length)
        total = max(lengths[-1], 1e-6)
        tangents = []
        for i in range(n):
            t = pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]
            tangents.append(t.normalized())
        # Bezugsachse: flat_axis (dünne Richtung) oder parallel mitgeführt
        ref = V(flat_axis) if flat_axis is not None else (UP if abs(tangents[0].dot(UP)) < 0.9 else LEFT)
        u0 = PALETTE[palette]
        rings = []
        a_prev = None
        for i in range(n):
            t = tangents[i]
            if flat_axis is not None or a_prev is None:
                a = (ref - t * ref.dot(t))
            else:
                a = (a_prev - t * a_prev.dot(t))
            a = a.normalized() if a.length > 1e-6 else t.orthogonal().normalized()
            a_prev = a
            b = t.cross(a).normalized()
            r = radii[i]
            v_coord = lengths[i] / total
            if r < 1e-5:
                rings.append(("tip", self.bm.verts.new(pts[i]), v_coord))
                continue
            ridge = 1.0 + ridges * (0.5 + 0.5 * math.cos(v_coord * total / 0.06 * math.pi * 2.0)) if ridges else 1.0
            ring = []
            for k in range(verts + 1):
                ang = 2.0 * math.pi * k / verts
                pos = pts[i] + (b * math.cos(ang) + a * math.sin(ang) * flat) * r * ridge
                ring.append(self.bm.verts.new(pos))
            rings.append(("ring", ring, v_coord))
        made = []
        uw = 0.25 - 0.04
        for (k0, r0, v0), (k1, r1, v1) in zip(rings, rings[1:]):
            for k in range(verts):
                ua, ub = u0 + 0.02 + uw * k / verts, u0 + 0.02 + uw * (k + 1) / verts
                if k0 == "ring" and k1 == "ring":
                    made.append(self._face((r0[k], r0[k + 1], r1[k + 1], r1[k]), [(ua, v0), (ub, v0), (ub, v1), (ua, v1)]))
                elif k0 == "ring":
                    made.append(self._face((r0[k], r0[k + 1], r1), [(ua, v0), (ub, v0), ((ua + ub) / 2, v1)]))
                elif k1 == "ring":
                    made.append(self._face((r1[k + 1], r1[k], r0), [(ub, v1), (ua, v1), ((ua + ub) / 2, v0)]))
        if cap and rings[0][0] == "ring":
            ring = rings[0][1][:verts]
            made.append(self._face(list(reversed(ring)), [(u0 + 0.12, 0.0)] * verts))
        all_verts = []
        for kind, data, _ in rings:
            all_verts += data if kind == "ring" else [data]
        self._assign(all_verts, bone if isinstance(bone, dict) else {bone: 1.0})
        return all_verts

    def leaf(self, center, outline, thickness, normal, bone, palette="horn"):
        """Flaches Blatt (Schwanzklinge): Umriss in Weltkoordinaten, in der Mitte dick, zum Rand dünn."""
        normal = V(normal).normalized()
        c = V(center)
        top = self.bm.verts.new(c + normal * thickness)
        bot = self.bm.verts.new(c - normal * thickness)
        rim = [self.bm.verts.new(V(p)) for p in outline]
        u0 = PALETTE[palette]
        n = len(rim)
        span = max((V(p) - c).length for p in outline)
        uvp = lambda p: (u0 + 0.12 + 0.08 * ((V(p) - c).length / span) * 0.0, 0.25 + 0.7 * (V(p) - c).length / span)
        for i in range(n):
            a, b = rim[i], rim[(i + 1) % n]
            self._face((top, a, b), [(u0 + 0.12, 0.2), uvp(a.co), uvp(b.co)])
            self._face((bot, b, a), [(u0 + 0.12, 0.2), uvp(b.co), uvp(a.co)])
        self._assign([top, bot] + rim, {bone: 1.0})

    def finish(self, material=None, smooth=True):
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        obj = link(bpy.data.objects.new(self.name, me))
        for g in self.groups:
            obj.vertex_groups.new(name=g)
        for p in me.polygons:
            p.use_smooth = smooth
        if material:
            me.materials.append(material)
        return obj


def station_at(stations, s):
    for (s0, *a), (s1, *b) in zip(stations, stations[1:]):
        if s0 <= s <= s1:
            f = (s - s0) / (s1 - s0)
            return [lerp(x, y, f) for x, y in zip(a, b)]
    return list(stations[0][1:] if s < stations[0][0] else stations[-1][1:])


def body_bvh(obj):
    me = obj.data
    return BVHTree.FromPolygons([v.co.copy() for v in me.vertices], [tuple(p.vertices) for p in me.polygons])


def build_horns(parts):
    hs = HEAD_SCALE
    for side in (1.0, -1.0):
        hp = lambda s, x, z: head_pt(s, x * side, z)
        # Haupthörner: vom Schädeldach weit nach hinten, am Ende nach oben geschwungen
        parts.tube([hp(0.04, 0.15, 0.19), hp(-0.18, 0.23, 0.25), hp(-0.44, 0.31, 0.29), hp(-0.70, 0.36, 0.34),
                    hp(-0.90, 0.37, 0.44), hp(-1.00, 0.35, 0.56)],
                   [0.078 * hs, 0.07 * hs, 0.056 * hs, 0.038 * hs, 0.018 * hs, 0.0], "head", verts=10, ridges=0.06)
        # zweites, kürzeres Hornpaar seitlich darunter
        parts.tube([hp(0.0, 0.21, 0.05), hp(-0.18, 0.32, 0.06), hp(-0.36, 0.40, 0.12), hp(-0.50, 0.43, 0.22)],
                   [0.05 * hs, 0.04 * hs, 0.024 * hs, 0.0], "head", verts=8, ridges=0.05)
        # Wangenstacheln (Kragen) am Kiefergelenk
        for base, off in (((0.10, 0.25, 0.00), (-0.26, 0.10, -0.02)), ((0.03, 0.245, -0.07), (-0.24, 0.12, -0.08)),
                          ((-0.03, 0.21, -0.12), (-0.20, 0.10, -0.12))):
            b = V(base)
            parts.tube([hp(*b), hp(*(b + V(off) * 0.5)), hp(*(b + V(off)))], [0.034 * hs, 0.02 * hs, 0.0], "head", verts=7)
        # kleine Brauenstacheln
        for base, tip in (((0.22, 0.165, 0.20), (0.10, 0.22, 0.31)), ((0.31, 0.15, 0.18), (0.22, 0.20, 0.27))):
            parts.tube([hp(*base), hp(*tip)], [0.022 * hs, 0.0], "head", verts=6)
    # Nasenhörner
    parts.tube([head_pt(0.69, 0, 0.09), head_pt(0.75, 0, 0.19), head_pt(0.73, 0, 0.27)], [0.036 * hs, 0.022 * hs, 0.0], "head", verts=8)
    parts.tube([head_pt(0.58, 0, 0.12), head_pt(0.60, 0, 0.19)], [0.024 * hs, 0.0], "head", verts=6)


def build_teeth(parts):
    hs = HEAD_SCALE
    for side in (1.0, -1.0):
        s = 0.24
        while s <= 0.79:
            w, top, bot = station_at(UPPER_HEAD, s)
            fang = abs(s - 0.66) < 0.03
            length = (0.085 if fang else 0.04 + 0.01 * rng.random())
            x = w * 0.86 * side
            base = head_pt(s, x, -bot * 0.3)
            tip = head_pt(s + 0.01, x * 0.97, -bot * 0.3 - length)
            parts.tube([base, tip], [(0.02 if fang else 0.012) * hs, 0.0], "head", palette="tooth", verts=6)
            s += 0.06 if not fang else 0.07
        s = 0.28
        while s <= 0.77:
            w, top, bot = station_at(JAW, s)
            fang = abs(s - 0.58) < 0.03
            length = (0.07 if fang else 0.035 + 0.01 * rng.random())
            x = w * 0.82 * side
            parts.tube([head_pt(s, x, 0.0), head_pt(s + 0.01, x * 0.95, length)], [(0.018 if fang else 0.011) * hs, 0.0], "jaw",
                       palette="tooth", verts=6)
            s += 0.065


def build_dorsal_spikes(parts, bvh):
    table = {b[0]: b for b in bone_table()}
    pts = [place((0.0, y, z)) for y, z, _ in SPINE]
    lengths = [0.0]
    for i in range(1, len(pts)):
        lengths.append(lengths[-1] + (pts[i] - pts[i - 1]).length)
    total = lengths[-1]
    d = 0.42
    while d < total - 0.06:
        t = d / total
        c = polyline_sample(pts, t)
        tangent = (polyline_sample(pts, min(1.0, t + 0.01)) - polyline_sample(pts, max(0.0, t - 0.01))).normalized()
        dorsal = (UP - tangent * UP.dot(tangent)).normalized()
        hit, normal, _, _ = bvh.ray_cast(c + dorsal * 2.0, -dorsal)
        if hit is None:
            d += 0.2
            continue
        # Höhe: am Hals mittel, über den Schultern am größten, zum Schwanz hin klein
        h = 0.12 + 0.24 * math.exp(-((t - 0.24) / 0.16) ** 2) + 0.10 * smoothstep(0.55, 0.0, t) - 0.05 * smoothstep(0.6, 1.0, t)
        h = max(0.07, h)
        base = hit - dorsal * 0.03
        bone = nearest_bone(base, [b for b in SPINE_CHAIN if b != "head"], table)
        parts.tube([base, base + dorsal * h * 0.5 + tangent * h * 0.18, base + dorsal * h + tangent * h * 0.55],
                   [0.36 * h, 0.2 * h, 0.0], bone, verts=8, flat=0.38, flat_axis=LEFT)
        d += 0.16 + 0.12 * h


def build_tail_blade(parts):
    tip = place((0.0, 4.05, 0.43))
    z = tip.z + 0.01
    # Pfeilspitze am Schwanzende: zwei breite, nach hinten gezogene Flügel und eine lange Mittelspitze
    outline = [(0.0, 3.62), (0.16, 3.80), (0.40, 4.06), (0.36, 4.20), (0.12, 4.24), (0.0, 4.62), (-0.12, 4.24), (-0.36, 4.20),
               (-0.40, 4.06), (-0.16, 3.80)]
    parts.leaf(V((0.0, 4.05, z)), [V((x, y, z)) for x, y in outline], 0.05, UP, "tail7")


def build_claws(parts):
    table = {b[0]: b for b in bone_table()}
    for side, suf in ((1.0, ".L"), (-1.0, ".R")):
        for leg, toes, bone, size in ((FRONT_LEG, FRONT_TOES, "f_foot", 1.0), (HIND_LEG, HIND_TOES, "h_toe", 1.15)):
            ball = V(leg[-1][0])
            for base_off, tip_off in toes:
                a = ball + V(base_off)
                b = ball + V(tip_off)
                d = (b - a)
                d.z = 0.0
                d.normalize()
                tip = place(V((b.x * side, b.y, b.z)))
                d = V((d.x * side, d.y, 0.0))
                start = tip + V((0, 0, 0.03))
                parts.tube([start, start + d * 0.07 * size + UP * 0.015, start + d * 0.13 * size - UP * 0.02,
                            start + d * 0.155 * size - UP * 0.075],
                           [0.04 * size, 0.031 * size, 0.016 * size, 0.0], bone + suf, palette="claw", verts=8, flat=0.75,
                           flat_axis=V((d.y, -d.x, 0.0)))
    _ = table


def build_eyes(bvh, mat_eye, mat_pupil):
    parts_eye = Parts("DragonEyes")
    parts_pupil = Parts("DragonPupils")
    hs = HEAD_SCALE
    for side in (1.0, -1.0):
        target = head_pt(0.30, 0.0, 0.125)
        origin = head_pt(0.36, 0.55 * side, 0.135)
        hit, normal, _, _ = bvh.ray_cast(origin, (target - origin).normalized())
        if hit is None:
            log("Auge nicht gefunden")
            continue
        normal = normal.normalized()
        fwd = (HEAD_F - normal * HEAD_F.dot(normal)).normalized()
        upv = normal.cross(fwd).normalized() * side
        if upv.dot(UP) < 0:
            upv = -upv
        center = hit - normal * 0.012
        bm = parts_eye.bm
        res = bmesh.ops.create_uvsphere(bm, u_segments=14, v_segments=10, radius=1.0)
        for v in res["verts"]:
            lc = v.co.copy()
            v.co = center + fwd * lc.x * 0.052 * hs / 1.4 + upv * lc.y * 0.034 * hs / 1.4 + normal * lc.z * 0.03
        parts_eye._assign(res["verts"], {"head": 1.0})
        # senkrechte Schlitzpupille
        pc = center + normal * 0.031 + fwd * 0.004
        res = bmesh.ops.create_cube(parts_pupil.bm, size=1.0)
        for v in res["verts"]:
            lc = v.co.copy()
            v.co = pc + fwd * lc.x * 0.012 + upv * lc.y * 0.058 + normal * lc.z * 0.012
        parts_pupil._assign(res["verts"], {"head": 1.0})
    return parts_eye.finish(mat_eye), parts_pupil.finish(mat_pupil, smooth=False)


def stage_details(ctx):
    bvh = body_bvh(ctx["body"])
    jaw = unify("DragonJaw", [loft("JawLoft", JAW, n_top=4.0, n_bottom=2.4)], voxel=0.012, smooth_iter=3, target_faces=4000)
    jaw.vertex_groups.new(name="jaw").add(list(range(len(jaw.data.vertices))), 1.0, "REPLACE")
    ctx["jaw"] = jaw
    parts = Parts("DragonHorns")
    build_horns(parts)
    build_teeth(parts)
    build_dorsal_spikes(parts, bvh)
    build_tail_blade(parts)
    build_claws(parts)
    ctx["horns"] = parts.finish(clay("HornClay", (0.06, 0.045, 0.045), 0.4))
    eye_mat = clay("EyeGlow", (1.0, 0.6, 0.1))
    bsdf = eye_mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Emission Color"].default_value = (1.0, 0.55, 0.08, 1.0)
    bsdf.inputs["Emission Strength"].default_value = 6.0
    ctx["eyes"], ctx["pupils"] = build_eyes(bvh, eye_mat, clay("Pupil", (0.01, 0.005, 0.0), 0.3))
    log("Details: Hörner/Zähne/Stacheln/Krallen %d Flächen, Kiefer %d" % (len(ctx["horns"].data.polygons), len(jaw.data.polygons)))


# --- Phase 3: Flügel ---------------------------------------------------------------------------------

def build_wing_bones(parts, side, suf):
    S, E, W = wing_pt("S", side), wing_pt("E", side), wing_pt("W", side)
    parts.tube([S, S.lerp(E, 0.5), E], [0.085, 0.07, 0.062], "w_upper" + suf, palette="wingbone", verts=10)
    parts.tube([E, E.lerp(W, 0.5), W], [0.062, 0.05, 0.05], "w_fore" + suf, palette="wingbone", verts=10)
    for p, r, bone in ((E, 0.085, "w_fore" + suf), (W, 0.072, "w_fore" + suf)):   # Gelenkknubbel
        res = bmesh.ops.create_uvsphere(parts.bm, u_segments=10, v_segments=7, radius=r)
        for v in res["verts"]:
            v.co += p
        parts._assign(res["verts"], {bone: 1.0})
    for i, key in enumerate(FINGERS):
        T = wing_pt(key, side)
        mid = W.lerp(T, 0.5) + UP * 0.04 * (1.0 - i * 0.2)        # Finger leicht nach oben gewölbt
        parts.tube([W, W.lerp(T, 0.25), mid, W.lerp(T, 0.8), T], [0.045, 0.036, 0.028, 0.018, 0.0], "w_f%d%s" % (i + 1, suf),
                   palette="wingbone", verts=8)
    # Daumenkralle am Handgelenk, nach vorn oben
    thumb_dir = V((0.04 * side, -0.85, 0.5)).normalized()
    parts.tube([W, W + thumb_dir * 0.12, W + thumb_dir * 0.2 + V((0.0, -0.02, -0.04))], [0.035, 0.022, 0.0], "w_fore" + suf,
               palette="claw", verts=7)


class WingSkin:
    """Flughaut als Gitter je Feld; Gewichte werden pro Punkt aus den angrenzenden Knochen gemischt."""

    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.verify()
        self.deform = self.bm.verts.layers.deform.verify()
        self.groups = []
        self.strip = 0

    def gi(self, bone):
        if bone not in self.groups:
            self.groups.append(bone)
        return self.groups.index(bone)

    def grid(self, na, nt, point, weights):
        """point(a, t) -> Vector, weights(a, t) -> {Knochen: Gewicht}; a quer, t vom Ansatz zur Hinterkante."""
        col = self.strip
        self.strip += 1
        rows = []
        for j in range(nt + 1):
            t = j / nt
            row = []
            for i in range(na + 1):
                a = i / na
                v = self.bm.verts.new(point(a, t))
                ws = weights(a, t)
                total = sum(ws.values())
                for bone, w in ws.items():
                    if w > 1e-4:
                        v[self.deform][self.gi(bone)] = w / total
                row.append(v)
            rows.append(row)
        uvf = lambda a, t: (col * 0.2 + 0.01 + a * 0.18, 0.01 + t * 0.98)
        made = []
        for j in range(nt):
            for i in range(na):
                quad = (rows[j][i], rows[j][i + 1], rows[j + 1][i + 1], rows[j + 1][i])
                f = self.bm.faces.new(quad)
                for loop, (ai, tj) in zip(f.loops, ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))):
                    loop[self.uv].uv = uvf(ai / na, tj / nt)
                made.append(f)
        verts = [v for row in rows for v in row]
        bmesh.ops.remove_doubles(self.bm, verts=verts, dist=1e-5)
        return made

    def finish(self, name, material):
        bmesh.ops.dissolve_degenerate(self.bm, edges=self.bm.edges, dist=1e-6)
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        obj = link(bpy.data.objects.new(name, me))
        for g in self.groups:
            obj.vertex_groups.new(name=g)
        for p in me.polygons:
            p.use_smooth = True
        me.materials.append(material)
        return obj


def body_bone_at(p, table):
    return nearest_bone(p, ["chest", "spine", "hips"], table)


def build_wing_skin(skin, side, suf, table):
    W = wing_pt("W", side)
    tips = [wing_pt(k, side) for k in FINGERS]
    cup = lambda a, t, width: -UP * 0.10 * width * math.sin(math.pi * a) * smoothstep(0.0, 1.0, t)
    # Felder zwischen den Fingern: Hinterkante zwischen den Spitzen zum Handgelenk hin eingebuchtet
    for i in range(3):
        Ti, Tj = tips[i], tips[i + 1]
        fi, fj = "w_f%d%s" % (i + 1, suf), "w_f%d%s" % (i + 2, suf)
        width = (Ti - Tj).length
        mid_i = W.lerp(Ti, 0.5) + UP * 0.04 * (1.0 - i * 0.2)
        mid_j = W.lerp(Tj, 0.5) + UP * 0.04 * (1.0 - (i + 1) * 0.2)

        def spar(T, mid, t):
            # gleiche Wölbung wie der Fingerknochen (quadratische Kurve durch die Mitte)
            return W * ((1 - t) * (1 - 2 * t)) + mid * (4 * t * (1 - t)) + T * (t * (2 * t - 1))

        def point(a, t, Ti=Ti, Tj=Tj, mid_i=mid_i, mid_j=mid_j, width=width):
            p = spar(Ti, mid_i, t).lerp(spar(Tj, mid_j, t), a)
            p += (W - p).normalized() * 0.30 * width * math.sin(math.pi * a) * t * t if (W - p).length > 1e-6 else V()
            return p + cup(a, t, width)

        skin.grid(8, 14, point, lambda a, t, fi=fi, fj=fj: {fi: 1.0 - a, fj: a})
    # Hauptfeld: von Finger 4 über Unterarm, Oberarm und Flanke bis zur Hüfte
    root_pts = [W, wing_pt("E", side), wing_pt("S", side), wing_pt("B1", side), wing_pt("B2", side)]
    seg_len = [(root_pts[k + 1] - root_pts[k]).length for k in range(4)]
    total = sum(seg_len)
    marks = [sum(seg_len[:k]) / total for k in range(5)]
    T4, B2 = tips[3], root_pts[-1]
    rmid = polyline_sample(root_pts, 0.45)
    ctrl = T4.lerp(B2, 0.5).lerp(rmid, 0.32)
    width = (T4 - B2).length

    def trailing(a):
        return T4 * (1 - a) ** 2 + ctrl * (2 * a * (1 - a)) + B2 * a * a

    def root_bone(a):
        if a <= marks[1]:
            return "w_fore" + suf
        if a <= marks[2]:
            return "w_upper" + suf
        return body_bone_at(polyline_sample(root_pts, a), table)

    def point(a, t):
        return polyline_sample(root_pts, a).lerp(trailing(a), t) - UP * 0.08 * width * math.sin(math.pi * a) * math.sin(math.pi * t)

    def weights(a, t):
        ws = {}
        rb = root_bone(a)
        ws[rb] = ws.get(rb, 0.0) + (1.0 - t) + t * a
        f4 = "w_f4" + suf
        ws[f4] = ws.get(f4, 0.0) + t * (1.0 - a)
        return ws

    skin.grid(22, 12, point, weights)
    # Vorflughaut zwischen Schulter, Ellbogen und Handgelenk
    S, E = wing_pt("S", side), wing_pt("E", side)
    front_root = [S, E, W]
    e_mark = (E - S).length / ((E - S).length + (W - E).length)

    def fpoint(a, t):
        r = polyline_sample(front_root, a)
        chord = S.lerp(W, a)
        return r.lerp(chord.lerp(r, 0.28 * math.sin(math.pi * a)), t)

    skin.grid(10, 4, fpoint, lambda a, t: {"w_upper" + suf: 1.0 - smoothstep(e_mark - 0.15, e_mark + 0.15, a),
                                           "w_fore" + suf: smoothstep(e_mark - 0.15, e_mark + 0.15, a)})


def stage_wings(ctx):
    table = {b[0]: b for b in bone_table()}
    parts = Parts("DragonWingBones")
    skin = WingSkin()
    for side, suf in ((1.0, ".L"), (-1.0, ".R")):
        build_wing_bones(parts, side, suf)
        build_wing_skin(skin, side, suf, table)
    ctx["wing_bones"] = parts.finish(ctx["horns"].data.materials[0] if ctx["horns"].data.materials else None)
    mat = clay("MembraneClay", (0.32, 0.07, 0.05), 0.7)
    mat.use_backface_culling = False
    ctx["wings"] = skin.finish("DragonWings", mat)
    log("Flügel: Haut %d Flächen, Knochen %d Flächen" % (len(ctx["wings"].data.polygons), len(ctx["wing_bones"].data.polygons)))


# --- Phase 4: Skelett und Gewichtung -------------------------------------------------------------------

RIGID_PARTS = ["jaw", "horns", "eyes", "pupils", "wing_bones", "wings"]


def build_armature():
    data = bpy.data.armatures.new("DragonRig")
    arm = link(bpy.data.objects.new("DragonRig", data))
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for name, head, tail, parent in bone_table():
        eb = data.edit_bones.new(name)
        eb.head, eb.tail = head, tail
        d = (tail - head).normalized()
        eb.align_roll(FWD if abs(d.dot(UP)) > 0.85 else UP)
        if parent:
            eb.parent = data.edit_bones[parent]
            eb.use_connect = (data.edit_bones[parent].tail - eb.head).length < 1e-4 and not name.startswith("w_f")
    bpy.ops.object.mode_set(mode="OBJECT")
    data.bones["root"].use_deform = False
    return arm


def bind(obj, arm):
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    obj.parent = arm


def stage_rig(ctx):
    arm = build_armature()
    ctx["arm"] = arm
    body = ctx["body"]
    # Rumpf: automatische Gewichte (Wärmeverteilung); Flügelknochen dabei ausgeschlossen, sie liegen außerhalb des Körpers
    # Kieferknochen ebenfalls ausgeschlossen: der Unterkiefer ist ein eigenes Teil, der Oberkopf soll nicht mitklappen
    wing_bones = [b for b in arm.data.bones if b.name.startswith("w_") or b.name == "jaw"]
    for b in wing_bones:
        b.use_deform = False
    for o in bpy.context.scene.objects:
        o.select_set(False)
    body.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    for b in wing_bones:
        b.use_deform = True
    # ungewichtete Punkte (falls die Wärmeverteilung scheitert) an den nächsten Knochen hängen
    table = {b[0]: b for b in bone_table()}
    names = [b[0] for b in bone_table() if b[0] != "root" and not b[0].startswith("w_")]
    groups = {g.index: g for g in body.vertex_groups}
    missing = 0
    for v in body.data.vertices:
        if sum(g.weight for g in v.groups if g.group in groups) < 1e-3:
            name = nearest_bone(v.co, names, table)
            vg = body.vertex_groups.get(name) or body.vertex_groups.new(name=name)
            vg.add([v.index], 1.0, "REPLACE")
            missing += 1
    for key in RIGID_PARTS:
        bind(ctx[key], arm)
    log("Skelett: %d Knochen; Rumpf ohne Wärmegewicht: %d Punkte" % (len(arm.data.bones), missing))


class Poser:
    """Posen im Armature-Raum (vorn = -Y, oben = +Z, links = +X); Ruhepose = ausgebreitete Flügel."""

    def __init__(self, arm):
        self.arm = arm
        self.pose = arm.pose
        for pb in self.pose.bones:
            pb.rotation_mode = "QUATERNION"

    def reset(self):
        for pb in self.pose.bones:
            pb.matrix_basis = Matrix.Identity(4)
        bpy.context.view_layer.update()

    def _set(self, pb, mat):
        pb.matrix = mat
        bpy.context.view_layer.update()

    def turn(self, bone, axis, degrees):
        """Dreht einen Knochen samt Kindern um seinen Ansatz. Achse LEFT: + = Spitze nach unten; UP: + = nach links."""
        if abs(degrees) < 1e-4:
            return
        pb = self.pose.bones[bone]
        head = pb.matrix.translation.copy()
        rot = Matrix.Rotation(math.radians(degrees), 4, V(axis))
        self._set(pb, Matrix.Translation(head) @ rot @ Matrix.Translation(-head) @ pb.matrix)

    def aim(self, bone, direction, amount=1.0):
        pb = self.pose.bones[bone]
        current = pb.matrix.col[1].xyz.normalized()
        target = current.slerp(V(direction).normalized(), amount)
        rot = current.rotation_difference(target).to_matrix().to_4x4()
        head = pb.matrix.translation.copy()
        self._set(pb, Matrix.Translation(head) @ rot @ Matrix.Translation(-head) @ pb.matrix)

    def move(self, bone, offset):
        pb = self.pose.bones[bone]
        self._set(pb, Matrix.Translation(V(offset)) @ pb.matrix)

    def key(self, frame):
        for pb in self.pose.bones:
            pb.keyframe_insert("rotation_quaternion", frame=frame)
            pb.keyframe_insert("location", frame=frame)


def mirror_dir(d, side):
    return V((d[0] * side, d[1], d[2]))


def fold_wings(p, amount=1.0, spread=0.0):
    """Flügel an den Körper legen (amount 1 = ganz gefaltet); spread hebt sie leicht an (Drohgebärde)."""
    for side, suf in ((1.0, ".L"), (-1.0, ".R")):
        p.aim("w_upper" + suf, mirror_dir((0.42 + 0.3 * spread, 0.50, 0.75), side), amount)
        p.aim("w_fore" + suf, mirror_dir((0.16, -0.86, -0.42 + 0.3 * spread), side), amount)
        for i, d in enumerate(((0.20, 0.88, -0.40), (0.24, 0.86, -0.46), (0.27, 0.82, -0.52), (0.30, 0.76, -0.58))):
            p.aim("w_f%d%s" % (i + 1, suf), mirror_dir(d, side), amount)


def test_pose(p):
    p.reset()
    fold_wings(p)
    p.turn("neck2", UP, 12)
    p.turn("neck3", UP, 10)
    p.turn("head", LEFT, -10)
    p.turn("jaw", LEFT, 28)
    p.turn("f_upper.L", LEFT, -35)
    p.turn("f_lower.L", LEFT, 55)
    p.turn("tail2", UP, 15)
    p.turn("tail4", UP, 20)
    p.turn("tail6", UP, 25)


# --- Phase 5: Texturen -------------------------------------------------------------------------------

TEX_DIR = os.path.join(os.environ.get("TEMP", PROJECT), "dragon_textures")
COL = {   # sRGB
    "back": "#4e0d0a", "flank": "#8c1d12", "belly": "#a0521f", "mouth": "#3c0b0b", "tongue": "#80242a",
    "foot": "#2e0b09", "head": "#7a1810",
}


def hex_lin(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return V([x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c])


def head_local(p):
    """Blender-Raum -> Kopfraum (s, x, z) vor der Skalierung (Umkehrung von head_pt)."""
    d = V((p.x, p.y, p.z + BODY_DROP)) - HEAD_O
    return d.dot(HEAD_F) / HEAD_SCALE, d.x / HEAD_SCALE, d.dot(HEAD_U) / HEAD_SCALE


def join(objects, name):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    objects[0].name = name
    objects[0].data.name = name
    return objects[0]


def paint_body(body, table):
    """Farbe und Musterdaten je Punkt: paint = Grundfarbe, data = (u entlang der Wirbelsäule, Bauch, glatt, Glut)."""
    from mathutils.geometry import intersect_point_line
    me = body.data
    spine = [head_pt(0.84, 0, 0.0), table["head"][1], table["neck3"][1], table["neck2"][1], table["neck1"][1],
             table["chest"][1], table["spine"][1], table["hips"][1]] + [table["tail%d" % i][2] for i in range(1, 8)]
    cum = [0.0]
    for i in range(1, len(spine)):
        cum.append(cum[-1] + (spine[i] - spine[i - 1]).length)
    u_chest = cum[5]
    u_neck = cum[3]
    group_names = {g.index: g.name for g in body.vertex_groups}
    paint = me.color_attributes.new("paint", "FLOAT_COLOR", "POINT")
    data = me.color_attributes.new("data", "FLOAT_COLOR", "POINT")
    data2 = me.color_attributes.new("data2", "FLOAT_COLOR", "POINT")
    c = {k: hex_lin(v) for k, v in COL.items()}
    for v in me.vertices:
        p, n = v.co, v.normal
        best = (1e9, 0.0, V((0, 1, 0)))
        for i in range(len(spine) - 1):
            q, f = intersect_point_line(p, spine[i], spine[i + 1])
            f = max(0.0, min(1.0, f))
            q = spine[i].lerp(spine[i + 1], f)
            dist = (p - q).length
            if dist < best[0]:
                best = (dist, cum[i] + f * (cum[i + 1] - cum[i]), (spine[i + 1] - spine[i]).normalized())
        _, u, tangent = best
        up_local = (UP - tangent * UP.dot(tangent))
        up_local = up_local.normalized() if up_local.length > 1e-6 else UP
        facing = n.dot(up_local)
        top = max(v.groups, key=lambda g: g.weight).group if len(v.groups) else -1
        region = group_names.get(top, "")
        leg = region.startswith(("f_", "h_"))
        belly = 0.0 if leg else smoothstep(0.30, 0.62, -facing)
        col = c["flank"].lerp(c["back"], smoothstep(0.05, 0.75, facing))
        smooth = 0.0
        glow = 0.0
        scale_mult = 1.0
        if leg:
            col = c["flank"].lerp(c["back"], 0.35).lerp(c["foot"], smoothstep(0.55, 0.08, p.z))
            scale_mult = 1.35 + 0.6 * smoothstep(0.5, 0.1, p.z)
        if region in ("head", "jaw", "neck3"):
            s, x, z = head_local(p)
            hu = n.dot(HEAD_U)
            scale_mult = 1.5 if region != "neck3" else 1.2
            if region == "head":
                col = c["head"].lerp(c["back"], smoothstep(0.2, 0.9, hu) * 0.6)
                belly = smoothstep(0.35, 0.7, -hu) if s < -0.02 else 0.0     # nur die Kehle hinter dem Kiefer
                if z < 0.02 and s > 0.0 and hu < -0.25:                     # Gaumen
                    col, smooth, glow, belly = c["mouth"], 1.0, 0.1 * smoothstep(0.45, 0.0, s), 0.0
            elif region == "jaw":
                if hu > 0.25 and z > -0.03:                                  # Mundboden und Zunge
                    col = c["tongue"] if abs(x) < 0.07 and s > 0.1 else c["mouth"]
                    smooth, glow, belly = 1.0, 0.08 * smoothstep(0.45, 0.0, s), 0.0
                else:
                    col = c["head"]
                    belly = smoothstep(0.2, 0.6, -hu)
        col = col.lerp(c["belly"], belly)
        # Glut in den Fugen von Kehle und Brust
        glow = max(glow, 0.65 * belly * math.exp(-((u - (u_neck + u_chest) * 0.5) / 1.1) ** 2))
        paint.data[v.index].color = (col.x, col.y, col.z, 1.0)
        data.data[v.index].color = (u, belly, smooth, glow)
        data2.data[v.index].color = (scale_mult, 0.0, 0.0, 1.0)


def node(nt, kind, loc, **inputs):
    n = nt.nodes.new(kind)
    n.location = loc
    for k, val in inputs.items():
        n.inputs[k].default_value = val
    return n


def math_node(nt, op, loc, a=None, b=None, clamp=False):
    n = nt.nodes.new("ShaderNodeMath")
    n.operation = op
    n.location = loc
    n.use_clamp = clamp
    for i, val in enumerate((a, b)):
        if val is None:
            continue
        if isinstance(val, (int, float)):
            n.inputs[i].default_value = val
        else:
            nt.links.new(val, n.inputs[i])
    return n.outputs[0]


def smooth_range(nt, value, lo, hi, loc):
    n = nt.nodes.new("ShaderNodeMapRange")
    n.interpolation_type = "SMOOTHSTEP"
    n.location = loc
    n.inputs["From Min"].default_value = lo
    n.inputs["From Max"].default_value = hi
    nt.links.new(value, n.inputs["Value"])
    return n.outputs["Result"]


def mix_col(nt, a, b, fac, loc, blend="MIX"):
    n = nt.nodes.new("ShaderNodeMix")
    n.data_type = "RGBA"
    n.blend_type = blend
    n.location = loc
    for sock, val in ((n.inputs[0], fac), (n.inputs[6], a), (n.inputs[7], b)):
        if isinstance(val, (int, float)):
            sock.default_value = val
        elif isinstance(val, tuple):
            sock.default_value = val
        else:
            nt.links.new(val, sock)
    return n.outputs[2]


def bake_material_body():
    """Prozedurales Material nur zum Backen: Schuppen (Voronoi), Bauchplatten (Bänder entlang u), Glut, Relief."""
    mat = bpy.data.materials.new("DragonBodyBake")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    attr = lambda name, y: node(nt, "ShaderNodeAttribute", (-1600, y))
    a_paint = attr("paint", 400)
    a_paint.attribute_name = "paint"
    a_data = attr("data", 0)
    a_data.attribute_name = "data"
    a_data2 = attr("data2", -300)
    a_data2.attribute_name = "data2"
    sep = node(nt, "ShaderNodeSeparateColor", (-1400, 0))
    nt.links.new(a_data.outputs["Color"], sep.inputs[0])
    sep2 = node(nt, "ShaderNodeSeparateColor", (-1400, -300))
    nt.links.new(a_data2.outputs["Color"], sep2.inputs[0])
    u, belly, smooth, glow = sep.outputs[0], sep.outputs[1], sep.outputs[2], a_data.outputs["Alpha"]
    coord = node(nt, "ShaderNodeTexCoord", (-1600, -600))
    scale = math_node(nt, "MULTIPLY", (-1200, -400), sep2.outputs[0], 12.5)
    vor = node(nt, "ShaderNodeTexVoronoi", (-1000, -500))
    vor.voronoi_dimensions = "3D"
    vor.inputs["Randomness"].default_value = 0.85
    nt.links.new(coord.outputs["Object"], vor.inputs["Vector"])
    nt.links.new(scale, vor.inputs["Scale"])
    edge = node(nt, "ShaderNodeTexVoronoi", (-1000, -800))
    edge.voronoi_dimensions = "3D"
    edge.feature = "DISTANCE_TO_EDGE"
    edge.inputs["Randomness"].default_value = 0.85
    nt.links.new(coord.outputs["Object"], edge.inputs["Vector"])
    nt.links.new(scale, edge.inputs["Scale"])
    crevice = smooth_range(nt, edge.outputs["Distance"], 0.0, 0.065, (-800, -800))
    dome = math_node(nt, "SUBTRACT", (-800, -500), 1.0, math_node(nt, "MULTIPLY", (-900, -450), vor.outputs["Distance"], 1.1), clamp=True)
    scale_h = math_node(nt, "MULTIPLY", (-600, -600), crevice, math_node(nt, "ADD", (-700, -500), 0.35, dome))
    cellvar = node(nt, "ShaderNodeSeparateColor", (-800, -300))
    nt.links.new(vor.outputs["Color"], cellvar.inputs[0])
    var = math_node(nt, "ADD", (-600, -300), 0.86, math_node(nt, "MULTIPLY", (-700, -300), cellvar.outputs[0], 0.26))
    shade = math_node(nt, "MULTIPLY", (-550, -150), math_node(nt, "ADD", (-600, -150), 0.3, math_node(nt, "MULTIPLY", (-700, -150), crevice, 0.7)), math_node(nt, "ADD", (-650, -50), 0.7, math_node(nt, "MULTIPLY", (-750, -50), dome, 0.4)))
    tmp = math_node(nt, "MULTIPLY", (-500, -200), var, shade)
    scales_col = mix_col(nt, (0, 0, 0, 1), a_paint.outputs["Color"], tmp, (-300, 200))
    # Bauchplatten: Bänder quer zur Wirbelsäule, alle ~14 cm
    band = math_node(nt, "FRACT", (-1000, 200), math_node(nt, "MULTIPLY", (-1100, 200), u, 7.0))
    e0 = smooth_range(nt, band, 0.0, 0.08, (-800, 300))
    e1 = smooth_range(nt, band, 1.0, 0.9, (-800, 150))
    plate = math_node(nt, "MULTIPLY", (-600, 250), e0, e1)
    plate_shade = math_node(nt, "ADD", (-450, 350), 0.42, math_node(nt, "MULTIPLY", (-550, 350), plate,
                                                                      math_node(nt, "ADD", (-650, 450), 0.45, math_node(nt, "MULTIPLY", (-750, 450), band, 0.25))))
    belly_col = mix_col(nt, (0, 0, 0, 1), a_paint.outputs["Color"], plate_shade, (-250, 400))
    col = mix_col(nt, scales_col, belly_col, belly, (-50, 300))
    col = mix_col(nt, col, a_paint.outputs["Color"], smooth, (100, 300))
    nt.links.new(col, bsdf.inputs["Base Color"])
    # Relief
    h_belly = math_node(nt, "MULTIPLY", (-300, -100), plate, 0.8)
    height = mix_col(nt, scale_h, h_belly, belly, (-150, -150))
    height = mix_col(nt, height, (0.5, 0.5, 0.5, 1.0), smooth, (0, -150))
    bump = node(nt, "ShaderNodeBump", (200, -200))
    bump.inputs["Strength"].default_value = 0.9
    bump.inputs["Distance"].default_value = 0.012
    nt.links.new(height, bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    # Glut: leuchtet in den Fugen (zwischen Schuppen / Platten), nicht auf ihnen
    gap = mix_col(nt, math_node(nt, "SUBTRACT", (-300, -400), 1.0, crevice), math_node(nt, "SUBTRACT", (-300, -500), 1.0, plate),
                  belly, (-100, -450))
    gap = mix_col(nt, gap, (1.0, 1.0, 1.0, 1.0), smooth, (50, -450))
    g = math_node(nt, "MULTIPLY", (200, -450), gap, glow)
    emit = mix_col(nt, (0, 0, 0, 1), (1.0, 0.32, 0.04, 1.0), g, (350, -450))
    nt.links.new(emit, bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 1.0
    return mat


def new_image(name, size, non_color=False):
    img = bpy.data.images.new(name, size, size, alpha=False, float_buffer=False)
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    return img


def bake(obj, mat, image, kind, samples=1, **kw):
    nt = mat.node_tree
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = image
    nt.nodes.active = tex
    for o in bpy.context.scene.objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.context.scene.cycles.samples = samples
    bpy.ops.object.bake(type=kind, margin=8, use_clear=True, **kw)
    nt.nodes.remove(tex)
    log("gebacken: %s (%s)" % (image.name, kind))


def save_image(img):
    os.makedirs(TEX_DIR, exist_ok=True)
    img.filepath_raw = os.path.join(TEX_DIR, img.name + ".png")
    img.file_format = "PNG"
    img.save()


def pixels(img):
    import numpy as np
    arr = np.empty(img.size[0] * img.size[1] * 4, dtype=np.float32)
    img.pixels.foreach_get(arr)
    return arr.reshape(img.size[1], img.size[0], 4)


def set_pixels(img, arr):
    img.pixels.foreach_set(arr.astype("float32").ravel())
    img.update()


def unwrap(obj, margin=0.003):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=margin, area_weight=0.6)
    bpy.ops.object.mode_set(mode="OBJECT")


def final_material(name, albedo, normal=None, emission=None, emission_strength=1.0, roughness=0.55, double_sided=False):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = roughness
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = albedo
    nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
    if normal is not None:
        tn = nt.nodes.new("ShaderNodeTexImage")
        tn.image = normal
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    if emission is not None:
        te = nt.nodes.new("ShaderNodeTexImage")
        te.image = emission
        nt.links.new(te.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    mat.use_backface_culling = not double_sided
    return mat


def horn_atlas(size=512):
    """Farbverläufe je Spalte: Horn, Zahn, Kralle, Flügelknochen (v = Ansatz -> Spitze)."""
    import numpy as np
    h = w = size
    v = np.linspace(0.0, 1.0, h)[:, None]
    u = np.linspace(0.0, 1.0, w)[None, :]
    rnd = np.random.default_rng(5)
    noise = rnd.random((h, w))
    for _ in range(3):
        noise = (noise + np.roll(noise, 1, 0) + np.roll(noise, -1, 0) + np.roll(noise, 1, 1) + np.roll(noise, -1, 1)) / 5.0
    streak = (rnd.random((1, w)) - 0.5) * 0.12

    def ramp(stops):
        out = np.zeros((h, 1, 3))
        for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
            m = (v >= p0) & (v <= p1)
            f = np.clip((v - p0) / max(p1 - p0, 1e-6), 0, 1)[..., None]
            out = np.where(m[..., None], np.array(hex_lin(c0))[None, None] * (1 - f) + np.array(hex_lin(c1))[None, None] * f, out)
        return out

    cols = {
        "horn": ramp([(0.0, "#6a3424"), (0.3, "#4a3029"), (0.75, "#2a201d"), (1.0, "#120e0d")]),
        "tooth": ramp([(0.0, "#b89a6a"), (0.4, "#e2d3b0"), (1.0, "#f6efdf")]),
        "claw": ramp([(0.0, "#3a2a26"), (0.5, "#1c1514"), (1.0, "#080606")]),
        "wingbone": ramp([(0.0, "#5a120d"), (0.5, "#4a0f0b"), (1.0, "#2a0807")]),
    }
    img = np.zeros((h, w, 4))
    img[..., 3] = 1.0
    for key, u0 in PALETTE.items():
        x0, x1 = int(u0 * w), int((u0 + 0.25) * w)
        base = np.repeat(cols[key], x1 - x0, axis=1)
        var = 0.85 + 0.3 * noise[:, x0:x1, None] + streak[:, x0:x1, None]
        if key == "horn":   # Wachstumsringe
            rings = 0.82 + 0.18 * np.abs(np.sin(v * np.pi * 26.0))[..., None]
            var = var * rings
        img[:, x0:x1, :3] = np.clip(base * var, 0, 1)
    out = new_image("DragonHornAtlas", size)
    set_pixels(out, img)
    return out


def membrane_texture(size=1024):
    """Flughaut: dunkel am Ansatz, zum Rand rötlich durchscheinend, Adern entlang der Felder, dunkle Ränder."""
    import numpy as np
    h = w = size
    v = np.linspace(0.0, 1.0, h)[:, None] * np.ones((1, w))
    uu = np.linspace(0.0, 1.0, w)[None, :] * np.ones((h, 1))
    col_idx = np.minimum((uu / 0.2).astype(int), 4)
    a = np.clip(((uu - col_idx * 0.2) - 0.01) / 0.18, 0.0, 1.0)
    t = np.clip((v - 0.01) / 0.98, 0.0, 1.0)
    rnd = np.random.default_rng(9)
    noise = rnd.random((h // 8, w // 8))
    for _ in range(2):
        noise = (noise + np.roll(noise, 1, 0) + np.roll(noise, -1, 0) + np.roll(noise, 1, 1) + np.roll(noise, -1, 1)) / 5.0
    noise = np.kron(noise, np.ones((8, 8)))[:h, :w]
    root, edge, vein_c = np.array(hex_lin("#4a0e0a")), np.array(hex_lin("#b03c1c")), np.array(hex_lin("#1e0605"))
    f = (t ** 0.8)[..., None]
    img = root[None, None] * (1 - f) + edge[None, None] * f
    img *= (0.85 + 0.3 * noise)[..., None]
    veins = np.zeros((h, w))
    for c in range(5):
        n_veins = 7 if c == 3 else (3 if c < 3 else 4)
        for k in range(1, n_veins):
            ak = k / n_veins + 0.025 * np.sin(t * (7.0 + k) + k * 1.7 + c)
            width = 0.010 + 0.012 * (1.0 - t)
            veins = np.maximum(veins, (col_idx == c) * np.exp(-((a - ak) / width) ** 2))
            # Seitenäste
            for br in (0.35, 0.62):
                ab = ak + (t - br) * 0.6 * (1 if k % 2 else -1)
                veins = np.maximum(veins, (col_idx == c) * (t > br) * (t < br + 0.25) * np.exp(-((a - ab) / (width * 0.7)) ** 2) * 0.8)
    rim = np.maximum(np.exp(-((1.0 - t) / 0.025) ** 2), np.maximum(np.exp(-(a / 0.03) ** 2), np.exp(-((1.0 - a) / 0.03) ** 2)) * 0.7)
    dark = np.clip(np.maximum(veins, rim), 0, 1)[..., None]
    img = img * (1 - dark * 0.8) + vein_c[None, None] * dark * 0.8
    rgba = np.ones((h, w, 4))
    rgba[..., :3] = np.clip(img, 0, 1)
    out = new_image("DragonMembrane", size)
    set_pixels(out, rgba)
    return out


def stage_texture(ctx):
    import numpy as np
    table = {b[0]: b for b in bone_table()}
    body = join([ctx["body"], ctx["jaw"]], "DragonBody")
    ctx["body"] = body
    parts = join([ctx["horns"], ctx["wing_bones"], ctx["eyes"], ctx["pupils"]], "DragonParts")
    ctx["horns"] = parts
    for key in ("jaw", "wing_bones", "eyes", "pupils"):
        ctx.pop(key, None)
    paint_body(body, table)
    unwrap(body)
    setup_bake_engine()
    bake_mat = bake_material_body()
    body.data.materials.clear()
    body.data.materials.append(bake_mat)
    size = 2048
    albedo = new_image("DragonBody_albedo", size)
    normal = new_image("DragonBody_normal", size, non_color=True)
    emit = new_image("DragonBody_emission", 1024)
    ao = new_image("DragonBody_ao", size, non_color=True)
    bake(body, bake_mat, albedo, "DIFFUSE", pass_filter={"COLOR"})
    bake(body, bake_mat, normal, "NORMAL", normal_space="TANGENT")
    bake(body, bake_mat, emit, "EMIT")
    hidden = [o for o in bpy.context.scene.objects if o.type == "MESH" and o != body]
    for o in hidden:
        o.hide_render = True
    bake(body, bake_mat, ao, "AO", samples=48)
    for o in hidden:
        o.hide_render = False
    # Umgebungsverdeckung in die Farbe malen (gemalter Look, tiefe Fugen auch ohne Echtzeit-Schatten)
    alb = pixels(albedo)
    occ = pixels(ao)[..., :1]
    alb[..., :3] *= 0.42 + 0.58 * np.clip(occ, 0, 1) ** 1.1
    set_pixels(albedo, alb)
    for img in (albedo, normal, emit):
        save_image(img)
    body.data.materials.clear()
    body.data.materials.append(final_material("DragonBody", albedo, normal, emit, emission_strength=2.5, roughness=0.5))
    # Hörner/Zähne/Krallen/Flügelknochen: Farbverläufe; Augen und Pupillen behalten ihre Materialien
    atlas = horn_atlas()
    save_image(atlas)
    horn_mat = final_material("DragonHorn", atlas, roughness=0.55)
    mats = parts.data.materials
    for i, m in enumerate(mats):
        if m and m.name.startswith("HornClay"):
            mats[i] = horn_mat
    eye = next((m for m in mats if m and m.name.startswith("EyeGlow")), None)
    if eye:
        eye.name = "DragonEye"
    membrane = membrane_texture()
    save_image(membrane)
    ctx["wings"].data.materials.clear()
    ctx["wings"].data.materials.append(final_material("DragonMembrane", membrane, roughness=0.75, double_sided=True))
    log("Texturen fertig -> %s" % TEX_DIR)


def setup_bake_engine():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "OPTIX"
        prefs.get_devices()
        for d in prefs.devices:
            d.use = d.type == "OPTIX"
        scene.cycles.device = "GPU"
    except Exception as exc:
        log("GPU nicht verfügbar: %s" % exc)
    scene.render.bake.margin = 8


# --- Phase 6: Animationen ----------------------------------------------------------------------------
# Drehachsen (Armature-Raum): LEFT + = nach vorn zeigende Knochen nicken nach unten, nach unten zeigende Beinknochen
# schwingen nach hinten, nach hinten zeigende Schwanzknochen heben sich; UP + = nach links drehen;
# BACK + = linker Flügel nach unten (rechter Flügel nach oben).

BACK = V((0.0, 1.0, 0.0))
SIDES = ((1.0, ".L"), (-1.0, ".R"))


def wave(t, freq=1.0, phase=0.0):
    return math.sin(2.0 * math.pi * (t * freq + phase))


def ground_base(p, breath=0.0):
    fold_wings(p, 1.0)
    for side, suf in SIDES:
        p.turn("w_upper" + suf, BACK, 1.5 * breath * side)
    p.turn("chest", LEFT, -1.2 * breath)
    p.turn("neck1", LEFT, 0.8 * breath)


def tail_wave(p, t, amp, phase=0.0, lift=0.0, freq=1.0):
    for i in range(1, 8):
        p.turn("tail%d" % i, UP, amp * (0.35 + 0.15 * i) * wave(t, freq, phase - i * 0.08))
        if lift:
            p.turn("tail%d" % i, LEFT, lift)


def keyed(p, name, frames, pose_fn):
    """Legt eine Aktion an und setzt an jedem Bild der Liste die Pose pose_fn(p, frame)."""
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    p.arm.animation_data.action = act
    for f in frames:
        p.reset()
        pose_fn(p, f)
        p.key(f)
    return act


def tween(keys, f):
    """keys: [(Bild, (Werte...))] -> weich interpolierte Werte bei Bild f."""
    for (f0, a), (f1, b) in zip(keys, keys[1:]):
        if f0 <= f <= f1:
            s = smoothstep(0.0, 1.0, (f - f0) / max(f1 - f0, 1e-6))
            return [lerp(x, y, s) for x, y in zip(a, b)]
    return list(keys[-1][1])


def leg_cycle(phi):
    """Gangzyklus eines Beins: x = Fußposition (+1 vorn, -1 hinten), lift = Anheben in der Schwungphase."""
    phi %= 1.0
    if phi < 0.62:
        return 1.0 - 2.0 * phi / 0.62, 0.0
    s = (phi - 0.62) / 0.38
    return -1.0 + 2.0 * (0.5 - 0.5 * math.cos(math.pi * s)), math.sin(math.pi * s)


def anim_idle(p):
    n = 80

    def pose(p, f):
        t = f / n
        ground_base(p, wave(t))
        p.turn("neck2", UP, 4.0 * wave(t, 1, 0.1))
        p.turn("neck3", UP, 3.0 * wave(t, 1, 0.2))
        p.turn("head", LEFT, -3.0 * wave(t, 2, 0.3))
        p.turn("head", UP, 6.0 * wave(t, 1, 0.35))
        p.turn("jaw", LEFT, 2.0 + 2.0 * wave(t, 2))
        tail_wave(p, t, 4.0)
    return keyed(p, "Idle", range(0, n + 1, 4), pose)


def anim_walk(p):
    n = 36
    legs = (("f", ".L", 0.25), ("f", ".R", 0.75), ("h", ".L", 0.0), ("h", ".R", 0.5))

    def pose(p, f):
        t = f / n
        ground_base(p, 0.3 * wave(t, 2))
        for kind, suf, ph in legs:
            x, lift = leg_cycle(t + ph)
            if kind == "f":
                p.turn("f_upper" + suf, LEFT, -22.0 * x)
                p.turn("f_lower" + suf, LEFT, 48.0 * lift)
                p.turn("f_foot" + suf, LEFT, 30.0 * lift)
            else:
                p.turn("h_thigh" + suf, LEFT, -24.0 * x)
                p.turn("h_shin" + suf, LEFT, 30.0 * lift)
                p.turn("h_meta" + suf, LEFT, -22.0 * lift)
                p.turn("h_toe" + suf, LEFT, 25.0 * lift)
        p.move("hips", (0.0, 0.0, 0.035 * wave(t, 2, 0.25)))
        p.turn("spine", UP, 3.0 * wave(t))
        p.turn("chest", UP, -4.0 * wave(t))
        p.turn("neck1", LEFT, 2.0 * wave(t, 2))
        p.turn("neck2", UP, 3.0 * wave(t, 1, 0.1))
        p.turn("head", LEFT, -2.0 * wave(t, 2))
        tail_wave(p, t, 6.0, phase=0.15)
    return keyed(p, "Walk", range(0, n + 1, 2), pose)


def anim_bite(p):
    keys = [(0, (0, 0, 2)), (9, (1, 0, 18)), (14, (0, 1, 38)), (17, (0, 0.9, 0)), (30, (0, 0, 2))]

    def pose(p, f):
        rear, strike, jaw = tween(keys, f)
        ground_base(p)
        p.turn("chest", LEFT, -4 * rear + 5 * strike)
        p.turn("neck1", LEFT, -12 * rear + 14 * strike)
        p.turn("neck2", LEFT, -10 * rear + 12 * strike)
        p.turn("neck3", LEFT, -6 * rear + 10 * strike)
        p.turn("head", LEFT, -8 * rear + 6 * strike)
        p.turn("jaw", LEFT, jaw)
        tail_wave(p, f / 30.0, 3.0)
    return keyed(p, "Attack_Bite", [0, 3, 6, 9, 11, 13, 14, 15, 17, 20, 24, 30], pose)


def anim_claw(p):
    keys = [(0, (0, 0)), (10, (1, 0)), (14, (0.6, 1)), (18, (0.3, 1)), (32, (0, 0))]

    def pose(p, f):
        raise_, swipe = tween(keys, f)
        ground_base(p)
        p.turn("chest", LEFT, -6 * raise_)
        p.turn("spine", UP, -6 * swipe)
        p.turn("f_upper.R", LEFT, -70 * raise_ + 55 * swipe)
        p.turn("f_upper.R", UP, -15 * raise_ + 25 * swipe)
        p.turn("f_lower.R", LEFT, -30 * raise_ + 12 * swipe)
        p.turn("f_foot.R", LEFT, 25 * raise_)
        p.turn("neck2", UP, -8 * swipe)
        p.turn("head", LEFT, 6 * swipe)
        p.turn("jaw", LEFT, 8 + 10 * raise_)
        tail_wave(p, f / 32.0, 4.0)
    return keyed(p, "Attack_Claw", [0, 4, 8, 10, 12, 14, 16, 18, 22, 26, 32], pose)


def anim_fire_breath(p):
    keys = [(0, (0, 0, 0, 2)), (12, (1, 0, 0, 12)), (18, (0.2, 1, -1, 40)), (30, (0.2, 1, 0, 42)), (42, (0.2, 1, 1, 40)),
            (50, (0.1, 0.8, 0.5, 30)), (60, (0, 0, 0, 2))]

    def pose(p, f):
        rear, breath, sweep, jaw = tween(keys, f)
        fold_wings(p, 1.0 - 0.25 * rear, spread=0.6 * rear)
        p.turn("spine", LEFT, -3 * rear)
        p.turn("chest", LEFT, -5 * rear + 4 * breath)
        p.turn("neck1", LEFT, -14 * rear + 16 * breath)
        p.turn("neck2", LEFT, -12 * rear + 12 * breath)
        p.turn("neck3", LEFT, -8 * rear + 8 * breath)
        p.turn("head", LEFT, -10 * rear + 12 * breath)
        p.turn("neck2", UP, 10 * sweep)
        p.turn("neck3", UP, 8 * sweep)
        p.turn("jaw", LEFT, jaw)
        tail_wave(p, f / 60.0, 3.0, lift=2.0 * rear)
    return keyed(p, "Fire_Breath", list(range(0, 61, 3)), pose)


def anim_roar(p):
    keys = [(0, (0, 0, 0, 0)), (14, (1, 1, 25, 0)), (20, (1, 1, 45, 1)), (26, (1, 1, 45, -1)), (32, (1, 1, 45, 1)),
            (40, (1, 1, 40, 0)), (60, (0, 0, 0, 0))]

    def pose(p, f):
        rear, wings, jaw, shake = tween(keys, f)
        fold_wings(p, 1.0 - wings)
        for side, suf in SIDES:
            p.turn("w_upper" + suf, BACK, -25.0 * wings * side)
        p.turn("spine", LEFT, -6 * rear)
        p.turn("chest", LEFT, -8 * rear)
        for side, suf in SIDES:   # Vorderbeine bleiben senkrecht, die Pranken heben ab
            p.turn("f_upper" + suf, LEFT, 10 * rear)
        p.turn("neck1", LEFT, -15 * rear)
        p.turn("neck2", LEFT, -12 * rear)
        p.turn("neck3", LEFT, -10 * rear)
        p.turn("head", LEFT, -20 * rear + 3 * shake)
        p.turn("head", UP, 4 * shake)
        p.turn("jaw", LEFT, jaw)
        tail_wave(p, f / 60.0, 5.0, lift=4.0 * rear)
    return keyed(p, "Roar", list(range(0, 61, 3)), pose)


def anim_hit(p):
    keys = [(0, (0,)), (3, (1,)), (14, (0,))]

    def pose(p, f):
        (k,) = tween(keys, f)
        ground_base(p)
        p.turn("chest", LEFT, -3 * k)
        p.turn("neck2", UP, 10 * k)
        p.turn("neck3", LEFT, -8 * k)
        p.turn("head", LEFT, -10 * k)
        p.turn("jaw", LEFT, 2 + 15 * k)
        tail_wave(p, f / 14.0, 3.0 * k)
    return keyed(p, "Hit", [0, 2, 3, 5, 8, 11, 14], pose)


def anim_death(p):
    keys = [(0, (0, 0)), (10, (1, 0)), (22, (1, 0.6)), (30, (1, 1.05)), (34, (1, 0.97)), (60, (1, 1.0))]

    def pose(p, f):
        fall, roll = tween(keys, f)
        fold_wings(p, 1.0 - 0.45 * roll)
        p.turn("root", BACK, 64.0 * roll)                    # kippt auf die linke Seite
        p.turn("chest", LEFT, 8 * fall)
        p.turn("neck1", LEFT, 10 * fall)
        p.turn("neck2", LEFT, 14 * fall + 6 * roll)
        p.turn("neck2", UP, 12 * roll)
        p.turn("head", LEFT, 12 * fall)
        p.turn("jaw", LEFT, 4 + 18 * roll)
        for side, suf in SIDES:
            p.turn("f_upper" + suf, LEFT, -15 * roll * side)
            p.turn("f_lower" + suf, LEFT, 25 * fall)
            p.turn("h_thigh" + suf, LEFT, -10 * roll)
            p.turn("h_shin" + suf, LEFT, 15 * fall)
        for i in range(1, 8):
            p.turn("tail%d" % i, UP, 4.0 * roll)
    return keyed(p, "Death", [0, 5, 10, 16, 22, 26, 30, 34, 40, 50, 60], pose)


def anim_fly(p):
    n = 30

    def pose(p, f):
        t = f / n
        flap = wave(t)
        p.move("root", (0.0, 0.0, 1.6 - 0.12 * wave(t, 1, 0.25)))
        for side, suf in SIDES:
            p.turn("w_upper" + suf, BACK, -38.0 * flap * side)
            p.turn("w_fore" + suf, BACK, -18.0 * wave(t, 1, -0.1) * side)
            for i in range(1, 5):
                p.turn("w_f%d%s" % (i, suf), BACK, -10.0 * wave(t, 1, -0.16) * side)
            p.turn("f_upper" + suf, LEFT, 55)
            p.turn("f_lower" + suf, LEFT, -65)
            p.turn("h_thigh" + suf, LEFT, 62)
            p.turn("h_shin" + suf, LEFT, 15)
            p.turn("h_toe" + suf, LEFT, 30)
        p.turn("chest", LEFT, -2.0 * flap)
        p.turn("neck1", LEFT, 10)
        p.turn("head", LEFT, -10)
        tail_wave(p, t, 4.0, lift=-1.5)
    return keyed(p, "Fly", range(0, n + 1, 2), pose)


ANIMS = [anim_idle, anim_walk, anim_bite, anim_claw, anim_fire_breath, anim_roar, anim_hit, anim_death, anim_fly]


def stage_anim(ctx):
    arm = ctx["arm"]
    arm.animation_data_create()
    mods = [m for o in bpy.context.scene.objects if o.type == "MESH" for m in o.modifiers if m.type == "ARMATURE"]
    for m in mods:   # Posen ohne Mesh-Verformung rechnen (schneller)
        m.show_viewport = False
    p = Poser(arm)
    names = [fn(p).name for fn in ANIMS]
    arm.animation_data.action = None
    p.reset()
    for m in mods:
        m.show_viewport = True
    ctx["anims"] = names
    log("Animationen: %s" % ", ".join(names))


# --- Phase 7: Export ---------------------------------------------------------------------------------

def stage_export(ctx):
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    # alle Knochen exportieren: "root" verformt nichts, trägt aber Tod (Umkippen) und Flug (Höhe)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=False, export_animations=True,
                              export_animation_mode="ACTIONS", export_skins=True, export_def_bones=False, export_yup=True)
    log("exportiert -> %s (%.1f MB)" % (OUT, os.path.getsize(OUT) / 1e6))


# --- Vorschau ------------------------------------------------------------------------------------------

def clay(name, color, rough=0.55):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    return mat


def setup_render(res=(1280, 860), samples=48):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "OPTIX"
        prefs.get_devices()
        for d in prefs.devices:
            d.use = d.type == "OPTIX"
        scene.cycles.device = "GPU"
    except Exception as exc:   # ohne GPU geht es auch, nur langsamer
        log("GPU nicht verfügbar: %s" % exc)
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "AgX"
    world = bpy.data.worlds.new("PreviewWorld")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.045, 0.05, 0.065, 1.0)
    world.node_tree.nodes["Background"].inputs[1].default_value = 1.0
    scene.world = world
    for name, rot, energy, color in (("Key", (52, 0, -38), 4.0, (1.0, 0.95, 0.88)), ("Rim", (60, 0, 150), 3.0, (0.6, 0.7, 1.0)),
                                     ("Fill", (75, 0, 60), 1.0, (1.0, 0.9, 0.85))):
        light = bpy.data.lights.new(name, "SUN")
        light.energy = energy
        light.color = color
        light.angle = math.radians(4.0)
        lo = link(bpy.data.objects.new(name, light))
        lo.rotation_euler = [math.radians(a) for a in rot]
    ground = bpy.data.meshes.new("Ground")
    ground.from_pydata([(-30, -30, 0), (30, -30, 0), (30, 30, 0), (-30, 30, 0)], [], [(0, 1, 2, 3)])
    go = link(bpy.data.objects.new("Ground", ground))
    go.data.materials.append(clay("GroundMat", (0.06, 0.065, 0.075), 0.9))
    cam = link(bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam")))
    cam.data.lens = 50
    scene.camera = cam
    return cam


def look(cam, pos, target):
    cam.location = V(pos)
    cam.rotation_euler = (V(target) - V(pos)).to_track_quat("-Z", "Y").to_euler()


VIEWS = {
    "front34": ((-8.5, -11.5, 6.0), (0.0, 0.3, 1.6)),
    "side": ((-11.5, 0.6, 2.4), (0.0, 0.7, 1.3)),
    "head": ((-3.0, -5.2, 3.5), (0.0, -2.1, 2.5)),
    "back": ((5.5, 8.5, 5.5), (0.0, 0.8, 1.6)),
    "top": ((0.0, 0.4, 13.0), (0.0, 0.4, 1.0)),
}


def render_previews(folder, tag, views=("front34", "side", "head")):
    cam = bpy.context.scene.camera or setup_render()
    os.makedirs(folder, exist_ok=True)
    for view in views:
        pos, target = VIEWS[view]
        look(cam, pos, target)
        bpy.context.scene.render.filepath = os.path.join(folder, "%s_%s.png" % (tag, view))
        bpy.ops.render.render(write_still=True)
        log("Vorschau -> %s" % bpy.context.scene.render.filepath)


ANIM_SHOTS = [("Idle", 0, "front34"), ("Walk", 10, "side"), ("Attack_Bite", 14, "head"), ("Attack_Claw", 12, "front34"),
              ("Fire_Breath", 30, "front34"), ("Roar", 30, "front34"), ("Hit", 3, "head"), ("Death", 60, "front34"),
              ("Fly", 8, "front34")]


def render_anim_sheet(folder, ctx, cols=3):
    """Je Animation ein Standbild an einer Schlüsselstelle, zusammengesetzt zu einem Übersichtsbild."""
    import numpy as np
    scene = bpy.context.scene
    cam = scene.camera
    arm = ctx["arm"]
    scene.render.resolution_x, scene.render.resolution_y = 640, 430
    scene.cycles.samples = 24
    os.makedirs(folder, exist_ok=True)
    tiles = []
    for act_name, frame, view in ANIM_SHOTS:
        arm.animation_data.action = bpy.data.actions[act_name]
        scene.frame_set(frame)
        look(cam, *VIEWS[view])
        path = os.path.join(folder, "anim_%s.png" % act_name)
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        tiles.append(pixels(bpy.data.images.load(path)))
    rows = [np.concatenate(tiles[r * cols:(r + 1) * cols], axis=1) for r in range(len(tiles) // cols)]
    sheet = np.concatenate(rows[::-1], axis=0)
    img = bpy.data.images.new("AnimSheet", sheet.shape[1], sheet.shape[0])
    set_pixels(img, sheet)
    img.filepath_raw = os.path.join(folder, "anim_sheet.png")
    img.file_format = "PNG"
    img.save()
    arm.animation_data.action = None
    log("Animations-Übersicht -> %s" % img.filepath_raw)


# --- Ablauf --------------------------------------------------------------------------------------------

def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    stage = argv[argv.index("--stage") + 1] if "--stage" in argv else STAGES[-1]
    preview = argv[argv.index("--preview") + 1] if "--preview" in argv else None
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS
    ctx = {}
    for name in STAGES[: STAGES.index(stage) + 1]:
        fn = globals().get("stage_" + name)
        if fn is None:
            log("Phase %s noch nicht gebaut" % name)
            break
        log("--- Phase %s ---" % name)
        fn(ctx)
    if preview:
        setup_render()
        if stage in ("body", "details", "wings", "rig"):
            mat = clay("Clay", (0.42, 0.12, 0.08))
            for obj in bpy.context.scene.objects:
                if obj.type == "MESH" and obj.name != "Ground" and not obj.data.materials:
                    obj.data.materials.append(mat)
        if stage == "rig":
            test_pose(Poser(ctx["arm"]))
        if stage in ("anim", "export"):
            render_anim_sheet(preview, ctx)
        else:
            render_previews(preview, stage, ("front34", "side", "head", "back", "top") if stage != "body" else ("front34", "side", "head"))
        if stage == "texture":
            test_pose(Poser(ctx["arm"]))
            render_previews(preview, stage + "_pose", ("front34", "head"))
    log("fertig.")


if __name__ == "__main__":
    main()
