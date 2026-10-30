class_name Arena
extends GameMap
## Arena: Boden, Spawnpfade und Heldenstartpunkt stehen in der Szene (im Editor anpassbar).
## Mauerring, Tore, Pfadmarkierungen und Deko werden hier aus KayKit-Teilen gebaut.

const HALF := 32.0
const SEGMENT := 4.0
const ENV := "res://assets/models/environment/"

@onready var spawn_paths: Node3D = $SpawnPaths
@onready var hero_spawn: Marker3D = $HeroSpawn
@onready var decor: Node3D = $Decor

var _scene_cache: Dictionary = {}
var _gate_walls: Array[Vector3] = []


func _ready() -> void:
	_build_walls()
	_build_path_strips()
	_build_decor()


## Wegpunkte aller Spawnpfade in Reihenfolge der Kindknoten (0 = Nord, 1 = West, 2 = Ost).
func get_spawn_paths() -> Array[PackedVector3Array]:
	var result: Array[PackedVector3Array] = []
	for path in spawn_paths.get_children():
		var points := PackedVector3Array()
		for m in path.get_children():
			if m is Marker3D:
				points.append((m as Marker3D).global_position)
		result.append(points)
	return result


func hero_spawn_point(_index := 0) -> Vector3:
	return hero_spawn.global_position


func camera_bounds() -> Rect2:
	return Rect2(-HALF + 6.0, -HALF + 6.0, HALF * 2.0 - 12.0, HALF * 2.0 - 12.0)


func minimap_extent() -> Rect2:
	return Rect2(-HALF, -HALF, HALF * 2.0, HALF * 2.0)


func _gate_positions() -> Array[Vector3]:
	var gates: Array[Vector3] = []
	for points in get_spawn_paths():
		if not points.is_empty():
			gates.append(points[0])
	return gates


func _build_walls() -> void:
	var gates := _gate_positions()
	var count := int(HALF * 2.0 / SEGMENT)
	for side in 4:
		for i in count:
			var along := -HALF + SEGMENT * 0.5 + i * SEGMENT
			# Seiten: 0 = Nord, 1 = Süd, 2 = West, 3 = Ost; die Wandfront zeigt jeweils zur Mitte
			var pos: Vector3 = [Vector3(along, 0, -HALF), Vector3(along, 0, HALF), Vector3(-HALF, 0, along), Vector3(HALF, 0, along)][side]
			var rot: float = [0.0, PI, PI * 0.5, -PI * 0.5][side]
			var is_gate := false
			for g in gates:
				if Vector2(g.x, g.z).distance_to(Vector2(pos.x, pos.z)) < SEGMENT * 0.75:
					is_gate = true
			_place("wall_doorway.glb" if is_gate else ("wall_cracked" if (i * 7 + side) % 5 == 0 else "wall"), pos, rot)
			if is_gate:
				_gate_walls.append(pos)
				_place_gate_glow(pos, rot)
	for corner in [Vector3(-HALF, 0, -HALF), Vector3(HALF, 0, -HALF), Vector3(-HALF, 0, HALF), Vector3(HALF, 0, HALF)]:
		_place("pillar", corner, 0.0)
	# Kollision: vier unsichtbare Wände
	for spec in [[Vector3(0, 2, -HALF), Vector3(HALF * 2, 4, 1)], [Vector3(0, 2, HALF), Vector3(HALF * 2, 4, 1)],
			[Vector3(-HALF, 2, 0), Vector3(1, 4, HALF * 2)], [Vector3(HALF, 2, 0), Vector3(1, 4, HALF * 2)]]:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = spec[1]
		shape.shape = box
		body.add_child(shape)
		body.position = spec[0]
		decor.add_child(body)


func _place_gate_glow(pos: Vector3, rot: float) -> void:
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2.4, 3.2)
	quad.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.85, 0.15, 0.25, 0.55)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material_override = mat
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.position = pos + Vector3(0, 1.6, 0)
	quad.rotation.y = rot
	decor.add_child(quad)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.25, 0.3)
	light.light_energy = 2.5
	light.omni_range = 8.0
	light.position = pos + Vector3(0, 2.0, 0) + _inward(pos) * 1.5
	decor.add_child(light)


