extends RefCounted
## Szenentests: echte Runde im SceneTree (headless, mit Physik).

const MATCH_SCENE := preload("res://scenes/main/match.tscn")


func _start_match(t, waves_override := []) -> MatchController:
	var m: MatchController = MATCH_SCENE.instantiate()
	if not waves_override.is_empty():
		var normalized := []
		var n := 0
		for w in waves_override:
			n += 1
			normalized.append(GameData.normalize_wave(w, n))
		m.waves_override = normalized
	t.root.add_child(m)
	await t.frames(2)
	t.check(m.local_hero != null and m.spawner != null and m.wave_manager.state != WaveManager.State.IDLE, "Runde vollständig aufgebaut")
	return m


func _end_match(t, m: MatchController) -> void:
	t.paused = false
	m.queue_free()
	await t.frames(2)


func test_main_menu_loads(t) -> void:
	var menu: Control = load("res://scenes/main/main_menu.tscn").instantiate()
	t.root.add_child(menu)
	await t.frames(2)
	t.check(menu.get_child_count() > 0, "Hauptmenü baut seine Oberfläche auf")
	menu.queue_free()
	await t.frames(1)


func test_match_starts(t) -> void:
	var m := await _start_match(t)
	t.check(m.local_hero != null and m.local_hero.is_alive(), "Held erzeugt")
	t.eq(m.core.health.hp, 10000.0, "Kern mit 10.000 Lebenspunkten")
	t.eq(m.spawner.paths.size(), 3, "drei Spawnpfade")
	t.eq(m.wave_manager.state, WaveManager.State.PREPARING, "erste Welle in Vorbereitung")
	t.check(m.arena.decor.get_child_count() > 50, "Arena-Deko aufgebaut")
	await _end_match(t, m)


func test_hero_moves(t) -> void:
	var m := await _start_match(t)
	var hero := m.local_hero
	var start := hero.global_position
	hero.command_move_direction(Vector3.RIGHT)
	await t.frames(30)
	hero.command_move_direction(Vector3.ZERO)
	t.check(hero.global_position.x > start.x + 2.0, "WASD-Befehl bewegt den Helden (%.2f -> %.2f)" % [start.x, hero.global_position.x])
	hero.command_move_to(Vector3(-6, 0, 8))
	var arrived: bool = await t.wait_until(func() -> bool: return hero.global_position.distance_to(Vector3(-6, 0, 8)) < 0.5, 240)
	t.check(arrived, "Bewegung per Klickziel erreicht den Punkt")
	await _end_match(t, m)


func test_attack_move_engages_and_continues(t) -> void:
	var m := await _start_match(t, [{"prepare_seconds": 0, "groups": [{"enemy": "grunt", "count": 1, "path": 1}, {"enemy": "grunt", "count": 1, "path": 0, "delay": 120}]}])  # zweiter Gegner spät, damit die Runde nicht endet
	await t.frames(80)   # Spawn-Animation abwarten
	var e: Enemy = m.spawner.alive_enemies()[0]
	e.set_physics_process(false)   # Gegner steht still, damit der Test reproduzierbar ist
	var hero := m.local_hero
	var goal := e.global_position + Vector3(0, 0, -10)
	hero.global_position = e.global_position + Vector3(0, 0, 8)
	hero.command_attack_move(goal)
	var engaged: bool = await t.wait_until(func() -> bool: return hero.attack_target == e, 240)
	t.check(engaged, "Angriffsbewegung greift den Gegner unterwegs an")
	var dead: bool = await t.wait_until(func() -> bool: return not e.is_alive(), 600)
	t.check(dead, "Gegner besiegt")
	var arrived: bool = await t.wait_until(func() -> bool: return hero.global_position.distance_to(goal) < 0.6, 300)
	t.check(arrived, "danach läuft der Held zum Ziel weiter")
	await _end_match(t, m)


