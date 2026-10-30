extends Node3D
## Drachen-Viewer: zeigt den in Blender gebauten Glutdrachen (tools/blender_build_dragon.py) mit allen Animationen.
## Start: tools/dragon_viewer.cmd (Doppelklick) oder im Editor tools/dragon_viewer.tscn mit F6.
## Automatische Bilder ohne Bedienung (nicht headless, braucht echtes Rendering):
##   godot --path . res://tools/dragon_viewer.tscn -- --shots=<ordner>

const MODEL := "res://assets/models/enemies_custom/EmberDrake.glb"
const FROST_MODEL := "res://assets/models/enemies_custom/FrostDrake.glb"   ## `-- --frost`: Frostdrache (Tripo-Modell, gleiches Skelett)
## Reihenfolge und deutsche Namen der Animationen
const ANIMS := [
	["Idle", "Stehen und Atmen"], ["Walk", "Laufen"], ["Attack_Bite", "Biss"], ["Attack_Claw", "Prankenhieb"],
	["Fire_Breath", "Feuerodem"], ["Roar", "Brüllen"], ["Hit", "Treffer"], ["Death", "Tod"], ["Fly", "Fliegen"],
]
const LOOPING := ["Idle", "Walk", "Fly"]
const SPEEDS := [0.1, 0.25, 0.5, 1.0, 1.5, 2.0]
const HELP := "← / →  Animation      Leertaste  Pause      + / −  Tempo      G  Größenvergleich mit dem Guardian\nMaus ziehen  drehen      Mausrad  Zoom      R  Kamera zurück      Esc  Beenden"

var _player: AnimationPlayer
var _anim_index := 0
var _speed_index := 3
var _paused := false
var _hero: CharacterVisual
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
	# wie im Spiel über CharacterVisual laden (dreht das Modell nach Godot-vorn = -Z)
	var dragon := CharacterVisual.new()
	add_child(dragon)
	dragon.setup(_model_path(), [], 1.0, {"idle": "Idle", "run": "Walk"})
	_player = dragon.anim_player
	for a in LOOPING:
		if _player.has_animation(a):
			_player.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	_player.animation_finished.connect(func(_a: StringName) -> void: _restart_later())
	_play_current()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_run_shots(arg.trim_prefix("--shots="))


func _build_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.1, 0.11, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.63, 0.7)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true       # Glut in den Bauchfugen und leuchtende Augen
	env.glow_intensity = 0.6
	env.glow_hdr_threshold = 1.2
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -150.0, 0.0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-25.0, 35.0, 0.0)
	rim.light_energy = 0.5
	rim.light_color = Color(0.7, 0.8, 1.0)
	add_child(rim)

	var ground := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 12.0
	disc.bottom_radius = 12.0
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
	help.anchor_top = 1.0
	help.anchor_bottom = 1.0
	help.anchor_right = 1.0
	help.offset_left = 20.0
	help.offset_right = -20.0
	help.offset_top = -70.0
	help.offset_bottom = -14.0
	help.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	layer.add_child(help)


func _reset_camera() -> void:
	_yaw = PI - 0.6   # Modelle blicken zur Kamera; leicht seitlich
	_pitch = 0.22
	_distance = 13.0


func _play_current() -> void:
	var anim: String = ANIMS[_anim_index][0]
	_player.speed_scale = SPEEDS[_speed_index]
	_player.play(anim, 0.15)
	if _paused:
		_player.pause()
	_update_info()


## Einmal-Animationen nach kurzer Pause wiederholen, damit man sie mehrfach sehen kann
func _restart_later() -> void:
	var anim: String = ANIMS[_anim_index][0]
	if anim in LOOPING:
		return
	await get_tree().create_timer(0.8).timeout
	if ANIMS[_anim_index][0] == anim and not _paused:
		_player.play(anim, 0.0)
		_player.seek(0.0, true)


func _frost() -> bool:
	return OS.get_cmdline_user_args().has("--frost")


