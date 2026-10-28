extends Node
## Fähigkeiten-Vorschau: zeigt jede Fähigkeit so, wie sie im Spiel wirkt, in einer echten Runde mit echten
## Effekten, Schadenszahlen, Zuständen und Klängen. Die Gegner sind Trainingspuppen: Sie bleiben stehen,
## greifen nicht an und werden vor jeder Vorführung wieder aufgefüllt.
## Start per Doppelklick auf tools/skill_showcase.cmd oder im Editor (tools/skill_showcase.tscn, F6).
## Direkt bei einer Fähigkeit starten:  godot --path . res://tools/skill_showcase.tscn -- --skill=<id>
## Mit den alten KayKit-Modellen:        ... -- --original

const MATCH_SCENE := "res://scenes/main/match.tscn"
const CUSTOM_MODELS := {
	"guardian": "res://assets/models/heroes_custom/Guardian.glb",
	"shadow": "res://assets/models/heroes_custom/Shadow.glb",
	"arcanist": "res://assets/models/heroes_custom/Arcanist.glb",
}
const HERO_ORDER := ["guardian", "shadow", "arcanist"]
const STAGE := Vector3(-2.0, 0.0, 13.0)   ## Platz des wirkenden Helden: freie Fläche südlich des Kerns
const ALLY_OFFSETS := [Vector3(-3.0, 0.0, -1.6), Vector3(-3.0, 0.0, 1.6)]
## Puppen vor dem Helden: die vorderste in Nahkampfreichweite, die hinteren für Flächen- und Kettenwirkungen.
## Vor dem hinteren Paar bleibt Platz, damit Shadow Strike nicht in einer anderen Puppe landet.
const DUMMIES := [["brute", Vector3(2.4, 0.0, 0.0)], ["grunt", Vector3(3.0, 0.0, -2.2)], ["grunt", Vector3(3.0, 0.0, 2.2)],
	["runner", Vector3(5.2, 0.0, -0.9)], ["grunt", Vector3(5.2, 0.0, 0.9)]]
const DUMMY_HP := 2000.0
const REPEAT_SECONDS := 4.0
const CAMERA_OFFSET := Vector3(1.0, 1.0, 0.0)
const TARGET_LABELS := {"enemy": "ein Gegner", "ally": "ein Verbündeter", "self": "der Held selbst", "point": "eine Stelle am Boden"}
const HELP := "F / →  nächste Fähigkeit      ←  vorherige      Leertaste  sofort nochmal      ↑ / ↓  Stufe      1 / 2 / 3  Held      Tab  Neu ↔ Original\nMaus ziehen  drehen      Mausrad  Zoom      R  Kamera zurück      Esc  Beenden"

var _match: MatchController
var _heroes: Dictionary = {}            ## hero_id -> Hero
var _dummies: Array[Enemy] = []
var _original_models: Dictionary = {}
var _hero_index := 0
var _skill_index := 0
var _level := 1
var _use_custom := true
var _busy := false                      ## Runde wird gerade (neu) aufgebaut
var _repeat_left := 0.0
var _note := ""                         ## Hinweis, wenn das Wirken nicht geklappt hat

var _camera: Camera3D
var _info: Label
var _yaw := 0.0
var _pitch := 0.0
var _distance := 0.0
var _dragging := false


func _ready() -> void:
	# Werkzeug: keine Telemetrie in die echten Spieldaten schreiben
	Session.telemetry_enabled_override = false
	Session.telemetry_directory_override = "user://telemetry_tools"
	for id in HERO_ORDER:
		_original_models[id] = String(GameData.hero(id).model)
	for arg in OS.get_cmdline_user_args():
		if arg == "--original":
			_use_custom = false
		elif arg.begins_with("--skill="):
			_select_skill(arg.trim_prefix("--skill="))
	_camera = Camera3D.new()
	_camera.fov = 45.0
	add_child(_camera)
	_build_ui()
	_reset_camera()
	await _build_match()
	_cast_current()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_info = Label.new()
	_info.position = Vector2(20, 16)
	_info.add_theme_font_size_override("font_size", 20)
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
	_yaw = 0.35   # von Süden, leicht seitlich: Held links, Puppen rechts
	_pitch = 0.5
	_distance = 12.0


