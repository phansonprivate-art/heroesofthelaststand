class_name VfxLayer
extends Node3D
## Visuelle Effekte (reine Darstellung) im Stil klassischer Fantasy-Strategiespiele:
## eigene Blender-Texturen (Feuer, Energie, Rauch, Druckwelle, Runenkreis, Lichtsäule, Funkeln, Blitz,
## Eiskristalle) und texturierte Partikel (Kenney Particle Pack, CC0), Bodenzeichen, Schlagbögen,
## Meteore, Geschoss-Schweife, dazu Zustandseffekte direkt an Einheiten
## (Betäubungssterne, Frost, Gift, Spott, Schutz) und ein Schimmer unter jedem Helden.
## Gleichzeitig aktive Einmal-Effekte sind begrenzt, alles räumt sich selbst auf und pausiert mit dem Spiel.

const MAX_ACTIVE := 90
const TEX_DIR := "res://assets/effects/particles/"
## Eigene Texturen aus Blender: tools/blender_fire_flipbooks.py und tools/blender_effect_textures.py
const FLIPBOOK_DIR := "res://assets/effects/flipbooks/"
const FLIPBOOK_FRAMES := 8                                 ## je Zeile und Spalte (8 x 8 Bilder)
const ICE_SHARDS := "res://assets/models/effects/ice_shards.glb"
const KNIFE_SOURCE := "res://assets/models/heroes/Rogue_Hooded.glb"   ## Wurfmesser = Messer des Schattens

var _active := 0
var _soft_tex: Texture2D
var _materials: Dictionary = {}     ## "textur|additiv|billboard|farbe" -> Material
var _textures: Dictionary = {}
var _quad: QuadMesh
var _shard_meshes: Array[Mesh] = []
var _ice_material: StandardMaterial3D
var _knife_mesh: Mesh
var _knife_basis := Basis.IDENTITY   ## legt die Klinge waagerecht
var _camera_rig: Node                ## Kamerastoß beim großen Eis-Einschlag (aus bind)


func _ready() -> void:
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	_soft_tex = tex
	_quad = QuadMesh.new()
	_quad.size = Vector2.ONE


func bind(m: MatchController) -> void:
	_camera_rig = m.camera_rig
	m.spawner.enemy_spawned.connect(func(e: Enemy) -> void:
		smoke(e.global_position + Vector3(0, 0.3, 0), Color(0.3, 0.26, 0.22, 0.8), 1.0, 1.0, 14, "dirt_02")
		decal(e.global_position, "scorch_03", 1.4, Color(0.1, 0.08, 0.06, 0.6), 2.0, 0.0, false)
		track_unit(e))
	m.spawner.enemy_killed.connect(func(e: Enemy, _i: DamageInfo) -> void:
		burst(e.global_position + Vector3(0, 1.0, 0), Color(0.95, 0.92, 0.85), 14, 4.0, 0.55, 0.7, {"gravity": Vector3(0, -12, 0), "glow": false, "tex": "dirt_02"})
		burst(e.global_position + Vector3(0, 1.2, 0), Color(0.6, 0.9, 1.0, 0.8), 3, 1.5, 0.6, 1.4, {"gravity": Vector3(0, 2.0, 0), "spread": 15.0, "tex": "flare_01"}))
	m.combat.damage_applied.connect(_on_damage)
	for hero in m.heroes:
		track_hero(hero)


func track_hero(hero: Hero) -> void:
	_hero_glow(hero)
	track_unit(hero)
	hero.leveled_up.connect(func(h: Hero, _l: int) -> void:
		# Mehrere Aufstiege auf einmal (viel XP) zeigen nur einen Effekt
		var now := Time.get_ticks_msec()
		if now - int(h.get_meta("vfx_level_ms", -100000)) < 500:
			return
		h.set_meta("vfx_level_ms", now)
		beam(h.global_position, Color(1.0, 0.85, 0.35), 2.0, 9.0, 1.1, "light_rays")
		decal(h.global_position, "rune_circle", 2.2, Color(1.0, 0.85, 0.35, 0.9), 1.2, 0.5)
		sparkles(h.global_position + Vector3(0, 0.3, 0), Color(1.0, 0.9, 0.5), 26, 0.7, 1.3, 0.5, 3.0))


func _on_damage(target: Node3D, info: DamageInfo) -> void:
	if not is_instance_valid(target):
		return
	var source := info.source if info.source_is_valid() else null
	if target is DefenseCore:
		burst(target.global_position + Vector3(0, 3.0, 0), Color(0.5, 0.9, 1.0), 10, 5.0, 0.6, 0.5, {"gravity": Vector3(0, -8, 0), "tex": "spark_04"})
	elif info.is_crit:
		burst(target.global_position + Vector3(0, 1.2, 0), Color(1.0, 0.75, 0.3), 14, 6.0, 0.8, 0.35, {"gravity": Vector3.ZERO, "tex": "star_06"})
		slash(target.global_position + Vector3(0, 1.1, 0), randf() * TAU, Color(1.0, 0.85, 0.5), 2.2)
	elif source is Hero and target is Enemy and info.type == DamageInfo.Type.PHYSICAL:
		# kleiner Treffer-Funke je Schlag (Knochenstaub bei Skeletten)
		burst(target.global_position + Vector3(0, 1.1, 0), Color(1.0, 0.95, 0.85), 5, 3.0, 0.45, 0.25, {"gravity": Vector3(0, -6, 0), "tex": "spark_05"})


# --- Zustände an Einheiten ------------------------------------------------------

## Zeigt laufende Zustände direkt an der Einheit (Kinder der Einheit: bewegen sich mit und verschwinden mit ihr).
func track_unit(unit: Node3D) -> void:
	var status: StatusEffects = unit.get("status")
	if status == null:
		return
	status.effects_changed.connect(_update_status_fx.bind(unit))
	# Dauerhafte Aura aus den Gegnerdaten: "embers" = aufsteigende Glutfunken (Feuerdrache)
	var data: Variant = unit.get("data")
	if data is Dictionary and String(data.get("aura_fx", "")) == "embers":
		var r := maxf(0.6, float(data.get("body_radius", 0.0)))
		var p := _attached_emitter(unit, "spark_05", Color(1.0, 0.55, 0.15), Vector3(0, 1.3, 0), 28, 1.6, 0.17,
			Vector3(0, 1.6, 0), r)
		if unit.has_signal("died"):
			unit.connect("died", func(_u: Node, _i: DamageInfo) -> void:
				if is_instance_valid(p):
					p.emitting = false)


func _update_status_fx(unit: Node3D) -> void:
	if not is_instance_valid(unit):
		return
	var status: StatusEffects = unit.get("status")
	var fx: Dictionary = unit.get_meta("vfx_status", {})
	var wanted := {
		StatusEffects.STUN: status.is_stunned(),
		StatusEffects.SLOW: status.has(StatusEffects.SLOW),
		StatusEffects.POISON: status.has(StatusEffects.POISON),
		StatusEffects.BURN: status.has(StatusEffects.BURN),
		StatusEffects.TAUNT: status.has(StatusEffects.TAUNT),
		StatusEffects.DAMAGE_REDUCTION: status.damage_reduction() > 0.0,
	}
	for id in wanted:
		var has_fx: bool = fx.has(id) and is_instance_valid(fx[id])
		if wanted[id] and not has_fx:
			fx[id] = _make_status_fx(id, unit)
		elif not wanted[id] and has_fx:
			fx[id].queue_free()
			fx.erase(id)
	unit.set_meta("vfx_status", fx)