func _model_path() -> String:
	return FROST_MODEL if _frost() else MODEL


func _title() -> String:
	return "Frostdrache" if _frost() else "Glutdrache"


func _update_info() -> void:
	var anim: String = ANIMS[_anim_index][0]
	_info.text = "%s  –  %s  (%s)\nAnimation %d/%d   ·   %.2f s   ·   Tempo ×%s%s" % [
		_title(), ANIMS[_anim_index][1], anim, _anim_index + 1, ANIMS.size(), _player.get_animation(anim).length,
		str(SPEEDS[_speed_index]), "   ·   PAUSE" if _paused else ""]


func _process(_delta: float) -> void:
	var target := Vector3(0.0, 1.4, 0.0)
	var dir := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch))
	_camera.position = target + dir * _distance
	_camera.look_at(target, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(2.5, _distance * 0.9)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(40.0, _distance * 1.1)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.008
		_pitch = clampf(_pitch + mm.relative.y * 0.005, -0.3, 1.4)
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_RIGHT:
				_anim_index = (_anim_index + 1) % ANIMS.size()
				_play_current()
			KEY_LEFT:
				_anim_index = (_anim_index - 1 + ANIMS.size()) % ANIMS.size()
				_play_current()
			KEY_SPACE:
				_paused = not _paused
				if _paused:
					_player.pause()
				else:
					_player.play()
				_update_info()
			KEY_PLUS, KEY_KP_ADD, KEY_EQUAL:
				_speed_index = mini(_speed_index + 1, SPEEDS.size() - 1)
				_player.speed_scale = SPEEDS[_speed_index]
				_update_info()
			KEY_MINUS, KEY_KP_SUBTRACT:
				_speed_index = maxi(_speed_index - 1, 0)
				_player.speed_scale = SPEEDS[_speed_index]
				_update_info()
			KEY_G:
				_toggle_hero()
			KEY_R:
				_reset_camera()
			KEY_ESCAPE:
				get_tree().quit()


## Guardian in Spielgröße neben den Drachen stellen (Größenvergleich)
func _toggle_hero() -> void:
	if _hero != null:
		_hero.queue_free()
		_hero = null
		return
	var data := GameData.hero("guardian")
	_hero = CharacterVisual.new()
	add_child(_hero)
	_hero.position = Vector3(-2.8, 0.0, 0.6)
	_hero.setup(data.model, data.hidden_parts, data.model_scale, data.anims, data.color)
	_hero.add_animation_libraries(data.anim_libraries)
	_hero.play("idle")


func _run_shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	get_tree().create_timer(120.0).timeout.connect(func() -> void: get_tree().quit(1))
	# [Animation, Anteil der Länge, Kamerawinkel, Dateiname]
	var shots := [["Idle", 0.0, PI - 0.6, "00_stehen"], ["Idle", 0.0, PI * 0.5, "01_seite"], ["Walk", 0.3, PI - 0.6, "02_laufen"],
		["Attack_Bite", 0.47, PI - 0.9, "03_biss"], ["Fire_Breath", 0.5, PI - 0.6, "04_feuer"], ["Roar", 0.5, PI - 0.6, "05_bruellen"],
		["Fly", 0.25, PI - 0.6, "06_fliegen"], ["Death", 1.0, PI - 0.6, "07_tod"]]
	_toggle_hero()
	for s in shots:
		_reset_camera()
		_yaw = s[2]
		_anim_index = ANIMS.map(func(e: Array) -> String: return e[0]).find(s[0])
		_update_info()
		_player.play(s[0], 0.0)
		_player.seek(s[1] * _player.get_animation(s[0]).length, true)
		_player.pause()
		for i in 8:
			await get_tree().process_frame
		var path: String = dir.path_join(s[3] + ".png")
		get_viewport().get_texture().get_image().save_png(path)
		print("Screenshot: ", path)
	get_tree().quit()
