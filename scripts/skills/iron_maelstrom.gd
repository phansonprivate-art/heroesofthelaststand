class_name IronMaelstrom
extends Node3D
## Iron Maelstrom (Ultimate des Guardian): Der Held wirbelt `duration` Sekunden um die eigene Achse und bleibt dabei
## frei beweglich. Alle `interval` Sekunden trifft der Wirbel jeden Gegner im Radius; jeder Treffer würfelt einzeln
## auf Krit (eigene Krit-Chance der Fähigkeit plus die des Helden). Der nächste Gegner erhält Zusatzschaden.
## Währenddessen erleidet der Held weniger Schaden. Normale Angriffe ruhen, Betäubung oder Tod beenden den Wirbel.

const COLOR := Color(0.7, 0.85, 1.0)
const STEEL := Color(0.92, 0.95, 1.0)
const SPIN_ANIM := "2H_Melee_Attack_Spinning"
const VORTEX_TURNS := 2.5   ## Umdrehungen des Bodenwirbels je Sekunde

var hero: Hero
var world
var radius := 3.0
var damage := 0.0
var interval := 0.25
var near_bonus := 0.5
var crit_chance := 0.15
var _left := 0.0
var _tick_left := 0.0
var _done := false
var _vortex: Node3D


func start(p_hero: Hero, p_world, duration: float, p_radius: float, p_damage: float, p_interval: float,
		p_near_bonus: float, p_crit: float, reduction: float) -> void:
	hero = p_hero
	world = p_world
	radius = p_radius
	damage = p_damage
	interval = maxf(0.05, p_interval)
	near_bonus = p_near_bonus
	crit_chance = p_crit
	_left = duration
	_tick_left = 0.0   # erster Treffer sofort
	hero.status.apply(StatusEffects.WHIRL, duration + 0.2, 0.0, hero)
	hero.status.apply(StatusEffects.DAMAGE_REDUCTION, duration, reduction, hero)
	_vortex = world.vfx.blade_vortex(hero, radius, COLOR, VORTEX_TURNS)


func _physics_process(delta: float) -> void:
	if _done:
		return
	if not is_instance_valid(hero) or not hero.is_alive() or hero.status.is_stunned():
		_finish()
		return
	_left -= delta
	_tick_left -= delta
	if not hero.visual.is_busy():
		hero.visual.play_action(SPIN_ANIM, 1.5)
	while _tick_left <= 0.0 and _left > 0.0:
		_tick()
		_tick_left += interval
	if _left <= 0.0:
		_finish()


func _exit_tree() -> void:
	if is_instance_valid(hero):
		hero.status.remove(StatusEffects.WHIRL)
	if is_instance_valid(_vortex):
		_vortex.queue_free()


func _tick() -> void:
	var center := hero.global_position
	var foes: Array[Enemy] = world.spawner.enemies_in_radius(center, radius)
	var nearest: Enemy = null
	for e in foes:
		if nearest == null or e.global_position.distance_squared_to(center) < nearest.global_position.distance_squared_to(center):
			nearest = e
	for e in foes:
		var amount := damage * (1.0 + near_bonus if e == nearest else 1.0)
		var crit := hero.rng.randf() < minf(1.0, crit_chance + hero.stats.crit_chance() + hero.status.magnitude(StatusEffects.CRIT_BONUS))
		if crit:
			amount *= hero.stats.crit_multiplier()
		world.combat.deal_damage(hero, e, amount, DamageInfo.Type.PHYSICAL, crit)
		var hit := e.global_position + Vector3(0, 1.0, 0)
		var away := hit - (center + Vector3(0, 1.0, 0))
		world.vfx.burst(hit, STEEL, 6, 4.5, 0.3, 0.25, {"gravity": Vector3(0, -8, 0), "tex": "spark_04"})
		if crit:   # Krit-Blitz: heller Stoß und großer Funkenflug
			world.vfx.energy_burst(hit, Color(1.0, 0.9, 0.6), 2.0, 0.3)
			world.vfx.burst(hit, Color(1.0, 0.85, 0.5), 18, 8.0, 0.4, 0.4, {"gravity": Vector3(0, -9, 0), "tex": "spark_04"})
			world.vfx.slash(hit, atan2(-away.x, -away.z), Color(1.0, 0.95, 0.75), 2.2, "slash_02")


func _finish() -> void:
	if _done:
		return
	_done = true
	if is_instance_valid(hero):
		hero.status.remove(StatusEffects.WHIRL)
		world.vfx.shockwave(hero.global_position, radius * 1.2, COLOR, 0.45)
	queue_free()
