class_name CharacterVisual
extends Node3D
## Reine Darstellung einer Figur: lädt das Modell, blendet überzählige Teile aus und spielt Animationen
## über logische Namen ("idle", "run", "attack" ...). Die Zuordnung kommt aus den Daten.
## Fehlt das Modell, wird ein Platzhalter erzeugt – die Spielmechanik hängt nie am Modell.

const LOOPING := ["idle", "run"]
const EXTRA_LIBRARY := "kk"

static var _library_cache: Dictionary = {}   ## "Modell|Skelettpfad|Bibliotheken" -> umgerechnete AnimationLibrary

var anim_player: AnimationPlayer
var anim_map: Dictionary = {}
var _model: Node3D
var _meshes: Array[MeshInstance3D] = []
var _current := ""
var _action := ""   ## aktuelle Einzelanimation (leer bei Schleifen wie Laufen/Stehen)
var _next_pick: Dictionary = {}   ## logisch -> bei animation_length() gewürfelte Variante für das nächste play()
var _flash_material: StandardMaterial3D
var _flash_left := 0.0
var _tint_material: StandardMaterial3D


func setup(model_path: String, hidden_parts: Array, scale_factor: float, anims: Dictionary, placeholder_color := Color(0.6, 0.6, 0.65)) -> void:
	anim_map = anims
	var scene: PackedScene = null
	if not model_path.is_empty() and ResourceLoader.exists(model_path):
		scene = load(model_path) as PackedScene
	if scene != null:
		_model = scene.instantiate()
	else:
		push_warning("Modell fehlt, nutze Platzhalter: %s" % model_path)
		_model = _make_placeholder(placeholder_color)
	# KayKit-Modelle blicken nach +Z, in Godot ist vorne -Z
	_model.rotation.y = PI
	_model.scale = Vector3.ONE * scale_factor
	add_child(_model)

	for m: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		if hidden_parts.has(String(m.name)):
			m.visible = false
		else:
			_meshes.append(m)

	var players := _model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		anim_player = players[0]
		for logical in LOOPING:
			var anim_name := _resolve(logical)
			if anim_player.has_animation(anim_name):
				anim_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR

	_flash_material = StandardMaterial3D.new()
	_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_material.albedo_color = Color(1, 1, 1, 0.55)


## Zusätzliche Animationen aus KayKit-Animationsbibliotheken (Rig_Medium) laden, z. B. Sprung-Hieb oder
## Beschwörung. Die Bibliotheken haben dasselbe Skelett wie die Figuren; nur der Knotenpfad zum Skelett
## unterscheidet sich und wird umgeschrieben. Erreichbar als "kk/<Name>". Je Skelettpfad nur einmal umgerechnet.
func add_animation_libraries(paths: Array) -> void:
	if anim_player == null or paths.is_empty():
		return
	var skeletons := _model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	var root := anim_player.get_node(anim_player.root_node)
	var skeleton: Skeleton3D = skeletons[0]
	var skeleton_path := String(root.get_path_to(skeleton))
	# Modelle mit gestrecktem Skelett (z. B. der Assassine) brauchen eigene Positionsspuren: Schlüssel je Modell
	var key := "%s|%s|%s" % [_model.scene_file_path, skeleton_path, "|".join(PackedStringArray(paths))]
	if not _library_cache.has(key):
		_library_cache[key] = _build_library(paths, skeleton_path, skeleton)
	if not anim_player.has_animation_library(EXTRA_LIBRARY):
		anim_player.add_animation_library(EXTRA_LIBRARY, _library_cache[key])


## Positionsspuren gelten relativ zur Ruhepose und wachsen mit der Knochenstreckung:
## Ziel = Ruhepose Ziel + (Wert − Ruhepose Quelle) × (Länge Ziel / Länge Quelle). Bei gleichem Skelett ändert sich
## nichts; bei gestreckten Knochen (Assassine) sitzen Hüfte, Schultern und Beine an der richtigen Stelle.
static func _retarget_positions(anim: Animation, source: Skeleton3D, target: Skeleton3D) -> void:
	if source == null or target == null:
		return
	for t in anim.get_track_count():
		if anim.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		var bone_name := String(anim.track_get_path(t)).get_slice(":", 1)
		var si := source.find_bone(bone_name)
		var ti := target.find_bone(bone_name)
		if si < 0 or ti < 0:
			continue
		var src_rest := source.get_bone_rest(si).origin
		var dst_rest := target.get_bone_rest(ti).origin
		if (dst_rest - src_rest).length_squared() < 1e-10:
			continue
		var ratio := dst_rest.length() / src_rest.length() if src_rest.length() > 0.05 else 1.0
		for k in anim.track_get_key_count(t):
			var value: Vector3 = anim.track_get_key_value(t, k)
			anim.track_set_key_value(t, k, dst_rest + (value - src_rest) * ratio)


