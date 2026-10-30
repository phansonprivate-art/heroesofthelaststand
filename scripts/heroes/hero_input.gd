class_name HeroInput
extends Node3D
## Übersetzt Maus und Tastatur des lokalen Spielers in Befehle an seinen Helden
## und zeigt Ziel- und Klickmarkierungen. Enthält keine Spiellogik.
## Auswahl (Issue #10, Doppelgänger): Befehle gehen an alle gewählten eigenen Einheiten. Linksklick wählt eine Einheit,
## Umschalt + Linksklick nimmt sie hinzu oder heraus, Linksklick ziehen wählt alle im Rahmen; F1 Held, F2 nächste
## Kopie, F3 alle Kopien, F4 alles. Fähigkeiten und Gegenstände wirkt immer der Held.

const PICK_RADIUS := 1.4
const HOLD_MOVE_INTERVAL := 0.12
const MOVE_COLOR := Color(0.4, 0.9, 1.0, 0.9)
const ATTACK_MOVE_COLOR := Color(1.0, 0.35, 0.3, 0.9)
const SELECT_COLOR := Color(0.75, 0.55, 1.0, 0.95)
const DRAG_MIN_PIXELS := 10.0     ## ab so viel Mausweg ist ein Linksklick ein Auswahlrahmen
const FORMATION_SPACING := 1.3    ## Abstand der Einheiten um den Zielpunkt bei Gruppenbefehlen

var hero: Hero                   ## erste gewählte Einheit (Marker, Halten-Bewegen); Befehle gehen an `selected`
var main_hero: Hero              ## der eigene Held; wirkt immer die Fähigkeiten
var selected: Array[Hero] = []   ## alle gewählten eigenen Einheiten (Held und/oder Doppelgänger)
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
var _select_rings: Array[MeshInstance3D] = []   ## violette Ringe unter gewählten Einheiten
var _drag_start := Vector2.ZERO
var _dragging := false
var _drag_box: Panel
var _selection_label: Label


func _ready() -> void:
	_hover_marker = _make_ring(Color(1.0, 0.85, 0.3, 0.7), 0.75)
	_target_marker = _make_ring(Color(1.0, 0.3, 0.25, 0.9), 0.85)
	_click_marker = _make_ring(MOVE_COLOR, 0.5)
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_drag_box = Panel.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.6, 0.45, 1.0, 0.12)
	box.border_color = Color(0.75, 0.55, 1.0, 0.9)
	box.set_border_width_all(2)
	_drag_box.add_theme_stylebox_override("panel", box)
	_drag_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_box.visible = false
	layer.add_child(_drag_box)
	_selection_label = Label.new()
	_selection_label.add_theme_font_size_override("font_size", 15)
	_selection_label.add_theme_color_override("font_color", SELECT_COLOR)
	_selection_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_selection_label.add_theme_constant_override("outline_size", 5)
	_selection_label.anchor_top = 1.0
	_selection_label.anchor_bottom = 1.0
	_selection_label.offset_left = 18.0
	_selection_label.offset_top = -275.0   # über der Heldenleiste (HUD-Grundauflösung 1080 hoch)
	_selection_label.offset_bottom = -250.0
	_selection_label.visible = false
	layer.add_child(_selection_label)


# --- Auswahl ------------------------------------------------------------------------------------

## Eine Einheit wählen (Held oder eigener Doppelgänger).
func select(unit: Hero) -> void:
	select_group([unit] if unit != null else [])


## Mehrere eigene Einheiten wählen; leere oder ungültige Auswahl = der Held.
func select_group(units: Array) -> void:
	var valid: Array[Hero] = []
	for u in units:
		if u is Hero and is_instance_valid(u) and (u as Hero).is_alive() and not valid.has(u):
			valid.append(u)
	if valid.is_empty() and main_hero != null:
		valid.append(main_hero)
	selected = valid
	hero = selected[0] if not selected.is_empty() else main_hero
	_set_attack_move_armed(false)
	_update_selection_label()


