class_name CitadelMap
extends GameMap
## Zitadelle des Lichts (Issue #4) nach dem Konzeptbild des Spielers: im Westen der Abgrund mit drei Portalen, drei
## Lanes (die mittlere teilt sich um den Krater des Dschungelbosses), Fluss mit drei Brücken, Mauern und Türme,
## Kasernen, Händlerposten, Schreine, Ruinen und Lagerlichtungen im Dschungel, im Osten die Zitadelle auf einer
## Klippe über den Wolken. Grundriss in data/maps/citadel_layout.json in PIXELN des Konzeptbilds (1408 × 768),
## umgerechnet über px_origin/px_scale; Waldverteilung aus data/maps/citadel_forest.json (aus dem Bild gemessen).
## Gegnerwege: 0 Oben, 1 Mitte (abwechselnd Nord- und Südbogen), 2 Unten.

const ENV := "res://assets/models/environment/"
const CUSTOM := "res://assets/models/environment_custom/"
const GROUND_SHADER := preload("res://assets/effects/citadel_ground.gdshader")
const WATER_SHADER := preload("res://assets/effects/citadel_water.gdshader")
const PORTAL_SHADER := preload("res://assets/effects/citadel_portal.gdshader")
const CLIFF_SHADER := preload("res://assets/effects/citadel_cliff.gdshader")
const CLOUD_SHADER := preload("res://assets/effects/citadel_cloud.gdshader")
const FOREST_PATH := "res://data/maps/citadel_forest.json"
const IMAGE_SIZE := Vector2(1408, 768)   ## Konzeptbild in Pixeln (Bereich des Waldrasters)
const ENEMY_BARRIER_LAYER := 16          ## Kollisionsebene, die nur Gegner aufhält (Torhaus)
const BRIDGE_HALF_GAP := 4.0             ## so weit um eine Brücke herum ist der Fluss passierbar
const SCENERY_SEED := 4041               ## fester Zufall: Bäume und Felsen stehen in jeder Runde gleich
const MAX_ROAD_SEGS := 128               ## wie MAX_SEGS im Boden-Shader
const GATE_TOWER_OFFSET := 4.29          ## Abstand der Tortürme von der Tormitte (Lage im Bild)

var layout: Dictionary = {}
var lanes: Array[PackedVector3Array] = []      ## Hauptwege (Mitte über den Nordbogen)
var lane_variants: Dictionary = {}              ## Pfadnummer -> [Nordbogen, Südbogen]
var river: PackedVector2Array = PackedVector2Array()
var river_width := 5.0
var bridges: Array[Dictionary] = []             ## {pos: Vector3, dir: Vector3 (längs der Lane), lane: int}
var roads: Array[Dictionary] = []               ## {points: PackedVector2Array, width: float, kind: 0 Pflaster / 1 Erdpfad}
var walls: Array[PackedVector2Array] = []
var bounds_polygon := PackedVector2Array()      ## begehbarer Bereich
var plateau_polygon := PackedVector2Array()     ## Umriss der Insel (Boden und Felswand)
var citadel_polygon := PackedVector2Array()     ## Mauerring; letzte → erste Ecke = Torseite
var abyss_x := -53.0                            ## Grenze des Abgrunds (Welt-x)
var pit := Vector3(-5.3, 0.0, 7.5)              ## Krater: x, z, Radius
var structures: Array[MapStructure] = []        ## Wachtürme und Torhaus (Gegner greifen sie an, sie schießen zurück)
var shrines: Array[MapShrine] = []
var gatehouse: MapStructure
var _origin := Vector2(760, 397)
var _scale := 0.11
var _forest_rows: Array = []
var _forest_cell := 8
var _scene_cache: Dictionary = {}


func _ready() -> void:
	layout = _load_json(String(definition.get("layout", "res://data/maps/citadel_layout.json")))
	var o: Array = layout.get("px_origin", [760, 397])
	_origin = Vector2(float(o[0]), float(o[1]))
	_scale = float(layout.get("px_scale", 0.11))
	var forest := _load_json(FOREST_PATH)
	_forest_rows = forest.get("rows", [])
	_forest_cell = int(forest.get("cell", 8))
	_parse_layout()
	_find_bridges()
	_build_environment()
	_build_ground()
	_build_cliffs()
	_build_river()
	_build_bridges()
	_build_citadel()
	_build_gatehouse()
	_build_portals()
	_build_pads()
	_build_structures()
	_build_walls()
	_build_landmarks()
	_build_bounds()
	_build_scenery()
	_build_clouds()


func get_spawn_paths() -> Array[PackedVector3Array]:
	return lanes


func get_path_variants() -> Dictionary:
	return lane_variants


func hero_spawn_point(index := 0) -> Vector3:
	var pads: Array = layout.get("pads", [])
	if pads.is_empty():
		return citadel_center()
	return to_world3(pads[clampi(index, 0, pads.size() - 1)])


## Bauwerke an die Runde anschließen: Türme schießen über den CombatService, Gegner sehen sie über den Spawner.
func bind_match(m: Node) -> void:
	for s in structures:
		s.bind(m.combat, m.spawner, m)
		m.spawner.structures.append(s)
	for shrine in shrines:
		shrine.bind(m.heroes, m.vfx)


