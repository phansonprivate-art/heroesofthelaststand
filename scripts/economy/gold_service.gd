class_name GoldService
extends Node
## Zentrale Verwaltung des persönlichen Golds. Läuft autoritativ auf dem Host.
## Garantien:
##  - kein negativer Kontostand, fehlgeschlagene Käufe ziehen nichts ab
##  - jede Buchung hat Grund und Referenz; dieselbe Referenz wird für denselben Spieler nur einmal gebucht
##  - alle Buchungen werden protokolliert (Grundlage für Telemetrie/Balancing in Phase 3/6)
## Team-Gold folgt in Phase 3.

signal balance_changed(peer_id: int, balance: int)
signal transaction_recorded(entry: Dictionary)

var _balances: Dictionary = {}     ## peer_id -> int
var _seen_refs: Dictionary = {}    ## "peer|ref" -> true
var _log: Array[Dictionary] = []
var _next_id := 1
var unlimited := false   ## Testmodus: Ausgaben gelingen und werden gebucht, ziehen aber nichts vom Guthaben ab


## Team-Gold ist ein eigenes Konto (TEAM_PEER), getrennt vom persönlichen Gold.
## Es wird nie stillschweigend aus persönlichem Gold gespeist – nur durch Wellen und ausdrückliche Spenden.
const TEAM_PEER := 0


func _init() -> void:
	_balances[TEAM_PEER] = 0


func team_balance() -> int:
	return balance(TEAM_PEER)


func grant_team(amount: int, reason: String, ref: String) -> bool:
	return grant(TEAM_PEER, amount, reason, ref)


func spend_team(amount: int, reason: String, ref: String) -> bool:
	return spend(TEAM_PEER, amount, reason, ref)


## Ausdrückliche Spende eines Spielers an das Team (zwei Buchungen mit derselben Referenz).
func donate_to_team(peer_id: int, amount: int, ref: String) -> bool:
	if peer_id == TEAM_PEER or not spend(peer_id, amount, "donation", ref):
		return false
	grant(TEAM_PEER, amount, "donation", ref)
	return true


func register_player(peer_id: int, start_gold: int) -> void:
	if _balances.has(peer_id):
		return
	_balances[peer_id] = 0
	grant(peer_id, start_gold, "start", "start")


func balance(peer_id: int) -> int:
	return _balances.get(peer_id, 0)


## Vergibt Gold. Gibt false zurück, wenn der Betrag ungültig ist oder die Referenz schon gebucht wurde.
func grant(peer_id: int, amount: int, reason: String, ref: String) -> bool:
	if not _accept(peer_id, amount, ref):
		return false
	_balances[peer_id] += amount
	_record(peer_id, amount, reason, ref)
	return true


## Gibt Gold aus. Gibt false zurück (ohne Abzug), wenn nicht genug Gold vorhanden ist,
## der Betrag ungültig ist oder dieselbe Referenz schon gebucht wurde (z. B. Doppelklick).
func spend(peer_id: int, amount: int, reason: String, ref: String) -> bool:
	if not _accept(peer_id, amount, ref):
		return false
	if _balances[peer_id] < amount and not unlimited:
		return false
	if not unlimited:
		_balances[peer_id] -= amount
	_record(peer_id, -amount, reason, ref)
	return true


func can_afford(peer_id: int, amount: int) -> bool:
	return balance(peer_id) >= amount


func transactions(peer_id := -1) -> Array[Dictionary]:
	if peer_id < 0:
		return _log
	var result: Array[Dictionary] = []
	for e in _log:
		if e.peer == peer_id:
			result.append(e)
	return result


## Summe der Buchungen eines Spielers nach Grund, z. B. {"kill": 120, "wave_bonus": 300, "attribute": -216}
func totals_by_reason(peer_id: int) -> Dictionary:
	var totals := {}
	for e in _log:
		if e.peer == peer_id:
			totals[e.reason] = totals.get(e.reason, 0) + int(e.amount)
	return totals


func _accept(peer_id: int, amount: int, ref: String) -> bool:
	# Außerhalb des Szenenbaums (Tests, Simulationen) gibt es kein Netzwerk – dann gilt der Dienst als Host.
	if is_inside_tree() and not multiplayer.is_server():
		return false
	if amount <= 0 or ref.is_empty() or not _balances.has(peer_id):
		return false
	return not _seen_refs.has("%d|%s" % [peer_id, ref])


func _record(peer_id: int, amount: int, reason: String, ref: String) -> void:
	_seen_refs["%d|%s" % [peer_id, ref]] = true
	var entry := {"id": _next_id, "peer": peer_id, "amount": amount, "reason": reason, "ref": ref,
		"balance": _balances[peer_id], "time": Time.get_ticks_msec()}
	_next_id += 1
	_log.append(entry)
	transaction_recorded.emit(entry)
	balance_changed.emit(peer_id, _balances[peer_id])
