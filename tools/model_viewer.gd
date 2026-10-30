extends Node3D
## Modell-Viewer: zeigt die neuen, in Blender gebauten Heldenmodelle (oder zum Vergleich die alten
## KayKit-Modelle) und spielt die Animationen ab, die das Spiel für den Helden nutzt.
## Im Godot-Editor diese Szene (tools/model_viewer.tscn) öffnen und mit F6 starten.
## Direkt bei einer Fähigkeit starten:  godot --path . res://tools/model_viewer.tscn -- --skill=<id>
## Automatische Bilder ohne Bedienung (nicht headless, braucht echtes Rendering):
##   godot --path . res://tools/model_viewer.tscn -- --shots=<ordner>

const CUSTOM_MODELS := {
	"guardian": "res://assets/models/heroes_custom/GuardianTripo.glb",
	"shadow": "res://assets/models/heroes_custom/ShadowTripo.glb",
	"arcanist": "res://assets/models/heroes_custom/ArcanistTripo.glb",
}
const HERO_ORDER := ["guardian", "shadow", "arcanist"]
const LOGICAL_LABELS := {"idle": "Stehen", "run": "Laufen", "attack": "Standardangriff", "cast": "Zaubern", "death": "Tod", "cheer": "Jubeln"}
const SPEEDS := [0.1, 0.25, 0.5, 1.0, 1.5, 2.0]
const LINEUP_SPACING := 2.4
const SKILL_PREFIX := "Fähigkeit: "
const HELP := "1 / 2 / 3  Held wählen      ← / →  Animation      F  nächste Fähigkeit      Leertaste  Pause      + / −  Tempo      Tab  Neu ↔ Original\nV  alle drei nebeneinander      L  Liste: im Spiel genutzt ↔ alle      Maus ziehen  drehen      Mausrad  Zoom      R  Kamera zurück      Esc  Beenden"

var _hero_index := 0
var _use_custom := true
var _lineup := false
var _show_all := false
var _entries: Array[Dictionary] = []   ## {name, speed, start, label}
var _anim_index := 0
var _speed_index := 3
var _paused := false
var _play_token := 0
var _visuals: Array[CharacterVisual] = []

var _camera: Camera3D
var _info: Label
var _yaw := 0.0
var _pitch := 0.0
var _distance := 0.0
var _dragging := false


func _ready() -> void:
	_build_stage()
	_build_ui()
	_reset_camera()
	_reload_models()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_run_shots(arg.trim_prefix("--shots="))
		elif arg.begins_with("--skill="):
			_show_skill(arg.trim_prefix("--skill="))


func _build_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.13, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.63, 0.7)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -150.0, 0.0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-25.0, 35.0, 0.0)
	rim.light_energy = 0.45
	rim.light_color = Color(0.7, 0.8, 1.0)
	add_child(rim)

	var ground := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 7.0
	disc.bottom_radius = 7.0
	disc.height = 0.05
	ground.mesh = disc
	ground.position.y = -0.025
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.23, 0.25, 0.29)
	ground_mat.roughness = 0.95
	ground.material_override = ground_mat
	add_child(ground)

	_camera = Camera3D.new()
	_camera.fov = 40.0
	add_child(_camera)
	_camera.make_current()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_info = Label.new()
	_info.position = Vector2(20, 16)
	_info.add_theme_font_size_override("font_size", 22)
	_info.add_theme_color_override("font_outline_color", Color.BLACK)
	_info.add_theme_constant_override("outline_size", 6)
	layer.add_child(_info)
	var help := Label.new()
	help.text = HELP
	help.add_theme_font_size_override("font_size", 16)
	help.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	help.add_theme_color_override("font_outline_color", Color.BLACK)
	help.add_theme_constant_override("outline_size", 5)
	help.anchor_left = 0.0
	help.anchor_right = 1.0
	help.anchor_top = 1.0
	help.anchor_bottom = 1.0
	help.offset_left = 20.0
	help.offset_right = -20.0
	help.offset_top = -70.0
	help.offset_bottom = -14.0
	help.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	layer.add_child(help)


func _reset_camera() -> void:
	_yaw = PI - 0.5   # Modelle blicken nach -Z; Kamera vorne, leicht seitlich
	_pitch = 0.18
	_distance = 11.0 if _lineup else 6.5


func _reload_models() -> void:
	for v in _visuals:
		remove_child(v)
		v.free()
	_visuals.clear()
	var ids: Array = HERO_ORDER if _lineup else [HERO_ORDER[_hero_index]]
	for i in ids.size():
		var id: String = ids[i]
		var data := GameData.hero(id)
		var path: String = CUSTOM_MODELS[id] if _use_custom else String(data.model)
		var visual := CharacterVisual.new()
		add_child(visual)
		# Kamera blickt nach +Z, Bild-rechts ist also -X: so stehen die Helden in der Reihenfolge 1-2-3
		visual.position.x = -(i - (ids.size() - 1) * 0.5) * LINEUP_SPACING
		visual.setup(path, data.hidden_parts, data.model_scale, data.anims, data.color)
		visual.add_animation_libraries(data.anim_libraries)
		if visual.anim_player != null:
			visual.anim_player.animation_finished.connect(_on_animation_finished)
		_visuals.append(visual)
	_rebuild_entries()
	_play_current()