func _make_status_fx(id: String, unit: Node3D) -> Node3D:
	var data: Variant = unit.get("data")
	var head := 2.3 * (float(data.get("model_scale", 1.0)) if data is Dictionary else 1.0)
	match id:
		StatusEffects.STUN:
			# Klassisch: Sterne kreisen über dem Kopf
			var ring_node := Node3D.new()
			unit.add_child(ring_node)
			ring_node.position = Vector3(0, head + 0.2, 0)
			for i in 3:
				var star := MeshInstance3D.new()
				var q := QuadMesh.new()
				q.size = Vector2(0.35, 0.35)
				star.mesh = q
				star.material_override = _billboard_material("star_04", Color(1.0, 0.95, 0.4))
				star.position = Vector3(cos(i * TAU / 3.0), 0, sin(i * TAU / 3.0)) * 0.45
				star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				ring_node.add_child(star)
			ring_node.create_tween().set_loops().tween_property(ring_node, "rotation:y", TAU, 0.9).from(0.0)
			return ring_node
		StatusEffects.SLOW:
			return _attached_emitter(unit, "sparkle", Color(0.6, 0.85, 1.0, 0.9), Vector3(0, head * 0.6, 0), 10, 1.2, 0.4,
				Vector3(0, -0.8, 0), 0.6)
		StatusEffects.POISON:
			return _attached_emitter(unit, "circle_02", Color(0.45, 1.0, 0.3, 0.9), Vector3(0, head * 0.5, 0), 8, 1.1, 0.3,
				Vector3(0, 1.2, 0), 0.4)
		StatusEffects.BURN:
			return _attached_emitter(unit, "flame_03", Color(1.0, 0.5, 0.15, 0.9), Vector3(0, head * 0.45, 0), 14, 0.7, 0.45,
				Vector3(0, 2.2, 0), 0.35)
		StatusEffects.TAUNT:
			var mark := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(0.8, 0.8)
			mark.mesh = q
			mark.material_override = _billboard_material("flare_01", Color(1.0, 0.25, 0.15))
			mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			unit.add_child(mark)
			mark.position = Vector3(0, head + 0.3, 0)
			var t := mark.create_tween().set_loops()
			t.tween_property(mark, "scale", Vector3.ONE * 1.3, 0.3)
			t.tween_property(mark, "scale", Vector3.ONE * 0.8, 0.3)
			return mark
		StatusEffects.DAMAGE_REDUCTION:
			return _attached_emitter(unit, "sparkle", Color(1.0, 0.85, 0.4, 0.9), Vector3(0, 1.0, 0), 12, 1.0, 0.4,
				Vector3(0, 1.0, 0), 0.8)
	return Node3D.new()


func _attached_emitter(unit: Node3D, tex: String, color: Color, offset: Vector3, amount: int, lifetime: float, size: float,
		gravity: Vector3, radius: float) -> CPUParticles3D:
	var p := _particles(amount, lifetime, size, color, true, tex)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.gravity = gravity
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.4
	p.spread = 180.0
	unit.add_child(p)
	p.position = offset
	p.emitting = true
	return p


## Weicher Schimmer unter dem Helden in seiner Farbe, leicht pulsierend.
func _hero_glow(hero: Hero) -> void:
	var glow := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.6, 2.6)
	glow.mesh = q
	var mat := _flat_material("circle_05", true)
	mat.albedo_color = Color(hero.data.color, 0.55)
	glow.material_override = mat
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.rotation.x = -PI * 0.5
	glow.position.y = 0.04
	hero.add_child(glow)
	var t := glow.create_tween().set_loops()
	t.tween_property(glow, "scale", Vector3.ONE * 1.08, 1.2).set_trans(Tween.TRANS_SINE)
	t.tween_property(glow, "scale", Vector3.ONE * 0.95, 1.2).set_trans(Tween.TRANS_SINE)


# --- Bausteine ---------------------------------------------------------------

## Partikel-Explosion. opts: tex (Textur aus dem Partikelpaket), gravity, spread (Grad), up (Richtung),
## flat (in der Bodenebene), glow (additiv leuchtend, Standard true), radius (Emissionskugel)
func burst(pos: Vector3, color: Color, amount := 24, speed := 4.0, size := 0.25, lifetime := 0.6, opts := {}) -> void:
	if not _reserve():
		return
	var p := _particles(amount, lifetime, size, color, bool(opts.get("glow", true)), String(opts.get("tex", "")))
	p.one_shot = true
	p.explosiveness = 0.95
	p.direction = opts.get("up", Vector3.UP)
	p.spread = float(opts.get("spread", 180.0))
	p.flatness = 1.0 if opts.get("flat", false) else 0.0
	p.gravity = opts.get("gravity", Vector3(0, -6, 0))
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.damping_min = speed * 0.5
	p.damping_max = speed * 1.0
	if opts.has("radius"):
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = float(opts.radius)
	_spawn(p, pos, lifetime + 0.3)


## Flaches Bodenzeichen (Runenkreis, Brandfleck, Frostfläche). spin = Umdrehungen pro Sekunde.
func decal(pos: Vector3, tex: String, radius: float, color: Color, duration: float, spin := 0.0, additive := true) -> void:
	if not _reserve():
		return
	var d := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 2.0)
	d.mesh = q
	var mat := _flat_material(tex, additive)
	mat.albedo_color = color
	d.material_override = mat
	d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(d)
	d.global_position = Vector3(pos.x, 0.06, pos.z)
	d.rotation = Vector3(-PI * 0.5, randf() * TAU, 0)
	d.scale = Vector3.ONE * radius * 0.6
	var tween := d.create_tween().set_parallel(true)
	tween.tween_property(d, "scale", Vector3.ONE * radius, minf(0.25, duration * 0.3)).set_ease(Tween.EASE_OUT)
	if spin != 0.0:
		tween.tween_property(d, "rotation:y", d.rotation.y + TAU * spin * duration, duration)
	tween.tween_property(mat, "albedo_color:a", 0.0, duration * 0.4).set_delay(duration * 0.6)
	tween.chain().tween_callback(_release.bind(d))


## Senkrechter Lichtstrahl (heiliges Licht, Segen, Levelaufstieg); dreht sich zur Kamera.
func beam(pos: Vector3, color: Color, width := 1.6, height := 8.0, duration := 0.9, tex := "light_01") -> void:
	if not _reserve():
		return
	var b := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(width, height)
	b.mesh = q
	var mat := _flat_material(tex, true)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.albedo_color = color
	b.material_override = mat
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(b)
	b.global_position = pos + Vector3(0, height * 0.5, 0)
	b.scale = Vector3(0.2, 1.0, 1.0)
	var tween := b.create_tween().set_parallel(true)
	tween.tween_property(b, "scale", Vector3.ONE, duration * 0.25).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, duration * 0.5).set_delay(duration * 0.5)
	tween.chain().tween_callback(_release.bind(b))


## Schlagbogen (Klingenhieb), waagerecht in Blickrichtung.
func slash(pos: Vector3, yaw: float, color: Color, size := 2.0, tex := "slash_03") -> void:
	if not _reserve():
		return
	var s := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	s.mesh = q
	var mat := _flat_material(tex, true)
	mat.albedo_color = color
	s.material_override = mat
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(s)
	s.global_position = pos
	s.rotation = Vector3(-PI * 0.5, yaw, 0)
	s.scale = Vector3.ONE * 0.6
	var tween := s.create_tween().set_parallel(true)
	tween.tween_property(s, "scale", Vector3.ONE * 1.15, 0.18).set_ease(Tween.EASE_OUT)
	tween.tween_property(s, "rotation:y", yaw + 0.9, 0.22)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.18).set_delay(0.1)
	tween.chain().tween_callback(_release.bind(s))


## Bodenring, der wächst und ausblendet; gleiche Radien = stehende Markierung (Vorwarnung).
func ring(pos: Vector3, from_radius: float, to_radius: float, color: Color, duration: float, thickness := 0.12) -> void:
	if not _reserve():
		return
	# Ringbreite in Metern etwa konstant halten (sonst wird ein 8-m-Ring fast 1 m breit)
	thickness = clampf(thickness * 2.0 / maxf(1.0, to_radius), 0.025, thickness)
	var r := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.0 - thickness
	torus.outer_radius = 1.0
	torus.rings = 48
	torus.ring_segments = 4
	r.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = color
	mat.no_depth_test = true
	mat.render_priority = 1
	r.material_override = mat
	r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(r)
	r.global_position = Vector3(pos.x, 0.08, pos.z)
	r.scale = Vector3(from_radius, 0.15, from_radius)
	var tween := r.create_tween().set_parallel(true)
	if not is_equal_approx(from_radius, to_radius):
		tween.tween_property(r, "scale", Vector3(to_radius, 0.15, to_radius), duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(mat, "albedo_color:a", 0.0, duration * 0.5).set_delay(duration * 0.5)
	tween.chain().tween_callback(_release.bind(r))


## Gefüllte Bodenfläche (z. B. Frostfläche, Rauchgebiet), blendet aus.
func disc(pos: Vector3, radius: float, color: Color, duration: float, tex := "circle_05") -> void:
	decal(pos, tex, radius * 1.2, color, duration, 0.0, false)


## Lichtsäule (Bastion): halbtransparenter Zylinder.
func pillar(pos: Vector3, color: Color, radius := 1.0, height := 6.0, duration := 0.8) -> void:
	if not _reserve():
		return
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius * 0.6
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 24
	cyl.cap_top = false
	cyl.cap_bottom = false
	m.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(color, 0.32)
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	m.global_position = pos + Vector3(0, height * 0.5, 0)
	m.scale = Vector3(0.3, 0.2, 0.3)
	var tween := m.create_tween().set_parallel(true)
	tween.tween_property(m, "scale", Vector3.ONE, duration * 0.3).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, duration * 0.6).set_delay(duration * 0.4)
	tween.chain().tween_callback(_release.bind(m))


