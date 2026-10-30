class_name Enemy
extends CharacterBody3D
## Gegner als einfacher Zustandsautomat:
##   SPAWNING -> ADVANCE (Pfad zum Kern) -> ATTACK (Kern oder Held) -> DEAD
## Standardziel ist der Kern. Helden in der Nähe (aggro_radius) oder Helden, die den Gegner angreifen,
## ziehen ihn ab, solange sie im aggro_leash bleiben. Taunt (Phase 3) setzt mit höherer Priorität an.

signal died(enemy: Enemy, info: DamageInfo)

enum State { SPAWNING, ADVANCE, ATTACK, DEAD }

const WAYPOINT_REACHED := 1.6
const CORE_DIRECT_RANGE := 9.0   ## ab dieser Nähe zum Kern direkt darauf zu, ohne Wegpunkte
const SCAN_INTERVAL := 0.25      ## so oft wird nach Helden in der Nähe gesucht (nicht jeden Frame)
const THREAT_LEASH_MARGIN := 4.0   ## so viel weiter als die Trefferdistanz wird ein Angreifer verfolgt
const STAGGER_SECONDS := 0.2
const STAGGER_COOLDOWN := 0.8
const STAGGER_MIN_RATIO := 0.04
## Wird ein Gegner von einem Helden angegriffen, den er bisher nicht im Visier hatte, wehrt er sich nach spätestens
## dieser Zeit – statt erst die volle Angriffspause eines Schlags auf den Kern abzuwarten (Issue #3: Auskiten)
const RETALIATE_DELAY := 0.15
const REACH_MARGIN := 0.1        ## Nahkampfgegner erreichen einen Nahkampfhelden knapp an dessen eigener Reichweite

@onready var health: HealthComponent = $Health
@onready var visual: CharacterVisual = $Visual
@onready var collision: CollisionShape3D = $Collision
@onready var health_bar: MeshInstance3D = $HealthBar
@onready var status: StatusEffects = $Status

var data: Dictionary = {}
var enemy_id := ""
var uid := 0                  ## eindeutige, fortlaufende Nummer je Runde (Schutz vor Doppelbelohnung)
var damage_multiplier := 1.0
var state := State.SPAWNING
var body_radius := 0.5
var combat: CombatService
var core: DefenseCore
var spawner: EnemySpawner
var world: Node                 ## MatchController (Effekte, Geschosse) – vom Spawner gesetzt, in Tests evtl. leer
var target: Node3D = null
var haste := 1.0                ## Angriffstempo-Faktor (Boss-Raserei)
var move_bonus := 1.0           ## Lauftempo-Faktor (Boss-Raserei)
var brain: BossBrain = null     ## nur bei Bossen: Phasen und Bossfähigkeiten

var _path: PackedVector3Array = []
var _path_index := 0
var _threat_target: Hero = null
var _threat_left := 0.0
var _threat_seconds := 4.0
var _threat_leash := 8.0
var _stagger_left := 0.0
var _stagger_cooldown := 0.0
var _scan_left := 0.0
var _attack_cooldown := 0.0
var _windup_left := -1.0
var _state_left := 0.0
var _corpse_seconds := 2.5
var _ability_left := 0.0        ## Abklingzeit der Zusatzfähigkeit
var _ability_windup := -1.0     ## >= 0: Fähigkeit wird gerade angekündigt (Warnkreis), bei 0 löst sie aus
var _melee_swing := false       ## laufender Schlag ist ein Nahkampfhieb eines Hybrid-Gegners


