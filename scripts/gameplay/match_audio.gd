class_name MatchAudio
extends Node
## Übersetzt Spielsignale einer Runde in Sounds. Enthält keine Spiellogik und verändert keinen Zustand;
## die Simulation weiß nichts von Audio.

var _match: MatchController


func bind(m: MatchController) -> void:
	_match = m
	m.combat.damage_applied.connect(_on_damage)
	m.spawner.enemy_spawned.connect(func(e: Enemy) -> void: Audio.play("enemy_spawn", e.global_position))
	m.spawner.enemy_killed.connect(func(e: Enemy, _i: DamageInfo) -> void: Audio.play("enemy_death", e.global_position))
	m.rewards.gold_awarded.connect(func(peer: int, _a: int, _p: Vector3) -> void:
		if peer == m.local_hero.peer_id:
			Audio.play("gold"))
	m.wave_manager.wave_announced.connect(func(_n: int, _w: Dictionary, _s: float) -> void: Audio.play("wave_announce"))
	m.wave_manager.wave_started.connect(func(_n: int, _w: Dictionary) -> void: Audio.play("wave_start"))
	# Nach der letzten Welle spielt stattdessen der Sieg-Jingle
	m.wave_manager.wave_completed.connect(func(n: int) -> void:
		if n < m.wave_manager.total_waves():
			Audio.play("wave_complete"))
	m.core.critical_changed.connect(func(critical: bool) -> void:
		if critical:
			Audio.play("core_critical"))
	for service in [m.upgrades, m.shop]:
		service.purchase_result.connect(func(peer: int, ok: bool, _msg: String) -> void:
			if peer == m.local_hero.peer_id:
				Audio.play("purchase_ok" if ok else "purchase_fail"))
	m.finished.connect(func(victory: bool) -> void: Audio.play("victory" if victory else "defeat"))
	for hero in m.heroes:
		track_hero(hero)


func track_hero(hero: Hero) -> void:
	hero.attack_started.connect(func(h: Hero, ranged: bool) -> void:
		Audio.play("spell_cast" if ranged else "swing", h.global_position))
	hero.abilities.cast_performed.connect(func(h: Hero, ability_id: String, _l: int) -> void:
		play_at("cast_" + ability_id, h.global_position))
	hero.abilities.cast_failed.connect(func(h: Hero, _id: String, _reason: String) -> void:
		if h == _match.local_hero:
			Audio.play("ability_fail"))
	hero.leveled_up.connect(func(h: Hero, _l: int) -> void:
		if h == _match.local_hero:
			Audio.play("level_up"))
	hero.died.connect(func(h: Hero) -> void:
		if h == _match.local_hero:
			Audio.play("hero_death"))


## Für Effekte ohne eigenes Signal (Feuerball-Explosion, Sterneneinschläge).
func play_at(event_id: String, pos: Vector3) -> void:
	Audio.play(event_id, pos)


func _on_damage(target: Node3D, info: DamageInfo) -> void:
	if not is_instance_valid(target):
		return
	var pos := target.global_position
	if info.type == DamageInfo.Type.TRUE and not info.is_crit:
		return   # Schaden über Zeit (Gift) tickt still
	var source := info.source if info.source_is_valid() else null
	if source is Hero:
		if info.is_crit:
			Audio.play("hit_crit", pos)
		elif info.type == DamageInfo.Type.MAGIC:
			Audio.play("spell_impact", pos)
		elif (source as Hero).data.get("main_attribute", "") == "agi":
			Audio.play("hit_dagger", pos)
		else:
			Audio.play("hit_sword", pos)
	elif source is Enemy:
		if target is DefenseCore:
			Audio.play("enemy_hit_core", pos)
		elif target is Hero:
			Audio.play("enemy_hit_hero", pos)
