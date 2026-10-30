class_name BossBrain
extends Node
## Steuerung des Endbosses (Kind des Boss-Gegners). Drei Phasen nach Lebenspunkten (data.boss.phase_hp):
##   Phase 1: beschwört Skelette (Beschwörungskreise erscheinen vorher am Boden)
##   Phase 2: zusätzlich Seelenfeuer – Kreise unter den Helden, nach der Vorwarnung Explosion
##   Phase 3: Raserei (schneller) und Todeswelle – ein Ring wächst um den Boss, danach Schaden im ganzen Kreis
## Jede Fähigkeit wird sichtbar angekündigt; wer rechtzeitig ausweicht, bleibt unverletzt.
## Stirbt der Boss, zerfallen seine Beschwörungen.
## Welche Fähigkeiten ein Boss hat, steht in seinen Daten (fehlender Eintrag = Fähigkeit aus). Eisdrache (Issue #9):
##   frost_breath: Eisfeuer-Odem – Kegel vor dem Drachen (Vorwarnung am Boden), Frostschaden, starke Verlangsamung
##   blizzard:     Schneesturm an einem Helden – Schaden im Takt, Erfrierung stapelt, bei voller Zahl eingefroren
##   frost_roar:   Arktischer Schrei – Helden im großen Umkreis langsamer (Laufen und Angriff), Gegner gepanzert

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
var _breath_left := 0.0
var _blizzard_left := 0.0
var _roar_left := 0.0
var _cast_left := 0.0            ## > 0: Boss steht und wirkt (Beschwörung, Todeswelle, Odem, Schrei)
var _pending: Array[Dictionary] = []   ## {time, kind, pos}
var _storms: Array[Dictionary] = []    ## laufende Schneestürme {pos, left, tick}


func setup(p_boss: Enemy) -> void:
	boss = p_boss
	cfg = boss.data.boss
	_summon_left = float(_phase_value("summon", "first_delay", 4.0))
	_soulfire_left = float(cfg.get("soulfire", {}).get("first_delay", 2.0))
	_wave_left = float(cfg.get("deathwave", {}).get("first_delay", 3.0))
	_breath_left = float(cfg.get("frost_breath", {}).get("first_delay", 4.0))
	_blizzard_left = float(cfg.get("blizzard", {}).get("first_delay", 2.0))
	_roar_left = float(cfg.get("frost_roar", {}).get("first_delay", 8.0))
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
	_process_storms(delta)
	if boss.status.is_stunned():
		return
	if cfg.has("summon"):
		_summon_left -= delta
		if _summon_left <= 0.0 and _cast_left <= 0.0:
			_start_summon()
	if _active("soulfire", 2):
		_soulfire_left -= delta
		if _soulfire_left <= 0.0:
			_start_soulfire()
	if _active("deathwave", 3):
		_wave_left -= delta
		if _wave_left <= 0.0 and _cast_left <= 0.0:
			_start_deathwave()
	if _active("frost_breath", 1):
		_breath_left -= delta
		if _breath_left <= 0.0 and _cast_left <= 0.0:
			_start_breath()
	if _active("blizzard", 2):
		_blizzard_left -= delta
		if _blizzard_left <= 0.0:
			_start_blizzard()
	if _active("frost_roar", 1):
		_roar_left -= delta
		if _roar_left <= 0.0 and _cast_left <= 0.0:
			_start_roar()


## Fähigkeit vorhanden und ab dieser Phase freigeschaltet (from_phase in den Daten, sonst `default_phase`)?
func _active(ability: String, default_phase: int) -> bool:
	return cfg.has(ability) and phase >= int(cfg[ability].get("from_phase", default_phase))


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
	boss.visual.play_action(String(cfg.get("phase_anim", "Taunt")), 1.2)
	var w = boss.world
	if w != null:
		var c := _color()
		w.vfx.shockwave(boss.global_position, 6.0, c.lightened(0.2), 0.6)
		w.vfx.energy_burst(boss.global_position + Vector3(0, 2.0, 0), c, 4.0, 0.6)
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
			"breath": _release_breath(p.pos, p.dir, p.target_dist)
			"breath_hit": _breath_hit(p.hero)
			"blizzard": _begin_storm(p.pos)
			"roar": _release_roar(p.pos)


