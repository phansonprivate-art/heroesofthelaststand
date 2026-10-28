class_name ShopService
extends Node
## Alle Käufe außer Attributen: Fähigkeiten lernen/verbessern, Ausrüstung und Verbrauchsgegenstände,
## Verkaufen, Team-Upgrades und Spenden. Läuft autoritativ auf dem Host.
## Grundsatz: erst vollständig prüfen, dann bezahlen, dann gutschreiben. Fehlgeschlagene Käufe kosten nichts
## und liefern immer einen verständlichen Grund.

signal purchase_result(peer_id: int, ok: bool, message: String)
signal team_upgraded(upgrade_id: String, level: int)

var gold: GoldService
var core: DefenseCore
var sell_ratio := 0.5
var team_levels: Dictionary = {}      ## upgrade_id -> Stufe
var _counter: Dictionary = {}         ## peer -> fortlaufende Kaufnummer (eindeutige Referenzen)


func _ready() -> void:
	sell_ratio = float(GameData.setting("rewards", "sell_ratio", 0.5))


# --- Fähigkeiten ---------------------------------------------------------------

func learn_ability(hero: Hero, ability_id: String) -> Dictionary:
	if not _authority():
		return _result(hero, false, "Nur der Host kann Käufe ausführen.")
	var reason := hero.abilities.check_learn(ability_id)
	if reason != "":
		return _result(hero, false, reason)
	var def := GameData.skill(ability_id)
	var level := hero.abilities.level_of(ability_id)
	var cost := hero.abilities.cost_for(ability_id)
	if not gold.can_afford(hero.peer_id, cost):
		return _result(hero, false, "Nicht genug Gold für %s (%d benötigt, %d vorhanden)." % [def.name, cost, gold.balance(hero.peer_id)])
	if not gold.spend(hero.peer_id, cost, "ability", "skill:%s:%d" % [ability_id, level + 1]):
		return _result(hero, false, "Kauf abgelehnt.")
	hero.abilities.learn(ability_id)
	var slot := hero.abilities.slots.find(ability_id)
	if level == 0:
		var where := " auf %s" % AbilityCaster.SLOT_KEYS[slot] if slot >= 0 else " (kein freier Slot – im Shop zuweisen)"
		return _result(hero, true, "%s gelernt%s." % [def.name, where])
	return _result(hero, true, "%s auf Stufe %d verbessert." % [def.name, level + 1])


# --- Gegenstände ---------------------------------------------------------------

func buy_item(hero: Hero, item_id: String) -> Dictionary:
	if not _authority():
		return _result(hero, false, "Nur der Host kann Käufe ausführen.")
	var def := GameData.item(item_id)
	if def.is_empty():
		return _result(hero, false, "Unbekannter Gegenstand.")
	var reason := hero.inventory.check_add(item_id)
	if reason != "":
		return _result(hero, false, reason)
	if not gold.can_afford(hero.peer_id, def.price):
		return _result(hero, false, "Nicht genug Gold für %s (%d benötigt, %d vorhanden)." % [def.name, def.price, gold.balance(hero.peer_id)])
	if not gold.spend(hero.peer_id, def.price, "item", "item:%s:%d" % [item_id, _next(hero.peer_id)]):
		return _result(hero, false, "Kauf abgelehnt.")
	hero.inventory.add(item_id)
	hero.apply_equipment()
	return _result(hero, true, "%s gekauft." % def.name)


## Verkauft einen angelegten Gegenstand (slot) oder einen aus der Tasche (bag_index >= 0).
func sell(hero: Hero, slot: String, bag_index := -1) -> Dictionary:
	if not _authority():
		return _result(hero, false, "Nur der Host kann verkaufen.")
	var item_id := hero.inventory.remove_from_bag(bag_index) if bag_index >= 0 else hero.inventory.remove_equipped(slot)
	if item_id == "":
		return _result(hero, false, "Nichts zu verkaufen.")
	var def := GameData.item(item_id)
	var refund := int(floor(def.price * sell_ratio))
	gold.grant(hero.peer_id, refund, "sell", "sell:%s:%d" % [item_id, _next(hero.peer_id)])
	hero.apply_equipment()
	return _result(hero, true, "%s für %d Gold verkauft." % [def.name, refund])


