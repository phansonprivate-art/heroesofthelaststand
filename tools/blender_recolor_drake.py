"""Färbt einen fertigen Drachen (glTF mit einer Textur) um, z. B. den Frostdrachen zum Feuerdrachen.
Mit --shift <von> <bis> <neu> wird nur ein Farbtonbereich gedreht (Morvath: Hexer mit grünem statt violettem Leuchten:
  --src assets/models/enemies_custom/AbyssHexer.glb --out assets/models/enemies_custom/MorvathHexer.glb --shift 0.68 0.92 0.33).

Ablauf: Modell mit Skelett und Animationen laden, die Textur Pixel für Pixel umfärben (dunkle Schuppen tiefrot,
helle Kristalle orange-gold), aus den hellen Stellen eine Leuchttextur bauen, etwas metallischen Glanz setzen
(„schimmernd“) und wieder exportieren. Skelett und Animationen bleiben unverändert.

  blender --background --python tools/blender_recolor_drake.py -- [--src <glb>] [--out <glb>]
"""
import sys

import bpy
import numpy as np

SRC_DEFAULT = "assets/models/enemies_custom/FrostDrake.glb"
OUT_DEFAULT = "assets/models/enemies_custom/FireDrake.glb"
HUE_DARK = 0.995      ## Farbton der dunklen Schuppen (kräftiges Rot)
HUE_BRIGHT = 0.07     ## Farbton der hellen Kristalle (Orange-Gold)
GLOW_FROM = 0.68      ## ab dieser Helligkeit leuchtet eine Stelle (nur die Zacken)
GLOW_STRENGTH = 1.6
METALLIC = 0.15       ## mehr wirkt ohne Umgebungsspiegelung dunkel und bräunlich
ROUGHNESS = 0.3


def args():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = {"src": SRC_DEFAULT, "out": OUT_DEFAULT, "shift": None}
    for i, k in enumerate(a):
        if k in ("--src", "--out") and i + 1 < len(a):
            opts[k[2:]] = a[i + 1]
        elif k == "--shift" and i + 3 < len(a):   # --shift <von> <bis> <neu>: nur diesen Farbton-Bereich umfärben
            opts["shift"] = (float(a[i + 1]), float(a[i + 2]), float(a[i + 3]))
    return opts


def shift_hues(img, lo, hi, to):
    """Nur gesättigte Pixel im Farbtonbereich lo..hi auf den Farbton `to` drehen (z. B. violettes Leuchten → grün);
    Knochen, Metall und dunkle Teile bleiben, wie sie sind. Für Varianten von Figuren (Morvath aus dem Hexer)."""
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    hue, sat, val = rgb_to_hsv(px[..., :3])
    sel = (hue >= lo) & (hue <= hi) & (sat > 0.2)
    new_h = np.where(sel, to, hue)
    rgb = hsv_to_rgb(new_h, sat, val)
    out = bpy.data.images.new(img.name + "_shift", w, h, alpha=True)
    out.pixels[:] = np.concatenate([rgb, px[..., 3:]], -1).ravel()
    out.file_format = "PNG"
    out.pack()
    print("Farbton %.2f–%.2f → %.2f: %d Pixel" % (lo, hi, to, int(sel.sum())))
    return out


