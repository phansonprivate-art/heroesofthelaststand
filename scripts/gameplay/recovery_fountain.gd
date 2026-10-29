class_name RecoveryFountain
extends Node3D
## Brunnen der Erholung hinter dem Kern: Helden im Wirkkreis regenerieren langsam Leben und Mana (Anteil ihres
## Maximums pro Sekunde, zusätzlich zur eigenen Regeneration). Im Kreis ist nur Bewegung möglich – keine
## Angriffe, keine Zauber (Zustand StatusEffects.SANCTUARY). Betreten und Verlassen verstärkt nichts: es gibt
## genau eine Rate je Held und Sekunde. Werte aus data/balance/game.json ("fountain").

signal hero_entered(hero: Hero)
signal hero_left(hero: Hero)

const MODEL := "res://assets/models/environment_custom/RecoveryFountain.glb"
const GLOW := Color(0.45, 0.85, 1.0)
const FEEDBACK_INTERVAL := 0.7     ## Sekunden zwischen den Funken an erholenden Helden
const STATUS_HOLD := 0.25          ## Zustand wird laufend erneuert und läuft kurz nach dem Verlassen aus

var radius := 4.0
var hp_per_second := 0.01
var mana_per_second := 0.01
var heroes: Array[Hero] = []
var _inside: Dictionary = {}       ## Hero -> true
var _vfx: VfxLayer
var _feedback_left := 0.0
var _ring: MeshInstance3D
var _light: OmniLight3D
var _crystal: Node3D               ## schwebender Kristall aus dem Blender-Modell (dreht sich langsam)
var _crystal_y := 0.0
var _time := 0.0


func setup(config: Dictionary, hero_list: Array[Hero], vfx: VfxLayer) -> void:
	radius = float(config.get("radius", radius))
	hp_per_second = float(config.get("hp_per_second", hp_per_second))
	mana_per_second = float(config.get("mana_per_second", mana_per_second))
	var pos: Array = config.get("position", [0.0, 0.0, 25.5])
	position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	heroes = hero_list
	_vfx = vfx
	process_physics_priority = -10   # vor den Helden rechnen: der Zustand gilt schon im Bild des Betretens
	_build_visuals()


func contains(point: Vector3) -> bool:
	return Vector2(point.x - global_position.x, point.z - global_position.z).length() <= radius


func is_inside(hero: Hero) -> bool:
	return _inside.has(hero)


func _physics_process(delta: float) -> void:
	_feedback_left -= delta
	var feedback := _feedback_left <= 0.0
	if feedback:
		_feedback_left = FEEDBACK_INTERVAL
	for hero in heroes:
		if not is_instance_valid(hero):
			continue
		if hero.is_alive() and contains(hero.global_position):
			hero.status.apply(StatusEffects.SANCTUARY, STATUS_HOLD, 0.0, self)
			# Quelle null: zählt wie die eigene Regeneration nicht als belohnbare Heilung
			var healed := hero.health.heal(hero.health.max_hp * hp_per_second * delta, null)
			var missing_mana := hero.stats.max_mana() - hero.mana
			if missing_mana > 0.0:
				hero.restore_mana(hero.stats.max_mana() * mana_per_second * delta)
			if not _inside.has(hero):
				_inside[hero] = true
				hero_entered.emit(hero)
			if feedback and _vfx != null and (healed > 0.0 or missing_mana > 0.0):
				_vfx.sparkles(hero.global_position + Vector3(0, 0.3, 0), GLOW, 6, 0.45, 1.0, 0.3, 1.6)
		elif _inside.has(hero):
			_inside.erase(hero)
			hero.status.remove(StatusEffects.SANCTUARY)   # sofort wieder kampfbereit
			hero_left.emit(hero)


func _process(delta: float) -> void:
	_time += delta
	if _ring != null:
		_ring.rotation.y += delta * 0.12
	if _light != null:
		_light.light_energy = 1.3 + 0.35 * sin(_time * 1.7)
	if _crystal != null:
		_crystal.rotation.y += delta * 0.8
		_crystal.position.y = _crystal_y + 0.05 * sin(_time * 1.3)


# --- Darstellung ----------------------------------------------------------------------------------------

func _build_visuals() -> void:
	if ResourceLoader.exists(MODEL):
		var model: Node3D = (load(MODEL) as PackedScene).instantiate()
		add_child(model)
		_crystal = model.find_child("Crystal", true, false) as Node3D
		if _crystal != null:
			_crystal_y = _crystal.position.y
	else:   # Platzhalter, falls das Blender-Modell fehlt
		var basin := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.2
		cyl.bottom_radius = 1.35
		cyl.height = 0.7
		basin.mesh = cyl
		basin.position.y = 0.35
		add_child(basin)
	# fester Körper: Helden laufen um das Becken herum
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 1.3
	cylinder.height = 2.0
	shape.shape = cylinder
	shape.position.y = 1.0
	body.add_child(shape)
	add_child(body)
	if _vfx == null:
		return
	# Wirkkreis am Boden: Runenkreis, langsam drehend, dazu ein schwacher Schimmer der ganzen Fläche
	_ring = _ground_quad("rune_circle", radius, Color(GLOW, 0.32), 0.03)
	_ground_quad("", radius, Color(GLOW, 0.07), 0.025)
	# aufsteigende Lichtfunken über dem Wasser
	var p := _vfx.make_particles(26, 2.4, 0.32, Color(0.75, 0.95, 1.0), "sparkle")
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.75
	p.direction = Vector3.UP
	p.spread = 15.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.1
	p.gravity = Vector3.ZERO
	p.scale_amount_curve = _vfx.make_curve([[0.0, 0.0], [0.25, 1.0], [0.7, 0.6], [1.0, 0.0]])
	p.position = Vector3(0, 1.35, 0)
	add_child(p)
	p.emitting = true
	_light = OmniLight3D.new()
	_light.light_color = GLOW
	_light.omni_range = radius + 2.5
	_light.position = Vector3(0, 1.6, 0)
	add_child(_light)


func _ground_quad(tex: String, size: float, color: Color, height: float) -> MeshInstance3D:
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(size * 2.0, size * 2.0)
	quad.mesh = mesh
	var mat := _vfx.make_flat_material(tex, true)
	mat.albedo_color = color
	quad.material_override = mat
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.rotation.x = -PI * 0.5
	quad.position.y = height
	add_child(quad)
	return quad
