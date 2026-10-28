class_name BossBrain
extends Node
## Steuerung des Endbosses (Kind des Boss-Gegners). Drei Phasen nach Lebenspunkten (data.boss.phase_hp):
##   Phase 1: beschwört Skelette (Beschwörungskreise erscheinen vorher am Boden)
##   Phase 2: zusätzlich Seelenfeuer – Kreise unter den Helden, nach der Vorwarnung Explosion
##   Phase 3: Raserei (schneller) und Todeswelle – ein Ring wächst um den Boss, danach Schaden im ganzen Kreis
## Jede Fähigkeit wird sichtbar angekündigt; wer rechtzeitig ausweicht, bleibt unverletzt.
## Stirbt der Boss, zerfallen seine Beschwörungen.

signal phase_changed(phase: int, title: String, subtitle: String)
signal defeated

const SUMMON_RING := 2.6        ## Abstand der Beschwörungen zum Boss
const SOULFIRE_RANGE := 22.0    ## Helden in diesem Umkreis können zum Ziel werden

var boss: Enemy
var cfg: Dictionary = {}
var phase := 1
var summons: Array[Enemy] = []
var _summon_left := 0.0
var _soulfire_left := 0.0
var _wave_left := 0.0
var _cast_left := 0.0            ## > 0: Boss steht und wirkt (Beschwörung, Todeswelle)
var _pending: Array[Dictionary] = []   ## {time, kind, pos}


func setup(p_boss: Enemy) -> void:
	boss = p_boss
	cfg = boss.data.boss
	_summon_left = float(_phase_value("summon", "first_delay", 4.0))
	_soulfire_left = float(cfg.get("soulfire", {}).get("first_delay", 2.0))
	_wave_left = float(cfg.get("deathwave", {}).get("first_delay", 3.0))
	boss.health.changed.connect(_on_health_changed)
	boss.died.connect(func(_e: Enemy, _i: DamageInfo) -> void: _on_boss_died())


func is_casting() -> bool:
	return _cast_left > 0.0


func title() -> String:
	return String(cfg.get("title", boss.data.name))


func _physics_process(delta: float) -> void:
	if boss == null or not boss.is_alive() or boss.state == Enemy.State.SPAWNING:
		return
	_cast_left = maxf(0.0, _cast_left - delta)
	_process_pending(delta)
	if boss.status.is_stunned():
		return
	_summon_left -= delta
	if _summon_left <= 0.0 and _cast_left <= 0.0:
		_start_summon()
	if phase >= int(cfg.get("soulfire", {}).get("from_phase", 2)):
		_soulfire_left -= delta
		if _soulfire_left <= 0.0:
			_start_soulfire()
	if phase >= int(cfg.get("deathwave", {}).get("from_phase", 3)):
		_wave_left -= delta
		if _wave_left <= 0.0 and _cast_left <= 0.0:
			_start_deathwave()


# --- Phasen ---------------------------------------------------------------------

func _on_health_changed(current: float, maximum: float) -> void:
	var ratio := current / maxf(1.0, maximum)
	var thresholds: Array = cfg.get("phase_hp", [0.66, 0.33])
	var target_phase := 1
	for t in thresholds:
		if ratio <= float(t):
			target_phase += 1
	while phase < target_phase and boss.is_alive():
		_enter_phase(phase + 1)


