extends RefCounted
## GoldService und Aufteilung von Belohnungen.


func _gold() -> GoldService:
	var g := GoldService.new()
	g.register_player(1, 500)
	return g


func test_start_gold(t) -> void:
	var g := _gold()
	t.eq(g.balance(1), 500, "Startgold 500")
	g.register_player(1, 500)
	t.eq(g.balance(1), 500, "doppelte Registrierung bucht nicht erneut")
	g.free()


func test_spend_never_negative(t) -> void:
	var g := _gold()
	t.check(not g.spend(1, 600, "test", "a"), "zu teuer: abgelehnt")
	t.eq(g.balance(1), 500, "kein Abzug bei Fehlschlag")
	t.check(g.spend(1, 500, "test", "b"), "genau passend: ok")
	t.eq(g.balance(1), 0, "Kontostand 0, nicht negativ")
	t.check(not g.spend(1, 1, "test", "c"), "bei 0 nichts mehr kaufbar")
	t.check(not g.spend(1, -50, "test", "d"), "negativer Betrag abgelehnt")
	t.check(not g.grant(1, 0, "test", "e"), "0 Gold wird nicht gebucht")
	t.eq(g.balance(1), 0, "unverändert")
	g.free()


func test_duplicate_refs_rejected(t) -> void:
	var g := _gold()
	t.check(g.grant(1, 10, "kill", "kill:7"), "erste Belohnung")
	t.check(not g.grant(1, 10, "kill", "kill:7"), "dieselbe Belohnung nicht doppelt")
	t.check(g.spend(1, 100, "attribute", "attr:str:0"), "Kauf")
	t.check(not g.spend(1, 100, "attribute", "attr:str:0"), "derselbe Kauf nicht doppelt (Doppelklick)")
	t.eq(g.balance(1), 410, "Kontostand korrekt")
	t.check(not g.grant(2, 10, "kill", "kill:8"), "unbekannter Spieler bekommt nichts")
	g.free()


func test_transaction_log(t) -> void:
	var g := _gold()
	g.grant(1, 25, "kill", "kill:1")
	g.spend(1, 100, "attribute", "attr:agi:0")
	var log := g.transactions(1)
	t.eq(log.size(), 3, "drei Buchungen (Start, Kill, Kauf)")
	t.eq(log[2].amount, -100, "Ausgabe negativ protokolliert")
	t.eq(log[2].balance, 425, "Kontostand nach Buchung protokolliert")
	var ids := log.map(func(e: Dictionary) -> int: return e.id)
	t.eq(ids, [1, 2, 3], "eindeutige, fortlaufende IDs")
	t.eq(g.totals_by_reason(1), {"start": 500, "kill": 25, "attribute": -100}, "Summen nach Grund")
	g.free()


func test_split_by_share(t) -> void:
	t.eq(RewardService.split_by_share(10, {1: 100.0}), {1: 10}, "ein Beteiligter bekommt alles")
	var s := RewardService.split_by_share(10, {1: 50.0, 2: 50.0})
	t.eq(s, {1: 5, 2: 5}, "gleiche Anteile")
	var s3 := RewardService.split_by_share(10, {1: 1.0, 2: 1.0, 3: 1.0})
	t.eq(s3.values().reduce(func(a, b): return a + b), 10, "Summe exakt erhalten (größter Rest)")
	var tiny := RewardService.split_by_share(12, {1: 99.0, 2: 1.0})
	t.eq(tiny[1] + tiny[2], 12, "Summe exakt")
	t.check(tiny[1] > tiny[2], "größerer Anteil bekommt mehr")
	t.eq(RewardService.split_by_share(10, {}), {}, "ohne Beteiligte keine Belohnung")
	t.eq(RewardService.split_by_share(0, {1: 5.0}), {}, "0 Gold: nichts")
