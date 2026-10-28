extends RefCounted
## Shop: Ausrüstung, Inventar, Verbrauch, Team-Gold und Kern-Upgrades.

const MATCH_SCENE := preload("res://scenes/main/match.tscn")


func _start(t) -> MatchController:
	Session.hero_id = "guardian"
	var m: MatchController = MATCH_SCENE.instantiate()
	m.waves_override = [GameData.normalize_wave({"prepare_seconds": 60, "groups": [{"enemy": "grunt", "count": 1, "path": 0}]}, 1)]
	t.root.add_child(m)
	await t.frames(2)
	return m


func _end(t, m: MatchController) -> void:
	m.queue_free()
	await t.frames(2)


func test_item_data(t) -> void:
	for id in ["iron_blade", "guardian_plate", "shadow_boots", "arcane_focus", "healing_amulet", "ring_of_haste", "phoenix_potion", "protection_rune"]:
		t.check(GameData.items.has(id), "Gegenstand vorhanden: %s" % id)


func test_buy_equip_and_stats(t) -> void:
	var m := await _start(t)
	var hero := m.local_hero
	var dmg := hero.stats.attack_damage()
	var r := m.request_buy_item("iron_blade")
	t.check(r.ok, "Iron Blade gekauft")
	t.eq(m.gold.balance(1), 50, "450 Gold bezahlt")
	t.eq(hero.inventory.equipment.get("weapon", ""), "iron_blade", "direkt angelegt")
	t.eq(snappedf(hero.stats.attack_damage() - dmg, 0.01), 14.0, "Angriff +14")
	var fail := m.request_buy_item("guardian_plate")
	t.check(not fail.ok and fail.message.contains("Nicht genug Gold"), "zu teuer: Grund angegeben")
	t.eq(m.gold.balance(1), 50, "kein Abzug bei Fehlschlag")
	var sold := m.request_sell("weapon")
	t.check(sold.ok, "verkauft")
	t.eq(m.gold.balance(1), 50 + 225, "50 %% zurück")
	t.eq(snappedf(hero.stats.attack_damage(), 0.01), snappedf(dmg, 0.01), "Bonus entfernt")
	await _end(t, m)


func test_bag_and_swap(t) -> void:
	var m := await _start(t)
	var hero := m.local_hero
	m.gold.grant(1, 5000, "test", "test")
	m.request_buy_item("iron_blade")
	m.request_buy_item("arcane_focus")
	t.eq(hero.inventory.equipment.weapon, "iron_blade", "erste Waffe angelegt")
	t.eq(hero.inventory.bag, ["arcane_focus"], "zweite Waffe in der Tasche")
	m.request_equip_from_bag(0)
	t.eq(hero.inventory.equipment.weapon, "arcane_focus", "getauscht")
	t.eq(hero.inventory.bag, ["iron_blade"], "alte Waffe in der Tasche")
	t.check(hero.stats.ability_power() > 1.1, "Fokus-Bonus wirkt")
	await _end(t, m)


func test_consumables(t) -> void:
	var m := await _start(t)
	var hero := m.local_hero
	m.gold.grant(1, 5000, "test", "test")
	for i in 3:
		t.check(m.request_buy_item("phoenix_potion").ok, "Trank %d" % (i + 1))
	t.eq(hero.inventory.consumables[0].count, 3, "stapelt bis 3")
	m.request_buy_item("phoenix_potion")
	t.eq(hero.inventory.consumables[1].get("count", 0), 1, "vierter in Slot 2")
	m.combat.deal_damage(null, hero, 500, DamageInfo.Type.TRUE)
	var hp := hero.health.hp
	t.check(m.request_use_consumable(0).ok, "benutzt")
	t.check(hero.health.hp > hp, "heilt")
	t.eq(hero.inventory.consumables[0].count, 2, "eine Ladung weniger")
	t.check(m.request_buy_item("protection_rune").ok == false, "beide Slots belegt: Rune passt nicht")
	await _end(t, m)


func test_team_gold_and_core_upgrades(t) -> void:
	var m := await _start(t)
	t.eq(m.gold.team_balance(), 0, "Team-Gold startet bei 0")
	var poor := m.request_team_upgrade("core_hp")
	t.check(not poor.ok and poor.message.contains("Team-Gold"), "ohne Team-Gold kein Upgrade")
	t.eq(m.gold.balance(1), 500, "persönliches Gold wird nicht stillschweigend genutzt")
	t.check(m.request_donate(100).ok, "Spende")
	t.eq(m.gold.balance(1), 400, "100 persönliches Gold weniger")
	t.eq(m.gold.team_balance(), 100, "100 Team-Gold mehr")
	m.gold.grant_team(5000, "test", "test")
	var max_hp := m.core.health.max_hp
	t.check(m.request_team_upgrade("core_hp").ok, "Kern-Upgrade gekauft")
	t.eq(m.core.health.max_hp, max_hp + 1000.0, "+1.000 maximale Kernleben")
	t.check(m.request_team_upgrade("core_regen").ok, "Regeneration gekauft")
	m.combat.deal_damage(null, m.core, 500, DamageInfo.Type.TRUE)
	var hp := m.core.health.hp
	await t.frames(60)
	t.check(m.core.health.hp > hp, "Kern regeneriert")
	t.check(m.request_team_upgrade("core_barrier").ok, "Barriere gekauft")
	m.wave_manager.skip_preparation()
	await t.frames(3)
	t.eq(m.core.health.shield_total(), 500.0, "Barriere zu Wellenbeginn")
	m.request_team_upgrade("core_hp")
	m.request_team_upgrade("core_hp")
	var maxed := m.request_team_upgrade("core_hp")
	t.check(not maxed.ok and maxed.message.contains("Höchststufe"), "Upgrades sind begrenzt")
	await _end(t, m)
