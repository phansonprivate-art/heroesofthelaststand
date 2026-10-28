"""Eigene Körperanimationen für die Helden, in Blender auf dem KayKit-Skelett gebaut.

Ausgangspunkt jeder Pose ist die Stehpose (Idle, Bild 0); verändert werden Oberkörper, Arme und Kopf.
Die Beine bleiben in der Stehpose, damit die Füße nicht rutschen. Posen werden im Armature-Raum
beschrieben (Blender: vorn = -Y, oben = +Z, links der Figur = +X): Knochen ausrichten (aim) und um
den eigenen Ansatz drehen (turn). Ausgabe ist eine Animationsbibliothek mit einem Mini-Mesh
(nötig, damit Godot ein Skeleton3D anlegt); im Spiel heißen die Animationen "kk/<Name>".

  Fireball_Cast   Ausholen mit der freien linken Hand an der Hüfte, Wurf nach vorn, Arm sinkt zurück
  Sanctuary_Cast  beide Arme im V zum Himmel, Stab nach oben, Blick nach oben, halten, sinken lassen

Aufruf (Blender 5.2, ohne Oberfläche):
  blender.exe --background --python tools/blender_hero_animations.py
"""
import math
import os

import bpy
from mathutils import Matrix, Vector

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(PROJECT, "assets", "models", "heroes_custom", "Arcanist.glb")
OUT = os.path.join(PROJECT, "assets", "models", "heroes_custom", "anims", "Spell_Animations.glb")
FPS = 30

UP = Vector((0.0, 0.0, 1.0))
FORWARD = Vector((0.0, -1.0, 0.0))
LEFT = Vector((1.0, 0.0, 0.0))   # linke Seite der Figur


class Poser:
    def __init__(self, arm):
        self.arm = arm
        self.pose = arm.pose
        self.base = {}

    def capture_base(self, action_name, frame):
        """Merkt sich die Pose einer vorhandenen Animation als Ausgangspunkt."""
        self.arm.animation_data_create()
        self.arm.animation_data.action = bpy.data.actions[action_name]
        bpy.context.scene.frame_set(frame)
        bpy.context.view_layer.update()
        self.base = {pb.name: pb.matrix_basis.copy() for pb in self.pose.bones}
        self.arm.animation_data.action = None

    def reset(self):
        for pb in self.pose.bones:
            pb.rotation_mode = "QUATERNION"
            pb.matrix_basis = self.base[pb.name]
        bpy.context.view_layer.update()

    def _set_world(self, pb, mat):
        pb.matrix = mat
        bpy.context.view_layer.update()

    def turn(self, bone, axis, degrees):
        """Dreht einen Knochen (samt Kindern) im Armature-Raum um seinen Ansatz."""
        pb = self.pose.bones[bone]
        head = pb.matrix.translation.copy()
        rot = Matrix.Rotation(math.radians(degrees), 4, axis)
        self._set_world(pb, Matrix.Translation(head) @ rot @ Matrix.Translation(-head) @ pb.matrix)

    def aim(self, bone, direction, amount=1.0):
        """Richtet die Knochenachse (lokal +Y) auf eine Richtung im Armature-Raum, kleinste Drehung.
        amount < 1 dreht nur anteilig dorthin (Zwischenposen)."""
        pb = self.pose.bones[bone]
        current = pb.matrix.col[1].xyz.normalized()
        target = current.slerp(Vector(direction).normalized(), amount)
        rot = current.rotation_difference(target).to_matrix().to_4x4()
        head = pb.matrix.translation.copy()
        self._set_world(pb, Matrix.Translation(head) @ rot @ Matrix.Translation(-head) @ pb.matrix)

    def key(self, frame):
        for pb in self.pose.bones:
            pb.keyframe_insert("rotation_quaternion", frame=frame)
            pb.keyframe_insert("location", frame=frame)


# --- Fireball_Cast -------------------------------------------------------------------------------
# Der Feuerball fliegt im Spiel sofort los: der Wurf liegt deshalb ganz vorn (Bild 4 = 0,13 s).

def torso(p, twist, lean):
    """Oberkörper verdrehen (twist > 0: linke Schulter zurück) und neigen (lean > 0: nach vorn;
    positive Drehung um +X kippt +Z nach -Y = vorn). Der Kopf dreht gegen, der Blick bleibt beim Ziel."""
    p.turn("spine", UP, twist * 0.45)
    p.turn("spine", LEFT, lean * 0.5)
    p.turn("chest", UP, twist * 0.55)
    p.turn("chest", LEFT, lean * 0.5)
    p.turn("head", UP, -twist * 0.8)
    p.turn("head", LEFT, -lean * 0.6)


