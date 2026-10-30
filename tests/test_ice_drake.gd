extends RefCounted
## Issue #9: Eisdrache – Elemente (immun gegen Eis, anfällig für Feuer und Gift), Hybrid aus Fern- und Nahkampf,
## Unterkühlung bei Treffern, Eisfeuer-Odem (Kegel), Schneesturm (Erfrierung bis zum Einfrieren), Arktischer Schrei.

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


## Boss steht still, eigene Fähigkeiten pausiert (einzeln im Test freigegeben)
func _quiet_drake(t, m: MatchController) -> Enemy:
	var drake := await _spawn(t, m, "ice_drake", Vector3(0, 0, 20), 20000.0)
	drake.set_physics_process(false)
	drake.brain._breath_left = 999.0
	drake.brain._blizzard_left = 999.0
	drake.brain._roar_left = 999.0
	return drake


func test_ice_drake_data(t) -> void:
	t.eq(GameData.errors.size(), 0, "Daten fehlerfrei: %s" % str(GameData.errors))
	var d := GameData.enemy("ice_drake")
	t.check(not d.is_empty(), "Eisdrache vorhanden")
	t.eq(float(d.elements.ice), 0.0, "immun gegen Eis")
	t.eq(float(d.elements.fire), 1.5, "anfällig für Feuer")
	t.eq(float(d.elements.poison), 1.5, "anfällig für Gift")
	t.check(float(d.armor) >= 50.0, "stark gepanzert (%.0f)" % float(d.armor))
	t.check(not d.projectile.is_empty() and not d.melee.is_empty(), "Fern- und Nahkampf")
	for key in ["frost_breath", "blizzard", "frost_roar"]:
		t.check(d.boss.has(key), "Bossfähigkeit %s" % key)
	t.check(GameData.waves[7].groups.any(func(g: Dictionary) -> bool: return g.enemy == "ice_drake"), "Welle 8 bringt den Eisdrachen")
	var v := CharacterVisual.new()
	v.setup(d.model, [], 1.0, {}, Color.WHITE)
	for anim in ["Idle", "Walk", "Attack_Bite", "Attack_Claw", "Fire_Breath", "Roar", "Hit", "Death"]:
		t.check(v.anim_player != null and v.anim_player.has_animation(anim), "Modell hat Animation %s" % anim)
	v.free()


func test_elements_and_ice_immunity(t) -> void:
	var m := await _start(t)
	var drake := await _quiet_drake(t, m)
	var hp := drake.health.hp
	m.combat.deal_damage(null, drake, 500.0, DamageInfo.Type.MAGIC, false, "ice")
	t.eq(drake.health.hp, hp, "Eisschaden prallt ab")
	var plain := m.combat.deal_damage(null, drake, 500.0, DamageInfo.Type.MAGIC)
	var fire := m.combat.deal_damage(null, drake, 500.0, DamageInfo.Type.MAGIC, false, "fire")
	t.check(absf(fire - plain * 1.5) < 0.5, "Feuer +50 %% (%.0f statt %.0f)" % [fire, plain])
	hp = drake.health.hp
	drake.status.dot_handler.call(null, 100.0, "poison")
	t.check(absf(hp - drake.health.hp - 150.0) < 0.5, "Gift +50 %% (%.0f)" % (hp - drake.health.hp))
	# Frost Nova des Arcanisten: kein Schaden, keine Verlangsamung
	var hero := m.local_hero
	_place_hero(hero, Vector3(0, 0, 18))
	hp = drake.health.hp
	AbilityEffects._frost_nova(3, hero, m)
	t.eq(drake.health.hp, hp, "Frost Nova macht keinen Schaden")
	t.check(not drake.status.has(StatusEffects.SLOW), "und verlangsamt nicht")
	await _end(t, m)


func test_chill_slows_attack_speed(t) -> void:
	var m := await _start(t)
	var hero := m.local_hero
	var before := hero.current_attack_interval()
	hero.status.apply(StatusEffects.CHILL, 3.0, 0.4)
	t.check(absf(hero.current_attack_interval() - before / 0.6) < 0.001, "Unterkühlung 40 %%: Angriffsintervall %.2f → %.2f s" % [before, hero.current_attack_interval()])
	await _end(t, m)