func _rebuild_entries() -> void:
	var keep := String(_entries[_anim_index].name) if _anim_index < _entries.size() else ""
	_entries.clear()
	if _visuals.is_empty() or _visuals[0].anim_player == null:
		return
	var id: String = HERO_ORDER[_hero_index]
	if _show_all:
		var names := Array(_visuals[0].anim_player.get_animation_list())
		names.sort()
		for n in names:
			if not (String(n) in ["T-Pose", "RESET"]):
				_entries.append({"name": String(n), "speed": 1.0, "start": 0.0, "label": "Zusatzbibliothek" if String(n).begins_with("kk/") else ""})
	else:
		var data := GameData.hero(id)
		for logical in LOGICAL_LABELS:
			var entry: Variant = data.anims.get(logical, "")
			var list: Array = entry if entry is Array else [entry]
			for n in list:
				_add_entry(String(n), 1.0, LOGICAL_LABELS[logical])
		for sid in GameData.skill_order:
			var def: Dictionary = GameData.skills[sid]
			if id in def.heroes:
				_add_entry(String(def.anim), float(def.anim_speed), SKILL_PREFIX + String(def.name), float(def.anim_start))
	_anim_index = 0
	for i in _entries.size():
		if _entries[i].name == keep:
			_anim_index = i
			break


func _add_entry(anim_name: String, speed: float, label: String, start := 0.0) -> void:
	if anim_name.is_empty():
		return
	for e in _entries:
		if e.name == anim_name and is_equal_approx(float(e.speed), speed) and is_equal_approx(float(e.start), start):
			e.label = "%s · %s" % [e.label, label]
			return
	_entries.append({"name": anim_name, "speed": speed, "start": start, "label": label})


func _play_current() -> void:
	_play_token += 1
	_paused = false
	if not _entries.is_empty():
		var e: Dictionary = _entries[_anim_index]
		for v in _visuals:
			var player := v.anim_player
			if player == null or not player.has_animation(e.name):
				continue
			player.speed_scale = SPEEDS[_speed_index]
			player.play(e.name, 0.12, float(e.speed))
			player.seek(float(e.start) * player.get_animation(e.name).length, true)
	_update_info()


func _on_animation_finished(_anim: StringName) -> void:
	# Einzelanimationen (Angriff, Tod ...) nach kurzer Pause wiederholen, damit man sie mehrfach sieht
	var token := _play_token
	await get_tree().create_timer(0.6).timeout
	if token == _play_token and not _paused:
		_play_current()


func _toggle_pause() -> void:
	_paused = not _paused
	for v in _visuals:
		if v.anim_player == null:
			continue
		if _paused:
			v.anim_player.pause()
		else:
			v.anim_player.play()
	_update_info()


func _update_info() -> void:
	var data := GameData.hero(HERO_ORDER[_hero_index])
	var lines: Array[String] = []
	lines.append("%s   –   %s" % ["Alle drei Helden" if _lineup else String(data.name), "NEUES Modell (Blender)" if _use_custom else "ORIGINAL (KayKit, zum Vergleich)"])
	if _entries.is_empty():
		lines.append("keine Animationen gefunden")
	else:
		var e: Dictionary = _entries[_anim_index]
		var notes: Array[String] = []
		if not is_equal_approx(float(e.speed), 1.0):
			notes.append("im Spiel ×%.1f" % float(e.speed))
		if float(e.start) > 0.0:
			notes.append("Start bei %d %%" % roundi(float(e.start) * 100.0))
		var extra := "   (%s)" % ", ".join(notes) if not notes.is_empty() else ""
		lines.append("Animation %d / %d:  %s%s" % [_anim_index + 1, _entries.size(), e.name, extra])
		if String(e.label) != "":
			lines.append("Verwendung: %s" % e.label)
	lines.append("Liste: %s     Wiedergabe ×%s%s" % ["alle Animationen" if _show_all else "im Spiel genutzt", str(SPEEDS[_speed_index]), "     [PAUSE]" if _paused else ""])
	_info.text = "\n".join(lines)


