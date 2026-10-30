class_name AbilityEffects
extends RefCounted
## Wirkung jeder Fähigkeit. Alle Zahlen kommen aus data/skills/skills.json (Stufe 1–3);
## hier steht nur, WAS passiert und wie es aussieht. Schaden läuft über den CombatService,
## Kontrolle über StatusEffects, Beteiligung (Kontrolle) wird dem RewardService gemeldet.
## Aussehen: Bausteine des VfxLayer mit eigenen Blender-Texturen (Energie, Rauch, Druckwelle,
## Runenkreis, Lichtsäule, Funkeln, Blitz, Eiskristalle, Feuer).
##
## Wirkwert = Basis × Fähigkeitsstärke + Σ scaling[Attribut] × Attribut (nur für scaled_keys)

const HEAL_COLOR := Color(0.45, 1.0, 0.55)
const GOLD := Color(1.0, 0.82, 0.35)
const FROST := Color(0.55, 0.85, 1.0)
const SHADOW := Color(0.7, 0.45, 1.0)
const POISON := Color(0.45, 0.95, 0.35)
const ARCANE := Color(0.5, 0.8, 1.0)
const RAGE := Color(1.0, 0.3, 0.2)
const DUST := Color(0.45, 0.38, 0.3, 0.85)
const SHADOW_SMOKE := Color(0.22, 0.1, 0.32, 0.85)


static func cast(id: String, level: int, hero: Hero, target: Node3D, point: Vector3) -> void:
	var world = hero.world
	if world == null:
		push_warning("Fähigkeit ohne Spielwelt gewirkt: %s" % id)
		return
	if target != null and target != hero:
		_face(hero, target.global_position)
	elif point != hero.global_position:
		_face(hero, point)
	var def := GameData.skill(id)
	if def.anim != "":
		hero.visual.play_action(def.anim, def.anim_speed, def.anim_start)
	match id:
		"shield_bash": _shield_bash(level, hero, target as Enemy, world)
		"taunt": _taunt(level, hero, world)
		"guardian_blessing": _guardian_blessing(level, hero, world)
		"arcane_barrier": _arcane_barrier(level, hero, target as Hero, world)
		"shadow_strike": _shadow_strike(level, hero, target as Enemy, world)
		"poison_mark": _poison_mark(level, hero, target as Enemy, world)
		"fan_of_knives": _fan_of_knives(level, hero, world)
		"smoke_bomb": _smoke_bomb(level, hero, point, world)
		"fireball": _fireball(level, hero, point, world)
		"frost_nova": _frost_nova(level, hero, world)
		"chain_lightning": _chain_lightning(level, hero, target as Enemy, world)
		"healing_pulse": _healing_pulse(level, hero, world)
		"bastion": _bastion(level, hero, world)
		"shadow_dance": _shadow_dance(level, hero, world)
		"blade_dance": _blade_dance(level, hero, target as Enemy, world)
		"dagger_cyclone": _dagger_cyclone(level, hero, world)
		"iron_maelstrom": _iron_maelstrom(level, hero, world)
		"glacial_rift": _glacial_rift(level, hero, point, world)
		"starfall": _starfall(level, hero, point, world)
		"sanctuary": _sanctuary(level, hero, world)
		_:
			push_error("Fähigkeit ohne Wirkung: %s" % id)


## Wirkwert einer Fähigkeit für einen Helden. Attribut-Skalierung nur für die skalierenden Werte.
static func power(id: String, level: int, key: String, hero: Hero, multiplier := 1.0) -> float:
	return power_for_stats(id, level, key, hero.stats, multiplier)


## Wie power(), aber für beliebige Werte (z. B. die Vorschau des nächsten Attributkaufs).
static func power_for_stats(id: String, level: int, key: String, stats: StatBlock, multiplier := 1.0) -> float:
	var base := float(GameData.skill_value(id, level, key, 0.0))
	var total := base * stats.ability_power() * multiplier
	var def := GameData.skill(id)
	if key in def.get("scaled_keys", []):
		var scaling: Dictionary = def.get("scaling", {})
		for attr in scaling:
			total += float(scaling[attr]) * stats.attribute(attr)
	return total


