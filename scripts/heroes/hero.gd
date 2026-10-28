class_name Hero
extends CharacterBody3D
## Simulation eines Helden: Bewegung, Zielverfolgung, Angriff, Tod und Wiederbelebung.
## Bekommt nur Befehle (command_*); woher sie kommen (lokale Eingabe, später Netzwerk), ist egal.

signal died(hero: Hero)
signal respawned(hero: Hero)
signal leveled_up(hero: Hero, level: int)
signal stats_changed(hero: Hero)
signal mana_changed(current: float, maximum: float)
signal attack_started(hero: Hero, ranged: bool)

const TURN_SPEED := 14.0
const AUTO_ACQUIRE_BONUS := 1.2   ## Auto-Angriff greift Gegner etwas außerhalb der Reichweite auf
const AUTO_LEASH_BONUS := 3.0     ## automatisch gewählte Ziele werden nicht endlos verfolgt
const ATTACK_MOVE_ACQUIRE := 3.0  ## Suchradius-Zuschlag bei Angriffsbewegung

@onready var health: HealthComponent = $Health
@onready var visual: CharacterVisual = $Visual
@onready var collision: CollisionShape3D = $Collision
@onready var selection_ring: MeshInstance3D = $SelectionRing
@onready var status: StatusEffects = $Status
@onready var abilities: AbilityCaster = $Abilities

var data: Dictionary = {}
var stats: StatBlock
var mana := 0.0
var projectile_root: Node3D       ## Ablage für Geschosse (Fernkampfhelden)
var world: Node                    ## MatchController (für Fähigkeiten: Gegner, Verbündete, Effekte)
var inventory: Inventory
var idle_time := 0.0               ## Sekunden ohne Spielerbefehl (AFK-Erkennung)
var _shield_bubble: MeshInstance3D
var rng := RandomNumberGenerator.new()
var _max_mana_cache := 0.0
var hero_id := ""
var peer_id := 1
var combat: CombatService
var enemies: EnemySpawner
var respawn_point := Vector3.ZERO
var respawn_seconds := 6.0
var respawn_left := 0.0

var move_input := Vector3.ZERO
var move_target := Vector3.ZERO
var has_move_target := false
var attack_moving := false
var attack_target: Enemy = null
var _target_is_auto := false
var _attack_cooldown := 0.0
var _windup_left := -1.0
var _windup_target: Enemy = null


func setup(hero_data: Dictionary, p_combat: CombatService, p_enemies: EnemySpawner, spawn_point: Vector3, p_respawn_seconds: float) -> void:
	data = hero_data
	hero_id = data.id
	combat = p_combat
	enemies = p_enemies
	respawn_point = spawn_point
	respawn_seconds = p_respawn_seconds
	global_position = spawn_point
	stats = StatBlock.create(data, GameData.attribute_rules)
	stats.changed.connect(_apply_stats)
	stats.leveled_up.connect(func(lvl: int) -> void: leveled_up.emit(self, lvl))
	health.setup(stats.max_hp())
	mana = stats.max_mana()
	_max_mana_cache = mana
	status.max_slow = float(GameData.attribute_rules.get("caps", {}).get("slow", 0.7))
	health.died.connect(_on_died)
	health.damaged.connect(func(_i: DamageInfo) -> void: visual.flash(Color(1, 0.3, 0.25)))
	visual.setup(data.model, data.hidden_parts, data.model_scale, data.anims, data.color)
	visual.add_animation_libraries(data.anim_libraries)
	(selection_ring.get_surface_override_material(0) as StandardMaterial3D).albedo_color = Color(data.color, 0.8)
	inventory = Inventory.new()
	abilities.setup(self)
	health.shield_changed.connect(func(total: float) -> void: _shield_bubble.visible = total > 0.0)
	status.effects_changed.connect(_on_status_changed)
	_build_shield_bubble()
	visual.play("idle")


func is_alive() -> bool:
	return not health.dead


func gain_xp(amount: int) -> void:
	stats.add_xp(amount)