func _process(_delta: float) -> void:
	var target := Vector3(0.0, 1.0, 0.0)
	var dir := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch))
	_camera.position = target + dir * _distance
	_camera.look_at(target, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(1.5, _distance * 0.9)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(25.0, _distance * 1.1)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.008
		_pitch = clampf(_pitch + mm.relative.y * 0.005, -0.3, 1.3)
	elif event is InputEventKey and event.pressed:
		var key := (event as InputEventKey).keycode
		if event.echo and not (key in [KEY_LEFT, KEY_RIGHT]):
			return
		_on_key(key)


func _on_key(key: Key) -> void:
	match key:
		KEY_1, KEY_2, KEY_3:
			_hero_index = int(key) - int(KEY_1)
			_lineup = false
			_reset_camera()
			_reload_models()
		KEY_TAB:
			_use_custom = not _use_custom
			_reload_models()
		KEY_V:
			_lineup = not _lineup
			_reset_camera()
			_reload_models()
		KEY_L:
			_show_all = not _show_all
			_rebuild_entries()
			_play_current()
		KEY_RIGHT:
			if not _entries.is_empty():
				_anim_index = (_anim_index + 1) % _entries.size()
				_play_current()
		KEY_LEFT:
			if not _entries.is_empty():
				_anim_index = (_anim_index - 1 + _entries.size()) % _entries.size()
				_play_current()
		KEY_F:
			_next_skill()
		KEY_SPACE:
			_toggle_pause()
		KEY_PLUS, KEY_KP_ADD, KEY_EQUAL:
			_set_speed(_speed_index + 1)
		KEY_MINUS, KEY_KP_SUBTRACT:
			_set_speed(_speed_index - 1)
		KEY_R:
			_reset_camera()
		KEY_ESCAPE:
			get_tree().quit()


## Nächste Fähigkeits-Animation; nach der letzten des Helden geht es beim nächsten Helden weiter.
func _next_skill() -> void:
	var from := _anim_index + 1
	if _lineup or _show_all:
		_lineup = false
		_show_all = false
		_reset_camera()
		_reload_models()
		from = 0
	for _attempt in HERO_ORDER.size() + 1:
		for i in range(from, _entries.size()):
			if SKILL_PREFIX in String(_entries[i].label):
				_anim_index = i
				_play_current()
				return
		_hero_index = (_hero_index + 1) % HERO_ORDER.size()
		_reload_models()
		from = 0


## Wählt den Helden einer Fähigkeit und springt zu ihrer Animation (Start mit -- --skill=<id>).
func _show_skill(sid: String) -> void:
	var def := GameData.skill(sid)
	if def.is_empty():
		push_warning("Unbekannte Fähigkeit: %s" % sid)
		return
	_hero_index = maxi(HERO_ORDER.find(def.heroes[0]), 0)
	_lineup = false
	_show_all = false
	_reset_camera()
	_reload_models()
	for i in _entries.size():
		var e := _entries[i]
		if e.name == def.anim and is_equal_approx(float(e.speed), float(def.anim_speed)) and is_equal_approx(float(e.start), float(def.anim_start)):
			_anim_index = i
			_play_current()
			return


func _set_speed(index: int) -> void:
	_speed_index = clampi(index, 0, SPEEDS.size() - 1)
	for v in _visuals:
		if v.anim_player != null:
			v.anim_player.speed_scale = SPEEDS[_speed_index]
	_update_info()


# --- Automatische Bilder zur Sichtprüfung ---------------------------------------------------------

func _run_shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	get_tree().create_timer(180.0).timeout.connect(func() -> void: get_tree().quit(1))
	for custom in [true, false]:
		_use_custom = custom
		_lineup = true
		_reset_camera()
		_reload_models()
		_pose("Idle", 0.0)
		await _settle(20)
		_shot(dir, "00_reihe_%s" % ("neu" if custom else "original"))
	_use_custom = true
	_lineup = true
	_reset_camera()
	_reload_models()
	_yaw = 0.35   # von hinten: Sitz der Capes prüfen
	_pose("Idle", 0.0)
	await _settle(20)
	_shot(dir, "01_reihe_hinten")
	_lineup = false
	for i in HERO_ORDER.size():
		_hero_index = i
		_reload_models()
		# [Animation, Zeitpunkt, Kamerawinkel oder null, Dateiname]; Fähigkeiten kurz nach ihrem Startpunkt
		var shots: Array = [["Idle", 0.0, PI * 0.5, "stehen_seite"], ["Running_A", 0.3, null, "laufen"], ["Death_A", 1.0, null, "tod"]]
		for sid in GameData.skill_order:
			var def := GameData.skill(sid)
			if HERO_ORDER[i] in def.heroes:
				shots.append([def.anim, def.anim_start + (1.0 - def.anim_start) * 0.45, null, sid])
		for s in shots:
			_reset_camera()
			if s[2] != null:
				_yaw = s[2]
			_pose(s[0], s[1])
			await _settle(8)
			_shot(dir, "%d_%s_%s" % [i + 2, HERO_ORDER[i], s[3]])
	get_tree().quit()


func _pose(anim_name: String, at: float) -> void:
	var data := GameData.hero(HERO_ORDER[_hero_index])
	_info.text = "%s   –   %s\nPose: %s (bei %d %%)" % ["Alle drei Helden" if _lineup else String(data.name), "NEUES Modell (Blender)" if _use_custom else "ORIGINAL (KayKit)", anim_name, roundi(at * 100.0)]
	for v in _visuals:
		var player := v.anim_player
		if player == null or not player.has_animation(anim_name):
			push_warning("Animation fehlt: %s" % anim_name)
			continue
		player.speed_scale = 1.0
		player.play(anim_name, 0.0)
		player.seek(at * player.get_animation(anim_name).length, true)
		player.pause()


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(dir: String, shot_name: String) -> void:
	var path := dir.path_join(shot_name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("Screenshot: ", path)
