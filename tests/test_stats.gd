extends RefCounted
## StatBlock: Attribute, abgeleitete Werte, Obergrenzen, Kosten, Level/XP.


func _stats(id: String) -> StatBlock:
	return StatBlock.create(GameData.hero(id), GameData.attribute_rules)


func test_upgrade_cost_formula(t) -> void:
	var rules := GameData.attribute_rules
	t.eq(StatBlock.cost_for(0, rules), 100, "erster Punkt 100 Gold")
	t.eq(StatBlock.cost_for(1, rules), 116, "zweiter Punkt 116 Gold")
	t.eq(StatBlock.cost_for(2, rules), 135, "dritter Punkt 135 Gold")
	t.eq(StatBlock.cost_for(10, rules), roundi(100 * pow(1.16, 10)), "allgemeine Formel round(100 · 1.16^n)")
	for n in 60:
		t.check(StatBlock.cost_for(n + 1, rules) > StatBlock.cost_for(n, rules), "Kosten steigen streng (n=%d)" % n)
		if StatBlock.cost_for(n + 1, rules) <= StatBlock.cost_for(n, rules):
			break


func test_soft_cap_halves_effect(t) -> void:
	var s := _stats("guardian")
	s.bought["str"] = 40
	t.eq(s.effective_bought("str"), 40.0, "bis zum Soft Cap volle Wirkung")
	s.bought["str"] = 44
	t.eq(s.effective_bought("str"), 42.0, "darüber halbe Wirkung")
	t.check(s.is_beyond_soft_cap("str"), "Soft Cap erkannt")


func test_attributes_drive_derived_stats(t) -> void:
	var s := _stats("guardian")
	var hp0 := s.max_hp()
	var dmg0 := s.attack_damage()
	s.add_bought_point("str")
	t.eq(snappedf(s.max_hp() - hp0, 0.01), 20.0, "+1 Stärke = +20 Leben")
	t.check(s.attack_damage() > dmg0, "Stärke (Hauptattribut) erhöht den Schaden")
	var a := _stats("shadow")
	var interval0 := a.attack_interval()
	var crit0 := a.crit_chance()
	a.add_bought_point("agi")
	t.check(a.attack_interval() < interval0, "Beweglichkeit erhöht das Angriffstempo")
	t.check(a.crit_chance() > crit0, "Beweglichkeit erhöht die Krit-Chance")
	var m := _stats("arcanist")
	var mana0 := m.max_mana()
	var ap0 := m.ability_power()
	m.add_bought_point("int")
	t.eq(snappedf(m.max_mana() - mana0, 0.01), 12.0, "+1 Intelligenz = +12 Mana")
	t.check(m.ability_power() > ap0, "Intelligenz erhöht die Fähigkeitsstärke")


func test_caps_hold(t) -> void:
	var s := _stats("shadow")
	s.bought["agi"] = 2000
	t.check(s.crit_chance() <= 0.5 + 0.0001, "Krit-Chance gedeckelt bei 50 %% (%.3f)" % s.crit_chance())
	t.check(s.attack_interval() >= s.def.base_attack_interval / 2.5 - 0.0001, "Angriffstempo gedeckelt (+150 %%)")
	t.check(s.move_speed() <= 8.5 + 0.0001, "Lauftempo gedeckelt")
	var g := _stats("guardian")
	g.bought["str"] = 5000
	t.check(g.armor() <= 200.0 + 0.0001, "Rüstung gedeckelt")


func test_heroes_differ_by_role(t) -> void:
	var g := _stats("guardian")
	var s := _stats("shadow")
	var a := _stats("arcanist")
	t.check(g.max_hp() > s.max_hp() and g.max_hp() > a.max_hp(), "Guardian hat die meisten Leben")
	t.check(g.armor() > s.armor() and g.armor() > a.armor(), "Guardian hat die meiste Rüstung")
	var dps := func(x: StatBlock) -> float: return x.attack_damage() * (1.0 + x.crit_chance() * (x.crit_multiplier() - 1.0)) / x.attack_interval()
	t.check(dps.call(s) > dps.call(g) and dps.call(s) > dps.call(a), "Shadow hat den höchsten Einzelziel-DPS")
	t.check(a.attack_range() > 5.0 and a.max_mana() > g.max_mana(), "Arcanist: Fernkampf und meiste Mana")
	t.eq(a.damage_type(), DamageInfo.Type.MAGIC, "Arcanist macht magischen Schaden")


func test_level_up_and_growth(t) -> void:
	var s := _stats("guardian")
	var str1 := s.attribute("str")
	var levels := [0]
	s.leveled_up.connect(func(_l: int) -> void: levels[0] += 1)
	t.eq(s.add_xp(s.xp_to_next() - 1), 0, "knapp unter der Grenze kein Aufstieg")
	t.eq(s.add_xp(1), 1, "genau an der Grenze Aufstieg")
	t.eq(s.level, 2, "Stufe 2")
	t.eq(s.xp, 0, "Rest-XP 0")
	t.eq(snappedf(s.attribute("str") - str1, 0.01), 3.0, "Stärke wächst um 3 pro Stufe")
	var gained := s.add_xp(100000)
	t.eq(s.level, s.max_level(), "viele XP: Höchststufe, kein Überlauf")
	t.eq(levels[0], 1 + gained, "leveled_up für jede Stufe gemeldet")
	t.eq(s.add_xp(500), 0, "auf Höchststufe keine weiteren Aufstiege")
	t.eq(s.add_xp(-50), 0, "negative XP werden ignoriert")


func test_level_curve_reaches_target(t) -> void:
	var table: Array = GameData.attribute_rules.levels.xp_to_next
	var to_15 := 0
	for i in 14:
		to_15 += int(table[i])
	t.check(to_15 > 4000 and to_15 < 12000, "XP bis Stufe 15 in plausibler Größenordnung (%d)" % to_15)


func test_crit_roll(t) -> void:
	var s := _stats("shadow")
	s.bonus["crit_chance"] = 1.0   # erzwingt die Obergrenze von 50 %
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var crits := 0
	for i in 2000:
		var r := s.roll_attack(rng)
		if r.crit:
			crits += 1
			t.check(is_equal_approx(r.amount, s.attack_damage() * s.crit_multiplier()), "Krit-Schaden = Schaden × Multiplikator")
			if not is_equal_approx(r.amount, s.attack_damage() * s.crit_multiplier()):
				break
	t.check(crits > 900 and crits < 1100, "Krit-Quote entspricht der gedeckelten Chance (%d / 2000)" % crits)
