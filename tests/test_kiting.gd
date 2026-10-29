extends RefCounted
## Nahkampf gegen Diener (Issue #3): Wer einen Diener im Nahkampf trifft und sofort wegläuft, soll nicht risikofrei
## davonkommen. Auskiten bleibt möglich, wenn man nicht zuschlägt, und gegen Fernkämpfer-Helden unverändert.

const MATCH_SCENE := preload("res://scenes/main/match.tscn")
const SPOT := Vector3(0, 0, 14)   ## ruhiger Platz zwischen Kern und Brunnen


func _start(t, hero_id := "guardian") -> MatchController:
	Session.hero_id = hero_id
	var m: MatchController = MATCH_SCENE.instantiate()
	m.waves_override = [GameData.normalize_wave({"prepare_seconds": 0, "groups": [
		{"enemy": "grunt", "count": 1, "path": 0, "delay": 600}]}, 1)]   # ferner Nachzügler: Runde endet nicht
	t.root.add_child(m)
	await t.frames(5)
	m.local_hero.health.setup(100000.0)
	return m


func _end(t, m: MatchController) -> void:
	Session.hero_id = "guardian"
	m.queue_free()
	await t.frames(2)


func _grunt(t, m: MatchController, pos: Vector3) -> Enemy:
	var e := m.spawner.spawn_at("grunt", pos)
	e.health.setup(5000.0)   # überlebt viele Schläge
	await t.frames(90)       # Auftauch-Animation
	e.global_position = pos
	return e


func _flat_dist(a: Node3D, b: Node3D) -> float:
	return Vector2(a.global_position.x - b.global_position.x, a.global_position.z - b.global_position.z).length()


func test_melee_reach_is_mutual(t) -> void:
	var m := await _start(t)
	var hero := m.local_hero
	var e := await _grunt(t, m, SPOT)
	hero.set_physics_process(false)   # steht still und schlägt nicht
	var hero_reach := hero.stats.attack_range() + e.body_radius
	hero.global_position = SPOT + Vector3(hero_reach - 0.05, 0, 0)   # knapp in der eigenen Schlagweite des Helden
	e.target = hero
	e._attack_cooldown = 0.0
	var start := e.global_position
	await t.wait_until(func() -> bool: return hero.health.hp < hero.health.max_hp, 90)
	t.check(hero.health.hp < hero.health.max_hp, "Diener trifft einen Nahkämpfer aus dessen eigener Schlagweite")
	t.check(_flat_dist(e, hero) > hero_reach - 0.2 and (e.global_position - start).length() < 0.2,
		"dafür muss er nicht erst herantreten (bewegt %.2f m)" % (e.global_position - start).length())
	await _end(t, m)


func test_hit_and_run_gets_punished(t) -> void:
	var m := await _start(t)
	var hero := m.local_hero
	var e := await _grunt(t, m, SPOT)
	e._attack_cooldown = 1.4   # hat gerade auf etwas anderes geschlagen
	hero.global_position = SPOT + Vector3(7.0, 0, 0)
	hero.command_attack(e)   # heranlaufen und zuschlagen
	var hit: bool = await t.wait_until(func() -> bool: return e.health.hp < e.health.max_hp, 240)
	t.check(hit, "Held trifft den Diener")
	hero.command_move_to(SPOT + Vector3(16.0, 0, 0))   # sofort weglaufen
	await t.wait_until(func() -> bool: return hero.health.hp < hero.health.max_hp, 90)
	t.check(hero.health.hp < hero.health.max_hp, "Wer zuschlägt und sofort wegläuft, kassiert den Gegenschlag")
	await _end(t, m)


func test_kiting_still_possible_without_attacking(t) -> void:
	var m := await _start(t)
	var hero := m.local_hero
	var e := await _grunt(t, m, SPOT)
	var hero_reach := hero.stats.attack_range() + e.body_radius
	hero.global_position = SPOT + Vector3(hero_reach - 0.05, 0, 0)
	e.target = hero
	e._attack_cooldown = 0.0
	hero.command_move_to(SPOT + Vector3(20.0, 0, 0))   # gar nicht erst zuschlagen, gleich weg
	await t.frames(90)
	t.eq(hero.health.hp, hero.health.max_hp, "wer vor dem Einschlag die Reichweite verlässt, wird nicht getroffen")
	await _end(t, m)


func test_ranged_heroes_unchanged(t) -> void:
	var m := await _start(t, "arcanist")
	var e := await _grunt(t, m, SPOT)
	e.target = m.local_hero
	t.eq(e._attack_reach(), float(e.data.attack_range), "gegen Fernkämpfer bleibt die Diener-Reichweite wie in den Daten")
	await _end(t, m)


func test_no_faster_attacks_in_sustained_melee(t) -> void:
	var m := await _start(t)
	var hero := m.local_hero
	var e := await _grunt(t, m, SPOT)
	hero.set_physics_process(false)
	hero.global_position = SPOT + Vector3(1.2, 0, 0)
	var hits := [0]
	m.combat.damage_applied.connect(func(target: Node3D, info: DamageInfo) -> void:
		if target == hero and info.source == e:
			hits[0] += 1)
	var start := Engine.get_physics_frames()
	await t.frames(300)
	var secs := float(Engine.get_physics_frames() - start) / float(Engine.physics_ticks_per_second)
	var allowed := int(ceil(secs / float(e.data.attack_interval))) + 1
	t.check(hits[0] >= 2 and hits[0] <= allowed, "im Dauerkampf %d Schläge in %.1f s (höchstens %d nach Angriffsintervall)" % [hits[0], secs, allowed])
	await _end(t, m)
