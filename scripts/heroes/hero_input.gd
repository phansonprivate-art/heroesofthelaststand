class_name HeroInput
extends Node3D
## Übersetzt Maus und Tastatur des lokalen Spielers in Befehle an seinen Helden
## und zeigt Ziel- und Klickmarkierungen. Enthält keine Spiellogik.

const PICK_RADIUS := 1.4
const HOLD_MOVE_INTERVAL := 0.12
const MOVE_COLOR := Color(0.4, 0.9, 1.0, 0.9)
const ATTACK_MOVE_COLOR := Color(1.0, 0.35, 0.3, 0.9)

var hero: Hero
var camera_rig: CameraRig
var enemies: EnemySpawner
var input_enabled := true

var hovered: Enemy = null
var _hover_marker: MeshInstance3D
var _target_marker: MeshInstance3D
var _click_marker: MeshInstance3D
var _click_tween: Tween
var _hold_timer := 0.0
var _attack_move_armed := false


func _ready() -> void:
	_hover_marker = _make_ring(Color(1.0, 0.85, 0.3, 0.7), 0.75)
	_target_marker = _make_ring(Color(1.0, 0.3, 0.25, 0.9), 0.85)
	_click_marker = _make_ring(MOVE_COLOR, 0.5)


func _physics_process(delta: float) -> void:
	if hero == null or camera_rig == null:
		return
	if not input_enabled:
		_set_attack_move_armed(false)
		return
	# Rechte Maustaste gedrückt halten = dem Mauszeiger folgen (Befehle gedrosselt, später weniger Netzwerkverkehr)
	if Input.is_action_pressed("secondary_action") and hovered == null:
		_hold_timer -= delta
		if _hold_timer <= 0.0:
			_hold_timer = HOLD_MOVE_INTERVAL
			var p: Variant = _mouse_ground()
			if p != null:
				hero.command_move_to(p)


func _process(_delta: float) -> void:
	if hero == null or camera_rig == null:
		return
	hovered = null
	if input_enabled:
		var p: Variant = _mouse_ground()
		if p != null and enemies != null:
			hovered = enemies.nearest_enemy(p, PICK_RADIUS)
	_place_ring(_hover_marker, hovered if hovered != hero.attack_target else null)
	_place_ring(_target_marker, hero.attack_target if hero.is_alive() else null)


func _unhandled_input(event: InputEvent) -> void:
	if hero == null or not input_enabled or not hero.is_alive():
		return
	for i in AbilityCaster.SLOT_KEYS.size():
		if event.is_action_pressed("ability_%d" % (i + 1)):
			_cast(i)
			get_viewport().set_input_as_handled()
			return
	for i in 2:
		if event.is_action_pressed("item_%d" % (i + 1)) and hero.world != null:
			hero.world.request_use_consumable(i)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("attack_move"):
		_set_attack_move_armed(true)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("stop"):
		_set_attack_move_armed(false)
		hero.command_stop()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("primary_action"):
		if _attack_move_armed:
			_set_attack_move_armed(false)
			if hovered != null:
				hero.command_attack(hovered)
			else:
				var p: Variant = _mouse_ground()
				if p != null:
					hero.command_attack_move(p)
					_show_click(p, ATTACK_MOVE_COLOR)
			get_viewport().set_input_as_handled()
		elif hovered != null:
			hero.command_attack(hovered)
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("secondary_action"):
		_set_attack_move_armed(false)
		if hovered != null:
			hero.command_attack(hovered)
		else:
			var p: Variant = _mouse_ground()
			if p != null:
				hero.command_move_to(p)
				_show_click(p)
		_hold_timer = HOLD_MOVE_INTERVAL
		get_viewport().set_input_as_handled()


## Schnellwirken (wie "Quick Cast" in MOBAs): Ziel ist, was unter dem Mauszeiger liegt.
func _cast(slot: int) -> void:
	if hero.world == null:
		return
	_set_attack_move_armed(false)
	var p: Variant = _mouse_ground()
	var point: Vector3 = p if p != null else hero.global_position
	var id: String = hero.abilities.slots[slot]
	var target_unit: Node3D = hovered
	if id != "" and GameData.skill(id).target == "ally":
		target_unit = _hovered_ally(point)
	hero.world.request_cast(slot, target_unit, point)


func _hovered_ally(point: Vector3) -> Hero:
	var best: Hero = null
	var best_d := PICK_RADIUS
	for h: Hero in hero.world.heroes:
		if not is_instance_valid(h) or not h.is_alive():
			continue
		var d := Vector2(h.global_position.x - point.x, h.global_position.z - point.z).length()
		if d <= best_d:
			best_d = d
			best = h
	return best


func _mouse_ground() -> Variant:
	return camera_rig.ground_point(get_viewport().get_mouse_position())


func _place_ring(ring: MeshInstance3D, target: Node3D) -> void:
	if target == null or not is_instance_valid(target):
		ring.visible = false
		return
	ring.visible = true
	var r: float = target.get("body_radius") if target.get("body_radius") != null else 0.6
	ring.global_position = Vector3(target.global_position.x, 0.06, target.global_position.z)
	ring.scale = Vector3(r + 0.4, 1.0, r + 0.4)


## A gedrückt: nächster Linksklick ist eine Angriffsbewegung (Fadenkreuz als Hinweis).
func _set_attack_move_armed(armed: bool) -> void:
	if _attack_move_armed == armed:
		return
	_attack_move_armed = armed
	Input.set_default_cursor_shape(Input.CURSOR_CROSS if armed else Input.CURSOR_ARROW)


func _exit_tree() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _show_click(p: Vector3, color := MOVE_COLOR) -> void:
	(_click_marker.material_override as StandardMaterial3D).albedo_color = color
	_click_marker.global_position = Vector3(p.x, 0.06, p.z)
	_click_marker.visible = true
	_click_marker.scale = Vector3.ONE * 1.2
	if _click_tween != null:
		_click_tween.kill()
	_click_tween = create_tween()
	_click_tween.tween_property(_click_marker, "scale", Vector3.ONE * 0.3, 0.35)
	_click_tween.tween_callback(func() -> void: _click_marker.visible = false)


func _make_ring(color: Color, radius: float) -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.inner_radius = radius * 0.82
	torus.outer_radius = radius
	torus.rings = 32
	torus.ring_segments = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.no_depth_test = true
	mat.render_priority = 2
	var ring := MeshInstance3D.new()
	ring.mesh = torus
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.visible = false
	ring.top_level = true
	add_child(ring)
	return ring