func test_stop_command(t) -> void:
	var m := await _start_match(t)
	var hero := m.local_hero
	hero.command_move_to(Vector3(-15, 0, 15))
	await t.frames(10)
	hero.command_stop()
	var pos := hero.global_position
	await t.frames(20)
	t.check(hero.global_position.distance_to(pos) < 0.05, "Stopp hält den Helden an")
	await _end_match(t, m)


func test_enemies_spawn_and_advance(t) -> void:
	var m := await _start_match(t)
	m.wave_manager.skip_preparation()
	await t.frames(5)
	t.check(m.spawner.alive_count() > 0, "Gegner erscheinen nach Wellenstart")
	var e: Enemy = m.spawner.alive_enemies()[0]
	var d0 := e.global_position.distance_to(m.core.global_position)
	await t.frames(150)
	if is_instance_valid(e) and e.is_alive():
		var d1 := e.global_position.distance_to(m.core.global_position)
		t.check(d1 < d0 - 2.0, "Gegner läuft zum Kern (%.1f -> %.1f)" % [d0, d1])
	await _end_match(t, m)


func test_enemies_damage_core(t) -> void:
	var m := await _start_match(t, [{"prepare_seconds": 0, "groups": [{"enemy": "grunt", "count": 3, "path": 0, "interval": 0.1}]}])
	await t.frames(10)
	m.local_hero.global_position = Vector3(0, 0, 25)   # Held aus dem Weg
	m.local_hero.set_physics_process(false)
	for e in m.spawner.alive_enemies():
		e.global_position = Vector3(randf_range(-1, 1), 0, -4.5)
	var hit: bool = await t.wait_until(func() -> bool: return m.core.health.hp < 10000.0, 300)
	t.check(hit, "Gegner greifen den Kern an")
	await _end_match(t, m)


func test_hero_kills_enemy_and_wave_completes(t) -> void:
	var m := await _start_match(t, [{"prepare_seconds": 0, "groups": [{"enemy": "grunt", "count": 1, "path": 1}]}])
	await t.frames(5)
	t.eq(m.spawner.alive_count(), 1, "ein Gegner")
	var e: Enemy = m.spawner.alive_enemies()[0]
	var hero := m.local_hero
	hero.global_position = e.global_position + Vector3(1.5, 0, 0)
	hero.command_attack(e)
	var completed := []
	m.wave_manager.wave_completed.connect(func(n: int) -> void: completed.append(n))
	var dead: bool = await t.wait_until(func() -> bool: return not is_instance_valid(e) or not e.is_alive(), 600)
	t.check(dead, "Held besiegt den Gegner")
	t.eq(m.spawner.killed_total, 1, "Kill gezählt")
	await t.frames(3)
	t.eq(completed, [1], "Welle genau einmal abgeschlossen")
	t.eq(m.phase, MatchController.Phase.VICTORY, "letzte Welle abgewehrt -> Sieg")
	t.check(m.game_over.visible, "Siegbildschirm sichtbar")
	await _end_match(t, m)


func test_enemy_retaliates_against_hero(t) -> void:
	var m := await _start_match(t, [{"prepare_seconds": 0, "groups": [{"enemy": "brute", "count": 1, "path": 2}]}])
	await t.frames(80)   # Spawn-Animation abwarten
	var e: Enemy = m.spawner.alive_enemies()[0]
	var hero := m.local_hero
	hero.global_position = e.global_position + Vector3(-1.8, 0, 0)
	hero.command_attack(e)
	var aggro: bool = await t.wait_until(func() -> bool: return e.target == hero, 120)
	t.check(aggro, "angegriffener Gegner wendet sich dem Helden zu")
	var hurt: bool = await t.wait_until(func() -> bool: return hero.health.hp < hero.health.max_hp - 10.0, 300)
	t.check(hurt, "Gegner verletzt den Helden")
	hero.global_position = Vector3(0, 0, 25)
	hero.command_stop()
	hero.set_physics_process(false)
	var back: bool = await t.wait_until(func() -> bool: return e.target == m.core, 400)
	t.check(back, "nach Verlassen der Reichweite zurück zum Kern")
	await _end_match(t, m)


