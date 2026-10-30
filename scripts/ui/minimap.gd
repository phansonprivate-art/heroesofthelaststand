class_name Minimap
extends Control
## Minimap oben rechts: Grundriss der Karte (Gegnerwege, Fluss, Zitadelle), Bauwerke, Kern und Brunnen,
## Helden und Gegner als Punkte, dazu der Kamerausschnitt. Linksklick/Ziehen schwenkt die Kamera dorthin
## (löst sie vom Helden; Leertaste zentriert wieder). Darüber die Spieluhr der Runde.

const MAX_WIDTH := 300.0
const MAX_HEIGHT := 210.0
const GROUND := Color(0.2, 0.3, 0.16)
const ABYSS := Color(0.17, 0.11, 0.12)
const LANE := Color(0.55, 0.52, 0.46)
const TRAIL := Color(0.42, 0.33, 0.21)
const SKY := Color(0.42, 0.58, 0.76)
const WATER := Color(0.2, 0.42, 0.62)
const WALL := Color(0.82, 0.8, 0.74)
const FRIEND := Color(0.45, 0.8, 1.0)
const FOE := Color(0.95, 0.3, 0.25)
const DOWN := Color(0.4, 0.4, 0.42)

var _match: MatchController
var _extent := Rect2(-26, -26, 52, 52)
var _clock: Label
var _dragging := false


func bind(m: MatchController) -> void:
	_match = m
	_extent = m.arena.minimap_extent()
	var w := MAX_WIDTH
	var h := w * _extent.size.y / _extent.size.x
	if h > MAX_HEIGHT:
		h = MAX_HEIGHT
		w = h * _extent.size.x / _extent.size.y
	custom_minimum_size = Vector2(w, h)
	size = custom_minimum_size
	UiTheme.place(self, Control.PRESET_TOP_RIGHT, -18 - w, 58, -18, 58 + h, Control.GROW_DIRECTION_BEGIN)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_clock = UiTheme.label("00:00", 18, UiTheme.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	_clock.add_theme_constant_override("outline_size", 6)
	_clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.place(_clock, Control.PRESET_TOP_RIGHT, -18 - w, 30, -18, 54, Control.GROW_DIRECTION_BEGIN)
	get_parent().add_child.call_deferred(_clock)


## Spieluhr als mm:ss (ab einer Stunde h:mm:ss).
static func format_clock(seconds: float) -> String:
	var s := int(seconds)
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
	return "%02d:%02d" % [s / 60, s % 60]


func _process(_delta: float) -> void:
	if _match == null:
		return
	_clock.text = format_clock(_match.elapsed)
	queue_redraw()


func to_map(world: Vector3) -> Vector2:
	return (Vector2(world.x, world.z) - _extent.position) / _extent.size * size


func to_world(local: Vector2) -> Vector3:
	var p := _extent.position + local / size * _extent.size
	return Vector3(p.x, 0.0, p.y)


func _gui_input(event: InputEvent) -> void:
	if _match == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			_match.camera_rig.jump_to(to_world(event.position))
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_match.camera_rig.jump_to(to_world(event.position.clamp(Vector2.ZERO, size)))
		accept_event()


func _draw() -> void:
	if _match == null:
		return
	var rect := Rect2(Vector2.ZERO, size)
	var map := _match.arena
	var citadel := map as CitadelMap
	var px := size.x / _extent.size.x   # Pixel je Meter
	if citadel != null:
		draw_rect(rect, SKY)
		draw_colored_polygon(_map_points(citadel.plateau_polygon), GROUND)
		draw_rect(Rect2(0, 0, clampf(to_map(Vector3(citadel.abyss_x, 0, 0)).x, 0.0, size.x), size.y), ABYSS)
		if citadel.river.size() > 1:
			draw_polyline(_map_points(citadel.river), WATER, maxf(2.0, citadel.river_width * px), true)
		var pit_p := to_map(Vector3(citadel.pit.x, 0, citadel.pit.y))
		draw_circle(pit_p, citadel.pit.z * px, Color(0.08, 0.06, 0.07))
		for r in citadel.roads:
			draw_polyline(_map_points(r.points), LANE if r.kind == 0 else TRAIL, maxf(1.5, float(r.width) * px), true)
		for line in citadel.walls:
			draw_polyline(_map_points(line), WALL, 1.5, true)
		for path in map.get_spawn_paths():
			draw_circle(to_map(path[0]), 4.0, Color(0.7, 0.35, 1.0))   # Portal
		var ring := _map_points(citadel.citadel_polygon)
		ring.append(ring[0])
		draw_polyline(ring, WALL, 2.0, true)
	else:
		draw_rect(rect, GROUND)
		for path in map.get_spawn_paths():
			var pts := PackedVector2Array()
			for p in path:
				pts.append(to_map(p))
			draw_polyline(pts, LANE, 3.0, true)
			draw_circle(pts[0], 4.0, Color(0.7, 0.35, 1.0))   # Portal
	if citadel != null:
		for s in citadel.shrines:
			draw_circle(to_map(s.global_position), 3.0, MapShrine.GLOW if s.is_ready() else DOWN)
		for s in citadel.structures:
			var col := FRIEND if s.is_alive() else DOWN
			var p := to_map(s.global_position)
			if s.kind == "gate":
				draw_rect(Rect2(p - Vector2(3, 6), Vector2(6, 12)), col)
			else:
				draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), col)
				draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), Color.BLACK, false, 1.0)
	if _match.fountain != null:
		draw_arc(to_map(_match.fountain.global_position), maxf(3.0, _match.fountain.radius * px), 0, TAU, 20, FRIEND, 1.5)
	var core_p := to_map(_match.core.global_position)
	draw_colored_polygon(PackedVector2Array([core_p + Vector2(0, -7), core_p + Vector2(7, 0), core_p + Vector2(0, 7), core_p + Vector2(-7, 0)]),
		UiTheme.CORE if _match.core.is_alive() else DOWN)
	for e in _match.spawner.alive_enemies():
		if is_instance_valid(e) and e.is_alive():
			draw_circle(to_map(e.global_position).clamp(Vector2.ZERO, size), 4.5 if e.brain != null else 2.5, FOE)
	for h in _match.heroes:
		if not is_instance_valid(h):
			continue
		var p := to_map(h.global_position).clamp(Vector2.ZERO, size)
		var mine := h == _match.local_hero
		draw_circle(p, 5.0 if mine else 4.0, Color.WHITE if mine else Color.BLACK)
		draw_circle(p, 3.5 if mine else 3.0, h.data.color if h.is_alive() else DOWN)
	_draw_view()
	draw_rect(rect, UiTheme.BORDER, false, 2.0)


func _map_points(world: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in world:
		out.append(to_map(Vector3(p.x, 0, p.y)))
	return out


## Kamerausschnitt als Viereck (Bodenpunkte der vier Bildschirmecken).
func _draw_view() -> void:
	var rig := _match.camera_rig
	if rig.camera == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var corners := PackedVector2Array()
	for s in [Vector2.ZERO, Vector2(vp.x, 0), vp, Vector2(0, vp.y)]:
		var g: Variant = rig.ground_point(s)
		if g == null:
			return
		var p := to_map(g)
		corners.append(p.clamp(Vector2.ZERO, size))
	corners.append(corners[0])
	draw_polyline(corners, Color(1, 1, 1, 0.75), 1.5)
