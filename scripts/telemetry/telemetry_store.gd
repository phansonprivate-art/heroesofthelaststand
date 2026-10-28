class_name TelemetryStore
extends RefCounted
## Schreibt Telemetrie-Zeilen als CSV-Tabellen (eine Datei je Tabelle, Kopfzeile beim Anlegen).
## Bewusst ohne native Abhängigkeit: die Dateien lassen sich direkt in SQLite, Excel o. Ä. importieren.
## Ein anderes Speicherziel (z. B. SQLite) muss nur write_rows() mit derselben Bedeutung anbieten.

## Tabellen und ihre Spalten. Neue Spalten nur hinten anhängen, damit alte Dateien lesbar bleiben;
## bei inkompatiblen Änderungen SCHEMA_VERSION erhöhen (landet in jeder Runde).
const SCHEMA_VERSION := 2
const TABLES := {
	"matches": ["match_id", "schema", "game_version", "started_at", "ended_at", "duration_s", "result",
		"player_count", "heroes", "waves_completed", "waves_total", "core_hp_end", "core_hp_max", "kills_total"],
	"wave_players": ["match_id", "wave", "peer_id", "hero_id", "wave_duration_s", "level_start", "level_end",
		"xp_gained", "gold_kill", "gold_wave", "gold_other", "gold_spent", "gold_end", "damage_dealt",
		"damage_physical", "damage_magic", "crits", "hits", "damage_taken", "kill_participations", "deaths", "gold_support", "gold_role", "healing", "shield_absorbed", "damage_prevented",
		"control_points", "tanked", "afk", "abilities_cast"],
	"wave_abilities": ["match_id", "wave", "peer_id", "hero_id", "ability_id", "level", "casts"],
	"wave_enemies": ["match_id", "wave", "enemy_id", "spawned", "killed", "avg_lifetime_s",
		"damage_to_core", "damage_to_heroes", "damage_received"],
	"transactions": ["match_id", "tx_id", "time_s", "wave", "peer_id", "hero_id", "amount", "reason", "ref", "balance"],
	"level_ups": ["match_id", "time_s", "wave", "peer_id", "hero_id", "level"],
	"hero_end": ["match_id", "peer_id", "hero_id", "level", "total_xp", "bought_str", "bought_agi", "bought_int",
		"str", "agi", "int", "max_hp", "attack_damage", "attacks_per_s", "crit_chance", "armor",
		"gold_end", "gold_earned", "gold_spent", "deaths"],
}

var directory := "user://telemetry"


func _init(p_directory: String) -> void:
	directory = p_directory


func path_for(table: String) -> String:
	return directory.path_join(table + ".csv")


## Hängt Zeilen (Dictionaries Spalte -> Wert) an die Tabelle an. Gibt false bei Fehlern zurück.
func write_rows(table: String, rows: Array) -> bool:
	if rows.is_empty():
		return true
	if not TABLES.has(table):
		push_error("Telemetrie: unbekannte Tabelle %s" % table)
		return false
	if DirAccess.make_dir_recursive_absolute(directory) != OK and not DirAccess.dir_exists_absolute(directory):
		push_error("Telemetrie: Ordner nicht anlegbar: %s" % directory)
		return false
	var path := path_for(table)
	_rotate_if_schema_changed(path, TABLES[table])
	var is_new := not FileAccess.file_exists(path)
	var f := FileAccess.open(path, FileAccess.WRITE if is_new else FileAccess.READ_WRITE)
	if f == null:
		push_error("Telemetrie: %s nicht schreibbar (%s)" % [path, error_string(FileAccess.get_open_error())])
		return false
	var columns: Array = TABLES[table]
	if is_new:
		f.store_csv_line(PackedStringArray(columns))
	else:
		f.seek_end()
	for row: Dictionary in rows:
		var line := PackedStringArray()
		for c in columns:
			line.append(_format(row.get(c, "")))
		f.store_csv_line(line)
	f.close()
	return true


## Passt die Kopfzeile einer vorhandenen Datei nicht zum aktuellen Schema, wird sie umbenannt
## (z. B. wave_players_alt_20261027-153000.csv) statt Zeilen unterschiedlicher Form zu mischen.
func _rotate_if_schema_changed(path: String, columns: Array) -> void:
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var header := f.get_csv_line()
	f.close()
	if header == PackedStringArray(columns):
		return
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "-")
	DirAccess.rename_absolute(path, path.get_basename() + "_alt_%s.csv" % stamp)


## Liest eine Tabelle als Liste von Dictionaries (für Auswertung und Tests).
func read_rows(table: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var path := path_for(table)
	if not FileAccess.file_exists(path):
		return result
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return result
	var header := f.get_csv_line()
	while not f.eof_reached():
		var line := f.get_csv_line()
		if line.size() < header.size():
			continue
		var row := {}
		for i in header.size():
			row[header[i]] = line[i]
		result.append(row)
	return result


static func _format(v: Variant) -> String:
	if v is float:
		return str(snappedf(v, 0.01))
	return str(v)
