class_name Projectile
extends Node3D
## Zielsuchendes Geschoss (Fernkampfangriffe). Der Schaden wird beim Abschuss ausgewürfelt und
## beim Einschlag über den Helden bzw. CombatService zugefügt. Stirbt das Ziel vorher, verpufft es.

const HIT_DISTANCE := 0.6
const MAX_LIFETIME := 3.0

var source: Node3D
var target: Node3D
var combat: CombatService
var amount := 0.0
var damage_type := DamageInfo.Type.MAGIC
var crit := false
var on_hit: Dictionary = {}
var speed := 20.0
var _life := 0.0


func launch(p_source: Node3D, p_target: Node3D, p_combat: CombatService, p_amount: float, p_type: DamageInfo.Type,
		p_crit: bool, p_on_hit: Dictionary, from: Vector3, p_speed: float, color: Color) -> void:
	source = p_source
	target = p_target
	combat = p_combat
	amount = p_amount
	damage_type = p_type
	crit = p_crit
	on_hit = p_on_hit
	speed = p_speed
	global_position = from
	_build_visual(color)


func _physics_process(delta: float) -> void:
	_life += delta
	if _life > MAX_LIFETIME or target == null or not is_instance_valid(target) or not target.call("is_alive"):
		queue_free()
		return
	var aim := target.global_position + Vector3(0, 1.1, 0)
	var to := aim - global_position
	var step := speed * delta
	if to.length() <= maxf(HIT_DISTANCE, step):
		_impact()
		return
	global_position += to.normalized() * step


func _impact() -> void:
	var world = source.get("world") if source != null and is_instance_valid(source) else null
	if world != null and is_instance_valid(target):
		world.vfx.burst(target.global_position + Vector3(0, 1.1, 0), Color(1.0, 0.6, 0.3), 12, 3.0, 0.4, 0.3, {"gravity": Vector3.ZERO})
	if source != null and is_instance_valid(source) and source.has_method("hit_target"):
		source.hit_target(target, amount, crit)
	elif combat != null:
		# Verursacher nicht mehr vorhanden: Schaden trotzdem zufügen, aber ohne Zuordnung
		combat.deal_damage(null, target, amount, damage_type, crit)
		Hero.apply_on_hit(target, on_hit, null)
	queue_free()


func _build_visual(color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.44
	sphere.radial_segments = 12
	sphere.rings = 6
	mesh.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color.lightened(0.4)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.0
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.2
	light.omni_range = 3.0
	add_child(light)
	var world = source.get("world") if source != null else null
	if world != null:
		world.vfx.attach_trail(self, color, 0.45, "flare_01")
