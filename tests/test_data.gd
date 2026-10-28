extends RefCounted
## Datendefinitionen und Tastenbelegung.


func test_data_valid(t) -> void:
	var gd = load("res://scripts/core/game_data.gd").new()
	t.eq(gd.errors.size(), 0, "Datendefinitionen fehlerfrei: %s" % str(gd.errors))
	t.check(gd.heroes.has("guardian"), "Guardian ist definiert")
	t.check(gd.enemies.size() >= 3, "mindestens drei Gegnertypen")
	t.check(gd.waves.size() >= 1, "mindestens eine Welle")
	t.eq(int(gd.setting("core", "max_hp")), 10000, "Kern startet mit 10.000 Lebenspunkten")
	gd.free()


func test_models_exist(t) -> void:
	for id in GameData.heroes:
		t.check(ResourceLoader.exists(GameData.hero(id).model), "Heldenmodell vorhanden: %s" % id)
	for id in GameData.enemies:
		t.check(ResourceLoader.exists(GameData.enemy(id).model), "Gegnermodell vorhanden: %s" % id)


func test_animations_exist(t) -> void:
	var defs := []
	for id in GameData.heroes:
		defs.append(GameData.hero(id))
	for id in GameData.enemies:
		defs.append(GameData.enemy(id))
	for def in defs:
		var inst: Node = (load(def.model) as PackedScene).instantiate()
		var players := inst.find_children("*", "AnimationPlayer", true, false)
		if t.check(not players.is_empty(), "%s hat einen AnimationPlayer" % def.id):
			var ap: AnimationPlayer = players[0]
			for logical in def.anims:
				var entry = def.anims[logical]
				for anim_name in (entry if entry is Array else [entry]):
					t.check(ap.has_animation(anim_name), "%s: Animation '%s' (%s) existiert" % [def.id, anim_name, logical])
		inst.free()


func test_invalid_wave_is_rejected(t) -> void:
	var gd = load("res://scripts/core/game_data.gd").new()
	var bad: Dictionary = gd.normalize_wave({"groups": [{"enemy": "gibts_nicht", "count": 3, "path": 0}, {"enemy": "grunt", "count": 2, "path": 9}]}, 99)
	t.check(bad.is_empty(), "Welle ohne gültige Gruppen wird verworfen")
	t.check(gd.errors.size() >= 2, "beide Fehler werden gemeldet")
	gd.free()


func test_input_actions_registered(t) -> void:
	for action in ["primary_action", "secondary_action", "attack_move", "stop", "camera_lock",
			"ability_1", "ability_2", "ability_3", "ability_4", "ability_5", "ability_6",
			"open_shop", "open_inventory", "open_character", "team_overview", "pause"]:
		t.check(InputMap.has_action(action) and not InputMap.action_get_events(action).is_empty(), "Aktion belegt: %s" % action)
	var abilities := []
	for i in range(1, 7):
		abilities.append(OS.get_keycode_string(InputSetup.KEYS["ability_%d" % i][0]))
	t.eq(abilities, ["Q", "W", "E", "R", "D", "F"], "Fähigkeiten im MOBA-Layout")


func test_no_key_bound_twice(t) -> void:
	var seen := {}
	for action in InputSetup.KEYS:
		for key in InputSetup.KEYS[action]:
			t.check(not seen.has(key), "Taste %s doppelt belegt (%s und %s)" % [OS.get_keycode_string(key), seen.get(key, ""), action])
			seen[key] = action