## Blitz zwischen zwei Punkten: Blitz-Textur aus Blender (8 Varianten), zwei Lagen, flackert und verblasst.
func lightning(from: Vector3, to: Vector3, color: Color, duration := 0.25, width := 1.0) -> void:
	if not _reserve():
		return
	var cam := get_viewport().get_camera_3d()
	var root := Node3D.new()
	add_child(root)
	for layer in 2:
		var bolt := MeshInstance3D.new()
		bolt.mesh = _quad
		var mat := _flat_material("lightning", true)
		mat.albedo_color = color.lightened(0.35) if layer == 0 else color
		mat.uv1_scale = Vector3(0.5, 0.25, 1.0)
		_pick_bolt(mat)
		bolt.material_override = mat
		bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(bolt)
		bolt.global_transform = _bolt_transform(from, to, cam, width * (1.0 if layer == 0 else 1.5))
		# Flackern: zweimal eine andere Blitzform, dann ausblenden
		var tween := bolt.create_tween()
		tween.tween_interval(duration * 0.25)
		tween.tween_callback(_pick_bolt.bind(mat))
		tween.tween_interval(duration * 0.25)
		tween.tween_callback(_pick_bolt.bind(mat))
		tween.tween_property(mat, "albedo_color:a", 0.0, duration * 0.5)
	get_tree().create_timer(duration + 0.05, false).timeout.connect(_release.bind(root))
	burst(to, color, 10, 4.0, 0.5, 0.3, {"gravity": Vector3.ZERO, "tex": "spark_04"})


## Anhaltende Rauch-/Staubwolke.
func smoke(pos: Vector3, color: Color, radius: float, duration: float, amount := 40, tex := "smoke_04") -> void:
	if not _reserve():
		return
	var p := _particles(amount, minf(1.6, duration), radius * 1.1, color, false, tex)
	p.one_shot = duration <= 1.6
	p.explosiveness = 0.8 if p.one_shot else 0.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius * 0.7
	p.direction = Vector3.UP
	p.spread = 60.0
	p.gravity = Vector3(0, 0.6, 0)
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 1.0
	_spawn(p, pos, duration + 1.8)
	if not p.one_shot:
		var ref: WeakRef = weakref(p)   # schwache Referenz: die Wolke kann vorher mit der Runde verschwinden
		get_tree().create_timer(duration, false).timeout.connect(func() -> void:
			var cloud: CPUParticles3D = ref.get_ref()
			if cloud != null:
				cloud.emitting = false)


## Meteor: fällt in `time` Sekunden vom Himmel auf `to`, als Feuerkugel mit Flammenschweif, und explodiert.
func meteor(to: Vector3, color: Color, time := 0.6) -> void:
	if not _reserve():
		return
	var m := Node3D.new()
	add_child(m)
	var from := to + Vector3(4.0, 18.0, -3.0)
	m.global_position = from
	attach_fire(m, 1.5)
	var trail := fire_trail(0.8)
	trail.global_position = from
	var tween := m.create_tween()
	tween.tween_method(func(p: Vector3) -> void:
		m.global_position = p
		if is_instance_valid(trail):
			trail.global_position = p, from, to + Vector3(0, 0.3, 0), time).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(func() -> void:
		end_trail(trail)
		fire_explosion(to, 1.3)
		burst(to + Vector3(0, 0.4, 0), Color(1.0, 0.8, 0.4), 22, 8.0, 0.4, 0.6, {"gravity": Vector3(0, -10, 0), "tex": "spark_04"})
		decal(to, "scorch_01", 1.8, Color(0.12, 0.07, 0.04, 0.8), 2.5, 0.0, false)
		shockwave(to, 2.4, color, 0.4)
		_release(m))


## Leuchtender Schweif hinter einem bewegten Objekt (Geschosse, Meteore).
func attach_trail(target: Node3D, color: Color, size := 0.3, tex := "") -> void:
	var p := _particles(36, 0.35, size, color, true, tex)
	p.local_coords = false
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 0.3
	p.spread = 180.0
	target.add_child(p)


## Brennende Kugel an einem bewegten Objekt (Feuerball): mehrere versetzt laufende Feuer-Flipbooks
## und ein Glut-Hof. Verschwindet mit dem Objekt.
func attach_fire(target: Node3D, size := 1.3) -> void:
	var core := _flipbook_particles("fire_loop", true, 4, 0.5, size)
	core.local_coords = true   # fliegt mit dem Objekt, statt als Schweif zurückzubleiben
	core.preprocess = 0.5      # brennt schon im ersten Bild voll
	core.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	core.emission_sphere_radius = size * 0.08
	core.gravity = Vector3.ZERO
	core.initial_velocity_max = 0.0
	core.anim_speed_min = 0.22
	core.anim_speed_max = 0.3
	core.color_ramp = _ramp([[0.0, Color(1.0, 0.95, 0.85, 0.0)], [0.2, Color(1.0, 0.92, 0.8, 1.0)],
		[0.8, Color(1.0, 0.8, 0.6, 1.0)], [1.0, Color(1.0, 0.7, 0.4, 0.0)]])
	target.add_child(core)
	core.emitting = true
	var halo := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size * 2.4
	halo.mesh = q
	halo.material_override = _billboard_material("", Color(1.0, 0.42, 0.1, 0.55))
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	target.add_child(halo)


## Flammenschweif für Geschosse: Die Flammen bleiben in der Welt stehen, steigen auf und verglühen.
## Der Aufrufer bewegt den zurückgegebenen Knoten mit und beendet ihn mit end_trail.
func fire_trail(size := 1.0) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	var flames := _flipbook_particles("fire_loop", true, 70, 0.5, size * 1.1)
	flames.local_coords = false
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flames.emission_sphere_radius = size * 0.2
	flames.spread = 180.0
	flames.initial_velocity_min = 0.3
	flames.initial_velocity_max = 1.2
	flames.gravity = Vector3(0, 1.6, 0)
	flames.damping_min = 0.5
	flames.damping_max = 1.5
	flames.angular_velocity_min = -90.0
	flames.angular_velocity_max = 90.0
	flames.anim_speed_min = 0.3
	flames.anim_speed_max = 0.6
	flames.scale_amount_curve = _curve([[0.0, 0.5], [0.15, 1.0], [1.0, 0.2]])   # klein am Kopf, dann aufwallend
	flames.color_ramp = _ramp([[0.0, Color(1.0, 0.95, 0.8, 1.0)], [0.3, Color(1.0, 0.62, 0.22, 0.9)],
		[0.65, Color(0.9, 0.26, 0.05, 0.6)], [1.0, Color(0.4, 0.05, 0.0, 0.0)]])
	root.add_child(flames)
	var embers := _particles(30, 0.7, size * 0.14, Color(1.0, 0.75, 0.3), true, "spark_04")
	embers.local_coords = false
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	embers.emission_sphere_radius = size * 0.3
	embers.spread = 180.0
	embers.initial_velocity_min = 1.0
	embers.initial_velocity_max = 3.0
	embers.gravity = Vector3(0, 0.8, 0)
	root.add_child(embers)
	flames.emitting = true
	embers.emitting = true
	return root


