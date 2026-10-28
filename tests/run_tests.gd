extends SceneTree
## Testläufer:
##   godot --headless --fixed-fps 60 --path . -s res://tests/run_tests.gd
## Führt alle tests/test_*.gd aus. Jede Testdatei hat Funktionen test_*(t).
## --fixed-fps 60 lässt die Simulation so schnell wie möglich laufen (1 Physik-Schritt pro Frame).
## TEST_ONLY=<teil> filtert nach Testnamen. Exit-Code 0 = alles bestanden.

var failures := 0
var passed := 0
var current := ""


func _initialize() -> void:
	# Autoloads sind bei -s erst im ersten Frame verfügbar
	await process_frame
	# Telemetrie der Tests in einen eigenen, frischen Ordner – echte Balancing-Daten bleiben unberührt
	var telemetry_dir := "user://telemetry_test"
	for f in (DirAccess.get_files_at(telemetry_dir) if DirAccess.dir_exists_absolute(telemetry_dir) else PackedStringArray()):
		DirAccess.remove_absolute(telemetry_dir.path_join(f))
	root.get_node("Session").telemetry_directory_override = telemetry_dir
	var files: Array[String] = []
	for f in DirAccess.get_files_at("res://tests"):
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
	files.sort()
	var only := OS.get_environment("TEST_ONLY")
	for f in files:
		var script: GDScript = load("res://tests/" + f)
		if script == null or not script.can_instantiate():
			current = f
			check(false, "Testdatei lässt sich nicht laden (Parse-Fehler?)")
			continue
		var inst = script.new()
		for m in script.get_script_method_list():
			var name: String = m.name
			if not name.begins_with("test_"):
				continue
			if only != "" and not name.contains(only):
				continue
			current = "%s::%s" % [f, name]
			var before := failures
			await inst.call(name, self)
			if failures == before:
				passed += 1
				print("  ok   ", current)
		if inst is Node:
			inst.queue_free()
	# Laufende Sounds stoppen, sonst meldet Godot beim sofortigen Beenden belegte Ressourcen
	root.get_node("Audio").stop_all()
	await process_frame
	print("\n%d bestanden, %d fehlgeschlagen" % [passed, failures])
	quit(1 if failures > 0 else 0)


func check(cond: bool, msg: String) -> bool:
	if not cond:
		failures += 1
		printerr("  FAIL ", current, ": ", msg)
	return cond


func eq(a, b, msg: String) -> bool:
	return check(a == b, "%s (erwartet %s, erhalten %s)" % [msg, str(b), str(a)])


## Wartet, bis cond() wahr ist oder max_frames vergangen sind. Gibt zurück, ob die Bedingung eintrat.
func wait_until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await physics_frame
	return cond.call()


func frames(n: int) -> void:
	for i in n:
		await physics_frame