func setup(enemy_data: Dictionary, path: PackedVector3Array, p_core: DefenseCore, p_combat: CombatService, p_spawner: EnemySpawner, hp_multiplier: float, p_damage_multiplier := 1.0) -> void:
	data = enemy_data
	enemy_id = data.id
	_path = path
	core = p_core
	combat = p_combat
	spawner = p_spawner
	target = core
	body_radius = data.body_radius if float(data.get("body_radius", 0.0)) > 0.0 else 0.45 * data.model_scale
	damage_multiplier = p_damage_multiplier
	status.cc_resist = data.cc_resist
	status.max_slow = float(GameData.attribute_rules.get("caps", {}).get("slow", 0.7))
	status.effects_changed.connect(_on_status_changed)
	# Gift: Schaden über den CombatService, damit er als Beteiligung des Verursachers zählt; ignoriert Rüstung
	status.dot_handler = func(src: Node, amount: float, element: String) -> void:
		if is_alive():
			combat.deal_damage(src, self, amount, DamageInfo.Type.TRUE, false, element)
	_threat_seconds = float(GameData.setting("enemies", "threat_seconds", 4.0))
	_corpse_seconds = float(GameData.setting("enemies", "corpse_seconds", 2.5))
	health.setup(data.max_hp * hp_multiplier)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	health.changed.connect(_on_health_changed)
	visual.setup(data.model, [], data.model_scale, data.anims, Color(0.75, 0.7, 0.6))
	var pulse: Array = data.get("glow_pulse", [])   ## [niedrig, hoch, Periode]: Eigenleuchten pulsiert (Feuerdrache)
	if pulse.size() == 3:
		visual.pulse_glow(float(pulse[0]), float(pulse[1]), float(pulse[2]))
	var bar_height := float(data.get("bar_height", 0.0))
	health_bar.position.y = bar_height if bar_height > 0.0 else 2.2 * data.model_scale + 0.3
	health_bar.visible = false
	_attack_cooldown = randf_range(0.0, 0.4)
	_ability_left = float(data.ability.get("first_delay", 3.0)) if not data.ability.is_empty() else 0.0
	if not data.boss.is_empty():
		brain = BossBrain.new()
		brain.name = "BossBrain"
		add_child(brain)
		brain.setup(self)
	var spawn_time := visual.play("spawn", 1.6)
	_state_left = minf(spawn_time, 1.2)
	if _state_left <= 0.0:
		state = State.ADVANCE


func is_alive() -> bool:
	return state != State.DEAD


## Rüstung und Magieresistenz inkl. Verstärkung durch einen Boss (Arktischer Schrei: ARMOR_BONUS gilt für beide)
func get_armor() -> float:
	return data.armor + status.magnitude(StatusEffects.ARMOR_BONUS)


func get_magic_resist() -> float:
	return data.magic_resist + status.magnitude(StatusEffects.ARMOR_BONUS)


## Schadensfaktor gegen ein Element (CombatService): 0 = immun, 1.5 = anfällig. Fehlt der Eintrag, gilt 1.
func element_multiplier(element: String) -> float:
	return float(data.get("elements", {}).get(element, 1.0))


func is_immune(element: String) -> bool:
	return element_multiplier(element) <= 0.0


