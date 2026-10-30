extends SceneTree
## Bild der Doppelgänger im Spiel (nicht headless): Runde mit der Assassine im Testmodus, Doppelgänger Stufe 3 wirken,
## alle Kopien wählen (F3), eine Kopie verletzen; Bild mit Lebensbalken, Auswahlringen und Auswahl-Anzeige.
##   godot --path . -s res://tools/clone_shot.gd -- --out=<datei.png>

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var session: Node = root.get_node("Session")
	session.hero_id = "shadow"
	session.test_mode = true
	session.test_level = 10
	var out := "user://clones.png"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	change_scene_to_file("res://scenes/main/match.tscn")
	for i in 30:
		await process_frame
	var m = current_scene
	for i in 3:
		m.request_learn_ability("shadow_clones")
	m.local_hero.mana = 10000.0
	m.request_cast(m.local_hero.abilities.slots.find("shadow_clones"), null, m.local_hero.global_position)
	for i in 60:
		await process_frame
	m.hero_input.select_group(m.hero_input.own_clones())
	m.combat.deal_damage(null, m.clones[0], m.clones[0].health.max_hp * 0.45, DamageInfo.Type.TRUE)
	for i in 20:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out)
	print("Screenshot: ", out)
	quit()
