extends RefCounted
## WaveManager ohne Szene, mit einer Spawner-Attrappe.


class FakeSpawner:
	extends RefCounted
	var spawned: Array = []
	var alive := 0

	func spawn(enemy_id: String, path: int) -> void:
		spawned.append([enemy_id, path])
		alive += 1

	func alive_count() -> int:
		return alive


func _make(waves: Array) -> Array:
	var wm := WaveManager.new()
	var fake := FakeSpawner.new()
	var normalized := []
	var n := 0
	for w in waves:
		n += 1
		normalized.append(GameData.normalize_wave(w, n))
	wm.waves = normalized
	wm.spawner = fake
	return [wm, fake]


func _run(wm: WaveManager, seconds: float, step := 0.1) -> void:
	var steps := roundi(seconds / step)
	for i in steps:
		wm.tick(step)


func test_wave_flow_and_spawn_timing(t) -> void:
	var parts := _make([
		{"prepare_seconds": 5, "groups": [{"enemy": "grunt", "count": 3, "path": 0, "interval": 1.0, "delay": 0},
			{"enemy": "runner", "count": 2, "path": 2, "interval": 0.5, "delay": 2.0}]},
		{"prepare_seconds": 3, "groups": [{"enemy": "brute", "count": 1, "path": 1}]},
	])
	var wm: WaveManager = parts[0]
	var fake: FakeSpawner = parts[1]
	var completed := []
	var finished := [0]
	wm.wave_completed.connect(func(n: int) -> void: completed.append(n))
	wm.all_waves_completed.connect(func() -> void: finished[0] += 1)
	wm.start()
	t.eq(wm.state, WaveManager.State.PREPARING, "startet mit Vorbereitung")
	_run(wm, 4.5)
	t.eq(fake.spawned.size(), 0, "während der Vorbereitung kein Spawn")
	_run(wm, 0.6)
	t.eq(fake.spawned.size(), 1, "erster Gegner direkt zum Wellenstart")
	_run(wm, 3.0)
	t.eq(fake.spawned.size(), 5, "alle fünf Gegner nach Ablauf der Zeitpunkte")
	t.eq(wm.state, WaveManager.State.CLEARING, "wartet auf das Besiegen")
	_run(wm, 10.0)
	t.eq(completed.size(), 0, "Welle nicht abgeschlossen, solange Gegner leben")
	fake.alive = 0
	wm.tick(0.1)
	t.eq(completed, [1], "Welle 1 abgeschlossen")
	t.eq(wm.state, WaveManager.State.PREPARING, "Vorbereitung auf Welle 2")
	t.eq(wm.current_wave_number(), 2, "Wellenanzeige korrekt")
	_run(wm, 3.2)
	fake.alive = 0
	_run(wm, 1.0)
	t.eq(completed, [1, 2], "Welle 2 abgeschlossen")
	t.eq(finished[0], 1, "Ende genau einmal gemeldet")
	t.eq(wm.state, WaveManager.State.FINISHED, "fertig")
	_run(wm, 5.0)
	t.eq(completed, [1, 2], "keine doppelten Abschlüsse nach Ende")
	wm.free()


func test_skip_preparation(t) -> void:
	var parts := _make([{"prepare_seconds": 30, "groups": [{"enemy": "grunt", "count": 1, "path": 0}]}])
	var wm: WaveManager = parts[0]
	var fake: FakeSpawner = parts[1]
	wm.start()
	wm.skip_preparation()
	wm.tick(0.016)
	t.eq(fake.spawned.size(), 1, "Welle startet sofort")
	wm.free()


func test_spawn_paths_from_data(t) -> void:
	var parts := _make([{"prepare_seconds": 0, "groups": [{"enemy": "grunt", "count": 2, "path": 1}, {"enemy": "runner", "count": 1, "path": 2, "delay": 0}]}])
	var wm: WaveManager = parts[0]
	var fake: FakeSpawner = parts[1]
	wm.start()
	_run(wm, 3.0)
	var paths := fake.spawned.map(func(s: Array) -> int: return s[1])
	t.check(paths.count(1) == 2 and paths.count(2) == 1, "Gegner nutzen die angegebenen Pfade: %s" % str(paths))
	wm.free()


func test_stop_halts_spawning(t) -> void:
	var parts := _make([{"prepare_seconds": 0, "groups": [{"enemy": "grunt", "count": 10, "path": 0, "interval": 1.0}]}])
	var wm: WaveManager = parts[0]
	var fake: FakeSpawner = parts[1]
	wm.start()
	_run(wm, 2.05)
	var before := fake.spawned.size()
	wm.stop()
	_run(wm, 10.0)
	t.eq(fake.spawned.size(), before, "nach stop() keine weiteren Gegner")
	wm.free()