func _physics_process(delta: float) -> void:
	match state:
		State.DEAD:
			_state_left -= delta
			# Leiche versinkt in der letzten Sekunde im Boden statt plötzlich zu verschwinden
			if _state_left < 1.0:
				visual.position.y -= delta * 1.4
			if _state_left <= 0.0:
				queue_free()
			return
		State.SPAWNING:
			_state_left -= delta
			if _state_left <= 0.0:
				state = State.ADVANCE
			return

	# Ziel gelöscht (z. B. Doppelgänger zerfallen): vergessen und zum Kern weiter, statt stehen zu bleiben
	if target != null and not is_instance_valid(target):
		target = core
		_windup_left = -1.0
	if _threat_target != null and not is_instance_valid(_threat_target):
		_threat_target = null
	_attack_cooldown -= delta
	_threat_left -= delta
	_stagger_cooldown -= delta
	# Zusammenzucken hält den Gegner nur an; zurückschlagen darf er trotzdem (sonst lädt jeder Treffer zum Weglaufen ein)
	var staggered := _stagger_left > 0.0
	if staggered:
		_stagger_left -= delta
	if status.is_stunned():
		_windup_left = -1.0
		_cancel_ability()
		velocity = Vector3.ZERO
		return
	if _update_ability(delta):
		velocity = Vector3.ZERO   # während der Ankündigung steht der Gegner still: Zeit zum Ausweichen
		return
	if brain != null and brain.is_casting():
		velocity = Vector3.ZERO
		return
	_update_windup(delta)
	var previous := target
	_choose_target(delta)
	# Wechsel vom Kern auf einen Helden (bemerkt oder angegriffen): schnell schlagbereit statt die Pause eines
	# Schlags auf den Kern abzuwarten. Nur bei diesem Wechsel – im Dauerkampf gilt das normale Angriffsintervall.
	if target is Hero and not (previous is Hero) and _windup_left < 0.0:
		_attack_cooldown = minf(_attack_cooldown, RETALIATE_DELAY)

	var desired := Vector3.ZERO
	var face_point := Vector3.ZERO
	var has_face := false
	if target != null:
		var dist := _distance_to_target()
		if dist <= _attack_reach():
			state = State.ATTACK
			face_point = target.global_position
			has_face = true
			if _attack_cooldown <= 0.0 and _windup_left < 0.0:
				_stagger_left = 0.0   # der Gegenschlag geht dem Zusammenzucken vor
				staggered = false
				_start_attack()
		else:
			state = State.ADVANCE
			if not staggered:
				desired = _advance_direction()

	if spawner != null and not staggered:
		desired += spawner.separation(self) * 0.8
	if desired.length_squared() > 0.0001 and _windup_left < 0.0:
		desired = desired.normalized()
		if not has_face:
			face_point = global_position + desired
			has_face = true
		velocity = desired * float(data.move_speed) * status.move_multiplier() * move_bonus
	else:
		velocity = Vector3.ZERO
	velocity.y = 0.0
	move_and_slide()
	global_position.y = 0.0

	if has_face:
		_face(face_point, delta)
	if _windup_left < 0.0 and not visual.is_busy():
		if velocity.length_squared() > 0.01:
			# Gehtempo passend zur Geschwindigkeit; verlangsamte Gegner bewegen sich sichtbar träger
			visual.play("run", clampf(velocity.length() / maxf(0.1, float(data.move_speed)), 0.4, 1.6))
		else:
			visual.play("idle")


## Zielwahl nach Priorität:
##   0. Taunt: der verspottende Held, solange der Effekt läuft (Bosse: verkürzt über cc_resist)
##   1. Held, der mich angegriffen hat (für threat_seconds, bis Trefferdistanz + 4 m bzw. aggro_leash)
##   2. Held, den ich gerade verfolge oder der in meinen aggro_radius kommt (bis er den aggro_leash verlässt)
##   3. Bauwerk der Karte (Wachturm, Torhaus) in meinem aggro_radius – ich bleibe daran, bis es fällt oder ein Held kommt
##   4. der Kern
## (Taunt kommt in Phase 3 mit höchster Priorität davor.)
func _choose_target(delta: float) -> void:
	if status.has(StatusEffects.TAUNT):
		var taunter := status.source_of(StatusEffects.TAUNT) as Hero
		if taunter != null and taunter.is_alive():
			target = taunter
			return
	if _threat_target != null:
		if _threat_left > 0.0 and _hero_in_range(_threat_target, _threat_leash):
			target = _threat_target
			return
		_threat_target = null
	if target is Hero and _hero_in_range(target, data.aggro_leash):
		return
	_scan_left -= delta
	if _scan_left <= 0.0 and spawner != null:
		_scan_left = SCAN_INTERVAL
		var hero := spawner.nearest_hero(global_position, data.aggro_radius)
		if hero != null:
			target = hero
			return
		var building := spawner.nearest_structure(global_position, data.aggro_radius)
		if building != null:
			target = building
			return
	if target is MapStructure and (target as MapStructure).is_alive():
		return
	target = core if core != null and core.is_alive() else null


func _hero_in_range(hero: Node3D, radius: float) -> bool:
	return is_instance_valid(hero) and hero.is_alive() and not hero.status.has(StatusEffects.UNTARGETABLE) \
		and _flat(hero.global_position - global_position).length() <= radius