static func v(id: String, level: int, key: String) -> float:
	return float(GameData.skill_value(id, level, key, 0.0))


# --- Guardian ------------------------------------------------------------------

static func _shield_bash(level: int, hero: Hero, e: Enemy, world) -> void:
	if e == null or not e.is_alive():
		return
	world.combat.deal_damage(hero, e, power("shield_bash", level, "damage", hero), DamageInfo.Type.PHYSICAL)
	if e.is_alive():
		e.status.apply(StatusEffects.STUN, v("shield_bash", level, "stun"), 0.0, hero)
		world.rewards.record_control(hero, e, StatusEffects.STUN, e.status.last_gain)
	# Schildschlag: goldener Stoß am Ziel, Druckwelle am Boden, Funken und aufgewirbelter Staub
	var hit := e.global_position + Vector3(0, 1.1, 0)
	world.vfx.energy_burst(hit, Color(1.0, 0.88, 0.55), 2.6, 0.45)
	world.vfx.shockwave(e.global_position, 2.2, GOLD, 0.35)
	world.vfx.burst(hit, Color(1.0, 0.95, 0.6), 18, 7.0, 0.4, 0.35, {"gravity": Vector3(0, -6, 0), "tex": "star_04"})
	world.vfx.smoke_cloud(e.global_position + Vector3(0, 0.3, 0), DUST, 0.7, 0.0, 6, 0.8)
	world.vfx.slash(hit, hero.rotation.y, Color(0.9, 0.95, 1.0), 2.4, "slash_02")


static func _taunt(level: int, hero: Hero, world) -> void:
	var radius := v("taunt", level, "radius")
	var duration := v("taunt", level, "duration")
	_taunt_enemies(hero, world, radius, duration)
	var armor := power("taunt", level, "armor", hero)
	if armor > 0.0:
		hero.status.apply(StatusEffects.ARMOR_BONUS, duration, armor, hero)
	# Kampfschrei: zwei rote Druckwellen über den Boden, Energiestoß, aufgewirbelter Staub
	world.vfx.shockwave(hero.global_position, radius, RAGE, 0.5)
	world.vfx.shockwave(hero.global_position, radius * 0.7, Color(1.0, 0.55, 0.3), 0.8)
	world.vfx.energy_burst(hero.global_position + Vector3(0, 1.3, 0), RAGE, 3.2, 0.5)
	world.vfx.smoke_cloud(hero.global_position + Vector3(0, 0.3, 0), DUST, 1.4, 0.0, 10, 1.2)


## Verspottet Gegner im Umkreis. Belohnt wird nur wirksamer Taunt (Zielwechsel, neue Wirkdauer).
static func _taunt_enemies(hero: Hero, world, radius: float, duration: float) -> void:
	for e: Enemy in world.spawner.enemies_in_radius(hero.global_position, radius):
		var before: Node3D = e.target
		e.status.apply(StatusEffects.TAUNT, duration, 0.0, hero)
		world.rewards.record_control(hero, e, StatusEffects.TAUNT, e.status.last_gain, 1.0, before != hero)
		e.on_taunted()
		world.vfx.energy_burst(e.global_position + Vector3(0, 2.4, 0), RAGE, 1.0, 0.4)


static func _guardian_blessing(level: int, hero: Hero, world) -> void:
	var radius := v("guardian_blessing", level, "radius")
	var duration := v("guardian_blessing", level, "duration")
	var haste := v("guardian_blessing", level, "haste")
	var reduction := power("guardian_blessing", level, "reduction", hero)
	for ally: Hero in _allies_in_radius(world, hero.global_position, radius):
		ally.status.apply(StatusEffects.DAMAGE_REDUCTION, duration, reduction, hero)
		if haste > 0.0:
			ally.status.apply(StatusEffects.HASTE, duration, haste, hero)
		# Heiliges Licht: Lichtsäule von oben und aufsteigende Funken
		world.vfx.beam(ally.global_position, GOLD, 1.9, 8.0, 1.0, "light_rays")
		world.vfx.sparkles(ally.global_position + Vector3(0, 0.3, 0), GOLD, 18, 0.6, 1.3, 0.5, 2.8)
	world.vfx.decal(hero.global_position, "rune_circle", 2.4, Color(1.0, 0.85, 0.4, 0.9), 1.3, 0.25)
	world.vfx.shockwave(hero.global_position, radius, GOLD, 0.6)