## Für die Schadensberechnung im CombatService
func get_armor() -> float:
	return stats.armor() + status.magnitude(StatusEffects.ARMOR_BONUS)


func get_magic_resist() -> float:
	return stats.magic_resist()


## Übernimmt geänderte Werte (Levelaufstieg, Attributkauf). Gewonnene Max-LP/-Mana werden aufgefüllt.
func _apply_stats() -> void:
	health.set_max_hp(stats.max_hp())
	var old_max_mana := _max_mana_cache
	_max_mana_cache = stats.max_mana()
	mana = clampf(mana + maxf(0.0, _max_mana_cache - old_max_mana), 0.0, _max_mana_cache)
	mana_changed.emit(mana, _max_mana_cache)
	stats_changed.emit(self)


# --- Befehle -------------------------------------------------------------

## Jeder Spielerbefehl zählt als Aktivität und bricht eine wartende Fähigkeit ab.
func _on_command() -> void:
	idle_time = 0.0
	abilities.cancel_queue()


func command_move_direction(dir: Vector3) -> void:
	move_input = Vector3(dir.x, 0.0, dir.z)
	if move_input.length_squared() > 0.01:
		has_move_target = false
		_clear_target()


func command_move_to(point: Vector3) -> void:
	_on_command()
	move_target = Vector3(point.x, 0.0, point.z)
	has_move_target = true
	attack_moving = false
	_clear_target()


## Angriffsbewegung: zum Punkt laufen, unterwegs Gegner in Reichweite angreifen, danach weiterlaufen.
func command_attack_move(point: Vector3) -> void:
	command_move_to(point)
	attack_moving = true


func command_attack(target: Enemy) -> void:
	if target == null or not target.is_alive():
		return
	_on_command()
	attack_target = target
	_target_is_auto = false
	has_move_target = false
	attack_moving = false


func command_stop() -> void:
	_on_command()
	has_move_target = false
	attack_moving = false
	move_input = Vector3.ZERO
	_cancel_windup()
	_clear_target()


## Rundenende: Simulation anhalten, bei Sieg jubeln.
func freeze(cheer: bool) -> void:
	command_stop()
	abilities.cancel_queue()
	_cancel_windup()
	set_physics_process(false)
	if cheer and is_alive():
		visual.play("cheer")


# --- Simulation ----------------------------------------------------------

func _physics_process(delta: float) -> void:
	if health.dead:
		respawn_left -= delta
		if respawn_left <= 0.0:
			_respawn()
		return

	idle_time += delta
	# Regeneration ohne Quelle: zählt nicht als belohnbare Heilung
	health.heal(stats.hp_regen() * delta, null)
	_regen_mana(delta)
	if status.has(StatusEffects.UNTARGETABLE):
		velocity = Vector3.ZERO   # Blade Dance führt den Helden: kein Laufen, kein Auto-Angriff
		return
	if status.has(StatusEffects.CHANNEL):
		if has_move_target or move_input.length_squared() > 0.01:
			status.remove(StatusEffects.CHANNEL)   # Bewegungsbefehl bricht die Kanalisierung ab
		else:
			velocity = Vector3.ZERO
			return
	_attack_cooldown -= delta
	if status.is_stunned():
		_cancel_windup()
		velocity = Vector3.ZERO
		visual.play("idle")
		return
	_update_windup(delta)

	var desired := Vector3.ZERO
	var face_point = null
	if attack_moving:
		_validate_target()
		if attack_target == null:
			_auto_acquire(ATTACK_MOVE_ACQUIRE)
	if move_input.length_squared() > 0.01:
		desired = move_input
	elif has_move_target and not (attack_moving and attack_target != null):
		var to_target := _flat(move_target - global_position)
		if to_target.length() < 0.25:
			has_move_target = false
			attack_moving = false
		else:
			desired = to_target
	else:
		_validate_target()
		if attack_target == null:
			_auto_acquire(AUTO_ACQUIRE_BONUS)
		if attack_target != null:
			face_point = attack_target.global_position
			var dist := _flat_dist(attack_target)
			if dist > _reach(attack_target):
				desired = _flat(attack_target.global_position - global_position)
			elif _attack_cooldown <= 0.0 and _windup_left < 0.0 and not status.has(StatusEffects.WHIRL):
				_start_attack(attack_target)

	if desired.length_squared() > 0.0001:
		if _windup_left >= 0.0:
			_cancel_windup()   # Bewegen bricht einen laufenden Schlag ab
		desired = desired.normalized()
		face_point = global_position + desired
	velocity = desired * stats.move_speed() * status.move_multiplier()
	velocity.y = 0.0
	move_and_slide()
	global_position.y = 0.0

	if face_point != null:
		_face(face_point, delta)
	_update_animation(desired)


