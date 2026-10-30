class_name StatusEffects
extends Node
## Zeitlich begrenzte Zustände einer Einheit.
## Regeln:
##  - gleiche Effekte stapeln nicht: Dauer wird erneuert, die stärkere Wirkung gilt (Ausnahme: apply_stacking)
##  - cc_resist (z. B. Bosse) verkürzt die Dauer von Kontrolleffekten (stun, slow, taunt, chill)
##  - last_gain = tatsächlich hinzugekommene Wirkdauer der letzten Anwendung (Grundlage gegen Belohnungs-Farmen)
## Effekte mit Schaden über Zeit (poison, burn) rufen jede Sekunde dot_handler(source, amount, element) auf.

signal effects_changed

const SLOW := "slow"
const STUN := "stun"
const TAUNT := "taunt"
const POISON := "poison"
const DAMAGE_REDUCTION := "damage_reduction"
const HASTE := "haste"            ## Angriffstempo-Bonus (Anteil)
const CHILL := "chill"            ## Unterkühlung: Angriffstempo-Malus (Anteil), z. B. vom Eisdrachen
const FROSTBITE := "frostbite"    ## Erfrierung: Stapel im Schneesturm, bei voller Zahl friert die Einheit ein
const BURN := "burn"              ## Verbrennung: Schaden über Zeit (magnitude = Schaden je Sekunde), z. B. Feuerdrache
const ARMOR_SHRED := "armor_shred"   ## senkt Rüstung und Magieresistenz um magnitude (Drachengebrüll)
const EMPOWER := "empower"        ## Gegner verursachen magnitude mehr Schaden (Anteil, Drachengebrüll)
const DOTS := {POISON: "poison", BURN: "fire"}   ## Schaden über Zeit -> Element für den dot_handler
const SWIFT := "swift"            ## Lauftempo-Bonus (Anteil)
const CRIT_BONUS := "crit_bonus"
const ARMOR_BONUS := "armor_bonus"
const UNTARGETABLE := "untargetable"   ## unverwundbar und für Gegner unsichtbar (Blade Dance); die Fähigkeit führt den Helden
const CHANNEL := "channel"             ## kanalisiert (Dagger Cyclone): steht still, ein Bewegungsbefehl bricht ab
const WHIRL := "whirl"                 ## wirbelt (Iron Maelstrom): läuft frei, aber keine normalen Angriffe
const SANCTUARY := "sanctuary"         ## am Brunnen der Erholung: nur Bewegung – keine Angriffe, keine Zauber
const CONTROL := [SLOW, STUN, TAUNT, CHILL]
const MAX_DAMAGE_REDUCTION := 0.75

var cc_resist := 0.0          ## 0 = volle Wirkung, 0.5 = halbe Dauer
var max_slow := 0.7
var last_gain := 0.0
var dot_handler: Callable     ## func(source: Node, amount: float, element: String)
var _effects: Dictionary = {}  ## id -> {left, magnitude, source, stacks, tick}


## Wendet einen Effekt an. Gibt die tatsächliche Dauer zurück (0, wenn wirkungslos).
func apply(id: String, duration: float, magnitude := 0.0, source: Node = null) -> float:
	var d := duration * (1.0 - cc_resist) if id in CONTROL else duration
	last_gain = 0.0
	if d <= 0.0:
		return 0.0
	var current: Dictionary = _effects.get(id, {})
	if current.is_empty():
		_effects[id] = {"left": d, "magnitude": magnitude, "source": source, "stacks": 1, "tick": 1.0}
		last_gain = d
	else:
		last_gain = maxf(0.0, d - current.left)
		current.left = maxf(current.left, d)
		if magnitude >= current.magnitude:
			current.magnitude = magnitude
			current.source = source
		elif last_gain > 0.0:
			current.source = source
	effects_changed.emit()
	return d


## Stapelbarer Effekt (Gift): bis max_stacks Stapel, jede Anwendung erneuert die Dauer.
func apply_stacking(id: String, duration: float, magnitude_per_stack: float, max_stacks: int, source: Node = null) -> int:
	var current: Dictionary = _effects.get(id, {})
	if current.is_empty():
		_effects[id] = {"left": duration, "magnitude": magnitude_per_stack, "source": source, "stacks": 1, "tick": 1.0}
		last_gain = duration
	else:
		last_gain = maxf(0.0, duration - current.left)
		current.left = maxf(current.left, duration)
		current.magnitude = maxf(current.magnitude, magnitude_per_stack)
		current.stacks = mini(current.stacks + 1, maxi(1, max_stacks))
		current.source = source
	effects_changed.emit()
	return _effects[id].stacks


func has(id: String) -> bool:
	return _effects.has(id)


func remaining(id: String) -> float:
	return _effects[id].left if _effects.has(id) else 0.0


func magnitude(id: String) -> float:
	return _effects[id].magnitude if _effects.has(id) else 0.0


func stacks(id: String) -> int:
	return _effects[id].stacks if _effects.has(id) else 0


func source_of(id: String) -> Node:
	if not _effects.has(id):
		return null
	var s: Variant = _effects[id].source
	return s if s != null and is_instance_valid(s) else null


func is_stunned() -> bool:
	return _effects.has(STUN)


## Multiplikator für die Bewegungsgeschwindigkeit (1.0 = normal).
func move_multiplier() -> float:
	var m := 1.0 + magnitude(SWIFT)
	if _effects.has(SLOW):
		m *= 1.0 - clampf(_effects[SLOW].magnitude, 0.0, max_slow)
	return m


## Multiplikator für das Angriffstempo (1.0 = normal). Unterkühlung bremst wie ein Slow, gleiche Obergrenze.
func attack_speed_multiplier() -> float:
	return 1.0 - clampf(magnitude(CHILL), 0.0, max_slow)


func damage_reduction() -> float:
	return clampf(magnitude(DAMAGE_REDUCTION), 0.0, MAX_DAMAGE_REDUCTION)


func active_ids() -> Array:
	return _effects.keys()


## Beendet einen Effekt vorzeitig (z. B. am Ende einer Fähigkeit).
func remove(id: String) -> void:
	if _effects.erase(id):
		effects_changed.emit()


func clear() -> void:
	if not _effects.is_empty():
		_effects.clear()
		effects_changed.emit()


func tick(delta: float) -> void:
	if _effects.is_empty():
		return
	var expired := []
	for id in _effects:
		var e: Dictionary = _effects[id]
		if DOTS.has(id) and dot_handler.is_valid():
			e.tick -= delta
			while e.tick <= 0.0:
				e.tick += 1.0
				var src: Variant = e.source
				dot_handler.call(src if src != null and is_instance_valid(src) else null, e.magnitude * e.stacks, String(DOTS[id]))
		e.left -= delta
		if e.left <= 0.0:
			expired.append(id)
	for id in expired:
		_effects.erase(id)
	if not expired.is_empty():
		effects_changed.emit()


func _physics_process(delta: float) -> void:
	tick(delta)
