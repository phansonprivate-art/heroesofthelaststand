class_name EnemySpawner
extends Node
## Erzeugt Gegner, führt die Liste lebender Gegner und beantwortet räumliche Abfragen
## (nächster Gegner, Abstand halten) über ein einfaches Raster statt Suchen über alle Objekte.

signal enemy_spawned(enemy: Enemy)
signal enemy_killed(enemy: Enemy, info: DamageInfo)
signal alive_count_changed(count: int)

# Bewusst kein preload: enemy.gd referenziert EnemySpawner, ein preload ergäbe einen Ladezyklus.
const ENEMY_SCENE_PATH := "res://scenes/enemies/enemy.tscn"
const CELL := 2.0
const SPAWN_JITTER := 1.5

var container: Node3D
var paths: Array[PackedVector3Array] = []
var core: DefenseCore
var combat: CombatService
var heroes: Array[Hero] = []   ## mögliche Ziele für die Nähe-Aggro der Gegner
var path_variants: Dictionary = {}   ## Pfadnummer -> Wegvarianten (Zitadelle: Mitte über Nord- oder Südbogen), abwechselnd genutzt
var structures: Array[MapStructure] = []   ## Bauwerke der Karte (Wachtürme, Torhaus), von der Karte eingetragen
var world: Node                  ## MatchController (Effekte, Geschosse, Kamera für Gegnerfähigkeiten)
var hp_multiplier := 1.0         ## Spielerzahl-Skalierung
var wave_number := 1             ## aktuelle Welle; steuert die Schwierigkeitssteigerung
var hp_growth_per_wave := 0.0
var damage_growth_per_wave := 0.0
var _next_uid := 0
var separation_radius := 1.1
var killed_total := 0

var _alive: Array[Enemy] = []
var _grid: Dictionary = {}   ## Vector2i -> Array[Enemy], jeden Physik-Frame neu aufgebaut
var _enemy_scene: PackedScene
var _variant_next: Dictionary = {}   ## Pfadnummer -> nächste Variante


func spawn(enemy_id: String, path_index: int) -> Enemy:
	if not multiplayer.is_server():
		return null
	var def := GameData.enemy(enemy_id)
	if def.is_empty():
		push_error("Unbekannter Gegnertyp: %s" % enemy_id)
		return null
	if paths.is_empty():
		push_error("Keine Spawnpfade vorhanden")
		return null
	if path_index < 0 or path_index >= paths.size():
		push_error("Ungültiger Pfad %d, nutze 0" % path_index)
		path_index = 0
	var path := paths[path_index]
	var variants: Array = path_variants.get(path_index, [])
	if variants.size() > 1:
		var k: int = _variant_next.get(path_index, 0)
		path = variants[k % variants.size()]
		_variant_next[path_index] = k + 1
	var side := Vector3(randf_range(-SPAWN_JITTER, SPAWN_JITTER), 0.0, randf_range(-SPAWN_JITTER, SPAWN_JITTER))
	var e := _create(def, path, path[0] + side)
	if path.size() > 1:
		var dir := path[1] - path[0]
		e.rotation.y = atan2(-dir.x, -dir.z)
	return e


## Beschworener Gegner (Boss): erscheint an `pos` und läuft ohne Wegpunkte direkt zum Kern bzw. zu Helden.
func spawn_at(enemy_id: String, pos: Vector3) -> Enemy:
	if not multiplayer.is_server():
		return null
	var def := GameData.enemy(enemy_id)
	if def.is_empty():
		push_error("Unbekannter Gegnertyp: %s" % enemy_id)
		return null
	var e := _create(def, PackedVector3Array(), Vector3(pos.x, 0.0, pos.z))
	if core != null:
		var dir := core.global_position - e.global_position
		e.rotation.y = atan2(-dir.x, -dir.z)
	return e


