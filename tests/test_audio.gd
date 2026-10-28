extends RefCounted
## AudioService und Anbindung an Spielereignisse.

const MATCH_SCENE := preload("res://scenes/main/match.tscn")


func test_config_valid(t) -> void:
	t.eq(Audio.errors.size(), 0, "Audio-Konfiguration fehlerfrei: %s" % str(Audio.errors))
	for id in ["hit_sword", "hit_dagger", "hit_crit", "swing", "spell_cast", "spell_impact", "enemy_hit_hero", "enemy_hit_core",
			"enemy_death", "enemy_spawn", "hero_death", "level_up", "gold", "core_critical", "wave_announce", "wave_start",
			"wave_complete", "victory", "defeat", "ui_click", "purchase_ok", "purchase_fail"]:
		t.check(Audio.has_event(id), "Ereignis vorhanden: %s" % id)
	for bus in ["SFX", "UI", "Music"]:
		t.check(AudioServer.get_bus_index(bus) >= 0, "Bus vorhanden: %s" % bus)


func test_rate_limiting(t) -> void:
	Audio._last_played.clear()
	t.check(Audio.play("gold"), "erster Sound spielt")
	t.check(not Audio.play("gold"), "Mindestabstand verhindert sofortige Wiederholung")
	t.check(not Audio.play("gibts_nicht"), "unbekanntes Ereignis wird ignoriert")
	Audio._last_played.clear()
	# hero_death: höchstens 1 gleichzeitig, Mindestabstand 0,5 s
	Audio.play("hero_death")
	Audio._last_played.erase("hero_death")
	t.check(not Audio.play("hero_death"), "Höchstzahl gleichzeitiger Wiedergaben greift")
	Audio.muted = true
	Audio._last_played.clear()
	t.check(not Audio.play("ui_click"), "stumm: nichts wird abgespielt")
	Audio.muted = false


func test_match_events_trigger_sounds(t) -> void:
	Session.hero_id = "guardian"
	var m: MatchController = MATCH_SCENE.instantiate()
	m.waves_override = [GameData.normalize_wave({"prepare_seconds": 0, "groups": [{"enemy": "grunt", "count": 1, "path": 1}, {"enemy": "grunt", "count": 1, "path": 0, "delay": 300}]}, 1)]
	t.root.add_child(m)
	await t.frames(80)
	Audio.stop_all()
	Audio._last_played.clear()
	var e: Enemy = m.spawner.alive_enemies()[0]
	m.combat.deal_damage(m.local_hero, e, 10, DamageInfo.Type.PHYSICAL)
	t.check(Audio._last_played.has("hit_sword"), "Schwerttreffer klingt")
	t.check(Audio._last_played.has("bone_crack"), "mit Knochen-Schicht")
	m.local_hero._start_attack(e)
	t.check(Audio._last_played.has("swing"), "Ausholen klingt (Schwung)")
	m.combat.deal_damage(m.local_hero, e, 99999, DamageInfo.Type.TRUE, true)
	t.check(Audio._last_played.has("hit_crit"), "Krit klingt")
	t.check(Audio._last_played.has("blade_ring"), "Krit mit Klingen-Schicht")
	t.check(Audio._last_played.has("enemy_death"), "Gegnertod klingt")
	t.check(Audio._last_played.has("gold"), "Gold klingt")
	m.combat.deal_damage(e, m.core, 5)
	t.check(Audio._last_played.has("enemy_hit_core"), "Kerntreffer klingt")
	m.request_attribute_upgrade("str")
	t.check(Audio._last_played.has("purchase_ok"), "erfolgreicher Kauf klingt")
	m.queue_free()
	await t.frames(2)
