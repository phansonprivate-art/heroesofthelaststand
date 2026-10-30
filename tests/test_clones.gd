extends RefCounted
## Issue #10: Doppelgänger der Assassine – Anzahl je Stufe, weniger Schaden, mehr erlittener Schaden, Gift vom Helden,
## einzeln wähl- und steuerbar, verschwinden nach Ablauf oder Tod.

const MATCH_SCENE := preload("res://scenes/main/match.tscn")


func _start(t) -> MatchController:
	Session.hero_id = "shadow"
	Session.test_mode = true      # genug Gold und Stufe für alle Fähigkeiten
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
	Session.hero_id = "guardian"
	m.queue_free()
	await t.frames(2)


func _cast_clones(t, m: MatchController, level: int) -> void:
	for i in level:
		t.check(m.request_learn_ability("shadow_clones").ok, "Doppelgänger Stufe %d gelernt" % (i + 1))
	var hero := m.local_hero
	hero.mana = 10000.0
	hero.abilities.cooldowns.clear()
	m.local_hero.global_position = Vector3(0, 0, 14)
	t.check(m.request_cast(hero.abilities.slots.find("shadow_clones"), null, hero.global_position), "Doppelgänger gewirkt")
	await t.frames(30)   # Wirk-Animation


func test_clone_skill_data(t) -> void:
	var d := GameData.skill("shadow_clones")
	t.check(not d.is_empty() and "shadow" in d.heroes, "Fähigkeit für die Assassine")
	for i in 3:
		t.eq(int(GameData.skill_value("shadow_clones", i + 1, "count", 0)), i + 1, "Stufe %d: %d Kopien" % [i + 1, i + 1])
	t.check(float(GameData.skill_value("shadow_clones", 1, "damage_share", 1.0)) < 1.0, "Kopien machen weniger Schaden")
	t.check(float(GameData.skill_value("shadow_clones", 1, "damage_taken", 1.0)) > 1.0, "Kopien erleiden mehr Schaden")


func test_clones_spawn_and_stats(t) -> void:
	var m := await _start(t)
	var hero := m.local_hero
	await _cast_clones(t, m, 3)
	t.eq(m.clones.size(), 3, "Stufe 3: drei Doppelgänger")
	var c: Hero = m.clones[0]
	t.check(c.clone_owner == hero and c.peer_id == hero.peer_id, "gehört dem Helden (Gold/XP an ihn)")
	t.check(c in m.spawner.heroes and not (c in m.heroes), "Gegner greifen ihn an, er zählt aber nicht als Held der Runde")
	t.eq(c.stats.level, hero.stats.level, "gleiche Stufe")
	t.check(absf(c.health.max_hp - hero.health.max_hp) < 1.0 and absf(c.health.hp - hero.health.hp) < 1.0, "Leben wie der Held beim Wirken (%.0f / %.0f)" % [c.health.hp, c.health.max_hp])
	var hp := c.health.hp
	m.combat.deal_damage(null, c, 100.0, DamageInfo.Type.TRUE)
	t.check(absf(hp - c.health.hp - 150.0) < 0.5, "erleidet 150 %% Schaden (%.0f)" % (hp - c.health.hp))
	t.check(c.outgoing_multiplier < 1.0, "verursacht weniger Schaden (×%.2f)" % c.outgoing_multiplier)
	await _end(t, m)


func test_clone_fights_and_poisons(t) -> void:
	var m := await _start(t)
	t.check(m.request_learn_ability("poison_mark").ok, "Poison Mark gelernt")
	await _cast_clones(t, m, 1)
	var c: Hero = m.clones[0]
	var e := m.spawner.spawn_at("brute", c.global_position + Vector3(0, 0, -1.8))
	e.data = e.data.duplicate(true)
	e.health.setup(50000.0)
	await t.frames(90)
	e.set_physics_process(false)
	e.global_position = c.global_position + Vector3(0, 0, -1.8)
	await t.frames(150)
	t.check(e.health.hp < 50000.0, "Doppelgänger greift selbstständig an")
	t.check(e.status.has(StatusEffects.POISON), "und vergiftet wie der Held (Poison Mark)")
	await _end(t, m)


