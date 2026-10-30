extends RefCounted
## Fähigkeiten: Daten, Lernen, Slots, Wirken und die Wirkung jeder Fähigkeit in einer echten Runde.

const MATCH_SCENE := preload("res://scenes/main/match.tscn")


func _start(t, hero_id := "guardian", enemies := [{"enemy": "brute", "count": 3, "path": 1, "interval": 0.1}]) -> MatchController:
	Session.hero_id = hero_id
	var m: MatchController = MATCH_SCENE.instantiate()
	var groups: Array = enemies.duplicate()
	groups.append({"enemy": "grunt", "count": 1, "path": 0, "delay": 600})   # Nachzügler: Runde endet nicht
	m.waves_override = [GameData.normalize_wave({"prepare_seconds": 0, "groups": groups}, 1)]
	t.root.add_child(m)
	await t.frames(80)   # Spawn-Animationen abwarten
	for e in m.spawner.alive_enemies():
		e.set_physics_process(false)   # Gegner stehen still: Tests sind reproduzierbar
	m.gold.grant(1, 20000, "test", "test_gold")
	return m


func _end(t, m: MatchController) -> void:
	Session.hero_id = "guardian"
	m.queue_free()
	await t.frames(2)


func _learn(t, m: MatchController, id: String, level := 1) -> void:
	for i in level:
		var r := m.request_learn_ability(id)
		t.check(r.ok, "%s lernen/verbessern: %s" % [id, r.message])


func _cast(m: MatchController, id: String, target: Node3D = null, point := Vector3.ZERO) -> bool:
	var slot := m.local_hero.abilities.slots.find(id)
	m.local_hero.mana = 10000.0
	m.local_hero.abilities.cooldowns.clear()
	return m.request_cast(slot, target, point)


func _near(m: MatchController, e: Enemy, dist := 1.5) -> void:
	m.local_hero.global_position = e.global_position + Vector3(0, 0, dist)


func test_skill_data_valid(t) -> void:
	t.eq(GameData.errors.size(), 0, "Daten fehlerfrei: %s" % str(GameData.errors))
	for hero_id in GameData.hero_order:
		var normals := GameData.skill_order.filter(func(id: String) -> bool: return hero_id in GameData.skill(id).heroes and not GameData.skill(id).ultimate)
		var ults := GameData.skill_order.filter(func(id: String) -> bool: return hero_id in GameData.skill(id).heroes and GameData.skill(id).ultimate)
		t.check(normals.size() >= 4, "%s hat mindestens 4 eigene Fähigkeiten (%d)" % [hero_id, normals.size()])
		t.check(ults.size() >= 1, "%s hat mindestens ein Ultimate" % hero_id)
	for id in ["shield_bash", "taunt", "arcane_barrier", "shadow_strike", "poison_mark", "fireball", "frost_nova", "healing_pulse", "guardian_blessing", "fan_of_knives", "smoke_bomb", "chain_lightning", "iron_maelstrom"]:
		t.check(GameData.skills.has(id) and not GameData.skill(id).ultimate, "normale Fähigkeit vorhanden: %s" % id)
	for id in ["bastion", "shadow_dance", "blade_dance", "dagger_cyclone", "starfall", "sanctuary", "glacial_rift"]:
		var def := GameData.skill(id)
		t.check(def.get("ultimate", false), "Ultimate vorhanden: %s" % id)
		for lv in def.levels:
			t.check(lv.cooldown >= 90.0 and lv.cooldown <= 120.0, "%s: Abklingzeit 90–120 s" % id)
	for id in GameData.skill_order:
		var c: Array = GameData.skill(id).costs
		if not GameData.skill(id).ultimate:
			t.check(c[0] >= 250 and c[0] <= 350, "%s: erste Stufe kostet 250–350 Gold" % id)


