extends RefCounted
## Belohnungslogik: Anti-Exploit-Regeln und Rollenvergleich (Abrechnung ohne Szene).


func _rewards(players := 4) -> RewardService:
	var r := RewardService.new()
	r._ready()
	r.player_count = players
	return r


func test_no_gold_for_overheal_or_unused_shield(t) -> void:
	# Heilung/Schild kommen nur über effektive Werte an (HealthComponent liefert nur den effektiven Anteil)
	var h := HealthComponent.new()
	h.setup(100)
	var effective := [0.0]
	h.healed.connect(func(a: float, _s: Node) -> void: effective[0] += a)
	h.heal(50)
	t.eq(effective[0], 0.0, "volle Leben: Heilung zählt nicht")
	var absorbed := [0.0]
	h.shield_absorbed.connect(func(a: float, _s: Node) -> void: absorbed[0] += a)
	h.add_shield(100, 0.5)
	h._physics_process(1.0)
	t.eq(h.shield_total(), 0.0, "Schild läuft ungenutzt aus")
	t.eq(absorbed[0], 0.0, "ungenutzter Schild: keine Beteiligung")
	h.free()


func test_taunt_without_effect_gives_nothing(t) -> void:
	var r := _rewards()
	t.eq(r.add_control(1, 1, "taunt", 3.0, 1.0, false), 0.0, "Taunt ohne Zielwechsel: keine Punkte")
	t.check(r.add_control(1, 1, "taunt", 3.0, 1.0, true) > 0.0, "Taunt mit Zielwechsel: Punkte")
	t.eq(r.add_control(2, 1, "stun", 0.0), 0.0, "Kontrolle ohne neue Wirkdauer: keine Punkte")
	r.free()


func test_repeated_control_diminishes_and_caps(t) -> void:
	var r := _rewards()
	var first := r.add_control(5, 1, "stun", 1.0)
	var second := r.add_control(5, 1, "stun", 1.0)
	t.check(second < first, "Wiederholung am selben Ziel bringt weniger (%.3f < %.3f)" % [second, first])
	for i in 50:
		r.add_control(5, 1, "stun", 2.0)
	var share: float = r.shares_for(5, 100.0).get(1, 0.0)
	t.check(share <= r.control_cap + 0.0001, "Kontrollanteil je Gegner gedeckelt (%.2f)" % share)
	r.free()


func test_role_bonus_bounds_and_afk(t) -> void:
	var r := _rewards()
	r.add_support(1, "heal", 100000)
	var s := r.wave_payout(1, true)
	t.eq(s.role_bonus, r.role_bonus_max, "Rollenbonus höchstens 100")
	t.eq(s.support_gold, r.support_gold_cap, "Support-Gold gedeckelt")
	var none := r.wave_payout(2, true)
	t.eq(none.role_bonus, 0, "ohne Leistung kein Rollenbonus")
	var afk := r.wave_payout(1, false)
	t.eq(afk.wave_bonus + afk.role_bonus + afk.support_gold, 0, "AFK: keine Wellenbelohnungen")
	r.free()


func test_kill_gold_scales_with_players(t) -> void:
	var r := _rewards(4)
	r.add_damage(9, 1, 120.0)
	var split := r.settle_kill(9, 10, 120.0)
	t.eq(split.get(1, 0), roundi(10 * r.gold_multiplier()), "4 Spieler: Gegner-Gold steigt (×%.1f) – zusammen mit mehr Gegnern bleibt das Einkommen je Spieler stabil" % r.gold_multiplier())
	t.check(r.gold_multiplier() > 1.0, "Multiplikator > 1 bei mehreren Spielern")
	t.eq(r.settle_kill(9, 10, 120.0), {}, "ein Gegner wird nur einmal abgerechnet")
	r.free()


## Simulierte Welle mit vier aktiven Rollen. Annahmen (pro Welle, 4 Spieler):
## 24 Knochenläufer (120 LP, 10 Gold) und 4 Grabkolosse (480 LP, 15 Gold).
##  - Tank:     15 % des Schadens, verspottet die Hälfte der Gegner wirksam, fängt 900 Schaden ab, betäubt Kolosse
##  - Support:  10 % des Schadens, heilt 700 effektiv, Schilde absorbieren 300, Segen verhindert 250
##  - Magier:   40 % des Schadens, verlangsamt viele Gegner (Frost Nova)
##  - Schurke:  35 % des Schadens, Gift auf Kolossen
## Ziel aus der Vorgabe: vergleichbar aktive Spieler liegen höchstens ~10–15 % auseinander.
func test_roles_earn_comparable_gold(t) -> void:
	var r := _rewards(4)
	var g := GoldService.new()
	for p in [1, 2, 3, 4]:
		g.register_player(p, 0)
	var totals := {1: 0, 2: 0, 3: 0, 4: 0}
	var uid := 0
	var enemies := []
	for i in 24:
		enemies.append({"hp": 120.0, "gold": 10, "brute": false})
	for i in 4:
		enemies.append({"hp": 480.0, "gold": 15, "brute": true})
	for e in enemies:
		uid += 1
		var hp: float = e.hp
		r.add_damage(uid, 1, hp * 0.15)    # Tank
		r.add_damage(uid, 2, hp * 0.10)    # Support
		r.add_damage(uid, 3, hp * 0.40)    # Magier
		r.add_damage(uid, 4, hp * 0.35)    # Schurke
		if uid % 2 == 0:
			r.add_control(uid, 1, "taunt", 2.5, 1.0, true)
			r.add_tank(uid, 1, 900.0 / 14.0)
		if e.brute:
			r.add_control(uid, 1, "stun", 1.5)
		if uid % 3 == 0:
			r.add_control(uid, 3, "slow", 2.5, 0.5)
		var split := r.settle_kill(uid, e.gold, hp)
		for p in split:
			totals[p] += split[p]
	r.add_support(2, "heal", 700.0)
	r.add_support(2, "shield", 300.0)
	r.add_support(2, "prevented", 250.0)
	for p in [1, 2, 3, 4]:
		var s := r.wave_payout(p, true)
		totals[p] += s.wave_bonus + s.support_gold + s.role_bonus
	var values: Array = totals.values()
	var lo: float = values.min()
	var hi: float = values.max()
	print("    Gold je Rolle in der simulierten Welle: Tank %d · Support %d · Magier %d · Schurke %d" % [totals[1], totals[2], totals[3], totals[4]])
	t.check(lo >= 300 and hi <= 450, "aktive Spieler verdienen 300–450 Gold je Welle (%d–%d)" % [lo, hi])
	t.check(hi / lo <= 1.15, "Abstand zwischen den Rollen höchstens 15 %% (%.1f %%)" % ((hi / lo - 1.0) * 100.0))
	r.free()
	g.free()