def rgb_to_hsv(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx = rgb.max(-1)
    mn = rgb.min(-1)
    d = mx - mn
    h = np.zeros_like(mx)
    m = d > 1e-6
    rc = np.where(m, (mx - r) / np.where(m, d, 1), 0)
    gc = np.where(m, (mx - g) / np.where(m, d, 1), 0)
    bc = np.where(m, (mx - b) / np.where(m, d, 1), 0)
    h = np.where(r == mx, bc - gc, np.where(g == mx, 2.0 + rc - bc, 4.0 + gc - rc))
    h = np.where(m, (h / 6.0) % 1.0, 0.0)
    s = np.where(mx > 1e-6, d / np.where(mx > 1e-6, mx, 1), 0)
    return h, s, mx


def hsv_to_rgb(h, s, v):
    i = np.floor(h * 6.0).astype(int) % 6
    f = h * 6.0 - np.floor(h * 6.0)
    p = v * (1 - s)
    q = v * (1 - s * f)
    t = v * (1 - s * (1 - f))
    choices = [(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)]
    out = np.zeros(h.shape + (3,), dtype=np.float32)
    for k, (cr, cg, cb) in enumerate(choices):
        sel = i == k
        out[sel, 0] = cr[sel]
        out[sel, 1] = cg[sel]
        out[sel, 2] = cb[sel]
    return out


def recolor(img):
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    hue, sat, val = rgb_to_hsv(px[..., :3])
    k = np.clip((val - 0.15) / 0.75, 0.0, 1.0) ** 1.4          # 0 = dunkel, 1 = hell
    # Farbton von Rot (dunkel) nach Orange-Gold (hell); über 1.0 hinweg interpolieren
    kh = k ** 2.4   # Farbton bleibt lange rot, erst die hellsten Stellen werden orange-gold
    new_h = (HUE_DARK + ((HUE_BRIGHT + 1.0) - HUE_DARK) * kh) % 1.0
    new_s = np.clip(np.maximum(sat, 0.8) * (1.0 - 0.2 * k ** 3), 0.0, 1.0)   # satt rot; helle Kristalle etwas blasser (Glut)
    new_v = np.clip(0.03 + val * (0.95 + 0.35 * kh), 0.0, 1.0)               # dunkles Rot, helle Zacken bleiben hell
    rgb = hsv_to_rgb(new_h, new_s, new_v)
    albedo = bpy.data.images.new(img.name + "_fire", w, h, alpha=True)
    albedo.pixels[:] = np.concatenate([rgb, px[..., 3:]], -1).ravel()
    glow_mask = np.clip((val - GLOW_FROM) / (1.0 - GLOW_FROM), 0.0, 1.0)[..., None]
    glow = bpy.data.images.new(img.name + "_fire_glow", w, h, alpha=False)
    ember = np.array([1.0, 0.45, 0.12], np.float32)   # Leuchten Richtung Orange ziehen, sonst brennt es weiß aus
    glow.pixels[:] = np.concatenate([rgb * ember * glow_mask, np.ones((h, w, 1), np.float32)], -1).ravel()
    for im in (albedo, glow):
        im.file_format = "PNG"
        im.pack()
    return albedo, glow


def fcurves_of(action):
    """F-Kurven einer Aktion (Blender 5: Ebenen/Streifen/Kanalbeutel)."""
    out = []
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                out.extend(bag.fcurves)
    return out


def smooth_keys(t, keys):
    """Weich zwischen (t, Wert)-Paaren interpolieren (smoothstep je Abschnitt)."""
    if t <= keys[0][0]:
        return keys[0][1]
    for (t0, v0), (t1, v1) in zip(keys, keys[1:]):
        if t <= t1:
            u = (t - t0) / (t1 - t0)
            u = u * u * (3 - 2 * u)
            return v0 + (v1 - v0) * u
    return keys[-1][1]


## Schwanzschlag: Ausholen, Körper dreht sich in den Schlag, der Schwanz peitscht mit Verzögerung herum
## (Spitze am weitesten), Kopf und Hals drehen gegen, damit der Blick am Ziel bleibt.
SWIPE_FRAMES = 36     ## 1,5 s bei 24 Bildern/s; Treffer etwa bei der Hälfte
SWIPE_CURVE = [(0.0, 0.0), (0.25, -0.35), (0.5, 1.0), (0.62, 0.85), (1.0, 0.0)]
SWIPE_BONES = {"hips": (24.0, 0.0), "spine": (6.0, 0.01), "chest": (-4.0, 0.02),
               "neck1": (-8.0, 0.0), "neck2": (-8.0, 0.0), "head": (-6.0, 0.0)}
for _i in range(1, 8):
    SWIPE_BONES["tail%d" % _i] = (10.0 + 4.0 * _i, 0.03 * _i)   # (Grad, Verzögerung als Anteil der Länge)


def add_tail_swipe(arm):
    import math
    from mathutils import Quaternion, Vector
    base = bpy.data.actions.get("Idle")
    if base is None or "Tail_Swipe" in bpy.data.actions:
        return
    act = base.copy()
    act.name = "Tail_Swipe"
    curves = fcurves_of(act)
    frames = range(SWIPE_FRAMES + 1)
    # Alle Kurven auf 0..SWIPE_FRAMES kürzen (Stehen als Grundhaltung, Flügel angelegt)
    samples = {fc: [fc.evaluate(f) for f in frames] for fc in curves}
    by_path = {}
    for fc in curves:
        by_path.setdefault(fc.data_path, {})[fc.array_index] = fc
    bag = act.layers[0].strips[0].channelbags[0]
    for name, (deg, lag) in SWIPE_BONES.items():
        if name not in arm.data.bones:
            continue
        path = 'pose.bones["%s"].rotation_quaternion' % name
        quat_curves = by_path.get(path, {})
        for i in range(4):
            if i not in quat_curves:
                fc = bag.fcurves.new(path, index=i)
                quat_curves[i] = fc
                samples[fc] = [1.0 if i == 0 else 0.0 for _ in frames]
        rest = arm.data.bones[name].matrix_local.to_3x3()
        axis = (rest.inverted() @ Vector((0.0, 0.0, 1.0))).normalized()   # Hochachse im Ruheraum des Knochens
        for f in frames:
            t = max(0.0, f / SWIPE_FRAMES - lag)
            q = Quaternion([samples[quat_curves[i]][f] for i in range(4)])
            q = Quaternion(axis, math.radians(deg) * smooth_keys(t, SWIPE_CURVE)) @ q
            for i in range(4):
                samples[quat_curves[i]][f] = q[i]
    for fc, values in samples.items():
        fc.keyframe_points.clear()
        fc.keyframe_points.add(len(values))
        for f, v in zip(frames, values):
            fc.keyframe_points[f].co = (f, v)
            fc.keyframe_points[f].interpolation = "LINEAR"
        fc.update()
    act.frame_range = (0, SWIPE_FRAMES)
    print("Animation Tail_Swipe:", len(samples), "Kurven,", SWIPE_FRAMES + 1, "Bilder")


def main():
    o = args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=o["src"])
    done = set()
    for mat in bpy.data.materials:
        if not mat.use_nodes:
            continue
        nt = mat.node_tree
        bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
        tex = next((n for n in nt.nodes if n.type == "TEX_IMAGE" and n.image is not None), None)
        if bsdf is None or tex is None or tex.image.name in done:
            continue
        done.add(tex.image.name)
        if o["shift"] is not None:   # nur Farbton drehen, sonst nichts ändern
            tex.image = shift_hues(tex.image, *o["shift"])
            continue
        albedo, glow = recolor(tex.image)
        tex.image = albedo
        g = nt.nodes.new("ShaderNodeTexImage")
        g.image = glow
        nt.links.new(g.inputs["Vector"], tex.inputs["Vector"].links[0].from_socket) if tex.inputs["Vector"].links else None
        nt.links.new(g.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = GLOW_STRENGTH
        bsdf.inputs["Metallic"].default_value = METALLIC
        bsdf.inputs["Roughness"].default_value = ROUGHNESS
        for link in list(nt.links):   # feste Werte statt evtl. verknüpfter Metall-/Rauheitskarten
            if link.to_node == bsdf and link.to_socket.name in ("Metallic", "Roughness"):
                nt.links.remove(link)
        print("umgefärbt:", mat.name, tex.image.size[:])
    arm = next((ob for ob in bpy.data.objects if ob.type == "ARMATURE"), None)
    if arm is not None and o["shift"] is None:   # Schwanzschlag nur für den Drachen
        add_tail_swipe(arm)
    bpy.ops.export_scene.gltf(filepath=o["out"], export_format="GLB", export_animations=True,
                              export_image_format="JPEG", export_yup=True)
    print("exportiert:", o["out"])


if __name__ == "__main__":
    main()