func test_learn_slots_and_rules(t) -> void:
	var m := await _start(t)
	var caster := m.local_hero.abilities
	var before := m.gold.balance(1)
	_learn(t, m, "shield_bash")
	t.eq(caster.slots[0], "shield_bash", "erste Fähigkeit landet auf Q")
	t.eq(m.gold.balance(1), before - 300, "300 Gold bezahlt")
	_learn(t, m, "taunt")
	t.eq(caster.slots[1], "taunt", "zweite auf W")
	_learn(t, m, "shield_bash", 2)
	t.eq(caster.level_of("shield_bash"), 3, "Stufe 3")
	var r := m.request_learn_ability("shield_bash")
	t.check(not r.ok and r.message.contains("Höchststufe"), "nicht über Stufe 3: %s" % r.message)
	var u := m.request_learn_ability("bastion")
	t.check(not u.ok and u.message.contains("stufe 5"), "Ultimate erst ab Heldenstufe 5: %s" % u.message)
	m.local_hero.gain_xp(100000)
	_learn(t, m, "bastion")
	t.eq(caster.slots[AbilityCaster.ULT_SLOT], "bastion", "Ultimate liegt auf R")
	var other := m.request_learn_ability("starfall")
	t.check(not other.ok and other.message.contains("nur für"), "fremde Klasse: Fähigkeit nicht lernbar (%s)" % other.message)
	var foreign := m.request_learn_ability("fireball")
	t.check(not foreign.ok and foreign.message.contains("Arcanist"), "Guardian kann keinen Fireball lernen")
	t.check(caster.equip("taunt", AbilityCaster.ULT_SLOT) != "", "normale Fähigkeit nicht auf R")
	t.eq(caster.equip("taunt", 4), "", "Fähigkeit auf D verschieben")
	t.eq(caster.slots[4], "taunt", "liegt jetzt auf D")
	t.eq(caster.slots[1], "", "W ist frei")
	m.gold.spend(1, m.gold.balance(1), "test", "drain")
	var poor := m.request_learn_ability("guardian_blessing")
	t.check(not poor.ok and poor.message.contains("Nicht genug Gold"), "ohne Gold kein Lernen")
	t.check(not caster.knows("guardian_blessing"), "kein Lernen ohne Bezahlung")
	await _end(t, m)


func test_mana_and_cooldown(t) -> void:
	var m := await _start(t)
	_learn(t, m, "taunt")
	var hero := m.local_hero
	hero.mana = 100.0
	t.check(m.request_cast(0, null, hero.global_position), "Wirken klappt")
	t.eq(hero.mana, 60.0, "40 Mana verbraucht")
	t.check(hero.abilities.cooldown_left("taunt") > 13.0, "Abklingzeit läuft")
	t.check(not m.request_cast(0, null, hero.global_position), "während der Abklingzeit nicht wirkbar")
	hero.abilities.cooldowns.clear()
	hero.mana = 10.0
	t.check(not m.request_cast(0, null, hero.global_position), "ohne Mana nicht wirkbar")
	t.eq(hero.mana, 10.0, "kein Mana abgezogen")
	hero.mana = 100.0
	hero.status.apply(StatusEffects.STUN, 1.0)
	t.check(not m.request_cast(0, null, hero.global_position), "betäubt nicht wirkbar")
	hero.status.clear()
	await t.frames(60)
	hero.abilities.cooldowns["taunt"] = 1.0
	m.pause_menu.open()
	await t.frames(30)
	t.eq(hero.abilities.cooldown_left("taunt"), 1.0, "Abklingzeit steht in der Pause")
	m.pause_menu.close()
	await _end(t, m)


func test_shield_bash_and_taunt(t) -> void:
	var m := await _start(t)
	_learn(t, m, "shield_bash")
	_learn(t, m, "taunt")
	var e: Enemy = m.spawner.alive_enemies()[0]
	_near(m, e)
	var hp := e.health.hp
	t.check(_cast(m, "shield_bash", e), "Shield Bash gewirkt")
	t.check(e.health.hp < hp, "Shield Bash verursacht Schaden")
	t.check(e.status.is_stunned(), "und betäubt")
	e.status.clear()
	e.set_physics_process(true)
	e.target = m.core
	t.check(_cast(m, "taunt"), "Taunt gewirkt")
	t.eq(e.target, m.local_hero, "verspotteter Gegner greift den Tank an")
	await t.frames(30)
	t.eq(e.target, m.local_hero, "und bleibt beim Tank, solange Taunt wirkt")
	await _end(t, m)


func test_taunt_far_enemy_moves_to_tank(t) -> void:
	var m := await _start(t)
	_learn(t, m, "taunt")
	var e: Enemy = m.spawner.alive_enemies()[0]
	e.set_physics_process(true)
	var hero := m.local_hero
	hero.global_position = e.global_position + Vector3(0, 0, 5.5)
	_cast(m, "taunt")
	var d0 := hero.global_position.distance_to(e.global_position)
	await t.frames(40)
	t.check(hero.global_position.distance_to(e.global_position) < d0 - 1.0, "Gegner läuft zum verspottenden Helden")
	await _end(t, m)