func _inward(wall_pos: Vector3) -> Vector3:
	return -Vector3(wall_pos.x, 0, wall_pos.z).normalized()


## Dunkle Bodenstreifen entlang der Pfade, damit die Laufwege der Gegner gut lesbar sind.
func _build_path_strips() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.23, 0.22)
	mat.roughness = 1.0
	for points in get_spawn_paths():
		var pts := Array(points)
		pts.append(Vector3.ZERO)
		for i in pts.size() - 1:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			var length := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
			var strip := MeshInstance3D.new()
			var plane := PlaneMesh.new()
			plane.size = Vector2(2.6, length + 2.6)
			strip.mesh = plane
			strip.material_override = mat
			strip.position = (a + b) * 0.5 + Vector3(0, 0.01 + i * 0.001, 0)
			strip.rotation.y = atan2(b.x - a.x, b.z - a.z)
			strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			decor.add_child(strip)


func _build_decor() -> void:
	# Säulen in den Zwischenräumen der drei Pfade, abseits der Laufwege
	for p in [Vector3(-13, 0, -13), Vector3(13, 0, -13), Vector3(-12, 0, 16), Vector3(12, 0, 16)]:
		_place("pillar_decorated", p, 0.0, true, 0.8)
	for p in [Vector3(-22, 0, -22), Vector3(22, 0, -22)]:
		_place("rubble_large", p, randf() * TAU)
	for p in [Vector3(-27, 0, 26), Vector3(27, 0, 26), Vector3(-26, 0, -27), Vector3(26.5, 0, -26)]:
		_place("barrel_large", p, randf() * TAU, true, 1.0)
	for p in [Vector3(-24, 0, 27), Vector3(24, 0, 27.5)]:
		_place("crates_stacked", p, randf() * TAU, true, 1.2)
	_place("sword_shield_gold", Vector3(0, 1.0, HALF - 0.6), PI)
	# Fackeln an den Wänden
	for x in [-20.0, -8.0, 8.0, 20.0]:
		_place("torch_mounted", Vector3(x, 2.4, -HALF + 0.6), 0.0)
		_place("torch_mounted", Vector3(x, 2.4, HALF - 0.6), PI)
	for z in [-20.0, 18.0]:
		_place("torch_mounted", Vector3(-HALF + 0.6, 2.4, z), PI * 0.5)
		_place("torch_mounted", Vector3(HALF - 0.6, 2.4, z), -PI * 0.5)
	for p in [Vector3(-14, 3, -HALF + 1.5), Vector3(14, 3, -HALF + 1.5), Vector3(-HALF + 1.5, 3, -6), Vector3(HALF - 1.5, 3, -6), Vector3(0, 3, HALF - 1.5)]:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.65, 0.35)
		light.light_energy = 1.6
		light.omni_range = 12.0
		light.position = p
		decor.add_child(light)
	# Banner neben den Toren
	for wall_pos in _gate_walls:
		# Mauerteile sind achsenparallel: die Richtung zur Mitte entlang der dominanten Achse
		var inward := _inward(wall_pos)
		inward = Vector3(signf(inward.x), 0, 0) if absf(inward.x) > absf(inward.z) else Vector3(0, 0, signf(inward.z))
		var side := inward.cross(Vector3.UP)
		var rot := atan2(inward.x, inward.z)
		for s in [-1.0, 1.0]:
			_place("banner_patternA_blue", wall_pos + side * s * 3.0 + inward * 0.5, rot)


func _place(model: String, pos: Vector3, rot_y: float, solid := false, radius := 0.8) -> Node3D:
	var path := ENV + (model if model.ends_with(".glb") else model + ".gltf.glb")
	if not _scene_cache.has(path):
		_scene_cache[path] = load(path) if ResourceLoader.exists(path) else null
	var scene: PackedScene = _scene_cache[path]
	if scene == null:
		push_warning("Deko-Modell fehlt: %s" % path)
		return null
	var inst: Node3D = scene.instantiate()
	inst.position = pos
	inst.rotation.y = rot_y
	decor.add_child(inst)
	if solid:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = radius
		cyl.height = 3.0
		shape.shape = cyl
		shape.position.y = 1.5
		body.add_child(shape)
		body.position = pos
		decor.add_child(body)
	return inst