func test_hybrid_ranged_then_melee(t) -> void:
	var m := await _start(t)
	var hero := m.local_hero
	var drake := await _quiet_drake(t, m)
	drake.set_physics_process(true)
	var shots := [0]
	m.enemies_root.child_entered_tree.connect(func(n: Node) -> void:
		if n is Projectile:
			shots[0] += 1)
	_place_hero(hero, Vector3(0, 0, 13))   # 7 m: Fernkampf
	await t.frames(200)
	t.check(shots[0] >= 1, "aus der Distanz schießt er (%d Geschosse)" % shots[0])
	t.check(hero.status.has(StatusEffects.CHILL) or hero.health.hp < 100000.0, "Geschosse treffen")
	await t.frames(120)
	t.check(hero.status.has(StatusEffects.CHILL) and hero.status.has(StatusEffects.SLOW), "Unterkühlung: Lauf- und Angriffstempo gebremst")
	_place_hero(hero, drake.global_position + Vector3(0, 0, -2.8))   # dicht am Körper: Nahkampf
	hero.status.clear()
	await t.frames(30)
	shots[0] = 0
	var hp := hero.health.hp
	await t.frames(200)
	t.eq(shots[0], 0, "im Nahkampf keine Geschosse")
	t.check(hero.health.hp < hp, "sondern Hiebe (%.0f Schaden)" % (hp - hero.health.hp))
	await _end(t, m)


func test_frost_breath_hits_cone_only(t) -> void:
	var m := await _start(t)
	var front := m.local_hero
	var behind: Hero = m._spawn_hero("arcanist", 2)
	behind.set_physics_process(false)
	var drake := await _quiet_drake(t, m)
	_place_hero(front, Vector3(0, 0, 16))    # 4 m vor dem Drachen
	_place_hero(behind, Vector3(0, 0, 25))   # 5 m dahinter
	drake.brain._breath_left = 0.0
	await t.frames(3)
	t.check(drake.brain.is_casting(), "Odem wird angekündigt")
	t.eq(front.health.hp, 100000.0, "während der Warnung kein Schaden")
	await t.frames(70)
	t.eq(front.health.hp, 100000.0, "Schaden erst, wenn die Stacheln ankommen")
	await t.frames(40)
	t.check(front.health.hp < 100000.0, "im Kegel: Frostschaden")
	t.check(front.status.has(StatusEffects.SLOW) and front.status.has(StatusEffects.CHILL), "und stark verlangsamt")
	t.eq(behind.health.hp, 100000.0, "hinter dem Drachen: nichts")
	await _end(t, m)


func test_blizzard_stacks_until_frozen(t) -> void:
	var m := await _start(t)
	var hero := m.local_hero
	var drake := await _quiet_drake(t, m)
	_place_hero(hero, Vector3(0, 0, 12))
	m.combat.deal_damage(null, drake, drake.health.max_hp * 0.45, DamageInfo.Type.TRUE)
	t.eq(drake.brain.phase, 2, "Phase 2 unter 60 %")
	drake.brain._blizzard_left = 0.0
	var frozen := false
	var max_stacks := 0
	for i in 420:
		await t.frames(1)
		max_stacks = maxi(max_stacks, hero.status.stacks(StatusEffects.FROSTBITE))
		if hero.status.is_stunned():
			frozen = true
			break
	t.check(max_stacks >= 3, "Erfrierung stapelt (%d)" % max_stacks)
	t.check(frozen, "wer im Sturm bleibt, friert ein")
	t.check(hero.health.hp < 100000.0, "Sturm verursacht Schaden")
	await _end(t, m)


func test_frost_roar_buffs_allies_and_slows_heroes(t) -> void:
	var m := await _start(t)
	var hero := m.local_hero
	var drake := await _quiet_drake(t, m)
	var grunt := await _spawn(t, m, "grunt", Vector3(4, 0, 20), 5000.0)
	grunt.set_physics_process(false)
	_place_hero(hero, Vector3(0, 0, 10))   # 10 m: im großen Umkreis (14 m)
	var armor := grunt.get_armor()
	drake.brain._roar_left = 0.0
	await t.frames(80)
	t.check(grunt.get_armor() > armor, "Gegner gepanzert (%.0f → %.0f)" % [armor, grunt.get_armor()])
	t.check(hero.status.has(StatusEffects.SLOW) and hero.status.has(StatusEffects.CHILL), "Helden langsamer (Laufen und Angriff)")
	await _end(t, m)