func test_barrier_absorbs(t) -> void:
	var m := await _start(t, "guardian")
	_learn(t, m, "arcane_barrier")
	var hero := m.local_hero
	_cast(m, "arcane_barrier", hero)
	var shield := hero.health.shield_total()
	t.check(shield > 90.0, "Schild aufgebaut (%.0f, skaliert mit Stärke)" % shield)
	var hp := hero.health.hp
	m.combat.deal_damage(m.spawner.alive_enemies()[0], hero, 50, DamageInfo.Type.TRUE)
	t.eq(hero.health.hp, hp, "Schild absorbiert den Schaden vollständig")
	t.eq(snappedf(hero.health.shield_total(), 0.01), snappedf(shield - 50.0, 0.01), "Schild um 50 kleiner")
	await _end(t, m)


func test_shadow_strike_and_poison(t) -> void:
	var m := await _start(t, "shadow")
	_learn(t, m, "shadow_strike")
	_learn(t, m, "poison_mark", 3)
	var e: Enemy = m.spawner.alive_enemies()[0]
	var hero := m.local_hero
	hero.global_position = e.global_position + Vector3(0, 0, 6.0)
	var hp := e.health.hp
	t.check(_cast(m, "shadow_strike", e), "Shadow Strike gewirkt")
	t.check(hero.global_position.distance_to(e.global_position) < 2.0, "Held springt zum Ziel")
	t.check(e.health.hp < hp, "Schaden")
	for i in 5:
		_cast(m, "poison_mark", e)
	t.eq(e.status.stacks(StatusEffects.POISON), 3, "Gift stapelt nur bis 3 (Stufe 3)")
	var hp2 := e.health.hp
	await t.frames(130)
	t.check(e.health.hp < hp2, "Gift schadet über Zeit")
	await _end(t, m)


func test_fireball_frost_nova_starfall(t) -> void:
	var m := await _start(t, "arcanist", [{"enemy": "brute", "count": 3, "path": 1, "interval": 0.05}])
	_learn(t, m, "fireball")
	_learn(t, m, "frost_nova")
	var enemies := m.spawner.alive_enemies().duplicate()
	var center: Vector3 = enemies[0].global_position
	for e in enemies:
		e.global_position = center + Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0))
	var hero := m.local_hero
	hero.global_position = center + Vector3(0, 0, 8.0)
	var hps := enemies.map(func(e: Enemy) -> float: return e.health.hp)
	t.check(_cast(m, "fireball", null, center), "Feuerball gewirkt")
	await t.frames(40)
	var hit := 0
	for i in enemies.size():
		if enemies[i].health.hp < hps[i]:
			hit += 1
	t.check(hit >= 2, "Feuerball trifft mehrere Gegner im Umkreis (%d)" % hit)
	hero.global_position = center + Vector3(0, 0, 2.0)
	_cast(m, "frost_nova")
	t.check(enemies.all(func(e: Enemy) -> bool: return e.status.has(StatusEffects.SLOW)), "Frost Nova verlangsamt alle im Radius")
	hero.gain_xp(100000)
	_learn(t, m, "starfall")
	hero.set_physics_process(false)   # keine Auto-Angriffe während der Messung
	await t.wait_until(func() -> bool: return m.projectiles_root.get_child_count() == 0, 120)   # fliegende Geschosse abwarten
	var hp_before: float = enemies.map(func(e: Enemy) -> float: return e.health.hp).reduce(func(a, b): return a + b)
	t.check(_cast(m, "starfall", null, center), "Starfall gewirkt")
	await t.frames(10)
	var hp_mid: float = enemies.map(func(e: Enemy) -> float: return e.health.hp if e.is_alive() else 0.0).reduce(func(a, b): return a + b)
	t.eq(hp_mid, hp_before, "vor Ablauf der Vorwarnung noch kein Schaden (faire Warnung)")
	await t.frames(260)
	var hp_after: float = enemies.map(func(e: Enemy) -> float: return e.health.hp if e.is_alive() else 0.0).reduce(func(a, b): return a + b)
	t.check(hp_after < hp_before, "Starfall-Einschläge verursachen Schaden")
	await _end(t, m)


