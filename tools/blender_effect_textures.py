"""Rendert die Effekt-Texturen der Fähigkeiten in Blender: prozedural, alles selbst erstellt.
Ergänzt tools/blender_fire_flipbooks.py (Feuer). Weiß bzw. graustufig gerendert, gefärbt wird im Spiel.

Bildfolgen (8 x 8 Bilder):
  smoke_puff.png    Rauchwolke, beleuchtet, mit Transparenz (Rauch, Schatten, Staub, Gift, Frostnebel)
  energy_burst.png  Energiestoß mit Strahlen, additiv (heilig, arkan, Heilung, Schatten, Gift)
Einzelbilder:
  ring_wave.png     Druckwellen-Ring mit Schlieren, von oben
  rune_circle.png   Runenkreis von oben
  light_rays.png    Lichtsäule mit Strahlen (unten hell, oben auslaufend)
  sparkle.png       vierstrahliges Funkeln
  lightning.png     8 Blitze (2 Spalten x 4 Zeilen), jeder läuft von links nach rechts durch sein Feld
Modelle:
  assets/models/effects/ice_shards.glb   6 Eiskristalle für Frost Nova

Aufruf (Blender 5.2, ohne Oberfläche):
  blender.exe --background --python tools/blender_effect_textures.py [-- name ...]
"""
import math
import os
import random
import shutil
import sys
import tempfile

import bmesh
import bpy
import numpy as np

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(PROJECT, "assets", "effects", "flipbooks")
MODEL_DIR = os.path.join(PROJECT, "assets", "models", "effects")
COLS = ROWS = 8
FRAMES = COLS * ROWS
CELL = 128


# --- Szene und Ausgabe ---------------------------------------------------------------------------

def reset_scene(width, height, ortho_scale, transparent=False, samples=48):
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
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = transparent
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA" if transparent else "RGB"
    world = bpy.data.worlds.new("World")
    scene.world = world
    set_world(world, (0.0, 0.0, 0.0), 0.0)
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = ortho_scale
    cam = bpy.data.objects.new("Cam", cam_data)
    cam.location = (0.0, -6.0, 0.0)
    cam.rotation_euler = (math.radians(90.0), 0.0, 0.0)   # blickt entlang +Y, Bildebene = XZ
    scene.collection.objects.link(cam)
    scene.camera = cam
    return scene


def set_world(world, color, strength):
    world.color = color
    if world.node_tree is not None:
        bg = world.node_tree.nodes.get("Background")
        if bg is not None:
            bg.inputs["Color"].default_value = (*color, 1.0)
            bg.inputs["Strength"].default_value = strength


def new_material(name):
    mat = bpy.data.materials.new(name)
    if hasattr(mat, "use_nodes"):
        mat.use_nodes = True
    mat.node_tree.nodes.clear()
    return mat


class Graph:
    """Kleine Hilfe für Shader-Knoten: Rechenknoten mit Zahl oder Verbindung als Eingang."""

    def __init__(self, mat):
        self.nodes = mat.node_tree.nodes
        self.link = mat.node_tree.links.new

    def node(self, kind, **props):
        n = self.nodes.new(kind)
        for k, v in props.items():
            setattr(n, k, v)
        return n

    def _input(self, socket, value):
        if isinstance(value, (int, float)):
            socket.default_value = value
        else:
            self.link(value, socket)

    def math(self, op, a, b=0.0, clamp=False):
        n = self.node("ShaderNodeMath", operation=op, use_clamp=clamp)
        self._input(n.inputs[0], a)
        self._input(n.inputs[1], b)
        return n.outputs[0]

    def map_range(self, value, from_min, from_max, to_min, to_max, clamp=True):
        n = self.node("ShaderNodeMapRange", clamp=clamp)
        self._input(n.inputs["Value"], value)
        self._input(n.inputs["From Min"], from_min)
        self._input(n.inputs["From Max"], from_max)
        self._input(n.inputs["To Min"], to_min)
        self._input(n.inputs["To Max"], to_max)
        return n.outputs["Result"]

    def noise(self, vector, scale, detail=4.0, roughness=0.6, distortion=0.3):
        n = self.node("ShaderNodeTexNoise")
        self.link(vector, n.inputs["Vector"])
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = roughness
        n.inputs["Distortion"].default_value = distortion
        return n

    def emission_out(self, strength, volume=False):
        em = self.node("ShaderNodeEmission")
        em.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
        self._input(em.inputs["Strength"], strength)
        out = self.node("ShaderNodeOutputMaterial")
        self.link(em.outputs["Emission"], out.inputs["Volume" if volume else "Surface"])