## Baut die Runde (neu) auf: echte Arena, alle drei Helden, fünf Trainingspuppen.
func _build_match() -> void:
	_busy = true
	if _match != null:
		_match.queue_free()
		_match = null
		await get_tree().process_frame
	for id in HERO_ORDER:
		GameData.hero(id).model = CUSTOM_MODELS[id] if _use_custom else _original_models[id]   # nur im Speicher
	Session.hero_id = HERO_ORDER[0]
	var m: MatchController = load(MATCH_SCENE).instantiate()
	# Nur ein Nachzügler in ferner Zukunft: keine Wellen, die Runde endet nie
	m.waves_override = [GameData.normalize_wave({"prepare_seconds": 0, "groups": [{"enemy": "grunt", "count": 1, "path": 0, "delay": 1000000}]}, 1)]
	add_child(m)
	_match = m
	m.hud.visible = false
	m.hero_input.input_enabled = false
	_heroes = {HERO_ORDER[0]: m.local_hero}
	for i in range(1, HERO_ORDER.size()):
		_heroes[HERO_ORDER[i]] = m._spawn_hero(HERO_ORDER[i], i + 1)
	for h: Hero in _heroes.values():
		h.set_physics_process(false)   # kein Laufen, kein Auto-Angriff: zu sehen ist nur die Fähigkeit
		h.abilities.cast_failed.connect(_on_cast_failed)
	_dummies.clear()
	for i in DUMMIES.size():
		_dummies.append(_spawn_dummy(i))
	_reset_stage()
	_camera.make_current()
	await get_tree().create_timer(1.2).timeout   # Auftauchen der Puppen abwarten
	_busy = false


## Trainingspuppe: echter Gegner mit eigener Kopie der Werte, der nicht laufen und nicht zuschlagen kann.
func _spawn_dummy(i: int) -> Enemy:
	var e := _match.spawner.spawn(DUMMIES[i][0], 0)
	e.data = e.data.duplicate()
	e.data.move_speed = 0.0
	e.data.attack_range = 0.0
	e.health.setup(DUMMY_HP)
	e.global_position = STAGE + DUMMIES[i][1]
	return e


## Alle zurück auf ihre Plätze, volle LP, keine Zustände: Jede Vorführung beginnt gleich.
func _reset_stage() -> void:
	for p in _match.projectiles_root.get_children():
		p.queue_free()   # Feuerbälle und Sternenregen der vorigen Vorführung beenden
	var caster_id: String = HERO_ORDER[_hero_index]
	var ally := 0
	for id in HERO_ORDER:
		var h: Hero = _heroes[id]
		h.command_stop()
		h.status.clear()
		if h.health.shield_total() > 0.0:
			h.health._shields.clear()   # Schild einer vorigen Arcane Barrier entfernen
			h.health.shield_changed.emit(0.0)
		if id == caster_id:
			h.global_position = STAGE
		else:
			h.global_position = STAGE + ALLY_OFFSETS[ally]
			ally += 1
		h.rotation.y = -PI * 0.5   # Blick nach +X, zu den Puppen
	for i in _dummies.size():
		var e := _dummies[i]
		if not is_instance_valid(e) or not e.is_alive():
			if is_instance_valid(e):
				e.queue_free()
			e = _spawn_dummy(i)
			_dummies[i] = e
		e.status.clear()
		e.health.setup(DUMMY_HP)
		e.global_position = STAGE + DUMMIES[i][1]


func _cast_current() -> void:
	if _busy or _match == null:
		return
	_reset_stage()
	_note = ""
	var id := _current_skill()
	var def := GameData.skill(id)
	var hero: Hero = _heroes[HERO_ORDER[_hero_index]]
	hero.abilities.levels[id] = _level
	hero.abilities.slots[0] = id
	hero.abilities.cooldowns.clear()
	hero.mana = 100000.0
	var target: Node3D = null
	var point := hero.global_position
	match String(def.target):
		"enemy":
			target = _pick_dummy(hero, float(GameData.skill_value(id, _level, "range", 0.0)))
			point = target.global_position
		"ally":
			target = _heroes[HERO_ORDER[(_hero_index + 1) % HERO_ORDER.size()]]
			point = target.global_position
		"point":
			point = _dummy_center()
	hero.abilities.request_cast(0, target, point)
	if hero.abilities.is_queued():
		hero.abilities.cancel_queue()
		_note = "Ziel außer Reichweite, Aufstellung prüfen."
	_repeat_left = REPEAT_SECONDS
	_update_info()


## Nahkampf trifft die vorderste Puppe, Fernkampf die hinterste in Reichweite: So sieht man Sprung,
## Blitz oder Geschoss über eine sichtbare Strecke.
func _pick_dummy(hero: Hero, cast_range: float) -> Enemy:
	var best: Enemy = null
	var best_dist := 0.0
	for e in _dummies:
		var d := Vector2(e.global_position.x - hero.global_position.x, e.global_position.z - hero.global_position.z).length()
		if d > cast_range + e.body_radius:
			continue
		if best == null or (d > best_dist if cast_range >= 5.0 else d < best_dist):
			best = e
			best_dist = d
	return best if best != null else _dummies[0]


