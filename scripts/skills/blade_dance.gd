class_name BladeDance
extends Node3D
## Blade Dance (Ultimate des Shadow): 6–8 blitzschnelle Sprünge um ein Ziel. Jeder Sprung trifft mit eigenem
## Krit-Wurf und löst Treffereffekte aus (Treffereffekt des Helden, Giftstapel bei gelerntem Poison Mark).
## Währenddessen ist der Held unverwundbar und für Gegner nicht anvisierbar.
## Sprungpunkte liegen auf einem Kreis um das Ziel, je 135° versetzt: kreuz und quer, alle acht 45°-Richtungen.
## Stirbt das Ziel vorher, springt der Held zum nächsten Gegner in der Nähe, sonst endet der Tanz.

const STEP_DEG := 135.0
const RETARGET_RANGE := 6.0
const COLOR := Color(0.75, 0.5, 1.0)
const SHADOW_SMOKE := Color(0.22, 0.1, 0.32, 0.85)

var hero: Hero
var world
var target: Enemy
var hits := 6
var damage := 0.0
var radius := 1.8
var poison_dps := 0.0
var poison_stacks := 0
var _interval := 0.08
var _done := 0
var _left := 0.0
var _angle := 0.0


func start(p_hero: Hero, p_world, p_target: Enemy, p_hits: int, p_damage: float, duration: float, p_radius: float,
		p_poison_dps := 0.0, p_poison_stacks := 0) -> void:
	hero = p_hero
	world = p_world
	target = p_target
	hits = maxi(1, p_hits)
	damage = p_damage
	radius = p_radius
	poison_dps = p_poison_dps
	poison_stacks = p_poison_stacks
	_interval = duration / maxf(1.0, hits - 1)   # erster Sprung sofort, letzter nach `duration`
	var away := hero.global_position - target.global_position
	_angle = atan2(away.z, away.x)
	hero.command_stop()
	hero.status.apply(StatusEffects.UNTARGETABLE, duration + 0.5, 0.0, hero)   # Sicherheitsnetz; endet beim letzten Sprung
	_hop()


func _physics_process(delta: float) -> void:
	_left -= delta
	while _left <= 0.0 and _done < hits:
		_hop()


func _exit_tree() -> void:
	if is_instance_valid(hero):
		hero.status.remove(StatusEffects.UNTARGETABLE)


func _hop() -> void:
	if target == null or not is_instance_valid(target) or not target.is_alive():
		target = world.spawner.nearest_enemy(hero.global_position, RETARGET_RANGE)
		if target == null:
			_finish()
			return
	var from := hero.global_position
	_angle += deg_to_rad(STEP_DEG)
	var to := target.global_position + Vector3(cos(_angle), 0.0, sin(_angle)) * (radius + target.body_radius * 0.5)
	to.y = 0.0
	hero.global_position = to
	var look := target.global_position - to
	hero.rotation.y = atan2(-look.x, -look.z)
	var attacks: Variant = hero.data.anims.get("attack", [])
	var anim := String((attacks as Array).pick_random()) if attacks is Array and not (attacks as Array).is_empty() else String(attacks)
	hero.visual.play_action(anim, 2.6)

	# eigener Krit-Wurf je Sprung (Krit-Buffs wie Shadow Dance zählen mit)
	var crit := hero.rng.randf() < minf(1.0, hero.stats.crit_chance() + hero.status.magnitude(StatusEffects.CRIT_BONUS))
	var amount := damage * (hero.stats.crit_multiplier() if crit else 1.0)
	var dealt: float = world.combat.deal_damage(hero, target, amount, DamageInfo.Type.PHYSICAL, crit)
	if dealt > 0.0 and target.is_alive():
		Hero.apply_on_hit(target, hero.data.get("on_hit", {}), hero)
		if poison_stacks > 0:
			target.status.apply_stacking(StatusEffects.POISON, 4.0, poison_dps, poison_stacks, hero)

	var chest := target.global_position + Vector3(0, 1.1, 0)
	world.vfx.lightning(from + Vector3(0, 1.0, 0), to + Vector3(0, 1.0, 0), COLOR, 0.18, 0.8)
	world.vfx.smoke_cloud(from + Vector3(0, 0.6, 0), SHADOW_SMOKE, 0.45, 0.0, 3, 0.5)
	world.vfx.slash(chest, hero.rotation.y + randf_range(-0.6, 0.6), COLOR, 2.2, "slash_03")
	world.vfx.burst(chest, Color(0.9, 0.8, 1.0), 8, 5.0, 0.35, 0.25, {"gravity": Vector3.ZERO, "tex": "spark_05"})
	if crit:
		world.vfx.energy_burst(chest, Color(1.0, 0.85, 0.55), 1.6, 0.35)
	_done += 1
	_left += _interval
	if _done >= hits:
		_finish()


func _finish() -> void:
	_done = hits
	if target != null and is_instance_valid(target):
		world.vfx.energy_burst(target.global_position + Vector3(0, 1.1, 0), COLOR, 2.8, 0.5)
		world.vfx.shockwave(target.global_position, 2.6, COLOR, 0.45)
		if target.is_alive():
			hero.attack_target = target
	hero.status.remove(StatusEffects.UNTARGETABLE)
	queue_free()
