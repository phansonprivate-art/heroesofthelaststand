class_name DefenseCore
extends StaticBody3D
## Der zu verteidigende Kern. Fällt er, ist die Runde verloren.

signal destroyed
signal critical_changed(is_critical: bool)

@export var radius := 2.4   ## Abstand, ab dem Gegner den Kern angreifen können (plus ihre Reichweite)

@onready var health: HealthComponent = $Health
@onready var crystal: MeshInstance3D = $Crystal
@onready var glow: OmniLight3D = $Glow

const BARRIER_SECONDS := 120.0

var critical_ratio := 0.25
var critical := false
var regen_per_second := 0.0
var barrier_per_wave := 0.0
var _crystal_material: StandardMaterial3D
var _hit_pulse := 0.0
var _time := 0.0


func _ready() -> void:
	_crystal_material = crystal.get_surface_override_material(0).duplicate()
	crystal.set_surface_override_material(0, _crystal_material)
	health.damaged.connect(_on_damaged)
	health.changed.connect(_on_changed)
	health.died.connect(func(_info: DamageInfo) -> void: destroyed.emit())


func setup(max_hp: float, p_critical_ratio: float) -> void:
	critical_ratio = p_critical_ratio
	health.setup(max_hp)


func is_alive() -> bool:
	return not health.dead


## Team-Upgrade anwenden. value_per_level stammt aus data/balance/game.json (team_upgrades).
func apply_upgrade(upgrade_id: String, level: int, value_per_level: float) -> void:
	match upgrade_id:
		"core_hp":
			health.set_max_hp(health.max_hp + value_per_level)   # Zuwachs wird auch geheilt
		"core_regen":
			regen_per_second = value_per_level * level
		"core_barrier":
			barrier_per_wave = value_per_level * level
		_:
			push_warning("Unbekanntes Kern-Upgrade: %s" % upgrade_id)


## Zu Beginn jeder Welle: Schutzbarriere erneuern (falls gekauft).
func on_wave_started() -> void:
	if barrier_per_wave > 0.0 and is_alive():
		health.add_shield(barrier_per_wave, BARRIER_SECONDS, null)


func _physics_process(delta: float) -> void:
	if regen_per_second > 0.0 and is_alive():
		health.heal(regen_per_second * delta, null)


func _on_damaged(_info: DamageInfo) -> void:
	_hit_pulse = 1.0


func _on_changed(current: float, maximum: float) -> void:
	var now_critical := current > 0.0 and current / maximum <= critical_ratio
	if now_critical != critical:
		critical = now_critical
		critical_changed.emit(critical)


func _process(delta: float) -> void:
	_time += delta
	_hit_pulse = maxf(0.0, _hit_pulse - delta * 4.0)
	crystal.rotation.y += delta * 0.6
	crystal.position.y = 3.3 + sin(_time * 1.6) * 0.15
	var base := Color(0.35, 0.8, 1.0)
	if critical:
		base = base.lerp(Color(1.0, 0.25, 0.2), 0.5 + 0.5 * sin(_time * 6.0))
	if health.dead:
		base = Color(0.2, 0.2, 0.25)
	var col := base.lerp(Color(1, 0.4, 0.3), _hit_pulse)
	_crystal_material.emission = col
	_crystal_material.emission_energy_multiplier = 1.6 + _hit_pulse * 3.0
	glow.light_color = col
	glow.light_energy = 0.3 if health.dead else 2.0 + _hit_pulse * 2.0