def render(scene, path):
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def assemble(paths, out_path, keep_alpha):
    """Bild 0 oben links, zeilenweise (Reihenfolge der Godot-Partikel-Flipbooks)."""
    sheet = np.zeros((ROWS * CELL, COLS * CELL, 4), dtype=np.float32)
    for i, path in enumerate(paths):
        img = bpy.data.images.load(path)
        img.scale(CELL, CELL)
        px = np.array(img.pixels[:], dtype=np.float32).reshape(CELL, CELL, 4)
        row, col = divmod(i, COLS)
        y0 = (ROWS - 1 - row) * CELL
        sheet[y0:y0 + CELL, col * CELL:(col + 1) * CELL] = px
        bpy.data.images.remove(img)
    if not keep_alpha:
        sheet[..., 3] = 1.0
    save_pixels(sheet, out_path)


def save_pixels(pixels, out_path):
    h, w = pixels.shape[:2]
    out = bpy.data.images.new(os.path.basename(out_path), w, h, alpha=True)
    out.pixels = pixels.ravel()
    out.filepath_raw = out_path
    out.file_format = "PNG"
    out.save()
    print("Gespeichert:", out_path)


def copy_render(src, out_path):
    shutil.copyfile(src, out_path)
    print("Gespeichert:", out_path)


def ease_out(t, power=3.0):
    return 1.0 - (1.0 - t) ** power


# --- Bildfolgen ----------------------------------------------------------------------------------

def volume_shape(g, coords, contrast_node_ref):
    """Kugel mit Rauschrand (wie beim Feuer): (1 - d/R) + (noise - 0.5) * breakup. Gibt Knoten zum Steuern zurück."""
    mapping = g.node("ShaderNodeMapping")
    g.link(coords, mapping.inputs["Vector"])
    noise = g.noise(mapping.outputs["Vector"], 2.2, detail=7.0, roughness=0.62, distortion=0.5)
    contrast = g.node("ShaderNodeMapRange", clamp=True)
    g.link(noise.outputs["Fac"], contrast.inputs["Value"])
    contrast.inputs["From Min"].default_value = 0.25
    contrast.inputs["From Max"].default_value = 0.75
    dist = g.node("ShaderNodeVectorMath", operation="LENGTH")
    g.link(coords, dist.inputs[0])
    falloff = g.node("ShaderNodeMapRange", clamp=False)
    g.link(dist.outputs["Value"], falloff.inputs["Value"])
    falloff.inputs["From Min"].default_value = 0.0
    falloff.inputs["To Min"].default_value = 1.0
    falloff.inputs["To Max"].default_value = 0.0
    breakup = g.node("ShaderNodeMath", operation="MULTIPLY")
    g.link(g.math("SUBTRACT", contrast.outputs["Result"], 0.5), breakup.inputs[0])
    shape = g.math("ADD", falloff.outputs["Result"], breakup.outputs[0])
    mask = g.map_range(dist.outputs["Value"], 0.78, 0.93, 1.0, 0.0)   # weich vor dem Bildrand ausblenden
    shape = g.math("MULTIPLY", shape, mask, clamp=True)
    return {"mapping": mapping, "noise": noise, "falloff": falloff, "breakup": breakup, "shape": shape}