func camera_bounds() -> Rect2:
	var cb: Array = layout.get("camera_bounds", [[260, 110], [1300, 690]])
	var a := to_world(cb[0])
	var b := to_world(cb[1])
	return Rect2(a, b - a)


func minimap_extent() -> Rect2:
	return extent()


## Begehbarer Bereich als Rechteck (Hülle der Kartengrenze).
func extent() -> Rect2:
	var r := Rect2(bounds_polygon[0], Vector2.ZERO)
	for p in bounds_polygon:
		r = r.expand(p)
	return r


func citadel_center() -> Vector3:
	return to_world3(layout.citadel.core)


## Pixel des Konzeptbilds → Welt (x/z in Metern).
func to_world(px_point: Variant) -> Vector2:
	return (Vector2(float(px_point[0]), float(px_point[1])) - _origin) * _scale


func to_world3(px_point: Variant) -> Vector3:
	var p := to_world(px_point)
	return Vector3(p.x, 0.0, p.y)


## Welt (x/z) → Pixel des Konzeptbilds.
func to_px(p: Vector2) -> Vector2:
	return p / _scale + _origin


## Wald laut Konzeptbild an einer Weltstelle: 0 frei, 1 Wald, 2 dichter Wald, -1 außerhalb des Bildes.
func forest_at(p: Vector2) -> int:
	var q := to_px(p)
	if q.x < 0.0 or q.y < 0.0 or q.x >= IMAGE_SIZE.x or q.y >= IMAGE_SIZE.y or _forest_rows.is_empty():
		return -1
	var row: String = _forest_rows[clampi(int(q.y) / _forest_cell, 0, _forest_rows.size() - 1)]
	var col := clampi(int(q.x) / _forest_cell, 0, row.length() - 1)
	return int(row[col])


# --- Grundriss ------------------------------------------------------------------------------------------

func _load_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	push_error("Datei nicht lesbar: %s" % path)
	return {}


func _px_list(list: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in list:
		out.append(to_world(p))
	return out


func _parse_layout() -> void:
	var ring: Dictionary = layout.get("ring", {})
	var lane_width := float(layout.get("lane_width", 5.5))
	for lane in layout.get("lanes", []):
		var main := PackedVector3Array()
		var alt := PackedVector3Array()
		var before := PackedVector2Array()
		var after := PackedVector2Array()
		var has_ring := false
		for p in lane.points:
			if p is String:   # "RING": hier läuft der Weg um den Krater, Hauptweg Nord, Variante Süd
				has_ring = true
				for q in _ring_arc(ring, true):
					main.append(Vector3(q.x, 0.0, q.y))
				for q in _ring_arc(ring, false):
					alt.append(Vector3(q.x, 0.0, q.y))
				continue
			var w := to_world(p)
			main.append(Vector3(w.x, 0.0, w.y))
			alt.append(Vector3(w.x, 0.0, w.y))
			if has_ring:
				after.append(w)
			else:
				before.append(w)
		lanes.append(main)
		roads.append({"points": before, "width": lane_width, "kind": 0})
		if has_ring:
			lane_variants[lanes.size() - 1] = [main, alt]
			roads.append({"points": after, "width": lane_width, "kind": 0})
	if not ring.is_empty():
		var loop := PackedVector2Array()
		for i in 33:
			var a := TAU * i / 32.0
			loop.append(to_world([float(ring.center[0]) + float(ring.rx) * cos(a), float(ring.center[1]) + float(ring.rz) * sin(a)]))
		roads.append({"points": loop, "width": float(ring.get("width", 4.5)), "kind": 0})
	for t in layout.get("trails", []):
		roads.append({"points": _px_list(t), "width": float(layout.get("trail_width", 2.8)), "kind": 1})
	var rv: Dictionary = layout.get("river", {})
	river = _px_list(rv.get("points", []))
	river_width = float(rv.get("width", 5.0))
	for w in layout.get("walls", []):
		walls.append(_px_list(w))
	bounds_polygon = _px_list(layout.get("bounds", [[205, 70], [1368, 70], [1368, 735], [205, 735]]))
	plateau_polygon = _px_list(layout.get("plateau", [[-400, -250], [1500, -250], [1500, 1000], [-400, 1000]]))
	citadel_polygon = _px_list(layout.citadel.polygon)
	abyss_x = to_world([float(layout.get("abyss_x", 272)), 0]).x
	var pt: Array = layout.get("pit", [708, 397, 7.5])
	var pc := to_world(pt)
	pit = Vector3(pc.x, pc.y, float(pt[2]))


## Zwischenpunkte des Nord- oder Südbogens der Ringstraße, ohne die beiden Abzweigungen (Welt-x/z).
func _ring_arc(ring: Dictionary, north: bool, steps := 8) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(1, steps):
		var a := PI * (1.0 - float(i) / steps)   # 180° (Westen) → 0° (Osten)
		var py := float(ring.center[1]) + (-1.0 if north else 1.0) * float(ring.rz) * sin(a)
		out.append(to_world([float(ring.center[0]) + float(ring.rx) * cos(a), py]))
	return out


## Brücken: Schnittpunkte jeder Lane mit dem Fluss.
func _find_bridges() -> void:
	for li in lanes.size():
		var pts := lanes[li]
		for i in pts.size() - 1:
			var a := Vector2(pts[i].x, pts[i].z)
			var b := Vector2(pts[i + 1].x, pts[i + 1].z)
			for j in river.size() - 1:
				var hit: Variant = Geometry2D.segment_intersects_segment(a, b, river[j], river[j + 1])
				if hit != null and not _has_bridge_near(hit, li):   # Wegpunkt genau auf dem Fluss: nur eine Brücke
					var dir := (b - a).normalized()
					bridges.append({"pos": Vector3(hit.x, 0.0, hit.y), "dir": Vector3(dir.x, 0.0, dir.y), "lane": li})


func _has_bridge_near(p: Vector2, lane: int) -> bool:
	for br in bridges:
		if br.lane == lane and Vector2(br.pos.x, br.pos.z).distance_to(p) < 3.0:
			return true
	return false


# --- Aufbau ---------------------------------------------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.72, 0.9)   # Himmel unter der Klippe
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.78, 0.88)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)