## Umschalt + Linksklick: Einheit zur Auswahl hinzunehmen bzw. herausnehmen.
func toggle_in_selection(unit: Hero) -> void:
	var units := selected.duplicate()
	if units.has(unit):
		units.erase(unit)
	else:
		units.append(unit)
	select_group(units)


## Eigene Einheiten (Held + seine Doppelgänger) in fester Reihenfolge
func _own_units() -> Array[Hero]:
	var units: Array[Hero] = [main_hero]
	for c in own_clones():
		units.append(c)
	return units


func own_clones() -> Array[Hero]:
	var result: Array[Hero] = []
	if main_hero != null and main_hero.world != null:
		for c: Hero in main_hero.world.clones:
			if is_instance_valid(c) and c.clone_owner == main_hero and c.is_alive():
				result.append(c)
	return result


## Eigene Einheit unter dem Mauszeiger (Linksklick wählt sie)
func _own_unit_at(point: Vector3) -> Hero:
	var best: Hero = null
	var best_d := PICK_RADIUS * 0.8
	for u in _own_units():
		if u == null or not is_instance_valid(u) or not u.is_alive():
			continue
		var d := Vector2(u.global_position.x - point.x, u.global_position.z - point.z).length()
		if d <= best_d:
			best_d = d
			best = u
	return best


## Auswahlrahmen: alle eigenen Einheiten, deren Fußpunkt im Rechteck (Bildschirm) liegt.
func box_select(rect: Rect2, add := false) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var units: Array = selected.duplicate() if add else []
	for u in _own_units():
		if u == null or not is_instance_valid(u) or not u.is_alive() or cam.is_position_behind(u.global_position):
			continue
		if rect.has_point(cam.unproject_position(u.global_position + Vector3(0, 0.8, 0))) and not units.has(u):
			units.append(u)
	if not units.is_empty():
		select_group(units)


func _update_selection_label() -> void:
	if _selection_label == null:
		return
	var clones := selected.filter(func(u: Hero) -> bool: return u.clone_owner != null).size()
	var with_hero := selected.has(main_hero)
	_selection_label.visible = clones > 0
	if clones > 0:
		_selection_label.text = "Auswahl: %s%d Doppelgänger   ·   F1 Held  ·  F3 alle Kopien  ·  F4 alle" % [
			"Held + " if with_hero else "", clones]


# --- Befehle an die Auswahl -----------------------------------------------------------------------

## Zielpunkt je Einheit: die erste genau auf den Punkt, die übrigen im Kreis darum (stehen nicht aufeinander).
func _formation_point(p: Vector3, index: int, count: int) -> Vector3:
	if index == 0 or count <= 1:
		return p
	var a := TAU * float(index - 1) / float(count - 1)
	var ring := FORMATION_SPACING * (1.0 + 0.4 * float(count > 6))
	return p + Vector3(cos(a), 0.0, sin(a)) * ring


func _command_move(p: Vector3) -> void:
	for i in selected.size():
		selected[i].command_move_to(_formation_point(p, i, selected.size()))


func _command_attack_move(p: Vector3) -> void:
	for i in selected.size():
		selected[i].command_attack_move(_formation_point(p, i, selected.size()))


func _command_attack(target: Enemy) -> void:
	for u in selected:
		u.command_attack(target)


func _command_stop() -> void:
	for u in selected:
		u.command_stop()


# --- Ablauf ---------------------------------------------------------------------------------------

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
				_command_move(p)


func _process(_delta: float) -> void:
	if main_hero == null:
		main_hero = hero
	if selected.is_empty() and main_hero != null:
		select(main_hero)
	# zerfallene Doppelgänger aus der Auswahl nehmen
	if selected.any(func(u) -> bool: return not is_instance_valid(u) or not (u as Hero).is_alive() and u != main_hero):
		select_group(selected.filter(func(u) -> bool: return is_instance_valid(u) and ((u as Hero).is_alive() or u == main_hero)))
	if hero == null or camera_rig == null:
		return
	hovered = null
	if input_enabled:
		var p: Variant = _mouse_ground()
		if p != null and enemies != null:
			hovered = enemies.nearest_enemy(p, PICK_RADIUS)
	_place_ring(_hover_marker, hovered if hovered != hero.attack_target else null)
	_place_ring(_target_marker, hero.attack_target if hero.is_alive() else null)
	_place_selection_rings()
	if _dragging:
		var now := get_viewport().get_mouse_position()
		var r := Rect2(_drag_start, Vector2.ZERO).expand(now)
		_drag_box.visible = r.size.length() >= DRAG_MIN_PIXELS
		_drag_box.position = r.position
		_drag_box.size = r.size