func _dummy_center() -> Vector3:
	var sum := Vector3.ZERO
	for e in _dummies:
		sum += e.global_position
	return sum / float(_dummies.size())


func _skills_of(hero_id: String) -> Array[String]:
	var list: Array[String] = []
	for sid in GameData.skill_order:
		if hero_id in GameData.skill(sid).heroes:
			list.append(sid)
	return list


func _current_skill() -> String:
	return _skills_of(HERO_ORDER[_hero_index])[_skill_index]


func _select_skill(sid: String) -> void:
	var def := GameData.skill(sid)
	if def.is_empty():
		push_warning("Unbekannte Fähigkeit: %s" % sid)
		return
	_hero_index = maxi(HERO_ORDER.find(def.heroes[0]), 0)
	_skill_index = maxi(_skills_of(HERO_ORDER[_hero_index]).find(sid), 0)


## Nächste bzw. vorherige Fähigkeit; am Ende der Liste geht es beim nächsten Helden weiter.
func _step(direction: int) -> void:
	_skill_index += direction
	if _skill_index >= _skills_of(HERO_ORDER[_hero_index]).size():
		_hero_index = (_hero_index + 1) % HERO_ORDER.size()
		_skill_index = 0
	elif _skill_index < 0:
		_hero_index = (_hero_index - 1 + HERO_ORDER.size()) % HERO_ORDER.size()
		_skill_index = _skills_of(HERO_ORDER[_hero_index]).size() - 1
	_cast_current()


func _on_cast_failed(_hero: Hero, ability_id: String, reason: String) -> void:
	_note = "%s: %s" % [GameData.skill(ability_id).get("name", ability_id), reason]
	_update_info()


func _update_info() -> void:
	var hero_id: String = HERO_ORDER[_hero_index]
	var def := GameData.skill(_current_skill())
	var anim := "%s ×%.1f" % [def.anim, float(def.anim_speed)]
	if float(def.anim_start) > 0.0:
		anim += ", Start bei %d %%" % roundi(float(def.anim_start) * 100.0)
	var lines: Array[String] = []
	lines.append("%s   –   %s   (Stufe %d von %d)" % [GameData.hero(hero_id).name, def.name, _level, GameData.MAX_SKILL_LEVEL])
	lines.append(String(def.description))
	lines.append("Ziel: %s      Animation: %s" % [TARGET_LABELS.get(String(def.target), def.target), anim])
	lines.append("Fähigkeit %d / %d%s      wird alle %d s neu gewirkt" % [_skill_index + 1, _skills_of(hero_id).size(),
		"  (Ultimate)" if def.ultimate else "", roundi(REPEAT_SECONDS)])
	lines.append("%s      Gegner sind Trainingspuppen: stehen still, greifen nicht an" % ("NEUE Modelle (Blender)" if _use_custom else "ORIGINAL-Modelle (KayKit)"))
	if _note != "":
		lines.append("Hinweis: " + _note)
	_info.text = "\n".join(lines)


func _process(delta: float) -> void:
	var target := STAGE + CAMERA_OFFSET
	var dir := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch))
	_camera.position = target + dir * _distance
	_camera.look_at(target, Vector3.UP)
	if _busy or _match == null:
		return
	for h: Hero in _heroes.values():
		if not h.visual.is_busy():
			h.visual.play("idle")   # Helden sind angehalten: nach der Fähigkeit zurück in die Grundhaltung
	_repeat_left -= delta
	if _repeat_left <= 0.0:
		_cast_current()


## Eigene Steuerung vor allen anderen: Spielsteuerung (Pause, Kamera, Befehle) bekommt nichts davon.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(3.0, _distance * 0.9)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(40.0, _distance * 1.1)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.008
		_pitch = clampf(_pitch + mm.relative.y * 0.005, 0.05, 1.4)
	elif event is InputEventKey:
		if event.pressed and not event.echo:
			_on_key((event as InputEventKey).keycode)
	else:
		return
	get_viewport().set_input_as_handled()


func _on_key(key: Key) -> void:
	match key:
		KEY_F, KEY_RIGHT:
			_step(1)
		KEY_LEFT:
			_step(-1)
		KEY_SPACE:
			_cast_current()
		KEY_UP:
			_level = mini(_level + 1, GameData.MAX_SKILL_LEVEL)
			_cast_current()
		KEY_DOWN:
			_level = maxi(_level - 1, 1)
			_cast_current()
		KEY_1, KEY_2, KEY_3:
			_hero_index = int(key) - int(KEY_1)
			_skill_index = 0
			_cast_current()
		KEY_TAB:
			if not _busy:
				_use_custom = not _use_custom
				await _build_match()
				_cast_current()
		KEY_R:
			_reset_camera()
		KEY_ESCAPE:
			get_tree().quit()
