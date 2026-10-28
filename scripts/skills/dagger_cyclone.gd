class_name DaggerCyclone
extends Node3D
## Dagger Cyclone (Ultimate des Shadow): Der Held wirbelt `duration` Sekunden auf der Stelle und wirft alle
## `interval` Sekunden je ein Messer auf die bis zu drei nächsten Gegner im Radius. Jedes Messer trifft sofort
## (kurzer Flug nur fürs Auge), löst Treffereffekte aus und legt bei gelerntem Poison Mark einen Giftstapel.
## Kanalisiert: ein Bewegungsbefehl, Betäubung oder Tod beenden den Wirbel vorzeitig.

const MAX_TARGETS := 3
const COLOR := Color(0.85, 0.75, 1.0)
const SPIN_ANIM := "2H_Melee_Attack_Spinning"

var hero: Hero
var world
var radius := 5.5
var damage := 0.0
var interval := 0.2
var poison_dps := 0.0
var poison_stacks := 0
var _left := 0.0
var _wave_left := 0.0
var _pulse_left := 0.0
var _done := false


func start(p_hero: Hero, p_world, duration: float, p_radius: float, p_damage: float, p_interval: float,
		p_poison_dps := 0.0, p_poison_stacks := 0) -> void:
	hero = p_hero
	world = p_world
	radius = p_radius
	damage = p_damage
	interval = maxf(0.05, p_interval)
	poison_dps = p_poison_dps
	poison_stacks = p_poison_stacks
	_left = duration
	hero.command_stop()
	hero.status.apply(StatusEffects.CHANNEL, duration + 0.2, 0.0, hero)
	world.vfx.shockwave(hero.global_position, radius, COLOR, 0.5)
	_wave()   # erste Messer sofort
	_wave_left = interval
	_pulse_left = 0.5


func _physics_process(delta: float) -> void:
	if _done:
		return
	if not is_instance_valid(hero) or not hero.is_alive() or hero.status.is_stunned() or not hero.status.has(StatusEffects.CHANNEL):
		_finish()
		return
	_left -= delta
	_wave_left -= delta
	_pulse_left -= delta
	if not hero.visual.is_busy():
		hero.visual.play_action(SPIN_ANIM, 1.6)
	while _wave_left <= 0.0 and _left > 0.0:
		_wave()
		_wave_left += interval
	if _pulse_left <= 0.0:   # pulsierender Wirbel: Ring am Boden und Klingenbögen rundherum
		_pulse_left += 0.5
		world.vfx.shockwave(hero.global_position, radius * 0.45, COLOR, 0.4)
	if _left <= 0.0:
		_finish()


func _exit_tree() -> void:
	if is_instance_valid(hero):
		hero.status.remove(StatusEffects.CHANNEL)


## Ein Messer je Ziel auf die bis zu drei nächsten Gegner.
func _wave() -> void:
	var center := hero.global_position
	var foes: Array[Enemy] = world.spawner.enemies_in_radius(center, radius)
	foes.sort_custom(func(a: Enemy, b: Enemy) -> bool:
		return a.global_position.distance_squared_to(center) < b.global_position.distance_squared_to(center))
	var hand := center + Vector3(0, 1.1, 0)
	for i in mini(MAX_TARGETS, foes.size()):
		var e := foes[i]
		var chest := e.global_position + Vector3(0, 1.0, 0)
		world.vfx.thrown_knife(hand, chest, COLOR)
		var dealt: float = world.combat.deal_damage(hero, e, damage, DamageInfo.Type.PHYSICAL)
		if dealt > 0.0 and e.is_alive():
			Hero.apply_on_hit(e, hero.data.get("on_hit", {}), hero)
			if poison_stacks > 0:
				e.status.apply_stacking(StatusEffects.POISON, 4.0, poison_dps, poison_stacks, hero)
	world.vfx.slash(hand, randf() * TAU, COLOR, 2.4, "slash_02")


func _finish() -> void:
	if _done:
		return
	_done = true
	if is_instance_valid(hero):
		hero.status.remove(StatusEffects.CHANNEL)
		world.vfx.shockwave(hero.global_position, radius, COLOR, 0.4)
	queue_free()