## Boden: das Plateau als Vieleck mit dem Boden-Shader; darunter ein großer Kollisionsboden.
func _build_ground() -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "Ground"
	mesh.mesh = _flat_polygon_mesh(plateau_polygon)
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	var segs := PackedVector4Array()
	var info := PackedVector2Array()
	for r in roads:
		var pts: PackedVector2Array = r.points
		for i in pts.size() - 1:
			if segs.size() >= MAX_ROAD_SEGS:
				push_warning("Zu viele Straßenstücke für den Boden-Shader")
				break
			segs.append(Vector4(pts[i].x, pts[i].y, pts[i + 1].x, pts[i + 1].y))
			info.append(Vector2(float(r.width) * 0.5, float(r.kind)))
	mat.set_shader_parameter("segs", segs)
	mat.set_shader_parameter("seg_info", info)
	mat.set_shader_parameter("seg_count", segs.size())
	mat.set_shader_parameter("river_points", river)
	mat.set_shader_parameter("river_count", river.size())
	mat.set_shader_parameter("river_width", river_width)
	var plaza := citadel_polygon.duplicate()
	if _signed_area(plaza) < 0.0:
		plaza.reverse()   # Shader erwartet die Reihenfolge, bei der (e.y, -e.x) nach außen zeigt
	mat.set_shader_parameter("plaza", plaza)
	mat.set_shader_parameter("plaza_count", plaza.size())
	mat.set_shader_parameter("abyss_x", abyss_x)
	mat.set_shader_parameter("pit", pit)
	var clear := PackedVector4Array()
	for spec in [["camps", 6.5], ["ruins", 5.5], ["towers", 3.0], ["shrines", 2.8], ["barracks", 6.0]]:
		for q in layout.get(spec[0], []):
			var w := to_world(q)
			clear.append(Vector4(w.x, w.y, spec[1], 0))
	if layout.has("shop"):
		var w := to_world(layout.shop)
		clear.append(Vector4(w.x, w.y, 5.5, 0))
	mat.set_shader_parameter("clearings", clear)
	mat.set_shader_parameter("clearing_count", clear.size())
	var lava := PackedVector3Array()
	for l in layout.get("lava", []):
		var w := to_world(l)
		lava.append(Vector3(w.x, w.y, float(l[2])))
	mat.set_shader_parameter("lava", lava)
	mat.set_shader_parameter("lava_count", lava.size())
	mat.set_shader_parameter("forest_map", _forest_texture())
	var corner := to_world([0, 0])
	mat.set_shader_parameter("forest_rect", Vector4(corner.x, corner.y, IMAGE_SIZE.x * _scale, IMAGE_SIZE.y * _scale))
	mesh.material_override = mat
	add_child(mesh)
	var body := StaticBody3D.new()
	body.name = "Floor"
	var r := Rect2(plateau_polygon[0], Vector2.ZERO)
	for p in plateau_polygon:
		r = r.expand(p)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(r.size.x, 1.0, r.size.y)
	shape.shape = box
	shape.position = Vector3(r.get_center().x, -0.5, r.get_center().y)
	body.add_child(shape)
	add_child(body)


func _forest_texture() -> ImageTexture:
	var h := maxi(1, _forest_rows.size())
	var w := maxi(1, String(_forest_rows[0]).length() if not _forest_rows.is_empty() else 1)
	var img := Image.create(w, h, false, Image.FORMAT_L8)
	for y in _forest_rows.size():
		var row: String = _forest_rows[y]
		for x in row.length():
			img.set_pixel(x, y, Color.from_hsv(0, 0, [0.0, 0.6, 1.0][clampi(int(row[x]), 0, 2)]))
	return ImageTexture.create_from_image(img)


