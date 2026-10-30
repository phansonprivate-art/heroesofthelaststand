extends RefCounted
## Wunsch des Spielers: Wer angekündigten Bossfähigkeiten nicht ausweicht, wird hart bestraft. Jeder Treffer zieht
## zusätzlich einen Anteil der maximalen Leben ab (wahrer Schaden) – geprüft mit einem Guardian auf Stufe 10.

const MATCH_SCENE := preload("res://scenes/main/match.tscn")


func _start(t) -> MatchController:
	Session.hero_id = "guardian"
	Session.test_mode = true
	Session.test_level = 10
	Session.test_wave = 1
	var m: MatchController = MATCH_SCENE.instantiate()
	m.waves_override = [GameData.normalize_wave({"prepare_seconds": 0, "groups": [{"enemy": "grunt", "count": 1, "path": 0, "delay": 600}]}, 1)]
	t.root.add_child(m)
	await t.frames(5)
	m.local_hero.set_physics_process(false)
	return m


func _end(t, m: MatchController) -> void:
	Session.test_mode = false
	m.queue_free()
	await t.frames(2)


func _boss(t, m: MatchController, id: String) -> Enemy:
	var e := m.spawner.spawn_at(id, Vector3(0, 0, 20))
	e.data = e.data.duplicate(true)
	e.health.setup(50000.0)
	await t.frames(90)
	e.global_position = Vector3(0, 0, 20)
	e.set_physics_process(false)
	for key in ["_summon_left", "_soulfire_left", "_wave_left", "_breath_left", "_blizzard_left", "_roar_left", "_fireball_left", "_meteor_left"]:
		e.brain.set(key, 999.0)
	return e


## Leben voll, Fähigkeit auslösen, Verlust in Prozent der maximalen Leben
func _loss(t, m: MatchController, boss: Enemy, timer: String, frames: int) -> float:
	var hero := m.local_hero
	hero.health.heal(hero.health.max_hp)
	hero.status.clear()
	boss.brain._cast_left = 0.0
	boss.brain.set(timer, 0.0)
	await t.frames(frames)
	boss.brain.set(timer, 999.0)
	return (hero.health.max_hp - hero.health.hp) / hero.health.max_hp


func test_skillshots_punish_hard(t) -> void:
	var m := await _start(t)
	var hero := m.local_hero
	hero.global_position = Vector3(0, 0, 15)
	var morvath := await _boss(t, m, "morvath")
	m.combat.deal_damage(null, morvath, morvath.health.max_hp * 0.75, DamageInfo.Type.TRUE)   # Phase 3
	var wave := await _loss(t, m, morvath, "_wave_left", 160)
	t.check(wave >= 0.45, "Todeswelle: %.0f %% der Leben (Stufe 10, %.0f Leben)" % [wave * 100.0, hero.health.max_hp])
	var soul := await _loss(t, m, morvath, "_soulfire_left", 110)
	t.check(soul >= 0.25, "Seelenfeuer: %.0f %% der Leben" % (soul * 100.0))
	morvath.global_position = Vector3(80, 0, -80)   # aus dem Weg (nicht löschen: der Spawner verwaltet ihn)
	var fire := await _boss(t, m, "fire_drake")
	hero.global_position = Vector3(0, 0, 15)
	var ball := await _loss(t, m, fire, "_fireball_left", 110)
	t.check(ball >= 0.3, "Feuerball: %.0f %% der Leben (plus Brand)" % (ball * 100.0))
	await _end(t, m)