def build_smoke(tmp):
    scene = reset_scene(256, 256, 1.9, transparent=True, samples=128)
    set_world(scene.world, (0.28, 0.29, 0.32), 1.0)   # Umgebungslicht für die Schattenseite
    sun_data = bpy.data.lights.new("Sun", "SUN")
    sun_data.energy = 5.0
    sun = bpy.data.objects.new("Sun", sun_data)
    sun.rotation_euler = (math.radians(35.0), math.radians(-25.0), 0.0)   # von oben links vorn
    scene.collection.objects.link(sun)
    bpy.ops.mesh.primitive_cube_add(size=2.4)
    domain = bpy.context.active_object
    mat = new_material("Smoke")
    domain.data.materials.append(mat)
    g = Graph(mat)
    coords = g.node("ShaderNodeTexCoord").outputs["Object"]
    s = volume_shape(g, coords, None)
    density = g.node("ShaderNodeMath", operation="MULTIPLY")
    g.link(s["shape"], density.inputs[0])
    vol = g.node("ShaderNodeVolumePrincipled")
    vol.inputs["Color"].default_value = (0.9, 0.9, 0.9, 1.0)
    vol.inputs["Anisotropy"].default_value = 0.25
    g.link(density.outputs[0], vol.inputs["Density"])
    out = g.node("ShaderNodeOutputMaterial")
    g.link(vol.outputs["Volume"], out.inputs["Volume"])
    paths = []
    for i in range(FRAMES):
        t = i / (FRAMES - 1)
        # quillt auf, dehnt sich aus, wird dünner und steigt
        s["falloff"].inputs["From Max"].default_value = 0.3 + 0.42 * ease_out(t, 2.5)
        s["breakup"].inputs[1].default_value = 0.8 + 0.5 * t
        s["mapping"].inputs["Location"].default_value = (0.0, 0.2 * t, 0.7 * t)
        s["noise"].inputs["Scale"].default_value = 2.4 - 0.8 * t
        density.inputs[1].default_value = 10.0 * (1.0 - t) ** 2.0   # löst sich bis zum Ende ganz auf
        path = os.path.join(tmp, "smoke_%02d.png" % i)
        render(scene, path)
        paths.append(path)
    assemble(paths, os.path.join(OUT_DIR, "smoke_puff.png"), keep_alpha=True)


def build_energy(tmp):
    scene = reset_scene(256, 256, 1.9, samples=48)
    bpy.ops.mesh.primitive_cube_add(size=2.4)
    domain = bpy.context.active_object
    mat = new_material("Energy")
    domain.data.materials.append(mat)
    g = Graph(mat)
    coords = g.node("ShaderNodeTexCoord").outputs["Object"]
    dist = g.node("ShaderNodeVectorMath", operation="LENGTH")
    g.link(coords, dist.inputs[0])
    direction = g.node("ShaderNodeVectorMath", operation="NORMALIZE")
    g.link(coords, direction.inputs[0])
    mapping = g.node("ShaderNodeMapping")
    g.link(direction.outputs["Vector"], mapping.inputs["Vector"])
    streak_noise = g.noise(mapping.outputs["Vector"], 5.0, detail=3.0, roughness=0.5, distortion=0.2)
    streak = g.map_range(streak_noise.outputs["Fac"], 0.48, 0.62, 0.0, 1.0)   # nur von der Richtung abhängig: Strahlen
    ring_dist = g.node("ShaderNodeMath", operation="SUBTRACT")
    g.link(dist.outputs["Value"], ring_dist.inputs[0])
    shell_abs = g.math("ABSOLUTE", ring_dist.outputs[0])
    shell = g.node("ShaderNodeMapRange", clamp=True)
    g.link(shell_abs, shell.inputs["Value"])
    shell.inputs["From Min"].default_value = 0.0
    shell.inputs["To Min"].default_value = 1.0
    shell.inputs["To Max"].default_value = 0.0
    rays = g.math("MULTIPLY", shell.outputs["Result"], g.math("ADD", g.math("MULTIPLY", streak, 0.9), 0.1))
    fade = g.node("ShaderNodeMath", operation="MULTIPLY")
    g.link(rays, fade.inputs[0])
    core = g.map_range(dist.outputs["Value"], 0.0, 0.3, 1.0, 0.0)
    flash = g.node("ShaderNodeMath", operation="MULTIPLY")
    g.link(core, flash.inputs[0])
    mask = g.map_range(dist.outputs["Value"], 0.8, 0.93, 1.0, 0.0)
    total = g.math("MULTIPLY", g.math("ADD", fade.outputs[0], flash.outputs[0]), mask)
    strength = g.math("MULTIPLY", total, 2.2)
    g.emission_out(strength, volume=True)
    paths = []
    for i in range(FRAMES):
        t = i / (FRAMES - 1)
        ring_dist.inputs[1].default_value = 0.08 + 0.78 * ease_out(t)   # Radius der Stoßwelle
        shell.inputs["From Max"].default_value = 0.04 + 0.12 * t           # Breite
        fade.inputs[1].default_value = (1.0 - t) ** 1.2
        flash.inputs[1].default_value = max(0.0, 1.0 - t * 4.0) * 1.5      # heller Kern ganz am Anfang
        mapping.inputs["Location"].default_value = (0.0, 0.0, 0.25 * t)
        path = os.path.join(tmp, "energy_%02d.png" % i)
        render(scene, path)
        paths.append(path)
    assemble(paths, os.path.join(OUT_DIR, "energy_burst.png"), keep_alpha=False)