## Waagerechtes Vieleck (y = 0) als Fläche; Dreiecke so gedreht, dass sie nach oben zeigen.
func _flat_polygon_mesh(poly: PackedVector2Array) -> ArrayMesh:
	var tris := Geometry2D.triangulate_polygon(poly)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0, tris.size(), 3):
		var a := Vector3(poly[tris[i]].x, 0, poly[tris[i]].y)
		var b := Vector3(poly[tris[i + 1]].x, 0, poly[tris[i + 1]].y)
		var c := Vector3(poly[tris[i + 2]].x, 0, poly[tris[i + 2]].y)
		_add_triangle(st, a, b, c, Vector3.UP)
	return st.commit()


## Dreieck mit Blickseite in Richtung `facing` (Godot: Vorderseite im Uhrzeigersinn).
func _add_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, facing: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.dot(facing) > 0.0:
		var t := b
		b = c
		c = t
		n = -n
	st.set_normal(-n.normalized())
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


func _signed_area(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5


## Felswand unter dem Plateau: nach unten eingezogene Ringe mit zufälligem Versatz (schwebende Insel).
func _build_cliffs() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SCENERY_SEED + 7
	var orient := 1.0 if _signed_area(plateau_polygon) > 0.0 else -1.0
	var ring := PackedVector2Array()
	var inward := PackedVector2Array()
	var count := plateau_polygon.size()
	for i in count:
		var a := plateau_polygon[i]
		var b := plateau_polygon[(i + 1) % count]
		var e := (b - a).normalized()
		var into := Vector2(-e.y, e.x) * orient
		var steps := maxi(1, int(a.distance_to(b) / 4.0))
		for k in steps:
			ring.append(a.lerp(b, float(k) / steps))
			inward.append(into)
	var levels := [[0.05, 0.0, 0.0], [-5.0, 1.5, 1.0], [-14.0, 6.0, 2.5], [-26.0, 14.0, 3.5], [-40.0, 26.0, 4.0]]
	var rows: Array = []
	for lv in levels:
		var row := PackedVector3Array()
		for i in ring.size():
			var jitter := rng.randf_range(-1.0, 1.0) * float(lv[2])
			var p: Vector2 = ring[i] + inward[i] * (float(lv[1]) + absf(jitter))
			row.append(Vector3(p.x, float(lv[0]) + rng.randf_range(-0.6, 0.6) * float(lv[2]), p.y))
		rows.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for l in rows.size() - 1:
		var top: PackedVector3Array = rows[l]
		var bot: PackedVector3Array = rows[l + 1]
		for i in ring.size():
			var j := (i + 1) % ring.size()
			var out := Vector3(-inward[i].x, 0.0, -inward[i].y)
			_add_triangle(st, top[i], top[j], bot[i], out)
			_add_triangle(st, top[j], bot[j], bot[i], out)
	var mesh := MeshInstance3D.new()
	mesh.name = "Cliffs"
	mesh.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = CLIFF_SHADER
	mesh.material_override = mat
	add_child(mesh)


## Fluss als Band entlang einer geglätteten Linie; Wasser blockiert Laufen, außer an den Brücken.
func _build_river() -> void:
	var smooth := _smooth_polyline(river, 6)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := 0.0
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	for i in smooth.size():
		var p := smooth[i]
		var t := (smooth[mini(i + 1, smooth.size() - 1)] - smooth[maxi(i - 1, 0)]).normalized()
		var side := Vector2(-t.y, t.x) * river_width * 0.5
		var l := Vector3(p.x - side.x, 0.04, p.y - side.y)
		var r := Vector3(p.x + side.x, 0.04, p.y + side.y)
		if i > 0:
			along += (p - smooth[i - 1]).length()
			var v0 := along - (p - smooth[i - 1]).length()
			for tri in [[prev_l, Vector2(0, v0)], [prev_r, Vector2(1, v0)], [r, Vector2(1, along)],
					[prev_l, Vector2(0, v0)], [r, Vector2(1, along)], [l, Vector2(0, along)]]:
				st.set_uv(tri[1])
				st.set_normal(Vector3.UP)
				st.add_vertex(tri[0])
		prev_l = l
		prev_r = r
	var water := MeshInstance3D.new()
	water.name = "River"
	water.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	water.material_override = mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	# Sperre: Kästen entlang des Flusses, an Brücken ausgespart
	var body := StaticBody3D.new()
	body.name = "RiverBlock"
	for i in smooth.size() - 1:
		var a := smooth[i]
		var b := smooth[i + 1]
		var mid := (a + b) * 0.5
		var near_bridge := false
		for br in bridges:
			if Vector2(br.pos.x, br.pos.z).distance_to(mid) < BRIDGE_HALF_GAP:
				near_bridge = true
		if near_bridge:
			continue
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(river_width - 1.0, 2.0, (b - a).length() + 0.3)
		shape.shape = box
		shape.position = Vector3(mid.x, 1.0, mid.y)
		shape.rotation.y = atan2(b.x - a.x, b.y - a.y)
		body.add_child(shape)
	add_child(body)


func _build_bridges() -> void:
	var lane_width := float(layout.get("lane_width", 5.5))
	for br in bridges:
		var model := _place_custom("Bridge", br.pos, atan2(br.dir.x, br.dir.z))
		if model != null:
			model.scale = Vector3((lane_width + 2.0) / 8.0, 1.0, 1.0)   # Modell ist 8 m breit


## Mauerring nach dem Bild: Sechseck mit vier Ecktürmen; die Torseite (letzte → erste Ecke) bleibt fürs Torhaus frei.
func _build_citadel() -> void:
	var body := StaticBody3D.new()
	body.name = "CitadelWalls"
	add_child(body)
	var c := citadel_center()
	var count := citadel_polygon.size()
	for k in count - 1:
		var p0 := Vector3(citadel_polygon[k].x, 0, citadel_polygon[k].y)
		var p1 := Vector3(citadel_polygon[k + 1].x, 0, citadel_polygon[k + 1].y)
		var mid := (p0 + p1) * 0.5
		var inward := (c - mid).normalized()
		var rot := atan2(inward.x, inward.z)
		var length := p0.distance_to(p1)
		var pieces := maxi(1, ceili(length / 4.0))
		for s in pieces:
			var at := p0.lerp(p1, (s + 0.5) / pieces)
			var piece := _place_custom("CitadelWall", at, rot)
			if piece != null:
				piece.scale = Vector3(length / pieces / 4.0, 1.0, 1.0)   # Modell: 4 m lang
			else:
				piece = _place(ENV + "wall.gltf.glb", at, rot)
				piece.scale = Vector3(length / pieces / 4.0, 1.6, 1.3)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(length, 4.0, 1.4)
		shape.shape = box
		shape.position = mid + Vector3(0, 2.0, 0)
		shape.rotation.y = rot
		body.add_child(shape)
	for t in layout.citadel.get("corner_towers", []):
		_place_custom("CitadelTower", to_world3(t), 0.0, true, 1.8)


## Torhaus zwischen den beiden Tortürmen: die Türme blockieren alle, die Toröffnung nur Gegner (eigene Ebene).
func _build_gatehouse() -> void:
	var g: Array = layout.citadel.get("gate", [])
	if g.size() != 2:
		return
	var a := to_world3(g[0])
	var b := to_world3(g[1])
	var mid := (a + b) * 0.5
	var outward := (mid - citadel_center()).normalized()
	var rot := atan2(outward.x, outward.z)
	var barrier := BoxShape3D.new()
	barrier.size = Vector3(5.4, 4.0, 1.6)
	gatehouse = _add_structure("gate", "Gatehouse", mid, rot, barrier, Vector3(0, 2.0, 0))
	gatehouse.collision_layer = ENEMY_BARRIER_LAYER
	gatehouse.half_length = GATE_TOWER_OFFSET + 1.6
	gatehouse.radius = 1.6
	var body := StaticBody3D.new()
	body.name = "GateTowers"
	for p in [a, b]:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(3.2, 6.0, 3.2)
		shape.shape = box
		shape.position = p + Vector3(0, 3.0, 0)
		shape.rotation.y = rot
		body.add_child(shape)
	add_child(body)


func _build_portals() -> void:
	for i in lanes.size():
		var p := lanes[i][0]
		var toward := (lanes[i][1] - p).normalized()
		var rot := atan2(toward.x, toward.z)
		var color := Color.html(String(layout.lanes[i].get("color", "#9a4dff")))
		_place_custom("Portal", p - toward * 1.0, rot)
		var swirl := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(5.4, 5.4)
		swirl.mesh = quad
		var mat := ShaderMaterial.new()
		mat.shader = PORTAL_SHADER
		mat.set_shader_parameter("tint", color)
		swirl.material_override = mat
		swirl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		swirl.position = p - toward * 1.0 + Vector3(0, 3.2, 0)
		swirl.rotation.y = rot
		add_child(swirl)
		var light := OmniLight3D.new()
		light.light_color = color
		light.light_energy = 2.4
		light.omni_range = 10.0
		light.position = p + Vector3(0, 2.5, 0)
		add_child(light)


## Start-Plattformen der Helden (die ersten vier) und weitere Markierungen wie im Bild.
func _build_pads() -> void:
	for q in layout.get("pads", []) + layout.get("pad_markers", []):
		_place_custom("HeroPad", to_world3(q), 0.0)


## Türme, Schreine, Händlerposten, Kasernen und Ruinen an den Stellen aus dem Bild.
func _build_structures() -> void:
	for t in layout.get("towers", []):
		var pos := to_world3(t)
		var cyl := CylinderShape3D.new()
		cyl.radius = 1.4
		cyl.height = 5.0
		_add_structure("tower", "GuardTower", pos, _facing_road(pos), cyl, Vector3(0, 2.5, 0))
	for s in layout.get("shrines", []):
		var pos := to_world3(s)
		var shrine := MapShrine.new()
		shrine.name = "Shrine%d" % shrines.size()
		shrine.position = pos
		shrine.rotation.y = _facing_road(pos)
		add_child(shrine)
		shrine.setup(_structure_config("shrine"), _model_scene("Shrine"))
		shrines.append(shrine)
	if layout.has("shop"):
		var pos := to_world3(layout.shop)
		var rot := _facing_road(pos)
		if _place_custom("ShopHouse", pos, rot) != null:
			_block("ShopBlock", pos, rot, Vector3(5.6, 3.0, 4.2))
	for b in layout.get("barracks", []):
		var pos := to_world3(b)
		var rot := _facing_road(pos)
		if _place_custom("Barracks", pos, rot) != null:
			_block("BarracksBlock", pos, rot, Vector3(7.6, 3.5, 5.2))
	for r in layout.get("ruins", []):
		_place_custom("Ruins", to_world3(r), _facing_road(to_world3(r)))


func _block(block_name: String, pos: Vector3, rot: float, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = block_name
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = pos + Vector3(0, size.y * 0.5, 0)
	shape.rotation.y = rot
	body.add_child(shape)
	add_child(body)


## Bauwerk mit Leben und Angriff (Wachturm, Torhaus); Werte aus map_structures in game.json.
func _add_structure(kind: String, model_name: String, pos: Vector3, rot_y: float, shape: Shape3D, offset: Vector3) -> MapStructure:
	var s := MapStructure.new()
	s.name = "%s%d" % [kind.capitalize(), structures.size()]
	s.position = pos
	s.rotation.y = rot_y
	s.collision_mask = 0
	add_child(s)
	s.setup(kind, _structure_config(kind), _model_scene(model_name), shape, offset)
	structures.append(s)
	return s


func _structure_config(kind: String) -> Dictionary:
	return GameData.balance.get("map_structures", {}).get(kind, {})


## Drehung, mit der die Vorderseite eines Modells (+Z) zur nächsten gepflasterten Straße zeigt.
func _facing_road(pos: Vector3) -> float:
	var p := Vector2(pos.x, pos.z)
	var best := p + Vector2(0, 1)
	var best_d := INF
	for r in roads:
		if r.kind != 0:
			continue
		var pts: PackedVector2Array = r.points
		for i in pts.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])
			if p.distance_to(q) < best_d:
				best_d = p.distance_to(q)
				best = q
	var dir := best - p
	return atan2(dir.x, dir.y)


