extends Node
## Lädt alle Spieldefinitionen aus res://data/*.json und prüft sie.
## Einzige Quelle für Helden-, Gegner-, Wellen- und Balancingwerte.
## Fehlerhafte Einträge werden übersprungen und in `errors` gesammelt, statt das Spiel abstürzen zu lassen.

const BALANCE_PATH := "res://data/balance/game.json"
const HEROES_PATH := "res://data/heroes/heroes.json"
const ENEMIES_PATH := "res://data/enemies/enemies.json"
const WAVES_PATH := "res://data/waves/waves.json"
const ATTRIBUTES_PATH := "res://data/balance/attributes.json"
const SKILLS_PATH := "res://data/skills/skills.json"
const ITEMS_PATH := "res://data/items/items.json"
const MAPS_PATH := "res://data/maps/maps.json"
const SKILL_TARGETS := ["enemy", "ally", "self", "point"]
const ITEM_SLOTS := ["weapon", "armor", "helmet", "boots", "ring", "amulet", "consumable"]
const MAX_SKILL_LEVEL := 3
const ATTRIBUTES := ["str", "agi", "int"]
const ATTRIBUTE_NAMES := {"str": "Stärke", "agi": "Beweglichkeit", "int": "Intelligenz"}

var balance: Dictionary = {}
var attribute_rules: Dictionary = {}
var skills: Dictionary = {}            ## id -> Definition
var skill_order: Array[String] = []
var items: Dictionary = {}             ## id -> Definition
var item_order: Array[String] = []
var team_upgrades: Array[Dictionary] = []
var heroes: Dictionary = {}            ## id -> Definition
var hero_order: Array[String] = []
var enemies: Dictionary = {}           ## id -> Definition
var waves: Array[Dictionary] = []
var maps: Dictionary = {}              ## id -> Definition (Szene, Kern, Brunnen)
var map_order: Array[String] = []
var errors: PackedStringArray = []


func _init() -> void:
	reload()


func reload() -> void:
	errors.clear()
	heroes.clear()
	hero_order.clear()
	skills.clear()
	skill_order.clear()
	items.clear()
	item_order.clear()
	enemies.clear()
	waves.clear()

	balance = _load_json(BALANCE_PATH)
	_validate_balance()
	attribute_rules = _load_json(ATTRIBUTES_PATH)
	_validate_attribute_rules()

	for h in _load_json(HEROES_PATH).get("heroes", []):
		var def := _normalize_hero(h)
		if def.is_empty():
			continue
		heroes[def.id] = def
		hero_order.append(def.id)

	for e in _load_json(ENEMIES_PATH).get("enemies", []):
		var def := _normalize_enemy(e)
		if not def.is_empty():
			enemies[def.id] = def

	for s in _load_json(SKILLS_PATH).get("skills", []):
		var def := _normalize_skill(s)
		if not def.is_empty():
			skills[def.id] = def
			skill_order.append(def.id)
	# Anzeige-Reihenfolge (Shop, Vorschau): normale Fähigkeiten zuerst, Ultimates ganz unten; sonst wie in der Datei
	var normals := skill_order.filter(func(id: String) -> bool: return not skills[id].ultimate)
	var ults := skill_order.filter(func(id: String) -> bool: return skills[id].ultimate)
	skill_order.assign(normals + ults)

	for it in _load_json(ITEMS_PATH).get("items", []):
		var def := _normalize_item(it)
		if not def.is_empty():
			items[def.id] = def
			item_order.append(def.id)

	team_upgrades.clear()
	for u in balance.get("team_upgrades", []):
		var id := String(u.get("id", ""))
		var costs: Array = u.get("costs", [])
		if id.is_empty() or costs.is_empty():
			errors.append("Team-Upgrade ohne ID oder Kosten: %s" % id)
			continue
		team_upgrades.append({"id": id, "name": String(u.get("name", id)), "description": String(u.get("description", "")),
			"costs": costs.map(func(c): return int(c)), "value_per_level": float(u.get("value_per_level", 0.0))})

	var number := 0
	for w in _load_json(WAVES_PATH).get("waves", []):
		number += 1
		var wave := normalize_wave(w, number)
		if not wave.is_empty():
			waves.append(wave)

	maps.clear()
	map_order.clear()
	for mp in _load_json(MAPS_PATH).get("maps", []):
		var def := _normalize_map(mp)
		if not def.is_empty():
			maps[def.id] = def
			map_order.append(def.id)

	for msg in errors:
		push_error("[GameData] " + msg)


func hero(id: String) -> Dictionary:
	return heroes.get(id, {})


func enemy(id: String) -> Dictionary:
	return enemies.get(id, {})


func skill(id: String) -> Dictionary:
	return skills.get(id, {})


