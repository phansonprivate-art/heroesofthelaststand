class_name AbilityCaster
extends Node
## Fähigkeiten eines Helden: gelernte Stufen, Slots (Q W E R D F), Abklingzeiten und Wirken.
## Regeln:
##  - jede Fähigkeit hat 3 Stufen; Lernen/Verbessern bezahlt der ShopService
##  - R (Slot 3) ist dem Ultimate vorbehalten; ein Ultimate ab Heldenstufe 5, nur eines pro Held
##  - Zielfähigkeiten außerhalb der Reichweite: der Held läuft hin und wirkt dann (wie Klick-Angriffe)
## Die Wirkung selbst steht in AbilityEffects; Werte kommen aus data/skills/skills.json.

signal changed
signal cast_performed(hero: Hero, ability_id: String, level: int)
signal cast_failed(hero: Hero, ability_id: String, reason: String)

const SLOT_KEYS := ["Q", "W", "E", "R", "D", "F"]
const ULT_SLOT := 3
const NORMAL_SLOTS := [0, 1, 2, 4, 5]
const ULT_HERO_LEVEL := 5
const QUEUE_TIMEOUT := 4.0
const CHASE_INTERVAL := 0.2

var hero: Hero
var levels: Dictionary = {}                        ## ability_id -> Stufe 1–3
var slots: Array[String] = ["", "", "", "", "", ""]
var cooldowns: Dictionary = {}                     ## ability_id -> verbleibende Sekunden
var cast_counts: Dictionary = {}                   ## ability_id -> Anzahl (Telemetrie)
var _queued: Dictionary = {}                       ## {id, target, left}
var _chase_left := 0.0


func setup(p_hero: Hero) -> void:
	hero = p_hero


func level_of(id: String) -> int:
	return levels.get(id, 0)


func knows(id: String) -> bool:
	return levels.has(id)


func known_ultimate() -> String:
	for id in levels:
		if GameData.skill(id).get("ultimate", false):
			return id
	return ""


## Preis für den nächsten Schritt (Lernen oder Verbessern); 0 auf Höchststufe.
func cost_for(id: String) -> int:
	var def := GameData.skill(id)
	var lvl := level_of(id)
	if def.is_empty() or lvl >= GameData.MAX_SKILL_LEVEL:
		return 0
	return int(def.costs[lvl])


## Prüft, ob Lernen/Verbessern erlaubt ist (ohne Gold). Leerer String = erlaubt, sonst der Grund.
func check_learn(id: String) -> String:
	var def := GameData.skill(id)
	if def.is_empty():
		return "Unbekannte Fähigkeit."
	if not (hero.hero_id in def.heroes):
		return "%s ist nur für %s." % [def.name, ", ".join(PackedStringArray(def.heroes.map(func(h): return GameData.hero(h).get("name", h))))]
	var lvl := level_of(id)
	if lvl >= GameData.MAX_SKILL_LEVEL:
		return "%s ist bereits auf Höchststufe." % def.name
	if def.ultimate:
		if hero.stats.level < ULT_HERO_LEVEL:
			return "Ultimates gibt es ab Heldenstufe %d (aktuell %d)." % [ULT_HERO_LEVEL, hero.stats.level]
		var other := known_ultimate()
		if lvl == 0 and other != "":
			return "Du hast bereits ein Ultimate (%s). Nur eines pro Held." % GameData.skill(other).name
	return ""


## Bucht eine Stufe (nach erfolgreicher Bezahlung). Neue Fähigkeiten landen im ersten freien Slot.
func learn(id: String) -> void:
	var first := not knows(id)
	levels[id] = level_of(id) + 1
	if first:
		_auto_equip(id)
	changed.emit()


## Legt eine gelernte Fähigkeit in einen Slot (tauscht, falls sie schon woanders liegt). Leer = ok, sonst Grund.
func equip(id: String, slot: int) -> String:
	if not knows(id):
		return "Fähigkeit nicht gelernt."
	if slot < 0 or slot >= slots.size():
		return "Ungültiger Slot."
	var ult: bool = GameData.skill(id).ultimate
	if ult != (slot == ULT_SLOT):
		return "R ist dem Ultimate vorbehalten." if not ult else "Ultimates gehören auf R."
	var old := slots.find(id)
	if old >= 0:
		slots[old] = slots[slot]
	slots[slot] = id
	changed.emit()
	return ""


func unequip(slot: int) -> void:
	if slot >= 0 and slot < slots.size() and slots[slot] != "":
		slots[slot] = ""
		changed.emit()


func cooldown_left(id: String) -> float:
	return maxf(0.0, cooldowns.get(id, 0.0))