## Steinmauern aus dem Bild (Wall an der oberen Lane, Mauern östlich des Flusses …) mit Kollision.
func _build_walls() -> void:
	var body := StaticBody3D.new()
	body.name = "Walls"
	add_child(body)
	for line in walls:
		for i in line.size() - 1:
			var a := Vector3(line[i].x, 0, line[i].y)
			var b := Vector3(line[i + 1].x, 0, line[i + 1].y)
			var length := a.distance_to(b)
			var rot := atan2(b.x - a.x, b.z - a.z) + PI * 0.5   # Modell liegt längs X
			var pieces := maxi(1, roundi(length / 3.5))
			for s in pieces:
				var piece := _place_custom("StoneWall", a.lerp(b, (s + 0.5) / pieces), rot)
				if piece != null:
					piece.scale = Vector3(length / pieces / 3.5, 1.0, 1.0)   # Modell: 3,5 m lang
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(length + 0.4, 2.0, 1.0)
			shape.shape = box
			shape.position = (a + b) * 0.5 + Vector3(0, 1.0, 0)
			shape.rotation.y = rot
			body.add_child(shape)


## Kraterrand, Felsen und Kristalle im Abgrund, Berge im Norden, Felsen an der Klippe.
func _build_landmarks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SCENERY_SEED + 3
	var groups := {}
	for i in 18:   # Felsen rund um den Krater
		var a := TAU * i / 18.0 + rng.randf_range(-0.08, 0.08)
		var p := Vector2(pit.x, pit.y) + Vector2(cos(a), sin(a)) * (pit.z + rng.randf_range(0.2, 0.9))
		var s := rng.randf_range(0.7, 1.15)
		_add_xform(groups, "Rock", p, rng.randf_range(0.0, TAU), Vector3(s, s * 0.8, s))
	var body := StaticBody3D.new()
	body.name = "Landmarks"
	add_child(body)
	for q in layout.get("abyss_rocks", []):
		var p := to_world(q)
		var s := rng.randf_range(1.0, 1.5)
		_add_xform(groups, "AbyssRock", p, rng.randf_range(0.0, TAU), Vector3.ONE * s)
		_add_cylinder(body, p, 2.0 * s)
	for q in layout.get("void_crystals", []):
		var p := to_world(q)
		_add_xform(groups, "VoidCrystals", p, rng.randf_range(0.0, TAU), Vector3.ONE * rng.randf_range(1.2, 1.6))
		_add_cylinder(body, p, 1.6)
	for q in layout.get("mountains", []):
		var s := rng.randf_range(1.0, 1.4)
		_add_xform(groups, "Mountain", to_world(q), rng.randf_range(0.0, TAU), Vector3(s, s * rng.randf_range(0.9, 1.2), s))
	for q in layout.get("edge_rocks", []):
		var s := rng.randf_range(1.1, 1.5)
		_add_xform(groups, "Cliff", to_world(q), rng.randf_range(0.0, TAU), Vector3.ONE * s)
	for model in groups:
		_scatter(model, groups[model])