func _hit_heroes(pos: Vector3, radius: float, damage: float, element := "") -> Array[Hero]:
	var hit := _heroes_in(pos, radius)
	for h in hit:
		boss.combat.deal_damage(boss, h, damage * boss.damage_multiplier, DamageInfo.Type.MAGIC, false, element)
	return hit


func _heroes_in(pos: Vector3, radius: float) -> Array[Hero]:
	var result: Array[Hero] = []
	for h: Hero in boss.spawner.heroes:
		if not is_instance_valid(h) or not h.is_alive():
			continue
		if Vector2(h.global_position.x - pos.x, h.global_position.z - pos.z).length() <= radius:
			result.append(h)
	return result


## Lauf- und Angriffstempo eines Helden bremsen (Frostfähigkeiten des Eisdrachen)
func _chill(h: Hero, slow: float, attack_slow: float, duration: float) -> void:
	if slow > 0.0:
		h.status.apply(StatusEffects.SLOW, duration, slow, boss)
	if attack_slow > 0.0:
		h.status.apply(StatusEffects.CHILL, duration, attack_slow, boss)


## Leitfarbe des Bosses für Phasen-Effekte (Morvath grün, Eisdrache eisblau)
func _color() -> Color:
	return Color.html(String(cfg.get("color", "#8cff73")))


## Nächster lebender, angreifbarer Held im Umkreis (für gezielte Fähigkeiten)
func _nearest_hero(radius: float) -> Hero:
	var best: Hero = null
	var best_d := radius
	for h: Hero in boss.spawner.heroes:
		if not is_instance_valid(h) or not h.is_alive() or h.status.has(StatusEffects.UNTARGETABLE):
			continue
		var d := _flat(h.global_position - boss.global_position).length()
		if d <= best_d:
			best = h
			best_d = d
	return best


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


# --- Eisfeuer-Odem (Eisdrache) --------------------------------------------------------

func _start_breath() -> void:
	var fb: Dictionary = cfg.frost_breath
	var reach := float(fb.get("range", 9.0))
	var target := _nearest_hero(reach)
	if target == null:
		_breath_left = 1.0   # niemand in Reichweite: bald erneut prüfen
		return
	_breath_left = float(_phase_value("frost_breath", "cooldown", 9.0))
	var warn := float(fb.get("warning", 1.0))
	var dir := _flat(target.global_position - boss.global_position).normalized()
	boss.rotation.y = atan2(-dir.x, -dir.z)   # sofort zum Ziel drehen: der Kegel liegt dann genau vor dem Maul
	_cast_left = warn + float(fb.get("breath_time", 0.9))
	var anim := String(fb.get("anim", "Fire_Breath"))
	if boss.visual.anim_player != null and boss.visual.anim_player.has_animation(anim):
		boss.visual.play_action(anim, boss.visual.anim_player.get_animation(anim).length / maxf(0.3, _cast_left))
	# Zielpunkt des Einschlags: wo der Held bei der Ankündigung steht (höchstens bis zur Reichweite)
	var target_dist := clampf(_flat(target.global_position - boss.global_position).length(), boss.body_radius + 2.0, reach)
	_pending.append({"time": warn, "kind": "breath", "pos": boss.global_position, "dir": dir, "target_dist": target_dist})
	if boss.world != null:
		boss.world.vfx.cone_indicator(boss.global_position, dir, reach, float(fb.get("angle", 70.0)), Color(0.55, 0.85, 1.0, 0.9), warn)
		boss.world.vfx.ice_charge(_mouth(boss.global_position, dir), warn, 1.2)   # 1. Magie sammelt sich im Maul
		boss.world.match_audio.play_at("cast_frost_nova", boss.global_position)


func _mouth(pos: Vector3, dir: Vector3) -> Vector3:
	return pos + dir * (boss.body_radius + 0.4) + Vector3(0, 1.3 * boss.data.model_scale, 0)


