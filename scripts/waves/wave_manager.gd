class_name WaveManager
extends Node
## Steuert den Wellenablauf: Vorbereitung -> Spawnen -> Aufräumen -> nächste Welle.
## Eine Welle gilt erst als abgeschlossen, wenn alle Gegner gespawnt und besiegt sind.
## Jede Welle wird höchstens einmal abgeschlossen (Schutz vor doppelten Belohnungen).
## Läuft über _process und pausiert daher automatisch mit dem SceneTree.

signal wave_announced(wave_number: int, wave: Dictionary, seconds: float)
signal wave_started(wave_number: int, wave: Dictionary)
signal wave_completed(wave_number: int)
signal all_waves_completed
signal state_changed(state: State)

enum State { IDLE, PREPARING, SPAWNING, CLEARING, FINISHED }

var waves: Array = []
## Erwartet spawn(enemy_id: String, path: int) und alive_count() -> int (EnemySpawner oder Test-Attrappe).
var spawner: Object
var state := State.IDLE
var current_index := -1
var prepare_left := 0.0

var _queue: Array[Dictionary] = []   ## [{time, enemy, path}], nach Zeit sortiert
var _elapsed := 0.0
var _completed: Dictionary = {}      ## wave_number -> true


## first_index: mit dieser Welle beginnen (Testmodus); die früheren gelten als nicht gespielt.
func start(first_index := 0) -> void:
	if waves.is_empty():
		push_error("WaveManager: keine Wellen definiert")
		return
	_completed.clear()
	_begin_preparation(clampi(first_index, 0, waves.size() - 1))


func stop() -> void:
	_queue.clear()
	_set_state(State.FINISHED)


func _process(delta: float) -> void:
	if multiplayer.is_server():
		tick(delta)


func tick(delta: float) -> void:
	match state:
		State.PREPARING:
			prepare_left -= delta
			if prepare_left <= 0.0:
				_start_spawning()
		State.SPAWNING:
			_elapsed += delta
			while not _queue.is_empty() and _queue[0].time <= _elapsed:
				var entry: Dictionary = _queue.pop_front()
				spawner.spawn(entry.enemy, entry.path)
			if _queue.is_empty():
				_set_state(State.CLEARING)
		State.CLEARING:
			if spawner.alive_count() == 0:
				_complete_current()


## Startet die nächste Welle sofort, statt die Vorbereitungszeit abzuwarten.
func skip_preparation() -> void:
	if state == State.PREPARING:
		prepare_left = 0.0


func current_wave_number() -> int:
	return current_index + 1


func total_waves() -> int:
	return waves.size()


func current_wave() -> Dictionary:
	return waves[current_index] if current_index >= 0 and current_index < waves.size() else {}


func remaining_to_spawn() -> int:
	return _queue.size()


func is_wave_completed(wave_number: int) -> bool:
	return _completed.has(wave_number)


## Kurze Beschreibung der Gegnergruppen einer Welle, z. B. für die Ankündigung.
static func describe(wave: Dictionary) -> String:
	var counts := {}
	for g in wave.get("groups", []):
		counts[g.enemy] = counts.get(g.enemy, 0) + int(g.count)
	var parts: PackedStringArray = []
	for id in counts:
		parts.append("%d× %s" % [counts[id], GameData.enemy(id).get("name", id)])
	return ", ".join(parts)


func _begin_preparation(index: int) -> void:
	current_index = index
	var wave: Dictionary = waves[index]
	prepare_left = float(wave.prepare_seconds)
	_set_state(State.PREPARING)
	wave_announced.emit(index + 1, wave, prepare_left)


func _start_spawning() -> void:
	var wave: Dictionary = waves[current_index]
	_queue.clear()
	for g in wave.groups:
		for i in int(g.count):
			_queue.append({"time": float(g.delay) + i * float(g.interval), "enemy": g.enemy, "path": int(g.path)})
	_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.time < b.time)
	_elapsed = 0.0
	_set_state(State.SPAWNING)
	wave_started.emit(current_index + 1, wave)
	tick(0.0)   # Gegner mit Verzögerung 0 sofort erzeugen


func _complete_current() -> void:
	var number := current_index + 1
	if _completed.has(number):
		return
	_completed[number] = true
	wave_completed.emit(number)
	if current_index + 1 >= waves.size():
		_set_state(State.FINISHED)
		all_waves_completed.emit()
	else:
		_begin_preparation(current_index + 1)


func _set_state(s: State) -> void:
	if state == s:
		return
	state = s
	state_changed.emit(s)