func mana_cost(id: String) -> float:
	return float(GameData.skill_value(id, level_of(id), "mana", 0.0))


## Grund, warum der Slot gerade nicht wirkbar ist ("" = wirkbar).
func check_cast(slot: int) -> String:
	if slot < 0 or slot >= slots.size() or slots[slot] == "":
		return "Keine Fähigkeit auf %s." % SLOT_KEYS[clampi(slot, 0, 5)]
	var id := slots[slot]
	if not hero.is_alive():
		return "Du bist gefallen."
	if hero.status.is_stunned():
		return "Betäubt."
	if cooldown_left(id) > 0.0:
		return "%s lädt noch %.0f s." % [GameData.skill(id).name, ceilf(cooldown_left(id))]
	if hero.mana < mana_cost(id):
		return "Nicht genug Mana (%d benötigt)." % int(mana_cost(id))
	return ""


## Wirkt den Slot. target_unit: Einheit unter dem Mauszeiger (oder null), point: Bodenpunkt unter dem Mauszeiger.
func request_cast(slot: int, target_unit: Node3D, point: Vector3) -> bool:
	var reason := check_cast(slot)
	var id := slots[slot] if slot >= 0 and slot < slots.size() else ""
	if reason != "":
		cast_failed.emit(hero, id, reason)
		return false
	hero.idle_time = 0.0
	var def := GameData.skill(id)
	var lvl := level_of(id)
	var cast_range := float(GameData.skill_value(id, lvl, "range", 0.0))
	match String(def.target):
		"self":
			return _execute(id, hero, hero.global_position)
		"point":
			var to := Vector3(point.x - hero.global_position.x, 0.0, point.z - hero.global_position.z)
			if to.length() > cast_range:
				point = hero.global_position + to.normalized() * cast_range
			return _execute(id, null, Vector3(point.x, 0.0, point.z))
		"enemy":
			var e := target_unit as Enemy
			if e == null or not e.is_alive():
				e = hero.enemies.nearest_enemy(point, 2.5) if hero.enemies != null else null
			if e == null:
				cast_failed.emit(hero, id, "Kein Gegner unter dem Mauszeiger.")
				return false
			return _cast_or_queue(id, e, cast_range + e.body_radius)
		"ally":
			var ally := target_unit as Hero
			if ally == null or not ally.is_alive():
				ally = hero
			return _cast_or_queue(id, ally, cast_range + 0.5)
	return false


func cancel_queue() -> void:
	_queued.clear()


func is_queued() -> bool:
	return not _queued.is_empty()


func _cast_or_queue(id: String, target: Node3D, reach: float) -> bool:
	if _flat_dist(target) <= reach:
		return _execute(id, target, target.global_position)
	_queued = {"id": id, "target": target, "reach": reach, "left": QUEUE_TIMEOUT}
	_chase_left = 0.0
	return true


func _execute(id: String, target: Node3D, point: Vector3) -> bool:
	var lvl := level_of(id)
	if not hero.spend_mana(mana_cost(id)):
		cast_failed.emit(hero, id, "Nicht genug Mana.")
		return false
	cooldowns[id] = float(GameData.skill_value(id, lvl, "cooldown", 0.0))
	cast_counts[id] = cast_counts.get(id, 0) + 1
	AbilityEffects.cast(id, lvl, hero, target, point)
	cast_performed.emit(hero, id, lvl)
	changed.emit()
	return true


func _physics_process(delta: float) -> void:
	for id in cooldowns:
		if cooldowns[id] > 0.0:
			cooldowns[id] = maxf(0.0, cooldowns[id] - delta)
	if _queued.is_empty() or hero == null:
		return
	var target: Variant = _queued.target
	_queued.left -= delta
	if _queued.left <= 0.0 or target == null or not is_instance_valid(target) or not target.call("is_alive") or not hero.is_alive():
		_queued.clear()
		return
	if _flat_dist(target) <= _queued.reach:
		var id: String = _queued.id
		_queued.clear()
		hero.has_move_target = false
		if check_cast(slots.find(id)) == "":
			_execute(id, target, target.global_position)
		return
	_chase_left -= delta
	if _chase_left <= 0.0:
		_chase_left = CHASE_INTERVAL
		hero.chase_point(target.global_position)


func _auto_equip(id: String) -> void:
	if GameData.skill(id).ultimate:
		if slots[ULT_SLOT] == "":
			slots[ULT_SLOT] = id
		return
	for s in NORMAL_SLOTS:
		if slots[s] == "":
			slots[s] = id
			return


func _flat_dist(node: Node3D) -> float:
	var d := node.global_position - hero.global_position
	return Vector2(d.x, d.z).length()
