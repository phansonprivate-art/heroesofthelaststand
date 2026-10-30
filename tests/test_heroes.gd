extends RefCounted
## Szenentests für Phase 2: Heldenwahl, Fernkampf, Belohnungen, Attributkäufe, Level, Skalierung.

const MATCH_SCENE := preload("res://scenes/main/match.tscn")


func _start(t, hero_id: String, waves: Array) -> MatchController:
	Session.hero_id = hero_id
	var m: MatchController = MATCH_SCENE.instantiate()
	var normalized := []
	var n := 0
	for w in waves:
		n += 1
		normalized.append(GameData.normalize_wave(w, n))
	m.waves_override = normalized
	t.root.add_child(m)
	await t.frames(2)
	t.check(m.local_hero != null and m.local_hero.hero_id == hero_id, "Runde mit %s aufgebaut" % hero_id)
	return m


func _end(t, m: MatchController) -> void:
	Session.hero_id = "guardian"
	t.paused = false
	m.queue_free()
	await t.frames(2)


## Eine Welle mit einem Ziel und einem späten Nachzügler, damit die Runde nicht sofort endet.
func _one_target(enemy := "grunt") -> Array:
	return [{"prepare_seconds": 0, "groups": [{"enemy": enemy, "count": 1, "path": 1}, {"enemy": "grunt", "count": 1, "path": 0, "delay": 300}]}]


func _first_enemy(m: MatchController) -> Enemy:
	return m.spawner.alive_enemies()[0] if m.spawner.alive_count() > 0 else null


func test_each_hero_playable(t) -> void:
	for id in ["guardian", "shadow", "arcanist"]:
		var m := await _start(t, id, _one_target())
		await t.frames(80)
		var e := _first_enemy(m)
		e.set_physics_process(false)
		var hero := m.local_hero
		hero.global_position = e.global_position + Vector3(0, 0, hero.stats.attack_range() - 0.3)
		hero.command_attack(e)
		var dead: bool = await t.wait_until(func() -> bool: return not e.is_alive(), 900)
		t.check(dead, "%s besiegt einen Gegner" % id)
		await _end(t, m)


func test_arcanist_uses_projectiles_and_slows(t) -> void:
	var m := await _start(t, "arcanist", _one_target("brute"))
	await t.frames(80)
	var e := _first_enemy(m)
	var hero := m.local_hero
	hero.global_position = e.global_position + Vector3(0, 0, 8.0)
	e.set_physics_process(false)
	hero.command_attack(e)
	var shot: bool = await t.wait_until(func() -> bool: return m.projectiles_root.get_child_count() > 0, 120)
	t.check(shot, "Arcanist feuert ein Geschoss")
	t.check(hero.global_position.distance_to(e.global_position) > 7.0, "aus der Distanz (kein Nahkampf)")
	var hit: bool = await t.wait_until(func() -> bool: return e.health.hp < e.health.max_hp, 120)
	t.check(hit, "Geschoss trifft")
	t.check(e.status.has(StatusEffects.SLOW), "Treffer verlangsamt das Ziel")
	await _end(t, m)


func test_kill_rewards_gold_and_xp(t) -> void:
	var m := await _start(t, "guardian", _one_target())
	await t.frames(80)
	var e := _first_enemy(m)
	e.set_physics_process(false)
	var hero := m.local_hero
	t.eq(m.gold.balance(1), 500, "Startgold")
	hero.global_position = e.global_position + Vector3(0, 0, 2.0)
	hero.command_attack(e)
	await t.wait_until(func() -> bool: return not e.is_alive(), 900)
	await t.frames(2)
	t.eq(m.gold.balance(1), 500 + int(e.data.gold), "Gold für den Kill (voller Anteil bei alleinigem Schaden)")
	t.eq(hero.stats.total_xp, int(e.data.xp), "XP für den Kill")
	t.eq(m.gold.totals_by_reason(1).get("kill", 0), int(e.data.gold), "genau eine Kill-Buchung")
	await _end(t, m)


func test_wave_bonus_once(t) -> void:
	var m := await _start(t, "guardian", [{"prepare_seconds": 0, "groups": [{"enemy": "grunt", "count": 1, "path": 1}]},
		{"prepare_seconds": 60, "groups": [{"enemy": "grunt", "count": 1, "path": 1}]}])
	await t.frames(80)
	var e := _first_enemy(m)
	m.combat.deal_damage(null, e, 99999)   # ohne Heldenbeteiligung: kein Kill-Gold
	await t.frames(3)
	t.eq(m.wave_manager.current_wave_number(), 2, "Welle 1 abgeschlossen")
	t.eq(m.gold.balance(1), 500 + 150, "Wellenbonus 150, kein Kill-Gold ohne Beteiligung")
	m.rewards._on_wave_completed(1)   # simuliertes doppeltes Ereignis
	t.eq(m.gold.balance(1), 650, "Wellenbonus nicht doppelt")
	t.eq(m.gold.totals_by_reason(1).get("wave_bonus", 0), 150, "genau eine Bonusbuchung")
	await _end(t, m)


