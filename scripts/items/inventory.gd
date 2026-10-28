class_name Inventory
extends RefCounted
## Ausrüstung eines Helden: sechs Slots (Waffe, Rüstung, Helm, Schuhe, Ring, Amulett), eine Tasche
## für Ersatzteile und zwei Verbrauchsslots mit Stapeln. Reine Datenhaltung – Kauf und Bezahlung
## erledigt der ShopService.

signal changed

const EQUIP_SLOTS := ["weapon", "armor", "helmet", "boots", "ring", "amulet"]
const SLOT_NAMES := {"weapon": "Waffe", "armor": "Rüstung", "helmet": "Helm", "boots": "Schuhe", "ring": "Ring", "amulet": "Amulett"}

var equipment: Dictionary = {}            ## slot -> item_id
var bag: Array[String] = []
var consumables: Array[Dictionary] = [{}, {}]   ## je Slot {id, count} oder leer
var bag_size := 6


func _init(p_bag_size := 6, consumable_slots := 2) -> void:
	bag_size = p_bag_size
	consumables.clear()
	for i in consumable_slots:
		consumables.append({})


## Summe der Werte aller angelegten Gegenstände (für StatBlock.bonus).
func stat_bonus() -> Dictionary:
	var total := {}
	for slot in equipment:
		for key in GameData.item(equipment[slot]).get("stats", {}):
			total[key] = total.get(key, 0.0) + float(GameData.item(equipment[slot]).stats[key])
	return total


## Grund, warum der Gegenstand nicht aufgenommen werden kann ("" = möglich).
func check_add(item_id: String) -> String:
	var def := GameData.item(item_id)
	if def.is_empty():
		return "Unbekannter Gegenstand."
	if def.slot == "consumable":
		for c in consumables:
			if c.is_empty() or (c.id == item_id and c.count < def.max_stack):
				return ""
		return "Beide Verbrauchsslots sind belegt."
	if not equipment.has(def.slot) or bag.size() < bag_size:
		return ""
	return "Slot %s belegt und Tasche voll." % SLOT_NAMES[def.slot]


## Nimmt einen Gegenstand auf: freier Ausrüstungsslot, sonst Tasche. Gibt "" oder den Grund zurück.
func add(item_id: String) -> String:
	var reason := check_add(item_id)
	if reason != "":
		return reason
	var def := GameData.item(item_id)
	if def.slot == "consumable":
		for i in consumables.size():
			if not consumables[i].is_empty() and consumables[i].id == item_id and consumables[i].count < def.max_stack:
				consumables[i].count += 1
				changed.emit()
				return ""
		for i in consumables.size():
			if consumables[i].is_empty():
				consumables[i] = {"id": item_id, "count": 1}
				changed.emit()
				return ""
	elif not equipment.has(def.slot):
		equipment[def.slot] = item_id
	else:
		bag.append(item_id)
	changed.emit()
	return ""


## Legt einen Gegenstand aus der Tasche an; ein belegter Slot wandert in die Tasche (Tausch).
func equip_from_bag(index: int) -> String:
	if index < 0 or index >= bag.size():
		return "Kein Gegenstand an dieser Stelle."
	var item_id := bag[index]
	var slot: String = GameData.item(item_id).slot
	bag.remove_at(index)
	if equipment.has(slot):
		bag.append(equipment[slot])
	equipment[slot] = item_id
	changed.emit()
	return ""


func unequip(slot: String) -> String:
	if not equipment.has(slot):
		return "Slot ist leer."
	if bag.size() >= bag_size:
		return "Tasche voll."
	bag.append(equipment[slot])
	equipment.erase(slot)
	changed.emit()
	return ""


func remove_equipped(slot: String) -> String:
	var id: String = equipment.get(slot, "")
	if id != "":
		equipment.erase(slot)
		changed.emit()
	return id


func remove_from_bag(index: int) -> String:
	if index < 0 or index >= bag.size():
		return ""
	var id := bag[index]
	bag.remove_at(index)
	changed.emit()
	return id


## Nimmt eine Ladung aus dem Verbrauchsslot und gibt die Item-ID zurück ("" wenn leer).
func take_consumable(slot_index: int) -> String:
	if slot_index < 0 or slot_index >= consumables.size() or consumables[slot_index].is_empty():
		return ""
	var c: Dictionary = consumables[slot_index]
	c.count -= 1
	var id: String = c.id
	if c.count <= 0:
		consumables[slot_index] = {}
	changed.emit()
	return id