## Beendet einen Schweif: keine neuen Flammen, die vorhandenen verglühen, danach wird aufgeräumt.
func end_trail(trail: Node3D, linger := 0.8) -> void:
	if not is_instance_valid(trail) or not trail.is_inside_tree():
		return
	for p in trail.get_children():
		if p is CPUParticles3D:
			(p as CPUParticles3D).emitting = false
	trail.get_tree().create_timer(linger, false).timeout.connect(trail.queue_free)


## Schwerer Feuerball (Feuerdrache): Flammenschweif fliegt in `time` Sekunden von `from` nach `to` (leichter Bogen).
## Den Einschlag (Explosion, Schaden) löst der Aufrufer aus.
func fire_bolt(from: Vector3, to: Vector3, time: float, size := 1.4) -> void:
	var trail := fire_trail(size)
	trail.global_position = from
	var mid := (from + to) * 0.5 + Vector3(0, 1.2, 0)
	var t := trail.create_tween()
	t.tween_method(func(u: float) -> void:
		if is_instance_valid(trail):
			trail.global_position = from.lerp(mid, u).lerp(mid.lerp(to, u), u), 0.0, 1.0, time)
	t.tween_callback(func() -> void: end_trail(trail, 0.5))


## Feuerexplosion: Flipbook-Explosion, kleinere Nebenexplosionen und ein Lichtblitz.
## radius = Wirkradius in Metern (die sichtbare Feuerkugel ist etwas kleiner).
func fire_explosion(pos: Vector3, radius: float) -> void:
	if not _reserve():
		return
	var size := radius * 2.2
	var center := pos + Vector3(0, size * 0.22, 0)   # Feuerkugel über dem Boden, nicht halb darin
	# CPUParticles3D lässt das Teilchen mit Startzeit 0 im ersten Durchlauf aus (einzelne Teilchen und
	# explosiveness 1.0 erscheinen nie): 3 Teilchen bei 0.95 ergeben zwei überlagerte Explosionen.
	var main := _flipbook_particles("fire_explosion", false, 3, 0.9, size)
	main.one_shot = true
	main.explosiveness = 0.95
	main.gravity = Vector3.ZERO
	main.initial_velocity_max = 0.0
	# getönt, damit die überlagerten Explosionen nicht zu Weiß verschmelzen: gelb -> orange -> rot
	main.color_ramp = _ramp([[0.0, Color(1.0, 0.82, 0.55)], [0.45, Color(1.0, 0.58, 0.28)], [1.0, Color(0.85, 0.3, 0.08)]])
	_spawn(main, center, 1.2)
	if _reserve():
		var side := _flipbook_particles("fire_explosion", false, 6, 0.75, size * 0.55)
		side.one_shot = true
		side.explosiveness = 0.85
		side.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		side.emission_sphere_radius = radius * 0.45
		side.spread = 70.0
		side.initial_velocity_min = 0.5
		side.initial_velocity_max = 2.0
		side.gravity = Vector3(0, 1.5, 0)
		side.anim_speed_min = 0.9
		side.anim_speed_max = 1.25
		side.color_ramp = _ramp([[0.0, Color(1.0, 0.62, 0.3, 0.8)], [1.0, Color(0.8, 0.25, 0.06, 0.7)]])
		_spawn(side, center, 1.1)
	_light_flash(center, Color(1.0, 0.6, 0.25), 5.0, maxf(3.0, radius * 3.0), 0.5)


## Energiestoß mit Strahlen (Blender-Bildfolge), in der Farbe der Fähigkeit: heilig, arkan, Heilung, Schatten, Gift.
func energy_burst(pos: Vector3, color: Color, size := 2.0, lifetime := 0.6) -> void:
	if not _reserve():
		return
	var p := _flipbook_particles("energy_burst", false, 3, lifetime, size)
	p.one_shot = true
	p.explosiveness = 0.95
	p.gravity = Vector3.ZERO
	p.initial_velocity_max = 0.0
	p.color_ramp = _ramp([[0.0, color.lightened(0.4)], [0.45, color], [1.0, Color(color, 0.0)]])
	_spawn(p, pos, lifetime + 0.3)


## Rauchwolke aus der Blender-Bildfolge, deckend gemischt (nicht leuchtend): Rauch, Schatten, Staub, Gift, Frostnebel.
## duration > 0 hält die Wolke so lange aufrecht; rise = Steiggeschwindigkeit.
func smoke_cloud(pos: Vector3, color: Color, radius: float, duration := 0.0, amount := 12, rise := 0.6) -> void:
	if not _reserve():
		return
	var lasting := duration > 0.0
	var lifetime := 2.2 if lasting else 1.6
	var p := _flipbook_particles("smoke_puff", false, amount, lifetime, radius * (1.7 if lasting else 1.5), BaseMaterial3D.BLEND_MODE_MIX)
	p.one_shot = duration <= 0.0
	p.explosiveness = 0.8 if p.one_shot else 0.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius * 0.6
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = rise * 0.4
	p.initial_velocity_max = rise
	p.gravity = Vector3(0, rise * 0.3, 0)
	p.damping_min = 0.3
	p.damping_max = 0.8
	p.angular_velocity_min = -25.0
	p.angular_velocity_max = 25.0
	# anhaltende Wolken spielen die Bildfolge langsamer ab: die Schwaden bleiben länger dicht
	p.anim_speed_min = 0.5 if lasting else 0.9
	p.anim_speed_max = 0.7 if lasting else 1.1
	p.color_ramp = _ramp([[0.0, Color(color, 0.0)], [0.12, color], [0.7, Color(color, color.a * 0.7)], [1.0, Color(color, 0.0)]])
	_spawn(p, pos, maxf(duration, 0.0) + lifetime + 0.4)
	if not p.one_shot:
		var ref: WeakRef = weakref(p)   # schwache Referenz: die Wolke kann vorher mit der Runde verschwinden
		get_tree().create_timer(duration, false).timeout.connect(func() -> void:
			var cloud: CPUParticles3D = ref.get_ref()
			if cloud != null:
				cloud.emitting = false)