static func _arcane_barrier(level: int, hero: Hero, ally: Hero, world) -> void:
	if ally == null or not ally.is_alive():
		ally = hero
	ally.health.add_shield(power("arcane_barrier", level, "shield", hero), v("arcane_barrier", level, "duration"), hero)
	var chest := ally.global_position + Vector3(0, 1.1, 0)
	world.vfx.energy_burst(chest, ARCANE, 2.4, 0.5)
	world.vfx.sparkles(ally.global_position + Vector3(0, 0.2, 0), ARCANE, 16, 0.8, 1.1, 0.45, 2.2)
	world.vfx.decal(ally.global_position, "rune_circle", 1.5, Color(0.5, 0.85, 1.0, 0.85), 0.9, 0.6)
	if ally != hero:
		world.vfx.lightning(hero.global_position + Vector3(0, 1.4, 0), chest, ARCANE, 0.3, 0.8)


# --- Shadow --------------------------------------------------------------------

static func _shadow_strike(level: int, hero: Hero, e: Enemy, world) -> void:
	if e == null or not e.is_alive():
		return
	var from := hero.global_position
	var dir := Vector3(e.global_position.x - from.x, 0.0, e.global_position.z - from.z)
	if dir.length() > 0.01:
		hero.global_position = e.global_position - dir.normalized() * (e.body_radius + 0.8)
	# verschwindet im Schattenrauch, zieht einen violetten Streif und taucht am Ziel wieder auf
	world.vfx.smoke_cloud(from + Vector3(0, 0.6, 0), SHADOW_SMOKE, 0.8, 0.0, 8, 0.8)
	world.vfx.lightning(from + Vector3(0, 1.0, 0), hero.global_position + Vector3(0, 1.0, 0), SHADOW, 0.3, 1.2)
	world.vfx.slash(e.global_position + Vector3(0, 1.1, 0), hero.rotation.y, Color(0.8, 0.6, 1.0), 2.6, "slash_03")
	var crit: bool = v("shadow_strike", level, "always_crit") > 0.0 or hero.rng.randf() < hero.stats.crit_chance()
	var amount := power("shadow_strike", level, "damage", hero) * (hero.stats.crit_multiplier() if crit else 1.0)
	world.combat.deal_damage(hero, e, amount, DamageInfo.Type.PHYSICAL, crit)
	world.vfx.energy_burst(e.global_position + Vector3(0, 1.1, 0), SHADOW, 2.0, 0.45)
	world.vfx.smoke_cloud(hero.global_position + Vector3(0, 0.5, 0), SHADOW_SMOKE, 0.6, 0.0, 5, 0.6)
	hero.attack_target = e


static func _poison_mark(level: int, hero: Hero, e: Enemy, world) -> void:
	if e == null or not e.is_alive():
		return
	e.status.apply_stacking(StatusEffects.POISON, v("poison_mark", level, "duration"), power("poison_mark", level, "dps", hero),
		int(v("poison_mark", level, "max_stacks")), hero)
	# Giftpfeil: grüner Streif, Giftspritzer und eine giftige Wolke am Ziel
	var chest := e.global_position + Vector3(0, 1.1, 0)
	world.vfx.lightning(hero.global_position + Vector3(0, 1.3, 0), chest, POISON, 0.25, 0.6)
	world.vfx.energy_burst(chest, POISON, 1.8, 0.5)
	world.vfx.smoke_cloud(e.global_position + Vector3(0, 0.7, 0), Color(0.35, 0.78, 0.25, 0.85), 0.85, 0.0, 12, 0.5)
	world.vfx.burst(chest, POISON, 10, 2.0, 0.35, 0.8, {"gravity": Vector3(0, 1.5, 0), "tex": "circle_02"})


