extends RefCounted
## Kampfberechnung und Status-Effekte ohne Szene.


class Dummy:
	extends Node3D
	var health := HealthComponent.new()
	var armor := 0.0
	var mr := 0.0

	func get_armor() -> float:
		return armor

	func get_magic_resist() -> float:
		return mr


func test_armor_mitigation(t) -> void:
	var c := CombatService.new()
	var d := Dummy.new()
	d.armor = 50.0
	d.mr = 0.0
	t.eq(c.mitigate(100.0, DamageInfo.Type.PHYSICAL, d), 50.0, "50 Rüstung halbiert physischen Schaden")
	t.eq(c.mitigate(100.0, DamageInfo.Type.MAGIC, d), 100.0, "Rüstung wirkt nicht gegen Magie")
	t.eq(c.mitigate(100.0, DamageInfo.Type.TRUE, d), 100.0, "wahrer Schaden ignoriert alles")
	d.mr = 150.0
	t.eq(c.mitigate(100.0, DamageInfo.Type.MAGIC, d), 25.0, "150 Magieresistenz: 25 %% Schaden")
	d.armor = -30.0
	t.eq(c.mitigate(100.0, DamageInfo.Type.PHYSICAL, d), 100.0, "negative Rüstung erhöht den Schaden nicht")
	d.health.free()
	d.free()
	c.free()


func test_slow_does_not_stack(t) -> void:
	var st := StatusEffects.new()
	st.apply(StatusEffects.SLOW, 2.0, 0.2)
	st.apply(StatusEffects.SLOW, 1.0, 0.5)
	t.eq(st.move_multiplier(), 0.5, "stärkere Verlangsamung gilt, keine Addition")
	t.eq(st.remaining(StatusEffects.SLOW), 2.0, "längere Dauer bleibt")
	st.apply(StatusEffects.SLOW, 5.0, 0.95)
	t.eq(snappedf(st.move_multiplier(), 0.001), 0.3, "Verlangsamung gedeckelt (max. 70 %%)")
	st.tick(5.1)
	t.eq(st.move_multiplier(), 1.0, "Effekt läuft aus")
	t.check(not st.has(StatusEffects.SLOW), "entfernt")
	st.free()


func test_stun_and_cc_resist(t) -> void:
	var st := StatusEffects.new()
	t.eq(st.apply(StatusEffects.STUN, 1.0), 1.0, "volle Dauer ohne Widerstand")
	t.check(st.is_stunned(), "betäubt")
	st.tick(1.05)
	t.check(not st.is_stunned(), "Betäubung endet")
	st.cc_resist = 0.5
	t.eq(st.apply(StatusEffects.STUN, 1.0), 0.5, "50 %% Kontrollresistenz halbiert die Dauer")
	st.cc_resist = 1.0
	t.eq(st.apply(StatusEffects.STUN, 1.0), 0.0, "volle Resistenz: wirkungslos")
	st.free()
