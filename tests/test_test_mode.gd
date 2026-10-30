extends RefCounted
## Issue #11: Testmodus – frei wählbare Heldenstufe, maximales (optional unbegrenztes) Gold, keine Telemetrie,
## und der normale Spielmodus bleibt davon unberührt.

const MATCH_SCENE := preload("res://scenes/main/match.tscn")


func _start(t, test_mode: bool, level := 1, unlimited := true) -> MatchController:
	Session.hero_id = "arcanist"
	Session.test_mode = test_mode
	Session.test_level = level
	Session.test_unlimited_gold = unlimited
	var m: MatchController = MATCH_SCENE.instantiate()
	m.waves_override = [GameData.normalize_wave({"prepare_seconds": 0, "groups": [{"enemy": "grunt", "count": 1, "path": 0, "delay": 600}]}, 1)]
	t.root.add_child(m)
	await t.frames(5)
	m.local_hero.set_physics_process(false)
	return m


func _end(t, m: MatchController) -> void:
	Session.test_mode = false
	Session.hero_id = "guardian"
	m.queue_free()
	await t.frames(2)


func test_level_and_max_gold(t) -> void:
	var m := await _start(t, true, 12)
	var hero := m.local_hero
	t.eq(hero.stats.level, 12, "Held startet auf der gewählten Stufe")
	t.eq(hero.health.hp, hero.health.max_hp, "mit vollem Leben")
	t.eq(m.gold.balance(hero.peer_id), int(GameData.setting("test_mode", "gold", 999999)), "Start mit maximalem Gold")
	t.check(not Session.telemetry_enabled(), "keine Telemetrie im Testmodus")
	await _end(t, m)


func test_max_level_and_ultimate(t) -> void:
	var m := await _start(t, true, 99)
	var hero := m.local_hero
	t.eq(hero.stats.level, hero.stats.max_level(), "Höchststufe wählbar (zu hohe Angabe wird gekappt)")
	var before := m.gold.balance(hero.peer_id)
	t.check(m.gold.spend(hero.peer_id, 5000, "test", "t1"), "Kaufen gelingt")
	t.eq(m.gold.balance(hero.peer_id), before, "unbegrenztes Gold: Guthaben bleibt gleich")
	await _end(t, m)


func test_limited_gold_option(t) -> void:
	var m := await _start(t, true, 5, false)
	var hero := m.local_hero
	var before := m.gold.balance(hero.peer_id)
	m.gold.spend(hero.peer_id, 5000, "test", "t1")
	t.eq(m.gold.balance(hero.peer_id), before - 5000, "ohne Häkchen: Gold wird abgezogen")
	await _end(t, m)


func test_normal_mode_unchanged(t) -> void:
	var m := await _start(t, false)
	var hero := m.local_hero
	t.eq(hero.stats.level, 1, "normales Spiel: Stufe 1")
	t.eq(m.gold.balance(hero.peer_id), int(GameData.setting("rewards", "start_gold", 500)), "normales Startgold")
	t.check(not m.gold.unlimited, "Gold begrenzt")
	await _end(t, m)


## Alle Käufe im Testmodus: Fähigkeit, Ultimate, Attribut, Gegenstand, Team-Verbesserung (Team-Gold)
func test_everything_buyable(t) -> void:
	var m := await _start(t, true, 20)
	var hero := m.local_hero
	var skills := GameData.skills.keys().filter(func(id: String) -> bool:
		return hero.hero_id in GameData.skill(id).heroes)
	var normal: String = skills.filter(func(id: String) -> bool: return not GameData.skill(id).ultimate)[0]
	var ult: String = skills.filter(func(id: String) -> bool: return GameData.skill(id).ultimate)[0]
	for i in GameData.MAX_SKILL_LEVEL:
		t.check(m.request_learn_ability(normal).ok, "Fähigkeit %s Stufe %d" % [normal, i + 1])
	t.check(m.request_learn_ability(ult).ok, "Ultimate %s auf Stufe 20 lernbar" % ult)
	t.check(m.request_attribute_upgrade("str").ok, "Attribut verbessern")
	t.check(m.request_buy_item(GameData.items.keys()[0]).ok, "Gegenstand kaufen")
	t.check(m.request_team_upgrade(GameData.team_upgrades[0].id).ok, "Team-Verbesserung (Team-Gold)")
	t.eq(m.gold.balance(hero.peer_id), int(GameData.setting("test_mode", "gold", 999999)), "Gold bleibt voll")
	await _end(t, m)


## Startwelle wählen: die Runde beginnt direkt mit dieser Welle (z. B. 8 = Eisdrache)
func test_start_wave(t) -> void:
	Session.test_wave = 8
	var m: MatchController = MATCH_SCENE.instantiate()
	Session.hero_id = "guardian"
	Session.test_mode = true
	Session.test_level = 15
	t.root.add_child(m)
	await t.frames(5)
	t.eq(m.wave_manager.current_wave_number(), 8, "Runde beginnt mit Welle 8")
	t.check(m.wave_manager.current_wave().groups.any(func(g: Dictionary) -> bool: return g.enemy == "ice_drake"), "Welle 8 bringt den Eisdrachen")
	m.wave_manager.skip_preparation()
	await t.frames(3)
	t.eq(m.spawner.wave_number, 8, "Gegnerstärke wie in Welle 8")
	Session.test_wave = 1
	await _end(t, m)
