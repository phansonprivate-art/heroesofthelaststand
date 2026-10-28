class_name StarfallStorm
extends Node3D
## Starfall: über `duration` Sekunden schlagen `impacts` Sterne an zufälligen Stellen im Gebiet ein.
## Jede Einschlagstelle wird WARNING Sekunden vorher am Boden markiert (faire Vorwarnung, auch für spätere Boss-Varianten).

const WARNING := 0.6

var hero: Hero
var world
var center := Vector3.ZERO
var radius := 6.0
var impact_radius := 2.0
var damage := 60.0
var _schedule: Array[Dictionary] = []   ## {time, pos, marked}
var _time := 0.0


func start(p_hero: Hero, p_world, p_center: Vector3, p_radius: float, impacts: int, p_impact_radius: float, p_damage: float, duration: float) -> void:
	hero = p_hero
	world = p_world
	center = Vector3(p_center.x, 0.0, p_center.z)
	radius = p_radius
	impact_radius = p_impact_radius
	damage = p_damage
	var rng := RandomNumberGenerator.new()
	for i in impacts:
		# Der erste Einschlag trifft genau den Zielpunkt, die übrigen verteilen sich zufällig im Gebiet
		var r := 0.0 if i == 0 else sqrt(rng.randf()) * radius
		var a := rng.randf() * TAU
		_schedule.append({"time": WARNING + duration * float(i) / maxf(1.0, impacts - 1), "pos": center + Vector3(cos(a) * r, 0.0, sin(a) * r), "marked": false})
	world.vfx.ring(center, radius, radius, Color(1.0, 0.9, 0.4, 0.5), duration + WARNING)
	world.vfx.decal(center, "rune_circle", radius * 1.05, Color(1.0, 0.85, 0.4, 0.8), duration + WARNING + 0.4, 0.15)


func _physics_process(delta: float) -> void:
	_time += delta
	for s in _schedule:
		if not s.marked and _time >= s.time - WARNING:
			s.marked = true
			world.vfx.ring(s.pos, impact_radius, impact_radius, Color(1.0, 0.85, 0.3, 0.8), WARNING)
			world.vfx.meteor(s.pos, Color(1.0, 0.85, 0.4), WARNING)
	while not _schedule.is_empty() and _time >= _schedule[0].time:
		_impact(_schedule.pop_front().pos)
	if _schedule.is_empty():
		queue_free()


func _impact(pos: Vector3) -> void:
	var source: Node = hero if is_instance_valid(hero) else null
	for e: Enemy in world.spawner.enemies_in_radius(pos, impact_radius):
		world.combat.deal_damage(source, e, damage, DamageInfo.Type.MAGIC)
	world.match_audio.play_at("starfall_impact", pos)