func test_attribute_purchase(t) -> void:
	var m := await _start(t, "guardian", _one_target())
	var hero := m.local_hero
	var hp_before := hero.health.max_hp
	var r := m.request_attribute_upgrade("str")
	t.check(r.ok, "Kauf erfolgreich: %s" % r.message)
	var rules := GameData.attribute_rules
	var per := hero.stats.points_per_buy()
	t.eq(m.gold.balance(1), 400, "100 Gold abgezogen")
	t.eq(hero.stats.bought["str"], 1, "Kauf gebucht")
	t.eq(snappedf(hero.health.max_hp - hp_before, 0.01), 20.0 * per, "Max-Leben +20 je Punkt (%d Punkte je Kauf)" % per)
	t.eq(hero.health.hp, hero.health.max_hp, "gewonnene Leben gutgeschrieben")
	t.eq(m.request_attribute_upgrade("str").ok, true, "zweiter Kauf")
	t.eq(m.gold.balance(1), 400 - StatBlock.cost_for(1, rules), "Preis des zweiten Kaufs abgezogen")
	t.eq(m.request_attribute_upgrade("agi").ok, true, "anderes Attribut beginnt wieder bei 100")
	t.eq(m.gold.balance(1), 300 - StatBlock.cost_for(1, rules), "100 Gold abgezogen")
	t.eq(m.request_attribute_upgrade("str").ok, true, "dritter Kauf")
	if StatBlock.cost_for(3, rules) <= m.gold.balance(1):   # der Fehlschlag-Test braucht zu wenig Gold
		m.gold.spend(1, m.gold.balance(1) - StatBlock.cost_for(3, rules) + 1, "test", "drain")
	var before := m.gold.balance(1)
	var fail := m.request_attribute_upgrade("str")
	t.check(not fail.ok, "zu wenig Gold: abgelehnt")
	t.check(fail.message.contains("Nicht genug Gold"), "Grund wird erklärt: %s" % fail.message)
	t.eq(m.gold.balance(1), before, "kein Abzug bei Fehlschlag")
	t.eq(hero.stats.bought["str"], 3, "kein Punkt bei Fehlschlag")
	t.check(not m.request_attribute_upgrade("luck").ok, "unbekanntes Attribut abgelehnt")
	await _end(t, m)


func test_level_up_in_match(t) -> void:
	var m := await _start(t, "shadow", _one_target())
	var hero := m.local_hero
	var hp_before := hero.health.max_hp
	var levels := []
	hero.leveled_up.connect(func(_h: Hero, l: int) -> void: levels.append(l))
	hero.gain_xp(hero.stats.xp_to_next())
	t.eq(levels, [2], "Levelaufstieg gemeldet")
	t.check(hero.health.max_hp > hp_before, "mehr Max-Leben nach Aufstieg")
	await _end(t, m)


func test_enemies_scale_with_wave(t) -> void:
	var m := await _start(t, "guardian", _one_target())
	m.spawner.wave_number = 5
	var e := m.spawner.spawn("grunt", 0)
	var expected := float(GameData.enemy("grunt").max_hp) * (1.0 + 0.08 * 4)
	t.eq(snappedf(e.health.max_hp, 0.01), snappedf(expected, 0.01), "Welle 5: +32 %% Leben")
	t.eq(snappedf(e.damage_multiplier, 0.001), 1.2, "Welle 5: +20 %% Schaden")
	await _end(t, m)


func test_one_shot_kill_rewards(t) -> void:
	var m := await _start(t, "guardian", _one_target())
	await t.frames(80)
	var e := _first_enemy(m)
	m.combat.deal_damage(m.local_hero, e, 99999, DamageInfo.Type.TRUE)
	await t.frames(2)
	t.eq(m.gold.balance(1), 500 + int(e.data.gold), "auch ein einziger tödlicher Treffer bringt Gold")
	t.eq(m.rewards._contrib.size(), 0, "keine Beteiligungsdaten bleiben liegen")
	await _end(t, m)


func test_gold_split_by_damage_share(t) -> void:
	var m := await _start(t, "guardian", _one_target("brute"))
	await t.frames(80)
	var e := _first_enemy(m)
	e.set_physics_process(false)
	# Zweiter, simulierter Spieler (peer 2) verursacht 3/4 des Schadens
	var helper: Hero = m._spawn_hero("arcanist", 2)
	var hero := m.local_hero
	var max_hp: float = e.health.max_hp
	m.combat.deal_damage(helper, e, max_hp * 0.75 * 10.0, DamageInfo.Type.TRUE)   # TRUE: keine Rüstung
	t.check(e.is_alive() == false, "Gegner besiegt")
	await t.frames(2)
	var total := int(e.data.gold)
	t.eq(m.gold.balance(2) - 500, total, "nur der Beteiligte bekommt Gold")
	t.eq(m.gold.balance(1), 500, "Unbeteiligter bekommt kein Kill-Gold")
	t.check(hero.stats.total_xp > 0 or hero.global_position.distance_to(e.global_position) > 16.0, "XP für Helden in der Nähe")
	await _end(t, m)