# --- Einzelbilder (Flächen mit Leucht-Shader) ----------------------------------------------------

def emissive_plane(scale_xy=(1.0, 1.0)):
    bpy.ops.mesh.primitive_plane_add(size=2.0)
    plane = bpy.context.active_object
    plane.rotation_euler = (math.radians(90.0), 0.0, 0.0)   # zur Kamera (Objektkoordinaten bleiben x/y)
    plane.scale = (scale_xy[0], scale_xy[1], 1.0)
    mat = new_material("Plane")
    plane.data.materials.append(mat)
    return Graph(mat)


def build_ring(tmp):
    scene = reset_scene(1024, 1024, 2.0, samples=32)
    g = emissive_plane()
    coords = g.node("ShaderNodeTexCoord").outputs["Object"]
    dist = g.node("ShaderNodeVectorMath", operation="LENGTH")
    g.link(coords, dist.inputs[0])
    wisp = g.noise(coords, 7.0, detail=6.0, roughness=0.65, distortion=0.8)
    wisp_c = g.map_range(wisp.outputs["Fac"], 0.3, 0.72, 0.15, 1.0)
    ring = g.map_range(g.math("ABSOLUTE", g.math("SUBTRACT", dist.outputs["Value"], 0.84)), 0.0, 0.1, 1.0, 0.0)
    ring = g.math("POWER", ring, 1.6)
    trail = g.map_range(dist.outputs["Value"], 0.45, 0.84, 0.0, 0.35)   # Nachleuchten innen
    trail = g.math("MULTIPLY", trail, g.map_range(dist.outputs["Value"], 0.84, 0.86, 1.0, 0.0))
    total = g.math("MULTIPLY", g.math("ADD", ring, trail), wisp_c)
    g.emission_out(g.math("MULTIPLY", total, 1.15))
    path = os.path.join(tmp, "ring.png")
    render(scene, path)
    copy_render(path, os.path.join(OUT_DIR, "ring_wave.png"))


def build_light_rays(tmp):
    scene = reset_scene(256, 512, 4.0, samples=32)   # Hochformat: ortho_scale gilt für die Höhe
    g = emissive_plane((1.0, 2.0))
    coords = g.node("ShaderNodeTexCoord").outputs["Object"]
    sep = g.node("ShaderNodeSeparateXYZ")
    g.link(coords, sep.inputs[0])
    x_abs = g.math("ABSOLUTE", sep.outputs["X"])
    beam = g.math("POWER", g.map_range(x_abs, 0.0, 0.92, 1.0, 0.0), 2.2)
    top = g.math("POWER", g.map_range(sep.outputs["Y"], -1.0, 1.0, 1.0, 0.0), 0.9)
    bottom = g.map_range(sep.outputs["Y"], -1.0, -0.9, 0.0, 1.0)
    streak_coords = g.node("ShaderNodeCombineXYZ")
    g.link(g.math("MULTIPLY", sep.outputs["X"], 9.0), streak_coords.inputs["X"])
    g.link(g.math("MULTIPLY", sep.outputs["Y"], 0.35), streak_coords.inputs["Y"])
    streaks = g.map_range(g.noise(streak_coords.outputs["Vector"], 1.0, detail=3.0).outputs["Fac"], 0.35, 0.7, 0.45, 1.0)
    total = g.math("MULTIPLY", g.math("MULTIPLY", g.math("MULTIPLY", beam, top), bottom), streaks)
    g.emission_out(g.math("MULTIPLY", total, 1.1))
    path = os.path.join(tmp, "rays.png")
    render(scene, path)
    copy_render(path, os.path.join(OUT_DIR, "light_rays.png"))


