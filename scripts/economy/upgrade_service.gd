class_name UpgradeService
extends Node
## Attribut-Käufe gegen persönliches Gold. Läuft autoritativ auf dem Host.
## Ein Kauf zieht nur dann Gold ab, wenn er vollständig gültig ist. Die Referenz "attr:<a>:<n>" verhindert,
## dass ein doppelt gesendeter Kaufwunsch (Doppelklick, Netzwerkwiederholung) zweimal bucht.

signal purchase_result(peer_id: int, ok: bool, message: String)

var gold: GoldService


## Gibt {ok: bool, message: String} zurück.
func request_attribute(hero: Hero, attribute: String) -> Dictionary:
	var result := _try_attribute(hero, attribute)
	purchase_result.emit(hero.peer_id if hero != null else 0, result.ok, result.message)
	return result


func _try_attribute(hero: Hero, attribute: String) -> Dictionary:
	if not multiplayer.is_server():
		return {"ok": false, "message": "Nur der Host kann Käufe ausführen."}
	if hero == null or not is_instance_valid(hero):
		return {"ok": false, "message": "Kein Held."}
	if not (attribute in StatBlock.ATTRIBUTES):
		return {"ok": false, "message": "Unbekanntes Attribut."}
	var stats := hero.stats
	var cost := stats.upgrade_cost(attribute)
	var name: String = GameData.ATTRIBUTE_NAMES[attribute]
	if not gold.can_afford(hero.peer_id, cost):
		return {"ok": false, "message": "Nicht genug Gold für %s (%d benötigt, %d vorhanden)." % [name, cost, gold.balance(hero.peer_id)]}
	var ref := "attr:%s:%d" % [attribute, stats.bought[attribute]]
	if not gold.spend(hero.peer_id, cost, "attribute", ref):
		return {"ok": false, "message": "Kauf abgelehnt."}
	stats.add_bought_point(attribute)
	var note := " (über dem Soft Cap: halbe Wirkung)" if stats.effective_bought(attribute) < stats.bought[attribute] else ""
	return {"ok": true, "message": "%s +1 für %d Gold%s" % [name, cost, note]}