func test_clone_selection_and_control(t) -> void:
	var m := await _start(t)
	await _cast_clones(t, m, 2)
	var input := m.hero_input
	var next := InputEventAction.new()
	next.action = "select_next_unit"
	next.pressed = true
	input._unhandled_input(next)
	t.eq(input.hero, m.clones[0], "F2 wählt den ersten Doppelgänger")
	input._unhandled_input(next)
	t.eq(input.hero, m.clones[1], "F2 noch einmal: der zweite")
	var c: Hero = m.clones[1]
	var goal := c.global_position + Vector3(4, 0, 0)
	input.hero.command_move_to(goal)
	await t.frames(120)
	t.check(c.global_position.distance_to(goal) < 1.0, "gewählter Doppelgänger läuft unabhängig zum Ziel")
	t.check(m.local_hero.global_position.distance_to(goal) > 2.0, "der Held bleibt stehen")
	var back := InputEventAction.new()
	back.action = "select_hero"
	back.pressed = true
	input._unhandled_input(back)
	t.eq(input.hero, m.local_hero, "F1: zurück zum Helden")
	await _end(t, m)


func test_clones_expire_and_die(t) -> void:
	var m := await _start(t)
	await _cast_clones(t, m, 2)
	var doomed: Hero = m.clones[0]
	m.hero_input.select(doomed)
	m.combat.deal_damage(null, doomed, doomed.health.hp + 10.0, DamageInfo.Type.TRUE)
	await t.frames(3)
	t.eq(m.clones.size(), 1, "getöteter Doppelgänger verschwindet")
	t.eq(m.hero_input.hero, m.local_hero, "Auswahl springt zurück zum Helden")
	m.clones[0].clone_left = 0.05
	await t.frames(10)
	t.eq(m.clones.size(), 0, "nach Ablauf der Dauer verschwinden die übrigen")
	t.check(not m.spawner.heroes.any(func(h) -> bool: return is_instance_valid(h) and h.clone_owner != null), "und sind aus der Gegnerzielsuche entfernt")
	await _end(t, m)


## Mehrfachauswahl: F3 alle Kopien, F4 alles, Umschalt-Klick, Auswahlrahmen; Gruppenbefehle mit Auffächern; Lebensbalken
func test_group_selection_and_bars(t) -> void:
	var m := await _start(t)
	await _cast_clones(t, m, 3)
	var input := m.hero_input
	var all_clones := InputEventAction.new()
	all_clones.action = "select_all_clones"
	all_clones.pressed = true
	input._unhandled_input(all_clones)
	t.eq(input.selected.size(), 3, "F3: alle drei Doppelgänger gewählt")
	t.check(not input.selected.has(m.local_hero), "ohne den Helden")
	var goal := m.local_hero.global_position + Vector3(6, 0, 0)
	input._command_move(goal)
	await t.frames(150)
	var near := m.clones.filter(func(c: Hero) -> bool: return c.global_position.distance_to(goal) < 2.2).size()
	t.eq(near, 3, "Gruppenbefehl: alle drei laufen zum Ziel")
	t.check(m.clones[0].global_position.distance_to(m.clones[1].global_position) > 0.6, "und stehen nicht aufeinander")
	var everything := InputEventAction.new()
	everything.action = "select_all_units"
	everything.pressed = true
	input._unhandled_input(everything)
	t.eq(input.selected.size(), 4, "F4: Held und alle Kopien")
	input.select(m.local_hero)
	input.toggle_in_selection(m.clones[2])
	t.eq(input.selected.size(), 2, "Umschalt-Klick nimmt eine Kopie hinzu")
	input.toggle_in_selection(m.clones[2])
	t.eq(input.selected.size(), 1, "und wieder heraus")
	input.box_select(Rect2(Vector2.ZERO, Vector2(get_viewport_size(t))))
	t.check(input.selected.size() >= 2, "Auswahlrahmen über den Bildschirm wählt eigene Einheiten (%d)" % input.selected.size())
	var c: Hero = m.clones[0]
	var bar: MeshInstance3D = c.get_node_or_null("CloneHealthBar")
	t.check(bar != null, "Doppelgänger hat einen Lebensbalken")
	m.combat.deal_damage(null, c, c.health.max_hp * 0.3, DamageInfo.Type.TRUE)
	t.check(float(bar.get_instance_shader_parameter("fill")) < 1.0, "Balken sinkt mit den Leben")
	await _end(t, m)