func _add_cylinder(body: StaticBody3D, p: Vector2, radius: float) -> void:
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = 3.0
	shape.shape = cyl
	shape.position = Vector3(p.x, 1.5, p.y)
	body.add_child(shape)


## Unsichtbare Grenze entlang des begehbaren Bereichs (Berge, Abgrund und Klippe sind nur Kulisse).
func _build_bounds() -> void:
	var body := StaticBody3D.new()
	body.name = "MapBounds"
	var count := bounds_polygon.size()
	for i in count:
		var a := bounds_polygon[i]
		var b := bounds_polygon[(i + 1) % count]
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(a.distance_to(b) + 1.0, 4.0, 1.0)
		shape.shape = box
		shape.position = Vector3((a.x + b.x) * 0.5, 2.0, (a.y + b.y) * 0.5)
		shape.rotation.y = atan2(b.x - a.x, b.y - a.y) + PI * 0.5
		body.add_child(shape)
	add_child(body)


## Natur nach dem Waldraster des Konzeptbilds: dichte Wälder im Norden, Süden und im Dschungel, einzelne Bäume
## auf den Wiesen, im Abgrund tote Bäume und Glutkristalle. Wege, Fluss, Bauten, Lager und Zitadelle bleiben frei.
## Fester Zufall, gezeichnet als MultiMesh je Modellteil; im begehbaren Bereich mit Kollision.
func _build_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SCENERY_SEED
	var noise := FastNoiseLite.new()
	noise.seed = SCENERY_SEED
	noise.frequency = 0.05
	var inner: PackedVector2Array = plateau_polygon
	var shrunk := Geometry2D.offset_polygon(plateau_polygon, -3.0)
	if not shrunk.is_empty():
		inner = shrunk[0]
	var area := Rect2(to_world([0, 0]), IMAGE_SIZE * _scale).grow(14.0)
	var groups := {}
	var solid: Array = []   ## [Vector2 Mitte, Radius] – Hindernisse im begehbaren Bereich
	var step := 2.4
	var x := area.position.x
	while x < area.end.x:
		var z := area.position.y
		while z < area.end.y:
			var p := Vector2(x + rng.randf_range(-1.2, 1.2), z + rng.randf_range(-1.2, 1.2))
			z += step
			var roll := rng.randf()
			var pick := rng.randf()
			var s := rng.randf_range(1.05, 1.6)
			if not Geometry2D.is_point_in_polygon(p, inner) or not _scenery_free(p):
				continue
			var walkable := Geometry2D.is_point_in_polygon(p, bounds_polygon)
			var in_abyss := p.x < abyss_x + noise.get_noise_2d(p.y, p.x) * 6.0
			var f := forest_at(p)
			var density: float
			if in_abyss:
				density = 0.14
			elif f < 0:
				density = 0.85
			else:
				density = [0.03, 0.88, 0.97][f]
			if not walkable and not in_abyss:
				density = maxf(density, 0.6)   # hinter der Grenze: geschlossener Wald als Kulisse
			if roll > density:
				continue
			var model: String
			if in_abyss:
				model = "TreeDead" if pick < 0.5 else ("Rock" if pick < 0.85 else "AbyssSpikes")
			elif f == 2 or f < 0:
				model = "TreePine" if pick < 0.7 else ("TreeOak" if pick < 0.97 else "Rock")
			else:
				model = "TreeOak" if pick < 0.55 else ("TreePine" if pick < 0.94 else "Rock")
			_add_xform(groups, model, p, rng.randf_range(0.0, TAU), Vector3.ONE * s)
			if walkable:
				solid.append([p, (1.0 if model == "Rock" else 0.5) * s])
		x += step
	for model in groups:
		_scatter(model, groups[model])
	if solid.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = "SceneryBlock"
	for entry in solid:
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = entry[1]
		cyl.height = 3.0
		shape.shape = cyl
		shape.position = Vector3(entry[0].x, 1.5, entry[0].y)
		body.add_child(shape)
	add_child(body)


