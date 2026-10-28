class_name HealthComponent
extends Node
## Lebenspunkte einer Einheit oder eines Gebäudes.
## Garantiert: nie negative Werte, `died` genau einmal pro Leben, Heilung liefert nur den effektiven Anteil.

signal damaged(info: DamageInfo)
signal healed(amount: float, source: Node)
signal died(info: DamageInfo)
signal changed(current: float, maximum: float)
signal revived

signal shield_absorbed(amount: float, source: Node)
signal shield_changed(total: float)

@export var max_hp := 100.0
var hp := 100.0
var dead := false
var _shields: Array[Dictionary] = []   ## {amount, left, source}


func _physics_process(delta: float) -> void:
	if _shields.is_empty():
		return
	var before := _shields.size()
	for s in _shields:
		s.left -= delta
	_shields = _shields.filter(func(s: Dictionary) -> bool: return s.left > 0.0 and s.amount > 0.0)
	if _shields.size() != before:
		shield_changed.emit(shield_total())


func setup(maximum: float) -> void:
	max_hp = maxf(1.0, maximum)
	hp = max_hp
	dead = false
	changed.emit(hp, max_hp)


## Schild hinzufügen (absorbiert Schaden vor den LP, läuft nach `duration` aus).
func add_shield(amount: float, duration: float, source: Node = null) -> void:
	if dead or amount <= 0.0 or duration <= 0.0:
		return
	_shields.append({"amount": amount, "left": duration, "source": source})
	shield_changed.emit(shield_total())


func shield_total() -> float:
	var total := 0.0
	for s in _shields:
		total += s.amount
	return total


## Zieht Schaden ab (zuerst Schilde, älteste zuerst) und gibt die tatsächlich verlorenen LP zurück.
## Absorbierter Schaden steht in info.absorbed und wird je Schildquelle über shield_absorbed gemeldet.
func apply_damage(info: DamageInfo) -> float:
	if dead or info.amount <= 0.0:
		return 0.0
	var remaining := info.amount
	while remaining > 0.0 and not _shields.is_empty():
		var s: Dictionary = _shields[0]
		var take := minf(remaining, s.amount)
		s.amount -= take
		remaining -= take
		info.absorbed += take
		var src: Variant = s.source
		shield_absorbed.emit(take, src if src != null and is_instance_valid(src) else null)
		if s.amount <= 0.0:
			_shields.pop_front()
	if info.absorbed > 0.0:
		shield_changed.emit(shield_total())
	if remaining <= 0.0:
		return 0.0
	var dealt := minf(remaining, hp)
	hp -= dealt
	info.final_amount = dealt
	damaged.emit(info)
	changed.emit(hp, max_hp)
	if hp <= 0.0:
		hp = 0.0
		dead = true
		_shields.clear()
		died.emit(info)
	return dealt


## Heilt und gibt nur die effektive Heilung zurück; Überheilung zählt nicht.
func heal(amount: float, source: Node = null) -> float:
	if dead or amount <= 0.0:
		return 0.0
	var effective := minf(amount, max_hp - hp)
	if effective <= 0.0:
		return 0.0
	hp += effective
	healed.emit(effective, source)
	changed.emit(hp, max_hp)
	return effective


func revive(fraction := 1.0) -> void:
	hp = max_hp * clampf(fraction, 0.01, 1.0)
	dead = false
	revived.emit()
	changed.emit(hp, max_hp)


## Ändert das Maximum. Ein Zuwachs wird auch den aktuellen LP gutgeschrieben (Levelaufstieg, Stärke-Kauf),
## ein Rückgang kappt die aktuellen LP. Tote bleiben tot.
func set_max_hp(new_max: float) -> void:
	new_max = maxf(1.0, new_max)
	var gained := new_max - max_hp
	max_hp = new_max
	if not dead:
		hp = clampf(hp + maxf(0.0, gained), 0.0, max_hp)
	changed.emit(hp, max_hp)


func ratio() -> float:
	return hp / max_hp