func get_viewport_size(t) -> Vector2:
	return Vector2(t.root.get_visible_rect().size)


## Verletzter Held: die Kopien übernehmen seinen aktuellen Lebensstand, nicht das Maximum
func test_clone_copies_current_health(t) -> void:
	var m := await _start(t)
	var hero := m.local_hero
	for i in 1:
		m.request_learn_ability("shadow_clones")
	hero.health.hp = hero.health.max_hp * 0.4
	hero.mana = 10000.0
	m.request_cast(hero.abilities.slots.find("shadow_clones"), null, hero.global_position)
	await t.frames(30)
	var c: Hero = m.clones[0]
	t.check(absf(c.health.hp - hero.health.hp) < hero.health.max_hp * 0.02, "Kopie hat die aktuellen Leben des Helden (%.0f ≈ %.0f)" % [c.health.hp, hero.health.hp])
	t.check(absf(c.health.ratio() - hero.health.ratio()) < 0.02, "Balken steht gleich voll")
	await _end(t, m)


## Gegner, die einen Doppelgänger angreifen, laufen nach dessen Zerfall weiter zum Kern (vorher blieben sie stehen)
func test_enemies_continue_after_clone_vanishes(t) -> void:
	var m := await _start(t)
	await _cast_clones(t, m, 1)
	var c: Hero = m.clones[0]
	var e := m.spawner.spawn_at("grunt", c.global_position + Vector3(0, 0, -3))
	e.data = e.data.duplicate(true)
	e.health.setup(50000.0)
	await t.frames(90)
	e.global_position = c.global_position + Vector3(0, 0, -3)
	c.health.setup(50000.0)
	await t.frames(60)
	t.eq(e.target, c, "Gegner greift den Doppelgänger an")
	m.local_hero.global_position = Vector3(-25, 0, 30)   # weit weg: der Gegner soll den Kern wählen, nicht den Helden
	var start := e.global_position
	c.clone_left = 0.01
	await t.frames(120)
	t.check(e.target == m.core or e.target is MapStructure or e.target == m.local_hero, "nach dem Zerfall: neues Ziel statt ins Leere")
	t.check(e.global_position.distance_to(start) > 1.0, "und er läuft weiter (%.1f m)" % e.global_position.distance_to(start))
	await _end(t, m)


## Doppelgänger wehren sich gegen Fernkämpfer außerhalb ihrer Nahkampf-Reichweite
func test_clone_fights_back(t) -> void:
	var m := await _start(t)
	await _cast_clones(t, m, 1)
	var c: Hero = m.clones[0]
	c.health.setup(50000.0)
	var seer := m.spawner.spawn_at("seer", c.global_position + Vector3(0, 0, -7.5))
	seer.data = seer.data.duplicate(true)
	seer.health.setup(50000.0)
	await t.frames(90)
	seer.global_position = c.global_position + Vector3(0, 0, -7.5)
	seer.set_physics_process(false)
	m.combat.deal_damage(seer, c, 10.0, DamageInfo.Type.MAGIC)
	await t.frames(180)
	t.check(seer.health.hp < 50000.0, "Doppelgänger läuft zum Angreifer und schlägt zu")
	await _end(t, m)