## Druckwelle am Boden: Ring mit Schlieren (Blender), wächst schnell auf radius und blendet aus.
func shockwave(pos: Vector3, radius: float, color: Color, duration := 0.5) -> void:
	if not _reserve():
		return
	var d := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 2.0)
	d.mesh = q
	var mat := _flat_material("ring_wave", true)
	mat.albedo_color = color
	d.material_override = mat
	d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(d)
	d.global_position = Vector3(pos.x, 0.07, pos.z)
	d.rotation = Vector3(-PI * 0.5, randf() * TAU, 0)
	var full := radius / 0.84   # der Ring liegt bei 84 % der halben Bildbreite
	d.scale = Vector3.ONE * full * 0.12
	var tween := d.create_tween().set_parallel(true)
	tween.tween_property(d, "scale", Vector3.ONE * full, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(mat, "albedo_color:a", 0.0, duration * 0.6).set_delay(duration * 0.4)
	tween.chain().tween_callback(_release.bind(d))


## Aufsteigende Lichtfunken (Blender-Funkeln), die sich drehen und aufblinken.
func sparkles(pos: Vector3, color: Color, amount := 16, radius := 0.6, lifetime := 1.2, size := 0.45, rise := 2.5) -> void:
	if not _reserve():
		return
	var p := _particles(amount, lifetime, size, color, true, "sparkle")
	p.one_shot = true
	p.explosiveness = 0.6
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = rise * 0.5
	p.initial_velocity_max = rise
	p.gravity = Vector3.ZERO
	p.damping_min = rise * 0.3
	p.damping_max = rise * 0.6
	p.angular_velocity_min = -120.0
	p.angular_velocity_max = 120.0
	p.scale_amount_curve = _curve([[0.0, 0.0], [0.25, 1.0], [0.6, 0.7], [1.0, 0.0]])
	_spawn(p, pos, lifetime + 0.3)


## Eiskristalle (Blender-Modelle) brechen von innen nach außen aus dem Boden, stehen kurz und zerspringen.
func ice_shards(pos: Vector3, radius: float, count := 14, hold := 0.5) -> void:
	if _shard_meshes.is_empty():
		_load_shards()
	if _shard_meshes.is_empty() or not _reserve():
		return
	var root := Node3D.new()
	add_child(root)
	root.global_position = Vector3(pos.x, 0.0, pos.z)
	var grow := 0.14
	var spread := 0.18
	for i in count:
		var a := TAU * (i + randf() * 0.6) / count
		var dir := Vector3(cos(a), 0.0, sin(a))
		var r := radius * randf_range(0.4, 0.95)
		var shard := MeshInstance3D.new()
		shard.mesh = _shard_meshes[randi() % _shard_meshes.size()]
		shard.material_override = _ice_material
		root.add_child(shard)
		# nach außen gekippt (Drehachse = Tangente), dazu zufällig um die eigene Achse
		shard.basis = Basis(Vector3.UP.cross(dir).normalized(), deg_to_rad(randf_range(10.0, 30.0))) * Basis(Vector3.UP, randf() * TAU)
		shard.position = dir * r + Vector3(0, -0.05, 0)
		var s := randf_range(0.9, 1.6) * clampf(radius / 5.0, 0.7, 1.4)
		shard.scale = Vector3(s, 0.01, s)
		var t := shard.create_tween()
		t.tween_interval(r / radius * spread)
		t.tween_property(shard, "scale", Vector3.ONE * s, grow).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		t.tween_interval(hold)
		t.tween_property(shard, "scale", Vector3(s * 0.2, 0.01, s * 0.2), 0.3).set_ease(Tween.EASE_IN)
	get_tree().create_timer(spread + grow + hold + 0.35, false).timeout.connect(_release.bind(root))


## Wurfmesser fliegen kreisförmig nach außen und drehen sich dabei (Messer-Modell des Schattens).
func knife_fan(pos: Vector3, radius: float, color: Color, count := 12) -> void:
	if _knife_mesh == null:
		_load_knife()
	if _knife_mesh == null or not _reserve():
		return
	var root := Node3D.new()
	add_child(root)
	root.global_position = pos
	var flight := 0.28
	for i in count:
		var a := TAU * i / count + randf_range(-0.1, 0.1)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var pivot := Node3D.new()   # dreht sich um die Hochachse, das Messer liegt darin waagerecht
		root.add_child(pivot)
		pivot.position = dir * 0.4
		var knife := MeshInstance3D.new()
		knife.mesh = _knife_mesh
		knife.basis = _knife_basis.scaled(Vector3.ONE * 0.6)   # Modell ist 1,2 m lang (Chibi-Maßstab)
		knife.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(knife)
		attach_trail(pivot, color, 0.35, "flare_01")
		var t := pivot.create_tween().set_parallel(true)
		t.tween_property(pivot, "position", dir * radius, flight).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		t.tween_property(pivot, "rotation:y", randf() * TAU + TAU * 2.5, flight)
		t.chain().tween_property(pivot, "scale", Vector3.ONE * 0.01, 0.1)   # nicht 0: Transform muss umkehrbar bleiben
	get_tree().create_timer(flight + 0.2, false).timeout.connect(_release.bind(root))


## Ziel-Anzeige einer Linien-Fähigkeit: schmales Rechteck mit Pfeilspitze am Boden, blendet aus.
func line_indicator(from: Vector3, dir: Vector3, length: float, width: float, color: Color, duration := 0.5) -> void:
	if not _reserve():
		return
	var root := Node3D.new()
	add_child(root)
	root.global_position = Vector3(from.x, 0.06, from.z)
	root.rotation.y = atan2(-dir.x, -dir.z)   # lokal -Z zeigt in Wurfrichtung
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(color, 0.45)
	var arrow := maxf(0.8, width)
	var body_len := maxf(0.1, length - arrow)
	var verts := PackedVector3Array([
		Vector3(-width * 0.35, 0, 0), Vector3(width * 0.35, 0, 0), Vector3(width * 0.35, 0, -body_len),
		Vector3(-width * 0.35, 0, 0), Vector3(width * 0.35, 0, -body_len), Vector3(-width * 0.35, 0, -body_len),
		Vector3(-width * 0.6, 0, -body_len), Vector3(width * 0.6, 0, -body_len), Vector3(0, 0, -length),
	])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(m)
	var tween := root.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, duration).set_delay(duration * 0.3)
	tween.tween_callback(_release.bind(root))


## Vorwarnung eines Kegelangriffs (Eisfeuer-Odem): blasser Fächer am Boden, darin wächst ein zweiter Fächer vom
## Ursprung bis zum Rand – ist er voll, schlägt der Angriff zu.
func cone_indicator(from: Vector3, dir: Vector3, length: float, angle_deg: float, color: Color, duration: float) -> void:
	if not _reserve():
		return
	var root := Node3D.new()
	add_child(root)
	root.global_position = Vector3(from.x, 0.07, from.z)
	root.rotation.y = atan2(-dir.x, -dir.z)   # lokal -Z zeigt in Angriffsrichtung
	var half := deg_to_rad(angle_deg * 0.5)
	var verts := PackedVector3Array()
	var steps := 16
	for i in steps:
		var a0 := -half + 2.0 * half * i / steps
		var a1 := -half + 2.0 * half * (i + 1) / steps
		verts.append_array([Vector3.ZERO, Vector3(sin(a0), 0, -cos(a0)), Vector3(sin(a1), 0, -cos(a1))])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var fill_mat: StandardMaterial3D
	for layer in 2:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.no_depth_test = true
		mat.render_priority = 1
		mat.albedo_color = Color(color, 0.22 if layer == 0 else 0.4)
		var m := MeshInstance3D.new()
		m.mesh = mesh
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(m)
		m.scale = Vector3.ONE * (length if layer == 0 else 0.05)
		if layer == 1:
			fill_mat = mat
			m.create_tween().tween_property(m, "scale", Vector3.ONE * length, duration)
	var tween := root.create_tween()
	tween.tween_interval(duration)
	tween.tween_property(fill_mat, "albedo_color:a", 0.0, 0.25)
	tween.tween_callback(_release.bind(root))


# --- Eisangriff in acht Schritten ------------------------------------------------------------------------------
# Eisdrache (Eisfeuer-Odem): Zapfen fliegen aus dem Maul. Arcanist (Glacial Rift): Stacheln brechen aus dem Boden.
#   1 charge_up       Magie sammelt sich und bricht mit einem Blitz los (Farbe wählbar, auch für Feuer)
#   2–4 ice_spike_path Stacheln entlang der Bahn, je näher am Ziel desto größer, kleinere fächern zu den Seiten auf
#   5–6 ice_impact     Boden reißt um das Ziel auf, Brocken fliegen, großer Eiscluster, Lichtblitz, Kamerastoß
#   7 (in _spike)     Stacheln schmelzen von oben und zerspringen in Splitter
#   8 frost_linger    Schnee, Nebel und feines Glitzern bleiben in der Luft

const ICE_COLOR := Color(0.6, 0.88, 1.0)
const ICICLE_FLIGHT := 0.22   ## Flugzeit eines Zapfens vom Maul zum Boden (Schaden des Odems wartet darauf)


## 1. Aufladen: Funken strömen zum Punkt, ein Glühen wächst; nach `duration` bricht es mit einem Blitz los.
func charge_up(pos: Vector3, duration: float, size := 1.0, color := ICE_COLOR) -> void:
	if _reserve():
		var p := _particles(44, minf(duration, 0.7), 0.24 * size, color.lightened(0.3), true, "spark_05")
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 1.7 * size
		p.initial_velocity_min = 0.0
		p.initial_velocity_max = 0.3
		p.radial_accel_min = -16.0 * size   # zieht die Funken zur Mitte
		p.radial_accel_max = -11.0 * size
		p.gravity = Vector3.ZERO
		_spawn(p, pos, duration + 0.8)
		_stop_after(p, maxf(0.05, duration - 0.25))
	if _reserve():
		var glow := MeshInstance3D.new()
		glow.mesh = _quad
		var mat := _base_material("", true)   # weicher runder Verlauf: flare_01 hat nur einen winzigen Kern
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.billboard_keep_scale = true   # sonst ignoriert das Billboard die Skalierung und das Glühen wächst nicht
		mat.no_depth_test = true          # leuchtet auch, wenn das Maul im Kopf steckt
		mat.render_priority = 2
		mat.albedo_color = Color(color, 0.85)
		glow.material_override = mat
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(glow)
		glow.global_position = pos
		glow.scale = Vector3.ONE * 0.1
		var light := OmniLight3D.new()
		light.light_color = color
		light.light_energy = 0.0
		light.omni_range = 4.0 * size
		glow.add_child(light)
		var t := glow.create_tween()
		t.set_parallel(true)
		t.tween_property(glow, "scale", Vector3.ONE * 2.2 * size, duration).set_ease(Tween.EASE_IN)
		t.tween_property(light, "light_energy", 4.0, duration).set_ease(Tween.EASE_IN)
		t.chain().tween_property(glow, "scale", Vector3.ONE * 0.05, 0.12)
		t.tween_callback(_release.bind(glow))
	get_tree().create_timer(duration, false).timeout.connect(func() -> void:
		energy_burst(pos, color, 1.8 * size, 0.35)
		burst(pos, color.lightened(0.5), 16, 6.0 * size, 0.3, 0.4, {"gravity": Vector3.ZERO, "tex": "spark_05"})
		_light_flash(pos, color, 4.0, 7.0 * size, 0.3))