static func _fan_of_knives(level: int, hero: Hero, world) -> void:
	var radius := v("fan_of_knives", level, "radius")
	var dmg := power("fan_of_knives", level, "damage", hero)
	var poison := int(v("fan_of_knives", level, "poison"))
	for e: Enemy in world.spawner.enemies_in_radius(hero.global_position, radius):
		world.combat.deal_damage(hero, e, dmg, DamageInfo.Type.PHYSICAL)
		if poison > 0 and e.is_alive():
			e.status.apply_stacking(StatusEffects.POISON, 4.0, power("poison_mark", maxi(1, hero.abilities.level_of("poison_mark")), "dps", hero), 3, hero)
	# Messerfächer: echte Wurfmesser fliegen kreisförmig nach außen, dazu Klingenbögen und Druckwelle
	var center := hero.global_position + Vector3(0, 1.0, 0)
	world.vfx.knife_fan(center, radius, Color(0.85, 0.7, 1.0), 12)
	world.vfx.shockwave(hero.global_position, radius, Color(0.85, 0.7, 1.0), 0.4)
	for i in 4:
		world.vfx.slash(center, hero.rotation.y + i * PI * 0.5, Color(0.85, 0.75, 1.0), radius * 0.9, "slash_02")
	world.vfx.burst(center, Color(0.9, 0.85, 1.0), 24, radius * 3.0, 0.4, 0.35,
		{"flat": true, "up": Vector3.RIGHT, "gravity": Vector3.ZERO, "tex": "spark_05"})


static func _smoke_bomb(level: int, hero: Hero, point: Vector3, world) -> void:
	var radius := v("smoke_bomb", level, "radius")
	var duration := v("smoke_bomb", level, "duration")
	var slow := v("smoke_bomb", level, "slow")
	for e: Enemy in world.spawner.enemies_in_radius(point, radius):
		e.status.apply(StatusEffects.SLOW, duration, slow, hero)
		world.rewards.record_control(hero, e, StatusEffects.SLOW, e.status.last_gain, slow)
	hero.status.apply(StatusEffects.SWIFT, duration, v("smoke_bomb", level, "move"), hero)
	# Zündblitz, Druckwelle, dann eine dichte Rauchwolke für die ganze Wirkdauer
	world.vfx.energy_burst(point + Vector3(0, 0.8, 0), Color(0.85, 0.85, 0.9), 2.2, 0.35)
	world.vfx.shockwave(point, radius, Color(0.75, 0.78, 0.85), 0.45)
	world.vfx.smoke_cloud(point + Vector3(0, 0.5, 0), Color(0.58, 0.6, 0.66, 0.95), radius, duration, 44, 0.35)
	world.vfx.disc(point, radius, Color(0.4, 0.42, 0.5, 0.35), duration)


# --- Arcanist ------------------------------------------------------------------

static func _fireball(level: int, hero: Hero, point: Vector3, world) -> void:
	var fb := FireballProjectile.new()
	world.projectiles_root.add_child(fb)
	fb.launch(hero, world, hero.global_position + Vector3(0, 1.4, 0), point,
		power("fireball", level, "damage", hero), v("fireball", level, "radius"))


