class_name DamageInfo
extends RefCounted
## Beschreibt einen einzelnen Schadensvorgang. Wird vom CombatService erzeugt und durch
## HealthComponent und Signale gereicht, damit spätere Systeme (Gold, XP, Beteiligung) alle Details sehen.

enum Type { PHYSICAL, MAGIC, TRUE }

var raw_amount := 0.0      ## Schaden vor Rüstung/Magieresistenz
var amount := 0.0          ## Schaden nach Abschwächung (angefragt)
var final_amount := 0.0    ## tatsächlich abgezogene Lebenspunkte (nie mehr als die vorhandenen)
var absorbed := 0.0        ## von Schilden abgefangen (zählt nicht als LP-Verlust)
var type := Type.PHYSICAL
var is_crit := false
var source: Node = null    ## Verursacher; vor Zugriff mit is_instance_valid prüfen


static func create(p_amount: float, p_type: Type, p_source: Node) -> DamageInfo:
	var info := DamageInfo.new()
	info.raw_amount = p_amount
	info.amount = p_amount
	info.type = p_type
	info.source = p_source
	return info


func source_is_valid() -> bool:
	return source != null and is_instance_valid(source)