## 2.–4. Stachelbahn von `from` in Richtung `dir`: Hauptstacheln wachsen mit dem Abstand, kleinere fächern seitlich
## auf (spread_deg = Öffnungswinkel, mindestens 0,5 m Abstand). Die Front läuft mit `speed`; `start_delay` verschiebt
## alles (z. B. Aufladen). mouth: Zapfen fliegen erst aus dem Maul zu ihrem Platz (Eisdrache).
func ice_spike_path(from: Vector3, dir: Vector3, length: float, spread_deg: float, hold: float, speed := 22.0,
		mouth: Variant = null, start_delay := 0.0, start_dist := 1.0) -> void:
	if _shard_meshes.is_empty():
		_load_shards()
	if _shard_meshes.is_empty() or not _reserve():
		return
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	var side := flat.cross(Vector3.UP).normalized()
	var root := Node3D.new()
	add_child(root)
	root.global_position = Vector3(from.x, 0.0, from.z)
	var half := deg_to_rad(spread_deg * 0.5)
	var last := 0.0
	var d := start_dist
	while d <= length:
		var k := d / length
		var t := start_delay + (d - start_dist) / speed
		if mouth != null:
			_icicle(mouth as Vector3, root.global_position + flat * d, t)
			t += ICICLE_FLIGHT
		var size := lerpf(0.75, 2.0, k) * randf_range(0.9, 1.1)
		_spike(root, flat * d, flat, size, t, hold, true)
		# Seitenstacheln: je weiter vorn, desto mehr und desto weiter außen
		var count := 1 + int(k * 2.0)
		var reach := maxf(0.5, tan(half) * d)
		for j in count:
			for s in [-1.0, 1.0]:
				var lateral: float = s * reach * (j + 1) / count * randf_range(0.8, 1.05)
				var offset := flat * (d + randf_range(-0.3, 0.3)) + side * lateral
				var outward := (flat + side * signf(lateral) * 0.5).normalized()
				_spike(root, offset, outward, size * randf_range(0.4, 0.6), t + 0.04 * (j + 1), hold, false)
		last = t
		d += 1.0
	get_tree().create_timer(last + hold + 0.9, false).timeout.connect(_release.bind(root))


## Ein Stachel: bricht nach `delay` aus dem Boden (Spitze leicht nach vorn), steht `hold` Sekunden,
## 7. schmilzt dann von oben und zerspringt (große Stacheln mit Splittern).
func _spike(root: Node3D, local_pos: Vector3, lean_dir: Vector3, size: float, delay: float, hold: float, shatter: bool) -> void:
	var spike := MeshInstance3D.new()
	spike.mesh = _shard_meshes[randi() % _shard_meshes.size()]
	spike.material_override = _ice_material
	root.add_child(spike)
	var tilt_axis := Vector3.UP.cross(lean_dir).normalized()
	spike.basis = Basis(tilt_axis, deg_to_rad(randf_range(14.0, 30.0))) * Basis(Vector3.UP, randf() * TAU)
	spike.position = local_pos + Vector3(0, -0.08, 0)
	spike.scale = Vector3(size, 0.01, size)
	spike.visible = false
	var t := spike.create_tween()
	t.tween_interval(maxf(0.0, delay))
	t.tween_callback(func() -> void: spike.visible = true)
	t.tween_property(spike, "scale", Vector3.ONE * size, 0.11).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_interval(hold)
	if shatter:
		t.tween_callback(func() -> void:
			var top := spike.global_position + Vector3(0, 0.9 * size, 0)
			burst(top, Color(0.82, 0.96, 1.0), 10, 3.5, 0.3, 0.55, {"gravity": Vector3(0, -10, 0), "tex": "spark_05"}))
	t.tween_property(spike, "scale", Vector3(size * 0.85, 0.02, size * 0.85), 0.35).set_ease(Tween.EASE_IN)   # schmilzt von oben
	t.tween_callback(func() -> void: spike.visible = false)


## 2. Ein Eiszapfen fliegt aus dem Maul zum Boden (Spitze voraus) und verschwindet beim Aufschlag.
func _icicle(from: Vector3, to: Vector3, delay: float) -> void:
	var ice := MeshInstance3D.new()
	ice.mesh = _shard_meshes[randi() % _shard_meshes.size()]
	ice.material_override = _ice_material
	ice.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ice)
	ice.global_position = from
	var v := to - from
	if v.length() > 0.01:
		# Modell zeigt nach +Y: so drehen, dass +Y in Flugrichtung zeigt
		ice.basis = Basis.looking_at(v.normalized(), Vector3.UP if absf(v.normalized().y) < 0.99 else Vector3.RIGHT) * Basis(Vector3.RIGHT, -PI * 0.5)
	ice.scale = Vector3.ONE * 0.45
	ice.visible = false
	var t := ice.create_tween()
	t.tween_interval(maxf(0.0, delay))
	t.tween_callback(func() -> void: ice.visible = true)
	t.tween_property(ice, "global_position", to, ICICLE_FLIGHT).set_ease(Tween.EASE_IN)
	t.tween_callback(ice.queue_free)


## 5.–6. Einschlag: Boden reißt um das Ziel auf, Brocken fliegen. big = großer Abschluss mit Eiscluster,
## Lichtblitz, Kamerastoß und anhaltendem Frost (sonst nur Risse, Brocken und ein kleiner Kranz).
func ice_impact(pos: Vector3, radius: float, hold: float, delay := 0.0, big := true) -> void:
	var ground := Vector3(pos.x, 0.0, pos.z)
	get_tree().create_timer(maxf(0.01, delay), false).timeout.connect(func() -> void:
		_ground_cracks(ground, radius * 1.4, hold + 1.4)
		burst(ground + Vector3(0, 0.3, 0), Color(0.42, 0.38, 0.34), 16 if big else 8, 7.0, 0.4, 0.9,
			{"gravity": Vector3(0, -16, 0), "spread": 45.0, "glow": false, "tex": "dirt_02"})
		if not big:
			ice_shards(ground, radius, 7, hold)
			return
		ice_shards(ground, radius * 1.15, 16, hold)
		if _reserve():
			var cluster := Node3D.new()
			add_child(cluster)
			cluster.global_position = ground
			for i in 5:
				var a := TAU * i / 5.0 + randf() * 0.5
				var off := Vector3(cos(a), 0, sin(a)) * radius * randf_range(0.1, 0.45)
				_spike(cluster, off, off.normalized() if off.length() > 0.01 else Vector3.FORWARD,
					randf_range(2.2, 3.0), randf() * 0.06, hold, true)
			get_tree().create_timer(hold + 0.7, false).timeout.connect(_release.bind(cluster))
		energy_burst(ground + Vector3(0, 1.0, 0), ICE_COLOR, radius * 1.4, 0.45)
		shockwave(ground, radius * 1.6, ICE_COLOR, 0.45)
		_light_flash(ground + Vector3(0, 1.5, 0), ICE_COLOR, 7.0, radius * 4.0, 0.45)
		if _camera_rig != null and is_instance_valid(_camera_rig):
			_camera_rig.shake(0.35)
		frost_linger(ground, radius * 1.3, hold + 1.6))