static func _frost_nova(level: int, hero: Hero, world) -> void:
	var radius := v("frost_nova", level, "radius")
	var dmg := power("frost_nova", level, "damage", hero)
	var slow := v("frost_nova", level, "slow")
	var duration := v("frost_nova", level, "duration")
	for e: Enemy in world.spawner.enemies_in_radius(hero.global_position, radius):
		world.combat.deal_damage(hero, e, dmg, DamageInfo.Type.MAGIC, false, "ice")
		if e.is_alive() and not e.is_immune("ice"):
			e.status.apply(StatusEffects.SLOW, duration, slow, hero)
			world.rewards.record_control(hero, e, StatusEffects.SLOW, e.status.last_gain, slow)
			world.vfx.burst(e.global_position + Vector3(0, 0.6, 0), FROST, 8, 2.0, 0.5, 0.8, {"gravity": Vector3(0, -3, 0), "tex": "sparkle"})
	# Eiswelle: Kristalle brechen aus dem Boden, Druckwellen, Kältenebel, Frostfläche
	world.vfx.ice_shards(hero.global_position, radius, 10 + int(radius) * 2)
	world.vfx.shockwave(hero.global_position, radius, FROST, 0.45)
	world.vfx.shockwave(hero.global_position, radius * 0.85, Color(0.9, 0.97, 1.0), 0.65)
	world.vfx.energy_burst(hero.global_position + Vector3(0, 1.0, 0), FROST, 3.0, 0.5)
	world.vfx.smoke_cloud(hero.global_position + Vector3(0, 0.3, 0), Color(0.85, 0.95, 1.0, 0.38), radius * 0.45, 0.0, 10, 0.3)
	world.vfx.disc(hero.global_position, radius, Color(0.6, 0.85, 1.0, 0.45), duration, "magic_05")


static func _chain_lightning(level: int, hero: Hero, first: Enemy, world) -> void:
	if first == null or not first.is_alive():
		return
	var dmg := power("chain_lightning", level, "damage", hero)
	var jumps := int(v("chain_lightning", level, "jumps"))
	var jump_range := v("chain_lightning", level, "jump_range")
	var hit: Array[Enemy] = []
	var current := first
	var from := hero.global_position + Vector3(0, 1.5, 0)
	for i in jumps:
		if current == null:
			break
		hit.append(current)
		var to := current.global_position + Vector3(0, 1.1, 0)
		world.vfx.lightning(from, to, Color(0.75, 0.85, 1.0), 0.35, 1.1)
		world.vfx.energy_burst(to, Color(0.7, 0.85, 1.0), 1.5, 0.35)
		world.combat.deal_damage(hero, current, dmg * pow(0.85, i), DamageInfo.Type.MAGIC)
		from = to
		var next: Enemy = null
		var best := jump_range
		for e: Enemy in world.spawner.enemies_in_radius(to, jump_range):
			if e in hit or not e.is_alive():
				continue
			var d := e.global_position.distance_to(to)
			if d < best:
				best = d
				next = e
		current = next


static func _healing_pulse(level: int, hero: Hero, world) -> void:
	var radius := v("healing_pulse", level, "radius")
	var amount := power("healing_pulse", level, "heal", hero) * hero.stats.heal_power()
	for ally: Hero in _allies_in_radius(world, hero.global_position, radius):
		ally.health.heal(amount, hero)   # liefert nur effektive Heilung – Überheilung zählt nicht
		world.vfx.beam(ally.global_position, HEAL_COLOR, 1.7, 7.0, 0.9, "light_rays")
		world.vfx.sparkles(ally.global_position + Vector3(0, 0.3, 0), HEAL_COLOR, 20, 0.7, 1.3, 0.5, 2.6)
	world.vfx.shockwave(hero.global_position, radius, HEAL_COLOR, 0.7)
	world.vfx.decal(hero.global_position, "rune_circle", 2.6, Color(0.5, 1.0, 0.6, 0.85), 1.1, 0.4)


static func _starfall(level: int, hero: Hero, point: Vector3, world) -> void:
	var storm := StarfallStorm.new()
	world.projectiles_root.add_child(storm)
	storm.start(hero, world, point, v("starfall", level, "radius"), int(v("starfall", level, "impacts")),
		v("starfall", level, "impact_radius"), power("starfall", level, "damage", hero), v("starfall", level, "duration"))