## Schlagweite gegen das aktuelle Ziel. Nahkampfgegner erreichen einen Nahkampfhelden mindestens aus dessen
## eigener Reichweite: wer mich treffen kann, den kann ich auch treffen. Sonst schlägt ein Held aus sicherer
## Entfernung zu und ist weg, bevor der Gegner herangetreten ist (Issue #3). Fernkämpfer bleiben auskitebar.
func _attack_reach() -> float:
	var reach: float = data.attack_range
	if data.projectile.is_empty() and target is Hero and (target as Hero).data.projectile.is_empty():
		var hero := target as Hero
		# Held trifft bis Mittenabstand (Reichweite + mein Körper); mein Maß ist Mittenabstand − 0,5
		reach = maxf(reach, hero.stats.attack_range() + body_radius - 0.5 + REACH_MARGIN)
	return reach


func _distance_to_target() -> float:
	var d := _flat(target.global_position - global_position).length()
	if target == core:
		return d - core.radius
	if target is MapStructure:
		return (target as MapStructure).surface_distance(global_position)
	return d - 0.5


func _advance_direction() -> Vector3:
	if target != core:
		return _flat(target.global_position - global_position)
	var to_core := _flat(core.global_position - global_position)
	if to_core.length() < CORE_DIRECT_RANGE + core.radius:
		return to_core
	while _path_index < _path.size():
		var to_wp := _flat(_path[_path_index] - global_position)
		if to_wp.length() > WAYPOINT_REACHED:
			return to_wp
		_path_index += 1
	return to_core


func _start_attack() -> void:
	var interval: float = data.attack_interval / haste
	_attack_cooldown = interval
	_windup_left = data.attack_hit_delay / haste
	_melee_swing = _melee_in_reach()
	var logical := "melee" if _melee_swing else "attack"
	var anim_len := visual.animation_length(logical)
	var speed := maxf(1.0, anim_len / maxf(interval, 0.1)) if anim_len > 0.0 else 1.0
	visual.play(logical, speed, true)


## Hybrid (data.melee): Steht ein Held nah am Körper, schlägt der Fernkämpfer zu statt zu schießen (Eisdrache).
func _melee_in_reach() -> bool:
	if data.get("melee", {}).is_empty() or not (target is Hero):
		return false
	return _flat(target.global_position - global_position).length() <= body_radius + float(data.melee.get("range", 2.0))


func _update_windup(delta: float) -> void:
	if _windup_left < 0.0:
		return
	_windup_left -= delta
	if _windup_left > 0.0:
		return
	_windup_left = -1.0
	if target == null or not is_instance_valid(target) or not target.call("is_alive"):
		return
	if _distance_to_target() > _attack_reach() + 0.8:
		return
	var amount: float = (data.structure_damage if target == core or target is MapStructure else data.damage) * damage_multiplier
	if _melee_swing:
		amount = float(data.melee.get("damage", data.damage)) * damage_multiplier
	amount *= 1.0 + status.magnitude(StatusEffects.EMPOWER)   # Drachengebrüll stärkt die Diener
	if data.projectile.is_empty() or _melee_swing:
		combat.deal_damage(self, target, amount, DamageInfo.Type.PHYSICAL)
		_apply_on_hit(target)
		return
	# Fernkampf: Geschoss fliegt zum Ziel, Schaden beim Einschlag (hit_target)
	var p := Projectile.new()
	get_parent().add_child(p)
	p.launch(self, target, combat, amount, DamageInfo.Type.MAGIC, false, {},
		global_position + Vector3(0, 1.5 * data.model_scale, 0) - global_basis.z * float(data.projectile.get("forward", 0.5)),
		float(data.projectile.get("speed", 14.0)), Color.html(String(data.projectile.get("color", "#7dff9a"))))


## Einschlag eines eigenen Geschosses (von Projectile aufgerufen).
func hit_target(t: Node3D, amount: float, _crit: bool) -> void:
	var element := String(data.projectile.get("element", ""))
	if is_instance_valid(t):
		combat.deal_damage(self, t, amount, DamageInfo.Type.MAGIC, false, element)
		_apply_on_hit(t)
	# Flächenschaden (Feuerball): weitere Helden im Umkreis nehmen halben Schaden, Explosion am Einschlag
	var splash := float(data.projectile.get("splash", 0.0))
	if splash <= 0.0 or spawner == null:
		return
	var center: Vector3 = t.global_position if is_instance_valid(t) else global_position
	for h: Hero in spawner.heroes:
		if h == t or not is_instance_valid(h) or not h.is_alive():
			continue
		if _flat(h.global_position - center).length() <= splash:
			combat.deal_damage(self, h, amount * 0.5, DamageInfo.Type.MAGIC, false, element)
			_apply_on_hit(h)
	if world != null:
		world.vfx.fire_explosion(center + Vector3(0, 0.6, 0), splash)