func _create(def: Dictionary, path: PackedVector3Array, pos: Vector3) -> Enemy:
	if _enemy_scene == null:
		_enemy_scene = load(ENEMY_SCENE_PATH)
	var e: Enemy = _enemy_scene.instantiate()
	e.world = world
	container.add_child(e)
	e.global_position = pos
	_next_uid += 1
	e.uid = _next_uid
	var w := maxi(0, wave_number - 1)
	var hp_mult := hp_multiplier * (1.0 + hp_growth_per_wave * w)
	e.setup(def, path, core, combat, self, hp_mult, 1.0 + damage_growth_per_wave * w)
	e.died.connect(_on_enemy_died)
	_alive.append(e)
	enemy_spawned.emit(e)
	alive_count_changed.emit(_alive.size())
	return e


func alive_count() -> int:
	return _alive.size()


func alive_enemies() -> Array[Enemy]:
	return _alive


func clear_all() -> void:
	_alive.clear()
	_grid.clear()
	if container != null:
		for child in container.get_children():
			child.queue_free()
	alive_count_changed.emit(0)


func celebrate_all() -> void:
	for e in _alive:
		if is_instance_valid(e):
			e.celebrate()


func nearest_enemy(point: Vector3, radius: float) -> Enemy:
	var best: Enemy = null
	var best_d := radius * radius
	for e in _alive:
		var d := _flat_dist_sq(e.global_position, point)
		if d <= best_d:
			best_d = d
			best = e
	return best


## Nächster lebender Held innerhalb des Radius (Helden sind wenige, eine einfache Schleife reicht).
func nearest_hero(point: Vector3, radius: float) -> Hero:
	var best: Hero = null
	var best_d := radius * radius
	for h in heroes:
		if not is_instance_valid(h) or not h.is_alive() or h.status.has(StatusEffects.UNTARGETABLE):
			continue
		var d := _flat_dist_sq(h.global_position, point)
		if d <= best_d:
			best_d = d
			best = h
	return best


## Nächstes stehendes Bauwerk, gemessen ab seiner Oberfläche (Torhaus: ab der Mauerlinie).
func nearest_structure(point: Vector3, radius: float) -> MapStructure:
	var best: MapStructure = null
	var best_d := radius
	for s in structures:
		if not is_instance_valid(s) or not s.is_alive():
			continue
		var d := s.surface_distance(point)
		if d <= best_d:
			best_d = d
			best = s
	return best


func enemies_in_radius(point: Vector3, radius: float) -> Array[Enemy]:
	var result: Array[Enemy] = []
	var r2 := radius * radius
	for e in _alive:
		if _flat_dist_sq(e.global_position, point) <= r2:
			result.append(e)
	return result


## Abstoßungsvektor gegenüber nahen Gegnern, damit sie nicht zu einem Klumpen verschmelzen.
func separation(e: Enemy) -> Vector3:
	var push := Vector3.ZERO
	var pos := e.global_position
	var cell := _cell_of(pos)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for other: Enemy in _grid.get(cell + Vector2i(dx, dz), []):
				if other == e:
					continue
				var diff := Vector3(pos.x - other.global_position.x, 0.0, pos.z - other.global_position.z)
				var min_dist: float = separation_radius * (e.body_radius + other.body_radius)
				var d := diff.length()
				if d < min_dist:
					if d < 0.001:
						diff = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
						d = 0.001
					push += diff / d * (1.0 - d / min_dist)
	return push


func _physics_process(_delta: float) -> void:
	_grid.clear()
	for e in _alive:
		var c := _cell_of(e.global_position)
		if not _grid.has(c):
			_grid[c] = []
		_grid[c].append(e)


func _on_enemy_died(e: Enemy, info: DamageInfo) -> void:
	_alive.erase(e)
	killed_total += 1
	enemy_killed.emit(e, info)
	alive_count_changed.emit(_alive.size())


func _cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


func _flat_dist_sq(a: Vector3, b: Vector3) -> float:
	return (a.x - b.x) * (a.x - b.x) + (a.z - b.z) * (a.z - b.z)
