class_name MapStructure
extends StaticBody3D
## Bauwerk einer Karte (Wachturm, Torhaus): hat Leben und Rüstung, schießt auf Gegner in Reichweite, und Gegner
## greifen es an, wenn es in ihren Aggro-Radius kommt (Schaden wie gegen den Kern: structure_damage).
## Das Torhaus liegt auf einer Kollisionsebene, die nur Gegner aufhält: Helden gehen durch das Fallgitter,
## Gegner müssen es erst zerstören. Gefallene Bauwerke bleiben für die Runde zerstört.
## Werte aus data/balance/game.json ("map_structures").

signal destroyed(structure: MapStructure)

const BAR_SHADER := preload("res://assets/effects/health_bar.gdshader")

var kind := "tower"                ## "tower" oder "gate"
var display_name := ""
var radius := 1.4                  ## Abstand ab der Oberfläche: Mittelpunkt (Turm) bzw. Mauerlinie (Torhaus)
var half_length := 0.0             ## > 0: längliches Bauwerk, gemessen zur Strecke ±half_length entlang der lokalen X-Achse
var armor := 0.0
var attack_damage := 0.0
var attack_interval := 1.2
var attack_range := 9.0
var projectile_speed := 20.0
var projectile_color := Color(0.6, 0.85, 1.0)
var muzzle := Vector3(0, 6.4, 0)   ## Schussquelle (lokal)
var health: HealthComponent
var combat: CombatService
var spawner: EnemySpawner
var world: Node                    ## MatchController: Effekte; Geschosse lesen `world` für den Einschlag
var model: Node3D
var _cooldown := 0.0
var _crystal: Node3D
var _crystal_y := 0.0
var _portcullis: Node3D
var _light: OmniLight3D
var _bar: MeshInstance3D
var _time := 0.0


## config: Eintrag aus map_structures (tower/gate). model_scene: Blender-Modell (darf fehlen).
func setup(p_kind: String, config: Dictionary, model_scene: PackedScene, shape: Shape3D, shape_offset: Vector3) -> void:
	kind = p_kind
	display_name = String(config.get("name", kind))
	armor = float(config.get("armor", 0.0))
	attack_damage = float(config.get("damage", 0.0))
	attack_interval = float(config.get("attack_interval", 1.2))
	attack_range = float(config.get("attack_range", 9.0))
	projectile_speed = float(config.get("projectile_speed", 20.0))
	projectile_color = Color.html(String(config.get("color", "#9ad8ff")))
	health = HealthComponent.new()
	health.name = "Health"
	add_child(health)
	health.setup(float(config.get("hp", 1500.0)))
	health.died.connect(_on_died)
	health.changed.connect(_on_health_changed)
	if model_scene != null:
		model = model_scene.instantiate()
		add_child(model)
		_crystal = model.find_child("Crystal", true, false) as Node3D
		_portcullis = model.find_child("Portcullis", true, false) as Node3D
		if _crystal != null:
			_crystal_y = _crystal.position.y
			muzzle = _crystal.position
	var cs := CollisionShape3D.new()
	cs.name = "Collision"
	cs.shape = shape
	cs.position = shape_offset
	add_child(cs)
	_light = OmniLight3D.new()
	_light.light_color = projectile_color
	_light.light_energy = 1.2
	_light.omni_range = 5.0
	_light.position = muzzle
	add_child(_light)
	_bar = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.6, 0.24)
	_bar.mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = BAR_SHADER
	mat.set_shader_parameter("fill_color", Color(0.35, 0.75, 1.0))
	_bar.material_override = mat
	_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bar.position = Vector3(0, muzzle.y + 1.6, 0)
	_bar.visible = false
	add_child(_bar)


func bind(p_combat: CombatService, p_spawner: EnemySpawner, p_world: Node) -> void:
	combat = p_combat
	spawner = p_spawner
	world = p_world


func is_alive() -> bool:
	return health != null and not health.dead


func get_armor() -> float:
	return armor


## Abstand eines Punkts zur Oberfläche (Gegner messen damit ihre Schlagweite und den Aggro-Radius).
func surface_distance(point: Vector3) -> float:
	var local := to_local(point)
	if half_length > 0.0:
		return Vector2(maxf(0.0, absf(local.x) - half_length), local.z).length() - radius
	return Vector2(local.x, local.z).length() - radius


func _physics_process(delta: float) -> void:
	if not is_alive() or spawner == null or combat == null or attack_damage <= 0.0:
		return
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	var target := _pick_target()
	if target == null:
		return
	_cooldown = attack_interval
	var p := Projectile.new()
	get_parent().add_child(p)
	p.launch(self, target, combat, attack_damage, DamageInfo.Type.MAGIC, false, {}, to_global(muzzle),
		projectile_speed, projectile_color)


## Nächster lebender Gegner in Reichweite (gemessen ab der Bauwerksmitte).
func _pick_target() -> Enemy:
	var best: Enemy = null
	var best_d := attack_range * attack_range
	for e in spawner.alive_enemies():
		if not is_instance_valid(e) or not e.is_alive():
			continue
		var d := Vector2(e.global_position.x - global_position.x, e.global_position.z - global_position.z).length_squared()
		if d <= best_d:
			best_d = d
			best = e
	return best


## Einschlag eines eigenen Geschosses (von Projectile aufgerufen).
func hit_target(t: Node3D, amount: float, _crit: bool) -> void:
	if is_instance_valid(t) and combat != null:
		combat.deal_damage(self, t, amount, DamageInfo.Type.MAGIC)


func _process(delta: float) -> void:
	_time += delta
	if _crystal != null and is_alive():
		_crystal.rotation.y += delta * 1.1
		_crystal.position.y = _crystal_y + 0.12 * sin(_time * 1.8)
	if _light != null and is_alive():
		_light.light_energy = 1.1 + 0.3 * sin(_time * 2.3)


func _on_health_changed(current: float, maximum: float) -> void:
	_bar.visible = current < maximum and current > 0.0
	_bar.set_instance_shader_parameter("fill", current / maximum)


func _on_died(_info: DamageInfo) -> void:
	collision_layer = 0   # Gegner laufen durch das gefallene Tor, Helden und Gegner durch Trümmer
	_bar.visible = false
	_light.visible = false
	if _crystal != null:
		_crystal.visible = false
	var tween := create_tween()
	if kind == "gate":
		if _portcullis != null:   # Fallgitter bricht in den Boden
			tween.tween_property(_portcullis, "position:y", _portcullis.position.y - 4.5, 0.7).set_ease(Tween.EASE_IN)
	elif model != null:           # Turm sackt schief in sich zusammen
		tween.set_parallel(true)
		tween.tween_property(model, "position:y", -3.6, 1.6).set_ease(Tween.EASE_IN)
		tween.tween_property(model, "rotation:z", 0.25, 1.6)
	if world != null:
		world.vfx.smoke_cloud(global_position + Vector3(0, 1.0, 0), Color(0.5, 0.46, 0.42, 0.9), 2.6, 0.0, 18, 1.4)
		world.vfx.burst(global_position + Vector3(0, 2.0, 0), Color(0.75, 0.7, 0.62), 30, 6.0, 0.3, 0.8)
		world.camera_rig.shake(0.3)
	destroyed.emit(self)