func test_support_abilities(t) -> void:
	# Heilung: Arcanist heilt einen verletzten Verbündeten
	var m := await _start(t, "arcanist")
	var ally: Hero = m._spawn_hero("guardian", 2)
	_learn(t, m, "healing_pulse")
	ally.global_position = m.local_hero.global_position + Vector3(2, 0, 0)
	m.combat.deal_damage(null, ally, 200, DamageInfo.Type.TRUE)
	var missing := ally.health.max_hp - ally.health.hp
	var healed := [0.0]
	ally.health.healed.connect(func(a: float, _s: Node) -> void: healed[0] += a)
	_cast(m, "healing_pulse")
	t.check(healed[0] > 0.0 and healed[0] <= missing + 0.01, "Heilung, aber nie mehr als fehlende Leben")
	await _end(t, m)

	# Segen: Guardian schützt einen Verbündeten
	m = await _start(t, "guardian")
	ally = m._spawn_hero("arcanist", 2)
	_learn(t, m, "guardian_blessing")
	ally.global_position = m.local_hero.global_position + Vector3(2, 0, 0)
	_cast(m, "guardian_blessing")
	t.check(ally.status.damage_reduction() > 0.0, "Segen reduziert Schaden")
	var dr := ally.status.damage_reduction()
	_cast(m, "guardian_blessing")
	t.eq(ally.status.damage_reduction(), dr, "Segen stapelt nicht")
	var hp := ally.health.hp
	m.combat.deal_damage(null, ally, 100, DamageInfo.Type.PHYSICAL)
	var expected := 100.0 * m.combat.armor_constant / (m.combat.armor_constant + ally.get_armor()) * (1.0 - dr)
	t.eq(snappedf(hp - ally.health.hp, 0.01), snappedf(expected, 0.01), "Schaden um die Reduktion verringert")
	await _end(t, m)


func test_ultimates_bastion_dance_sanctuary(t) -> void:
	var m := await _start(t, "guardian")
	var hero := m.local_hero
	hero.gain_xp(100000)
	_learn(t, m, "bastion")
	_cast(m, "bastion")
	t.check(hero.status.damage_reduction() >= 0.5, "Bastion: mindestens 50 % weniger Schaden")
	t.check(hero.status.damage_reduction() <= StatusEffects.MAX_DAMAGE_REDUCTION, "nie unverwundbar")
	await _end(t, m)

	m = await _start(t, "shadow")
	hero = m.local_hero
	hero.gain_xp(100000)
	_learn(t, m, "shadow_dance")
	var interval := hero.current_attack_interval()
	_cast(m, "shadow_dance")
	t.check(hero.current_attack_interval() < interval, "Shadow Dance: schnellere Angriffe")
	t.check(hero.status.move_multiplier() > 1.2, "und mehr Tempo")
	await _end(t, m)

	m = await _start(t, "arcanist")
	hero = m.local_hero
	var ally: Hero = m._spawn_hero("guardian", 2)
	ally.global_position = Vector3(20, 0, 20)   # weit weg: Sanctuary wirkt auf das ganze Team
	hero.gain_xp(100000)
	_learn(t, m, "sanctuary")
	_cast(m, "sanctuary")
	t.check(ally.status.damage_reduction() > 0.0, "Sanctuary wirkt auch auf entfernte Verbündete")
	await _end(t, m)


func test_blade_dance(t) -> void:
	var m := await _start(t, "shadow", [{"enemy": "brute", "count": 2, "path": 1, "interval": 0.1}])
	var hero := m.local_hero
	hero.gain_xp(100000)
	_learn(t, m, "blade_dance")
	var foes := m.spawner.alive_enemies()
	var e: Enemy = foes[0]
	e.health.setup(100000.0)
	_near(m, e, 3.0)
	var start := hero.global_position
	var hits := [0, 0]   # Treffer, davon kritisch
	m.combat.damage_applied.connect(func(target: Node3D, info: DamageInfo) -> void:
		if target == e:
			hits[0] += 1
			if info.is_crit:
				hits[1] += 1)
	t.check(_cast(m, "blade_dance", e, e.global_position), "Blade Dance gewirkt")
	t.check(hero.status.has(StatusEffects.UNTARGETABLE), "während des Tanzes nicht anvisierbar")
	t.eq(m.combat.deal_damage(e, hero, 500.0), 0.0, "und unverwundbar")
	t.check(m.spawner.nearest_hero(hero.global_position, 10.0) == null, "Gegner finden den Helden nicht")
	t.check(hero.global_position.distance_to(start) > 0.5, "erster Sprung sofort")
	var frames := 0
	while hero.status.has(StatusEffects.UNTARGETABLE) and frames < 120:
		await t.frames(1)
		frames += 1
	# nur bis zum Ende des Tanzes zählen: danach greift der Held wie gewohnt automatisch weiter an
	t.eq(hits[0], int(GameData.skill_value("blade_dance", 1, "hits", 0)), "jeder Sprung trifft das Ziel")
	t.check(frames <= 40, "Tanz dauert etwa eine halbe Sekunde (%d Bilder)" % frames)
	t.check(not hero.status.has(StatusEffects.UNTARGETABLE), "danach wieder angreifbar")
	var flat := Vector2(hero.global_position.x - e.global_position.x, hero.global_position.z - e.global_position.z).length()
	t.check(flat < 3.0, "endet neben dem Ziel (%.1f m)" % flat)
	t.check(m.combat.deal_damage(e, hero, 50.0) > 0.0, "danach wieder verwundbar")
	await _end(t, m)

	# Ziel stirbt mitten im Tanz: der Rest trifft den nächsten Gegner
	m = await _start(t, "shadow", [{"enemy": "brute", "count": 2, "path": 1, "interval": 0.1}])
	hero = m.local_hero
	hero.gain_xp(100000)
	_learn(t, m, "blade_dance")
	foes = m.spawner.alive_enemies()
	var weak: Enemy = foes[0]
	var other: Enemy = foes[1]
	other.global_position = weak.global_position + Vector3(2.0, 0, 0)
	other.health.setup(100000.0)
	weak.health.setup(1.0)
	_near(m, weak, 3.0)
	_cast(m, "blade_dance", weak, weak.global_position)
	await t.frames(60)
	t.check(not weak.is_alive(), "erstes Ziel besiegt")
	t.check(other.health.hp < 100000.0, "Rest der Sprünge trifft den nächsten Gegner")
	await _end(t, m)


