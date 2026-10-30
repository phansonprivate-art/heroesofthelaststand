extends Node
## Gegner-Showcase: startet eine echte Runde (Arena) und lässt sofort einen Gegner auf Pfad 1 erscheinen,
## damit man ihn und seine Fähigkeiten im Spiel sehen kann. Start: tools/hexer_showcase.cmd (Abgrund-Hexer) oder
## tools/ice_drake_showcase.cmd (Eisdrache). Gegner wählen: `-- --enemy=ice_drake`.
## Karte wählen: `-- --map=citadel`; Held: `-- --hero=arcanist`.
## Automatische Bilder ohne Bedienung (nicht headless): `-- --shots=<ordner>`

## Spielsekunden (Physik-Takte, nicht Uhrzeit: das Speichern eines Bildes hält das Spiel kurz an) nach dem Auftauchen
const SHOT_TIMES := {
	"abyss_hexer": [0.6, 2.2, 3.1, 3.4, 3.7, 4.0, 4.3, 4.9],
	# Odem (Warnung ab ~4,1 s, Strahl ~5,1 s), Schrei (~8,1 s), danach Phase 2 erzwungen: Schneesturm und Einfrieren
	"ice_drake": [5.5, 6.0, 6.45, 6.6, 6.75, 6.95, 7.3, 7.6, 7.9, 8.6, 9.6, 10.1, 12.5, 14.0, 15.5, 16.5],
	# Feuerball (Glut ~5,2–6,2 s, Flug, Einschlag ~6,7 s), Gebrüll (~9,7 s), Phase 2 bei 11 s: Meteorschauer
	"fire_drake": [2.0, 5.6, 6.3, 6.55, 6.8, 7.4, 9.7, 10.2, 11.6, 12.1, 12.6, 13.2],
}

var _enemy_id := "abyss_hexer"


func _ready() -> void:
	var shots := ""
	Session.map_id = "arena"
	Session.hero_id = "guardian"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots = arg.trim_prefix("--shots=")
		elif arg.begins_with("--map="):
			Session.map_id = arg.trim_prefix("--map=")
		elif arg.begins_with("--hero="):
			Session.hero_id = arg.trim_prefix("--hero=")
		elif arg.begins_with("--enemy="):
			_enemy_id = arg.trim_prefix("--enemy=")
	var m: MatchController = (load("res://scenes/main/match.tscn") as PackedScene).instantiate()
	m.waves_override = [GameData.normalize_wave({"name": "Showcase", "prepare_seconds": 1, "groups": [
		{"enemy": _enemy_id, "count": 1, "path": 1, "interval": 1.0, "delay": 0},
		{"enemy": "grunt", "count": 600, "path": 1, "interval": 600.0, "delay": 600}]}, 1)]   # Nachzügler: Runde läuft weiter
	add_child(m)
	if shots != "":
		_run_shots(m, shots)


## Held vor den Gegner stellen, Kamera darauf richten, in Abständen fotografieren.
func _run_shots(m: MatchController, dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	get_tree().create_timer(60.0).timeout.connect(func() -> void: get_tree().quit(1))
	var foe: Enemy = null
	while foe == null:
		await get_tree().process_frame
		for e in m.spawner.alive_enemies():
			if e.enemy_id == _enemy_id:
				foe = e
	m.hud.visible = false
	var times: Array = SHOT_TIMES.get(_enemy_id, SHOT_TIMES.abyss_hexer)
	var t0 := Engine.get_physics_frames()
	var tps := float(Engine.physics_ticks_per_second)
	var cam := Camera3D.new()   # nahe Bildkamera neben den beiden (die Spielkamera ist für Nahaufnahmen zu weit weg)
	cam.fov = 42.0
	add_child(cam)
	cam.make_current()
	var index := 0
	var placed := false
	var forced_phase := false
	while index < times.size():
		await get_tree().process_frame
		if not is_instance_valid(foe):
			break
		var elapsed := float(Engine.get_physics_frames() - t0) / tps
		var mid := (foe.global_position + m.local_hero.global_position) * 0.5
		var line := (m.local_hero.global_position - foe.global_position)
		line.y = 0.0
		var side := line.normalized().cross(Vector3.UP).normalized()
		cam.global_position = mid + side * (6.0 + foe.body_radius * 3.0) + Vector3(0, 3.6 + foe.body_radius, 0)
		cam.look_at(mid + Vector3(0, 1.1, 0), Vector3.UP)
		if not placed:   # Held vor dem Gegner (zum Kern hin), unverwundbar genug für die Bilder
			var toward := (m.core.global_position - foe.global_position)
			toward.y = 0.0
			m.local_hero.global_position = foe.global_position + toward.normalized() * (2.6 + foe.body_radius * 2.0)
			m.local_hero.health.set_max_hp(50000.0)
			m.local_hero.health.heal(50000.0)
			placed = true
		if foe.brain != null and not forced_phase and elapsed >= 11.0 and (foe.brain.cfg.has("blizzard") or foe.brain.cfg.has("meteor_shower")):
			# Phase 2 erzwingen, damit Schneesturm bzw. Meteorschauer sofort kommen
			forced_phase = true
			m.combat.deal_damage(null, foe, foe.health.max_hp * 0.45, DamageInfo.Type.TRUE)
			foe.brain._blizzard_left = 0.0
			foe.brain._meteor_left = 0.0
			foe.brain._cast_left = 0.0
		if elapsed >= float(times[index]):
			var path := dir.path_join("%02d.png" % index)
			get_viewport().get_texture().get_image().save_png(path)
			print("Screenshot: ", path, " (", foe.visual.anim_player.current_animation, ")")
			index += 1
	get_tree().quit()