## Frei für Natur: nicht auf/an Straßen, Pfaden, Fluss, Mauern, Bauten, Lagern, Krater, Portalen und der Zitadelle.
func _scenery_free(p: Vector2) -> bool:
	for r in roads:
		var pts: PackedVector2Array = r.points
		var margin := float(r.width) * 0.5 + (2.2 if r.kind == 0 else 0.7)
		for i in pts.size() - 1:
			if Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1]).distance_to(p) < margin:
				return false
	for i in river.size() - 1:
		if Geometry2D.get_closest_point_to_segment(p, river[i], river[i + 1]).distance_to(p) < river_width * 0.5 + 1.8:
			return false
	for line in walls:
		for i in line.size() - 1:
			if Geometry2D.get_closest_point_to_segment(p, line[i], line[i + 1]).distance_to(p) < 1.8:
				return false
	var c := citadel_center()
	if Geometry2D.is_point_in_polygon(p, citadel_polygon) or p.distance_to(Vector2(c.x, c.y)) < 16.0:
		return false
	if p.distance_to(Vector2(pit.x, pit.y)) < pit.z + 2.5:
		return false
	for lane in lanes:
		if p.distance_to(Vector2(lane[0].x, lane[0].z)) < 8.0:
			return false
	for br in bridges:
		if p.distance_to(Vector2(br.pos.x, br.pos.z)) < 6.0:
			return false
	var spots := [["towers", 4.0], ["shrines", 3.4], ["camps", 5.6], ["ruins", 4.6], ["barracks", 6.5], ["pads", 2.6],
		["pad_markers", 2.6], ["abyss_rocks", 3.5], ["void_crystals", 3.0], ["mountains", 7.0], ["edge_rocks", 4.0]]
	for spec in spots:
		for q in layout.get(spec[0], []):
			if p.distance_to(to_world(q)) < spec[1]:
				return false
	if layout.has("shop") and p.distance_to(to_world(layout.shop)) < 6.5:
		return false
	return true