## Wert einer Fähigkeit auf einer Stufe (1–3), z. B. skill_value("fireball", 2, "damage").
func skill_value(id: String, level: int, key: String, fallback: Variant = 0.0) -> Variant:
	var def := skill(id)
	if def.is_empty():
		return fallback
	var levels: Array = def.levels
	return levels[clampi(level, 1, levels.size()) - 1].get(key, fallback)


## Kartendefinition; unbekannte Karte -> erste Karte der Liste (die Arena).
func map(id: String) -> Dictionary:
	return maps.get(id, maps.get(map_order[0], {}) if not map_order.is_empty() else {})


func item(id: String) -> Dictionary:
	return items.get(id, {})


func team_upgrade(id: String) -> Dictionary:
	for u in team_upgrades:
		if u.id == id:
			return u
	return {}


func setting(section: String, key: String, fallback: Variant = null) -> Variant:
	return balance.get(section, {}).get(key, fallback)


## Gegner-Lebenspunkte je nach Spielerzahl. Bewusst nicht linear (siehe docs/BALANCING.md).
func enemy_hp_multiplier(player_count: int) -> float:
	var per_player: float = setting("player_scaling", "enemy_hp_per_extra_player", 0.6)
	return 1.0 + per_player * maxi(0, player_count - 1)


## Wandelt eine Wellendefinition in die interne Form um. Öffentlich, damit Tests eigene Wellen bauen können.
func normalize_wave(src: Dictionary, number: int) -> Dictionary:
	var ctx := "Welle %d" % number
	var path_count := int(setting("arena", "path_count", 3))
	var groups: Array[Dictionary] = []
	for g in src.get("groups", []):
		var enemy_id := String(g.get("enemy", ""))
		if not enemies.has(enemy_id):
			errors.append("%s: unbekannter Gegnertyp '%s'" % [ctx, enemy_id])
			continue
		var path := int(g.get("path", 0))
		if path < 0 or path >= path_count:
			errors.append("%s: Pfad %d existiert nicht (0..%d)" % [ctx, path, path_count - 1])
			continue
		var count := int(g.get("count", 0))
		if count <= 0:
			errors.append("%s: Gruppe %s ohne Anzahl" % [ctx, enemy_id])
			continue
		groups.append({
			"enemy": enemy_id,
			"count": count,
			"path": path,
			"interval": maxf(0.05, float(g.get("interval", 1.0))),
			"delay": maxf(0.0, float(g.get("delay", 0.0))),
		})
	if groups.is_empty():
		errors.append("%s: keine gültigen Gegnergruppen" % ctx)
		return {}
	return {
		"number": number,
		"name": String(src.get("name", ctx)),
		"prepare_seconds": maxf(0.0, float(src.get("prepare_seconds", setting("waves", "default_prepare_seconds", 12.0)))),
		"groups": groups,
	}


func _validate_balance() -> void:
	for pair in [["core", "max_hp"], ["heroes", "respawn_seconds"], ["arena", "path_count"]]:
		if setting(pair[0], pair[1]) == null:
			errors.append("Balancing: %s.%s fehlt" % pair)


func _normalize_skill(src: Dictionary) -> Dictionary:
	var id := String(src.get("id", ""))
	if id.is_empty() or skills.has(id):
		errors.append("Fähigkeit ohne oder mit doppelter ID: '%s'" % id)
		return {}
	var ctx := "Fähigkeit %s" % id
	var target := String(src.get("target", ""))
	if not (target in SKILL_TARGETS):
		errors.append("%s: target '%s' unbekannt" % [ctx, target])
		return {}
	var levels: Array = src.get("levels", [])
	var costs: Array = src.get("costs", [])
	if levels.size() != MAX_SKILL_LEVEL or costs.size() != MAX_SKILL_LEVEL:
		errors.append("%s: braucht genau %d Stufen und %d Kosten" % [ctx, MAX_SKILL_LEVEL, MAX_SKILL_LEVEL])
		return {}
	for lv in levels:
		for key in ["mana", "cooldown"]:
			if not lv.has(key) or float(lv[key]) < 0.0:
				errors.append("%s: Stufe ohne gültiges '%s'" % [ctx, key])
				return {}
		if target in ["enemy", "ally", "point"] and not lv.has("range"):
			errors.append("%s: zielgerichtete Fähigkeit ohne 'range'" % ctx)
			return {}
	var class_list: Array = src.get("heroes", [])
	for h in class_list:
		if not heroes.has(String(h)):
			errors.append("%s: unbekannte Klasse '%s'" % [ctx, h])
	if class_list.is_empty():
		errors.append("%s: keiner Klasse zugeordnet (heroes)" % ctx)
	var anim: Array = src.get("anim", [])
	var kind := String(src.get("kind", "normal"))
	return {
		"id": id, "name": String(src.get("name", id)), "kind": kind, "ultimate": kind == "ultimate",
		"archetype": String(src.get("archetype", "")), "icon": String(src.get("icon", id.substr(0, 2).to_upper())),
		"color": Color.html(String(src.get("color", "#ffffff"))), "target": target,
		"description": String(src.get("description", "")), "costs": costs.map(func(c): return int(c)),
		"scaling": src.get("scaling", {}), "levels": levels, "heroes": class_list.map(func(h): return String(h)),
		"anim": String(anim[0]) if anim.size() > 0 else "", "anim_speed": float(anim[1]) if anim.size() > 1 else 1.0,
		"anim_start": clampf(float(anim[2]), 0.0, 0.9) if anim.size() > 2 else 0.0,   # Anteil der Animation, der übersprungen wird
		"scaled_keys": src.get("scaled_keys", ["damage", "shield", "heal", "dps"]),
	}