func test_dagger_cyclone(t) -> void:
	var m := await _start(t, "shadow", [{"enemy": "brute", "count": 5, "path": 1, "interval": 0.1}])
	var hero := m.local_hero
	hero.gain_xp(100000)
	_learn(t, m, "dagger_cyclone")
	var foes := m.spawner.alive_enemies().duplicate()
	var center := Vector3(0, 0, 14)   # zwischen Kern und Brunnen der Erholung (im Brunnen wird nicht gekämpft)
	hero.global_position = center
	# vier Gegner in 2, 3, 4 und 5 m, einer außerhalb des Radius
	for i in foes.size():
		var e: Enemy = foes[i]
		e.health.setup(100000.0)
		e.global_position = center + Vector3(2.0 + i if i < 4 else 12.0, 0, 0)
	var hits := {}
	m.combat.damage_applied.connect(func(target: Node3D, _info: DamageInfo) -> void:
		hits[target] = int(hits.get(target, 0)) + 1)
	t.check(_cast(m, "dagger_cyclone"), "Dagger Cyclone gewirkt")
	t.check(hero.status.has(StatusEffects.CHANNEL), "kanalisiert")
	await t.frames(170)   # 2,5 s Wirbel plus Puffer
	var waves := int(GameData.skill_value("dagger_cyclone", 1, "duration", 0) / GameData.skill_value("dagger_cyclone", 1, "interval", 1))
	for i in 3:
		t.check(int(hits.get(foes[i], 0)) >= waves, "Gegner %d (nah) bekommt jede Welle ein Messer (%d)" % [i + 1, int(hits.get(foes[i], 0))])
	t.eq(int(hits.get(foes[3], 0)), 0, "höchstens drei Ziele: der vierte bleibt verschont")
	t.eq(int(hits.get(foes[4], 0)), 0, "außerhalb des Radius kein Treffer")
	t.check(hero.global_position.distance_to(center) < 0.01, "Held bleibt auf der Stelle")
	t.check(not hero.status.has(StatusEffects.CHANNEL), "danach vorbei")
	await _end(t, m)

	# Bewegungsbefehl bricht ab
	m = await _start(t, "shadow", [{"enemy": "brute", "count": 1, "path": 1, "interval": 0.1}])
	hero = m.local_hero
	hero.gain_xp(100000)
	_learn(t, m, "dagger_cyclone")
	var e2: Enemy = m.spawner.alive_enemies()[0]
	e2.health.setup(100000.0)
	_near(m, e2, 3.0)
	var count := [0]
	m.combat.damage_applied.connect(func(target: Node3D, _info: DamageInfo) -> void:
		if target == e2:
			count[0] += 1)
	_cast(m, "dagger_cyclone")
	await t.frames(20)
	hero.command_move_to(hero.global_position + Vector3(5, 0, 0))
	await t.frames(5)
	t.check(not hero.status.has(StatusEffects.CHANNEL), "Bewegen bricht den Wirbel ab")
	var after: int = count[0]
	await t.frames(60)
	t.eq(count[0], after, "danach keine Messer mehr")
	await _end(t, m)


