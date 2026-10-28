class_name TelemetryService
extends Node
## Sammelt Balancing-Daten einer Runde und schreibt sie in den TelemetryStore:
## je Welle und Spieler (Gold nach Quelle, XP, Schaden, Tode …), je Welle und Gegnertyp,
## alle Gold-Transaktionen, Levelaufstiege und den Endstand jedes Helden.
## Geschrieben wird am Wellenende und am Rundenende; eine abgebrochene Runde wird als "aborted" vermerkt.
## Erfasst nur Spielwerte, keine persönlichen Daten.

const GAME_VERSION := "0.3"

var enabled := true
var match_id := ""
var store: TelemetryStore

var _match: MatchController
var _game_time := 0.0
var _started_at := ""
var _finished := false
var _wave_start_s := 0.0
var _players: Dictionary = {}     ## peer -> Zählwerte der laufenden Welle
var _enemies: Dictionary = {}     ## enemy_id -> Zählwerte der laufenden Welle
var _spawn_time: Dictionary = {}  ## enemy uid -> Spawnzeit (s)
var _deaths_total: Dictionary = {}
var _pending: Dictionary = {}     ## table -> Array an noch nicht geschriebenen Zeilen
var _cast_snapshot: Dictionary = {} ## peer -> cast_counts beim letzten Wellenende


func bind(m: MatchController, directory: String, p_enabled := true) -> void:
	_match = m
	enabled = p_enabled
	store = TelemetryStore.new(directory)
	_game_time = 0.0
	_started_at = Time.get_datetime_string_from_system(true)
	match_id = "%s-%06x" % [_started_at.replace(":", "").replace("-", ""), randi() % 0xFFFFFF]
	for hero in m.heroes:
		track_hero(hero)
	_reset_wave()
	# Buchungen vor dem Anschluss (Startgold) nachtragen
	for e in m.gold.transactions():
		_on_transaction(e)
	m.gold.transaction_recorded.connect(_on_transaction)
	m.combat.damage_applied.connect(_on_damage)
	m.spawner.enemy_spawned.connect(_on_enemy_spawned)
	m.spawner.enemy_killed.connect(_on_enemy_killed)
	m.rewards.xp_awarded.connect(_on_xp)
	m.rewards.wave_rewards.connect(_on_wave_rewards)
	m.wave_manager.wave_started.connect(func(_n: int, _w: Dictionary) -> void: _wave_start_s = now_s())
	m.wave_manager.wave_completed.connect(_on_wave_completed)


## Spielzeit seit Rundenstart in Sekunden (steht während der Pause still, wie die Simulation).
func now_s() -> float:
	return _game_time


func _process(delta: float) -> void:
	_game_time += delta


## Rundenende: offene Welle, Helden-Endstand und Runde schreiben.
func finish(result: String) -> void:
	if _finished or _match == null:
		return
	_finished = true
	# Laufende (nicht abgeschlossene) Welle mitschreiben, z. B. bei Niederlage oder Abbruch
	var current := _match.wave_manager.current_wave_number()
	if not _match.wave_manager.is_wave_completed(current):
		_flush_wave(current, false)
	var heroes_ids: PackedStringArray = []
	for hero in _match.heroes:
		if not is_instance_valid(hero):
			continue
		heroes_ids.append(hero.hero_id)
		var s := hero.stats
		var totals := _match.gold.totals_by_reason(hero.peer_id)
		var earned := 0
		var spent := 0
		for reason in totals:
			if totals[reason] > 0:
				earned += totals[reason]
			else:
				spent -= totals[reason]
		_queue("hero_end", {"match_id": match_id, "peer_id": hero.peer_id, "hero_id": hero.hero_id, "level": s.level,
			"total_xp": s.total_xp, "bought_str": s.bought["str"], "bought_agi": s.bought["agi"], "bought_int": s.bought["int"],
			"str": s.attribute("str"), "agi": s.attribute("agi"), "int": s.attribute("int"), "max_hp": s.max_hp(),
			"attack_damage": s.attack_damage(), "attacks_per_s": 1.0 / s.attack_interval(), "crit_chance": s.crit_chance(),
			"armor": s.armor(), "gold_end": _match.gold.balance(hero.peer_id), "gold_earned": earned, "gold_spent": spent,
			"deaths": _deaths_total.get(hero.peer_id, 0)})
	var st := _match.stats()
	_queue("matches", {"match_id": match_id, "schema": TelemetryStore.SCHEMA_VERSION, "game_version": GAME_VERSION,
		"started_at": _started_at, "ended_at": Time.get_datetime_string_from_system(true), "duration_s": now_s(),
		"result": result, "player_count": _match.heroes.size(), "heroes": "+".join(heroes_ids),
		"waves_completed": st.waves_completed, "waves_total": st.waves_total, "core_hp_end": st.core_hp,
		"core_hp_max": st.core_max, "kills_total": st.kills})
	flush()


