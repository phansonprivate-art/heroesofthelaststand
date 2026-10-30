extends RefCounted
## Issue #8: Feuerdrache – Elemente (immun gegen Feuer, anfällig für Eis und Gift), Feuerpest (Verbrennung bei
## Treffern), Feuerbälle mit Flächenschaden, schwerer Feuerball, Meteorschauer, Drachengebrüll.

const MATCH_SCENE := preload("res://scenes/main/match.tscn")


func _start(t) -> MatchController:
	Session.hero_id = "guardian"
	var m: MatchController = MATCH_SCENE.instantiate()
	m.waves_override = [GameData.normalize_wave({"prepare_seconds": 0, "groups": [{"enemy": "grunt", "count": 1, "path": 0, "delay": 600}]}, 1)]
	t.root.add_child(m)
	await t.frames(5)
	m.local_hero.set_physics_process(false)
	return m


func _end(t, m: MatchController) -> void:
	m.queue_free()
	await t.frames(2)


func _spawn(t, m: MatchController, id: String, pos: Vector3, hp := 0.0) -> Enemy:
	var e := m.spawner.spawn_at(id, pos)
	e.data = e.data.duplicate(true)
	if hp > 0.0:
		e.health.setup(hp)
	await t.frames(90)
	e.global_position = pos
	return e


func _place_hero(h: Hero, pos: Vector3) -> void:
	h.global_position = pos
	h.health.setup(100000.0)


## Drache steht still, Bossfähigkeiten pausiert (einzeln im Test freigegeben)
func _quiet_drake(t, m: MatchController) -> Enemy:
	var drake := await _spawn(t, m, "fire_drake", Vector3(0, 0, 20), 20000.0)
	drake.set_physics_process(false)
	drake.brain._fireball_left = 999.0
	drake.brain._meteor_left = 999.0
	drake.brain._roar_left = 999.0
	return drake


func test_fire_drake_data(t) -> void:
	t.eq(GameData.errors.size(), 0, "Daten fehlerfrei: %s" % str(GameData.errors))
	var d := GameData.enemy("fire_drake")
	t.check(not d.is_empty(), "Feuerdrache vorhanden")
	t.eq(float(d.elements.fire), 0.0, "immun gegen Feuer")
	t.eq(float(d.elements.ice), 1.5, "anfällig für Eis")
	t.eq(float(d.elements.poison), 1.5, "anfällig für Gift")
	for key in ["fireball", "meteor_shower", "fire_roar"]:
		t.check(d.boss.has(key), "Bossfähigkeit %s" % key)
	t.eq((d.glow_pulse as Array).size(), 3, "Glühen pulsiert")
	t.check(GameData.waves[8].groups.any(func(g: Dictionary) -> bool: return g.enemy == "fire_drake"), "Welle 9 bringt den Feuerdrachen")
	var v := CharacterVisual.new()
	v.setup(d.model, [], 1.0, {}, Color.WHITE)
	for anim in ["Idle", "Walk", "Attack_Bite", "Attack_Claw", "Tail_Swipe", "Fire_Breath", "Roar", "Fly", "Death"]:
		t.check(v.anim_player != null and v.anim_player.has_animation(anim), "Modell hat Animation %s" % anim)
	v.free()


func test_elements(t) -> void:
	var m := await _start(t)
	var drake := await _quiet_drake(t, m)
	var hp := drake.health.hp
	m.combat.deal_damage(null, drake, 500.0, DamageInfo.Type.MAGIC, false, "fire")
	t.eq(drake.health.hp, hp, "Feuerschaden prallt ab")
	var plain := m.combat.deal_damage(null, drake, 500.0, DamageInfo.Type.MAGIC)
	var ice := m.combat.deal_damage(null, drake, 500.0, DamageInfo.Type.MAGIC, false, "ice")
	t.check(absf(ice - plain * 1.5) < 0.5, "Eis +50 %% (%.0f statt %.0f)" % [ice, plain])
	await _end(t, m)


