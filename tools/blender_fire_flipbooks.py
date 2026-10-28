"""Rendert Feuer-Flipbooks (Bildfolgen als Sprite-Sheet, 8 x 8 Bilder) für die Effekte im Spiel.

Prozedural statt Simulation: ein Würfel mit leuchtendem Volumen, dessen Form ein animiertes Rauschen
bestimmt; die Farbe folgt einer Temperatur-Skala (schwarz -> dunkelrot -> orange -> gelb -> weiß).
Gerendert wird auf Schwarz, im Spiel werden die Bilder additiv (leuchtend) überblendet.

  fire_loop.png       Feuerkugel, nahtlos wiederholbar (Rauschen läuft auf einer Kreisbahn)
  fire_explosion.png  Explosion: weißglühender Kern, wächst, kühlt über Orange und Rot ab, zerfällt

Aufruf (Blender 5.2, ohne Oberfläche):
  blender.exe --background --python tools/blender_fire_flipbooks.py [-- nur-name]
"""
import math
import os
import shutil
import sys
import tempfile

import bpy
import numpy as np

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(PROJECT, "assets", "effects", "flipbooks")
COLS = 8
ROWS = 8
FRAMES = COLS * ROWS
RENDER_SIZE = 256   # je Bild; im Sheet auf CELL verkleinert (glättet das Rauschen der Volumen)
CELL = 128
ORTHO_SCALE = 1.9   # sichtbare Breite; der Bildrand liegt bei 0.95
MASK_RADIUS = 0.93

# Temperatur -> Farbe (Position, sRGB)
RAMP = [
    (0.00, (0.0, 0.0, 0.0)),
    (0.14, (0.30, 0.02, 0.0)),
    (0.32, (0.85, 0.16, 0.01)),
    (0.52, (1.0, 0.42, 0.04)),
    (0.72, (1.0, 0.72, 0.18)),
    (0.90, (1.0, 0.94, 0.62)),
    (1.00, (1.0, 1.0, 0.95)),
]


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


class FireShader:
    """Knoten: Rauschen + kugelförmiger Abfall ergeben die Temperatur, daraus Farbe und Leuchtkraft.
    heat = clamp(gain * ((1 - d/R) + (noise - 0.5) * breakup)), Leuchtkraft = heat² * strength.
    Der Rand liegt bei d = R * (1 + (noise - 0.5) * breakup), höchstens R * (1 + breakup / 2);
    außerhalb ist heat exakt 0, damit im Spiel kein Schleier um das Bild sichtbar wird."""

    def __init__(self, mat):
        nt = mat.node_tree
        nt.nodes.clear()
        self._nodes = nt.nodes
        self._link = nt.links.new
        coords = self._nodes.new("ShaderNodeTexCoord")
        self.mapping = self._nodes.new("ShaderNodeMapping")
        self.noise = self._nodes.new("ShaderNodeTexNoise")
        self.noise.inputs["Detail"].default_value = 8.0
        self.noise.inputs["Roughness"].default_value = 0.65
        self.noise.inputs["Lacunarity"].default_value = 2.2
        self.noise.inputs["Distortion"].default_value = 0.6
        self._link(coords.outputs["Object"], self.mapping.inputs["Vector"])
        self._link(self.mapping.outputs["Vector"], self.noise.inputs["Vector"])

        dist = self._nodes.new("ShaderNodeVectorMath")
        dist.operation = "LENGTH"
        self._link(coords.outputs["Object"], dist.inputs[0])
        self.falloff = self._nodes.new("ShaderNodeMapRange")   # Abstand 0..R -> 1..0, außerhalb negativ
        self.falloff.clamp = False
        self.falloff.inputs["From Min"].default_value = 0.0
        self.falloff.inputs["To Min"].default_value = 1.0
        self.falloff.inputs["To Max"].default_value = 0.0
        self._link(dist.outputs["Value"], self.falloff.inputs["Value"])

        # Kontrast: das Rauschen liegt meist nahe 0.5; gespreizt entstehen deutliche Flammenzungen
        self.contrast = self._nodes.new("ShaderNodeMapRange")
        self.contrast.clamp = True
        self._link(self.noise.outputs["Fac"], self.contrast.inputs["Value"])
        centered = self._math("SUBTRACT", self.contrast.outputs["Result"], 0.5)
        self.breakup = self._math("MULTIPLY", centered.outputs[0], 1.0)
        shape = self._math("ADD", self.falloff.outputs["Result"], self.breakup.outputs[0])
        self.gain = self._math("MULTIPLY", shape.outputs[0], 1.0)
        # Kugelmaske knapp innerhalb des Bildrands: Flammenzungen werden weich ausgeblendet statt abgeschnitten
        mask = self._nodes.new("ShaderNodeMapRange")
        mask.clamp = True
        mask.inputs["From Min"].default_value = MASK_RADIUS - 0.15
        mask.inputs["From Max"].default_value = MASK_RADIUS
        mask.inputs["To Min"].default_value = 1.0
        mask.inputs["To Max"].default_value = 0.0
        self._link(dist.outputs["Value"], mask.inputs["Value"])
        heat = self._math("MULTIPLY", self.gain.outputs[0], mask.outputs["Result"])
        heat.use_clamp = True

        ramp = self._nodes.new("ShaderNodeValToRGB")
        elements = ramp.color_ramp.elements
        while len(elements) < len(RAMP):
            elements.new(0.5)
        for el, (pos, col) in zip(elements, RAMP):
            el.position = pos
            el.color = (*[srgb_to_linear(c) for c in col], 1.0)
        self._link(heat.outputs[0], ramp.inputs["Fac"])

        squared = self._math("POWER", heat.outputs[0], 2.0)
        self.strength = self._math("MULTIPLY", squared.outputs[0], 1.0)
        emission = self._nodes.new("ShaderNodeEmission")
        self._link(ramp.outputs["Color"], emission.inputs["Color"])
        self._link(self.strength.outputs[0], emission.inputs["Strength"])
        out = self._nodes.new("ShaderNodeOutputMaterial")
        self._link(emission.outputs["Emission"], out.inputs["Volume"])

    def _math(self, op, a, b):
        node = self._nodes.new("ShaderNodeMath")
        node.operation = op
        self._link(a, node.inputs[0])
        if isinstance(b, (int, float)):
            node.inputs[1].default_value = b
        else:
            self._link(b, node.inputs[1])
        return node

    def set(self, radius, gain, breakup, strength, offset, noise_scale, contrast=2.0):
        self.contrast.inputs["From Min"].default_value = 0.5 - 0.5 / contrast
        self.contrast.inputs["From Max"].default_value = 0.5 + 0.5 / contrast
        self.falloff.inputs["From Max"].default_value = radius
        self.gain.inputs[1].default_value = gain
        self.breakup.inputs[1].default_value = breakup
        self.strength.inputs[1].default_value = strength
        self.mapping.inputs["Location"].default_value = offset
        self.noise.inputs["Scale"].default_value = noise_scale