func _enter_phase(p: int) -> void:
	phase = p
	var texts: Array = cfg.get("phase_texts", [])
	var text: Array = texts[p - 1] if p - 1 < texts.size() else ["Phase %d" % p, ""]
	if p >= 3:
		var enrage: Dictionary = cfg.get("enrage", {})
		boss.haste = float(enrage.get("attack_speed", 1.5))
		boss.move_bonus = float(enrage.get("move", 1.25))
		boss.visual.set_tint(Color(1.0, 0.25, 0.2, 0.25))
	_summon_left = minf(_summon_left, 1.5)   # neue Phase beginnt mit einer Beschwörung
	_cast_left = maxf(_cast_left, 1.0)
	boss.visual.play_action("Taunt", 1.2)
	var w = boss.world
	if w != null:
		w.vfx.shockwave(boss.global_position, 6.0, Color(0.6, 1.0, 0.5), 0.6)
		w.vfx.energy_burst(boss.global_position + Vector3(0, 2.0, 0), Color(0.55, 1.0, 0.45), 4.0, 0.6)
		w.camera_rig.shake(0.35)
		w.match_audio.play_at("boss_phase", boss.global_position)
	phase_changed.emit(p, String(text[0]), String(text[1]) if text.size() > 1 else "")


func _phase_value(ability: String, key: String, fallback: Variant) -> Variant:
	var a: Dictionary = cfg.get(ability, {})
	var v: Variant = a.get(key, fallback)
	if v is Array:
		var arr := v as Array
		return arr[clampi(phase - 1, 0, arr.size() - 1)] if not arr.is_empty() else fallback
	return v


# --- Beschwörung ------------------------------------------------------------------

func _start_summon() -> void:
	var list: Array = _phase_value("summon", "enemies", ["grunt", "grunt"])
	var warn := float(cfg.get("summon", {}).get("warning", 1.2))
	_summon_left = float(_phase_value("summon", "cooldown", 12.0))
	_cast_left = warn
	boss.visual.play_action("Spellcast_Summon", 1.0)
	var base := randf() * TAU
	for i in list.size():
		var a := base + TAU * i / list.size()
		var pos := boss.global_position + Vector3(cos(a), 0.0, sin(a)) * SUMMON_RING
		_pending.append({"time": warn, "kind": "summon", "pos": pos, "enemy": String(list[i])})
		if boss.world != null:
			boss.world.vfx.decal(pos, "rune_circle", 0.9, Color(0.5, 1.0, 0.45, 0.85), warn + 0.2, 0.6)
	if boss.world != null:
		boss.world.match_audio.play_at("boss_summon", boss.global_position)


func _summon(pos: Vector3, enemy_id: String) -> void:
	var e := boss.spawner.spawn_at(enemy_id, pos)
	if e == null:
		return
	summons.append(e)
	if boss.world != null:
		boss.world.vfx.energy_burst(pos + Vector3(0, 1.0, 0), Color(0.5, 1.0, 0.45), 1.8, 0.4)


# --- Seelenfeuer -------------------------------------------------------------------

func _start_soulfire() -> void:
	var sf: Dictionary = cfg.get("soulfire", {})
	_soulfire_left = float(_phase_value("soulfire", "cooldown", 6.0))
	var warn := float(sf.get("warning", 1.5))
	var r := float(sf.get("radius", 2.5))
	var heroes := boss.spawner.heroes.filter(func(h: Hero) -> bool:
		return is_instance_valid(h) and h.is_alive() and not h.status.has(StatusEffects.UNTARGETABLE) \
			and h.global_position.distance_to(boss.global_position) <= SOULFIRE_RANGE)
	heroes.shuffle()
	for i in mini(int(sf.get("targets", 3)), heroes.size()):
		var pos: Vector3 = heroes[i].global_position
		_pending.append({"time": warn, "kind": "soulfire", "pos": pos})
		if boss.world != null:
			boss.world.vfx.ring(pos, r, r, Color(0.55, 1.0, 0.35, 0.95), warn, 0.22)
			boss.world.vfx.ring(pos, 0.3, r, Color(0.4, 0.9, 0.3, 0.7), warn, 0.12)
			boss.world.vfx.decal(pos, "rune_circle", r * 0.95, Color(0.45, 1.0, 0.35, 0.7), warn + 0.1, 0.3)