func test_iron_maelstrom(t) -> void:
	var m := await _start(t, "guardian", [{"enemy": "brute", "count": 3, "path": 1, "interval": 0.1}])
	var hero := m.local_hero
	hero.gain_xp(100000)
	hero.rng.seed = 12345   # Krit-Würfe reproduzierbar
	_learn(t, m, "iron_maelstrom")
	var foes := m.spawner.alive_enemies().duplicate()
	var center := Vector3(0, 0, 14)   # zwischen Kern und Brunnen der Erholung (im Brunnen wird nicht gekämpft)
	hero.global_position = center
	for i in foes.size():
		var e: Enemy = foes[i]
		e.health.setup(100000.0)
		e.global_position = center + [Vector3(1.5, 0, 0), Vector3(-2.5, 0, 0), Vector3(9.0, 0, 0)][i]
	var hits := {}
	var dmg := {}
	var crits := [0, 0]   # kritisch, gesamt
	m.combat.damage_applied.connect(func(target: Node3D, info: DamageInfo) -> void:
		if target is Enemy and hero.status.has(StatusEffects.WHIRL):   # nur Wirbeltreffer, keine Angriffe danach
			hits[target] = int(hits.get(target, 0)) + 1
			dmg[target] = float(dmg.get(target, 0.0)) + info.final_amount
			crits[1] += 1
			if info.is_crit:
				crits[0] += 1)
	t.check(_cast(m, "iron_maelstrom"), "Iron Maelstrom gewirkt")
	t.check(hero.status.damage_reduction() >= 0.1, "Schutz beim Wirbeln (%.0f %%)" % (hero.status.damage_reduction() * 100.0))
	t.check(hero.status.has(StatusEffects.WHIRL), "wirbelt")
	await t.frames(30)
	hero.command_move_to(center + Vector3(0, 0, 0.6))   # frei beweglich, bleibt aber in Reichweite beider Gegner
	await t.frames(20)
	t.check(hero.global_position.distance_to(center) > 0.3, "läuft während des Wirbels")
	await t.frames(160)
	var ticks := int(GameData.skill_value("iron_maelstrom", 1, "duration", 0) / GameData.skill_value("iron_maelstrom", 1, "interval", 1))
	for i in 2:
		var n := int(hits.get(foes[i], 0))
		t.check(n >= ticks - 1 and n <= ticks + 1, "Gegner %d im Radius: %d Treffer (erwartet ~%d, keine normalen Angriffe dazwischen)" % [i + 1, n, ticks])
	t.eq(int(hits.get(foes[2], 0)), 0, "außerhalb des Radius kein Treffer")
	t.check(float(dmg.get(foes[0], 0.0)) > float(dmg.get(foes[1], 0.0)) * 1.2, "nächster Gegner nimmt deutlich mehr Schaden")
	t.check(crits[0] > 0 and crits[0] < crits[1], "einzelne Treffer kritisch (%d von %d)" % [crits[0], crits[1]])
	t.check(not hero.status.has(StatusEffects.WHIRL), "danach vorbei")
	await _end(t, m)


func test_glacial_rift(t) -> void:
	var m := await _start(t, "arcanist", [{"enemy": "brute", "count": 4, "path": 1, "interval": 0.1}])
	var hero := m.local_hero
	hero.gain_xp(100000)
	_learn(t, m, "glacial_rift")
	var foes := m.spawner.alive_enemies().duplicate()
	var center := Vector3(0, 0, 14)   # zwischen Kern und Brunnen der Erholung (im Brunnen wird nicht gekämpft)
	hero.global_position = center
	# in der Bahn bei 2,5 m und 6,2 m, einer seitlich daneben, einer hinter dem Ende der Bahn (7 m auf Stufe 1)
	var spots := [Vector3(2.5, 0, 0), Vector3(6.2, 0, 0.4), Vector3(4.0, 0, 3.0), Vector3(9.5, 0, 0)]
	for i in foes.size():
		var e: Enemy = foes[i]
		e.health.setup(100000.0)
		e.global_position = center + spots[i]
	hero.set_physics_process(false)   # keine Auto-Angriffe: gezählt wird nur das Eis
	t.check(_cast(m, "glacial_rift", null, center + Vector3(6, 0, 0)), "Glacial Rift gewirkt")
	await t.frames(6)
	t.eq(foes[0].health.hp, 100000.0, "während des Aufladens (0,3 s) noch kein Treffer")
	await t.frames(18)   # 0,3 s Aufladen, dann Front nach 0,1 s bei etwa 2,6 m
	t.check(foes[0].health.hp < 100000.0, "naher Gegner schon getroffen")
	t.eq(foes[1].health.hp, 100000.0, "ferner Gegner noch nicht: Welle läuft nach vorn")
	t.check(foes[0].status.is_stunned(), "Getroffene werden hochgeschleudert (betäubt)")
	t.check(foes[0].status.has(StatusEffects.SLOW), "und verlangsamt")
	var walls := m.projectiles_root.find_children("*", "StaticBody3D", true, false)
	t.check(not walls.is_empty(), "Eis steht als Hindernis")
	await t.frames(30)
	t.check(foes[1].health.hp < 100000.0, "ferner Gegner in der Bahn getroffen")
	t.eq(foes[2].health.hp, 100000.0, "Gegner neben der Bahn nicht getroffen")
	t.eq(foes[3].health.hp, 100000.0, "Gegner hinter dem Ende der Bahn nicht getroffen")
	var hp_once: float = foes[0].health.hp
	await t.frames(150)   # Eis bleibt 1,5 s und zersplittert
	t.eq(foes[0].health.hp, hp_once, "jeder Gegner nur einmal getroffen")
	t.check(m.projectiles_root.find_children("*", "StaticBody3D", true, false).is_empty(), "Eis ist wieder verschwunden")
	await _end(t, m)