static func _sanctuary(level: int, hero: Hero, world) -> void:
	var duration := v("sanctuary", level, "duration")
	var heal := power("sanctuary", level, "heal", hero) * hero.stats.heal_power()
	for ally: Hero in world.heroes:
		if not is_instance_valid(ally) or not ally.is_alive():
			continue
		ally.status.apply(StatusEffects.DAMAGE_REDUCTION, duration, v("sanctuary", level, "reduction"), hero)
		ally.health.heal(heal, hero)
		world.vfx.beam(ally.global_position, HEAL_COLOR, 2.6, 10.0, 1.4, "light_rays")
		world.vfx.decal(ally.global_position, "rune_circle", 3.0, Color(0.55, 1.0, 0.65, 0.85), 1.6, 0.3)
		world.vfx.sparkles(ally.global_position + Vector3(0, 0.3, 0), Color(0.75, 1.0, 0.6), 28, 0.9, 1.5, 0.55, 3.0)
	world.vfx.shockwave(hero.global_position, 7.0, HEAL_COLOR, 0.9)
	world.vfx.energy_burst(hero.global_position + Vector3(0, 1.2, 0), HEAL_COLOR, 3.5, 0.6)


# --- Ultimates Guardian / Shadow -------------------------------------------------

static func _bastion(level: int, hero: Hero, world) -> void:
	var radius := v("bastion", level, "radius")
	var duration := v("bastion", level, "duration")
	for ally: Hero in _allies_in_radius(world, hero.global_position, radius):
		var dr := v("bastion", level, "self_reduction") if ally == hero else v("bastion", level, "ally_reduction")
		ally.status.apply(StatusEffects.DAMAGE_REDUCTION, duration, dr, hero)
	_taunt_enemies(hero, world, radius, v("bastion", level, "taunt"))
	# Bollwerk: breite Lichtsäule, großer Runenkreis, zwei Druckwellen, Energiestoß und Funken
	world.vfx.beam(hero.global_position, Color(0.6, 0.85, 1.0), 3.2, 11.0, 1.3, "light_rays")
	world.vfx.decal(hero.global_position, "rune_circle", radius * 0.6, Color(0.5, 0.8, 1.0, 0.9), 1.8, 0.2)
	world.vfx.shockwave(hero.global_position, radius, Color(0.45, 0.75, 1.0), 0.7)
	world.vfx.shockwave(hero.global_position, radius * 0.6, GOLD, 1.0)
	world.vfx.energy_burst(hero.global_position + Vector3(0, 1.2, 0), Color(0.6, 0.85, 1.0), 3.8, 0.6)
	world.vfx.sparkles(hero.global_position + Vector3(0, 0.3, 0), Color(0.7, 0.9, 1.0), 32, 1.2, 1.5, 0.55, 3.2)


static func _shadow_dance(level: int, hero: Hero, world) -> void:
	var duration := v("shadow_dance", level, "duration")
	hero.status.apply(StatusEffects.SWIFT, duration, v("shadow_dance", level, "move"), hero)
	hero.status.apply(StatusEffects.HASTE, duration, v("shadow_dance", level, "haste"), hero)
	hero.status.apply(StatusEffects.CRIT_BONUS, duration, v("shadow_dance", level, "crit"), hero)
	# Schattentanz: der Schatten hüllt sich in violetten Rauch, Energiestoß, Runenkreis, Funken
	world.vfx.smoke_cloud(hero.global_position + Vector3(0, 0.6, 0), SHADOW_SMOKE, 1.3, 0.0, 14, 1.0)
	world.vfx.energy_burst(hero.global_position + Vector3(0, 1.0, 0), SHADOW, 3.0, 0.55)
	world.vfx.shockwave(hero.global_position, 3.0, SHADOW, 0.5)
	world.vfx.decal(hero.global_position, "rune_circle", 2.2, Color(0.75, 0.5, 1.0, 0.85), 1.0, 0.8)
	world.vfx.sparkles(hero.global_position + Vector3(0, 0.3, 0), SHADOW, 24, 0.9, 1.2, 0.45, 3.0)


## Alternative zu Shadow Dance: Sprungserie um ein Ziel (Ablauf in BladeDance).
static func _blade_dance(level: int, hero: Hero, e: Enemy, world) -> void:
	if e == null or not e.is_alive():
		return
	var poison_level := hero.abilities.level_of("poison_mark")
	var dance := BladeDance.new()
	world.projectiles_root.add_child(dance)
	dance.start(hero, world, e, int(v("blade_dance", level, "hits")), power("blade_dance", level, "damage", hero),
		v("blade_dance", level, "duration"), v("blade_dance", level, "radius"),
		power("poison_mark", poison_level, "dps", hero) if poison_level > 0 else 0.0,
		int(v("poison_mark", poison_level, "max_stacks")) if poison_level > 0 else 0)
	world.vfx.smoke_cloud(hero.global_position + Vector3(0, 0.6, 0), SHADOW_SMOKE, 0.9, 0.0, 8, 0.8)


