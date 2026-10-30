extends SceneTree
## Bild einer Szene ohne Bedienung (nicht headless, braucht echtes Rendering), z. B. Menü oder HUD:
##   godot --path . -s res://tools/ui_shot.gd -- --scene=res://scenes/main/main_menu.tscn --out=<datei.png>
## Optional: --frames=<n> (Wartezeit, Standard 90), --test-level=<n> (startet die Runde im Testmodus),
##           --hero=<id>, --map=<id>, --press=<Knopftext> (drückt nach dem Laden einen Knopf, z. B. im Menü),
##           --type=<zahl>[,<zahl>…] (vorher in die Zahlenfelder tippen, ohne Enter)

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame   # Autoloads (Session, GameData) sind erst jetzt im Baum
	var session: Node = root.get_node("Session")
	var scene := "res://scenes/main/main_menu.tscn"
	var out := "user://ui_shot.png"
	var frames := 90
	var press := ""
	var typed := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="):
			scene = arg.trim_prefix("--scene=")
		elif arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--frames="):
			frames = int(arg.trim_prefix("--frames="))
		elif arg.begins_with("--test-level="):
			session.test_mode = true
			session.test_level = int(arg.trim_prefix("--test-level="))
		elif arg.begins_with("--hero="):
			session.hero_id = arg.trim_prefix("--hero=")
		elif arg.begins_with("--map="):
			session.map_id = arg.trim_prefix("--map=")
		elif arg.begins_with("--press="):
			press = arg.trim_prefix("--press=")
		elif arg.begins_with("--type="):
			typed = arg.trim_prefix("--type=")
	change_scene_to_file(scene)
	if press != "":
		for i in 20:
			await process_frame
		if typed != "":
			var spin := root.find_children("*", "SpinBox", true, false)
			var values := typed.split(",")   # mehrere Felder: --type=10,8
			for i in mini(spin.size(), values.size()):
				(spin[i] as SpinBox).get_line_edit().text = values[i]
		for b: Button in root.find_children("*", "Button", true, false):
			if b.text == press:
				print("Drücke: ", press)
				b.pressed.emit()
				break
	for i in frames:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	print("Screenshot: ", out)
	quit()