func test_enemy_target_out_of_range_queues(t) -> void:
	var m := await _start(t)
	_learn(t, m, "shield_bash")
	var e: Enemy = m.spawner.alive_enemies()[0]
	var hero := m.local_hero
	hero.global_position = e.global_position + Vector3(0, 0, 8.0)
	t.check(_cast(m, "shield_bash", e), "Befehl angenommen")
	t.check(hero.abilities.is_queued(), "außer Reichweite: Held läuft erst hin")
	var done: bool = await t.wait_until(func() -> bool: return e.status.is_stunned(), 180)
	t.check(done, "und wirkt, sobald er in Reichweite ist")
	await _end(t, m)


func test_ranged_attacker_gets_aggro(t) -> void:
	var m := await _start(t, "arcanist", [{"enemy": "grunt", "count": 1, "path": 1}])
	var e: Enemy = m.spawner.alive_enemies()[0]
	e.set_physics_process(true)
	var hero := m.local_hero
	hero.global_position = e.global_position + Vector3(0, 0, 8.8)   # fast maximale Reichweite (9 m)
	hero.command_attack(e)
	var hit: bool = await t.wait_until(func() -> bool: return e.health.hp < e.health.max_hp, 180)
	t.check(hit, "Arcanist trifft aus maximaler Reichweite")
	await t.frames(5)
	t.eq(e.target, hero, "getroffener Gegner wendet sich dem Fernkämpfer zu (nicht dem Kern)")
	var d0 := hero.global_position.distance_to(e.global_position)
	hero.set_physics_process(false)
	await t.frames(40)
	t.check(e.global_position.distance_to(hero.global_position) < d0 - 1.0, "und läuft auf ihn zu")
	await _end(t, m)


func test_shop_opens_with_b_and_slot_click(t) -> void:
	var m := await _start(t)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_B
	ev.pressed = true
	t.root.push_input(ev)
	await t.frames(2)
	t.check(m.hud._shop.visible, "Taste B öffnet den Shop")
	t.eq(m.hud._shop._tabs.current_tab, 0, "Shop startet bei den Fähigkeiten")
	m.hud._shop.close()
	m.hud._ability_bar.shop_requested.emit(0)
	t.check(m.hud._shop.visible, "Klick auf einen Slot/den Shop-Knopf öffnet den Shop")
	await _end(t, m)


func test_new_class_skills(t) -> void:
	var m := await _start(t, "shadow", [{"enemy": "brute", "count": 3, "path": 1, "interval": 0.05}])
	_learn(t, m, "fan_of_knives")
	_learn(t, m, "smoke_bomb")
	var enemies := m.spawner.alive_enemies().duplicate()
	var hero := m.local_hero
	var center: Vector3 = enemies[0].global_position
	for e in enemies:
		e.global_position = center + Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0))
	hero.global_position = center + Vector3(0, 0, 1.5)
	var hps := enemies.map(func(e: Enemy) -> float: return e.health.hp)
	_cast(m, "fan_of_knives")
	var hit := 0
	for i in enemies.size():
		if enemies[i].health.hp < hps[i]:
			hit += 1
	t.eq(hit, enemies.size(), "Fan of Knives trifft alle Gegner im Umkreis")
	_cast(m, "smoke_bomb", null, center)
	t.check(enemies.all(func(e: Enemy) -> bool: return e.status.has(StatusEffects.SLOW)), "Smoke Bomb verlangsamt Gegner in der Wolke")
	t.check(hero.status.move_multiplier() > 1.0, "und macht den Shadow schneller")
	await _end(t, m)

	m = await _start(t, "arcanist", [{"enemy": "brute", "count": 3, "path": 1, "interval": 0.05}])
	_learn(t, m, "chain_lightning")
	enemies = m.spawner.alive_enemies().duplicate()
	center = enemies[0].global_position
	for i in enemies.size():
		enemies[i].global_position = center + Vector3(i * 3.0, 0, 0)   # Kette: je 3 m Abstand
	m.local_hero.global_position = center + Vector3(0, 0, 6.0)
	m.local_hero.set_physics_process(false)
	hps = enemies.map(func(e: Enemy) -> float: return e.health.hp)
	_cast(m, "chain_lightning", enemies[0])
	var struck := 0
	for i in enemies.size():
		if enemies[i].health.hp < hps[i]:
			struck += 1
	t.eq(struck, 3, "Chain Lightning springt über alle drei Gegner")
	await _end(t, m)