## Odem losgelassen: Zapfen fliegen aus dem Maul, Stacheln laufen mit spike_speed nach vorn. Ein Held im Kegel nimmt
## Schaden, sobald die Stacheln ihn erreichen (wer bei der Ankündigung im Kegel stand, wird getroffen).
func _release_breath(pos: Vector3, dir: Vector3, target_dist: float) -> void:
	var fb: Dictionary = cfg.frost_breath
	var reach := float(fb.get("range", 9.0))
	var half := deg_to_rad(float(fb.get("angle", 70.0)) * 0.5)
	var speed := float(fb.get("spike_speed", 22.0))
	var start := boss.body_radius * 0.8
	for h in _heroes_in(pos, reach):
		var to := _flat(h.global_position - pos)
		if to.length() > 0.3 and dir.angle_to(to.normalized()) > half:
			continue
		var arrival := maxf(0.0, to.length() - start) / speed + VfxLayer.ICICLE_FLIGHT
		_pending.append({"time": arrival, "kind": "breath_hit", "pos": pos, "hero": h})
	if boss.world != null:
		var hold := float(fb.get("breath_time", 0.9))
		boss.world.vfx.ice_spike_path(pos + dir * start, dir, reach - start, float(fb.get("angle", 70.0)), hold, speed,
			_mouth(pos, dir))
		var impact := pos + dir * target_dist
		boss.world.vfx.ice_impact(impact, 1.8, hold, (target_dist - start) / speed + VfxLayer.ICICLE_FLIGHT)


func _breath_hit(h: Variant) -> void:
	if not is_instance_valid(h) or not (h as Hero).is_alive():
		return
	var fb: Dictionary = cfg.frost_breath
	boss.combat.deal_damage(boss, h, float(fb.get("damage", 90.0)) * boss.damage_multiplier, DamageInfo.Type.MAGIC, false, "ice")
	_chill(h, float(fb.get("slow", 0.6)), float(fb.get("attack_slow", 0.4)), float(fb.get("slow_time", 2.5)))


# --- Schneesturm (Eisdrache) ------------------------------------------------------------

func _start_blizzard() -> void:
	var bz: Dictionary = cfg.blizzard
	_blizzard_left = float(_phase_value("blizzard", "cooldown", 12.0))
	var candidates := _heroes_in(boss.global_position, SOULFIRE_RANGE).filter(func(h: Hero) -> bool:
		return not h.status.has(StatusEffects.UNTARGETABLE))
	if candidates.is_empty():
		_blizzard_left = 1.0
		return
	var pos: Vector3 = candidates.pick_random().global_position
	var warn := float(bz.get("warning", 1.0))
	var r := float(bz.get("radius", 4.0))
	_pending.append({"time": warn, "kind": "blizzard", "pos": pos})
	if boss.world != null:
		boss.world.vfx.ring(pos, r, r, Color(0.6, 0.9, 1.0, 0.95), warn, 0.22)
		boss.world.vfx.ring(pos, 0.3, r, Color(0.5, 0.8, 1.0, 0.7), warn, 0.12)
		boss.world.vfx.decal(pos, "rune_circle", r * 0.95, Color(0.5, 0.85, 1.0, 0.6), warn + 0.1, 0.3)


func _begin_storm(pos: Vector3) -> void:
	var bz: Dictionary = cfg.blizzard
	var duration := float(bz.get("duration", 5.0))
	var r := float(bz.get("radius", 4.0))
	_storms.append({"pos": pos, "left": duration, "tick": 0.0})
	if boss.world != null:
		boss.world.vfx.blizzard(pos, r, duration)
		boss.world.vfx.ring(pos, r, r, Color(0.65, 0.9, 1.0, 0.8), duration, 0.15)
		boss.world.match_audio.play_at("cast_glacial_rift", pos)


