extends RefCounted
## HealthComponent: Schaden, Tod, Heilung.


func _new_health(max_hp: float) -> HealthComponent:
	var h := HealthComponent.new()
	h.setup(max_hp)
	return h


func test_damage_never_negative(t) -> void:
	var h := _new_health(100)
	var dealt := h.apply_damage(DamageInfo.create(250, DamageInfo.Type.PHYSICAL, null))
	t.eq(dealt, 100.0, "nur vorhandene Lebenspunkte werden abgezogen")
	t.eq(h.hp, 0.0, "Lebenspunkte nicht negativ")
	t.check(h.dead, "tot bei 0")
	h.free()


func test_died_emitted_once(t) -> void:
	var h := _new_health(50)
	var deaths := [0]
	h.died.connect(func(_i: DamageInfo) -> void: deaths[0] += 1)
	h.apply_damage(DamageInfo.create(60, DamageInfo.Type.PHYSICAL, null))
	h.apply_damage(DamageInfo.create(60, DamageInfo.Type.PHYSICAL, null))
	t.eq(deaths[0], 1, "died genau einmal")
	t.eq(h.apply_damage(DamageInfo.create(10, DamageInfo.Type.PHYSICAL, null)), 0.0, "kein Schaden an Toten")
	h.free()


func test_heal_returns_only_effective(t) -> void:
	var h := _new_health(100)
	h.apply_damage(DamageInfo.create(30, DamageInfo.Type.PHYSICAL, null))
	t.eq(h.heal(50), 30.0, "Überheilung zählt nicht")
	t.eq(h.heal(10), 0.0, "volle Lebenspunkte: keine effektive Heilung")
	t.eq(h.hp, 100.0, "nicht über Maximum")
	h.free()


func test_revive(t) -> void:
	var h := _new_health(80)
	h.apply_damage(DamageInfo.create(80, DamageInfo.Type.PHYSICAL, null))
	h.revive(1.0)
	t.check(not h.dead, "wiederbelebt")
	t.eq(h.hp, 80.0, "volle Lebenspunkte nach Wiederbelebung")
	h.free()


func test_zero_or_negative_damage_ignored(t) -> void:
	var h := _new_health(100)
	t.eq(h.apply_damage(DamageInfo.create(0, DamageInfo.Type.PHYSICAL, null)), 0.0, "0 Schaden")
	t.eq(h.apply_damage(DamageInfo.create(-20, DamageInfo.Type.PHYSICAL, null)), 0.0, "negativer Schaden heilt nicht")
	t.eq(h.hp, 100.0, "unverändert")
	h.free()
