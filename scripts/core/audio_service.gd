extends Node
## Zentrale Audioverwaltung (Autoload "Audio"). Spielt Ereignisse aus data/audio/sounds.json ab.
## - Player-Pools statt neuer Nodes pro Sound
## - je Ereignis Mindestabstand und Höchstzahl gleichzeitiger Wiedergaben, damit große Kämpfe nicht dröhnen
## - eigene Busse (SFX, UI, Music) für spätere Lautstärkeregler (Phase 7)
## Spiellogik ruft das nicht direkt auf; MatchAudio hört auf Spielsignale und löst Sounds aus.

const CONFIG_PATH := "res://data/audio/sounds.json"
const AUDIO_ROOT := "res://assets/audio/"
const POOL_3D := 24
const POOL_2D := 10
## Abschwächung so gewählt, dass Ereignisse im Kamerabild (ca. 15–45 m entfernt) gut hörbar sind
const UNIT_SIZE := 22.0
const MAX_DISTANCE := 90.0

var events: Dictionary = {}       ## id -> Definition
var errors: PackedStringArray = []
var muted := false

var _streams: Dictionary = {}     ## Pfad -> AudioStream
var _last_played: Dictionary = {} ## id -> Zeit (ms)
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _pool_2d: Array[AudioStreamPlayer] = []
var _active: Array[Dictionary] = []   ## laufende Sounds: {event, until (ms)} – unabhängig vom Player-Zustand
var _headless := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_headless = DisplayServer.get_name() == "headless"
	_load_config()
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = UNIT_SIZE
		p.max_distance = MAX_DISTANCE
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_pool_3d.append(p)
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool_2d.append(p)
	# Jeder Button im Spiel klickt – ohne dass jedes Menü daran denken muss
	get_tree().node_added.connect(_on_node_added)


## Spielt ein Ereignis. `position` nur für räumliche Sounds. Gibt true zurück, wenn etwas abgespielt wurde.
func play(event_id: String, position: Variant = null) -> bool:
	if muted:
		return false
	var def: Dictionary = events.get(event_id, {})
	if def.is_empty():
		return false
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(event_id, -100000)) < int(def.cooldown * 1000.0):
		return false
	if _count_playing(event_id) >= int(def.max):
		return false
	var stream := _stream(String(def.files.pick_random()))
	if stream == null:
		return false
	# Schichten (z. B. Schlag + Knochenknacken) gleichzeitig, jede mit eigenen Grenzen
	for layer in def.layers:
		if layer != event_id:
			play(layer, position)
	var pitch := 1.0 + randf_range(-def.pitch_var, def.pitch_var)
	_active.append({"event": event_id, "until": now + int(stream.get_length() / pitch * 1000.0)})
	_last_played[event_id] = now
	# Headless (Tests, Server) mischt der Dummy-Treiber nie; abgespielte Instanzen würden nie freigegeben.
	# Die Logik oben läuft trotzdem vollständig, nur die Wiedergabe entfällt.
	if _headless:
		return true
	var player: Node
	if def.positional and position is Vector3 and is_inside_tree():
		player = _free_player(_pool_3d)
		if player != null:
			(player as AudioStreamPlayer3D).global_position = position
	else:
		player = _free_player(_pool_2d)
	if player == null:
		return false
	player.stream = stream
	player.volume_db = float(def.volume_db)
	player.pitch_scale = pitch
	player.bus = String(def.bus)
	player.play()
	return true


## Stoppt alles und gibt zwischengespeicherte Streams frei (Beenden, Tests).
func stop_all() -> void:
	for p in _pool_3d + _pool_2d:
		p.stop()
		p.stream = null
	_active.clear()
	_streams.clear()


func _exit_tree() -> void:
	stop_all()


func has_event(event_id: String) -> bool:
	return events.has(event_id)


func _load_config() -> void:
	events.clear()
	errors.clear()
	if not FileAccess.file_exists(CONFIG_PATH):
		errors.append("Audio-Konfiguration fehlt: %s" % CONFIG_PATH)
		return
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not doc is Dictionary:
		errors.append("Audio-Konfiguration ist kein gültiges JSON")
		return
	_setup_buses(doc.get("buses", {}))
	for id in doc.get("events", {}):
		var src: Dictionary = doc.events[id]
		var files: Array = []
		for f in src.get("files", []):
			var path: String = AUDIO_ROOT + String(f)
			if ResourceLoader.exists(path):
				files.append(path)
			else:
				errors.append("Sound fehlt (%s): %s" % [id, path])
		if files.is_empty():
			continue
		var bus := String(src.get("bus", "SFX"))
		if AudioServer.get_bus_index(bus) < 0:
			errors.append("Unbekannter Audio-Bus '%s' (%s), nutze Master" % [bus, id])
			bus = "Master"
		events[id] = {
			"files": files,
			"volume_db": float(src.get("volume_db", 0.0)),
			"pitch_var": clampf(float(src.get("pitch_var", 0.0)), 0.0, 0.5),
			"cooldown": maxf(0.0, float(src.get("cooldown", 0.0))),
			"max": maxi(1, int(src.get("max", 4))),
			"positional": bool(src.get("positional", false)),
			"bus": bus,
			"layers": src.get("layers", []),
		}
	for id in events:
		for layer in events[id].layers:
			if not events.has(layer):
				errors.append("Ereignis %s: unbekannte Schicht '%s'" % [id, layer])
	for e in errors:
		push_warning("[Audio] " + e)


func _setup_buses(buses: Dictionary) -> void:
	for name in buses:
		var idx := AudioServer.get_bus_index(name)
		if idx < 0:
			AudioServer.add_bus()
			idx = AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, name)
			AudioServer.set_bus_send(idx, "Master")
		AudioServer.set_bus_volume_db(idx, float(buses[name]))


func _stream(path: String) -> AudioStream:
	if not _streams.has(path):
		_streams[path] = load(path)
	return _streams[path]


func _free_player(pool: Array) -> Node:
	for p in pool:
		if not p.playing:
			return p
	return null


func _count_playing(event_id: String) -> int:
	var now := Time.get_ticks_msec()
	_active = _active.filter(func(a: Dictionary) -> bool: return a.until > now)
	return _active.filter(func(a: Dictionary) -> bool: return a.event == event_id).size()


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		(node as BaseButton).pressed.connect(func() -> void: play("ui_click"))