## Laufende Schneestürme: im Takt Schaden, Bremse und ein Stapel Erfrierung; bei voller Zahl friert der Held ein.
func _process_storms(delta: float) -> void:
	if _storms.is_empty():
		return
	var bz: Dictionary = cfg.get("blizzard", {})
	var interval := float(bz.get("interval", 0.5))
	var freeze_stacks := int(bz.get("freeze_stacks", 6))
	for s in _storms:
		s.left -= delta
		s.tick -= delta
		while s.tick <= 0.0 and s.left > 0.0:
			s.tick += interval
			for h in _hit_heroes(s.pos, float(bz.get("radius", 4.0)), float(bz.get("damage", 14.0)), "ice"):
				_chill(h, float(bz.get("slow", 0.35)), 0.0, interval + 0.6)
				if h.status.has(StatusEffects.STUN):
					continue   # schon eingefroren
				var stacks := h.status.apply_stacking(StatusEffects.FROSTBITE, float(bz.get("stack_time", 2.0)), 0.0, freeze_stacks, boss)
				if stacks >= freeze_stacks:
					h.status.remove(StatusEffects.FROSTBITE)
					h.status.apply(StatusEffects.STUN, float(bz.get("freeze_time", 1.5)), 0.0, boss)
					if boss.world != null:
						boss.world.vfx.ice_shards(h.global_position, 1.3, 8, float(bz.get("freeze_time", 1.5)))
						boss.world.match_audio.play_at("ice_shatter", h.global_position)
	_storms = _storms.filter(func(s: Dictionary) -> bool: return s.left > 0.0)


# --- Arktischer Schrei (Eisdrache) --------------------------------------------------------

func _start_roar() -> void:
	var fr: Dictionary = cfg.frost_roar
	_roar_left = float(_phase_value("frost_roar", "cooldown", 18.0))
	var warn := float(fr.get("warning", 0.8))
	var r := float(fr.get("radius", 14.0))
	_cast_left = warn + 0.6
	var anim := String(fr.get("anim", "Roar"))
	if boss.visual.anim_player != null and boss.visual.anim_player.has_animation(anim):
		# Höhepunkt des Brüllens (etwa Mitte der Animation) fällt auf das Auslösen
		boss.visual.play_action(anim, maxf(0.5, boss.visual.anim_player.get_animation(anim).length * 0.5 / maxf(0.2, warn)))
	_pending.append({"time": warn, "kind": "roar", "pos": boss.global_position})
	if boss.world != null:
		boss.world.vfx.ring(boss.global_position, r, r, Color(0.6, 0.9, 1.0, 0.9), warn, 0.2)
		boss.world.vfx.ring(boss.global_position, 0.5, r, Color(0.5, 0.8, 1.0, 0.6), warn, 0.12)


func _release_roar(pos: Vector3) -> void:
	var fr: Dictionary = cfg.frost_roar
	var r := float(fr.get("radius", 14.0))
	for h in _heroes_in(pos, r):
		_chill(h, float(fr.get("slow", 0.4)), float(fr.get("attack_slow", 0.4)), float(fr.get("duration", 4.0)))
	var armor := float(fr.get("ally_armor", 25.0))
	var allies: Array[Enemy] = boss.spawner.enemies_in_radius(pos, r)
	for e in allies:
		if e != boss and e.is_alive():
			e.status.apply(StatusEffects.ARMOR_BONUS, float(fr.get("ally_duration", 6.0)), armor, boss)
			if boss.world != null:
				boss.world.vfx.sparkles(e.global_position + Vector3(0, 0.8, 0), Color(0.6, 0.9, 1.0), 10, 0.6, 1.0)
	if boss.world != null:
		boss.world.vfx.shockwave(pos, r, Color(0.6, 0.9, 1.0), 0.7)
		boss.world.vfx.shockwave(pos, r * 0.6, Color(0.9, 0.97, 1.0), 0.9)
		boss.world.vfx.smoke_cloud(pos + Vector3(0, 0.5, 0), Color(0.85, 0.93, 1.0, 0.7), 3.0, 0.0, 14, 1.2)
		boss.world.camera_rig.shake(0.45)
		boss.world.match_audio.play_at("warcry", pos)


func _on_boss_died() -> void:
	_pending.clear()
	_storms.clear()
	for s in summons:
		if is_instance_valid(s) and s.is_alive():
			s.combat.deal_damage(null, s, s.health.hp + 1.0, DamageInfo.Type.TRUE)   # Beschwörungen zerfallen
	defeated.emit()
