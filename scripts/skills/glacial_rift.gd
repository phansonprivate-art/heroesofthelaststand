class_name GlacialRift
extends Node3D
## Glacial Rift (Ultimate des Arcanist): Eine Welle aus Eisstacheln bricht in gerader Linie vom Helden aus
## nacheinander aus dem Boden (kein Sofortschaden, die Front läuft mit SPEED nach vorn). Jeder Gegner in der Bahn
## wird einmal getroffen: Magieschaden, kurz hochgeschleudert (Betäubung) und danach stark verlangsamt.
## Die Stacheln bleiben `wall_time` Sekunden als Hindernis stehen und zersplittern dann.

const SPEED := 26.0         ## m/s der Stachelfront
const STEP := 1.1           ## Abstand der Stachelgruppen
const START := 1.0          ## erste Gruppe vor dem Helden (er soll nicht im eigenen Eis stecken)
const HALF_WIDTH := 0.9
const COLOR := Color(0.6, 0.88, 1.0)
const LIFT_HEIGHT := 1.3

var hero: Hero
var world
var origin := Vector3.ZERO
var dir := Vector3.FORWARD
var length := 11.0
var damage := 0.0
var lift := 0.75
var slow := 0.5
var slow_time := 2.0
var wall_time := 1.8
var _front := 0.0
var _next := START
var _hit := {}


func start(p_hero: Hero, p_world, point: Vector3, p_length: float, p_damage: float, p_lift: float, p_slow: float,
		p_slow_time: float, p_wall_time: float) -> void:
	hero = p_hero
	world = p_world
	length = p_length
	damage = p_damage
	lift = p_lift
	slow = p_slow
	slow_time = p_slow_time
	wall_time = p_wall_time
	origin = Vector3(hero.global_position.x, 0.0, hero.global_position.z)
	var to := Vector3(point.x - origin.x, 0.0, point.z - origin.z)
	dir = to.normalized() if to.length() > 0.1 else -hero.global_basis.z
	dir.y = 0.0
	dir = dir.normalized()
	world.vfx.line_indicator(origin + dir * 0.5, dir, length, HALF_WIDTH * 2.0, COLOR, 0.55)
	# Ausbruch-Klang kommt beim Wirken (cast_glacial_rift); das Zersplittern einmal mitten auf der Bahn
	var w = world
	var mid := origin + dir * length * 0.5
	world.get_tree().create_timer(length / SPEED + wall_time + 0.1, false).timeout.connect(func() -> void:
		if is_instance_valid(w):
			w.match_audio.play_at("ice_shatter", mid))


func _physics_process(delta: float) -> void:
	_front += SPEED * delta
	while _next <= minf(_front, length):
		_erupt(_next)
		_next += STEP
	if _next > length:
		queue_free()


func _erupt(d: float) -> void:
	var pos := origin + dir * d
	world.vfx.ice_eruption(pos, dir, wall_time)
	_spawn_wall(pos)
	var source: Node = hero if is_instance_valid(hero) else null
	for e: Enemy in world.spawner.enemies_in_radius(pos, STEP + HALF_WIDTH + 1.0):
		if _hit.has(e) or not e.is_alive():
			continue
		var rel := Vector3(e.global_position.x - origin.x, 0.0, e.global_position.z - origin.z)
		var along := rel.dot(dir)
		var lateral := (rel - dir * along).length()
		if along < 0.0 or along > d + STEP * 0.5 or lateral > HALF_WIDTH + e.body_radius:
			continue
		_hit[e] = true
		world.combat.deal_damage(source, e, damage, DamageInfo.Type.MAGIC)
		if not e.is_alive():
			continue
		e.status.apply(StatusEffects.STUN, lift, 0.0, source)
		world.rewards.record_control(source, e, StatusEffects.STUN, e.status.last_gain)
		e.status.apply(StatusEffects.SLOW, lift + slow_time, slow, source)
		world.rewards.record_control(source, e, StatusEffects.SLOW, e.status.last_gain, slow)
		_knock_up(e)


## Hochschleudern ist reine Darstellung: Die Figur fliegt hoch und landet, die Betäubung hält den Gegner fest.
func _knock_up(e: Enemy) -> void:
	var v := e.visual
	var base := v.position.y
	var t := v.create_tween()
	t.tween_property(v, "position:y", base + LIFT_HEIGHT, lift * 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.tween_property(v, "position:y", base, lift * 0.45).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	t.tween_callback(func() -> void:
		if is_instance_valid(e):
			world.vfx.smoke_cloud(e.global_position + Vector3(0, 0.2, 0), Color(0.75, 0.88, 1.0, 0.5), 0.5, 0.0, 4, 0.4))


## Eis als Hindernis: blockiert Helden und Gegner (Ebene 1 wie die Mauern), bis es zersplittert.
func _spawn_wall(pos: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 2.0, STEP)
	shape.shape = box
	shape.position.y = 1.0
	body.add_child(shape)
	get_parent().add_child(body)   # Geschoss-Ablage: verschwindet mit der Runde
	body.global_position = pos
	body.rotation.y = atan2(-dir.x, -dir.z)
	body.get_tree().create_timer(wall_time, false).timeout.connect(body.queue_free)
