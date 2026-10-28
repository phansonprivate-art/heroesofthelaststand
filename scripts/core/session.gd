extends Node
## Hält die Auswahl zwischen Menü und Runde (Held, später Lobby/Spielerzahl) und wechselt die Szenen.

const MENU_SCENE := "res://scenes/main/main_menu.tscn"
const MATCH_SCENE := "res://scenes/main/match.tscn"

var hero_id := "guardian"
var player_count := 1
## Überschreibt Telemetrie-Ordner/-Schalter (Tests und Werkzeuge schreiben so nicht in die echten Daten).
var telemetry_directory_override := ""
var telemetry_enabled_override: Variant = null


func telemetry_directory() -> String:
	if not telemetry_directory_override.is_empty():
		return telemetry_directory_override
	return String(GameData.setting("telemetry", "directory", "user://telemetry"))


func telemetry_enabled() -> bool:
	if telemetry_enabled_override != null:
		return bool(telemetry_enabled_override)
	return bool(GameData.setting("telemetry", "enabled", true))


func _ready() -> void:
	InputSetup.register()
	hero_id = String(GameData.setting("heroes", "default_hero", "guardian"))


func start_singleplayer(selected_hero: String) -> void:
	if GameData.hero(selected_hero).is_empty():
		push_error("Unbekannter Held: %s" % selected_hero)
		return
	hero_id = selected_hero
	player_count = 1
	_change_scene(MATCH_SCENE)


func restart_match() -> void:
	_change_scene(MATCH_SCENE)


func return_to_menu() -> void:
	_change_scene(MENU_SCENE)


func _change_scene(path: String) -> void:
	get_tree().paused = false
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("Szene konnte nicht geladen werden: %s (%s)" % [path, error_string(err)])