func _normalize_item(src: Dictionary) -> Dictionary:
	var id := String(src.get("id", ""))
	if id.is_empty() or items.has(id):
		errors.append("Gegenstand ohne oder mit doppelter ID: '%s'" % id)
		return {}
	var slot := String(src.get("slot", ""))
	if not (slot in ITEM_SLOTS):
		errors.append("Gegenstand %s: Slot '%s' unbekannt" % [id, slot])
		return {}
	var price := int(src.get("price", 0))
	if price <= 0:
		errors.append("Gegenstand %s: Preis fehlt" % id)
		return {}
	return {
		"id": id, "name": String(src.get("name", id)), "slot": slot, "rarity": String(src.get("rarity", "common")),
		"price": price, "stats": src.get("stats", {}), "use": src.get("use", {}),
		"max_stack": maxi(1, int(src.get("max_stack", 1))), "description": String(src.get("description", "")),
	}


func _validate_attribute_rules() -> void:
	for key in ["upgrade", "per_point", "caps", "levels"]:
		if not attribute_rules.has(key):
			errors.append("Attributregeln: Abschnitt '%s' fehlt" % key)
	var table: Array = attribute_rules.get("levels", {}).get("xp_to_next", [])
	if table.is_empty():
		errors.append("Attributregeln: XP-Tabelle leer")
	for v in table:
		if float(v) <= 0.0:
			errors.append("Attributregeln: XP-Tabelle enthält Werte <= 0")
			break


func _normalize_hero(src: Dictionary) -> Dictionary:
	var id := String(src.get("id", ""))
	if id.is_empty() or heroes.has(id):
		errors.append("Held ohne oder mit doppelter ID: '%s'" % id)
		return {}
	var ctx := "Held %s" % id
	var main := String(src.get("main_attribute", ""))
	if not (main in ATTRIBUTES):
		errors.append("%s: main_attribute muss str, agi oder int sein" % ctx)
		main = "str"
	var attrs := {}
	var growth := {}
	for a in ATTRIBUTES:
		attrs[a] = float(src.get("attributes", {}).get(a, 0.0))
		growth[a] = float(src.get("growth", {}).get(a, 0.0))
	var damage_type := String(src.get("damage_type", "physical"))
	if not (damage_type in ["physical", "magic"]):
		errors.append("%s: damage_type '%s' unbekannt" % [ctx, damage_type])
		damage_type = "physical"
	return {
		"id": id,
		"name": String(src.get("name", id)),
		"archetype": String(src.get("archetype", "")),
		"role": String(src.get("role", "")),
		"description": String(src.get("description", "")),
		"color": Color.html(String(src.get("color", "#5aa9ff"))),
		"model": String(src.get("model", "")),
		"model_scale": float(src.get("model_scale", 1.0)),
		"hidden_parts": src.get("hidden_parts", []),
		"main_attribute": main,
		"attributes": attrs,
		"growth": growth,
		"base_hp": _num(src, "base_hp", ctx, 1.0),
		"base_hp_regen": float(src.get("base_hp_regen", 0.0)),
		"base_mana": float(src.get("base_mana", 0.0)),
		"base_mana_regen": float(src.get("base_mana_regen", 0.0)),
		"base_armor": float(src.get("base_armor", 0.0)),
		"base_magic_resist": float(src.get("base_magic_resist", 0.0)),
		"base_move_speed": _num(src, "base_move_speed", ctx, 0.5),
		"base_attack": _num(src, "base_attack", ctx, 0.0),
		"base_attack_interval": _num(src, "base_attack_interval", ctx, 0.1),
		"base_crit": clampf(float(src.get("base_crit", 0.0)), 0.0, 1.0),
		"attack_range": _num(src, "attack_range", ctx, 0.5),
		"damage_type": damage_type,
		"attack_hit_delay": float(src.get("attack_hit_delay", 0.3)),
		"projectile": src.get("projectile", {}),
		"on_hit": src.get("on_hit", {}),
		"anims": src.get("anims", {}),
		"anim_libraries": src.get("anim_libraries", []),
	}