def fireball_windup(p):
    torso(p, 32.0, -6.0)
    p.aim("upperarm.l", (0.3, 0.4, -0.86))      # Ellbogen nach hinten unten
    p.aim("lowerarm.l", (0.05, -0.95, 0.3))     # Unterarm nach vorn, Hand an der Hüfte
    p.aim("wrist.l", (0.0, -0.8, 0.6))
    p.aim("hand.l", (0.0, -0.6, 0.8))           # Handfläche nach oben: Feuer sammeln
    p.turn("upperarm.r", UP, -24.0)              # Stabarm dreht gegen: der Stab bleibt seitlich


def fireball_throw(p, reach=1.0):
    torso(p, -26.0 * reach, 14.0 * reach)
    p.aim("upperarm.l", (-0.12, -1.0, 0.22))    # Arm gestreckt zum Ziel, knapp über Schulterhöhe
    p.aim("lowerarm.l", (-0.1, -1.0, 0.18))
    p.aim("wrist.l", (-0.08, -0.85, 0.5))
    p.aim("hand.l", (0.0, -0.35, 0.95))          # Handfläche nach vorn (stoßen)
    p.turn("upperarm.r", UP, -18.0 * reach)      # Stabarm schwingt gegen
    p.turn("upperarm.r", LEFT, 10.0 * reach)


def build_fireball_cast(p):
    act = bpy.data.actions.new("Fireball_Cast")
    p.arm.animation_data.action = act
    p.reset(); fireball_windup(p); p.key(0)
    p.reset(); fireball_throw(p, 1.15); p.key(4)    # leicht überzogen: Wucht
    p.reset(); fireball_throw(p, 1.0); p.key(8)
    p.reset(); fireball_throw(p, 0.85); p.key(16)   # Arm bleibt kurz stehen
    p.reset(); p.key(30)                             # zurück in die Stehpose
    return act


# --- Sanctuary_Cast ------------------------------------------------------------------------------
# Beide Arme im V zum Himmel, Stab nach oben, Blick nach oben; halten, dann sinken lassen.

def sanctuary_raise(p, amount):
    torso(p, 0.0, -9.0 * amount)
    p.turn("head", LEFT, -18.0 * amount)                  # Blick nach oben
    p.aim("upperarm.l", (0.55, -0.12, 0.83), amount)
    p.aim("lowerarm.l", (0.38, -0.18, 0.91), amount)
    p.aim("hand.l", (0.3, -0.3, 0.9), amount)
    p.aim("upperarm.r", (-0.55, -0.12, 0.83), amount)     # Stabarm ebenso: der Stab ragt nach oben
    p.aim("lowerarm.r", (-0.38, -0.18, 0.91), amount)


def build_sanctuary_cast(p):
    act = bpy.data.actions.new("Sanctuary_Cast")
    p.arm.animation_data.action = act
    p.reset(); p.key(0)
    p.reset(); sanctuary_raise(p, 0.55); p.key(5)
    p.reset(); sanctuary_raise(p, 1.0); p.key(10)
    p.reset(); sanctuary_raise(p, 1.08); p.key(24)      # halten, noch etwas weiter gestreckt
    p.reset(); sanctuary_raise(p, 0.85); p.key(32)
    p.reset(); p.key(44)                                  # zurück in die Stehpose
    return act


def add_anchor_mesh(arm):
    """Mini-Dreieck am Becken: ohne gewichtetes Mesh legt Godot kein Skeleton3D an."""
    mesh = bpy.data.meshes.new("AnimAnchor")
    mesh.from_pydata([(0, 0, 0.5), (0.01, 0, 0.5), (0, 0.01, 0.5)], [], [(0, 1, 2)])
    obj = bpy.data.objects.new("AnimAnchor", mesh)
    bpy.context.scene.collection.objects.link(obj)
    group = obj.vertex_groups.new(name="hips")
    group.add([0, 1, 2], 1.0, "REPLACE")
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    obj.parent = arm


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS
    bpy.ops.import_scene.gltf(filepath=SOURCE)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    for obj in [o for o in bpy.data.objects if o.type != "ARMATURE"]:
        bpy.data.objects.remove(obj, do_unlink=True)

    p = Poser(arm)
    p.capture_base("Idle", 0)
    keep = {build_fireball_cast(p).name, build_sanctuary_cast(p).name}
    for act in [a for a in bpy.data.actions if a.name not in keep]:
        bpy.data.actions.remove(act)
    add_anchor_mesh(arm)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=OUT,
        export_format="GLB",
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_skins=True,
        export_def_bones=False,
        export_yup=True,
    )
    print("Animationen gespeichert:", OUT, sorted(keep))


main()
