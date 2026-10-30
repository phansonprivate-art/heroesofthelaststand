extends RefCounted
## Phase 4: neue Gegnertypen (Fernkämpfer, Elite mit Bodenschlag, Mini-Boss), Endboss mit drei Phasen, zehn Wellen.

const MATCH_SCENE := preload("res://scenes/main/match.tscn")


## Runde ohne eigene Wellengegner (nur ein ferner Nachzügler, damit die Runde nicht endet). Helden stehen still.
func _start(t, hero_id := "guardian", waves := []) -> MatchController:
	Session.hero_id = hero_id
	var m: MatchController = MATCH_SCENE.instantiate()
	if waves.is_empty():
		waves = [{"prepare_seconds": 0, "groups": [{"enemy": "grunt", "count": 1, "path": 0, "delay": 600}]}]
	var normalized := []
	for i in waves.size():
		normalized.append(GameData.normalize_wave(waves[i], i + 1))
	m.waves_override = normalized
	t.root.add_child(m)
	await t.frames(5)
	m.local_hero.set_physics_process(false)   # kein Laufen, kein Auto-Angriff, keine Regeneration
	return m


func _end(t, m: MatchController) -> void:
	Session.hero_id = "guardian"
	m.queue_free()
	await t.frames(2)


## Gegner erzeugen, Auftauchen abwarten, an eine Stelle setzen. Eigene Kopie der Werte, damit Tests nichts Globales ändern.
func _spawn(t, m: MatchController, id: String, pos: Vector3, hp := 0.0) -> Enemy:
	var e := m.spawner.spawn_at(id, pos)
	e.data = e.data.duplicate(true)
	if hp > 0.0:
		e.health.setup(hp)
	await t.frames(90)   # Auftauch-Animation
	e.global_position = pos
	return e


func _place_hero(h: Hero, pos: Vector3) -> void:
	h.global_position = pos
	h.health.setup(100000.0)


func test_phase4_data(t) -> void:
	t.eq(GameData.errors.size(), 0, "Daten fehlerfrei: %s" % str(GameData.errors))
	for id in ["seer", "grave_knight", "colossus", "morvath"]:
		t.check(not GameData.enemy(id).is_empty(), "Gegnertyp vorhanden: %s" % id)
	t.check(not GameData.enemy("seer").projectile.is_empty(), "Knochenseher schießt")
	t.eq(String(GameData.enemy("grave_knight").ability.get("type", "")), "stomp", "Grabritter hat einen Bodenschlag")
	t.eq(String(GameData.enemy("colossus").category), "miniboss", "Knochenkoloss ist Mini-Boss")
	t.eq((GameData.enemy("morvath").boss.get("phase_hp", []) as Array).size(), 2, "Endboss hat drei Phasen")
	t.eq(GameData.waves.size(), 10, "zehn Wellen")
	var has := func(wave: Dictionary, id: String) -> bool:
		return wave.groups.any(func(g: Dictionary) -> bool: return g.enemy == id)
	t.check(has.call(GameData.waves[4], "colossus"), "Welle 5 bringt den Mini-Boss")
	t.check(has.call(GameData.waves[9], "morvath"), "Welle 10 bringt den Endboss")
	var boss_def := GameData.enemy("morvath")
	var used := [String(boss_def.boss.get("phase_anim", "Taunt")), String(boss_def.boss.summon.get("anim", "Spellcast_Summon")), "Spellcast_Long"]
	for key in boss_def.anims:   # alle Animationen, die die Daten nennen
		var entry: Variant = boss_def.anims[key]
		used.append_array(entry if entry is Array else [entry])
	for anim in used:
		var e_visual := CharacterVisual.new()
		e_visual.setup(GameData.enemy("morvath").model, [], 1.0, {}, Color.WHITE)
		t.check(e_visual.anim_player != null and e_visual.anim_player.has_animation(anim), "Boss-Modell hat Animation %s" % anim)
		e_visual.free()


func test_seer_shoots_from_range(t) -> void:
	var m := await _start(t)
	var hero := m.local_hero
	var seer := await _spawn(t, m, "seer", Vector3(0, 0, 18), 5000.0)
	_place_hero(hero, Vector3(0, 0, 12))   # 6 m entfernt: in Schussweite, weit außerhalb Nahkampf
	var shots := [0]
	m.enemies_root.child_entered_tree.connect(func(n: Node) -> void:
		if n is Projectile:
			shots[0] += 1)
	await t.frames(240)
	t.check(shots[0] >= 1, "Knochenseher feuert Geschosse (%d)" % shots[0])
	t.check(hero.health.hp < 100000.0, "Geschosse treffen den Helden")
	var dist := Vector2(seer.global_position.x - hero.global_position.x, seer.global_position.z - hero.global_position.z).length()
	t.check(dist > 4.0, "bleibt auf Distanz (%.1f m)" % dist)
	await _end(t, m)