func test_enemy_aggros_hero_in_range(t) -> void:
	var m := await _start_match(t, [{"prepare_seconds": 0, "groups": [{"enemy": "grunt", "count": 1, "path": 1}, {"enemy": "runner", "count": 1, "path": 2}, {"enemy": "grunt", "count": 1, "path": 0, "delay": 120}]}])
	await t.frames(80)   # Spawn-Animation abwarten
	var grunt: Enemy = null
	var runner: Enemy = null
	for e in m.spawner.alive_enemies():
		if e.enemy_id == "grunt":
			grunt = e
		else:
			runner = e
	var hero := m.local_hero
	hero.set_physics_process(false)   # Held greift nicht an, steht nur in der Nähe
	hero.global_position = grunt.global_position + Vector3(0, 0, 4.0)
	var aggro: bool = await t.wait_until(func() -> bool: return grunt.target == hero, 60)
	t.check(aggro, "Knochenläufer greift einen Helden im Aggro-Radius an, ohne getroffen zu werden")
	var hurt: bool = await t.wait_until(func() -> bool: return hero.health.hp < hero.health.max_hp, 300)
	t.check(hurt, "und verletzt ihn")
	# Schattenhuscher haben einen kleinen Radius (3 m) und laufen an einem Helden in 4 m Abstand vorbei
	runner.global_position = hero.global_position + Vector3(4.0, 0, 0)
	runner.set_physics_process(false)
	runner._choose_target(1.0)
	t.check(runner.target == m.core, "Schattenhuscher ignoriert Helden außerhalb seines Radius")
	runner.global_position = hero.global_position + Vector3(2.0, 0, 0)
	runner._choose_target(1.0)
	t.check(runner.target == hero, "Schattenhuscher greift Helden innerhalb seines Radius an")
	await _end_match(t, m)


func test_hero_death_and_respawn(t) -> void:
	var m := await _start_match(t)
	var hero := m.local_hero
	m.combat.deal_damage(null, hero, 99999)
	t.check(not hero.is_alive(), "Held stirbt")
	var back: bool = await t.wait_until(func() -> bool: return hero.is_alive(), 60 * 8)
	t.check(back, "Held wird nach der Wartezeit wiederbelebt")
	t.check(hero.global_position.distance_to(m.arena.hero_spawn_point()) < 0.5, "Wiederbelebung am Startpunkt")
	await _end_match(t, m)


func test_core_destroyed_means_defeat(t) -> void:
	var m := await _start_match(t)
	m.wave_manager.skip_preparation()
	await t.frames(5)
	m.combat.deal_damage(null, m.core, 20000)
	await t.frames(2)
	t.eq(m.phase, MatchController.Phase.DEFEAT, "Niederlage, wenn der Kern fällt")
	t.eq(m.wave_manager.state, WaveManager.State.FINISHED, "Wellen gestoppt")
	t.check(not m.hero_input.input_enabled, "Eingabe gesperrt")
	t.check(m.game_over.visible, "Niederlagebildschirm sichtbar")
	t.eq(m.core.health.hp, 0.0, "Kern-Lebenspunkte nicht negativ")
	await _end_match(t, m)


func test_pause_stops_simulation(t) -> void:
	var m := await _start_match(t)
	var before := m.wave_manager.prepare_left
	m.pause_menu.open()
	await t.frames(30)
	t.eq(m.wave_manager.prepare_left, before, "Wellen-Countdown steht während der Pause")
	m.pause_menu.close()
	await t.frames(30)
	t.check(m.wave_manager.prepare_left < before, "läuft nach der Pause weiter")
	await _end_match(t, m)