func test_burn_on_hit_and_splash(t) -> void:
	var m := await _start(t)
	var hero := m.local_hero
	var other: Hero = m._spawn_hero("arcanist", 2)
	other.set_physics_process(false)
	var drake := await _quiet_drake(t, m)
	drake.set_physics_process(true)
	_place_hero(hero, Vector3(0, 0, 13))     # 7 m: Fernkampf
	_place_hero(other, Vector3(1.2, 0, 13))  # daneben: im Flächenschaden
	var burned := false
	for i in 300:
		await t.frames(1)
		if hero.status.has(StatusEffects.BURN):
			burned = true
			break
	t.check(burned, "Feuerpest: Treffer setzen den Helden in Brand")
	t.check(other.health.hp < 100000.0, "Feuerball trifft auch den Helden daneben (Flächenschaden)")
	# Verbrennung allein: Drache aus, Schaden läuft weiter
	drake.set_physics_process(false)
	hero.health.setup(100000.0)
	hero.status.apply(StatusEffects.BURN, 3.0, 10.0, drake)
	await t.frames(130)
	t.check(hero.health.hp <= 100000.0 - 19.0, "Verbrennung macht Schaden über Zeit (%.0f)" % (100000.0 - hero.health.hp))
	await _end(t, m)


func test_heavy_fireball(t) -> void:
	var m := await _start(t)
	var hero := m.local_hero
	var away: Hero = m._spawn_hero("arcanist", 2)
	away.set_physics_process(false)
	var drake := await _quiet_drake(t, m)
	_place_hero(hero, Vector3(0, 0, 12))
	_place_hero(away, Vector3(7, 0, 12))   # 7 m neben dem Ziel: außerhalb des Kreises (2,6 m)
	drake.brain._fireball_left = 0.0
	await t.frames(3)
	t.check(drake.brain.is_casting(), "Feuerball wird aufgeladen")
	await t.frames(50)
	t.eq(hero.health.hp, 100000.0, "während Aufladen und Flug kein Schaden")
	await t.frames(50)
	t.check(hero.health.hp < 100000.0, "Einschlag trifft")
	t.check(hero.status.has(StatusEffects.BURN), "und setzt in Brand")
	t.eq(away.health.hp, 100000.0, "außerhalb des Kreises nichts")
	await _end(t, m)


func test_meteor_shower_phase_two(t) -> void:
	var m := await _start(t)
	var hero := m.local_hero
	var drake := await _quiet_drake(t, m)
	_place_hero(hero, Vector3(0, 0, 12))
	m.combat.deal_damage(null, drake, drake.health.max_hp * 0.45, DamageInfo.Type.TRUE)
	t.eq(drake.brain.phase, 2, "Phase 2 unter 60 %")
	drake.brain._cast_left = 0.0
	drake.brain._meteor_left = 0.0
	await t.frames(3)
	t.check(drake.brain._pending.any(func(p: Dictionary) -> bool: return p.kind == "meteor_hit"), "Meteore angekündigt")
	t.eq(hero.health.hp, 100000.0, "erst Warnkreise, kein Sofortschaden")
	await t.frames(80)
	t.check(hero.health.hp < 100000.0, "der erste Meteor fällt auf den Helden")
	await _end(t, m)


func test_dragon_roar(t) -> void:
	var m := await _start(t)
	var hero := m.local_hero
	var drake := await _quiet_drake(t, m)
	var grunt := await _spawn(t, m, "grunt", Vector3(4, 0, 20), 5000.0)
	grunt.set_physics_process(false)
	_place_hero(hero, Vector3(0, 0, 10))
	var armor := hero.get_armor()
	var mr := hero.get_magic_resist()
	drake.brain._roar_left = 0.0
	await t.frames(80)
	t.check(hero.get_armor() < armor and hero.get_magic_resist() < mr,
		"Rüstung %.0f → %.0f, Magieresistenz %.0f → %.0f" % [armor, hero.get_armor(), mr, hero.get_magic_resist()])
	t.check(grunt.status.magnitude(StatusEffects.EMPOWER) > 0.0, "Diener in der Nähe verursachen mehr Schaden")
	await _end(t, m)