func _add_xform(groups: Dictionary, model: String, p: Vector2, rot_y: float, scale: Vector3) -> void:
	if not groups.has(model):
		groups[model] = []
	groups[model].append(Transform3D(Basis(Vector3.UP, rot_y).scaled(scale), Vector3(p.x, 0.0, p.y)))


## Viele Kopien eines Modells als MultiMesh (ein Zeichenaufruf je Modellteil statt je Kopie).
func _scatter(model_name: String, xforms: Array) -> void:
	var scene := _model_scene(model_name)
	if xforms.is_empty() or scene == null:
		return
	var root: Node3D = scene.instantiate()
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var local := Transform3D.IDENTITY
		var n: Node = mi
		while n != root:
			local = (n as Node3D).transform * local
			n = n.get_parent()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = (mi as MeshInstance3D).mesh
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i] * local)
		var inst := MultiMeshInstance3D.new()
		inst.name = "%s_%s" % [model_name, mi.name]
		inst.multimesh = mm
		add_child(inst)
	root.free()


## Wolkenfelder unter der Klippe im Osten (wie im Konzeptbild).
func _build_clouds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SCENERY_SEED + 11
	var orient := 1.0 if _signed_area(plateau_polygon) > 0.0 else -1.0
	var count := plateau_polygon.size()
	for i in count:
		var a := plateau_polygon[i]
		var b := plateau_polygon[(i + 1) % count]
		if (a.x + b.x) * 0.5 < 25.0:
			continue   # nur an der Ostkante, wo der Himmel zu sehen ist
		var e := (b - a).normalized()
		var out := Vector2(e.y, -e.x) * orient
		var steps := maxi(1, int(a.distance_to(b) / 9.0))
		for k in steps:
			var p := a.lerp(b, (k + rng.randf()) / steps) + out * rng.randf_range(4.0, 26.0)
			var cloud := MeshInstance3D.new()
			var plane := PlaneMesh.new()
			var size := rng.randf_range(16.0, 32.0)
			plane.size = Vector2(size, size * rng.randf_range(0.5, 0.8))
			cloud.mesh = plane
			var mat := ShaderMaterial.new()
			mat.shader = CLOUD_SHADER
			mat.set_shader_parameter("seed", rng.randf_range(0.0, 50.0))
			cloud.material_override = mat
			cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			cloud.position = Vector3(p.x, rng.randf_range(-22.0, -7.0), p.y)
			cloud.rotation.y = rng.randf_range(0.0, TAU)
			add_child(cloud)


# --- Hilfen --------------------------------------------------------------------------------------------

func _smooth_polyline(points: PackedVector2Array, steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in points.size() - 1:
		var p0 := points[maxi(i - 1, 0)]
		var p1 := points[i]
		var p2 := points[i + 1]
		var p3 := points[mini(i + 2, points.size() - 1)]
		for s in steps:
			var t := float(s) / steps
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(points[points.size() - 1])
	return out


func _model_scene(model_name: String) -> PackedScene:
	var path := CUSTOM + model_name + ".glb"
	if not ResourceLoader.exists(path):
		return null
	if not _scene_cache.has(path):
		_scene_cache[path] = load(path)
	return _scene_cache[path]


## Eigenes Blender-Modell (assets/models/environment_custom/<name>.glb) setzen; null, wenn es (noch) fehlt.
func _place_custom(model_name: String, pos: Vector3, rot_y: float, solid := false, radius := 1.0) -> Node3D:
	var path := CUSTOM + model_name + ".glb"
	if not ResourceLoader.exists(path):
		return null
	var inst := _place(path, pos, rot_y)
	if solid:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = radius
		cyl.height = 3.0
		shape.shape = cyl
		shape.position = pos + Vector3(0, 1.5, 0)
		body.add_child(shape)
		add_child(body)
	return inst


func _place(path: String, pos: Vector3, rot_y: float) -> Node3D:
	if not _scene_cache.has(path):
		_scene_cache[path] = load(path)
	var inst: Node3D = (_scene_cache[path] as PackedScene).instantiate()
	inst.position = pos
	inst.rotation.y = rot_y
	add_child(inst)
	return inst
