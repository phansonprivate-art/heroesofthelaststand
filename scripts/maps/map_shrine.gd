class_name MapShrine
extends Node3D
## Schrein am Flussufer: Der erste Held, der ihn verletzt oder mit fehlendem Mana berührt, bekommt einmalig einen
## Schub Leben und Mana (Anteil seines Maximums). Danach lädt der Schrein lange nach – er ist ein Notbehelf auf
## halbem Weg, kein Ersatz für den Brunnen der Erholung. Werte aus data/balance/game.json ("map_structures.shrine").

signal used(hero: Hero)

const GLOW := Color(0.36, 1.0, 0.66)

var radius := 2.2
var hp_ratio := 0.2
var mana_ratio := 0.2
var cooldown := 90.0
var heroes: Array[Hero] = []
var vfx: VfxLayer
var _left := 0.0
var _crystal: Node3D
var _crystal_y := 0.0
var _light: OmniLight3D
var _time := 0.0


func setup(config: Dictionary, model_scene: PackedScene) -> void:
	radius = float(config.get("radius", radius))
	hp_ratio = float(config.get("hp_ratio", hp_ratio))
	mana_ratio = float(config.get("mana_ratio", mana_ratio))
	cooldown = float(config.get("cooldown", cooldown))
	if model_scene != null:
		var model: Node3D = model_scene.instantiate()
		add_child(model)
		_crystal = model.find_child("Crystal", true, false) as Node3D
		if _crystal != null:
			_crystal_y = _crystal.position.y
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.9
	cyl.height = 2.0
	shape.shape = cyl
	shape.position.y = 1.0
	body.add_child(shape)
	add_child(body)
	_light = OmniLight3D.new()
	_light.light_color = GLOW
	_light.omni_range = 4.5
	_light.position.y = 2.0
	add_child(_light)


func bind(hero_list: Array[Hero], p_vfx: VfxLayer) -> void:
	heroes = hero_list
	vfx = p_vfx


func is_ready() -> bool:
	return _left <= 0.0


func cooldown_left() -> float:
	return maxf(0.0, _left)


func _physics_process(delta: float) -> void:
	if _left > 0.0:
		_left -= delta
		return
	for hero in heroes:
		if not is_instance_valid(hero) or not hero.is_alive():
			continue
		if Vector2(hero.global_position.x - global_position.x, hero.global_position.z - global_position.z).length() > radius:
			continue
		if hero.health.hp >= hero.health.max_hp and hero.mana >= hero.stats.max_mana():
			continue   # voller Held verbraucht den Schrein nicht
		_grant(hero)
		return


func _grant(hero: Hero) -> void:
	# Quelle null: zählt wie der Brunnen nicht als belohnbare Heilung
	hero.health.heal(hero.health.max_hp * hp_ratio, null)
	hero.restore_mana(hero.stats.max_mana() * mana_ratio)
	_left = cooldown
	if vfx != null:
		vfx.pillar(global_position, GLOW, 1.2, 5.0, 0.8)
		vfx.sparkles(hero.global_position + Vector3(0, 0.4, 0), GLOW, 24, 0.6, 1.2, 0.45, 2.5)
	used.emit(hero)


func _process(delta: float) -> void:
	_time += delta
	var charge := 1.0 - clampf(_left / maxf(cooldown, 0.01), 0.0, 1.0)
	if _crystal != null:
		_crystal.rotation.y += delta * (1.2 if is_ready() else 0.3)
		_crystal.position.y = _crystal_y - 0.6 * (1.0 - charge) + 0.08 * sin(_time * 1.6)
		_crystal.scale = Vector3.ONE * lerpf(0.4, 1.0, charge)
	_light.light_energy = (1.4 + 0.4 * sin(_time * 2.0)) if is_ready() else 0.25 * charge
