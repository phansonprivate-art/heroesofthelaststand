class_name StatBlock
extends RefCounted
## Werte eines Helden: Attribute (Stärke, Beweglichkeit, Intelligenz), daraus abgeleitete Kampfwerte,
## gekaufte Attributpunkte und Level/XP. Reine Logik ohne Szene – vollständig testbar.
## Alle Faktoren, Obergrenzen und Kosten kommen aus data/balance/attributes.json.

signal changed
signal leveled_up(new_level: int)

const ATTRIBUTES := ["str", "agi", "int"]

var def: Dictionary = {}      ## Heldendefinition aus GameData
var rules: Dictionary = {}    ## Attributregeln aus GameData
var level := 1
var xp := 0                   ## XP innerhalb der aktuellen Stufe
var total_xp := 0
var bought := {"str": 0, "agi": 0, "int": 0}
var bonus := {}               ## flache Boni (Ausrüstung, Phase 3): z. B. {"str": 5, "armor": 10}


static func create(hero_def: Dictionary, attribute_rules: Dictionary) -> StatBlock:
	var s := StatBlock.new()
	s.def = hero_def
	s.rules = attribute_rules
	return s


# --- Attribute ---------------------------------------------------------------

func attribute(a: String) -> float:
	return float(def.attributes[a]) + float(def.growth[a]) * (level - 1) + effective_bought(a) + _bonus(a)


## Gekaufte Punkte mit Soft Cap: oberhalb der Grenze wirkt jeder Punkt nur noch anteilig.
func effective_bought(a: String) -> float:
	var n: int = bought[a]
	var cap := int(_rule("upgrade", "soft_cap", 40))
	var eff := float(_rule("upgrade", "soft_cap_efficiency", 0.5))
	return mini(n, cap) + maxi(0, n - cap) * eff


func upgrade_cost(a: String) -> int:
	return cost_for(bought[a], rules)


## Kosten = round(cost_base · cost_growth^n), n = bereits gekaufte Punkte dieses Attributs.
static func cost_for(n: int, attribute_rules: Dictionary) -> int:
	var up: Dictionary = attribute_rules.get("upgrade", {})
	return roundi(float(up.get("cost_base", 100)) * pow(float(up.get("cost_growth", 1.16)), n))


func is_beyond_soft_cap(a: String) -> bool:
	return bought[a] >= int(_rule("upgrade", "soft_cap", 40))


## Kopie mit einem zusätzlich gekauften Punkt – nur für die Vorschau „was bringt +1?“ (kein Signal, keine Kosten).
func preview_with_point(a: String) -> StatBlock:
	var s := StatBlock.create(def, rules)
	s.level = level
	s.bought = bought.duplicate()
	s.bought[a] += 1
	s.bonus = bonus.duplicate()
	return s


## Bucht einen gekauften Punkt. Bezahlung prüft der Aufrufer (UpgradeService).
func add_bought_point(a: String) -> void:
	bought[a] += 1
	changed.emit()


# --- Abgeleitete Werte -----------------------------------------------------

func max_hp() -> float:
	return def.base_hp + _from_attrs("max_hp") + _bonus("max_hp")


func hp_regen() -> float:
	return def.base_hp_regen + _from_attrs("hp_regen") + _bonus("hp_regen")


func max_mana() -> float:
	return def.base_mana + _from_attrs("max_mana") + _bonus("max_mana")


func mana_regen() -> float:
	return def.base_mana_regen + _from_attrs("mana_regen") + _bonus("mana_regen")


func armor() -> float:
	return minf(def.base_armor + _from_attrs("armor") + _bonus("armor"), _cap("armor", 200.0))


func magic_resist() -> float:
	return minf(def.base_magic_resist + _from_attrs("magic_resist") + _bonus("magic_resist"), _cap("magic_resist", 200.0))


## Schaden eines normalen Angriffs (vor Krit und Rüstung des Ziels).
func attack_damage() -> float:
	var dmg: float = def.base_attack + attribute(def.main_attribute) * float(rules.get("main_attribute_damage", 0.8))
	if def.damage_type == "magic":
		dmg += _from_attrs("magic_damage")
	else:
		dmg += _from_attrs("physical_damage")
	return dmg + _bonus("attack_damage")


func attack_speed_bonus() -> float:
	return minf(_from_attrs("attack_speed") + _bonus("attack_speed"), _cap("attack_speed_bonus", 1.5))


func attack_interval() -> float:
	return def.base_attack_interval / (1.0 + attack_speed_bonus())


func crit_chance() -> float:
	return clampf(def.base_crit + _from_attrs("crit_chance") + _bonus("crit_chance"), 0.0, _cap("crit_chance", 0.5))


func crit_multiplier() -> float:
	return float(rules.get("crit_multiplier", 1.75))


func move_speed() -> float:
	return minf(def.base_move_speed + _from_attrs("move_speed") + _bonus("move_speed"), _cap("move_speed", 8.5))


## Multiplikator für Fähigkeiten (Phase 3): 1.0 + Anteil aus Intelligenz
func ability_power() -> float:
	return 1.0 + _from_attrs("ability_power") + _bonus("ability_power")


func heal_power() -> float:
	return 1.0 + _from_attrs("heal_power") + _bonus("heal_power")


func attack_range() -> float:
	return def.attack_range


func damage_type() -> DamageInfo.Type:
	return DamageInfo.Type.MAGIC if def.damage_type == "magic" else DamageInfo.Type.PHYSICAL


## Würfelt einen Angriff aus. Gibt {amount, crit} zurück.
func roll_attack(rng: RandomNumberGenerator, extra_crit := 0.0) -> Dictionary:
	# Buffs (z. B. Shadow Dance) dürfen die Krit-Chance kurzzeitig über die Attributgrenze heben, aber nie über 100 %
	var crit := rng.randf() < minf(1.0, crit_chance() + extra_crit)
	var amount := attack_damage() * (crit_multiplier() if crit else 1.0)
	return {"amount": amount, "crit": crit}


# --- Level und XP ------------------------------------------------------------

func max_level() -> int:
	return int(_rule("levels", "max_level", 20))


func xp_to_next() -> int:
	var table: Array = rules.get("levels", {}).get("xp_to_next", [])
	if level >= max_level() or table.is_empty():
		return 0
	return int(table[mini(level - 1, table.size() - 1)])


## Fügt XP hinzu und steigt ggf. mehrere Stufen auf. Gibt die Anzahl der Aufstiege zurück.
func add_xp(amount: int) -> int:
	if amount <= 0 or level >= max_level():
		return 0
	total_xp += amount
	xp += amount
	var gained := 0
	while level < max_level() and xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		gained += 1
		leveled_up.emit(level)
	if level >= max_level():
		xp = 0
	changed.emit()
	return gained


func xp_ratio() -> float:
	var need := xp_to_next()
	return 1.0 if need <= 0 else float(xp) / need


# --- Hilfen ----------------------------------------------------------------

## Summe eines Werts über alle Attribute laut per_point-Tabelle.
func _from_attrs(stat: String) -> float:
	var total := 0.0
	var per_point: Dictionary = rules.get("per_point", {})
	for a in ATTRIBUTES:
		total += attribute(a) * float(per_point.get(a, {}).get(stat, 0.0))
	return total


func _bonus(stat: String) -> float:
	return float(bonus.get(stat, 0.0))


func _cap(key: String, fallback: float) -> float:
	return float(rules.get("caps", {}).get(key, fallback))


func _rule(section: String, key: String, fallback: Variant) -> Variant:
	return rules.get(section, {}).get(key, fallback)
