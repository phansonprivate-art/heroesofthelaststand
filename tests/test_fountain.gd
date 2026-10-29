extends RefCounted
## Brunnen der Erholung (Issue #2): Lage hinter dem Kern, Regeneration nur im Wirkkreis, nicht stapelbar,
## und im Kreis nur Bewegung – keine Angriffe, keine Zauber.

const MATCH_SCENE := preload("res://scenes/main/match.tscn")


func _start(t, hero_id := "guardian") -> MatchController:
	Session.hero_id = hero_id
	var m: MatchController = MATCH_SCENE.instantiate()
	m.waves_override = [GameData.normalize_wave({"prepare_seconds": 0, "groups": [
		{"enemy": "brute", "count": 1, "path": 1, "interval": 0.1},
		{"enemy": "grunt", "count": 1, "path": 0, "delay": 600}]}, 1)]   # Nachzügler: Runde endet nicht
	t.root.add_child(m)
	await t.frames(80)
	for e in m.spawner.alive_enemies():
		e.set_physics_process(false)   # Gegner stehen still: Tests sind reproduzierbar
	m.gold.grant(1, 20000, "test", "test_gold")
	return m


func _end(t, m: MatchController) -> void:
	Session.hero_id = "guardian"
	m.queue_free()
	await t.frames(2)


## Held in den Wirkkreis (inside) oder knapp daneben stellen; liefert die tatsächlich vergangene Spielzeit.
func _rest(t, m: MatchController, inside: bool, frames: int) -> float:
	var f := m.fountain
	var hero := m.local_hero
	hero.velocity = Vector3.ZERO
	hero.has_move_target = false
	hero.global_position = f.global_position + Vector3(f.radius - 1.4 if inside else f.radius + 2.0, 0, 0)
	var start := Engine.get_physics_frames()
	await t.frames(frames)
	return float(Engine.get_physics_frames() - start) / float(Engine.physics_ticks_per_second)


func test_fountain_placement(t) -> void:
	var m := await _start(t)
	var f := m.fountain
	t.check(f != null and f.is_inside_tree(), "Brunnen ist in der Runde vorhanden")
	t.check(f.global_position.z > m.core.global_position.z + 6.0, "Brunnen steht hinter dem Kern (z %.1f)" % f.global_position.z)
	var to_core := Vector2(f.global_position.x - m.core.global_position.x, f.global_position.z - m.core.global_position.z).length()
	t.check(to_core >= 20.0, "Brunnen liegt weit vom Kern: Heilen kostet Zeit an der Basis (%.1f m)" % to_core)
	var near_path := 99.0
	for points in m.arena.get_spawn_paths():
		for p in points:
			near_path = minf(near_path, Vector2(p.x - f.global_position.x, p.z - f.global_position.z).length())
	t.check(near_path > f.radius + 4.0, "abseits der Gegnerwege (nächster Wegpunkt %.1f m)" % near_path)
	t.check(not f.contains(m.arena.hero_spawn_point()), "Wiedereinstiegspunkt liegt außerhalb des Wirkkreises")
	t.check(f.hp_per_second > 0.0 and f.hp_per_second <= 0.03 and f.mana_per_second > 0.0 and f.mana_per_second <= 0.03,
		"Regeneration moderat (%.1f %% Leben, %.1f %% Mana pro Sekunde)" % [f.hp_per_second * 100.0, f.mana_per_second * 100.0])
	await _end(t, m)