## Dritte Wahl für das Arcanist-Ultimate: Eisstachel-Welle in gerader Linie (Ablauf in GlacialRift).
static func _glacial_rift(level: int, hero: Hero, point: Vector3, world) -> void:
	var rift := GlacialRift.new()
	world.projectiles_root.add_child(rift)
	rift.start(hero, world, point, v("glacial_rift", level, "range"), power("glacial_rift", level, "damage", hero),
		v("glacial_rift", level, "lift"), v("glacial_rift", level, "slow"), v("glacial_rift", level, "slow_time"),
		v("glacial_rift", level, "wall_time"))
	world.vfx.shockwave(hero.global_position, 2.0, FROST, 0.35)


## Alternative zu Bastion: Klingenwirbel, mit dem der Guardian frei läuft (Ablauf in IronMaelstrom).
static func _iron_maelstrom(level: int, hero: Hero, world) -> void:
	var maelstrom := IronMaelstrom.new()
	world.projectiles_root.add_child(maelstrom)
	maelstrom.start(hero, world, v("iron_maelstrom", level, "duration"), v("iron_maelstrom", level, "radius"),
		power("iron_maelstrom", level, "damage", hero), v("iron_maelstrom", level, "interval"),
		v("iron_maelstrom", level, "near_bonus"), v("iron_maelstrom", level, "crit"), v("iron_maelstrom", level, "reduction"))
	world.vfx.shockwave(hero.global_position, v("iron_maelstrom", level, "radius"), Color(0.7, 0.85, 1.0), 0.4)
	# Kriegsschrei (Ton über cast_iron_maelstrom): Stoß aus Kopfhöhe und eine zweite, weite Welle
	world.vfx.energy_burst(hero.global_position + Vector3(0, 1.9, 0), Color(1.0, 0.8, 0.45), 2.4, 0.45)
	world.vfx.shockwave(hero.global_position, v("iron_maelstrom", level, "radius") * 1.8, Color(1.0, 0.75, 0.4), 0.7)


## Dritte Wahl für das Shadow-Ultimate: Messerwirbel auf der Stelle (Ablauf in DaggerCyclone).
static func _dagger_cyclone(level: int, hero: Hero, world) -> void:
	var poison_level := hero.abilities.level_of("poison_mark")
	var cyclone := DaggerCyclone.new()
	world.projectiles_root.add_child(cyclone)
	cyclone.start(hero, world, v("dagger_cyclone", level, "duration"), v("dagger_cyclone", level, "radius"),
		power("dagger_cyclone", level, "damage", hero), v("dagger_cyclone", level, "interval"),
		power("poison_mark", poison_level, "dps", hero) if poison_level > 0 else 0.0,
		int(v("poison_mark", poison_level, "max_stacks")) if poison_level > 0 else 0)
	world.vfx.energy_burst(hero.global_position + Vector3(0, 1.0, 0), Color(0.85, 0.75, 1.0), 2.6, 0.45)


# --- Hilfen ------------------------------------------------------------------

static func _allies_in_radius(world, point: Vector3, radius: float) -> Array[Hero]:
	var result: Array[Hero] = []
	for h: Hero in world.heroes:
		if is_instance_valid(h) and h.is_alive() and Vector2(h.global_position.x - point.x, h.global_position.z - point.z).length() <= radius:
			result.append(h)
	return result


static func _face(hero: Hero, point: Vector3) -> void:
	var dir := Vector3(point.x - hero.global_position.x, 0.0, point.z - hero.global_position.z)
	if dir.length_squared() > 0.0001:
		hero.rotation.y = atan2(-dir.x, -dir.z)