## Passiver Treffereffekt (data.on_hit), z. B. Unterkühlung des Eisdrachen: bremst Lauf- und Angriffstempo des Helden.
func _apply_on_hit(t: Node3D) -> void:
	var oh: Dictionary = data.get("on_hit", {})
	if oh.is_empty() or not (t is Hero) or not is_instance_valid(t) or not (t as Hero).is_alive():
		return
	var hero := t as Hero
	var duration := float(oh.get("duration", 2.0))
	if float(oh.get("slow", 0.0)) > 0.0:
		hero.status.apply(StatusEffects.SLOW, duration, float(oh.slow), self)
	if float(oh.get("attack_slow", 0.0)) > 0.0:
		hero.status.apply(StatusEffects.CHILL, duration, float(oh.attack_slow), self)
	if float(oh.get("burn_dps", 0.0)) > 0.0:   # Feuerpest: Verbrennung über Zeit
		hero.status.apply(StatusEffects.BURN, float(oh.get("burn_time", 3.0)), float(oh.burn_dps) * damage_multiplier, self)


# --- Zusatzfähigkeit (Elite, Mini-Boss) ---------------------------------------
# "stomp": Ist ein Held in Reichweite, kündigt der Gegner einen Bodenschlag mit rotem Warnkreis an
# (windup Sekunden, er steht dabei still). Danach nehmen alle Helden im Kreis Schaden und werden verlangsamt.

## Gibt true zurück, solange die Fähigkeit angekündigt wird.
func _update_ability(delta: float) -> bool:
	var ab: Dictionary = data.ability
	if ab.is_empty():
		return false
	if _ability_windup >= 0.0:
		_ability_windup -= delta
		if _ability_windup <= 0.0:
			_ability_windup = -1.0
			_fire_ability()
			return false
		return true
	_ability_left -= delta
	if _ability_left > 0.0 or _windup_left >= 0.0 or spawner == null:
		return false
	var trigger := float(ab.get("trigger", float(ab.get("radius", 3.0)) * 0.8))
	if spawner.nearest_hero(global_position, trigger) == null:
		return false
	_ability_windup = float(ab.get("windup", 1.0))
	_ability_left = float(ab.get("cooldown", 8.0))
	var r := float(ab.get("radius", 3.0))
	if world != null:
		world.vfx.ring(global_position, r, r, Color(1.0, 0.25, 0.15, 0.9), _ability_windup, 0.22)
		world.vfx.decal(global_position, "rune_circle", r * 0.95, Color(1.0, 0.2, 0.1, 0.6), _ability_windup + 0.1, 0.2)
	var anim := String(ab.get("anim", "2H_Melee_Attack_Chop"))
	if visual.anim_player != null and visual.anim_player.has_animation(anim):
		# Animation so takten, dass der Schlag (etwa 60 % der Animation) mit dem Auslösen zusammenfällt
		var length := visual.anim_player.get_animation(anim).length
		visual.play_action(anim, maxf(0.3, length * 0.6 / maxf(0.1, _ability_windup)))
	return true


func _cancel_ability() -> void:
	_ability_windup = -1.0