def build_sparkle(tmp):
    scene = reset_scene(256, 256, 2.0, samples=32)
    g = emissive_plane()
    coords = g.node("ShaderNodeTexCoord").outputs["Object"]
    sep = g.node("ShaderNodeSeparateXYZ")
    g.link(coords, sep.inputs[0])

    def spike(along, across, length, width):
        a = g.math("POWER", g.map_range(g.math("ABSOLUTE", along), 0.0, length, 1.0, 0.0), 1.5)
        b = g.math("POWER", g.map_range(g.math("ABSOLUTE", across), 0.0, width, 1.0, 0.0), 3.0)
        return g.math("MULTIPLY", a, b)

    main = g.math("MAXIMUM", spike(sep.outputs["X"], sep.outputs["Y"], 0.95, 0.06), spike(sep.outputs["Y"], sep.outputs["X"], 0.95, 0.06))
    rot = g.node("ShaderNodeMapping")
    rot.inputs["Rotation"].default_value = (0.0, 0.0, math.radians(45.0))
    g.link(coords, rot.inputs["Vector"])
    sep2 = g.node("ShaderNodeSeparateXYZ")
    g.link(rot.outputs["Vector"], sep2.inputs[0])
    diag = g.math("MAXIMUM", spike(sep2.outputs["X"], sep2.outputs["Y"], 0.5, 0.05), spike(sep2.outputs["Y"], sep2.outputs["X"], 0.5, 0.05))
    dist = g.node("ShaderNodeVectorMath", operation="LENGTH")
    g.link(coords, dist.inputs[0])
    core = g.math("POWER", g.map_range(dist.outputs["Value"], 0.0, 0.35, 1.0, 0.0), 2.0)
    total = g.math("MAXIMUM", g.math("MAXIMUM", main, g.math("MULTIPLY", diag, 0.6)), core)
    g.emission_out(g.math("MULTIPLY", total, 1.2))
    path = os.path.join(tmp, "sparkle.png")
    render(scene, path)
    copy_render(path, os.path.join(OUT_DIR, "sparkle.png"))


# --- Geometrie: Runenkreis und Blitze --------------------------------------------------------------

def emission_material(name, strength):
    mat = new_material(name)
    Graph(mat).emission_out(strength)
    return mat


def _blur(img, sigma):
    """Gauß-Weichzeichner (getrennt nach Zeilen und Spalten)."""
    r = int(3 * sigma)
    x = np.arange(-r, r + 1, dtype=np.float32)
    k = np.exp(-(x * x) / (2.0 * sigma * sigma))
    k /= k.sum()
    tmp = np.apply_along_axis(lambda m: np.convolve(m, k, mode="same"), 1, img)
    return np.apply_along_axis(lambda m: np.convolve(m, k, mode="same"), 0, tmp)


def glow_pixels(path, layers):
    """Liest ein Bild der hellen Linien und legt weichen Schein darum: layers = [(sigma in Pixeln, Stärke), ...]."""
    img = bpy.data.images.load(path)
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    bpy.data.images.remove(img)
    lum = px[..., :3].max(axis=2)
    total = lum.copy()
    for sigma, weight in layers:
        total += _blur(lum, sigma) * weight
    out = np.ones((h, w, 4), dtype=np.float32)
    out[..., 0] = out[..., 1] = out[..., 2] = np.clip(total, 0.0, 1.0)
    return out


