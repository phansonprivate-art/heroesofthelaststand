class_name FloatingText
extends Node3D
## Schwebende Zahlen (Schaden, Krits, Gold) und kurze Effekte (Levelaufstieg). Reine Darstellung.
## Die Anzahl gleichzeitiger Texte ist begrenzt, damit bei großen Kämpfen keine Node-Flut entsteht.

const MAX_ACTIVE := 40
const LIFETIME := 0.75

var local_peer := 1
var _active := 0


func bind(combat: CombatService, rewards: RewardService = null, p_local_peer := 1) -> void:
	local_peer = p_local_peer
	combat.damage_applied.connect(_on_damage)
	if rewards != null:
		rewards.gold_awarded.connect(_on_gold)


func _on_damage(target: Node3D, info: DamageInfo) -> void:
	if not is_instance_valid(target):
		return
	var color := Color(1.0, 0.95, 0.8)
	var size := 56
	var text := str(roundi(info.amount))
	if target is Hero:
		color = Color(1.0, 0.35, 0.3)
	elif target is DefenseCore:
		color = Color(1.0, 0.55, 0.25)
		size = 64
	elif info.type == DamageInfo.Type.MAGIC:
		color = Color(0.75, 0.6, 1.0)
	if info.is_crit:
		color = Color(1.0, 0.5, 0.15)
		size = 80
		text += "!"
	# Voller Trefferwert statt Restlebenspunkten, damit tödliche Treffer nicht schwach wirken
	spawn_text(text, target.global_position + Vector3(randf_range(-0.4, 0.4), 2.4, 0), color, size)


func _on_gold(peer_id: int, amount: int, pos: Vector3) -> void:
	if peer_id == local_peer:
		spawn_text("+%d Gold" % amount, pos + Vector3(0, 1.6, 0), Color(1.0, 0.82, 0.3), 44)


func spawn_text(text: String, pos: Vector3, color: Color, size := 56) -> void:
	if _active >= MAX_ACTIVE:
		return
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.outline_size = 12
	label.modulate = color
	label.outline_modulate = Color(0, 0, 0, 0.8)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.008
	label.render_priority = 5
	label.outline_render_priority = 4
	add_child(label)
	label.global_position = pos
	_active += 1
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position", pos + Vector3(0, 1.1, 0), LIFETIME).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(label, "modulate:a", 0.0, LIFETIME * 0.5).set_delay(LIFETIME * 0.5)
	tween.tween_property(label, "outline_modulate:a", 0.0, LIFETIME * 0.5).set_delay(LIFETIME * 0.5)
	tween.chain().tween_callback(func() -> void:
		_active -= 1
		label.queue_free())


## Ring am Boden, der von from_radius auf to_radius wächst und ausblendet (Fähigkeiten, Warnungen).
## Gleiche Radien = stehende Markierung (z. B. Einschlag-Vorwarnung).
func spawn_ring(pos: Vector3, from_radius: float, to_radius: float, color: Color, duration: float) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.0
	torus.rings = 48
	torus.ring_segments = 4
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.no_depth_test = true
	mat.render_priority = 1
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.global_position = Vector3(pos.x, 0.08, pos.z)
	ring.scale = Vector3(from_radius, 0.2, from_radius)
	var tween := ring.create_tween().set_parallel(true)
	if not is_equal_approx(from_radius, to_radius):
		tween.tween_property(ring, "scale", Vector3(to_radius, 0.2, to_radius), duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(mat, "albedo_color:a", 0.0, duration * 0.5).set_delay(duration * 0.5)
	tween.chain().tween_callback(ring.queue_free)


## Ringförmiger Lichtimpuls am Boden, z. B. beim Levelaufstieg.
func spawn_burst(pos: Vector3, color: Color) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	torus.rings = 48
	torus.ring_segments = 4
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.no_depth_test = true
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.global_position = Vector3(pos.x, 0.1, pos.z)
	ring.scale = Vector3(0.5, 0.3, 0.5)
	var tween := ring.create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(3.0, 0.3, 3.0), 0.7).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.7)
	tween.chain().tween_callback(ring.queue_free)