## Schreibt alle gepufferten Zeilen. Bei Schreibfehlern bleiben sie im Puffer (nächster Versuch beim nächsten Flush).
func flush() -> void:
	if not enabled or store == null:
		_pending.clear()
		return
	for table in _pending.keys():
		if store.write_rows(table, _pending[table]):
			_pending.erase(table)


func _exit_tree() -> void:
	# Szenenwechsel oder Beenden mitten in der Runde
	finish("aborted")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		finish("aborted")


## Auch für Helden, die nach bind() dazukommen (z. B. Koop-Beitritt).
func track_hero(hero: Hero) -> void:
	hero.leveled_up.connect(func(h: Hero, lvl: int) -> void:
		_queue("level_ups", {"match_id": match_id, "time_s": now_s(), "wave": _wave(), "peer_id": h.peer_id, "hero_id": h.hero_id, "level": lvl}))
	hero.died.connect(func(h: Hero) -> void:
		_player(h.peer_id).deaths += 1
		_deaths_total[h.peer_id] = _deaths_total.get(h.peer_id, 0) + 1)


func _on_transaction(e: Dictionary) -> void:
	var hero := _hero_by_peer(e.peer)
	_queue("transactions", {"match_id": match_id, "tx_id": e.id, "time_s": now_s(), "wave": _wave(), "peer_id": e.peer,
		"hero_id": hero.hero_id if hero != null else "", "amount": e.amount, "reason": e.reason, "ref": e.ref, "balance": e.balance})
	var p := _player(e.peer)
	match String(e.reason):
		"kill":
			p.gold_kill += e.amount
			p.kill_participations += 1
		"wave_bonus":
			p.gold_wave += e.amount
		"support":
			p.gold_support += e.amount
		"role_bonus":
			p.gold_role += e.amount
		_:
			if e.amount > 0:
				p.gold_other += e.amount
			else:
				p.gold_spent -= e.amount


func _on_damage(target: Node3D, info: DamageInfo) -> void:
	var source := info.source if info.source_is_valid() else null
	if source is Hero:
		var p := _player((source as Hero).peer_id)
		p.damage_dealt += info.final_amount
		p.hits += 1
		if info.is_crit:
			p.crits += 1
		if info.type == DamageInfo.Type.MAGIC:
			p.damage_magic += info.final_amount
		else:
			p.damage_physical += info.final_amount
	if target is Hero:
		_player((target as Hero).peer_id).damage_taken += info.final_amount
	if source is Enemy:
		var e := _enemy((source as Enemy).enemy_id)
		if target is DefenseCore:
			e.damage_to_core += info.final_amount
		elif target is Hero:
			e.damage_to_heroes += info.final_amount
	if target is Enemy:
		_enemy((target as Enemy).enemy_id).damage_received += info.final_amount


func _on_enemy_spawned(enemy: Enemy) -> void:
	_enemy(enemy.enemy_id).spawned += 1
	_spawn_time[enemy.uid] = now_s()


func _on_enemy_killed(enemy: Enemy, _info: DamageInfo) -> void:
	var e := _enemy(enemy.enemy_id)
	e.killed += 1
	e.lifetime_sum += now_s() - float(_spawn_time.get(enemy.uid, now_s()))
	_spawn_time.erase(enemy.uid)


func _on_xp(peer_id: int, amount: int) -> void:
	_player(peer_id).xp_gained += amount


func _on_wave_completed(number: int) -> void:
	_flush_wave(number, true)


