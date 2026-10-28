class_name FireballProjectile
extends Node3D
## Feuerball: fliegt zu einem Bodenpunkt und explodiert. Gegner im Kern der Explosion (1 m) erhalten
## vollen Schaden, alle anderen im Radius die Hälfte. Läuft mit dem SceneTree (pausierbar).
## Aussehen: brennende Kugel, Flammenschweif und Explosion aus den Feuer-Bildfolgen
## (tools/blender_fire_flipbooks.py), dazu flackerndes Licht.

const SPEED := 22.0
const SPLASH_FACTOR := 0.5
const CORE_RADIUS := 1.0

var hero: Hero
var world
var target := Vector3.ZERO
var damage := 0.0
var radius := 2.5
var _trail: Node3D
var _light: OmniLight3D


func launch(p_hero: Hero, p_world, from: Vector3, to: Vector3, p_damage: float, p_radius: float) -> void:
	hero = p_hero
	world = p_world
	target = Vector3(to.x, 0.6, to.z)
	damage = p_damage
	radius = p_radius
	global_position = from
	world.vfx.attach_fire(self, 2.0)
	_trail = world.vfx.fire_trail(1.0)
	_trail.global_position = from
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.2)
	_light.light_energy = 3.0
	_light.omni_range = 6.0
	add_child(_light)
	world.vfx.fire_explosion(from, 0.35)   # Zündung an der Hand


func _physics_process(delta: float) -> void:
	var to := target - global_position
	var step := SPEED * delta
	if to.length() <= step:
		_explode()
		return
	global_position += to.normalized() * step
	if is_instance_valid(_trail):
		_trail.global_position = global_position
	_light.light_energy = 2.6 + randf() * 0.9   # Flackern


func _exit_tree() -> void:
	# Auch bei vorzeitigem Entfernen (Rundenende, Werkzeuge) soll der Schweif verglühen statt hängen zu bleiben
	if is_instance_valid(world) and is_instance_valid(world.vfx):
		world.vfx.end_trail(_trail)


func _explode() -> void:
	var source: Node = hero if is_instance_valid(hero) else null
	for e: Enemy in world.spawner.enemies_in_radius(target, radius):
		var d := Vector2(e.global_position.x - target.x, e.global_position.z - target.z).length()
		var amount := damage if d <= CORE_RADIUS + e.body_radius else damage * SPLASH_FACTOR
		world.combat.deal_damage(source, e, amount, DamageInfo.Type.MAGIC)
	world.vfx.end_trail(_trail)
	world.vfx.fire_explosion(target, radius)
	world.vfx.burst(target + Vector3(0, 0.5, 0), Color(1.0, 0.75, 0.3), 30, 9.0, 0.3, 0.7, {"gravity": Vector3(0, -9, 0), "tex": "spark_04"})
	world.vfx.smoke(target + Vector3(0, 1.4, 0), Color(0.22, 0.18, 0.16, 0.6), radius * 0.6, 1.2, 12)
	world.vfx.ring(target, 0.5, radius, Color(1.0, 0.5, 0.15), 0.4, 0.2)
	world.vfx.decal(target, "scorch_01", radius * 0.9, Color(0.1, 0.06, 0.03, 0.8), 3.0, 0.0, false)
	world.match_audio.play_at("fireball_impact", target)
	queue_free()