static func _build_library(paths: Array, skeleton_path: String, target: Skeleton3D = null) -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	for path in paths:
		if not ResourceLoader.exists(path):
			push_warning("Animationsbibliothek fehlt: %s" % path)
			continue
		var scene: Node = (load(path) as PackedScene).instantiate()
		var players := scene.find_children("*", "AnimationPlayer", true, false)
		if players.is_empty():
			scene.free()
			continue
		var src: AnimationPlayer = players[0]
		var src_skeletons := scene.find_children("*", "Skeleton3D", true, false)
		var src_skeleton: Skeleton3D = src_skeletons[0] if not src_skeletons.is_empty() else null
		for anim_name in src.get_animation_list():
			if anim_name == "T-Pose" or lib.has_animation(anim_name):
				continue
			var anim: Animation = src.get_animation(anim_name).duplicate(true)
			_retarget_positions(anim, src_skeleton, target)
			for t in anim.get_track_count():
				var track := String(anim.track_get_path(t))
				var colon := track.find(":")
				if colon > 0:
					anim.track_set_path(t, NodePath(skeleton_path + track.substr(colon)))
			lib.add_animation(anim_name, anim)
		scene.free()
	return lib


## Spielt eine logische Animation. Liefert die Dauer in Sekunden (0, wenn nicht vorhanden).
func play(logical: String, speed := 1.0, restart := false) -> float:
	if anim_player == null:
		return 0.0
	# Wurde die Länge vorher abgefragt, genau diese Variante spielen (sonst passt das berechnete Tempo nicht)
	var anim_name: String = _next_pick.get(logical, "")
	_next_pick.erase(logical)
	if anim_name == "":
		anim_name = _resolve(logical)
	if not anim_player.has_animation(anim_name):
		return 0.0
	var looping := logical in LOOPING
	if anim_name == _current and not restart and anim_player.is_playing():
		if looping:
			anim_player.speed_scale = speed   # Lauftempo laufend an die Geschwindigkeit anpassen
		return 0.0
	_current = anim_name
	_action = "" if looping else anim_name
	if looping:
		# Schleifen über speed_scale, damit sich das Tempo ohne Neustart ändern lässt
		anim_player.speed_scale = speed
		anim_player.play(anim_name, 0.15, 1.0)
	else:
		anim_player.speed_scale = 1.0
		anim_player.play(anim_name, 0.1, speed)
	if restart:
		anim_player.seek(0.0, true)
	return anim_player.get_animation(anim_name).length / maxf(speed, 0.01)


## Spielt eine Animation direkt über ihren Namen (Fähigkeiten). Wird nicht von Laufen/Stehen überschrieben,
## solange sie läuft (siehe is_busy). `start` überspringt den Anfang (Anteil 0–1), damit z. B. ein Aufprall
## mit dem sofort eintretenden Effekt zusammenfällt.
func play_action(anim_name: String, speed := 1.0, start := 0.0) -> void:
	if anim_player == null or not anim_player.has_animation(anim_name):
		return
	_current = anim_name
	_action = anim_name
	anim_player.speed_scale = 1.0
	anim_player.play(anim_name, 0.08, speed)
	anim_player.seek(start * anim_player.get_animation(anim_name).length, true)


## Läuft gerade eine Einzelanimation (Angriff, Fähigkeit, Treffer, Tod)?
func is_busy() -> bool:
	return anim_player != null and _action != "" and _current == _action and anim_player.is_playing()


## Länge einer logischen Animation. Bei mehreren Varianten (z. B. drei Angriffe) wird hier gewürfelt und die
## Wahl für das nächste play() desselben Namens gemerkt.
func animation_length(logical: String) -> float:
	if anim_player == null:
		return 0.0
	var anim_name := _resolve(logical)
	_next_pick[logical] = anim_name
	return anim_player.get_animation(anim_name).length if anim_player.has_animation(anim_name) else 0.0


func current_logical_is(logical: String) -> bool:
	var entry: Variant = anim_map.get(logical, "")
	if entry is Array:
		return (entry as Array).has(_current)
	return _current == String(entry)


## Kurzes Aufblitzen als Trefferrückmeldung.
func flash(color := Color(1, 1, 1), duration := 0.09) -> void:
	_flash_material.albedo_color = Color(color, 0.55)
	_flash_left = duration
	_set_overlay(_flash_material)


## Dauerhafte Einfärbung für Zustände (z. B. Verlangsamung). Color.TRANSPARENT entfernt sie.
func set_tint(color: Color) -> void:
	if color.a <= 0.0:
		_tint_material = null
	else:
		if _tint_material == null:
			_tint_material = _flash_material.duplicate()
		_tint_material.albedo_color = color
	if _flash_left <= 0.0:
		_set_overlay(_tint_material)


func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_set_overlay(_tint_material)


func _set_overlay(mat: Material) -> void:
	for m in _meshes:
		m.material_overlay = mat


func _resolve(logical: String) -> String:
	var entry: Variant = anim_map.get(logical, "")
	if entry is Array:
		var list := entry as Array
		return String(list.pick_random()) if not list.is_empty() else ""
	return String(entry)


func _make_placeholder(color: Color) -> Node3D:
	var root := Node3D.new()
	var mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.45
	capsule.height = 1.9
	mesh.mesh = capsule
	mesh.position.y = 0.95
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material_override = mat
	root.add_child(mesh)
	return root