func _unhandled_input(event: InputEvent) -> void:
	if hero == null or not is_instance_valid(hero) or not input_enabled:
		return
	if event.is_action_pressed("select_hero"):
		select(main_hero)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("select_next_unit"):
		var units := _own_units()
		select(units[(units.find(hero) + 1) % units.size()] if units.size() > 1 else main_hero)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("select_all_clones"):
		select_group(own_clones())
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("select_all_units"):
		select_group(_own_units())
		get_viewport().set_input_as_handled()
		return
	if event.is_action_released("primary_action") and _dragging:
		_finish_drag(Input.is_key_pressed(KEY_SHIFT))
		get_viewport().set_input_as_handled()
		return
	if not hero.is_alive():
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
		_command_stop()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("primary_action"):
		if _attack_move_armed:
			_set_attack_move_armed(false)
			if hovered != null:
				_command_attack(hovered)
			else:
				var p: Variant = _mouse_ground()
				if p != null:
					_command_attack_move(p)
					_show_click(p, ATTACK_MOVE_COLOR)
			get_viewport().set_input_as_handled()
		elif hovered != null:
			_command_attack(hovered)
			get_viewport().set_input_as_handled()
		else:   # Klick oder Auswahlrahmen: entschieden wird beim Loslassen
			_dragging = true
			_drag_start = get_viewport().get_mouse_position()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("secondary_action"):
		_set_attack_move_armed(false)
		if hovered != null:
			_command_attack(hovered)
		else:
			var p: Variant = _mouse_ground()
			if p != null:
				_command_move(p)
				_show_click(p)
		_hold_timer = HOLD_MOVE_INTERVAL
		get_viewport().set_input_as_handled()


## Linksklick losgelassen: kurzer Klick wählt die Einheit darunter (Umschalt: hinzu/heraus), gezogen = Rahmen.
func _finish_drag(add: bool) -> void:
	_dragging = false
	_drag_box.visible = false
	var end := get_viewport().get_mouse_position()
	if _drag_start.distance_to(end) >= DRAG_MIN_PIXELS:
		box_select(Rect2(_drag_start, Vector2.ZERO).expand(end), add)
		return
	var p: Variant = _mouse_ground()
	var unit := _own_unit_at(p) if p != null else null
	if unit == null:
		return
	if add:
		toggle_in_selection(unit)
	else:
		select(unit)


## Schnellwirken (wie "Quick Cast" in MOBAs): Ziel ist, was unter dem Mauszeiger liegt.
func _cast(slot: int) -> void:
	if hero.world == null or main_hero == null or not main_hero.is_alive():
		return
	_set_attack_move_armed(false)
	var p: Variant = _mouse_ground()
	var point: Vector3 = p if p != null else hero.global_position
	var caster := main_hero if main_hero != null else hero   # Fähigkeiten wirkt immer der Held, nie die Kopie
	var id: String = caster.abilities.slots[slot]
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


## Violette Ringe unter allen gewählten Einheiten – außer wenn nur der Held gewählt ist (Normalfall).
func _place_selection_rings() -> void:
	var show := selected.filter(func(u) -> bool: return is_instance_valid(u)) if not (selected.size() == 1 and selected[0] == main_hero) else []
	while _select_rings.size() < show.size():
		_select_rings.append(_make_ring(SELECT_COLOR, 0.9))
	for i in _select_rings.size():
		_place_ring(_select_rings[i], show[i] if i < show.size() else null)


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