def setup_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    try:
        prefs.compute_device_type = "OPTIX"
        prefs.get_devices()
        for d in prefs.devices:
            d.use = d.type == "OPTIX"
        scene.cycles.device = "GPU"
    except Exception as ex:   # ohne passende Grafikkarte rechnet die CPU (langsamer, gleiches Ergebnis)
        print("GPU nicht verfügbar, nutze CPU:", ex)
    scene.cycles.samples = 64
    scene.cycles.use_denoising = True
    scene.render.resolution_x = RENDER_SIZE
    scene.render.resolution_y = RENDER_SIZE
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"

    world = bpy.data.worlds.new("Black")
    world.color = (0.0, 0.0, 0.0)
    scene.world = world
    if world.node_tree is not None:
        bg = world.node_tree.nodes.get("Background")
        if bg is not None:
            bg.inputs["Strength"].default_value = 0.0

    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = ORTHO_SCALE
    cam = bpy.data.objects.new("Cam", cam_data)
    cam.location = (0.0, -6.0, 0.0)
    cam.rotation_euler = (math.radians(90.0), 0.0, 0.0)   # blickt entlang +Y
    scene.collection.objects.link(cam)
    scene.camera = cam

    bpy.ops.mesh.primitive_cube_add(size=2.4)
    domain = bpy.context.active_object
    mat = bpy.data.materials.new("Fire")
    if hasattr(mat, "use_nodes"):
        mat.use_nodes = True
    domain.data.materials.append(mat)
    return scene, FireShader(mat)


def render_frames(scene, shader, params, tmp_dir, prefix):
    paths = []
    for i in range(FRAMES):
        shader.set(**params(i))
        path = os.path.join(tmp_dir, "%s_%02d.png" % (prefix, i))
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        paths.append(path)
    return paths


def assemble(paths, out_path):
    """Bild 0 oben links, zeilenweise nach rechts unten (Reihenfolge der Godot-Partikel-Flipbooks)."""
    sheet = np.zeros((ROWS * CELL, COLS * CELL, 4), dtype=np.float32)
    for i, path in enumerate(paths):
        img = bpy.data.images.load(path)
        img.scale(CELL, CELL)
        px = np.array(img.pixels[:], dtype=np.float32).reshape(CELL, CELL, 4)   # Zeilen von unten nach oben
        row, col = divmod(i, COLS)
        y0 = (ROWS - 1 - row) * CELL
        sheet[y0:y0 + CELL, col * CELL:(col + 1) * CELL] = px
        bpy.data.images.remove(img)
    sheet[..., 3] = 1.0
    out = bpy.data.images.new(os.path.basename(out_path), COLS * CELL, ROWS * CELL, alpha=True)
    out.pixels = sheet.ravel()
    out.filepath_raw = out_path
    out.file_format = "PNG"
    out.save()
    print("Sheet gespeichert:", out_path)


def loop_params(i):
    phase = math.tau * i / FRAMES
    # Kreisbahn in Höhe und Tiefe: Flammen wallen und steigen, Bild 64 = Bild 0
    return {"radius": 0.62, "gain": 1.0, "breakup": 1.3, "strength": 10.0,
            "offset": (0.0, 0.6 * math.sin(phase), 0.6 * math.cos(phase)), "noise_scale": 1.8}


def explosion_params(i):
    t = i / (FRAMES - 1)
    grow = 1.0 - (1.0 - t) ** 4
    cool = (1.0 - t) ** 0.9
    # schnell aufblähen, dann zerreißen die Flammen (mehr Rauschanteil) und kühlen ab
    return {"radius": 0.22 + 0.46 * grow, "gain": 2.2 * cool, "breakup": 0.7 + 0.7 * t,
            "strength": 8.0 + 8.0 * cool, "offset": (0.0, 0.3 * t, 0.8 * t), "noise_scale": 2.6 - 1.0 * t}


SHEETS = {"fire_loop": loop_params, "fire_explosion": explosion_params}


def main():
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    os.makedirs(OUT_DIR, exist_ok=True)
    scene, shader = setup_scene()
    tmp_dir = tempfile.mkdtemp(prefix="flipbook_")
    try:
        for name, params in SHEETS.items():
            if only and name not in only:
                continue
            paths = render_frames(scene, shader, params, tmp_dir, name)
            assemble(paths, os.path.join(OUT_DIR, name + ".png"))
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


main()