func test_stomp_warns_then_hits(t) -> void:
	var m := await _start(t)
	var near := m.local_hero
	var far: Hero = m._spawn_hero("arcanist", 2)
	far.set_physics_process(false)
	var knight := await _spawn(t, m, "grave_knight", Vector3(0, 0, 18), 5000.0)
	knight.data.damage = 0.0   # normale Schläge zählen nicht: geprüft wird nur der Bodenschlag
	_place_hero(near, Vector3(0, 0, 16))   # 2 m: löst aus
	_place_hero(far, Vector3(6, 0, 18))    # 6 m: außerhalb des Kreises (3,5 m)
	var sources: Array[String] = []
	m.combat.damage_applied.connect(func(target: Node3D, info: DamageInfo) -> void:
		if target == near:
			sources.append("%s %.0f (Fenster %.2f)" % [info.source.name if info.source_is_valid() else "-", info.final_amount, knight._ability_windup]))
	var warned := false
	for i in 300:
		await t.frames(1)
		if knight._ability_windup >= 0.0:
			warned = true
			break
	t.check(warned, "Bodenschlag wird angekündigt")
	t.eq(near.health.hp, 100000.0, "während der Warnung noch kein Schaden %s" % str(sources))
	t.check(not near.status.has(StatusEffects.SLOW), "und keine Verlangsamung")
	await t.frames(75)   # Ankündigung 1,0 s
	t.check(near.health.hp < 100000.0, "nach der Warnung: Schaden im Kreis")
	t.check(near.status.has(StatusEffects.SLOW), "und Verlangsamung")
	t.eq(far.health.hp, 100000.0, "außerhalb des Kreises kein Schaden")
	await _end(t, m)


func test_boss_phases_and_abilities(t) -> void:
	var m := await _start(t)
	var hero := m.local_hero
	var other: Hero = m._spawn_hero("shadow", 2)
	other.set_physics_process(false)
	var boss := await _spawn(t, m, "morvath", Vector3(0, 0, 20), 10000.0)
	boss.set_physics_process(false)   # steht still und schießt nicht: geprüft werden nur die Bossfähigkeiten
	var brain := boss.brain
	t.check(brain != null, "Boss hat eine Steuerung")
	var phases: Array[int] = []
	brain.phase_changed.connect(func(p: int, _a: String, _b: String) -> void: phases.append(p))
	_place_hero(hero, Vector3(0, 0, 16))
	_place_hero(other, Vector3(2, 0, 16))

	# Beschwörung: erst Kreise, dann Skelette
	var before := m.spawner.alive_count()
	brain._summon_left = 0.0
	await t.frames(10)
	t.eq(m.spawner.alive_count(), before, "Beschwörung kündigt sich erst an")
	await t.frames(80)
	t.check(m.spawner.alive_count() > before, "Skelette erscheinen (%d)" % (m.spawner.alive_count() - before))
	var summons := brain.summons.duplicate()
	for s in summons:
		s.set_physics_process(false)   # Beschwörungen greifen im Test nicht an

	# Phase 2 bei 66 %: Seelenfeuer
	m.combat.deal_damage(null, boss, boss.health.max_hp * 0.36, DamageInfo.Type.TRUE)
	t.eq(brain.phase, 2, "Phase 2 unter 66 %")
	brain._soulfire_left = 0.0
	brain._summon_left = 99.0
	await t.frames(3)
	other.global_position = Vector3(8, 0, 16)   # weicht nach der Warnung aus
	t.eq(hero.health.hp, 100000.0, "Seelenfeuer: erst Warnkreis, kein Sofortschaden")
	await t.frames(100)
	t.check(hero.health.hp < 100000.0, "wer stehen bleibt, wird getroffen")
	t.eq(other.health.hp, 100000.0, "wer ausweicht, bleibt heil")

	# Phase 3 bei 33 %: Raserei und Todeswelle
	m.combat.deal_damage(null, boss, boss.health.hp - boss.health.max_hp * 0.3, DamageInfo.Type.TRUE)
	t.eq(brain.phase, 3, "Phase 3 unter 33 %")
	t.check(boss.haste > 1.0 and boss.move_bonus > 1.0, "Raserei: schneller")
	t.eq(phases, [2, 3] as Array[int], "Phasenwechsel werden gemeldet")
	hero.health.setup(100000.0)
	other.global_position = Vector3(14, 0, 20)   # 14 m: außerhalb der Todeswelle (9 m)
	brain._soulfire_left = 99.0
	brain._summon_left = 99.0
	brain._cast_left = 0.0   # kurze Pause nach dem Phasenwechsel überspringen
	brain._wave_left = 0.0
	await t.frames(3)
	t.check(brain.is_casting() and not brain._pending.is_empty(), "Todeswelle wird aufgeladen")
	t.eq(hero.health.hp, 100000.0, "noch kein Schaden während der Ankündigung")
	await t.frames(140)
	t.check(hero.health.hp < 100000.0, "Todeswelle trifft im Ring")
	t.eq(other.health.hp, 100000.0, "außerhalb des Rings kein Schaden")

	# Tod des Bosses: Beschwörungen zerfallen
	var defeated := [false]
	brain.defeated.connect(func() -> void: defeated[0] = true)
	m.combat.deal_damage(null, boss, boss.health.hp + 1.0, DamageInfo.Type.TRUE)
	t.check(defeated[0], "Boss besiegt")
	t.check(summons.all(func(s) -> bool: return not is_instance_valid(s) or not s.is_alive()), "Beschwörungen zerfallen")
	await _end(t, m)


func test_boss_wave_ends_in_victory(t) -> void:
	var m := await _start(t, "guardian", [{"prepare_seconds": 0, "groups": [{"enemy": "morvath", "count": 1, "path": 0}]}])
	var won := [false]
	m.finished.connect(func(victory: bool) -> void: won[0] = victory)
	await t.frames(120)
	var boss: Enemy = null
	for e in m.spawner.alive_enemies():
		if e.enemy_id == "morvath":
			boss = e
	t.check(boss != null, "Endboss erscheint")
	t.check(m.hud._boss_box.visible, "Bossleiste ist sichtbar")
	m.combat.deal_damage(null, boss, boss.health.hp + 1.0, DamageInfo.Type.TRUE)
	await t.frames(30)
	t.check(won[0], "Sieg nach dem Fall des Endbosses")
	await _end(t, m)
