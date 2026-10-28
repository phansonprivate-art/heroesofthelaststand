extends SceneTree
## Erzeugt Screenshots zur Sichtprüfung. Ohne Typangaben auf Spielklassen, weil diese bei -s
## vor den Autoloads kompiliert würden. (nicht headless ausführen, braucht echtes Rendering):
##   godot --path . -s res://tools/screenshot.gd -- <ausgabeordner> [held-id]

var out_dir := "user://screenshots"
var hero_id := "arcanist"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		hero_id = args[1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	# Sicherheitsnetz: Fenster schließt sich spätestens nach 3 Minuten, auch bei Fehlern
	create_timer(180.0, true, false, true).timeout.connect(func() -> void: quit(1))
	await process_frame
	root.size = Vector2i(1600, 900)
	root.get_node("Session").telemetry_directory_override = "user://telemetry_tools"

	var menu = load("res://scenes/main/main_menu.tscn").instantiate()
	root.add_child(menu)
	await _settle(20)
	menu.select_hero(hero_id)
	await _settle(5)
	_shot("01_hauptmenue")
	menu.queue_free()
	await _settle(2)
	root.get_node("Session").hero_id = hero_id

	var m = load("res://scenes/main/match.tscn").instantiate()
	root.add_child(m)
	await _settle(40)
	_shot("02_arena_vorbereitung")

	# Überblick: weit herausgezoomt
	m.camera_rig.set("_target_distance", 80.0)   # weiter als im Spiel erlaubt, nur zur Layoutprüfung
	m.camera_rig.target = null
	m.camera_rig.focus = Vector3(0, 0, -4)
	await _settle(50)
	_shot("03_arena_ueberblick")

	m.camera_rig.set("_target_distance", 24.0)
	m.camera_rig.target = m.local_hero
	m.wave_manager.skip_preparation()
	m.local_hero.command_attack_move(Vector3(-3, 0, -6))
	await _settle(60 * 9)
	_shot("04_kampf")

	m.camera_rig.set("_target_distance", 15.0)
	await _settle(60 * 2)
	_shot("05_kampf_nah")

	m.local_hero.gain_xp(m.local_hero.stats.xp_to_next())
	await _settle(20)
	_shot("05b_levelaufstieg")
	m.gold.grant(1, 400, "screenshot", "screenshot")
	m.request_attribute_upgrade(m.local_hero.data.main_attribute)
	m.hud._character_window.toggle()
	m.hud._character_window.refresh()
	await _settle(10)
	_shot("05c_charakterfenster")
	m.hud._character_window.close()

	# Fähigkeiten: passende Fähigkeiten des Helden lernen und im Kampf wirken
	m.gold.grant(1, 20000, "screenshot", "screenshot_skills")
	var kit: Array = {"str": ["shield_bash", "taunt", "guardian_blessing", "bastion"], "agi": ["shadow_strike", "poison_mark", "fan_of_knives", "shadow_dance"],
		"int": ["fireball", "frost_nova", "healing_pulse", "starfall"]}[m.local_hero.data.main_attribute]
	m.local_hero.gain_xp(100000)
	await _settle(90)   # Levelaufstieg-Effekte abklingen lassen
	for id in kit:
		m.request_learn_ability(id)
	m.request_buy_item("phoenix_potion")
	m.request_buy_item("guardian_plate")
	var enemy = m.spawner.nearest_enemy(m.local_hero.global_position, 30.0)
	if enemy != null:
		m.local_hero.global_position = enemy.global_position + Vector3(0, 0, 2.5)
		for slot in [0, 1, 3]:
			m.local_hero.mana = 10000.0
			m.request_cast(slot, enemy, enemy.global_position)
			await _settle(8)
	await _settle(12)
	_shot("05d_faehigkeiten")
	m.hud._shop.open(0)
	await _settle(10)
	_shot("05e_shop")
	m.hud._shop.close()
	m.hud._inventory.toggle()
	await _settle(10)
	_shot("05f_inventar")
	m.hud._inventory.close()

	m.combat.deal_damage(null, m.core, m.core.health.hp - 2000)
	await _settle(60)
	_shot("06_kern_kritisch")

	m.combat.deal_damage(null, m.core, 99999)
	await _settle(120)
	_shot("07_niederlage")
	quit()


func _settle(frames: int) -> void:
	for i in frames:
		await process_frame


func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	img.save_png(path)
	print("Screenshot: ", path)