func test_skills_scale_with_attributes(t) -> void:
	var m := await _start(t, "arcanist")
	var hero := m.local_hero
	var before := AbilityEffects.power("fireball", 1, "damage", hero)
	for i in 5:
		m.request_attribute_upgrade("int")
	var after := AbilityEffects.power("fireball", 1, "damage", hero)
	t.check(after > before + 5.0 * 1.6 * 0.99, "5 Punkte Intelligenz: Fireball +≥ 8 Schaden (%.1f -> %.1f)" % [before, after])
	var lvl10 := AbilityEffects.power("fireball", 1, "damage", hero)
	hero.gain_xp(100000)
	t.check(AbilityEffects.power("fireball", 1, "damage", hero) > lvl10 * 1.5, "Heldenstufe (Attributwachstum) steigert den Fähigkeitsschaden deutlich")
	var text := UiTheme.format_skill_level("fireball", 1, hero)
	t.check(text.contains("Skalierung") and text.contains("Intelligenz"), "Skalierung wird angezeigt: %s" % text.get_slice("\n", 1))
	await _end(t, m)


func test_upgrade_preview_texts(t) -> void:
	var m := await _start(t, "arcanist")
	var hero := m.local_hero
	var up := UiTheme.format_skill_upgrade("fireball", 1, 2, hero)
	t.check(up.contains("Schaden") and up.contains("→"), "Fähigkeit: Verbesserung zeigt alt → neu: %s" % up)
	var dmg1 := roundi(AbilityEffects.power("fireball", 1, "damage", hero))
	var dmg2 := roundi(AbilityEffects.power("fireball", 2, "damage", hero))
	t.check(up.contains("Schaden %d → %d" % [dmg1, dmg2]), "Schadenswerte stimmen mit der Wirkung überein (%d → %d)" % [dmg1, dmg2])
	var mana_before := hero.stats.max_mana()
	var attr := UiTheme.format_attribute_upgrade(hero, "int")
	var per := hero.stats.points_per_buy()
	t.check(attr.contains("Mana +%d" % (12 * per)) and attr.contains("Fähigkeitsstärke +%d %%" % per), "Attribut: ein Intelligenz-Kauf zeigt die Zugewinne: %s" % attr)
	t.check(hero.stats.max_mana() == mana_before and hero.stats.bought.int == 0, "Vorschau verändert die echten Werte nicht")
	t.check(UiTheme.format_attribute_upgrade(hero, "str").contains("Leben +%d" % (20 * per)), "Stärke-Kauf: Leben +20 je Punkt")
	await _end(t, m)


func test_skill_animations_exist_on_class_models(t) -> void:
	for id in GameData.skill_order:
		var def := GameData.skill(id)
		for hero_id in def.heroes:
			var hdef := GameData.hero(hero_id)
			var visual := CharacterVisual.new()
			visual.setup(hdef.model, hdef.hidden_parts, hdef.model_scale, hdef.anims)
			visual.add_animation_libraries(hdef.anim_libraries)
			t.check(visual.anim_player != null and visual.anim_player.has_animation(def.anim),
				"%s: Animation '%s' auf %s vorhanden" % [id, def.anim, hero_id])
			if def.anim_start > 0.0 and visual.anim_player != null and visual.anim_player.has_animation(def.anim):
				visual.play_action(def.anim, def.anim_speed, def.anim_start)
				var expected: float = def.anim_start * visual.anim_player.get_animation(def.anim).length
				t.check(absf(visual.anim_player.current_animation_position - expected) < 0.01,
					"%s: Animation startet bei %d %% (Aufprall passt zum Effekt)" % [id, roundi(def.anim_start * 100.0)])
			visual.free()