## 8. Frost in der Luft: Nebel am Boden, langsam fallender Schnee und feines Glitzern.
func frost_linger(pos: Vector3, radius: float, duration: float) -> void:
	smoke_cloud(pos + Vector3(0, 0.4, 0), Color(0.86, 0.94, 1.0, 0.5), radius * 0.6, duration, 14, 0.2)
	if _reserve():
		var snow := _particles(40, 1.8, 0.13, Color(0.97, 0.99, 1.0, 0.95), true, "star_04")
		snow.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		snow.emission_box_extents = Vector3(radius, 0.3, radius)
		snow.direction = Vector3.DOWN
		snow.spread = 25.0
		snow.gravity = Vector3(0, -0.8, 0)
		snow.initial_velocity_min = 0.4
		snow.initial_velocity_max = 0.9
		_spawn(snow, pos + Vector3(0, 2.8, 0), duration + 2.0)
		_stop_after(snow, duration)
	if _reserve():
		var glitter := _particles(30, 1.3, 0.08, Color(0.7, 0.92, 1.0), true, "spark_05")
		glitter.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		glitter.emission_box_extents = Vector3(radius, 0.8, radius)
		glitter.gravity = Vector3(0, 0.25, 0)
		glitter.initial_velocity_min = 0.0
		glitter.initial_velocity_max = 0.2
		_spawn(glitter, pos + Vector3(0, 1.0, 0), duration + 1.5)
		_stop_after(glitter, duration)


## 5. Leuchtende Bodenrisse: gezackte Linien vom Zentrum nach außen (dunkler Spalt mit eisblauem Glimmen).
func _ground_cracks(pos: Vector3, radius: float, duration: float) -> void:
	if not _reserve():
		return
	var dark := PackedVector3Array()
	var glow := PackedVector3Array()
	for c in 9:
		var a := TAU * c / 9.0 + randf_range(-0.25, 0.25)
		var p := Vector3(cos(a), 0, sin(a)) * 0.25
		var segments := 5
		var length := radius * randf_range(0.6, 1.0)
		for s in segments:
			a += randf_range(-0.45, 0.45)
			var q := p + Vector3(cos(a), 0, sin(a)) * length / segments
			var w := lerpf(0.16, 0.03, float(s) / segments)
			_crack_quad(dark, p, q, w, 0.065)
			_crack_quad(glow, p, q, w * 0.45, 0.07)
			p = q
	var mesh := ArrayMesh.new()
	var mats: Array[StandardMaterial3D] = []
	for layer in [[dark, Color(0.05, 0.08, 0.13, 0.9), false], [glow, Color(0.55, 0.9, 1.0, 0.95), true]]:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = layer[0]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if layer[2] else BaseMaterial3D.BLEND_MODE_MIX
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_color = layer[1]
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
		mats.append(mat)
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	m.global_position = Vector3(pos.x, 0.0, pos.z)
	m.scale = Vector3(0.15, 1.0, 0.15)
	var t := m.create_tween().set_parallel(true)
	t.tween_property(m, "scale", Vector3.ONE, 0.14).set_ease(Tween.EASE_OUT)   # reißt schnell nach außen auf
	for mat in mats:
		t.tween_property(mat, "albedo_color:a", 0.0, duration * 0.4).set_delay(duration * 0.6)
	t.chain().tween_callback(_release.bind(m))


func _crack_quad(verts: PackedVector3Array, a: Vector3, b: Vector3, width: float, y: float) -> void:
	var p := (b - a).cross(Vector3.UP).normalized() * width * 0.5
	var lift := Vector3(0, y, 0)
	verts.append_array([a + p + lift, a - p + lift, b + p + lift, a - p + lift, b - p + lift, b + p + lift])


## Schneesturm: Nebelwand, schräg fallender Schnee und eine Frostfläche, solange der Sturm anhält.
func blizzard(pos: Vector3, radius: float, duration: float) -> void:
	smoke_cloud(pos + Vector3(0, 0.6, 0), Color(0.85, 0.92, 1.0, 0.7), radius * 0.75, duration, 30, 0.3)
	disc(pos, radius, Color(0.6, 0.85, 1.0, 0.35), duration)
	decal(pos, "rune_circle", radius * 0.9, Color(0.55, 0.85, 1.0, 0.5), duration, 0.15)
	if not _reserve():
		return
	var snow := _particles(90, 1.1, 0.2, Color(0.95, 0.98, 1.0, 0.95), true, "star_04")
	snow.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	snow.emission_box_extents = Vector3(radius * 0.8, 0.4, radius * 0.8)
	snow.direction = Vector3(0.5, -1.0, 0.2).normalized()   # Wind treibt den Schnee schräg
	snow.spread = 12.0
	snow.gravity = Vector3(0, -2.0, 0)
	snow.initial_velocity_min = 3.0
	snow.initial_velocity_max = 5.0
	_spawn(snow, pos + Vector3(-0.8, 4.0, 0), duration + 1.3)
	_stop_after(snow, duration)


## Dauerhaft sprühende Partikel nach `duration` abschalten (schwache Referenz: die Runde kann vorher enden).
func _stop_after(p: CPUParticles3D, duration: float) -> void:
	var ref: WeakRef = weakref(p)
	get_tree().create_timer(duration, false).timeout.connect(func() -> void:
		var node: CPUParticles3D = ref.get_ref()
		if node != null:
			node.emitting = false)


## Klingen-Wirbel am Boden um eine Einheit (zeigt den Radius): drehender Druckwellen-Ring und drei flache
## Klingenbögen in Hüfthöhe. Bewegt sich mit der Einheit; der Aufrufer entfernt den zurückgegebenen Knoten.
func blade_vortex(unit: Node3D, radius: float, color: Color, turns_per_second := 2.5) -> Node3D:
	var root := Node3D.new()
	unit.add_child(root)
	var ring := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 2.0)
	ring.mesh = q
	var ring_mat := _flat_material("ring_wave", true)
	ring_mat.albedo_color = Color(color, 0.75)
	ring.material_override = ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.rotation.x = -PI * 0.5
	ring.position.y = 0.07
	ring.scale = Vector3.ONE * radius / 0.84   # der Ring liegt bei 84 % der halben Bildbreite
	root.add_child(ring)
	var blades := Node3D.new()
	blades.position.y = 0.9
	root.add_child(blades)
	for i in 3:
		var b := MeshInstance3D.new()
		var bq := QuadMesh.new()
		bq.size = Vector2.ONE * radius * 1.6
		b.mesh = bq
		var mat := _flat_material("slash_02", true)
		mat.albedo_color = Color(color.lightened(0.3), 0.9)
		b.material_override = mat
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.rotation = Vector3(-PI * 0.5, i * TAU / 3.0, 0)
		blades.add_child(b)
	# Ring und Klingen drehen sich gegenläufig, die Klingen schneller
	root.create_tween().set_loops().tween_property(ring, "rotation:y", -TAU, 1.0 / turns_per_second).from(0.0)
	root.create_tween().set_loops().tween_property(blades, "rotation:y", TAU, 0.6 / turns_per_second).from(0.0)
	return root


## Geworfenes Messer (Messer-Modell des Schattens): fliegt in `time` Sekunden von from nach to, dreht sich
## und sprüht beim Einschlag Funken.
func thrown_knife(from: Vector3, to: Vector3, color: Color, time := 0.16) -> void:
	if _knife_mesh == null:
		_load_knife()
	if _knife_mesh == null or not _reserve():
		return
	var pivot := Node3D.new()
	add_child(pivot)
	pivot.global_position = from
	var dir := to - from
	pivot.rotation.y = atan2(-dir.x, -dir.z)
	var knife := MeshInstance3D.new()
	knife.mesh = _knife_mesh
	knife.basis = _knife_basis.scaled(Vector3.ONE * 0.75)
	knife.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(knife)
	# heller Glanzpunkt am Messer: bei voller Geschwindigkeit sonst kaum zu sehen
	var glint := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	glint.mesh = q
	glint.material_override = _billboard_material("sparkle", color.lightened(0.4))
	glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(glint)
	attach_trail(pivot, color.lightened(0.2), 0.55, "flare_01")
	var t := pivot.create_tween().set_parallel(true)
	t.tween_property(pivot, "global_position", to, time)
	t.tween_property(pivot, "rotation:y", pivot.rotation.y + TAU * 1.5, time)
	t.chain().tween_callback(func() -> void:
		burst(to, color, 5, 3.0, 0.3, 0.2, {"gravity": Vector3.ZERO, "tex": "spark_05"})
		_release(pivot))


# --- intern ------------------------------------------------------------------