func _fire_ability() -> void:
	var ab: Dictionary = data.ability
	var r := float(ab.get("radius", 3.0))
	for h: Hero in spawner.heroes:
		if not is_instance_valid(h) or not h.is_alive():
			continue
		if _flat(h.global_position - global_position).length() > r:
			continue
		combat.deal_damage(self, h, float(ab.get("damage", 40.0)) * damage_multiplier, DamageInfo.Type.PHYSICAL)
		if float(ab.get("max_hp_pct", 0.0)) > 0.0 and h.is_alive():   # Mini-Boss: Anteil der maximalen Leben als wahrer Schaden
			combat.deal_damage(self, h, h.health.max_hp * float(ab.max_hp_pct), DamageInfo.Type.TRUE)
		if float(ab.get("slow", 0.0)) > 0.0:
			h.status.apply(StatusEffects.SLOW, float(ab.get("slow_time", 2.0)), float(ab.get("slow", 0.0)), self)
	if world != null:
		world.vfx.shockwave(global_position, r, Color(1.0, 0.45, 0.25), 0.45)
		world.vfx.smoke_cloud(global_position + Vector3(0, 0.3, 0), Color(0.45, 0.38, 0.3, 0.85), r * 0.45, 0.0, 10, 1.0)
		world.vfx.decal(global_position, "scorch_03", r * 0.7, Color(0.15, 0.1, 0.08, 0.8), 2.5, 0.0, false)
		world.camera_rig.shake(0.25)
		world.match_audio.play_at("enemy_stomp", global_position)


func _on_damaged(info: DamageInfo) -> void:
	visual.flash()
	# Spürbare Treffer (nicht Gift-Ticks): kurzes Zusammenzucken. Ein laufender Schlag wird nicht abgebrochen.
	var noticeable := info.type != DamageInfo.Type.TRUE and info.final_amount >= health.max_hp * STAGGER_MIN_RATIO
	if state != State.SPAWNING and is_alive() and _windup_left < 0.0 and _ability_windup < 0.0 and noticeable and _stagger_cooldown <= 0.0:   # angekündigter Bodenschlag wird nicht weggezuckt
		_stagger_left = STAGGER_SECONDS
		_stagger_cooldown = STAGGER_COOLDOWN
		visual.play("hit", 1.8, true)
	if info.source_is_valid() and info.source is Hero:
		_threat_target = info.source
		_threat_left = _threat_seconds
		# Fernkämpfer (z. B. Arcanist aus 9 m) werden über ihre Schussdistanz hinaus verfolgt,
		# sonst würde der Gegner den Angreifer sofort vergessen und zum Kern weiterlaufen.
		var dist := _flat((info.source as Hero).global_position - global_position).length()
		_threat_leash = maxf(float(data.aggro_leash), dist + THREAT_LEASH_MARGIN)


## Eine Einheit verschwindet (Doppelgänger zerfällt): nicht mehr verfolgen, zurück zum Kern bzw. zum nächsten Ziel.
func forget(unit: Node) -> void:
	if target == unit:
		target = core
		_windup_left = -1.0
	if _threat_target == unit:
		_threat_target = null


## Sofortiger Zielwechsel bei Taunt (sonst erst beim nächsten Frame) und Abbruch eines laufenden Schlags auf ein anderes Ziel.
func on_taunted() -> void:
	var previous := target
	_choose_target(0.0)
	if previous != target:
		_windup_left = -1.0


func _on_status_changed() -> void:
	if status.is_stunned():
		visual.set_tint(Color(1.0, 0.9, 0.3, 0.35))
	elif status.has(StatusEffects.TAUNT):
		visual.set_tint(Color(1.0, 0.3, 0.25, 0.35))
	elif status.has(StatusEffects.SLOW):
		visual.set_tint(Color(0.4, 0.7, 1.0, 0.35))
	elif status.has(StatusEffects.POISON):
		visual.set_tint(Color(0.4, 0.9, 0.3, 0.35))
	else:
		visual.set_tint(Color.TRANSPARENT)


func _on_health_changed(current: float, maximum: float) -> void:
	health_bar.visible = current < maximum and current > 0.0
	health_bar.set_instance_shader_parameter("fill", current / maximum)


func _on_died(info: DamageInfo) -> void:
	state = State.DEAD
	_windup_left = -1.0
	_state_left = _corpse_seconds
	velocity = Vector3.ZERO
	collision.set_deferred("disabled", true)
	health_bar.visible = false
	visual.play("death")
	died.emit(self, info)


## Am Rundenende: Gegner jubeln und bleiben stehen.
func celebrate() -> void:
	if state == State.DEAD:
		return
	set_physics_process(false)
	visual.play("cheer")


func _face(point: Vector3, delta: float) -> void:
	var dir := _flat(point - global_position)
	if dir.length_squared() < 0.0001:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), clampf(10.0 * delta, 0.0, 1.0))


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
