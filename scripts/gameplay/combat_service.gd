class_name CombatService
extends Node
## Einziger Weg, Schaden zuzufügen. Läuft nur auf dem autoritativen Host.
## Rechnet Rüstung bzw. Magieresistenz des Ziels ein. Beteiligung (Gold/XP) hört auf `damage_applied`.

signal damage_applied(target: Node3D, info: DamageInfo)
signal damage_prevented(target: Node3D, source: Node, amount: float)

## Abschwächung: Schaden · K / (K + Rüstung). Bei K = 50 halbieren 50 Rüstung den Schaden.
var armor_constant := 50.0


func _ready() -> void:
	armor_constant = float(GameData.attribute_rules.get("armor_constant", 50.0))


## Fügt `target` Schaden zu, sofern es eine HealthComponent in `health` besitzt.
## Gibt den tatsächlich verursachten Schaden zurück.
func deal_damage(source: Node, target: Node3D, amount: float, type := DamageInfo.Type.PHYSICAL, is_crit := false) -> float:
	if not multiplayer.is_server():
		return 0.0
	if target == null or not is_instance_valid(target):
		return 0.0
	var health := target.get("health") as HealthComponent
	if health == null:
		push_warning("Ziel ohne HealthComponent: %s" % target.name)
		return 0.0
	var status: StatusEffects = target.get("status")
	if status != null and status.has(StatusEffects.UNTARGETABLE):
		return 0.0   # unverwundbar (Blade Dance)
	var info := DamageInfo.create(amount, type, source)
	info.is_crit = is_crit
	info.amount = mitigate(amount, type, target)
	# Schadensreduktion aus Zuständen (Segen, Bastion, Runen) – gedeckelt in StatusEffects
	if status != null and type != DamageInfo.Type.TRUE and status.damage_reduction() > 0.0:
		var before := info.amount
		info.amount *= 1.0 - status.damage_reduction()
		# Verhinderter Schaden ist die messbare Leistung von Segen/Bastion (Support-Beteiligung)
		damage_prevented.emit(target, status.source_of(StatusEffects.DAMAGE_REDUCTION), before - info.amount)
	var dealt := health.apply_damage(info)
	if dealt > 0.0 or info.absorbed > 0.0:
		damage_applied.emit(target, info)
	return dealt


## Schaden nach Rüstung/Magieresistenz des Ziels. Ziele ohne Werte nehmen vollen Schaden.
func mitigate(amount: float, type: DamageInfo.Type, target: Node) -> float:
	if type == DamageInfo.Type.TRUE:
		return amount
	var method := "get_armor" if type == DamageInfo.Type.PHYSICAL else "get_magic_resist"
	if not target.has_method(method):
		return amount
	var resist := maxf(0.0, float(target.call(method)))
	return amount * armor_constant / (armor_constant + resist)