func _start_attack(target: Enemy) -> void:
	var interval := current_attack_interval()
	_attack_cooldown = interval
	_windup_target = target
	var anim_len := visual.animation_length("attack")
	# Animation so beschleunigen, dass sie nie länger als das Angriffsintervall dauert
	var speed := maxf(1.0, anim_len / maxf(interval, 0.1)) if anim_len > 0.0 else 1.0
	# Der Treffermoment rückt bei hohem Angriffstempo entsprechend nach vorne
	_windup_left = data.attack_hit_delay * minf(1.0, interval / data.base_attack_interval)
	visual.play("attack", speed, true)
	attack_started.emit(self, not data.projectile.is_empty())


func _update_windup(delta: float) -> void:
	if _windup_left < 0.0:
		return
	_windup_left -= delta
	if _windup_left > 0.0:
		return
	_windup_left = -1.0
	var target := _windup_target
	_windup_target = null
	if target == null or not is_instance_valid(target) or not target.is_alive() or _flat_dist(target) > _reach(target) + 0.6:
		return
	var roll := stats.roll_attack(rng, status.magnitude(StatusEffects.CRIT_BONUS))
	if not data.projectile.is_empty() and projectile_root != null:
		var p := Projectile.new()
		projectile_root.add_child(p)
		p.launch(self, target, combat, roll.amount, stats.damage_type(), roll.crit, data.on_hit,
			global_position + Vector3(0, 1.4, 0) - global_basis.z * 0.6,
			float(data.projectile.get("speed", 20.0)), Color.html(String(data.projectile.get("color", "#ffffff"))))
	else:
		hit_target(target, roll.amount, roll.crit)


## Trifft ein Ziel sofort (Nahkampf) oder beim Einschlag eines Geschosses. Wendet On-Hit-Effekte an.
func hit_target(target: Enemy, amount: float, crit: bool) -> void:
	var dealt := combat.deal_damage(self, target, amount, stats.damage_type(), crit)
	if dealt > 0.0:
		apply_on_hit(target, data.on_hit, self)


static func apply_on_hit(target: Node, on_hit: Dictionary, source: Node) -> void:
	if on_hit.is_empty() or not is_instance_valid(target):
		return
	var st: StatusEffects = target.get("status")
	if st != null:
		st.apply(String(on_hit.get("status", "")), float(on_hit.get("duration", 0.0)), float(on_hit.get("magnitude", 0.0)), source)


## Angriffsintervall inkl. Tempo-Buffs (Segen, Shadow Dance). Gesamtbonus bleibt gedeckelt.
func current_attack_interval() -> float:
	var cap := float(GameData.attribute_rules.get("caps", {}).get("attack_speed_bonus", 1.5))
	var bonus := minf(stats.attack_speed_bonus() + status.magnitude(StatusEffects.HASTE), cap)
	return data.base_attack_interval / (1.0 + bonus)


func spend_mana(amount: float) -> bool:
	if mana < amount:
		return false
	mana -= amount
	mana_changed.emit(mana, stats.max_mana())
	return true


func restore_mana(amount: float) -> void:
	mana = minf(stats.max_mana(), mana + amount)
	mana_changed.emit(mana, stats.max_mana())