func _flush_wave(number: int, completed: bool) -> void:
	var duration := now_s() - _wave_start_s if _wave_start_s > 0.0 else 0.0
	for hero in _match.heroes:
		if not is_instance_valid(hero):
			continue
		var p := _player(hero.peer_id)
		_queue("wave_players", {"match_id": match_id, "wave": number, "peer_id": hero.peer_id, "hero_id": hero.hero_id,
			"wave_duration_s": duration, "level_start": p.level_start, "level_end": hero.stats.level, "xp_gained": p.xp_gained,
			"gold_kill": p.gold_kill, "gold_wave": p.gold_wave, "gold_other": p.gold_other, "gold_spent": p.gold_spent,
			"gold_end": _match.gold.balance(hero.peer_id), "damage_dealt": p.damage_dealt, "damage_physical": p.damage_physical,
			"damage_magic": p.damage_magic, "crits": p.crits, "hits": p.hits, "damage_taken": p.damage_taken,
			"kill_participations": p.kill_participations, "deaths": p.deaths, "gold_support": p.gold_support,
			"gold_role": p.gold_role, "healing": p.healing, "shield_absorbed": p.shield_absorbed, "damage_prevented": p.damage_prevented,
			"control_points": p.control_points, "tanked": p.tanked, "afk": p.afk, "abilities_cast": _casts_since_last(hero)})
	for id in _enemies:
		var e: Dictionary = _enemies[id]
		if e.spawned == 0 and e.killed == 0:
			continue
		_queue("wave_enemies", {"match_id": match_id, "wave": number, "enemy_id": id, "spawned": e.spawned, "killed": e.killed,
			"avg_lifetime_s": e.lifetime_sum / e.killed if e.killed > 0 else 0.0, "damage_to_core": e.damage_to_core,
			"damage_to_heroes": e.damage_to_heroes, "damage_received": e.damage_received})
	_reset_wave()
	if completed:
		flush()


## Werte, die der RewardService am Wellenende zusammenfasst (Heilung, Schilde, Kontrolle …).
func _on_wave_rewards(peer_id: int, _wave_number: int, s: Dictionary) -> void:
	var p := _player(peer_id)
	p.healing = s.heal
	p.shield_absorbed = s.shield
	p.damage_prevented = s.prevented
	p.control_points = s.control
	p.tanked = s.tank
	p.afk = not s.active


## Gewirkte Fähigkeiten seit der letzten Wellenzeile; schreibt dabei die Tabelle wave_abilities.
func _casts_since_last(hero: Hero) -> int:
	var total := 0
	var last: Dictionary = _cast_snapshot.get(hero.peer_id, {})
	for id in hero.abilities.cast_counts:
		var n: int = hero.abilities.cast_counts[id] - int(last.get(id, 0))
		if n > 0:
			total += n
			_queue("wave_abilities", {"match_id": match_id, "wave": _wave(), "peer_id": hero.peer_id, "hero_id": hero.hero_id,
				"ability_id": id, "level": hero.abilities.level_of(id), "casts": n})
	_cast_snapshot[hero.peer_id] = hero.abilities.cast_counts.duplicate()
	return total


func _reset_wave() -> void:
	_players.clear()
	_enemies.clear()
	_wave_start_s = 0.0
	for hero in _match.heroes:
		if is_instance_valid(hero):
			_player(hero.peer_id).level_start = hero.stats.level


func _player(peer_id: int) -> Dictionary:
	if not _players.has(peer_id):
		var hero := _hero_by_peer(peer_id)
		_players[peer_id] = {"level_start": hero.stats.level if hero != null else 1, "xp_gained": 0, "gold_kill": 0,
			"gold_wave": 0, "gold_other": 0, "gold_spent": 0, "gold_support": 0, "gold_role": 0, "healing": 0.0,
			"shield_absorbed": 0.0, "damage_prevented": 0.0, "control_points": 0.0, "tanked": 0.0, "afk": false, "damage_dealt": 0.0, "damage_physical": 0.0,
			"damage_magic": 0.0, "crits": 0, "hits": 0, "damage_taken": 0.0, "kill_participations": 0, "deaths": 0}
	return _players[peer_id]


func _enemy(enemy_id: String) -> Dictionary:
	if not _enemies.has(enemy_id):
		_enemies[enemy_id] = {"spawned": 0, "killed": 0, "lifetime_sum": 0.0, "damage_to_core": 0.0,
			"damage_to_heroes": 0.0, "damage_received": 0.0}
	return _enemies[enemy_id]


func _hero_by_peer(peer_id: int) -> Hero:
	for hero in _match.heroes:
		if is_instance_valid(hero) and hero.peer_id == peer_id:
			return hero
	return null


func _wave() -> int:
	return _match.wave_manager.current_wave_number() if _match != null else 0


func _queue(table: String, row: Dictionary) -> void:
	if not _pending.has(table):
		_pending[table] = []
	_pending[table].append(row)