func _load_shards() -> void:
	if not ResourceLoader.exists(ICE_SHARDS):
		push_warning("Eiskristalle fehlen: %s" % ICE_SHARDS)
		return
	var scene: Node = (load(ICE_SHARDS) as PackedScene).instantiate()
	for m: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		_shard_meshes.append(m.mesh)
	scene.free()
	_ice_material = StandardMaterial3D.new()
	_ice_material.albedo_color = Color(0.72, 0.9, 1.0, 0.82)
	_ice_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ice_material.roughness = 0.15
	_ice_material.metallic_specular = 0.9
	_ice_material.emission_enabled = true
	_ice_material.emission = Color(0.35, 0.65, 1.0)
	_ice_material.emission_energy_multiplier = 0.8
	_ice_material.rim_enabled = true
	_ice_material.rim = 0.8
	_ice_material.rim_tint = 0.3


func _load_knife() -> void:
	if not ResourceLoader.exists(KNIFE_SOURCE):
		return
	var scene: Node = (load(KNIFE_SOURCE) as PackedScene).instantiate()
	# gleichnamiger Knochen-Anhänger liegt darüber: gezielt das Mesh suchen
	var found := scene.find_children("Knife", "MeshInstance3D", true, false)
	if not found.is_empty():
		_knife_mesh = (found[0] as MeshInstance3D).mesh
		# Klinge = längste Achse des Modells; sie wird auf die Waagerechte (x) gedreht
		var size := _knife_mesh.get_aabb().size
		if size.y >= size.x and size.y >= size.z:
			_knife_basis = Basis(Vector3.BACK, -PI * 0.5)
		elif size.z >= size.x:
			_knife_basis = Basis(Vector3.UP, PI * 0.5)
	scene.free()


func _pick_bolt(mat: StandardMaterial3D) -> void:
	var v := randi() % 8
	mat.uv1_offset = Vector3((v % 2) * 0.5, floori(v / 2.0) * 0.25, 0.0)


## Rechteck von from nach to (lokal x = Länge, y = Breite), zur Kamera gedreht.
func _bolt_transform(from: Vector3, to: Vector3, cam: Camera3D, width: float) -> Transform3D:
	var mid := (from + to) * 0.5
	var x := to - from
	var length := maxf(x.length(), 0.01)
	x /= length
	var view := (cam.global_position - mid) if cam != null else Vector3.UP
	var z := view - x * view.dot(x)
	if z.length_squared() < 0.0001:
		z = Vector3.UP.cross(x)
	z = z.normalized()
	return Transform3D(Basis(x * length, z.cross(x) * width, z), mid)

## Partikel mit Flipbook-Material (8 x 8 Bilder). Schleifen starten bei zufälligem Bild.
func _flipbook_particles(tex_name: String, loop: bool, amount: int, lifetime: float, size: float,
		blend := BaseMaterial3D.BLEND_MODE_ADD) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = maxi(1, amount)
	p.lifetime = maxf(0.05, lifetime)
	p.mesh = _quad
	p.material_override = _flipbook_material(tex_name, loop, blend)
	p.scale_amount_min = size * 0.85
	p.scale_amount_max = size
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.anim_offset_max = 1.0 if loop else 0.0
	p.anim_speed_min = 1.0   # einmal durch alle Bilder je Lebensdauer; Schleifen setzen langsamer
	p.anim_speed_max = 1.0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Gemeinsames Flipbook-Material je Bildfolge: additiv (Feuer, Energie) oder gemischt (Rauch),
## weich an Boden und Figuren (proximity fade).
func _flipbook_material(tex_name: String, loop: bool, blend := BaseMaterial3D.BLEND_MODE_ADD) -> Material:
	var key := "f|%s|%s|%d" % [tex_name, loop, blend]
	if not _materials.has(key):
		var path := FLIPBOOK_DIR + tex_name + ".png"
		var found := ResourceLoader.exists(path)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = blend
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.billboard_keep_scale = true   # sonst ignoriert Godot die Partikelgröße (alles 1 m groß)
		mat.particles_anim_h_frames = FLIPBOOK_FRAMES if found else 1
		mat.particles_anim_v_frames = FLIPBOOK_FRAMES if found else 1
		mat.particles_anim_loop = loop
		mat.vertex_color_use_as_albedo = true
		mat.proximity_fade_enabled = true
		mat.proximity_fade_distance = 0.6
		mat.albedo_texture = load(path) if found else _soft_tex
		_materials[key] = mat
	return _materials[key]


func _ramp(stops: Array) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(stops.map(func(s: Array) -> float: return s[0]))
	g.colors = PackedColorArray(stops.map(func(s: Array) -> Color: return s[1]))
	return g


## Bausteine für dauerhafte Effekte (z. B. am Brunnen der Erholung): nicht auf MAX_ACTIVE angerechnet,
## Platzierung und Aufräumen übernimmt der Aufrufer.
func make_particles(amount: int, lifetime: float, size: float, color: Color, tex := "") -> CPUParticles3D:
	return _particles(amount, lifetime, size, color, true, tex)


func make_flat_material(tex_name: String, additive := true) -> StandardMaterial3D:
	return _flat_material(tex_name, additive)


func make_curve(points: Array) -> Curve:
	return _curve(points)


func _curve(points: Array) -> Curve:
	var c := Curve.new()
	for pt in points:
		c.add_point(Vector2(pt[0], pt[1]))
	return c


func _light_flash(pos: Vector3, color: Color, energy: float, light_range: float, duration: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	add_child(light)
	light.global_position = pos
	var tween := light.create_tween()
	tween.tween_property(light, "light_energy", 0.0, duration).set_ease(Tween.EASE_OUT)
	tween.tween_callback(light.queue_free)


func _particles(amount: int, lifetime: float, size: float, color: Color, glow: bool, tex := "") -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = maxi(1, amount)
	p.lifetime = maxf(0.05, lifetime)
	p.mesh = _quad
	p.material_override = _particle_material(tex, glow)
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size
	p.angle_min = 0.0
	p.angle_max = 360.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(0.2, 1.0))
	curve.add_point(Vector2(1, 0.2))
	p.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, color)
	ramp.set_color(1, Color(color, 0.0))
	p.color_ramp = ramp
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Gemeinsames Partikelmaterial je Textur (Farbe kommt aus den Partikeln), additiv oder deckend.
func _particle_material(tex_name: String, additive: bool) -> Material:
	var key := "p|%s|%s" % [tex_name, additive]
	if not _materials.has(key):
		var mat := _base_material(tex_name, additive)
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.billboard_keep_scale = true   # sonst ignoriert Godot die Partikelgröße (alles 1 m groß)
		mat.vertex_color_use_as_albedo = true
		_materials[key] = mat
	return _materials[key]


## Gemeinsames Material für zur Kamera gedrehte Einzelbilder (Sterne, Markierungen) in fester Farbe.
func _billboard_material(tex_name: String, color: Color) -> Material:
	var key := "b|%s|%s" % [tex_name, color.to_html()]
	if not _materials.has(key):
		var mat := _base_material(tex_name, true)
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.albedo_color = color
		_materials[key] = mat
	return _materials[key]


## Eigenes Material für flache Flächen, deren Farbe/Transparenz einzeln animiert wird.
func _flat_material(tex_name: String, additive: bool) -> StandardMaterial3D:
	return _base_material(tex_name, additive)


func _base_material(tex_name: String, additive: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.albedo_texture = _texture(tex_name)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _texture(tex_name: String) -> Texture2D:
	if tex_name == "":
		return _soft_tex
	if not _textures.has(tex_name):
		var path := FLIPBOOK_DIR + tex_name + ".png"   # eigene Blender-Texturen zuerst, sonst Kenney-Paket
		if not ResourceLoader.exists(path):
			path = TEX_DIR + tex_name + ".png"
		_textures[tex_name] = load(path) if ResourceLoader.exists(path) else _soft_tex
	return _textures[tex_name]


func _spawn(p: CPUParticles3D, pos: Vector3, life: float) -> void:
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(life, false).timeout.connect(_release.bind(p))


func _reserve() -> bool:
	if _active >= MAX_ACTIVE:
		return false
	_active += 1
	return true


func _release(node: Node) -> void:
	_active = maxi(0, _active - 1)
	if is_instance_valid(node):
		node.queue_free()