def poly(points, width, mat, closed=False):
    """Linienzug in der Bildebene (x, z) als Röhre: im orthografischen Bild eine saubere Linie."""
    curve = bpy.data.curves.new("Line", "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = width * 0.5
    curve.bevel_resolution = 2
    curve.use_fill_caps = True
    spline = curve.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for p, (x, z) in zip(spline.points, points):
        p.co = (x, 0.0, z, 1.0)
    spline.use_cyclic_u = closed
    obj = bpy.data.objects.new("Line", curve)
    obj.data.materials.append(mat)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def circle_points(radius, n=180):
    return [(radius * math.cos(math.tau * i / n), radius * math.sin(math.tau * i / n)) for i in range(n)]


def build_rune_circle(tmp):
    scene = reset_scene(1024, 1024, 2.05, samples=48)
    bright = emission_material("Bright", 1.0)
    rng = random.Random(7)
    shapes = []   # (punkte, breite, geschlossen)
    for r, w in [(0.97, 0.016), (0.94, 0.006), (0.79, 0.012), (0.42, 0.01), (0.18, 0.008)]:
        shapes.append((circle_points(r), w, True))
    # Hexagramm: zwei Dreiecke im inneren Ring
    for offset in (90.0, 270.0):
        tri = [(0.79 * math.cos(math.radians(offset + 120.0 * k)), 0.79 * math.sin(math.radians(offset + 120.0 * k))) for k in range(3)]
        shapes.append((tri, 0.009, True))
    # kleine Kreise an den Spitzen des Hexagramms
    for k in range(6):
        a = math.radians(90.0 + 60.0 * k)
        cx, cz = 0.6 * math.cos(a), 0.6 * math.sin(a)
        shapes.append(([(cx + 0.055 * math.cos(math.tau * i / 40), cz + 0.055 * math.sin(math.tau * i / 40)) for i in range(40)], 0.006, True))
    # Runenband: 24 Zeichen aus 2-4 Strichen auf einem 3 x 3-Raster (fester Zufall, immer gleich)
    glyphs = 24
    for k in range(glyphs):
        a0 = math.tau * k / glyphs
        def cell_point(u, v):
            ang = a0 + (u - 1) * (math.tau / glyphs) * 0.28
            rad = 0.865 + (v - 1) * 0.03
            return (rad * math.cos(ang), rad * math.sin(ang))
        for _ in range(rng.randint(2, 4)):
            u1, v1, u2, v2 = rng.randint(0, 2), rng.randint(0, 2), rng.randint(0, 2), rng.randint(0, 2)
            if (u1, v1) == (u2, v2):
                v2 = (v2 + 1) % 3
            shapes.append(([cell_point(u1, v1), cell_point(u2, v2)], 0.007, False))
    # Speichen zwischen innerem Kreis und Mitte
    for k in range(12):
        a = math.tau * k / 12
        shapes.append(([(0.2 * math.cos(a), 0.2 * math.sin(a)), (0.4 * math.cos(a), 0.4 * math.sin(a))], 0.005, False))
    for pts, w, closed in shapes:
        poly(pts, w, bright, closed)
    path = os.path.join(tmp, "rune.png")
    render(scene, path)
    save_pixels(glow_pixels(path, [(4.0, 0.8), (14.0, 0.45)]), os.path.join(OUT_DIR, "rune_circle.png"))


def jagged(a, b, depth, amplitude, rng):
    """Mittelpunktverschiebung: gezackte Linie von a nach b."""
    pts = [a, b]
    for level in range(depth):
        new = [pts[0]]
        for p, q in zip(pts, pts[1:]):
            mx, mz = (p[0] + q[0]) * 0.5, (p[1] + q[1]) * 0.5
            dx, dz = q[0] - p[0], q[1] - p[1]
            length = math.hypot(dx, dz) or 1.0
            off = rng.uniform(-1.0, 1.0) * amplitude * (0.55 ** level)
            new += [(mx - dz / length * off, mz + dx / length * off), q]
        pts = new
    return pts


def build_lightning(tmp):
    scene = reset_scene(512, 128, 2.0, samples=32)
    core = emission_material("Core", 1.0)
    cells = []
    for v in range(8):
        for obj in [o for o in bpy.data.objects if o.type == "CURVE"]:
            bpy.data.objects.remove(obj, do_unlink=True)
        rng = random.Random(100 + v)
        main = [(x, max(-0.2, min(0.2, z))) for x, z in jagged((-0.97, 0.0), (0.97, 0.0), 6, 0.16, rng)]
        bolts = [main]
        for _ in range(rng.randint(1, 3)):   # Seitenäste
            start = main[rng.randint(8, len(main) - 12)]
            ang = rng.uniform(0.35, 0.8) * rng.choice((-1, 1))
            length = rng.uniform(0.25, 0.5)
            end = (start[0] + math.cos(ang) * length, max(-0.22, min(0.22, start[1] + math.sin(ang) * length)))
            bolts.append(jagged(start, end, 4, 0.06, rng))
        for i, pts in enumerate(bolts):
            poly(pts, 0.012 if i == 0 else 0.007, core)
        path = os.path.join(tmp, "bolt_%d.png" % v)
        render(scene, path)
        cells.append(glow_pixels(path, [(2.5, 0.9), (8.0, 0.5)]))   # Schein je Feld, damit nichts überläuft
    # 2 Spalten x 4 Zeilen, Feld 512 x 128 -> Blatt 1024 x 512
    sheet = np.zeros((512, 1024, 4), dtype=np.float32)
    for v, px in enumerate(cells):
        row, col = divmod(v, 2)
        y0 = (3 - row) * 128
        sheet[y0:y0 + 128, col * 512:(col + 1) * 512] = px
    save_pixels(sheet, os.path.join(OUT_DIR, "lightning.png"))


# --- Eiskristalle (Modelle) ----------------------------------------------------------------------

def build_ice_shards(_tmp):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    rng = random.Random(3)
    mat = bpy.data.materials.new("Ice")
    mat.diffuse_color = (0.7, 0.9, 1.0, 1.0)
    for i in range(6):
        radius = rng.uniform(0.1, 0.18)
        height = rng.uniform(0.55, 1.15)
        mesh = bpy.data.meshes.new("Shard_%d" % i)
        bm = bmesh.new()
        sides = 6
        base, top = [], []
        for k in range(sides):
            a = math.tau * k / sides + rng.uniform(-0.15, 0.15)
            r = radius * rng.uniform(0.85, 1.1)
            base.append(bm.verts.new((r * math.cos(a), r * math.sin(a), 0.0)))
            top.append(bm.verts.new((r * 0.8 * math.cos(a), r * 0.8 * math.sin(a), height * 0.72)))
        tip = bm.verts.new((rng.uniform(-0.03, 0.03), rng.uniform(-0.03, 0.03), height))
        for k in range(sides):
            n = (k + 1) % sides
            bm.faces.new((base[k], base[n], top[n], top[k]))
            bm.faces.new((top[k], top[n], tip))
        bm.faces.new(list(reversed(base)))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(mesh)
        bm.free()
        mesh.materials.append(mat)
        obj = bpy.data.objects.new("Shard_%d" % i, mesh)
        obj.location = (i * 0.6, 0.0, 0.0)
        obj.rotation_euler = (rng.uniform(-0.15, 0.15), rng.uniform(-0.15, 0.15), 0.0)
        bpy.context.scene.collection.objects.link(obj)
    os.makedirs(MODEL_DIR, exist_ok=True)
    out = os.path.join(MODEL_DIR, "ice_shards.glb")
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_yup=True)
    print("Gespeichert:", out)


BUILDERS = {
    "smoke_puff": build_smoke,
    "energy_burst": build_energy,
    "ring_wave": build_ring,
    "light_rays": build_light_rays,
    "sparkle": build_sparkle,
    "rune_circle": build_rune_circle,
    "lightning": build_lightning,
    "ice_shards": build_ice_shards,
}


def main():
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    os.makedirs(OUT_DIR, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix="effects_")
    try:
        for name, build in BUILDERS.items():
            if not only or name in only:
                build(tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


main()
