extends RefCounted
## Telemetrie: CSV-Speicher und Erfassung einer echten Runde.

const MATCH_SCENE := preload("res://scenes/main/match.tscn")


func _store(name: String) -> TelemetryStore:
	var dir := "user://telemetry_test_%s" % name
	for f in (DirAccess.get_files_at(dir) if DirAccess.dir_exists_absolute(dir) else PackedStringArray()):
		DirAccess.remove_absolute(dir.path_join(f))
	return TelemetryStore.new(dir)


func test_store_roundtrip(t) -> void:
	var s := _store("store")
	t.check(s.write_rows("transactions", [{"match_id": "m1", "tx_id": 1, "amount": 10, "reason": "kill", "ref": "kill:1, \"quoted\""}]), "erste Zeile geschrieben")
	t.check(s.write_rows("transactions", [{"match_id": "m1", "tx_id": 2, "amount": -100, "reason": "attribute", "ref": "attr:str:0"}]), "angehängt")
	var rows := s.read_rows("transactions")
	t.eq(rows.size(), 2, "zwei Zeilen, eine Kopfzeile")
	t.eq(rows[0].ref, "kill:1, \"quoted\"", "Kommas und Anführungszeichen bleiben erhalten")
	t.eq(rows[1].amount, "-100", "Werte korrekt")
	t.eq(rows[0].keys().size(), TelemetryStore.TABLES.transactions.size(), "alle Spalten vorhanden")
	t.check(not s.write_rows("gibts_nicht", [{"a": 1}]), "unbekannte Tabelle abgelehnt")


func _start(t, waves: Array) -> MatchController:
	Session.hero_id = "guardian"
	var m: MatchController = MATCH_SCENE.instantiate()
	var normalized := []
	var n := 0
	for w in waves:
		n += 1
		normalized.append(GameData.normalize_wave(w, n))
	m.waves_override = normalized
	t.root.add_child(m)
	await t.frames(2)
	return m


func test_match_is_recorded(t) -> void:
	var m := await _start(t, [{"prepare_seconds": 0, "groups": [{"enemy": "grunt", "count": 2, "path": 1}]}])
	var store := m.telemetry.store
	var id := m.telemetry.match_id
	await t.frames(80)
	m.request_attribute_upgrade("str")
	for e in m.spawner.alive_enemies().duplicate():
		m.combat.deal_damage(m.local_hero, e, 99999, DamageInfo.Type.TRUE, true)
	await t.wait_until(func() -> bool: return m.phase == MatchController.Phase.VICTORY, 60)
	t.eq(m.phase, MatchController.Phase.VICTORY, "Runde gewonnen")

	var matches := store.read_rows("matches").filter(func(r: Dictionary) -> bool: return r.match_id == id)
	t.eq(matches.size(), 1, "genau eine Rundenzeile")
	if matches.size() == 1:
		t.eq(matches[0].result, "victory", "Ergebnis")
		t.eq(matches[0].waves_completed, "1", "Wellen")
		t.eq(matches[0].heroes, "guardian", "Held")
	var waves := store.read_rows("wave_players").filter(func(r: Dictionary) -> bool: return r.match_id == id)
	t.eq(waves.size(), 1, "eine Wellenzeile je Spieler")
	if waves.size() == 1:
		var grunt_gold := int(GameData.enemy("grunt").gold)
		t.eq(int(waves[0].gold_kill), grunt_gold * 2, "Kill-Gold der Welle")
		t.eq(int(waves[0].gold_wave), 150, "Wellenbonus")
		t.eq(int(waves[0].gold_spent), 100, "Ausgaben (Attributkauf)")
		t.eq(int(waves[0].kill_participations), 2, "Kill-Beteiligungen")
		t.eq(int(waves[0].crits), 2, "Krits gezählt")
		t.check(int(waves[0].xp_gained) > 0, "XP erfasst")
	var enemies := store.read_rows("wave_enemies").filter(func(r: Dictionary) -> bool: return r.match_id == id)
	t.check(enemies.size() == 1 and enemies[0].enemy_id == "grunt" and enemies[0].killed == "2", "Gegnerstatistik: 2 Knochenläufer besiegt")
	var tx := store.read_rows("transactions").filter(func(r: Dictionary) -> bool: return r.match_id == id)
	t.eq(tx.map(func(r: Dictionary) -> String: return r.reason), ["start", "attribute", "kill", "kill", "wave_bonus", "wave_team"], "alle Gold-Buchungen in Reihenfolge (inkl. Team-Gold der Welle)")
	var ends := store.read_rows("hero_end").filter(func(r: Dictionary) -> bool: return r.match_id == id)
	t.check(ends.size() == 1 and ends[0].bought_str == "1", "Helden-Endstand mit gekauften Punkten")
	m.queue_free()
	await t.frames(2)
	var again := store.read_rows("matches").filter(func(r: Dictionary) -> bool: return r.match_id == id)
	t.eq(again.size(), 1, "Verlassen nach Rundenende schreibt keine zweite Zeile")


func test_aborted_match_is_recorded(t) -> void:
	var m := await _start(t, [{"prepare_seconds": 0, "groups": [{"enemy": "grunt", "count": 3, "path": 0}]}])
	var store := m.telemetry.store
	var id := m.telemetry.match_id
	await t.frames(10)
	m.queue_free()
	await t.frames(2)
	var rows := store.read_rows("matches").filter(func(r: Dictionary) -> bool: return r.match_id == id)
	t.check(rows.size() == 1 and rows[0].result == "aborted", "abgebrochene Runde als 'aborted' gespeichert")


func test_disabled_writes_nothing(t) -> void:
	Session.telemetry_enabled_override = false
	var m := await _start(t, [{"prepare_seconds": 0, "groups": [{"enemy": "grunt", "count": 1, "path": 0}]}])
	var store := m.telemetry.store
	var id := m.telemetry.match_id
	m.queue_free()
	await t.frames(2)
	Session.telemetry_enabled_override = null
	t.eq(store.read_rows("matches").filter(func(r: Dictionary) -> bool: return r.match_id == id).size(), 0, "ausgeschaltet: keine Daten")