func equip_from_bag(hero: Hero, bag_index: int) -> Dictionary:
	var reason := hero.inventory.equip_from_bag(bag_index)
	if reason != "":
		return _result(hero, false, reason)
	hero.apply_equipment()
	return _result(hero, true, "Ausgerüstet.")


func unequip(hero: Hero, slot: String) -> Dictionary:
	var reason := hero.inventory.unequip(slot)
	if reason != "":
		return _result(hero, false, reason)
	hero.apply_equipment()
	return _result(hero, true, "In die Tasche gelegt.")


## Verbrauchsgegenstand aus Slot 0/1 benutzen.
func use_consumable(hero: Hero, slot_index: int) -> Dictionary:
	if not hero.is_alive():
		return _result(hero, false, "Du bist gefallen.")
	var item_id := hero.inventory.take_consumable(slot_index)
	if item_id == "":
		return _result(hero, false, "Verbrauchsslot %d ist leer." % (slot_index + 1))
	var use: Dictionary = GameData.item(item_id).use
	if use.has("heal_ratio"):
		hero.health.heal(hero.health.max_hp * float(use.heal_ratio), null)   # Selbstheilung: keine Support-Belohnung
	if use.has("reduction"):
		hero.status.apply(StatusEffects.DAMAGE_REDUCTION, float(use.get("duration", 4.0)), float(use.reduction), null)
	hero.idle_time = 0.0
	return _result(hero, true, "%s benutzt." % GameData.item(item_id).name)


# --- Team --------------------------------------------------------------------

func team_level(upgrade_id: String) -> int:
	return team_levels.get(upgrade_id, 0)


func team_cost(upgrade_id: String) -> int:
	var def := GameData.team_upgrade(upgrade_id)
	var lvl := team_level(upgrade_id)
	return int(def.costs[lvl]) if not def.is_empty() and lvl < def.costs.size() else 0


func buy_team_upgrade(hero: Hero, upgrade_id: String) -> Dictionary:
	if not _authority():
		return _result(hero, false, "Nur der Host kann Käufe ausführen.")
	var def := GameData.team_upgrade(upgrade_id)
	if def.is_empty():
		return _result(hero, false, "Unbekanntes Team-Upgrade.")
	var lvl := team_level(upgrade_id)
	if lvl >= def.costs.size():
		return _result(hero, false, "%s ist bereits auf Höchststufe." % def.name)
	var cost := team_cost(upgrade_id)
	if gold.team_balance() < cost:
		return _result(hero, false, "Nicht genug Team-Gold für %s (%d benötigt, %d vorhanden)." % [def.name, cost, gold.team_balance()])
	if not gold.spend_team(cost, "team_upgrade", "team:%s:%d" % [upgrade_id, lvl + 1]):
		return _result(hero, false, "Kauf abgelehnt.")
	team_levels[upgrade_id] = lvl + 1
	core.apply_upgrade(upgrade_id, lvl + 1, def.value_per_level)
	team_upgraded.emit(upgrade_id, lvl + 1)
	return _result(hero, true, "%s auf Stufe %d." % [def.name, lvl + 1])


func donate(hero: Hero, amount: int) -> Dictionary:
	if amount <= 0:
		return _result(hero, false, "Ungültiger Betrag.")
	if not gold.can_afford(hero.peer_id, amount):
		return _result(hero, false, "Nicht genug Gold zum Spenden (%d vorhanden)." % gold.balance(hero.peer_id))
	if not gold.donate_to_team(hero.peer_id, amount, "donate:%d:%d" % [hero.peer_id, _next(hero.peer_id)]):
		return _result(hero, false, "Spende abgelehnt.")
	return _result(hero, true, "%d Gold an das Team gespendet." % amount)


func _next(peer_id: int) -> int:
	_counter[peer_id] = _counter.get(peer_id, 0) + 1
	return _counter[peer_id]


func _authority() -> bool:
	return not is_inside_tree() or multiplayer.is_server()


func _result(hero: Hero, ok: bool, message: String) -> Dictionary:
	purchase_result.emit(hero.peer_id if hero != null else 0, ok, message)
	return {"ok": ok, "message": message}
