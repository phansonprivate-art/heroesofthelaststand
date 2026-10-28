extends SceneTree
## Balancing-Auswertung der gesammelten Telemetrie (Markdown-Tabellen auf der Konsole).
##   godot --headless --path . -s res://tools/telemetry_report.gd -- [ordner]
## Standardordner: user://telemetry (Pfad wird am Anfang ausgegeben).

var store


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var dir := args[0] if args.size() > 0 else "user://telemetry"
	store = load("res://scripts/telemetry/telemetry_store.gd").new(dir)
	print("Telemetrie-Ordner: ", ProjectSettings.globalize_path(dir))
	var matches: Array = store.read_rows("matches")
	if matches.is_empty():
		print("Noch keine Daten. Eine Runde spielen (auch abgebrochene Runden werden gespeichert).")
		quit()
		return
	_matches(matches)
	_heroes()
	_waves()
	_enemies()
	_purchases()
	_abilities()
	quit()


func _matches(rows: Array) -> void:
	var by_result := {}
	var duration := 0.0
	for r in rows:
		by_result[r.result] = by_result.get(r.result, 0) + 1
		duration += float(r.duration_s)
	print("\n## Runden\n")
	print("Anzahl: %d  ·  Ergebnisse: %s  ·  Ø Dauer: %s" % [rows.size(), str(by_result), _time(duration / rows.size())])


func _heroes() -> void:
	var waves: Array = store.read_rows("wave_players")
	var ends: Array = store.read_rows("hero_end")
	var agg := {}
	for r in waves:
		var a: Dictionary = agg.get(r.hero_id, {"waves": 0, "gold_kill": 0.0, "gold_wave": 0.0, "gold_support": 0.0, "gold_role": 0.0, "heal": 0.0, "control": 0.0, "xp": 0.0, "dmg": 0.0, "taken": 0.0, "deaths": 0.0, "hits": 0.0, "crits": 0.0})
		a.waves += 1
		a.gold_kill += float(r.gold_kill)
		a.gold_wave += float(r.gold_wave)
		a.gold_support += float(r.get("gold_support", 0))
		a.gold_role += float(r.get("gold_role", 0))
		a.heal += float(r.get("healing", 0)) + float(r.get("shield_absorbed", 0)) + float(r.get("damage_prevented", 0))
		a.control += float(r.get("control_points", 0))
		a.xp += float(r.xp_gained)
		a.dmg += float(r.damage_dealt)
		a.taken += float(r.damage_taken)
		a.deaths += float(r.deaths)
		a.hits += float(r.hits)
		a.crits += float(r.crits)
		agg[r.hero_id] = a
	var levels := {}
	for r in ends:
		var l: Array = levels.get(r.hero_id, [])
		l.append(float(r.level))
		levels[r.hero_id] = l
	print("\n## Helden (Durchschnitt je Welle)\n")
	print("| Held | Wellen | Kill-Gold | Wellen-Gold | Support-Gold | Rollenbonus | Gold gesamt | XP | Schaden | Heilung+Schild | Kontrolle | erlittener Schaden | Tode | Krit-Quote | Ø Endstufe |")
	print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
	for id in agg:
		var a: Dictionary = agg[id]
		var n := float(a.waves)
		var lv: Array = levels.get(id, [])
		var avg_level: float = lv.reduce(func(s, v): return s + v, 0.0) / lv.size() if not lv.is_empty() else 0.0
		print("| %s | %d | %.0f | %.0f | %.0f | %.0f | %.0f | %.0f | %.0f | %.0f | %.2f | %.0f | %.2f | %.0f %% | %.1f |" % [id, a.waves, a.gold_kill / n, a.gold_wave / n,
			a.gold_support / n, a.gold_role / n, (a.gold_kill + a.gold_wave + a.gold_support + a.gold_role) / n, a.xp / n, a.dmg / n, a.heal / n, a.control / n, a.taken / n, a.deaths / n, 100.0 * a.crits / maxf(1.0, a.hits), avg_level])


func _waves() -> void:
	var rows: Array = store.read_rows("wave_players")
	var agg := {}
	for r in rows:
		var w := int(r.wave)
		var a: Dictionary = agg.get(w, {"n": 0, "gold": 0.0, "xp": 0.0, "dur": 0.0, "level": 0.0})
		a.n += 1
		a.gold += float(r.gold_kill) + float(r.gold_wave)
		a.xp += float(r.xp_gained)
		a.dur += float(r.wave_duration_s)
		a.level += float(r.level_end)
		agg[w] = a
	print("\n## Wellen (Durchschnitt je Spieler)\n")
	print("| Welle | Datensätze | Gold | XP | Dauer | Stufe am Ende |")
	print("|---|---|---|---|---|---|")
	var keys := agg.keys()
	keys.sort()
	for w in keys:
		var a: Dictionary = agg[w]
		var n := float(a.n)
		print("| %d | %d | %.0f | %.0f | %s | %.1f |" % [w, a.n, a.gold / n, a.xp / n, _time(a.dur / n), a.level / n])


func _enemies() -> void:
	var rows: Array = store.read_rows("wave_enemies")
	var agg := {}
	for r in rows:
		var a: Dictionary = agg.get(r.enemy_id, {"spawned": 0.0, "killed": 0.0, "life": 0.0, "core": 0.0, "heroes": 0.0})
		a.spawned += float(r.spawned)
		a.killed += float(r.killed)
		a.life += float(r.avg_lifetime_s) * float(r.killed)
		a.core += float(r.damage_to_core)
		a.heroes += float(r.damage_to_heroes)
		agg[r.enemy_id] = a
	print("\n## Gegner\n")
	print("| Gegner | gespawnt | besiegt | Ø Lebensdauer | Kernschaden je Gegner | Heldenschaden je Gegner |")
	print("|---|---|---|---|---|---|")
	for id in agg:
		var a: Dictionary = agg[id]
		print("| %s | %d | %d | %s | %.1f | %.1f |" % [id, a.spawned, a.killed, _time(a.life / maxf(1.0, a.killed)),
			a.core / maxf(1.0, a.spawned), a.heroes / maxf(1.0, a.spawned)])


func _purchases() -> void:
	var rows: Array = store.read_rows("transactions")
	var agg := {}
	for r in rows:
		if r.reason != "attribute":
			continue
		var attr := String(r.ref).split(":")[1] if String(r.ref).count(":") >= 2 else "?"
		var key := "%s / %s" % [r.hero_id, attr]
		agg[key] = agg.get(key, 0) + 1
	print("\n## Attribut-Käufe (Held / Attribut: Anzahl)\n")
	if agg.is_empty():
		print("Noch keine Käufe.")
	for k in agg:
		print("- %s: %d" % [k, agg[k]])


func _abilities() -> void:
	var agg := {}
	for r in store.read_rows("wave_abilities"):
		var key := "%s / %s" % [r.hero_id, r.ability_id]
		agg[key] = agg.get(key, 0) + int(r.casts)
	print("
## Fähigkeiten (Held / Fähigkeit: Anzahl gewirkt)
")
	if agg.is_empty():
		print("Noch keine Fähigkeiten gewirkt.")
	for k in agg:
		print("- %s: %d" % [k, agg[k]])


func _time(seconds: float) -> String:
	return "%d:%02d" % [int(seconds) / 60, int(seconds) % 60]