func _explode_soulfire(pos: Vector3) -> void:
	var sf: Dictionary = cfg.get("soulfire", {})
	var r := float(sf.get("radius", 2.5))
	_hit_heroes(pos, r, float(sf.get("damage", 70.0)))
	if boss.world != null:
		boss.world.vfx.energy_burst(pos + Vector3(0, 0.8, 0), Color(0.45, 1.0, 0.35), r * 1.4, 0.5)
		boss.world.vfx.smoke_cloud(pos + Vector3(0, 0.4, 0), Color(0.2, 0.45, 0.15, 0.75), r * 0.5, 0.0, 8, 1.2)
		boss.world.vfx.decal(pos, "scorch_03", r * 0.8, Color(0.08, 0.15, 0.05, 0.8), 3.0, 0.0, false)
		boss.world.match_audio.play_at("boss_soulfire", pos)


# --- Todeswelle --------------------------------------------------------------------

func _start_deathwave() -> void:
	var dw: Dictionary = cfg.get("deathwave", {})
	_wave_left = float(_phase_value("deathwave", "cooldown", 10.0))
	var warn := float(dw.get("warning", 2.0))
	var r := float(dw.get("radius", 9.0))
	_cast_left = warn + 0.3
	boss.visual.play_action("Spellcast_Long", 1.0)
	_pending.append({"time": warn, "kind": "deathwave", "pos": boss.global_position})
	if boss.world != null:
		boss.world.vfx.ring(boss.global_position, r, r, Color(0.7, 0.2, 1.0, 0.95), warn, 0.25)        # Grenze
		boss.world.vfx.ring(boss.global_position, 0.5, r, Color(0.6, 0.15, 0.9, 0.7), warn, 0.15)      # wachsende Welle
		boss.world.vfx.decal(boss.global_position, "rune_circle", r * 0.6, Color(0.6, 0.2, 1.0, 0.6), warn + 0.2, 0.3)
		boss.world.match_audio.play_at("boss_deathwave_charge", boss.global_position)


func _release_deathwave(pos: Vector3) -> void:
	var dw: Dictionary = cfg.get("deathwave", {})
	var r := float(dw.get("radius", 9.0))
	_hit_heroes(pos, r, float(dw.get("damage", 110.0)))
	if boss.world != null:
		boss.world.vfx.shockwave(pos, r, Color(0.7, 0.25, 1.0), 0.6)
		boss.world.vfx.shockwave(pos, r * 0.7, Color(0.9, 0.6, 1.0), 0.8)
		boss.world.vfx.energy_burst(pos + Vector3(0, 1.5, 0), Color(0.65, 0.25, 1.0), 5.0, 0.6)
		boss.world.camera_rig.shake(0.5)
		boss.world.match_audio.play_at("boss_deathwave", pos)


# --- Hilfen ---------------------------------------------------------------------------

func _process_pending(delta: float) -> void:
	for p in _pending:
		p.time -= delta
	var due := _pending.filter(func(p: Dictionary) -> bool: return p.time <= 0.0)
	_pending = _pending.filter(func(p: Dictionary) -> bool: return p.time > 0.0)
	for p in due:
		match String(p.kind):
			"summon": _summon(p.pos, p.enemy)
			"soulfire": _explode_soulfire(p.pos)
			"deathwave": _release_deathwave(p.pos)


func _hit_heroes(pos: Vector3, radius: float, damage: float) -> void:
	for h: Hero in boss.spawner.heroes:
		if not is_instance_valid(h) or not h.is_alive():
			continue
		var d := Vector2(h.global_position.x - pos.x, h.global_position.z - pos.z).length()
		if d <= radius:
			boss.combat.deal_damage(boss, h, damage * boss.damage_multiplier, DamageInfo.Type.MAGIC)


func _on_boss_died() -> void:
	_pending.clear()
	for s in summons:
		if is_instance_valid(s) and s.is_alive():
			s.combat.deal_damage(null, s, s.health.hp + 1.0, DamageInfo.Type.TRUE)   # Beschwörungen zerfallen
	defeated.emit()