func _normalize_enemy(src: Dictionary) -> Dictionary:
	var id := String(src.get("id", ""))
	if id.is_empty() or enemies.has(id):
		errors.append("Gegner ohne oder mit doppelter ID: '%s'" % id)
		return {}
	var ctx := "Gegner %s" % id
	return {
		"id": id,
		"name": String(src.get("name", id)),
		"category": String(src.get("category", "normal")),
		"model": String(src.get("model", "")),
		"model_scale": float(src.get("model_scale", 1.0)),
		"max_hp": _num(src, "max_hp", ctx, 1.0),
		"move_speed": _num(src, "move_speed", ctx, 0.1),
		"damage": _num(src, "damage", ctx, 0.0),
		"structure_damage": _num(src, "structure_damage", ctx, 0.0),
		"attack_interval": _num(src, "attack_interval", ctx, 0.1),
		"attack_range": _num(src, "attack_range", ctx, 0.3),
		"attack_hit_delay": float(src.get("attack_hit_delay", 0.3)),
		"armor": float(src.get("armor", 0.0)),
		"magic_resist": float(src.get("magic_resist", 0.0)),
		"cc_resist": clampf(float(src.get("cc_resist", 0.0)), 0.0, 1.0),
		"aggro_radius": float(src.get("aggro_radius", 4.0)),
		"aggro_leash": maxf(float(src.get("aggro_leash", 7.0)), float(src.get("aggro_radius", 4.0)) + 1.0),
		"gold": int(src.get("gold", 0)),
		"xp": int(src.get("xp", 0)),
		"anims": src.get("anims", {}),
		"projectile": src.get("projectile", {}),   ## Fernkampf: {speed, color}; leer = Nahkampf
		"ability": src.get("ability", {}),         ## Zusatzfähigkeit (Elite, Mini-Boss), z. B. {type: "stomp", ...}
		"boss": src.get("boss", {}),               ## Boss-Phasen und -Fähigkeiten (siehe BossBrain)
		"melee": src.get("melee", {}),             ## Hybrid: {range, damage} – Fernkämpfer schlägt zu, wenn ein Held so nah ist
		"on_hit": src.get("on_hit", {}),           ## jeder Treffer: {slow, attack_slow, duration} (Unterkühlung)
		"elements": src.get("elements", {}),       ## Schadensfaktor je Element, z. B. {ice: 0, fire: 1.5}; fehlt = 1
		"body_radius": float(src.get("body_radius", 0.0)),   ## 0 = aus model_scale; große Körper (Drache) größer
		"bar_height": float(src.get("bar_height", 0.0)),     ## Höhe der Lebensleiste; 0 = aus model_scale
		"glow_pulse": src.get("glow_pulse", []),   ## [niedrig, hoch, Periode] – Eigenleuchten pulsiert
		"aura_fx": String(src.get("aura_fx", "")), ## dauerhafter Effekt am Körper, z. B. "embers"
	}


## Pflichtzahl lesen; fehlende oder zu kleine Werte werden gemeldet und auf das Minimum gesetzt.
func _normalize_map(src: Dictionary) -> Dictionary:
	var id := String(src.get("id", ""))
	var ctx := "Karte '%s'" % id
	if id == "":
		errors.append("Karte ohne id")
		return {}
	var scene := String(src.get("scene", ""))
	if not ResourceLoader.exists(scene):
		errors.append("%s: Szene fehlt (%s)" % [ctx, scene])
		return {}
	var def := {"id": id, "name": String(src.get("name", id)), "description": String(src.get("description", "")), "scene": scene,
		"layout": String(src.get("layout", ""))}
	for key in ["core", "fountain"]:
		var v: Array = src.get(key, [])
		if v.size() != 3:
			errors.append("%s: %s braucht [x, y, z]" % [ctx, key])
			return {}
		def[key] = Vector3(float(v[0]), float(v[1]), float(v[2]))
	if src.has("fountain_radius"):
		def.fountain_radius = float(src.fountain_radius)
	return def


func _num(src: Dictionary, key: String, ctx: String, minimum: float) -> float:
	if not src.has(key):
		errors.append("%s: Feld '%s' fehlt" % [ctx, key])
		return minimum
	var v := float(src[key])
	if v < minimum:
		errors.append("%s: '%s' = %s ist kleiner als %s" % [ctx, key, v, minimum])
		return minimum
	return v


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		errors.append("Datei fehlt: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		errors.append("Ungültiges JSON: %s" % path)
		return {}
	return parsed