## Laufen zu einem Punkt, ohne als Spielerbefehl zu zählen (z. B. um eine Fähigkeit in Reichweite zu bringen).
func chase_point(point: Vector3) -> void:
	move_target = Vector3(point.x, 0.0, point.z)
	has_move_target = true
	attack_moving = false
	_clear_target()


## Schreibt die Boni der angelegten Ausrüstung in den StatBlock.
func apply_equipment() -> void:
	stats.bonus = inventory.stat_bonus()
	stats.changed.emit()


func _on_status_changed() -> void:
	var mat := selection_ring.get_surface_override_material(0) as StandardMaterial3D
	if status.damage_reduction() > 0.0:
		mat.albedo_color = Color(1.0, 0.85, 0.3, 0.95)
	else:
		mat.albedo_color = Color(data.color, 0.8)
	# geisterhaft violett, solange der Held unverwundbar ist (Blade Dance)
	visual.set_tint(Color(0.65, 0.45, 1.0, 0.45) if status.has(StatusEffects.UNTARGETABLE) else Color.TRANSPARENT)


func _build_shield_bubble() -> void:
	_shield_bubble = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.15
	sphere.height = 2.5
	_shield_bubble.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.5, 0.85, 1.0, 0.22)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shield_bubble.material_override = mat
	_shield_bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shield_bubble.position.y = 1.0
	_shield_bubble.visible = false
	add_child(_shield_bubble)


func _regen_mana(delta: float) -> void:
	var max_mana := stats.max_mana()
	if mana < max_mana:
		mana = minf(max_mana, mana + stats.mana_regen() * delta)
		mana_changed.emit(mana, max_mana)


func _cancel_windup() -> void:
	_windup_left = -1.0
	_windup_target = null


func _auto_acquire(bonus: float) -> void:
	if enemies == null:
		return
	var e := enemies.nearest_enemy(global_position, stats.attack_range() + bonus)
	if e != null:
		attack_target = e
		_target_is_auto = true


func _validate_target() -> void:
	if attack_target == null:
		return
	if not is_instance_valid(attack_target) or not attack_target.is_alive():
		_clear_target()
	elif _target_is_auto and _flat_dist(attack_target) > stats.attack_range() + AUTO_LEASH_BONUS:
		_clear_target()


func _clear_target() -> void:
	attack_target = null
	_target_is_auto = false


func _reach(target: Enemy) -> float:
	return stats.attack_range() + target.body_radius


func _update_animation(desired: Vector3) -> void:
	if status.has(StatusEffects.WHIRL):
		return   # die Wirbel-Fähigkeit spielt ihre Drehung auch im Laufen weiter
	if visual.is_busy() and desired == Vector3.ZERO:
		return
	if desired == Vector3.ZERO:
		visual.play("idle")
	else:
		# Laufanimation passend zum tatsächlichen Tempo: kein Rutschen, schneller bei Tempo-Buffs
		visual.play("run", clampf(velocity.length() / maxf(0.1, float(data.base_move_speed)), 0.6, 1.8))


func _face(point: Vector3, delta: float) -> void:
	var dir := _flat(point - global_position)
	if dir.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(TURN_SPEED * delta, 0.0, 1.0))


func _on_died(_info: DamageInfo) -> void:
	_cancel_windup()
	abilities.cancel_queue()
	command_stop()
	velocity = Vector3.ZERO
	respawn_left = respawn_seconds
	collision.set_deferred("disabled", true)
	selection_ring.visible = false
	visual.play("death")
	died.emit(self)


func _respawn() -> void:
	global_position = respawn_point
	health.revive(1.0)
	mana = stats.max_mana()
	status.clear()
	collision.set_deferred("disabled", false)
	selection_ring.visible = true
	visual.play("idle", 1.0, true)
	respawned.emit(self)


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _flat_dist(node: Node3D) -> float:
	return _flat(node.global_position - global_position).length()
