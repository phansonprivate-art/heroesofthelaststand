class_name CameraRig
extends Node3D
## Feste Schrägansicht von oben (3/4-Perspektive). Fixiert folgt sie dem lokalen Helden,
## gelöst wird sie per Bildschirmrand verschoben; Leertaste zentriert (MOBA-Stil).
## Gehört genau einem lokalen Spieler und wird nie synchronisiert.

const MIN_DIST := 14.0
const MAX_DIST := 52.0
const YAW := 0.0                    ## Blick nach Norden; alle drei Tore liegen im Sichtfeld
const PITCH_DEG := 56.0
const BOUNDS := Rect2(-26, -26, 52, 52)

signal lock_changed(locked: bool)

const EDGE_MARGIN := 14.0
const EDGE_PAN_SPEED := 32.0

var target: Node3D
var camera: Camera3D
var locked := true              ## Y: Kamera folgt dem Helden oder ist frei (Randscrollen)
var edge_pan_enabled := true
var distance := 26.0
var _target_distance := 26.0
var focus := Vector3.ZERO
var _shake := 0.0


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 40.0
	camera.near = 0.5
	camera.far = 300.0
	add_child(camera)
	camera.make_current()
	if target != null:
		focus = target.global_position
	_apply()


func _process(delta: float) -> void:
	var has_target := target != null and is_instance_valid(target)
	if has_target and (locked or Input.is_action_pressed("camera_center")):
		focus = focus.lerp(target.global_position, 1.0 - exp(-7.0 * delta))
	elif not locked:
		_edge_pan(delta)
	distance = lerpf(distance, _target_distance, 1.0 - exp(-10.0 * delta))
	_shake = maxf(0.0, _shake - delta * 2.5)
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("zoom_in"):
		_target_distance = clampf(_target_distance * 0.9, MIN_DIST, MAX_DIST)
	elif event.is_action_pressed("zoom_out"):
		_target_distance = clampf(_target_distance * 1.1, MIN_DIST, MAX_DIST)
	elif event.is_action_pressed("camera_lock"):
		locked = not locked
		lock_changed.emit(locked)


## Gelöste Kamera: verschieben, wenn der Mauszeiger am Fensterrand steht.
func _edge_pan(delta: float) -> void:
	if not edge_pan_enabled or DisplayServer.window_is_focused() == false:
		return
	var vp := get_viewport()
	var rect := vp.get_visible_rect()
	var m := vp.get_mouse_position()
	if not rect.has_point(m):
		return
	var dir := Vector2.ZERO
	if m.x <= EDGE_MARGIN:
		dir.x = -1.0
	elif m.x >= rect.size.x - EDGE_MARGIN:
		dir.x = 1.0
	if m.y <= EDGE_MARGIN:
		dir.y = -1.0
	elif m.y >= rect.size.y - EDGE_MARGIN:
		dir.y = 1.0
	if dir != Vector2.ZERO:
		focus += ground_direction(dir) * EDGE_PAN_SPEED * (distance / 26.0) * delta


func shake(strength: float) -> void:
	_shake = clampf(maxf(_shake, strength), 0.0, 1.0)


func _apply() -> void:
	focus.x = clampf(focus.x, BOUNDS.position.x, BOUNDS.end.x)
	focus.z = clampf(focus.z, BOUNDS.position.y, BOUNDS.end.y)
	var p := deg_to_rad(PITCH_DEG)
	var offset := Vector3(sin(YAW) * cos(p), sin(p), cos(YAW) * cos(p)) * distance
	var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * _shake * 0.35
	camera.global_position = focus + offset + jitter
	camera.look_at(focus + Vector3(0, 0.8, 0) + jitter, Vector3.UP)


## Punkt auf dem Boden (y = 0) unter einer Bildschirmposition.
func ground_point(screen_pos: Vector2) -> Variant:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	return Plane(Vector3.UP, 0.0).intersects_ray(from, dir)


## Wandelt eine Eingabe (x = rechts, y = runter) in eine Bodenrichtung relativ zur Kamera um.
func ground_direction(input: Vector2) -> Vector3:
	if input == Vector2.ZERO:
		return Vector3.ZERO
	var right := camera.global_basis.x
	right.y = 0.0
	var forward := -camera.global_basis.z
	forward.y = 0.0
	return (right.normalized() * input.x - forward.normalized() * input.y).normalized()