func test_regenerates_only_inside(t) -> void:
	var m := await _start(t, "arcanist")
	var hero := m.local_hero
	var f := m.fountain
	var max_hp := hero.health.max_hp
	var max_mana := hero.stats.max_mana()
	# außerhalb: nur die eigene Regeneration
	hero.health.hp = max_hp * 0.4
	hero.mana = max_mana * 0.2
	var secs_out := await _rest(t, m, false, 120)
	var hp_out := hero.health.hp - max_hp * 0.4
	var mana_out := hero.mana - max_mana * 0.2
	t.check(not hero.status.has(StatusEffects.SANCTUARY), "außerhalb kein Brunnen-Zustand")
	# innerhalb: eigene Regeneration + Brunnen
	hero.health.hp = max_hp * 0.4
	hero.mana = max_mana * 0.2
	var secs_in := await _rest(t, m, true, 120)
	var hp_in := hero.health.hp - max_hp * 0.4
	var mana_in := hero.mana - max_mana * 0.2
	var hp_extra := hp_in - hp_out * secs_in / maxf(secs_out, 0.01)
	var mana_extra := mana_in - mana_out * secs_in / maxf(secs_out, 0.01)
	var hp_expect := max_hp * f.hp_per_second * secs_in
	var mana_expect := max_mana * f.mana_per_second * secs_in
	t.check(absf(hp_extra - hp_expect) < hp_expect * 0.25, "Brunnen heilt %.1f Leben in %.2f s (erwartet %.1f)" % [hp_extra, secs_in, hp_expect])
	t.check(absf(mana_extra - mana_expect) < mana_expect * 0.25, "Brunnen gibt %.1f Mana in %.2f s (erwartet %.1f)" % [mana_extra, secs_in, mana_expect])
	t.check(hp_in < max_hp * 0.2, "keine Vollheilung in wenigen Sekunden (+%.0f %% in %.1f s)" % [hp_in / max_hp * 100.0, secs_in])
	t.check(f.is_inside(hero) and hero.status.has(StatusEffects.SANCTUARY), "im Wirkkreis: Brunnen-Zustand aktiv")
	for id in [StatusEffects.SANCTUARY, StatusEffects.WHIRL, StatusEffects.CHANNEL, StatusEffects.UNTARGETABLE]:
		t.check(Hud.STATUS_NAMES.has(id), "HUD zeigt einen deutschen Namen für den Zustand '%s'" % id)
	await _end(t, m)


func test_no_stacking_by_reentering(t) -> void:
	var m := await _start(t)
	var hero := m.local_hero
	var f := m.fountain
	var max_hp := hero.health.max_hp
	hero.health.hp = max_hp * 0.3
	var start_frames := Engine.get_physics_frames()
	for i in 30:   # ständig rein und raus
		hero.global_position = f.global_position + Vector3((f.radius - 1.4) if i % 2 == 0 else (f.radius + 2.0), 0, 0)
		await t.frames(2)
	var secs := float(Engine.get_physics_frames() - start_frames) / float(Engine.physics_ticks_per_second)
	var gained := hero.health.hp - max_hp * 0.3
	var limit := (max_hp * f.hp_per_second + hero.stats.hp_regen()) * secs * 1.1
	t.check(gained <= limit, "Rein und raus heilt nicht mehr als Drinbleiben (%.1f ≤ %.1f)" % [gained, limit])
	await _end(t, m)


func test_no_combat_inside(t) -> void:
	var m := await _start(t)
	var hero := m.local_hero
	var f := m.fountain
	var e: Enemy = m.spawner.alive_enemies()[0]
	var spot := f.global_position + Vector3(f.radius - 1.4, 0, 0)
	e.global_position = spot + Vector3(0, 0, 1.4)   # in Schlagweite, ebenfalls im Kreis
	await _rest(t, m, true, 2)
	t.check(hero.attack_target == null, "am Brunnen sucht der Held sich kein Ziel von selbst")
	hero.attack_target = e
	var hp_before := e.health.hp
	await t.frames(90)
	t.eq(e.health.hp, hp_before, "kein Angriff im Wirkkreis, auch mit Ziel in Schlagweite")
	t.check(m.request_learn_ability("shield_bash").ok, "Schildstoß gelernt")
	var slot := hero.abilities.slots.find("shield_bash")
	hero.mana = 10000.0
	var reason := hero.abilities.check_cast(slot)
	t.check(reason.contains("Brunnen"), "Zauber gesperrt: %s" % reason)
	t.check(not m.request_cast(slot, e, e.global_position), "Wirken schlägt im Wirkkreis fehl")
	# Kreis verlassen: sofort wieder kampfbereit
	var outside := f.global_position + Vector3(f.radius + 3.0, 0, 0)
	hero.global_position = outside
	e.global_position = outside + Vector3(0, 0, 1.4)
	await t.frames(3)
	t.check(not hero.status.has(StatusEffects.SANCTUARY), "Zustand endet beim Verlassen")
	t.eq(hero.abilities.check_cast(slot), "", "außerhalb wieder wirkbar")
	hero.attack_target = e
	await t.wait_until(func() -> bool: return e.health.hp < hp_before, 120)
	t.check(e.health.hp < hp_before, "außerhalb greift der Held wieder an")
	await _end(t, m)


func test_dead_heroes_not_healed(t) -> void:
	var m := await _start(t)
	var hero := m.local_hero
	await _rest(t, m, true, 2)
	m.combat.deal_damage(null, hero, 999999.0, DamageInfo.Type.TRUE)
	t.check(not hero.is_alive(), "Held ist gefallen")
	await t.frames(30)
	t.eq(hero.health.hp, 0.0, "der Brunnen belebt nicht wieder und heilt keine Gefallenen")
	await _end(t, m)
